#!/usr/bin/env python3

import argparse
import datetime
import http.server
import json
import logging
from pathlib import Path
import socket
import socketserver
import ssl
import sys


class RelayHandler(http.server.BaseHTTPRequestHandler):
    token = ""
    timeout = 5

    def do_GET(self):
        if self.path != "/v1/status":
            self.send_error(404)
            return
        if self.headers.get("Authorization") != f"Bearer {self.token}":
            self.send_error(401)
            return

        now = datetime.datetime.now(datetime.timezone.utc)
        payload = {
            "protocolVersion": 1,
            "relayVersion": "test",
            "generatedAt": now.isoformat().replace("+00:00", "Z"),
            "host": {
                "id": "mock-windows",
                "name": "Mock Windows Desktop",
                "platform": "windows",
            },
            "sessions": [
                {
                    "id": "mock-session",
                    "project": "AgentMon",
                    "task": "Verify the secure relay",
                    "repository": "VeryKross/AgentMon",
                    "branch": "main",
                    "activity": "working",
                    "updatedAt": now.isoformat().replace("+00:00", "Z"),
                }
            ],
        }
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


class RelayServer(http.server.ThreadingHTTPServer):
    """Keep connection errors useful without logging request data or tracebacks."""

    def server_bind(self) -> None:
        """Bind the known loopback fixture without HTTPServer's reverse DNS lookup."""
        socketserver.TCPServer.server_bind(self)
        self.server_name = "localhost"
        self.server_port = self.server_address[1]

    def handle_error(self, request: socket.socket, client_address: tuple) -> None:
        logging.warning("Mock relay connection failed (%s)", type(sys.exc_info()[1]).__name__)


def create_server(cert: str, key: str, token: str, port: int) -> RelayServer:
    """Create the loopback HTTPS fixture used by the Mac transport test."""
    RelayHandler.token = token
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    server = RelayServer(("127.0.0.1", port), RelayHandler)
    # Handshake on each handler's first read, not in the shared accept loop:
    # a speculative TCP connection may not send any TLS data.
    server.socket = context.wrap_socket(
        server.socket, server_side=True, do_handshake_on_connect=False
    )
    return server


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cert", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--port", type=int, default=47831)
    parser.add_argument("--ready-file", type=Path)
    args = parser.parse_args()

    with create_server(args.cert, args.key, args.token, args.port) as server:
        if args.ready_file is not None:
            args.ready_file.write_text(str(server.server_port), encoding="ascii")
        server.serve_forever()


if __name__ == "__main__":
    main()
