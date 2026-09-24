#!/usr/bin/env python3
"""Local OpenCode v2 -> legacy list-envelope adapter for OpenChamber 1.x.

This is a diagnostic/bridge prototype. It binds only to loopback, never logs
credentials, and only unwraps known V2 response envelopes for read/list APIs.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import http.client
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlsplit

UPSTREAM_URL = os.environ.get("OPENCODE_UPSTREAM_URL", "http://127.0.0.1:49374")
UPSTREAM = urlsplit(UPSTREAM_URL)
UPSTREAM_HOST = UPSTREAM.hostname or "127.0.0.1"
UPSTREAM_PORT = UPSTREAM.port or (443 if UPSTREAM.scheme == "https" else 80)
UPSTREAM_SCHEME = UPSTREAM.scheme or "http"
USERNAME = os.environ.get("OPENCODE_SERVER_USERNAME", "opencode")
PASSWORD = os.environ.get("OPENCODE_SERVER_PASSWORD", "")
if not PASSWORD:
    state_path = Path("/home/j0wlt/.config/opencode-redteam/state/opencode/service.json")
    if state_path.exists():
        PASSWORD = json.loads(state_path.read_text()).get("password", "")

AUTH = "Basic " + base64.b64encode(f"{USERNAME}:{PASSWORD}".encode()).decode()
DEFAULT_PROJECT_DIR = os.environ.get("OPENCODE_PROJECT_DIR", "/home/j0wlt/redteam-agent")
SESSION_STATUS: dict[str, dict[str, str]] = {}
SESSION_DIRECTORY: dict[str, str] = {}
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailer", "transfer-encoding", "upgrade",
}


def fail(message: str) -> None:
    print(f"[redteam-adapter] ERROR: {message}", file=sys.stderr, flush=True)
    raise SystemExit(2)


def validate_configuration() -> None:
    global PASSWORD, AUTH
    if not PASSWORD and STATE_PATH.exists():
        try:
            state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            fail(f"cannot read service state: {exc}")
        PASSWORD = state.get("password", "")
    if not PASSWORD:
        fail("dedicated OpenCode service password is unavailable")
    if UPSTREAM_SCHEME not in {"http", "https"}:
        fail("upstream URL must use http or https")
    if UPSTREAM_HOST not in {"127.0.0.1", "localhost", "::1"}:
        fail("upstream URL must be loopback")
    AUTH = "Basic " + base64.b64encode(f"{USERNAME}:{PASSWORD}".encode()).decode()


def request_directory(handler: BaseHTTPRequestHandler) -> str:
    parsed = urlsplit(handler.path)
    values = parse_qs(parsed.query).get("directory")
    if values and values[0]:
        return values[0]
    header_directory = handler.headers.get("x-opencode-directory")
    return header_directory or DEFAULT_PROJECT_DIR


def fetch_upstream_json(path: str, directory: str | None = None):
    if directory and "?" not in path:
        path = f"{path}?{urlencode({'directory': directory})}"
    if UPSTREAM_SCHEME == "https":
        import ssl
        conn = http.client.HTTPSConnection(
            UPSTREAM_HOST,
            UPSTREAM_PORT,
            timeout=10,
            context=ssl._create_unverified_context(),
        )
    else:
        conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=10)
    try:
        conn.request(
            "GET",
            path,
            headers={
                "Authorization": AUTH,
                "Accept": "application/json",
                "Accept-Encoding": "identity",
            },
        )
        response = conn.getresponse()
        body = response.read()
        if response.status >= 400:
            return None
        return json.loads(body.decode("utf-8"))
    except (OSError, ValueError, json.JSONDecodeError):
        return None
    finally:
        conn.close()


def project_payload(directory: str) -> dict:
    projects = fetch_upstream_json("/api/project", directory)
    if isinstance(projects, list):
        for project in projects:
            if not isinstance(project, dict) or project.get("canonical") != directory:
                continue
            created = project.get("time", {}).get("created", 0) if isinstance(project.get("time"), dict) else 0
            return {
                "id": project.get("id", hashlib.sha1(directory.encode()).hexdigest()),
                "worktree": directory,
                "vcs": "git",
                "time": {"created": created},
            }
    return {
        "id": hashlib.sha1(directory.encode()).hexdigest(),
        "worktree": directory,
        "vcs": "git",
        "time": {"created": 0},
    }


def compatibility_response(handler: BaseHTTPRequestHandler, parsed):
    if handler.command != "GET":
        return None
    directory = request_directory(handler)
    if parsed.path == "/api/path":
        return {
            "state": "ready",
            "config": str(Path(directory) / ".opencode"),
            "worktree": directory,
            "directory": directory,
        }
    if parsed.path == "/api/project/current":
        return project_payload(directory)
    if parsed.path == "/api/session/status":
        sessions = fetch_upstream_json("/api/session", directory)
        rows = sessions.get("data", []) if isinstance(sessions, dict) else sessions
        if isinstance(rows, list):
            for session in rows:
                if isinstance(session, dict) and isinstance(session.get("id"), str):
                    SESSION_STATUS.setdefault(session["id"], {"type": "idle"})
                    SESSION_DIRECTORY[session["id"]] = directory
        return {
            session_id: status
            for session_id, status in SESSION_STATUS.items()
            if SESSION_DIRECTORY.get(session_id, directory) == directory
        }
    if parsed.path == "/api/experimental/session":
        sessions = fetch_upstream_json("/api/session", directory)
        rows = sessions.get("data", []) if isinstance(sessions, dict) else sessions
        return rows if isinstance(rows, list) else []
    if parsed.path == "/api/lsp":
        return []
    # OpenChamber's V2 SDK probes /skill; OpenCode 2.0.14 does not expose
    # that endpoint yet. Local project skills are discovered by OpenChamber
    # itself, so an empty read-only list is the safe compatibility response.
    if parsed.path in {"/skill", "/api/skill"}:
        return []
    if parsed.path in {"/api/question", "/api/permission"}:
        return []
    if parsed.path == "/api/global/config":
        return {}
    return None


def unwrap_v2(path: str, method: str, body: bytes, content_type: str) -> bytes:
    if "json" not in content_type.lower():
        return body
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return body
    if not isinstance(payload, dict):
        return body

    # V2 list endpoints return {data, location}; OpenChamber's V1 client
    # expects the list at the response body root.
    if method == "GET" and (
        path.startswith("/api/agent") or path.startswith("/api/command") or
        path.startswith("/api/session") or path.startswith("/api/experimental/session")
    ) and isinstance(payload.get("data"), list):
        return json.dumps(payload["data"], separators=(",", ":")).encode()

    # V2 session.create returns {data: session}; V1 callers expect the session.
    if method == "POST" and path.startswith("/api/session") and isinstance(payload.get("data"), dict):
        return json.dumps(payload["data"], separators=(",", ":")).encode()
    return body


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        # Keep credentials and request headers out of logs.
        print(f"[adapter] {self.command} {self.path} {fmt % args}", file=sys.stderr, flush=True)

    def send_json(self, status: int, payload: object, *, authenticate: bool = False) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        if authenticate:
            self.send_header("WWW-Authenticate", 'Basic realm="OpenCode redteam"')
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()
        self.close_connection = True

    def authorized(self) -> bool:
        return hmac.compare_digest(self.headers.get("Authorization", ""), AUTH)

    def _forward(self):
        if not self.authorized():
            self.send_json(401, {"error": "unauthorized"}, authenticate=True)
            return
        parsed = urlsplit(self.path)
        path = parsed.path + (("?" + parsed.query) if parsed.query else "")
        length = int(self.headers.get("Content-Length", "0") or "0")
        request_body = self.rfile.read(length) if length else None
        compatibility = compatibility_response(self, parsed)
        if compatibility is not None:
            body = json.dumps(compatibility, separators=(",", ":")).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
            self.close_connection = True
            return
        headers = {}
        for key, value in self.headers.items():
            lower = key.lower()
            if lower in HOP_BY_HOP or lower in {"host", "content-length", "authorization"}:
                continue
            headers[key] = value
        headers["Authorization"] = AUTH
        headers["Accept-Encoding"] = "identity"
        if request_body is not None:
            headers["Content-Length"] = str(len(request_body))

        if UPSTREAM_SCHEME == "https":
            import ssl
            conn = http.client.HTTPSConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=30, context=ssl._create_unverified_context())
        else:
            conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=30)
        try:
            conn.request(self.command, path, body=request_body, headers=headers)
            response = conn.getresponse()
            content_type = response.getheader("Content-Type", "")
            response_headers = []
            for key, value in response.getheaders():
                if key.lower() not in HOP_BY_HOP and key.lower() not in {"content-length", "transfer-encoding"}:
                    response_headers.append((key, value))

            if content_type.lower().find("text/event-stream") >= 0:
                self.send_response(response.status)
                for key, value in response_headers:
                    self.send_header(key, value)
                self.send_header("Connection", "close")
                self.end_headers()
                while True:
                    chunk = response.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
                self.close_connection = True
                return

            body = response.read()
            if self.command == "POST" and parsed.path == "/api/session":
                try:
                    payload = json.loads(body.decode("utf-8"))
                    session = payload.get("data") if isinstance(payload, dict) else None
                    if isinstance(session, dict) and isinstance(session.get("id"), str):
                        SESSION_STATUS[session["id"]] = {"type": "idle"}
                        SESSION_DIRECTORY[session["id"]] = request_directory(self)
                except (UnicodeDecodeError, json.JSONDecodeError):
                    pass
            body = unwrap_v2(parsed.path, self.command, body, content_type)
            self.send_response(response.status)
            for key, value in response_headers:
                self.send_header(key, value)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
            self.close_connection = True
        finally:
            conn.close()

    do_GET = _forward
    do_POST = _forward
    do_PUT = _forward
    do_PATCH = _forward
    do_DELETE = _forward
    do_OPTIONS = _forward


def self_test() -> int:
    info = fetch_upstream_json("/api/info")
    agents = fetch_upstream_json("/api/agent", DEFAULT_PROJECT_DIR)
    if not isinstance(info, dict) or not isinstance(agents, dict) or not isinstance(agents.get("data"), list):
        print("[redteam-adapter] self-test failed: dedicated OpenCode is not reachable/authenticated", file=sys.stderr)
        return 1
    print(f"[redteam-adapter] self-test ok: {len(agents['data'])} agents available")
    return 0


if __name__ == "__main__":
    validate_configuration()
    if "--self-test" in sys.argv:
        raise SystemExit(self_test())
    port = int(os.environ.get("OPENCODE_ADAPTER_PORT", "4099"))
    if not 1 <= port <= 65535:
        fail("adapter port is out of range")
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"[redteam-adapter] listening on 127.0.0.1:{port} -> {UPSTREAM_HOST}:{UPSTREAM_PORT}", file=sys.stderr, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
