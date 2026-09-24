# AgentMon Relay Protocol v1

AgentMon Relay exposes privacy-minimal GitHub Copilot session status from another computer. Version 1 is intentionally read-only and contains no prompts, source code, tool arguments, tool output, or raw event records.

## Transport and authentication

- Listen on TCP port `47831` by default.
- Serve HTTPS only.
- Generate a persistent self-signed certificate on first launch.
- Display its lowercase SHA-256 certificate fingerprint in colon-delimited hexadecimal.
- Generate a cryptographically random bearer token of at least 256 bits.
- Show the token only during pairing or explicit regeneration.
- Bind only to private network profiles. Never create a public-network firewall rule.
- Require `Authorization: Bearer <token>` for every versioned endpoint.
- Advertise `_agentmon._tcp.local` with TXT record `version=1` when mDNS is available.

The macOS client pins the certificate fingerprint and stores the bearer token in Keychain. A changed certificate must fail closed until the user explicitly pairs again.

## Snapshot endpoint

`GET /v1/status`

Response headers:

```http
Content-Type: application/json
Cache-Control: no-store
```

Response body:

```json
{
  "protocolVersion": 1,
  "relayVersion": "0.1.0",
  "generatedAt": "2026-09-23T02:15:01.123Z",
  "host": {
    "id": "c87c6241-8ef1-492a-8cd6-f78ae969323c",
    "name": "Ken's Windows Desktop",
    "platform": "windows"
  },
  "sessions": [
    {
      "id": "01165fb9-796a-48da-bd1d-4e96100977d1",
      "project": "RestoreSDK",
      "task": "Investigate package compatibility",
      "repository": "VeryKross/RestoreSDK",
      "branch": "fix/package-compatibility",
      "activity": "working",
      "updatedAt": "2026-09-23T02:14:57.000Z"
    }
  ]
}
```

## Field requirements

- `protocolVersion`: integer, exactly `1`.
- `relayVersion`: relay application version.
- `generatedAt`: current UTC RFC 3339 timestamp. Fractional seconds are allowed.
- `host.id`: stable random UUID persisted by the relay; never derive it from a MAC address.
- `host.name`: user-editable display name.
- `host.platform`: `windows` for the first relay implementation.
- `sessions`: zero to 50 most relevant sessions.
- `sessions[].id`: the local Copilot session ID.
- `project`: short project name suitable for display; standalone chats with no
  project metadata use `Copilot Chat` instead of their generated workspace name.
- `task`: concise session title, maximum 120 Unicode scalar values.
- `repository` and `branch`: nullable strings.
- `activity`: one of `working`, `ready`, `attention`, or `offline`.
- `updatedAt`: UTC RFC 3339 timestamp.

Unknown JSON fields must be ignored. Missing required fields must reject the snapshot. AgentMon rejects snapshots more than 30 seconds old.

## Activity semantics

- `working`: an assistant turn is active.
- `attention`: the session is blocked on user input.
- `ready`: the session process is alive but no turn or question is active.
- `offline`: the indexed session is recent but its process is no longer alive.

Match AgentMon's local adapter behavior in `CopilotSessionMonitor.swift`: inspect only workspace metadata, process lock/PID state, and event **types** needed to derive activity. Do not transmit event content.

## HTTP behavior

- `200`: valid snapshot.
- `401`: missing or invalid bearer token.
- `404`: unknown route.
- `405`: unsupported method.
- `426`: relay cannot serve protocol v1.
- `429`: client is polling too quickly.
- `500`: internal failure without sensitive details.

The response must complete within two seconds under normal local conditions.

## Privacy and logs

Logs may contain timestamps, endpoint names, counts, status codes, and exception types. They must not contain bearer tokens, prompts, source paths outside the project root, source code, tool payloads, or raw Copilot events.
