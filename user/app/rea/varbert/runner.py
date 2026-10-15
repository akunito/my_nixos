# rea-varbert: persistent VarBERT worker (AINF-408 M4). One JSON request per line on stdin:
#   {"text": "<Ghidra C of one function>", "opt": "O0" | "O2"}
# answers {"names": {old: new}, "code": "<renamed C>"} or {"error": "..."} per line.
# Models are the Ghidra-trained VarBERT weights converted to safetensors at build time
# (varbert.nix); the pickled originals never reach this process.
import atexit
import json
import logging
import os
import re
import shutil
import sys
import tempfile

# Libraries print progress to stdout; keep the real stdout for answers only.
OUT = sys.stdout
sys.stdout = sys.stderr
# varbert/logger.py creates $TMPDIR/varbert.*.log at import and appends INFO per request
# (audit 2026-10-15): give it a private dir removed at exit, and keep the level at WARNING.
_tmp = tempfile.mkdtemp(prefix="rea-varbert.")
os.environ["TMPDIR"] = _tmp
tempfile.tempdir = _tmp
atexit.register(shutil.rmtree, _tmp, True)
logging.getLogger("varbert").setLevel(logging.WARNING)

ROOTS = {"O0": os.environ["VARBERT_O0"], "O2": os.environ["VARBERT_O2"]}
MAX_TEXT = 32 * 1024
# Ghidra separates the declarations from the body with a line of two spaces; varbert's
# text_processor splits on "\n\n", so without this no local variable was ever renamed
# (audit 2026-10-15, reproduced: locals [] -> ['cVar1', 'sVar2', 'local_18']).
BLANKISH = re.compile(r"\n[ \t]+\n")
apis = {}


def api_for(opt):
    if opt not in apis:
        os.environ["VARBERT_ROOT"] = ROOTS[opt]  # read by the libbs stub when the model loads
        from varbert.api import VariableRenamingAPI
        apis[opt] = VariableRenamingAPI(decompiler_name="ghidra", use_decompiler=False)
        logging.getLogger("varbert").setLevel(logging.WARNING)
    return apis[opt]


for line in sys.stdin:
    try:
        req = json.loads(line)
        opt = req.get("opt", "O2")
        text = req["text"]
        if opt not in ROOTS:
            raise ValueError("opt must be O0 or O2")
        if len(text) > MAX_TEXT or "{" not in text or ")" not in text:
            raise ValueError("expected the pseudo-code of ONE function (<= 32 KB, with a signature and a body)")
        names, code = api_for(opt).predict_variable_names(decompilation_text=BLANKISH.sub("\n\n", text), use_decompiler=False)
        out = {"names": names, "code": code}
    except Exception as e:  # one bad function must not kill the worker
        out = {"error": f"{type(e).__name__}: {e}"}
    OUT.write(json.dumps(out) + "\n")
    OUT.flush()
