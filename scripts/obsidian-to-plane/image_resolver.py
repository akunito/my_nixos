import os
import urllib.parse
from config import VAULT_PATH, SKIP_DIRS, get_nextcloud_share_url


class ImageResolver:
    def __init__(self, vault_path: str = VAULT_PATH):
        self.vault_path = vault_path
        self.index = self._build_index()
        print(f"  Image index: {len(self.index)} files")

    def _build_index(self) -> dict:
        """Map filename -> relative path from vault root."""
        index = {}
        for root, dirs, files in os.walk(self.vault_path):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for f in files:
                ext = f.lower().rsplit(".", 1)[-1] if "." in f else ""
                if ext in ("png", "jpg", "jpeg", "gif", "svg", "webp", "pdf"):
                    rel = os.path.relpath(os.path.join(root, f), self.vault_path)
                    # Obsidian uses first-match by filename
                    if f not in index:
                        index[f] = rel
        return index

    def resolve(self, filename: str) -> str:
        """Resolve an image filename to a Nextcloud URL."""
        rel_path = self.index.get(filename)
        if rel_path:
            return get_nextcloud_share_url(rel_path)
        # Try case-insensitive match
        filename_lower = filename.lower()
        for key, val in self.index.items():
            if key.lower() == filename_lower:
                return get_nextcloud_share_url(val)
        return f"#image-not-found-{urllib.parse.quote(filename)}"
