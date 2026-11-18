"""Attachment uploads and the login hand-off for the LearnHarness iOS app.

Why: the LearnHarness paperclip gives the agent a *file path* (the Mac app does that via
Electron). Paths on the phone don't exist on the server, so the iOS app first puts the file here,
in the home folder of the LearnHarness container, and gives the agent that path.

Only reachable through Caddy behind the Authelia login (/app-upload/* and /app-login). Never
overwrites an existing file and only accepts safe names.

A folder (paperclip → Folder, as on the Mac) arrives file by file as `<folder>/<sub>/<file>`:
every part must match NAME_RE, at most MAX_DEPTH deep.
"""
import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEST = "/uploads"                      # inside the LearnHarness container: /home/lh/Bijlagen
AGENT_PATH = "/home/lh/Bijlagen"
MAX_BYTES = 50 * 1024 * 1024           # keep in line with request_body max_size in the Caddyfile
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._ ()+-]{0,180}$")
MAX_DEPTH = 8


def safe_parts(name):
    """Path split into safe parts, or None. No empty parts, no "..", no absolute paths."""
    parts = name.split("/")
    if not 1 <= len(parts) <= MAX_DEPTH:
        return None
    for p in parts:
        if not NAME_RE.match(p) or ".." in p:
            return None
    return parts


class Handler(BaseHTTPRequestHandler):
    server_version = "lh-upload"

    def reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_PUT(self):
        prefix = "/app-upload/"
        if not self.path.startswith(prefix):
            return self.reply(404, {"error": "unknown path"})
        from urllib.parse import unquote
        name = unquote(self.path[len(prefix):])
        parts = safe_parts(name)
        if parts is None:
            return self.reply(400, {"error": "invalid file name"})
        name = "/".join(parts)
        try:
            length = int(self.headers.get("Content-Length", "-1"))
        except ValueError:
            length = -1
        if length < 0:
            return self.reply(411, {"error": "Content-Length missing"})
        if length > MAX_BYTES:
            return self.reply(413, {"error": "file larger than 50 MB"})
        target = os.path.join(DEST, *parts)
        if len(parts) > 1:
            # Intermediate folders may already exist (next file of the same folder). No symlinks
            # possible: only this service writes here, and only plain folders and files.
            os.makedirs(os.path.dirname(target), mode=0o750, exist_ok=True)
        if not os.path.realpath(target).startswith(os.path.realpath(DEST) + os.sep):
            return self.reply(400, {"error": "invalid file name"})
        try:
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o640)
        except FileExistsError:
            return self.reply(409, {"error": "already exists"})
        remaining = length
        try:
            with os.fdopen(fd, "wb") as f:
                while remaining > 0:
                    chunk = self.rfile.read(min(remaining, 1 << 20))
                    if not chunk:
                        raise ConnectionError("upload interrupted")
                    f.write(chunk)
                    remaining -= len(chunk)
        except Exception as e:  # don't leave half a file behind
            try:
                os.unlink(target)
            except OSError:
                pass
            return self.reply(500, {"error": str(e)})
        return self.reply(201, {"path": f"{AGENT_PATH}/{name}", "bytes": length})

    def do_GET(self):
        # /app-login: hands the Authelia session to the iOS app (ASWebAuthenticationSession catches
        # the redirect to learnharness://). A raw cookie in the URL breaks: Authelia session IDs
        # also contain `!#$%^*` (randomSessionChars in Authelia 4.39), and a `#` cut the URL off.
        # Hence here, percent-encoded. Only reachable after forward_auth, so the cookie is valid.
        if self.path.split("?")[0] != "/app-login":
            return self.reply(404, {"error": "unknown path"})
        from urllib.parse import quote
        value = ""
        for part in self.headers.get("Cookie", "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == "lh_session" and v:
                value = v
                break
        target = "learnharness://login" + (f"?session={quote(value, safe='')}" if value else "")
        self.send_response(302)
        self.send_header("Location", target)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, fmt, *args):  # no file names or sessions in the log, only the status
        if args and isinstance(args[0], str) and args[0].startswith("PUT"):
            args = ("PUT /app-upload/…",) + args[1:]
        super().log_message(fmt, *args)


if __name__ == "__main__":
    os.makedirs(DEST, exist_ok=True)
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
