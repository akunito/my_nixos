import os
from pathlib import Path


class PluginInstaller:
    @staticmethod
    def find_pkg_files(name):
        # Models live in the Nix store, one root per optimisation level; the runner sets it.
        return Path(os.environ["VARBERT_ROOT"])
