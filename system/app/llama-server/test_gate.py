"""gate.py: decision table + an end-to-end run against a fake router.
Run: python3 -m unittest system/app/llama-server/test_gate.py (from the repo root)."""
from __future__ import annotations

import asyncio
import importlib.util
import json
import os
import sys
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load_gate(env: dict[str, str]):
    os.environ.update(env)
    spec = importlib.util.spec_from_file_location("gate_under_test", HERE / "gate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Decide(unittest.TestCase):
    def setUp(self):
        self.g = load_gate({"GATE_BACKEND_PORT": "1"})

    def d(self, model, loaded, inflight=None, last=None, now=1000.0, grace=300, ns=False):
        return self.g.decide(model, loaded, inflight or {}, last or {}, now, grace, ns)

    def test_same_or_nothing_loaded_forwards(self):
        self.assertEqual(self.d("a", "a"), "forward")
        self.assertEqual(self.d("a", None), "forward")
        self.assertEqual(self.d(None, "a"), "forward")

    def test_other_model_waits_while_busy_or_within_grace(self):
        self.assertEqual(self.d("b", "a", inflight={"a": 1}), "wait")
        self.assertEqual(self.d("b", "a", last={"a": 900.0}), "wait")      # 100 s ago < 300
        self.assertEqual(self.d("b", "a", last={"a": 600.0}), "forward")   # 400 s ago

    def test_no_switch_header_rejects_even_when_idle(self):
        self.assertEqual(self.d("b", "a", last={"a": 0.0}, ns=True), "reject")

    def test_request_model(self):
        self.assertEqual(self.g.request_model("POST", "/v1/chat/completions", {"content-type": "application/json"},
                                              b'{"model":"coder"}'), "coder")
        self.assertEqual(self.g.request_model("GET", "/props?model=laya", {}, b""), "laya")
        self.assertIsNone(self.g.request_model("GET", "/health", {}, b""))

    def test_reject_shapes(self):
        code, body = self.g.reject_body("/v1/messages", "reasoner-256k", "coder")
        self.assertEqual(code, 400)
        self.assertIn("Waybar NAS widget", json.loads(body)["error"]["message"])
        code, body = self.g.reject_body("/v1/chat/completions", "a", "b")
        self.assertEqual((code, json.loads(body)["error"]["type"]), (409, "model_busy"))


class SameModel(unittest.TestCase):
    def test_no_switch_request_for_same_gguf_is_served_by_the_loaded_preset(self):
        async def run():
            fake = FakeRouter(models=("reasoner-256k", "reasoner-256k-cache-mtp", "reasoner-128k-cache-mtp", "coder"),
                              loaded="reasoner-256k-cache-mtp")
            bsrv = await asyncio.start_server(fake.handle, "127.0.0.1", 0)
            same = {"reasoner-256k": {"file": "q38.gguf", "ctx": 262144},
                    "reasoner-256k-cache-mtp": {"file": "q38.gguf", "ctx": 262144},
                    "reasoner-128k-cache-mtp": {"file": "q38.gguf", "ctx": 131072},
                    "coder": {"file": "q36.gguf", "ctx": 262144}}
            g = load_gate({"GATE_BACKEND_PORT": str(bsrv.sockets[0].getsockname()[1]), "GATE_GRACE_SECONDS": "60",
                           "GATE_SAME_MODEL": json.dumps(same)})
            gate = g.Gate()
            gsrv = await asyncio.start_server(gate.handle, "127.0.0.1", 0)
            port = gsrv.sockets[0].getsockname()[1]
            h = {"X-Nas-No-Switch": "1"}
            st, body = await http(port, "POST", "/v1/messages", {"model": "reasoner-256k"}, h)
            self.assertEqual((st, body["model"]), (200, "reasoner-256k-cache-mtp"))
            st, _ = await http(port, "POST", "/v1/messages", {"model": "coder"}, h)
            self.assertEqual(st, 400)                     # other GGUF: still a manual switch
            fake.loaded = "reasoner-128k-cache-mtp"; gate.loaded_at = 0
            st, _ = await http(port, "POST", "/v1/messages", {"model": "reasoner-256k"}, h)
            self.assertEqual(st, 400)                     # loaded one has less context than the session expects
            self.assertEqual(fake.loaded, "reasoner-128k-cache-mtp")
            gsrv.close(); bsrv.close()
        asyncio.run(run())


class LegacyAlias(unittest.TestCase):
    def test_old_reasoner_alias_is_served_by_the_loaded_reasoner(self):
        async def run():
            fake = FakeRouter(models=("reasoner-256k", "coder"), loaded="reasoner-256k")
            bsrv = await asyncio.start_server(fake.handle, "127.0.0.1", 0)
            g = load_gate({"GATE_BACKEND_PORT": str(bsrv.sockets[0].getsockname()[1]), "GATE_GRACE_SECONDS": "60"})
            gate = g.Gate()
            gsrv = await asyncio.start_server(gate.handle, "127.0.0.1", 0)
            port = gsrv.sockets[0].getsockname()[1]
            st, body = await http(port, "POST", "/v1/messages", {"model": "qwen3.8-27b-abliterated"}, {"X-Nas-No-Switch": "1"})
            self.assertEqual((st, body["model"]), (200, "reasoner-256k"))
            self.assertEqual(fake.loaded, "reasoner-256k")
            self.assertEqual(fake.log[-1], "POST /v1/messages:reasoner-256k")   # path kept (a shadowed name once sent 'POST reasoner-256k')
            fake.loaded = "coder"
            gate.loaded_at = 0
            st, body = await http(port, "POST", "/v1/messages", {"model": "qwen3.8-27b-abliterated"})
            self.assertEqual(st, 400)   # another preset loaded: unknown, never a switch
            fake.loaded = None
            gate.loaded_at = 0
            st, body = await http(port, "POST", "/v1/messages", {"model": "qwen3.8-27b-abliterated"})
            self.assertEqual((st, body["model"]), (200, "reasoner-256k"))   # nothing loaded: its default
            gsrv.close(); bsrv.close()
        asyncio.run(run())


class FakeRouter:
    """Loads the model a request names after IN-FLIGHT requests finish (as measured on b11580)."""

    def __init__(self, models=("a", "b"), loaded="a"):
        self.models = models
        self.loaded = loaded
        self.log: list[str] = []

    async def handle(self, r, w):
        head = await r.readuntil(b"\r\n\r\n")
        lines = head.decode().split("\r\n")
        method, target, _ = lines[0].split(" ", 2)
        hdr = {l.split(":")[0].lower(): l.split(":", 1)[1].strip() for l in lines[1:] if ":" in l}
        body = await r.readexactly(int(hdr.get("content-length", "0")))
        if target == "/models":
            out = json.dumps({"data": [{"id": m, "status": {"value": "loaded" if m == self.loaded else "unloaded"}}
                                       for m in self.models]}).encode()
        else:
            m = json.loads(body or b"{}").get("model")
            if target == "/models/load":
                self.loaded = m
            elif m:
                self.loaded = m
            self.log.append(f"{method} {target}:{m}")
            await asyncio.sleep(float(json.loads(body or b"{}").get("sleep", 0)))
            out = json.dumps({"model": m, "ok": True}).encode()
        w.write(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(out) + out)
        await w.drain()
        w.close()


async def http(port, method, path, body=None, headers=None):
    r, w = await asyncio.open_connection("127.0.0.1", port)
    data = json.dumps(body).encode() if body is not None else b""
    h = "".join(f"{k}: {v}\r\n" for k, v in (headers or {}).items())
    w.write(f"{method} {path} HTTP/1.1\r\nHost: t\r\nContent-Type: application/json\r\nContent-Length: {len(data)}\r\n{h}\r\n".encode() + data)
    await w.drain()
    raw = await r.read()
    w.close()
    status = int(raw.split(b" ", 2)[1])
    return status, json.loads(raw.split(b"\r\n\r\n", 1)[1] or b"{}")


class EndToEnd(unittest.TestCase):
    def test_queue_reject_explicit(self):
        async def run():
            fake = FakeRouter()
            bsrv = await asyncio.start_server(fake.handle, "127.0.0.1", 0)
            bport = bsrv.sockets[0].getsockname()[1]
            g = load_gate({"GATE_BACKEND_PORT": str(bport), "GATE_GRACE_SECONDS": "1.0", "GATE_MAX_WAIT_SECONDS": "20"})
            gate = g.Gate()
            gsrv = await asyncio.start_server(gate.handle, "127.0.0.1", 0)
            gport = gsrv.sockets[0].getsockname()[1]
            # a is in use (0.6 s answer); b from another client must wait for it + 1 s grace
            t0 = time.monotonic()
            first = asyncio.create_task(http(gport, "POST", "/v1/chat/completions", {"model": "a", "sleep": 0.6}))
            await asyncio.sleep(0.1)
            st, _ = await http(gport, "POST", "/v1/chat/completions", {"model": "b"})
            waited = time.monotonic() - t0
            await first
            self.assertEqual(st, 200)
            self.assertGreaterEqual(waited, 1.5, "b must wait for a's answer AND the grace")
            self.assertEqual(fake.log[:2], ["POST /v1/chat/completions:a", "POST /v1/chat/completions:b"])
            # claude-nas naming another model: rejected at once, nothing forwarded
            n = len(fake.log)
            t1 = time.monotonic()
            st, body = await http(gport, "POST", "/v1/messages", {"model": "a"}, {"X-Nas-No-Switch": "1"})
            self.assertEqual(st, 400)
            self.assertLess(time.monotonic() - t1, 0.5)
            self.assertIn("Waybar NAS widget", body["error"]["message"])
            self.assertEqual(len(fake.log), n)
            # same model with the header passes
            st, _ = await http(gport, "POST", "/v1/messages", {"model": "b"}, {"X-Nas-No-Switch": "1"})
            self.assertEqual(st, 200)
            # explicit load passes immediately even though b was just used
            t2 = time.monotonic()
            st, _ = await http(gport, "POST", "/models/load", {"model": "a"})
            self.assertEqual(st, 200)
            self.assertLess(time.monotonic() - t2, 0.5)
            self.assertEqual(fake.loaded, "a")
            st, s = await http(gport, "GET", "/gate/status")
            self.assertEqual((st, s["loaded"]), (200, "a"))
            # a queued client that gives up must not switch the card later
            n = len(fake.log)
            r, w = await asyncio.open_connection("127.0.0.1", gport)
            body = json.dumps({"model": "b"}).encode()
            w.write(b"POST /v1/chat/completions HTTP/1.1\r\nHost: t\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % len(body) + body)
            await w.drain()
            await asyncio.sleep(0.3)
            st, s = await http(gport, "GET", "/gate/status")
            self.assertEqual([q["model"] for q in s["queue"]], ["b"])
            w.close()
            await asyncio.sleep(1.5 + 2.5)   # past the 1 s grace and one wake-up
            self.assertEqual(len(fake.log), n, "abandoned request was forwarded")
            self.assertEqual(fake.loaded, "a")
            st, s = await http(gport, "GET", "/gate/status")
            self.assertEqual(s["queue"], [])
            # unknown name: rejected at once, never queued
            t3 = time.monotonic()
            st, body = await http(gport, "POST", "/v1/chat/completions", {"model": "nope"})
            self.assertEqual(st, 400)
            self.assertLess(time.monotonic() - t3, 0.5)
            self.assertIn("Known: a, b", body["error"]["message"])
            gsrv.close()
            bsrv.close()
        asyncio.run(run())


if __name__ == "__main__":
    unittest.main()
