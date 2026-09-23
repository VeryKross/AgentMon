#!/usr/bin/env python3

import argparse
import datetime
import http.server
import json
import ssl


class RelayHandler(http.server.BaseHTTPRequestHandler):
    token = ""

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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cert", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--port", type=int, default=47831)
    args = parser.parse_args()

    RelayHandler.token = args.token
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), RelayHandler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(args.cert, args.key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
