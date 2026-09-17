"""L3-10 helper: find unguarded requestIdleCallback uses in a built bundle.

APLANE-1: an unguarded `window.requestIdleCallback(...)` crashed Work Items on every
iOS browser (WebKit has no requestIdleCallback). A use is safe when it is feature
tested (`typeof X.requestIdleCallback`), null-coalesced / optional-chained, compared,
or is the polyfill assignment itself.

  python3 ric_scan.py DIR        → prints "unguarded N" + up to 5 contexts; exit 1 if N > 0
  python3 ric_scan.py --selftest → checks the rules against known-good and known-bad snippets
"""
import os
import re
import sys

NAME = "requestIdleCallback"
GUARD_BEFORE = re.compile(r"typeof\s*\(?\s*(window|globalThis|self)\.requestIdleCallback")
GUARD_AFTER = re.compile(r"^requestIdleCallback\s*(\?\?|\?\.|==|!=|\)?\s*\?)")
GUARD_TERNARY = re.compile(r"(window|globalThis|self)\.requestIdleCallback\s*\?(?![?.])")
POLYFILL = re.compile(r"(globalThis|window|self)\.requestIdleCallback\s*=\s*(globalThis|window|self)\.requestIdleCallback\s*\?\?")


def unguarded(text):
    bad = []
    for m in re.finditer(NAME, text):
        i = m.start()
        before = text[max(0, i - 120):i + len(NAME)]
        after = text[i:i + 40]
        if GUARD_BEFORE.search(before) or GUARD_TERNARY.search(text[max(0, i - 120):i]) or GUARD_AFTER.search(after) or POLYFILL.search(text[max(0, i - 60):i + 80]):
            continue
        # a bare string/property name that is not called (e.g. "requestIdleCallback"in window)
        if not re.match(r"requestIdleCallback\s*\(", after) and not re.match(r"requestIdleCallback\s*\.bind", after):
            continue
        bad.append(text[max(0, i - 50):i + 40])
    return bad


def selftest():
    good = [
        "){let n=null;if(typeof window.requestIdleCallback==`function`)n=window.requestIdleCallback(()=>e(),{timeout:1})",
        "n=(t,n)=>typeof globalThis.requestIdleCallback==`function`?globalThis.requestIdleCallback(t,n):setTimeout(t,1)",
        "typeof globalThis>`u`||(globalThis.requestIdleCallback=globalThis.requestIdleCallback??(e=>setTimeout(e,1)))",
        "(window.requestIdleCallback?window.requestIdleCallback.bind(window):f=>setTimeout(f,1))(g)",
        '"requestIdleCallback"in window',
    ]
    bad = [
        "useEffect(()=>{window.requestIdleCallback(()=>load())},[])",  # the APLANE-1 bundle
        "const h=requestIdleCallback(t);",
    ]
    ok = True
    for g in good:
        if unguarded(g):
            print(f"selftest: false positive on {g!r}")
            ok = False
    for b in bad:
        if not unguarded(b):
            print(f"selftest: missed {b!r}")
            ok = False
    print("selftest OK" if ok else "selftest FAILED")
    return ok


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(0 if selftest() else 1)
    found = []
    for root, _, files in os.walk(sys.argv[1]):
        for f in files:
            if f.endswith(".js"):
                with open(os.path.join(root, f), encoding="utf-8", errors="replace") as fh:
                    found += [(f, c) for c in unguarded(fh.read())]
    print(f"unguarded {len(found)}")
    for f, c in found[:5]:
        print(f"  {f}: {c}")
    sys.exit(1 if found else 0)
