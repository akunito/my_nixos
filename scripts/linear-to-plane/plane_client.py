"""Extended Plane API client for Linear migration."""

import time
import requests


class PlaneClient:
    def __init__(self, base_url: str, workspace_slug: str, api_token: str, delay: float = 0.5):
        # base_url should be like "https://plane.akunito.com/api"
        self.base_url = base_url          # Internal API (for pages)
        self.base_url_v1 = base_url.rstrip("/") + "/v1"  # Public API v1
        self.workspace = workspace_slug
        self.delay = delay
        self.session = requests.Session()
        self.session.headers.update({
            "X-Api-Key": api_token,
            "Content-Type": "application/json",
        })

    def _url(self, path: str, use_internal: bool = False) -> str:
        base = self.base_url if use_internal else self.base_url_v1
        return f"{base}/workspaces/{self.workspace}/{path}"

    def _request(self, method: str, path: str, json_data: dict = None,
                 max_retries: int = 3, use_internal: bool = False) -> dict:
        url = self._url(path, use_internal=use_internal)
        for attempt in range(max_retries):
            try:
                resp = self.session.request(method, url, json=json_data)
                resp.raise_for_status()
                time.sleep(self.delay)
                return resp.json()
            except requests.HTTPError as e:
                if e.response.status_code == 429:
                    wait = float(e.response.headers.get("Retry-After", self.delay * (2 ** attempt)))
                    print(f"  Rate limited, waiting {wait}s...")
                    time.sleep(wait)
                elif e.response.status_code >= 500:
                    print(f"  Server error {e.response.status_code}, retry {attempt + 1}/{max_retries}...")
                    time.sleep(self.delay * (2 ** attempt))
                else:
                    print(f"  HTTP error {e.response.status_code}: {e.response.text[:300]}")
                    raise
        raise RuntimeError(f"API call failed after {max_retries} retries: {method} {path}")

    # =========================================================================
    # States
    # =========================================================================
    def list_states(self, project_id: str) -> list:
        result = self._request("GET", f"projects/{project_id}/states/")
        if isinstance(result, dict) and "results" in result:
            return result["results"]
        if isinstance(result, list):
            return result
        return result

    # =========================================================================
    # Labels
    # =========================================================================
    def list_labels(self, project_id: str) -> list:
        result = self._request("GET", f"projects/{project_id}/labels/")
        if isinstance(result, dict) and "results" in result:
            return result["results"]
        if isinstance(result, list):
            return result
        return result

    def create_label(self, project_id: str, name: str, color: str = "#6b7280") -> dict:
        return self._request("POST", f"projects/{project_id}/labels/", {
            "name": name,
            "color": color,
        })

    # =========================================================================
    # Work Items (Issues)
    # =========================================================================
    def create_work_item(self, project_id: str, name: str, **kwargs) -> dict:
        data = {"name": name, **kwargs}
        return self._request("POST", f"projects/{project_id}/issues/", data)

    def update_work_item(self, project_id: str, issue_id: str, **kwargs) -> dict:
        return self._request("PATCH", f"projects/{project_id}/issues/{issue_id}/", kwargs)

    def list_work_items(self, project_id: str) -> list:
        result = self._request("GET", f"projects/{project_id}/issues/")
        if isinstance(result, dict) and "results" in result:
            return result["results"]
        if isinstance(result, list):
            return result
        return result

    # =========================================================================
    # Comments
    # =========================================================================
    def create_comment(self, project_id: str, issue_id: str, comment_html: str) -> dict:
        return self._request(
            "POST",
            f"projects/{project_id}/issues/{issue_id}/comments/",
            {"comment_html": comment_html},
        )

    # =========================================================================
    # Links
    # =========================================================================
    def create_work_item_link(self, project_id: str, issue_id: str, url: str, title: str = "") -> dict:
        data = {"url": url}
        if title:
            data["title"] = title
        return self._request(
            "POST",
            f"projects/{project_id}/issues/{issue_id}/links/",
            data,
        )

    # =========================================================================
    # Pages
    # =========================================================================
    def create_page(self, project_id: str, name: str, html: str) -> dict:
        return self._request("POST", f"projects/{project_id}/pages/", {
            "name": name,
            "description_html": html,
        }, use_internal=True)
