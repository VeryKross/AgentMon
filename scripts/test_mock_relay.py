"""Regression coverage for the HTTPS fixture, without requiring Swift or macOS."""

from __future__ import annotations

import http.client
import importlib.util
import json
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location(
    "mock_relay", Path(__file__).with_name("mock-relay.py")
)
assert SPEC is not None and SPEC.loader is not None
MOCK_RELAY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOCK_RELAY)
TOKEN = "mock-relay-regression-token"


class MockRelayTests(unittest.TestCase):
    """Exercise real TLS while other clients leave connections idle."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="agentmon-mock-tests-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.cert = str(Path(cls.temporary.name, "cert.pem"))
        cls.key = str(Path(cls.temporary.name, "key.pem"))
        subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-days", "1", "-subj", "/CN=localhost",
                "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
                "-keyout", cls.key, "-out", cls.cert,
            ],
            check=True,
            capture_output=True,
        )
        cls.context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        cls.context.load_verify_locations(cls.cert)

    def setUp(self) -> None:
        self.server = MOCK_RELAY.create_server(self.cert, self.key, TOKEN, 0)
        self.address = self.server.server_address
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)

    def stop_server(self) -> None:
        """Stop and release the fixture even when an assertion fails."""
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)
        self.assertFalse(self.thread.is_alive())

    def request(self, token: str | None = TOKEN) -> tuple[int, bytes]:
        """Make a certificate-verified HTTPS request within a bounded timeout."""
        connection = http.client.HTTPSConnection(
            self.address[0], self.address[1], context=self.context, timeout=2
        )
        try:
            headers = {} if token is None else {"Authorization": f"Bearer {token}"}
            connection.request("GET", "/v1/status", headers=headers)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def test_idle_tcp_connection_does_not_block_tls_request(self) -> None:
        """A speculative connection must not serialize TLS handshakes in accept."""
        with socket.create_connection(self.address, timeout=2):
            status, body = self.request()
            self.assertEqual(200, status)
            self.assertEqual(1, json.loads(body)["protocolVersion"])

    def test_loopback_startup_does_not_resolve_dns(self) -> None:
        """A known loopback fixture must not wait for the runner's DNS resolver."""
        with mock.patch("socket.getfqdn", side_effect=AssertionError("Unexpected DNS lookup")):
            with MOCK_RELAY.create_server(self.cert, self.key, TOKEN, 0) as server:
                self.assertEqual("localhost", server.server_name)
                self.assertGreater(server.server_port, 0)

    def test_idle_tls_connection_does_not_block_http_request(self) -> None:
        """A completed handshake without HTTP data must not block other clients."""
        with socket.create_connection(self.address, timeout=2) as raw:
            with self.context.wrap_socket(raw, server_hostname="localhost"):
                self.assertEqual(200, self.request()[0])

    def test_authentication_and_snapshot(self) -> None:
        """The concurrency fix must preserve authentication and the snapshot."""
        self.assertEqual(401, self.request(None)[0])
        self.assertEqual(401, self.request("incorrect")[0])
        status, body = self.request()
        self.assertEqual(200, status)
        snapshot = json.loads(body)
        self.assertEqual("Mock Windows Desktop", snapshot["host"]["name"])
        self.assertEqual("working", snapshot["sessions"][0]["activity"])
        self.assertNotIn(TOKEN, body.decode("utf-8"))


if __name__ == "__main__":
    unittest.main()
