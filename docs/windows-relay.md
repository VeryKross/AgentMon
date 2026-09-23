# AgentMon Relay for Windows

AgentMon Relay is a read-only Windows tray companion for the macOS AgentMon
dashboard. It implements protocol v1 without changing the Mac contract.
Windows 10/11 x64 is the initial target; an ARM64 build is also available from
the same source. The relay requires a signed-in Windows user, not a service
account. It does not control Copilot.

## Install and run

1. Obtain `AgentMonRelay-win-x64.zip` and its `.sha256` from the Windows Relay
   workflow artifacts, or build them using the command below.
2. Verify the archive with `Get-FileHash -Algorithm SHA256`, then extract it
   into a stable per-user folder such as
   `%LOCALAPPDATA%\Programs\AgentMonRelay`. Keep the included notices.
3. Run `AgentMonRelay.exe`. No separately installed .NET runtime is needed.
   The initial portable build is unsigned; follow your organization's software
   approval policy rather than disabling Windows security features.
4. On a trusted LAN, set the Windows connection's network profile to
   **Private** in Windows Settings. Do not mark an untrusted network Private.
5. Use **Configure private firewall** in the relay. This explicit operation
   requests administrator approval and creates one inbound TCP rule for
   this exact executable, port `47831`, Private profile, and `LocalSubnet`
   remote addresses only. Do not approve a separate broad/Public rule from a
   Windows firewall prompt.

No startup entry or firewall exception is installed automatically. A portable
archive is used instead of an installer so installation never silently grants
network access. Moving the executable requires updating startup and configuring
the firewall rule again.

## Pair with the Mac

Open **AgentMon Settings > Windows Relay** on the Mac. Copy a listening HTTPS
URL from the Windows relay, the certificate's lowercase SHA-256 fingerprint,
and the pairing token. Use **Reveal and copy token** only when ready to pair.
Compare the fingerprint with the one displayed on the Windows computer through
a trusted channel; discovery is not a trust decision.

The token grants read access to session metadata. The relay warns before
copying it because other applications, clipboard history, and clipboard sync
can read the clipboard. Its display is hidden after 30 seconds or when the
window closes. The app does not later erase a clipboard that may contain
something else.

The Mac stores the token in Keychain and pins the certificate. It must reject
a changed certificate. **Rotate token** and **Rotate certificate** are explicit
actions with warnings; update all paired Macs afterward. Neither credential
changes during an ordinary restart or application upgrade. The self-signed
certificate expires after five years; rotate and re-pair before expiration.
Do not install this certificate as a broadly trusted root.

The Windows sessions appear alongside local Mac sessions, labeled with the
Windows host and branch. **Stop relay** or **Quit** makes the Mac report
`REMOTE OFFLINE` without affecting local sessions.
If a worktree session has no repository in its workspace metadata, the relay
uses Git's worktree pointer to show the parent project's name rather than the
worktree branch as the project label. The session title remains on the next
line, and the branch remains in the host line.

## Startup and tray behavior

Closing the management window hides it in the notification area; it does not
quit the relay. Double-click the tray icon to reopen it. **Quit** stops polling,
shuts down HTTPS, withdraws discovery, and exits.

**Start AgentMon Relay when I sign in** is opt-in. It writes a quoted executable
path plus `--background` into the current user's Windows `Run` registry key.
The background launch starts the relay without opening its window. No machine
startup task, scheduled task, or Windows service is installed.

## Network restrictions and discovery

The listener uses only explicit IPv4 addresses belonging to Windows **Private**
network profiles. It does not bind wildcard addresses, loopback, Domain, or
Public profiles. A private-looking IP address alone is not sufficient.
Only on-link subnet clients are accepted. IPv6-only LANs and routed/VPN clients
outside the interface's subnet are not supported in this initial version.

Profiles and addresses are refreshed every three seconds; HTTPS connections
and requests also recheck the profile and subnet, including keep-alive requests.
If Windows cannot determine the profile, access fails closed. Changing networks
may change the displayed URL; update the Mac's URL, not its saved identity.

The relay uses Windows DNS-SD to advertise `_agentmon._tcp.local` with
`version=1` on the selected private interfaces. It does not advertise the token,
fingerprint, session data, or Windows user identity. Windows DNS Client service,
multicast policy, and network isolation can prevent discovery. The tray reports
discovery availability; manual URL/fingerprint/token pairing remains independent
of it. The TCP firewall setup does not add broad UDP or Public-profile rules.

TLS 1.2 and TLS 1.3 are the only enabled versions (availability also depends on
Windows). Requests require a bearer token. The relay allows at most 20 requests
per second across clients, returns `429` with `Retry-After: 1` for excess
requests, and never queues abusive polling. Normal dashboard polling is well
below this limit.

## Data read, transmitted, and retained

The relay reads `%USERPROFILE%\.copilot\session-state` every three seconds:

- Top-level workspace ID, working directory, repository, branch, title, and
  modification time from `workspace.yaml` (bounded to 256 KiB).
- At most the last 128 KiB of `events.jsonl`. Only event types, tool names, and
  tool-call IDs are used to derive state. Partial JSON lines are ignored.
- `inuse.<pid>.lock` entries, with an actual process-liveness check.

`pending-session*`, hidden directories, and directory reparse points are
excluded. Only attention, working, ready, and recent offline sessions are
returned, ordered by that priority and then recency, capped at 50. Offline
sessions older than 24 hours are excluded. As in the Mac adapter, a live
session with no recent event activity for 15 minutes is treated as ready.

HTTPS responses contain only the protocol's host/session IDs, host display
name, platform, project basename, workspace title (maximum 120 Unicode scalars),
repository, branch, state, and timestamps. Workspace titles and repository or
branch names are intentionally shared metadata and may themselves contain
sensitive names; choose those names accordingly. Full working directories,
prompts, user/assistant messages, source code, tool arguments/output, and raw
events are never included. No telemetry, cloud service, or remote-control API
is provided.

The host UUID, display name, 256-bit random token, and certificate/private key
are saved atomically in `%LOCALAPPDATA%\AgentMonRelay\settings.dpapi`, encrypted
with Windows DPAPI for the current user. Schannel uses a temporary, Windows-
protected current-user key container while running. No plaintext PFX/token
file is written. Copying the settings file to a different user or computer is
not a supported backup or transfer mechanism.

Logs in `%LOCALAPPDATA%\AgentMonRelay\Logs` contain only timestamps, fixed
operation names, and exception type names. They rotate at about 1 MiB, retaining
one previous log. They never include exception messages, raw request URLs,
credentials, paths, or event contents.

## Freshness and troubleshooting

`generatedAt` is the start time of the last completely successful scan, **not**
the time an HTTP request arrived. A transient locked, replaced, invalid, or
partially written workspace file leaves the entire prior snapshot intact.
The management window reports the indexing failure and its original time.
The Mac rejects snapshots older than 30 seconds; stale data cannot masquerade
as a healthy connection. Before any successful scan, the endpoint returns a
sanitized `500`. A missing Copilot directory before first use is a valid empty
snapshot.

| Symptom | Action |
| --- | --- |
| Waiting for private network | Connect to a trusted IPv4 LAN and verify its Windows profile is Private. |
| Listener error | Check port 47831 is unused, network policy permits listening, and the certificate has not expired. Open logs for the exception type. |
| No sessions | Run Copilot under the same Windows user. Check that it writes the documented local session-state format. |
| Indexing error / remote offline | Wait for a write to finish; check access to Copilot files and malformed workspace metadata. The relay never fabricates a fresh timestamp. |
| Mac cannot connect | Check the selected IP, local-subnet reachability, Private-only firewall rule, and access-point client isolation. Never port-forward the relay. |
| `401` | Re-copy the pairing token securely; update it after rotation. |
| Certificate mismatch | Verify the fingerprint on Windows and explicitly re-pair. Do not disable pinning. |
| `426` | Use a Mac client and relay that both support v1. Unknown routes return `404`; non-GET status requests return `405`. |
| Settings cannot be opened | Check Windows user/profile permissions. Corrupt or undecryptable settings fail closed; identity is never silently regenerated. |
| mDNS unavailable | Use manual pairing. Discovery is optional and does not weaken authentication. |

## Build and check

Install the released .NET SDK pinned in `Relay\global.json`. From the repository
root in PowerShell:

```powershell
Push-Location .\Relay
dotnet restore .\AgentMon.Relay.Windows.Tests\AgentMon.Relay.Windows.Tests.csproj --locked-mode
dotnet test .\AgentMon.Relay.Windows.Tests\AgentMon.Relay.Windows.Tests.csproj -c Release --no-restore
# Optional native multicast acceptance on a trusted Private LAN (not required by CI):
$env:AGENTMON_TEST_MDNS = '1'
dotnet test .\AgentMon.Relay.Windows.Tests\AgentMon.Relay.Windows.Tests.csproj --filter TestCategory=NetworkDiscovery
Remove-Item Env:\AGENTMON_TEST_MDNS
Pop-Location
.\scripts\publish-relay.ps1
# Optional alternate architecture:
.\scripts\publish-relay.ps1 -Runtime win-arm64
```

The release command uses pinned packages, locked restore, the pinned SDK,
deterministic compilation, and self-contained single-file publishing. Outputs
are under `dist\AgentMonRelay-win-x64` plus a ZIP and SHA-256 checksum.
It does not sign, install, launch, register startup, or change the firewall.
The ZIP's timestamps/checksum can change between builds; reproducibility here
means the same pinned build inputs, not byte-identical ZIP containers.

Windows CI runs native parsing, process-lock, DPAPI, network-profile,
redaction, HTTPS/pinning/authentication, freshness, rate-limit, and shutdown
coverage and publishes both architectures. ARM64 execution still requires
an ARM64 Windows machine. The existing macOS CI runs `swift test` and
`make test-relay`; real paired Windows/Mac acceptance must be performed on
the two computers.

## Upgrade and complete removal

To upgrade, quit the relay, replace the executable in the same installation
folder, and relaunch. Do not remove `settings.dpapi`; keeping it preserves the
host ID and pairing.

To remove:

1. Uncheck **Start AgentMon Relay when I sign in**, then **Quit**.
2. In Windows Defender Firewall with Advanced Security, remove the inbound
   rule named **AgentMon Relay (Private network only)**. Administrator approval
   is required.
3. Delete the relay's installation folder and
   `%LOCALAPPDATA%\AgentMonRelay` (this deliberately destroys pairing and logs).
   If the single-file runtime extraction cache remains, remove only
   `%TEMP%\.net\AgentMonRelay`, not the shared `.net` directory.
4. Disable Windows Relay on the Mac and remove its saved pairing token if
   desired.

If the executable was removed before startup was disabled, delete only the
`AgentMon Relay` value under
`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. Reinstalling after deleting
settings creates a new host ID, token, and certificate and requires re-pairing.
