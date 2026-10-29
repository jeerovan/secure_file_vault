"""Temporary loopback-only input/progress transport for the Mac live UI test.

No credentials are embedded. One-use private inputs are supplied separately in
owner-only files and deleted before delivery. A per-run capability limits access;
neither requests nor values are logged. This is never linked into the product.
"""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import argparse
import json
import os
import secrets


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    directory = args.directory.resolve()
    capability = secrets.token_urlsafe(32)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, status, body=b""):
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            for kind in ("otp", "phrase"):
                if self.path == f"/{capability}/input/{kind}":
                    path = directory / f"private-{kind}.json"
                    if not path.exists():
                        self.reply(204)
                        return
                    data = path.read_bytes()
                    path.unlink()
                    self.reply(200, data)
                    return
            self.reply(404)

        def do_POST(self):
            if self.path != f"/{capability}/progress":
                self.reply(404)
                return
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size < 16384:
                self.reply(400)
                return
            data = json.loads(self.rfile.read(size))
            if not set(data) <= {"runId", "phase", "checks", "metrics", "time"}:
                self.reply(400)
                return
            path = directory / "progress.json"
            temporary = directory / "progress.partial"
            temporary.write_text(json.dumps(data))
            temporary.replace(path)
            self.reply(204)

    server = HTTPServer(("127.0.0.1", 0), Handler)
    url = f"http://127.0.0.1:{server.server_port}/{capability}"
    (directory / "control.json").write_text(json.dumps({"url": url}))
    print("Loopback test controller ready", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        for kind in ("otp", "phrase"):
            (directory / f"private-{kind}.json").unlink(missing_ok=True)
        (directory / "control.json").unlink(missing_ok=True)


if __name__ == "__main__":
    main()
