class AIAPI:
    # Only what varbert.api.VariableRenamingAPI reads on the text-only path.
    def __init__(self, decompiler_name="ghidra", use_decompiler=False, delay_init=False, **kwargs):
        self._dec_name = decompiler_name
        self._delay_init = delay_init
        self._dec_interface = None
        self._min_func_size = 0

    @staticmethod
    def requires_function(f):
        return f

    def info(self, *a, **k):
        pass

    warning = error = debug = info
