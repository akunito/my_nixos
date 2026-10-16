"""Switch gate in front of the llama-server router (router mode only).

The router (--models-max 1) loads whatever model a request names and unloads
the resident one once ITS in-flight requests finish (measured 2026-10-14: a
600-token generation completed, then the other model loaded). So nothing is
cut mid-answer, but between two turns of a claude-nas session any other client
naming another preset took the card away. Diego: no switch without an explicit
request, queue the rest:

  request for the loaded model, or nothing loaded   -> forward
  claude-nas (header X-Nas-No-Switch) naming another -> rejected at once: switch
                                                        it by hand (Waybar widget)
  any other client naming another model             -> waits while the loaded one
                                                        is busy or was used in the
                                                        last GRACE seconds, then
                                                        forwarded (the router switches)
  POST /models/load|unload (widget, `ai preset set`) -> explicit: forwarded at once,
                                                        after cutting every in-flight
                                                        request (the router would wait
                                                        for them: 2026-10-14 a session
                                                        Diego had exited kept 3 running)
  POST /gate/abort [{"model": id}]                   -> cuts in-flight requests, keeps
                                                        the model (`claude-nas stop`)

A client that goes away (Esc, Ctrl-C, killed session) is noticed at once: the
client socket is watched while the backend answers, and the backend connection
is dropped so llama-server stops generating (before, a dead client was only
seen on the next write, i.e. after a prefill of minutes at 400k tokens).

Replaces systemd-socket-proxyd: inherits the listening socket (LISTEN_FDS) from
llama-proxy.socket; one backend connection per request (Connection: close), the
response streamed through untouched (SSE included). GET /gate/status = state.
"""
from __future__ import annotations

import asyncio
import json
import os
import socket
import sys
import time
from urllib.parse import parse_qs, urlsplit

BACKEND_HOST = "127.0.0.1"
BACKEND_PORT = int(os.environ.get("GATE_BACKEND_PORT", "8091"))
GRACE = float(os.environ.get("GATE_GRACE_SECONDS", "300"))
MAX_WAIT = float(os.environ.get("GATE_MAX_WAIT_SECONDS", "1800"))
NO_SWITCH_HEADER = "x-nas-no-switch"
EXPLICIT_PATHS = ("/models/load", "/models/unload")
# Names clients used before router mode. A claude-nas session started before the
# switch kept sending this one and sat in the queue as "another model" (2026-10-14);
# it is served by whichever preset with that prefix is loaded, never switched.
# (prefix of the presets that may serve it, preset to load when nothing is loaded)
LEGACY_ALIASES = {"qwen3.8-27b-abliterated": ("reasoner-", "reasoner-256k")}
# preset -> {"file", "ctx"} (llama-server.nix, from aiPresets). A no-switch client (claude-nas) naming a
# preset that serves the SAME GGUF as the loaded one, with no more context than it has, is served by the
# loaded one: a session started on reasoner-256k got HTTP 400 once reasoner-256k-cache-mtp (same file,
# other serving flags) was loaded (2026-10-16).
SAME_MODEL = json.loads(os.environ.get("GATE_SAME_MODEL", "{}") or "{}")


def equivalent(model: str, loaded: str | None) -> bool:
    a, b = SAME_MODEL.get(model), SAME_MODEL.get(loaded or "")
    return bool(a and b and a["file"] == b["file"] and b["ctx"] >= a["ctx"])


def decide(model: str | None, loaded: str | None, inflight: dict[str, int], last_used: dict[str, float],
           now: float, grace: float, no_switch: bool) -> str:
    """forward | reject | wait"""
    if not model or loaded is None or model == loaded:
        return "forward"
    if no_switch:
        return "reject"
    busy = inflight.get(loaded, 0) > 0 or now - last_used.get(loaded, float("-inf")) < grace
    return "wait" if busy else "forward"


def request_model(method: str, target: str, headers: dict[str, str], body: bytes) -> str | None:
    q = parse_qs(urlsplit(target).query).get("model")
    if q:
        return q[0]
    if method == "POST" and body and "json" in headers.get("content-type", "application/json"):
        try:
            m = json.loads(body).get("model")
            return m if isinstance(m, str) else None
        except (ValueError, AttributeError):
            return None
    return None


def reject_body(path: str, loaded: str, model: str) -> tuple[int, bytes]:
    msg = (f"The NAS 3090 has '{loaded}' loaded and switching to '{model}' must be done by hand: "
           f"use the Waybar NAS widget (or `ai preset set {model}` on the NAS), then retry.")
    if path.startswith("/v1/messages"):  # Anthropic shape: Claude Code shows error.message
        return 400, json.dumps({"type": "error", "error": {"type": "invalid_request_error", "message": msg}}).encode()
    return 409, json.dumps({"error": {"code": 409, "type": "model_busy", "message": msg}}).encode()


def unknown_body(path: str, model: str, known: list[str]) -> tuple[int, bytes]:
    msg = f"'{model}' is not a NAS preset. Known: {', '.join(known)}. (An old session? Restart it.)"
    if path.startswith("/v1/messages"):
        return 400, json.dumps({"type": "error", "error": {"type": "invalid_request_error", "message": msg}}).encode()
    return 400, json.dumps({"error": {"code": 400, "type": "unknown_model", "message": msg}}).encode()


class Gate:
    def __init__(self) -> None:
        self.loaded: str | None = None
        self.loaded_at = 0.0          # when `loaded` was last confirmed from GET /models
        self.known: set[str] = set()  # preset ids the router serves
        self.inflight: dict[str, int] = {}
        self.last_used: dict[str, float] = {}
        self.queue: list[tuple[str, float]] = []
        self.changed = asyncio.Condition()
        self.forwards: dict[int, tuple[str | None, asyncio.StreamWriter]] = {}  # id -> (model, backend writer)

    # ---- backend -------------------------------------------------------------------
    async def refresh_loaded(self, force: bool = False) -> None:
        if not force and time.monotonic() - self.loaded_at < 2:
            return
        try:
            r, w = await asyncio.open_connection(BACKEND_HOST, BACKEND_PORT)
            w.write(b"GET /models HTTP/1.1\r\nHost: gate\r\nConnection: close\r\n\r\n")
            await w.drain()
            raw = await asyncio.wait_for(r.read(), 5)
            w.close()
            data = json.loads(raw.split(b"\r\n\r\n", 1)[1] or b"{}")
            self.known = {m["id"] for m in data.get("data") or [] if m.get("id")}
            hot = [m["id"] for m in data.get("data") or [] if (m.get("status") or {}).get("value") in ("loaded", "loading")]
            self.loaded = hot[0] if hot else None
            self.loaded_at = time.monotonic()
        except (OSError, ValueError, IndexError, asyncio.TimeoutError):
            pass

    def abort(self, model: str | None = None) -> int:
        """Drop the backend connection of every in-flight request (for `model`, or all).
        llama-server aborts a generation whose client is gone; the client side sees EOF."""
        n = 0
        for key, (m, bw) in list(self.forwards.items()):
            if model and m != model:
                continue
            try:
                bw.transport.abort()
            except Exception:
                pass
            self.forwards.pop(key, None)
            n += 1
        return n

    async def _watch_client(self, reader: asyncio.StreamReader, bw: asyncio.StreamWriter) -> None:
        # The request is fully read: any further read returns only on EOF (client gone).
        try:
            await reader.read(1)
        except Exception:
            pass
        try:
            bw.transport.abort()
        except Exception:
            pass

    # ---- one client connection ---------------------------------------------------------
    async def handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 60)
        except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, asyncio.TimeoutError, ConnectionError):
            writer.close()
            return
        lines = head.decode("latin-1").split("\r\n")
        try:
            method, target, _ver = lines[0].split(" ", 2)
        except ValueError:
            writer.close()
            return
        headers: dict[str, str] = {}
        raw_headers: list[str] = []
        for ln in lines[1:]:
            if not ln:
                continue
            k, _, v = ln.partition(":")
            headers[k.strip().lower()] = v.strip()
            raw_headers.append(ln)
        body = await self._read_body(reader, headers)
        path = urlsplit(target).path
        if path == "/gate/status":
            await self.refresh_loaded(force=self.loaded_at == 0)   # fresh after an unload
            await self._respond(writer, 200, json.dumps(self.status()).encode())
            return
        if path == "/gate/abort":
            if method != "POST":
                await self._respond(writer, 400, b'{"error":{"code":400,"message":"POST only"}}')
                return
            n = self.abort(request_model(method, target, headers, body))
            self.loaded_at = 0
            await self._respond(writer, 200, json.dumps({"aborted": n}).encode())
            return
        model = request_model(method, target, headers, body)
        explicit = path in EXPLICIT_PATHS
        if model and not explicit:
            await self.refresh_loaded(force=not self.known)
            if self.known and model not in self.known:
                alias = LEGACY_ALIASES.get(model)
                serve_as = None   # NOT `target`: that name holds the request path in this method
                if alias and self.loaded and self.loaded.startswith(alias[0]):
                    serve_as = self.loaded
                elif alias and self.loaded is None and alias[1] in self.known:
                    serve_as = alias[1]
                if serve_as:
                    body = body.replace(json.dumps(model).encode(), json.dumps(serve_as).encode(), 1)
                    model = serve_as
                else:
                    await self._respond(writer, *unknown_body(path, model, sorted(self.known)))
                    return
            if (model != self.loaded and headers.get(NO_SWITCH_HEADER, "") not in ("", "0", "false")
                    and equivalent(model, self.loaded)):
                body = body.replace(json.dumps(model).encode(), json.dumps(self.loaded).encode(), 1)
                model = self.loaded
            verdict = await self._admit(model, path, headers, reader)
            if verdict == "gone":
                writer.close()
                return
            if verdict is not None:
                await self._respond(writer, *verdict)
                return
        await self._forward(method, target, raw_headers, body, writer, model, explicit, path, reader)

    async def _read_body(self, reader: asyncio.StreamReader, headers: dict[str, str]) -> bytes:
        if "content-length" in headers:
            return await reader.readexactly(int(headers["content-length"]))
        if "chunked" in headers.get("transfer-encoding", ""):
            out = bytearray()
            while True:
                size = int((await reader.readline()).split(b";")[0].strip() or b"0", 16)
                if size == 0:
                    await reader.readline()
                    return bytes(out)
                out += await reader.readexactly(size)
                await reader.readline()
        return b""

    async def _admit(self, model: str, path: str, headers: dict[str, str],
                     reader: asyncio.StreamReader | None = None) -> tuple[int, bytes] | str | None:
        await self.refresh_loaded()
        no_switch = headers.get(NO_SWITCH_HEADER, "") not in ("", "0", "false")
        v = decide(model, self.loaded, self.inflight, self.last_used, time.monotonic(), GRACE, no_switch)
        if v == "reject":
            return reject_body(path, self.loaded or "?", model)
        if v == "forward":
            return None
        entry = (model, time.monotonic())
        self.queue.append(entry)
        deadline = time.monotonic() + MAX_WAIT
        try:
            async with self.changed:
                while True:
                    now = time.monotonic()
                    if reader is not None and reader.at_eof():
                        # The client gave up (timeout, Ctrl-C): forwarding it later
                        # would switch the card for nobody.
                        return "gone"
                    if decide(model, self.loaded, self.inflight, self.last_used, now, GRACE, False) == "forward" \
                            and self.queue and self.queue[0] is entry:
                        return None
                    if now >= deadline:
                        return 503, json.dumps({"error": {"code": 503, "type": "model_busy",
                                                          "message": f"waited {int(MAX_WAIT)} s for '{self.loaded}' to free the NAS 3090"}}).encode()
                    # wake on any change, or when the grace of the loaded model runs out
                    left = GRACE - (now - self.last_used.get(self.loaded or "", float("-inf")))
                    try:
                        await asyncio.wait_for(self.changed.wait(), max(0.5, min(left + 0.1, 2)))
                    except asyncio.TimeoutError:
                        await self.refresh_loaded(force=True)
        finally:
            if entry in self.queue:
                self.queue.remove(entry)
            async with self.changed:
                self.changed.notify_all()

    async def _forward(self, method: str, target: str, raw_headers: list[str], body: bytes,
                       writer: asyncio.StreamWriter, model: str | None, explicit: bool, path: str,
                       reader: asyncio.StreamReader | None = None) -> None:
        if model and not explicit:
            self.inflight[model] = self.inflight.get(model, 0) + 1
            if self.loaded != model:
                self.loaded = model           # the router switches on this request
                self.loaded_at = time.monotonic()
        if explicit and (path == "/models/unload" or model != self.loaded):
            self.abort()                      # the router unloads only once they finish
        try:
            br, bw = await asyncio.open_connection(BACKEND_HOST, BACKEND_PORT)
        except OSError:
            await self._respond(writer, 502, b'{"error":{"code":502,"message":"llama-server backend unreachable"}}')
            self._done(model, explicit)
            return
        key = id(bw)
        watch = None
        if not explicit:
            self.forwards[key] = (model, bw)
            watch = asyncio.get_running_loop().create_task(self._watch_client(reader, bw))
        keep = [h for h in raw_headers if h.split(":", 1)[0].strip().lower()
                not in ("connection", "content-length", "transfer-encoding", "keep-alive", NO_SWITCH_HEADER)]
        req = f"{method} {target} HTTP/1.1\r\n" + "".join(h + "\r\n" for h in keep)
        req += f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n"
        bw.write(req.encode("latin-1") + body)
        try:
            await bw.drain()
            while True:
                chunk = await br.read(65536)
                if not chunk:
                    break
                writer.write(chunk)
                await writer.drain()
        except (ConnectionError, OSError):
            pass
        finally:
            self.forwards.pop(key, None)
            if watch is not None:
                watch.cancel()
            bw.close()
            try:
                writer.close()
            except OSError:
                pass
            if explicit and path == "/models/load" and model:
                self.loaded, self.loaded_at = model, time.monotonic()
                self.last_used[model] = time.monotonic()   # an explicit switch starts its own grace
            elif explicit:
                self.loaded_at = 0                          # unload: re-read on the next decision
            self._done(model, explicit)

    def _done(self, model: str | None, explicit: bool) -> None:
        if model and not explicit:
            self.inflight[model] = max(0, self.inflight.get(model, 1) - 1)
            self.last_used[model] = time.monotonic()
        asyncio.get_running_loop().create_task(self._notify())

    async def _notify(self) -> None:
        async with self.changed:
            self.changed.notify_all()

    async def _respond(self, writer: asyncio.StreamWriter, code: int, body: bytes) -> None:
        reason = {200: "OK", 400: "Bad Request", 409: "Conflict", 502: "Bad Gateway", 503: "Service Unavailable"}.get(code, "")
        writer.write(f"HTTP/1.1 {code} {reason}\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\n"
                     f"Connection: close\r\n\r\n".encode() + body)
        try:
            await writer.drain()
        finally:
            writer.close()

    def status(self) -> dict:
        now = time.monotonic()
        return {"loaded": self.loaded, "grace_s": GRACE,
                "inflight": {k: v for k, v in self.inflight.items() if v},
                "idle_s": {k: round(now - v, 1) for k, v in self.last_used.items()},
                "queue": [{"model": m, "waiting_s": round(now - t, 1)} for m, t in self.queue]}


async def main() -> None:
    gate = Gate()
    if os.environ.get("LISTEN_FDS") == "1":
        sock = socket.socket(fileno=3)
    else:  # manual runs / tests: GATE_LISTEN=host:port
        host, _, port = os.environ.get("GATE_LISTEN", "127.0.0.1:8099").rpartition(":")
        sock = socket.create_server((host, int(port)))
    sock.setblocking(False)
    server = await asyncio.start_server(gate.handle, sock=sock, limit=1 << 20)
    print(f"gate: grace {GRACE:.0f} s, backend :{BACKEND_PORT}", file=sys.stderr, flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
