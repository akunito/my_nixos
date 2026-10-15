# Minimal stand-ins for libbs/dailalib (AINF-408 M4): varbert imports them at module level,
# but text-only prediction (use_decompiler=False) needs only these names. Pulling the real
# packages would drag dailalib's LLM stack into a process that only runs a local BERT.
