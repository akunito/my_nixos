#!/usr/bin/env python3
# capture-hub: frames in (UVC capture card / Wayland screen / pushed files) -> change-filtered
# JPEGs + OCR text + optional VLM notes, stored per PROFILE (one directory per project) and
# served over a small HTTP API for whatever AI consumes them (Claude, Hermes, game-assist).
# One file on purpose: it is shipped by the nix module as a single script (system/app/capture-hub.nix).
#
# Hot path = one frame every 1/fps s: decode with Pillow draft mode (JPEG DCT downscale, no
# full decode), 8x8 dHash, Hamming distance against the last KEPT frame. Everything else
# (disk, OCR, VLM, HTTP) runs on worker threads fed by bounded queues that drop the OLDEST
# item, so a slow tesseract/VLM never backs up the capture.
import base64
import glob
import io
import json
import os
import queue
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen

from PIL import Image
import imagehash

FFMPEG = os.environ.get("CAPTURE_HUB_FFMPEG", "ffmpeg")
TESSERACT = os.environ.get("CAPTURE_HUB_TESSERACT", "tesseract")
GRIM = os.environ.get("CAPTURE_HUB_GRIM", "grim")

PROFILE_DEFAULTS = {
    "source": None,          # None = first configured source
    "sink": None,            # None = <data_dir>/profiles/<name>
    "fps": 1.0,
    "max_side": 1920,        # stored frames are downscaled to this (0 = keep)
    "hash_threshold": 6,     # Hamming distance (0-64) below which a frame is "unchanged"
    "keyframe_s": 60,        # keep one frame at least this often even if unchanged
    "ocr": "sparse",         # sparse (UI/games, psm 11) | document (psm 3) | off
    "ocr_min_interval_s": 0,
    "vlm": "off",            # off | change (every kept frame, rate-limited) | demand (/ask only)
    "vlm_min_interval_s": 20,
    "vlm_prompt": "Describe briefly what is on screen. Answer in Spanish.",
    "vlm_max_tokens": 400,
    "keep_days": 7,
}


def now_ms():
    return int(time.time() * 1000)


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


class DropOldestQueue(queue.Queue):
    def put_drop(self, item):
        while True:
            try:
                super().put_nowait(item)
                return
            except queue.Full:
                try:
                    self.get_nowait()
                except queue.Empty:
                    pass


# ----------------------------------------------------------------------------- sources
class Source:
    """Yields (w_ms, jpeg_bytes). Blocks; returns None when the device is gone (caller retries)."""

    def __init__(self, spec):
        self.spec = spec
        self.name = spec["name"]
        self.kind = spec["kind"]
        self.stop = threading.Event()

    def frames(self, fps):
        raise NotImplementedError

    def close(self):
        self.stop.set()


class V4L2Source(Source):
    # ffmpeg decodes the device stream and re-emits MJPEG at the wanted fps on stdout; frames
    # are split on JPEG SOI/EOI markers. `input_format` (mjpeg on webcams/most cards) is tried
    # first and dropped on failure, because UVC devices advertise different pixel formats.
    def __init__(self, spec):
        super().__init__(spec)
        self.proc = None

    def device(self):
        hits = sorted(glob.glob(self.spec["device"]))
        return hits[0] if hits else None

    def frames(self, fps):
        dev = self.device()
        if not dev:
            return
        attempts = [self.spec.get("input_format"), None] if self.spec.get("input_format") else [None]
        for fmt in attempts:
            cmd = [FFMPEG, "-nostdin", "-hide_banner", "-loglevel", "error", "-f", "v4l2"]
            if fmt:
                cmd += ["-input_format", fmt]
            if self.spec.get("framerate"):
                cmd += ["-framerate", str(self.spec["framerate"])]
            if self.spec.get("size"):
                cmd += ["-video_size", self.spec["size"]]
            cmd += ["-i", dev, "-vf", f"fps={fps}", "-c:v", "mjpeg", "-q:v", "4", "-f", "image2pipe", "-"]
            log(f"source {self.name}: {' '.join(cmd)}")
            # stderr -> temp file: a never-drained stderr pipe would block ffmpeg once v4l2 warnings fill it.
            # os.read returns what is available; BufferedReader.read(n) would wait for the full n bytes
            # and hold a whole frame back at low fps.
            errf = tempfile.TemporaryFile()
            self.proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=errf)
            got_any = False
            buf = bytearray()
            fd = self.proc.stdout.fileno()
            # Stall watchdog: the C920 behind a hub chain delivered 2 frames and then nothing, with ffmpeg
            # parked in DQBUF forever (measured 2026-10-15). No bytes for stall_s -> kill and reopen.
            stall_s = max(5.0, 3.0 / fps)
            while not self.stop.is_set():
                if not select.select([fd], [], [], stall_s)[0]:
                    log(f"source {self.name}: no frames for {stall_s:.0f}s, restarting ffmpeg")
                    break
                chunk = os.read(fd, 1 << 20)
                if not chunk:
                    break
                buf += chunk
                while True:
                    soi = buf.find(b"\xff\xd8")
                    if soi < 0:
                        buf.clear()
                        break
                    eoi = buf.find(b"\xff\xd9", soi + 2)
                    if eoi < 0:
                        if soi:
                            del buf[:soi]
                        break
                    got_any = True
                    yield now_ms(), bytes(buf[soi:eoi + 2])
                    del buf[:eoi + 2]
            self._reap()
            errf.seek(0)
            err = errf.read().decode(errors="replace").strip()
            errf.close()
            self.proc = None
            if self.stop.is_set() or got_any:
                return
            log(f"source {self.name}: ffmpeg failed ({err[:200]})")
        return

    def _reap(self):
        # ffmpeg stuck in the v4l2 driver ignores SIGTERM (measured with the C920 after an unclean
        # stop): escalate to SIGKILL, otherwise the device stays "busy" for the next open.
        p = self.proc
        if not p:
            return
        p.terminate()
        try:
            p.wait(timeout=2)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()

    def close(self):
        super().close()
        self._reap()


class ScreenSource(Source):
    # Wayland screen via grim (needs WAYLAND_DISPLAY -> the user-service variant). grim at 4K
    # takes tens of ms, so fps > 2 is not meaningful here; use the capture card for that.
    def frames(self, fps):
        if not os.environ.get("WAYLAND_DISPLAY"):
            return
        period = 1.0 / fps
        cmd = [GRIM, "-t", "jpeg", "-q", "85"]
        if self.spec.get("output"):
            cmd += ["-o", self.spec["output"]]
        if self.spec.get("scale"):
            cmd += ["-s", str(self.spec["scale"])]
        cmd.append("-")
        while not self.stop.is_set():
            t0 = time.monotonic()
            r = subprocess.run(cmd, capture_output=True)
            if r.returncode != 0:
                log(f"source {self.name}: grim failed: {r.stderr.decode(errors='replace')[:200]}")
                return
            yield now_ms(), r.stdout
            self.stop.wait(max(0.0, period - (time.monotonic() - t0)))


class InboxSource(Source):
    # Frames pushed by another machine (POST /inbox) or dropped into <data_dir>/inbox/*.jpg.
    def __init__(self, spec, q):
        super().__init__(spec)
        self.q = q

    def frames(self, fps):
        while not self.stop.is_set():
            try:
                yield self.q.get(timeout=1.0)
            except queue.Empty:
                continue


# ----------------------------------------------------------------------------- hub
class Hub:
    def __init__(self, cfg):
        self.cfg = cfg
        self.data_dir = cfg["data_dir"]
        self.inbox_dir = os.path.join(self.data_dir, "inbox")
        os.makedirs(self.inbox_dir, exist_ok=True)
        self.lock = threading.Lock()
        self.inbox_q = DropOldestQueue(maxsize=8)
        self.ocr_q = DropOldestQueue(maxsize=4)
        self.vlm_q = DropOldestQueue(maxsize=1)
        self.paused = False
        self.stop = threading.Event()
        self.source = None
        self.session = None
        self.profile_name = None
        self.profile = None
        self.last_hash = None
        self.last_kept_ms = 0
        self.last_ocr_ms = 0
        self.last_vlm_ms = 0
        self.last_text = ""
        self.stats = {"frames_in": 0, "frames_kept": 0, "ocr": 0, "vlm": 0, "started": now_ms(), "source_state": "idle"}
        state = self._read_json(os.path.join(self.data_dir, "state.json")) or {}
        self.set_profile(state.get("profile") or cfg.get("profile") or next(iter(cfg["profiles"])),
                         state.get("source"))

    # -- config helpers
    def _read_json(self, p):
        try:
            with open(p) as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def _save_state(self):
        tmp = os.path.join(self.data_dir, "state.json.tmp")
        with open(tmp, "w") as f:
            json.dump({"profile": self.profile_name, "source": self.source_name}, f)
        os.replace(tmp, os.path.join(self.data_dir, "state.json"))

    def profile_dir(self, name=None):
        name = name or self.profile_name
        sink = self.cfg["profiles"][name].get("sink")
        return sink or os.path.join(self.data_dir, "profiles", name)

    # -- profile / source switching (one source active at a time)
    def set_profile(self, name, source=None):
        if name not in self.cfg["profiles"]:
            raise KeyError(name)
        with self.lock:
            self.profile_name = name
            self.profile = {**PROFILE_DEFAULTS, **self.cfg["profiles"][name]}
            self.source_name = source or self.profile["source"] or self.cfg["sources"][0]["name"]
            self._open_session()
            self.last_hash = None
            self.last_text = ""
            self._save_state()
            self._restart_source()
        log(f"profile={name} source={self.source_name} sink={self.profile_dir()}")

    def _open_session(self):
        base = self.profile_dir()
        sid = time.strftime("%Y%m%d-%H%M%S")
        d = os.path.join(base, "sessions", sid)
        os.makedirs(os.path.join(d, "frames"), exist_ok=True)
        self.session = {"id": sid, "dir": d, "base": base}
        with open(os.path.join(d, "meta.json"), "w") as f:
            json.dump({"profile": self.profile_name, "source": self.source_name, "started_ms": now_ms(),
                       "host": os.uname().nodename, "settings": self.profile}, f, indent=1)
        with open(os.path.join(base, "current_session"), "w") as f:
            f.write(sid)

    def _make_source(self, name):
        spec = next((s for s in self.cfg["sources"] if s["name"] == name), None)
        if not spec:
            raise KeyError(name)
        if spec["kind"] == "v4l2":
            return V4L2Source(spec)
        if spec["kind"] == "screen":
            return ScreenSource(spec)
        if spec["kind"] == "inbox":
            return InboxSource(spec, self.inbox_q)
        raise ValueError(spec["kind"])

    def _restart_source(self):
        if self.source:
            self.source.close()
        self.source = self._make_source(self.source_name)
        self._source_gen = 0

    # -- main capture loop (own thread)
    def capture_loop(self):
        while not self.stop.is_set():
            src = self.source
            fps = float(self.profile["fps"])
            got = False
            try:
                for w, jpeg in src.frames(fps):
                    got = True
                    if src is not self.source:
                        break
                    self.stats["source_state"] = "live"
                    if not self.paused:
                        self._on_frame(w, jpeg)
            except Exception as e:  # keep the daemon alive, log, retry
                log(f"capture error: {e!r}")
            finally:
                src.close()  # never leave an ffmpeg holding the device (the next open would be "busy")
            if src is not self.source:
                continue
            with self.lock:
                if src is self.source:
                    self.source = self._make_source(self.source_name)
            self.stats["source_state"] = "waiting-device" if not got else "restarting"
            self.stop.wait(10.0 if not got else 1.0)

    def _on_frame(self, w, jpeg):
        self.stats["frames_in"] += 1
        p = self.profile
        im = Image.open(io.BytesIO(jpeg))
        im.draft("L", (160, 160))  # DCT-domain downscale: ~10x cheaper than a full decode
        h = imagehash.dhash(im.convert("L"), hash_size=8)
        dist = 64 if self.last_hash is None else int(h - self.last_hash)  # numpy int64 -> int (json)
        keyframe = (w - self.last_kept_ms) >= p["keyframe_s"] * 1000
        if dist < p["hash_threshold"] and not keyframe:
            return
        self.last_hash = h
        self.last_kept_ms = w
        self.stats["frames_kept"] += 1
        rel = os.path.join("frames", time.strftime("%Y%m%d", time.localtime(w / 1000)), f"{w}.jpg")
        path = os.path.join(self.session["dir"], rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        full = Image.open(io.BytesIO(jpeg))
        ms = int(p["max_side"] or 0)
        if ms and max(full.size) > ms:
            full.draft("RGB", (ms, ms))
            full = full.convert("RGB")
            full.thumbnail((ms, ms), Image.Resampling.LANCZOS)
            full.save(path, "JPEG", quality=85, optimize=True)
        else:
            with open(path, "wb") as f:
                f.write(jpeg)
        ev = {"w": w, "src": self.source_name, "file": rel, "hash": str(h), "dist": dist, "keyframe": keyframe}
        self._append(os.path.join(self.session["dir"], "events.jsonl"), ev)
        self._latest("latest.jpg", path)
        if p["ocr"] != "off" and (w - self.last_ocr_ms) >= p["ocr_min_interval_s"] * 1000:
            self.last_ocr_ms = w
            self.ocr_q.put_drop((w, path, rel, self.session))
        if p["vlm"] == "change" and (w - self.last_vlm_ms) >= p["vlm_min_interval_s"] * 1000:
            self.last_vlm_ms = w
            self.vlm_q.put_drop((w, path, rel, self.session, p["vlm_prompt"], None))

    def _append(self, path, obj):
        with open(path, "a") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")

    def _latest(self, name, target):
        link = os.path.join(self.session["base"], name)
        tmp = link + ".tmp"
        try:
            os.symlink(target, tmp)
            os.replace(tmp, link)
        except OSError:
            shutil.copyfile(target, link)

    # -- OCR worker
    def ocr_loop(self):
        while not self.stop.is_set():
            try:
                w, path, rel, session = self.ocr_q.get(timeout=1.0)
            except queue.Empty:
                continue
            psm = "11" if self.profile["ocr"] == "sparse" else "3"
            try:
                r = subprocess.run([TESSERACT, path, "-", "-l", self.cfg["ocr"]["langs"], "--psm", psm],
                                   capture_output=True, timeout=60)
            except subprocess.TimeoutExpired:
                log("ocr timeout")
                continue
            text = r.stdout.decode(errors="replace").strip()
            if r.returncode != 0:
                log(f"ocr failed: {r.stderr.decode(errors='replace')[:200]}")
                continue
            self.stats["ocr"] += 1
            if not text or text == self.last_text:
                continue
            self.last_text = text
            with open(path[:-4] + ".txt", "w") as f:
                f.write(text)
            self._append(os.path.join(session["dir"], "text.jsonl"), {"w": w, "file": rel, "text": text})
            with open(os.path.join(session["base"], "latest.txt.tmp"), "w") as f:
                f.write(text)
            os.replace(os.path.join(session["base"], "latest.txt.tmp"), os.path.join(session["base"], "latest.txt"))

    # -- VLM worker (OpenAI chat completions with an image; the NAS llama-server router loads `model`)
    def vlm_ask(self, path, prompt, max_tokens=None):
        v = self.cfg["vlm"]
        im = Image.open(path)
        side = int(v.get("max_side", 1280))
        im.draft("RGB", (side, side))
        im = im.convert("RGB")
        im.thumbnail((side, side))
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=80)
        b64 = base64.b64encode(buf.getvalue()).decode()
        # enable_thinking=false: the reasoner presets think first (--reasoning-budget 16384) and the whole
        # max_tokens went into reasoning_content with an empty content (measured 2026-10-15).
        body = {"model": v["model"], "max_tokens": max_tokens or self.profile["vlm_max_tokens"], "temperature": 0.2,
                "chat_template_kwargs": {"enable_thinking": False},
                "messages": [{"role": "user", "content": [
                    {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + b64}},
                    {"type": "text", "text": prompt}]}]}
        req = Request(v["url"].rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                      headers={"Content-Type": "application/json"})
        t0 = time.monotonic()
        with urlopen(req, timeout=float(v.get("timeout", 180))) as resp:
            out = json.load(resp)
        msg = out["choices"][0]["message"]
        text = (msg.get("content") or msg.get("reasoning_content") or "").strip()
        self.stats["vlm"] += 1
        return text, round(time.monotonic() - t0, 2)

    def vlm_loop(self):
        while not self.stop.is_set():
            try:
                w, path, rel, session, prompt, reply = self.vlm_q.get(timeout=1.0)
            except queue.Empty:
                continue
            try:
                text, secs = self.vlm_ask(path, prompt)
            except Exception as e:
                log(f"vlm failed: {e!r}")
                if reply:
                    reply.put({"error": repr(e)})
                continue
            note = {"w": w, "file": rel, "prompt": prompt, "text": text, "secs": secs, "model": self.cfg["vlm"]["model"]}
            self._append(os.path.join(session["dir"], "notes.jsonl"), note)
            with open(os.path.join(session["base"], "latest.note.json"), "w") as f:
                json.dump(note, f, ensure_ascii=False)
            if reply:
                reply.put(note)

    def ask(self, question, frame=None):
        # Synchronous: latest kept frame (or a given path) + question -> VLM answer, logged as a note.
        path = frame or os.path.realpath(os.path.join(self.session["base"], "latest.jpg"))
        if not os.path.exists(path):
            return {"error": "no frame yet"}
        rel = os.path.relpath(path, self.session["dir"]) if path.startswith(self.session["dir"]) else path
        reply = queue.Queue(maxsize=1)
        self.vlm_q.put_drop((now_ms(), path, rel, self.session, question, reply))
        return reply.get(timeout=float(self.cfg["vlm"].get("timeout", 180)) + 5)

    # -- retention (once per hour; frames older than keep_days per profile)
    def retention_loop(self):
        while not self.stop.wait(3600):
            for name, p in self.cfg["profiles"].items():
                days = {**PROFILE_DEFAULTS, **p}["keep_days"]
                if not days:
                    continue
                cutoff = time.time() - days * 86400
                root = os.path.join(self.profile_dir(name), "sessions")
                for dirpath, _, files in os.walk(root):
                    for fn in files:
                        if fn.endswith((".jpg", ".txt")):
                            fp = os.path.join(dirpath, fn)
                            try:
                                if os.path.getmtime(fp) < cutoff:
                                    os.remove(fp)
                            except OSError:
                                pass

    def inbox_watch_loop(self):
        # Files dropped into <data_dir>/inbox (scp from another box) are consumed as frames.
        while not self.stop.wait(2.0):
            for fp in sorted(glob.glob(os.path.join(self.inbox_dir, "*.jpg"))):
                try:
                    with open(fp, "rb") as f:
                        data = f.read()
                    os.remove(fp)
                except OSError:
                    continue
                self.inbox_q.put_drop((now_ms(), data))

    def status(self):
        return {"profile": self.profile_name, "source": self.source_name, "paused": self.paused,
                "session": self.session["id"], "sink": self.session["base"], "stats": self.stats,
                "profiles": sorted(self.cfg["profiles"]), "sources": [s["name"] for s in self.cfg["sources"]],
                "vlm": {"url": self.cfg["vlm"]["url"], "model": self.cfg["vlm"]["model"]}}

    def tail(self, fname, since_ms, limit):
        out = []
        p = os.path.join(self.session["dir"], fname)
        try:
            with open(p) as f:
                for line in f:
                    try:
                        o = json.loads(line)
                    except ValueError:
                        continue
                    if o.get("w", 0) > since_ms:
                        out.append(o)
        except OSError:
            pass
        return out[-limit:]


# ----------------------------------------------------------------------------- http api
def make_handler(hub):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _json(self, obj, code=200):
            data = json.dumps(obj, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _file(self, path, ctype):
            try:
                with open(path, "rb") as f:
                    data = f.read()
            except OSError:
                return self._json({"error": "not found"}, 404)
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            u = urlparse(self.path)
            q = parse_qs(u.query)
            since = int(q.get("since", ["0"])[0])
            limit = int(q.get("limit", ["50"])[0])
            base = hub.session["base"]
            if u.path == "/status":
                return self._json(hub.status())
            if u.path == "/latest.jpg":
                return self._file(os.path.join(base, "latest.jpg"), "image/jpeg")
            if u.path == "/latest.txt":
                return self._file(os.path.join(base, "latest.txt"), "text/plain; charset=utf-8")
            if u.path == "/latest.note":
                return self._file(os.path.join(base, "latest.note.json"), "application/json")
            if u.path == "/frames":
                return self._json(hub.tail("events.jsonl", since, limit))
            if u.path == "/text":
                return self._json(hub.tail("text.jsonl", since, limit))
            if u.path == "/notes":
                return self._json(hub.tail("notes.jsonl", since, limit))
            if u.path.startswith("/frame/"):
                rel = os.path.normpath(u.path[len("/frame/"):])
                if rel.startswith(".."):
                    return self._json({"error": "bad path"}, 400)
                return self._file(os.path.join(hub.session["dir"], rel), "image/jpeg")
            return self._json({"error": "unknown"}, 404)

        def do_POST(self):
            u = urlparse(self.path)
            q = parse_qs(u.query)
            n = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(n) if n else b""
            try:
                if u.path == "/profile":
                    hub.set_profile(q["name"][0], q.get("source", [None])[0])
                    return self._json(hub.status())
                if u.path == "/source":
                    hub.set_profile(hub.profile_name, q["name"][0])
                    return self._json(hub.status())
                if u.path == "/pause":
                    hub.paused = True
                    return self._json(hub.status())
                if u.path == "/resume":
                    hub.paused = False
                    return self._json(hub.status())
                if u.path == "/ask":
                    o = json.loads(body or b"{}")
                    return self._json(hub.ask(o.get("question") or hub.profile["vlm_prompt"], o.get("frame")))
                if u.path == "/inbox":
                    if not body.startswith(b"\xff\xd8"):
                        return self._json({"error": "jpeg body expected"}, 400)
                    hub.inbox_q.put_drop((now_ms(), body))
                    return self._json({"ok": True, "bytes": len(body)})
            except KeyError as e:
                return self._json({"error": f"unknown {e}"}, 400)
            except Exception as e:
                return self._json({"error": repr(e)}, 500)
            return self._json({"error": "unknown"}, 404)

    return H


def serve(cfg):
    hub = Hub(cfg)
    for fn in (hub.capture_loop, hub.ocr_loop, hub.vlm_loop, hub.retention_loop, hub.inbox_watch_loop):
        threading.Thread(target=fn, name=fn.__name__, daemon=True).start()
    host, port = cfg["listen"].rsplit(":", 1)
    srv = ThreadingHTTPServer((host, int(port)), make_handler(hub))

    def _stop(*_):
        hub.stop.set()
        if hub.source:
            hub.source.close()
        threading.Thread(target=srv.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    log(f"capture-hub listening on {cfg['listen']} data={cfg['data_dir']}")
    srv.serve_forever()


# ----------------------------------------------------------------------------- cli
def cli(cfg, argv):
    url = os.environ.get("CAPTURE_HUB_URL") or ("http://" + cfg["listen"])

    def call(method, path, data=None, raw=False):
        req = Request(url + path, data=data, method=method)
        if data is not None and not raw:
            req.add_header("Content-Type", "application/json")
        with urlopen(req, timeout=300) as r:
            out = r.read()
        return out if raw else json.loads(out)

    cmd = argv[0] if argv else "status"
    args = argv[1:]
    if cmd == "status":
        print(json.dumps(call("GET", "/status"), indent=1, ensure_ascii=False))
    elif cmd == "profile":
        extra = f"&source={args[1]}" if len(args) > 1 else ""
        print(json.dumps(call("POST", f"/profile?name={args[0]}{extra}"), indent=1, ensure_ascii=False))
    elif cmd == "source":
        print(json.dumps(call("POST", f"/source?name={args[0]}"), indent=1, ensure_ascii=False))
    elif cmd in ("pause", "resume"):
        print(json.dumps(call("POST", "/" + cmd)["paused"]))
    elif cmd == "ask":
        o = call("POST", "/ask", json.dumps({"question": " ".join(args)}).encode())
        print(o.get("text") or json.dumps(o, ensure_ascii=False))
    elif cmd == "latest":
        sys.stdout.write(call("GET", "/latest.txt", raw=True).decode(errors="replace"))
    elif cmd == "text":
        since = int(args[0]) if args else 0
        for o in call("GET", f"/text?since={since}"):
            print(f"--- {o['w']} {o['file']}\n{o['text']}")
    elif cmd == "notes":
        for o in call("GET", "/notes"):
            print(f"--- {o['w']} {o['file']} ({o['secs']}s)\n{o['text']}")
    elif cmd == "push":
        with open(args[0], "rb") as f:
            print(json.dumps(call("POST", "/inbox", f.read(), raw=True)))
    else:
        print("usage: capture-hub [daemon|status|profile NAME [SOURCE]|source NAME|pause|resume|ask QUESTION|latest|text [SINCE_MS]|notes|push FILE.jpg]")
        return 2
    return 0


def main():
    cfg_path = os.environ.get("CAPTURE_HUB_CONFIG", "/etc/capture-hub/config.json")
    with open(cfg_path) as f:
        cfg = json.load(f)
    cfg["data_dir"] = os.path.expanduser(os.path.expandvars(cfg["data_dir"]))
    for p in cfg["profiles"].values():
        if p.get("sink"):
            p["sink"] = os.path.expanduser(os.path.expandvars(p["sink"]))
    if len(sys.argv) > 1 and sys.argv[1] == "daemon":
        os.makedirs(cfg["data_dir"], exist_ok=True)
        serve(cfg)
        return 0
    return cli(cfg, sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())
