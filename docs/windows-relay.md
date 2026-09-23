# AgentMon Relay for Windows

AgentMon Relay is a read-only Windows tray companion for the macOS AgentMon
dashboard. It implements protocol v1 without changing the Mac contract.
Windows 10/11 x64 is the initial target; an ARM64 build is also available from
the same source. The relay requires a signed-in Windows user, not a service
account. It does not control Copilot.

## Install and run

1. Obtain `AgentMonRelay-<version>-win-x64-unsigned-Setup.exe` and its `.sha256`
   from the [Windows Relay workflow artifacts](https://github.com/VeryKross/AgentMon/actions/workflows/windows-relay.yml).
   ARM64 computers use the `win-arm64` installer. Approved signed builds use
   `signed` instead of `unsigned` in their filenames.
2. Check that `Get-FileHash -Algorithm SHA256 .\AgentMonRelay-<version>-win-x64-unsigned-Setup.exe`
   matches the adjacent checksum file. A checksum detects corruption; it does
   not establish publisher trust. Run the installer as your normal Windows
   user, not as another administrator.
3. Setup installs into `%LOCALAPPDATA%\Programs\AgentMonRelay` without requesting
   administrator rights, adds **AgentMon Relay** to Start and Installed Apps,
   and displays the installed version. The completion page offers an unchecked
   **Launch AgentMon Relay** action; alternatively launch it from Start.
   No separately installed .NET runtime is needed.
   Unsigned artifacts are development/release candidates, not trusted signed
   releases. Follow your organization's software approval policy; do not
   disable SmartScreen, Defender, or other security controls to run them.
4. On a trusted LAN, set the Windows connection's network profile to
   **Private** in Windows Settings. Do not mark an untrusted network Private.
5. Use **Configure private firewall** in the relay. This explicit operation
   requests administrator approval and creates one inbound TCP rule for
   this exact executable, port `47831`, Private profile, and `LocalSubnet`
   remote addresses only. Do not approve a separate broad/Public rule from a
   Windows firewall prompt.

Installation never changes a network profile, firewall rule, startup choice,
or certificate trust store. Only the explicit in-app firewall action requests
administrator approval. The installer adds no service, scheduled task, or driver.

### Portable alternative

The versioned `AgentMonRelay-<version>-win-x64-unsigned.zip` (or `win-arm64`,
or `signed`) and its `.sha256` remain supported. Verify the checksum, extract
to a stable per-user folder, keep all included notices, and run
`AgentMonRelay.exe`. Moving a portable executable requires updating startup
and configuring its narrowly scoped firewall rule again. The installer can
adopt the default per-user folder after you quit the portable relay; it never
reads or changes the separate pairing-data directory during installation.

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

## Startup and tray behavior

Closing the management window hides it in the notification area; it does not
quit the relay. Double-click the tray icon to reopen it. **Quit** stops polling,
shuts down HTTPS, withdraws discovery, and exits.

The application and installer share AgentMon's one-bit retro computer icon.
The tray uses shape rather than color for status: empty ports when stopped,
a solid connection when running, a dashed connection while waiting for a
private network, and a broken connection on error. The same status is stated
in text. Button sizes follow font metrics at high DPI rather than fixed heights.

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
# Pin and install the open-source compiler for installer builds:
.\scripts\install-inno-setup.ps1
.\scripts\publish-relay.ps1 -Installer
.\scripts\publish-relay.ps1 -Runtime win-arm64 -Installer
.\scripts\test-relay-artifacts.ps1 -Version 0.2.0
```

The release command uses pinned packages, locked restore, the pinned SDK,
deterministic compilation, and self-contained single-file publishing. Outputs
are under `dist\AgentMonRelay-<version>-<runtime>-<signed|unsigned>`, plus a ZIP,
an optional `-Setup.exe`, and a SHA-256 checksum for each artifact.
Building packages does not install or launch the relay or change its startup
or firewall settings. Inno Setup 6.7.3 is pinned by download URL and SHA-256
in `Relay\installer-toolchain.json`; its source and build configuration are
committed, not proprietary tooling. Inno Setup was selected for mature
non-administrator installation, native accessible wizard controls, built-in
uninstall registration, and scriptable x64/ARM64 packaging.
The ZIP's timestamps/checksum can change between builds; reproducibility here
means the same pinned build inputs, not byte-identical ZIP containers.

The editable icon source and deterministic Windows ICO generator live in
`Relay\AgentMon.Relay.Windows\Assets`. Run `Generate-RelayIcons.ps1` there when
changing the artwork; the checked-in ICOs contain 16, 20, 24, 32, 48, 64, and
256-pixel frames and need no external asset service.

Windows CI runs native parsing, process-lock, DPAPI, network-profile,
redaction, HTTPS/pinning/authentication, freshness, rate-limit, and shutdown
coverage and publishes installers and ZIPs for both architectures. It also
creates a disposable standard Windows user to exercise clean installation,
tray startup, version reporting, blocked busy upgrades, in-place upgrade and
downgrade rejection, preserved credentials, owned startup cleanup, default
uninstall, explicit privacy reset, and unchanged network/firewall/trust settings.
The temporary user and its profile are removed afterward. Run this harness
only from an elevated PowerShell 7.4 or newer; it must never target an existing
user's profile or change execution policy to run:

```powershell
.\scripts\test-relay-installer.ps1 -OldSetup <older-fixture-Setup.exe> `
    -NewSetup <current-Setup.exe> -ExpectedVersion 0.2.0
```

CI builds the older fixture from the current source with `-Version 0.1.9`;
that synthetic test artifact is not uploaded as a release. ARM64 execution still requires
an ARM64 Windows machine. The existing macOS CI runs `swift test` and
`make test-relay`; real paired Windows/Mac acceptance must be performed on
the two computers.

### Optional Authenticode signing

Normal builds need no signing credentials and are explicitly labeled `unsigned`.
To sign, provide `RELAY_SIGNING_PFX_BASE64` and `RELAY_SIGNING_PFX_PASSWORD`
through protected CI secrets, plus `RELAY_SIGNING_TIMESTAMP_URL` as a CI variable
(default `http://timestamp.digicert.com`). Do not put credential values into
commands, repository files, or logs. Pull-request builds never receive these
secrets. The signing helper loads the PFX in memory using a temporary
Windows-protected key container; no plaintext PFX is written to disk.

The application, installer, and embedded uninstaller are SHA-256 Authenticode
signed and timestamped. Invalid signatures or missing timestamps fail the build
rather than producing a falsely labeled signed package. Signing requires a
valid code-signing certificate whose chain Windows trusts; setup does not add
trust roots. Publisher reputation and your organization's policy still apply
even to correctly signed packages.

## Upgrade and removal

Quit from the relay tray menu, then run the newer installer as the same Windows
user. Setup refuses downgrades and refuses to replace a running relay; it does
not force-kill the app or defer replacement to reboot. The stable installation
path preserves an existing opt-in startup command and firewall rule.
`%LOCALAPPDATA%\AgentMonRelay\settings.dpapi` is not an installer payload and is
never replaced during upgrade: host identity, token, certificate, and Mac
pairing remain intact. Same-version repairs are allowed.

Use **Settings > Apps > Installed Apps > AgentMon Relay > Uninstall**. Quit the
relay first if prompted. Uninstall removes only its installed files, shortcut,
and matching opt-in startup command. If its exact executable/TCP 47831/Private/
LocalSubnet firewall rule exists, cleanup requests administrator approval to
remove it. A denied elevation or ambiguous duplicate rule aborts removal with
an explanation rather than deleting unrelated rules. An unrelated startup
command is left untouched.

The uninstaller asks whether to remove pairing identity, credentials, and logs.
**No is the default**: preserving these allows reinstallation without breaking
pairing. Choose **Yes** only for a complete privacy reset. This removes only
`%LOCALAPPDATA%\AgentMonRelay`; redirected data directories/junctions are refused.
It cannot be undone, and reinstalling creates a new identity requiring re-pairing.

Silent uninstall preserves data; `/REMOVEUSERDATA=1` explicitly requests the
complete-removal path. Silent cleanup fails if firewall removal requires
elevation, rather than hiding an approval prompt. Remove the exact relay rule
with approved administrator access first, or use interactive uninstall.

For portable removal, quit the app, then run the executable's
`--uninstall-cleanup` command from its existing directory to remove only its
owned startup/firewall integration. Run `--remove-user-data` only if you
explicitly want to destroy pairing and logs, then remove the portable files.
`--shutdown` requests a graceful exit of the current user's running relay;
`--version` reports its version without opening the UI or creating settings.
If the executable has already been deleted, manually remove only its matching
`AgentMon Relay` value under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
and its exact firewall rule. If a runtime extraction cache remains, remove only
`%TEMP%\.net\AgentMonRelay`, not the shared `.net` directory. Disable Windows
Relay on the Mac and remove its saved Keychain pairing token if desired.
