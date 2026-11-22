#!/usr/bin/env python3
"""Serve the generated DataLens key set on the private network.

GET /<KEYS_TOKEN>/<name> returns the file <dir>/<name> for the fixed set of names below; every other path is a 404, and so is a
wrong token, so a service that does not know the token learns nothing. Binds dual-stack (IPv4 and IPv6): Railway's private
network may be either.
"""
import hmac
import os
import socket
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NAMES = {
    "auth_private", "auth_public", "bi_private", "bi_public", "ui_private", "ui_public",
    "temporal_private", "temporal_public", "crypto",
}
KEY_DIR = sys.argv[1]
TOKEN = os.environ.get("KEYS_TOKEN", "")
PORT = int(os.environ.get("KEYS_PORT", "8000"))
if len(TOKEN) < 24:
    sys.exit("KEYS_TOKEN missing or shorter than 24 characters: refusing to serve keys")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parts = self.path.strip("/").split("/")
        if len(parts) == 2 and hmac.compare_digest(parts[0], TOKEN) and parts[1] in NAMES:
            with open(os.path.join(KEY_DIR, parts[1]), "rb") as f:
                body = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_error(404)

    def log_message(self, *args):
        pass


class Server(ThreadingHTTPServer):
    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


try:
    server = Server(("::", PORT), Handler)
except OSError:
    ThreadingHTTPServer.address_family = socket.AF_INET
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
print(f"[keys-server] serving {len(NAMES)} keys on port {PORT}", flush=True)
server.serve_forever()
