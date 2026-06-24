"""Read-only Plane client. ONLY issues GET requests — never mutates Plane."""
import time
import requests

import config


class PlaneReader:
    def __init__(self, api_token: str, delay: float = config.API_DELAY_SECONDS):
        self.delay = delay
        self.ws = config.WORKSPACE_SLUG
        self.session = requests.Session()
        self.session.headers.update({"X-Api-Key": api_token})

    def _get(self, url: str, params: dict = None, max_retries: int = 3):
        for attempt in range(max_retries):
            resp = self.session.get(url, params=params)
            if resp.status_code == 429:
                wait = float(resp.headers.get("Retry-After", self.delay * (2 ** attempt)))
                print(f"  [plane] rate limited, waiting {wait}s")
                time.sleep(wait)
                continue
            if resp.status_code >= 500:
                print(f"  [plane] {resp.status_code}, retry {attempt + 1}/{max_retries}")
                time.sleep(self.delay * (2 ** attempt))
                continue
            resp.raise_for_status()
            time.sleep(self.delay)
            return resp.json()
        raise RuntimeError(f"GET failed after {max_retries} retries: {url}")

    def _paginate(self, url: str):
        """Yield items across Plane's cursor/offset pagination shapes."""
        params = {"per_page": 100}
        seen_cursor = None
        while True:
            data = self._get(url, params=params)
            if isinstance(data, list):
                yield from data
                return
            results = data.get("results", [])
            yield from results
            # cursor style
            nxt = data.get("next_cursor")
            if data.get("next_page_results") and nxt and nxt != seen_cursor:
                seen_cursor = nxt
                params = {"per_page": 100, "cursor": nxt}
                continue
            # offset/url style
            nxt_url = data.get("next")
            if nxt_url:
                url, params = nxt_url, None
                continue
            return

    # --- issues / states / labels (public /api/v1) ---
    def issues(self, project_id: str):
        url = f"{config.PLANE_BASE_V1}/workspaces/{self.ws}/projects/{project_id}/issues/"
        return list(self._paginate(url))

    def issue_detail(self, project_id: str, issue_id: str):
        url = f"{config.PLANE_BASE_V1}/workspaces/{self.ws}/projects/{project_id}/issues/{issue_id}/"
        return self._get(url)

    def states(self, project_id: str):
        url = f"{config.PLANE_BASE_V1}/workspaces/{self.ws}/projects/{project_id}/states/"
        data = self._get(url)
        return data.get("results", data) if isinstance(data, dict) else data

    def labels(self, project_id: str):
        url = f"{config.PLANE_BASE_V1}/workspaces/{self.ws}/projects/{project_id}/labels/"
        data = self._get(url)
        return data.get("results", data) if isinstance(data, dict) else data

    # --- pages (patched internal /api) ---
    def pages(self, project_id: str):
        url = f"{config.PLANE_BASE}/workspaces/{self.ws}/projects/{project_id}/pages/"
        return list(self._paginate(url))

    def page_detail(self, project_id: str, page_id: str):
        url = f"{config.PLANE_BASE}/workspaces/{self.ws}/projects/{project_id}/pages/{page_id}/"
        return self._get(url)
