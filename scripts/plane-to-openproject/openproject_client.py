"""OpenProject API v3 client (writes only to the disposable demo instance)."""
import time
import requests
from requests.auth import HTTPBasicAuth

import config


class OpenProjectClient:
    def __init__(self, base_url: str, api_key: str, delay: float = config.API_DELAY_SECONDS):
        self.base = base_url.rstrip("/")
        self.delay = delay
        self.session = requests.Session()
        self.session.auth = HTTPBasicAuth("apikey", api_key)
        self.session.headers.update({"Content-Type": "application/json"})

    def _req(self, method: str, path: str, json_data: dict = None, max_retries: int = 3):
        url = f"{self.base}/api/v3{path}"
        for attempt in range(max_retries):
            resp = self.session.request(method, url, json=json_data)
            if resp.status_code >= 500:
                print(f"  [op] {resp.status_code}, retry {attempt + 1}/{max_retries}")
                time.sleep(self.delay * (2 ** attempt))
                continue
            time.sleep(self.delay)
            return resp
        raise RuntimeError(f"{method} failed after {max_retries} retries: {url}")

    # --- lookups ---
    def _collection(self, path: str):
        resp = self._req("GET", path)
        resp.raise_for_status()
        return resp.json().get("_embedded", {}).get("elements", [])

    def name_to_href(self, path: str) -> dict:
        """Map element name -> self href for a v3 collection (statuses/priorities/types)."""
        out = {}
        for el in self._collection(path):
            out[el["name"]] = el["_links"]["self"]["href"]
        return out

    def statuses(self):
        return self.name_to_href("/statuses")

    def priorities(self):
        return self.name_to_href("/priorities")

    def types(self):
        return self.name_to_href("/types")

    # --- project ---
    def find_project(self, identifier: str):
        resp = self._req("GET", f"/projects/{identifier}")
        if resp.status_code == 200:
            return resp.json()
        return None

    def create_project(self, name: str, identifier: str):
        body = {"name": name, "identifier": identifier,
                "description": {"raw": "Disposable demo: AINF migrated from Plane for evaluation."}}
        resp = self._req("POST", "/projects", body)
        resp.raise_for_status()
        return resp.json()

    def ensure_project(self, name: str, identifier: str):
        return self.find_project(identifier) or self.create_project(name, identifier)

    # --- work packages ---
    def create_work_package(self, project_id, subject, description_md,
                            type_href, status_href, priority_href, parent_href=None):
        body = {
            "subject": subject[:255],
            "description": {"format": "markdown", "raw": description_md or ""},
            "_links": {
                "type": {"href": type_href},
                "status": {"href": status_href},
                "priority": {"href": priority_href},
            },
        }
        if parent_href:
            body["_links"]["parent"] = {"href": parent_href}
        resp = self._req("POST", f"/projects/{project_id}/work_packages", body)
        if not resp.ok:
            raise RuntimeError(f"WP create failed {resp.status_code}: {resp.text[:300]}")
        return resp.json()

    def set_parent(self, wp_id, parent_href, lock_version):
        body = {"lockVersion": lock_version, "_links": {"parent": {"href": parent_href}}}
        resp = self._req("PATCH", f"/work_packages/{wp_id}", body)
        resp.raise_for_status()
        return resp.json()

    # --- wiki (may be version-dependent; caller handles failure) ---
    def create_wiki_page(self, project_id, title, text_md):
        body = {"title": title[:255],
                "text": {"format": "markdown", "raw": text_md or ""}}
        resp = self._req("POST", f"/projects/{project_id}/wiki_pages", body)
        if not resp.ok:
            raise RuntimeError(f"wiki create {resp.status_code}: {resp.text[:200]}")
        return resp.json()
