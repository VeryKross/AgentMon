#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d)
TOKEN="agentmon-test-token"
READY_FILE="$TEMP_DIR/relay-port"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -nodes \
  -days 1 \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
  -keyout "$TEMP_DIR/key.pem" \
  -out "$TEMP_DIR/cert.pem" \
  >/dev/null 2>&1

FINGERPRINT=$(
  openssl x509 -in "$TEMP_DIR/cert.pem" -outform der |
    shasum -a 256 |
    awk '{print $1}'
)

python3 "$ROOT_DIR/scripts/mock-relay.py" \
  --cert "$TEMP_DIR/cert.pem" \
  --key "$TEMP_DIR/key.pem" \
  --token "$TOKEN" \
  --port 0 \
  --ready-file "$READY_FILE" &
SERVER_PID=$!

ATTEMPTS=0
while [ ! -s "$READY_FILE" ]; do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "Mock relay exited before becoming ready." >&2
    exit 1
  fi
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ "$ATTEMPTS" -ge 50 ]; then
    echo "Mock relay did not become ready within five seconds." >&2
    exit 1
  fi
  sleep 0.1
done
PORT=$(cat "$READY_FILE")

curl --silent --show-error --fail --noproxy '*' \
  --max-time 5 --cacert "$TEMP_DIR/cert.pem" \
  --header "Authorization: Bearer $TOKEN" \
  "https://127.0.0.1:$PORT/v1/status" >/dev/null

cd "$ROOT_DIR"
AGENTMON_TEST_RELAY_URL="https://127.0.0.1:$PORT" \
AGENTMON_TEST_RELAY_TOKEN="$TOKEN" \
AGENTMON_TEST_RELAY_FINGERPRINT="$FINGERPRINT" \
swift test --filter fetchesPinnedRelaySnapshot
