import time
import requests


class PlaneClient:
    def __init__(self, base_url: str, workspace_slug: str, api_token: str, delay: float = 0.5):
        self.base_url = base_url
        self.workspace = workspace_slug
        self.delay = delay
        self.session = requests.Session()
        self.session.headers.update({
            "X-Api-Key": api_token,
            "Content-Type": "application/json",
        })

    def _url(self, path: str) -> str:
        return f"{self.base_url}/workspaces/{self.workspace}/{path}"

    def _request(self, method: str, path: str, json_data: dict = None, max_retries: int = 3) -> dict:
        url = self._url(path)
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
                    print(f"  HTTP error {e.response.status_code}: {e.response.text[:200]}")
                    raise
        raise RuntimeError(f"API call failed after {max_retries} retries: {method} {path}")

    def create_page(self, project_id: str, name: str, html: str) -> dict:
        return self._request("POST", f"projects/{project_id}/pages/", {
            "name": name,
            "description_html": html,
        })

    def update_page(self, project_id: str, page_id: str, html: str) -> dict:
        return self._request("PATCH", f"projects/{project_id}/pages/{page_id}/", {
            "description_html": html,
        })

    def create_work_item(self, project_id: str, name: str, **kwargs) -> dict:
        data = {"name": name, **kwargs}
        return self._request("POST", f"projects/{project_id}/issues/", data)

    def list_states(self, project_id: str) -> list:
        return self._request("GET", f"projects/{project_id}/states/")
