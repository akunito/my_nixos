"""Minimal SNSS (Chromium/Vivaldi session) reader — exploratory pass."""
import struct, sys, json, collections

class Pickle:
    def __init__(self, buf):
        self.b = buf
        self.o = 0
    def _align(self, n=4):
        self.o = (self.o + (n - 1)) & ~(n - 1)
    def u32(self):
        v = struct.unpack_from("<I", self.b, self.o)[0]; self.o += 4; return v
    def i32(self):
        v = struct.unpack_from("<i", self.b, self.o)[0]; self.o += 4; return v
    def string(self):
        n = self.i32()
        if n < 0 or self.o + n > len(self.b): raise ValueError("bad string len")
        s = self.b[self.o:self.o + n]; self.o += n; self._align()
        return s.decode("utf-8", "replace")
    def string16(self):
        n = self.i32()
        if n < 0 or self.o + 2 * n > len(self.b): raise ValueError("bad string16 len")
        s = self.b[self.o:self.o + 2 * n]; self.o += 2 * n; self._align()
        return s.decode("utf-16-le", "replace")
    def left(self):
        return len(self.b) - self.o


def records(path):
    d = open(path, "rb").read()
    assert d[:4] == b"SNSS", "not an SNSS file"
    ver = struct.unpack_from("<i", d, 4)[0]
    o = 8
    while o + 2 <= len(d):
        (size,) = struct.unpack_from("<H", d, o); o += 2
        if size == 0 or o + size > len(d):
            break
        cmd = d[o]
        yield cmd, d[o + 1:o + size]
        o += size


if __name__ == "__main__":
    path = sys.argv[1]
    hist = collections.Counter()
    samples = {}
    for cmd, payload in records(path):
        hist[cmd] += 1
        if cmd not in samples:
            samples[cmd] = payload[:120]
    print("cmd  count  sample")
    for cmd, n in sorted(hist.items()):
        s = samples[cmd]
        printable = "".join(chr(c) if 32 <= c < 127 else "." for c in s[:80])
        print(f"{cmd:>3}  {n:>5}  {printable}")
