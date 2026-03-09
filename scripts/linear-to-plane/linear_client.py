"""Linear GraphQL API client with pagination and rate limiting."""

import time
import requests


class LinearClient:
    def __init__(self, api_token: str, delay: float = 0.5):
        self.endpoint = "https://api.linear.app/graphql"
        self.delay = delay
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": api_token,
            "Content-Type": "application/json",
        })

    def _query(self, query: str, variables: dict = None, max_retries: int = 3) -> dict:
        """Execute a GraphQL query with rate limiting and retries."""
        payload = {"query": query}
        if variables:
            payload["variables"] = variables

        for attempt in range(max_retries):
            try:
                resp = self.session.post(self.endpoint, json=payload)
                resp.raise_for_status()
                time.sleep(self.delay)
                data = resp.json()
                if "errors" in data:
                    errors = data["errors"]
                    raise RuntimeError(f"GraphQL errors: {errors}")
                return data["data"]
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
        raise RuntimeError(f"Linear API call failed after {max_retries} retries")

    def _paginate(self, query: str, path: list[str], variables: dict = None, page_size: int = 50) -> list:
        """Generic paginator for Linear's cursor-based pagination.

        `path` is the list of keys to reach the connection node, e.g. ["issues"].
        The query MUST include $cursor and $first variables and use pageInfo { hasNextPage endCursor }.
        """
        all_items = []
        cursor = None
        variables = dict(variables or {})
        variables["first"] = page_size

        while True:
            variables["cursor"] = cursor
            data = self._query(query, variables)

            # Navigate to the connection node
            node = data
            for key in path:
                node = node[key]

            items = node.get("nodes", [])
            all_items.extend(items)

            page_info = node.get("pageInfo", {})
            if page_info.get("hasNextPage"):
                cursor = page_info["endCursor"]
            else:
                break

        return all_items

    # =========================================================================
    # Teams
    # =========================================================================
    def get_teams(self) -> list:
        """Get all teams in the workspace."""
        data = self._query("""
            query {
                teams {
                    nodes {
                        id
                        name
                        key
                    }
                }
            }
        """)
        return data["teams"]["nodes"]

    # =========================================================================
    # Projects
    # =========================================================================
    def get_projects(self) -> list:
        """Get all projects."""
        return self._paginate("""
            query($first: Int!, $cursor: String) {
                projects(first: $first, after: $cursor) {
                    nodes {
                        id
                        name
                        description
                        state
                        startDate
                        targetDate
                        progress
                        teams {
                            nodes { id name }
                        }
                    }
                    pageInfo { hasNextPage endCursor }
                }
            }
        """, ["projects"])

    def get_project_by_name(self, name: str) -> dict | None:
        """Find a project by exact name."""
        projects = self.get_projects()
        for p in projects:
            if p["name"] == name:
                return p
        return None

    # =========================================================================
    # Workflow States
    # =========================================================================
    def get_workflow_states(self, team_id: str) -> list:
        """Get workflow states for a team."""
        return self._paginate("""
            query($teamId: ID!, $first: Int!, $cursor: String) {
                workflowStates(first: $first, after: $cursor, filter: { team: { id: { eq: $teamId } } }) {
                    nodes {
                        id
                        name
                        type
                        position
                    }
                    pageInfo { hasNextPage endCursor }
                }
            }
        """, ["workflowStates"], {"teamId": team_id})

    # =========================================================================
    # Labels
    # =========================================================================
    def get_labels(self, team_id: str = None) -> list:
        """Get labels, optionally filtered by team."""
        if team_id:
            return self._paginate("""
                query($teamId: ID!, $first: Int!, $cursor: String) {
                    issueLabels(first: $first, after: $cursor, filter: { team: { id: { eq: $teamId } } }) {
                        nodes {
                            id
                            name
                            color
                            description
                        }
                        pageInfo { hasNextPage endCursor }
                    }
                }
            """, ["issueLabels"], {"teamId": team_id})
        else:
            return self._paginate("""
                query($first: Int!, $cursor: String) {
                    issueLabels(first: $first, after: $cursor) {
                        nodes {
                            id
                            name
                            color
                            description
                        }
                        pageInfo { hasNextPage endCursor }
                    }
                }
            """, ["issueLabels"])

    # =========================================================================
    # Issues
    # =========================================================================
    def get_issues(self, project_id: str) -> list:
        """Get all issues for a project with full details."""
        return self._paginate("""
            query($projectId: ID!, $first: Int!, $cursor: String) {
                issues(first: $first, after: $cursor, filter: { project: { id: { eq: $projectId } } }) {
                    nodes {
                        id
                        identifier
                        title
                        description
                        priority
                        estimate
                        dueDate
                        createdAt
                        updatedAt
                        sortOrder
                        state {
                            id
                            name
                            type
                        }
                        assignee {
                            id
                            name
                            email
                        }
                        creator {
                            id
                            name
                            email
                        }
                        parent {
                            id
                            identifier
                        }
                        labels {
                            nodes {
                                id
                                name
                                color
                            }
                        }
                        attachments {
                            nodes {
                                id
                                title
                                url
                                metadata
                            }
                        }
                        children {
                            nodes {
                                id
                                identifier
                            }
                        }
                    }
                    pageInfo { hasNextPage endCursor }
                }
            }
        """, ["issues"], {"projectId": project_id})

    # =========================================================================
    # Comments
    # =========================================================================
    def get_issue_comments(self, issue_id: str) -> list:
        """Get all comments for an issue."""
        return self._paginate("""
            query($issueId: ID!, $first: Int!, $cursor: String) {
                comments(first: $first, after: $cursor, filter: { issue: { id: { eq: $issueId } } }) {
                    nodes {
                        id
                        body
                        createdAt
                        updatedAt
                        user {
                            id
                            name
                            email
                        }
                    }
                    pageInfo { hasNextPage endCursor }
                }
            }
        """, ["comments"], {"issueId": issue_id})

    # =========================================================================
    # Documents
    # =========================================================================
    def get_documents(self, project_id: str) -> list:
        """Get all documents for a project."""
        return self._paginate("""
            query($projectId: ID!, $first: Int!, $cursor: String) {
                documents(first: $first, after: $cursor, filter: { project: { id: { eq: $projectId } } }) {
                    nodes {
                        id
                        title
                        content
                        createdAt
                        updatedAt
                        creator {
                            id
                            name
                            email
                        }
                        project {
                            id
                            name
                        }
                    }
                    pageInfo { hasNextPage endCursor }
                }
            }
        """, ["documents"], {"projectId": project_id})

    # =========================================================================
    # Cycles
    # =========================================================================
    def get_cycles(self, team_id: str) -> list:
        """Get all cycles for a team."""
        return self._paginate("""
            query($teamId: ID!, $first: Int!, $cursor: String) {
                cycles(first: $first, after: $cursor, filter: { team: { id: { eq: $teamId } } }) {
                    nodes {
                        id
                        name
                        description
                        number
                        startsAt
                        endsAt
                        completedAt
                        progress
                        issues {
                            nodes {
                                id
                                identifier
                            }
                        }
                    }
                    pageInfo { hasNextPage endCursor }
                }
            }
        """, ["cycles"], {"teamId": team_id})

    # =========================================================================
    # Project Milestones
    # =========================================================================
    def get_project_milestones(self, project_id: str) -> list:
        """Get milestones for a project."""
        data = self._query("""
            query($projectId: String!) {
                project(id: $projectId) {
                    projectMilestones {
                        nodes {
                            id
                            name
                            description
                            targetDate
                            sortOrder
                        }
                    }
                }
            }
        """, {"projectId": project_id})
        return data["project"]["projectMilestones"]["nodes"]

    # =========================================================================
    # Users
    # =========================================================================
    def get_users(self) -> list:
        """Get all workspace users."""
        return self._paginate("""
            query($first: Int!, $cursor: String) {
                users(first: $first, after: $cursor) {
                    nodes {
                        id
                        name
                        email
                        active
                    }
                    pageInfo { hasNextPage endCursor }
                }
            }
        """, ["users"])
