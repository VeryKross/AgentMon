[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OldSetup,
    [Parameter(Mandatory)][string]$NewSetup,
    [Parameter(Mandatory)][string]$ExpectedVersion,
    [Parameter(Mandatory)][string]$ExpectedUser,
    [Parameter(Mandatory)][string]$DeveloperRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($identity.Name.Split('\')[-1] -ne $ExpectedUser -or $ExpectedUser -notmatch '^AMRelayTest[0-9a-f]{8}$' -or
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Installer tests require their disposable non-administrator account.'
}
# Start-Process -Credential can inherit the launcher's profile environment.
# Resolve the loaded profile by the child's token SID before any installer or app starts.
$profileKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($identity.User.Value)"
$profile = [Environment]::ExpandEnvironmentVariables((Get-ItemPropertyValue $profileKey -Name ProfileImagePath))
if (-not $profile -or (Split-Path $profile -Leaf) -ne $ExpectedUser) {
    throw 'The disposable account profile could not be verified.'
}
$env:USERPROFILE = $profile
$env:USERNAME = $ExpectedUser
$env:APPDATA = Join-Path $profile 'AppData\Roaming'
$env:LOCALAPPDATA = Join-Path $profile 'AppData\Local'
$env:TEMP = Join-Path $env:LOCALAPPDATA 'Temp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
$localData = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::LocalApplicationData, [Environment+SpecialFolderOption]::Create)
if (-not $localData -or $localData -ne $env:LOCALAPPDATA) {
    $shellKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $shellLocal = Get-ItemPropertyValue $shellKey -Name 'Local AppData' -ErrorAction SilentlyContinue
    throw "Disposable LocalAppData resolution failed: actual='$localData'; expected='$env:LOCALAPPDATA'; registry='$shellLocal'."
}
$install = Join-Path $localData 'Programs\AgentMonRelay'
$data = Join-Path $localData 'AgentMonRelay'
$exe = Join-Path $install 'AgentMonRelay.exe'
$startupKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupName = 'AgentMon Relay'
$programs = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::Programs, [Environment+SpecialFolderOption]::Create)
$shortcut = Join-Path $programs 'AgentMon Relay.lnk'
$relayProcess = $null
$result = Join-Path $PSScriptRoot 'result.txt'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        $error = [InvalidOperationException]::new($Message)
        $error.Data['InstallerAssertion'] = $true
        throw $error
    }
}
function Run-Exe([string]$File, [string[]]$Arguments, [string]$Output = '') {
    $options = @{ FilePath = $File; ArgumentList = $Arguments; PassThru = $true }
    if ($Output) { $options.RedirectStandardOutput = $Output }
    $process = Start-Process @options
    if (-not $process.WaitForExit(60000)) {
        Stop-Process -Id $process.Id -Force
        Assert-True $false 'Test process exceeded its deadline.'
    }
    $process.Refresh()
    return $process.ExitCode
}
function Install-Setup([string]$File, [string]$Log, [bool]$ExpectSuccess = $true) {
    $code = Run-Exe $File @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$PSScriptRoot\$Log`"")
    Assert-True (($code -eq 0) -eq $ExpectSuccess) 'Unexpected installer result.'
}
function Get-Startup {
    if (-not (Test-Path $startupKey)) { return $null }
    return (Get-Item $startupKey).GetValue($startupName)
}
function Get-FirewallSnapshot {
    $policy = New-Object -ComObject HNetCfg.FwPolicy2
    try {
        return (@($policy.Rules | ForEach-Object {
            '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}' -f $_.Name, $_.ApplicationName,
                $_.Profiles, $_.Protocol, $_.LocalPorts, $_.RemoteAddresses, $_.Enabled, $_.Direction, $_.Action
        } | Sort-Object) -join "`n")
    }
    finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($policy) }
}
function Start-Relay {
    $script:relayProcess = Start-Process -FilePath $exe -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 200
        $script:relayProcess.Refresh()
        Assert-True (-not $script:relayProcess.HasExited) 'Installed relay exited unexpectedly.'
        if ((Test-Path (Join-Path $data 'settings.dpapi')) -and $script:relayProcess.MainWindowHandle -ne 0) { return }
    } while ([DateTime]::UtcNow -lt $deadline)
    Assert-True $false 'Installed tray UI did not become ready.'
}
function Stop-Relay {
    Assert-True ((Run-Exe $exe @('--shutdown')) -eq 0) 'Graceful relay shutdown failed.'
    Assert-True ($script:relayProcess.WaitForExit(25000)) 'Relay did not exit after shutdown.'
    Assert-True ($script:relayProcess.ExitCode -eq 0) 'Relay exited with an error.'
    $script:relayProcess.Dispose()
    $script:relayProcess = $null
}
function Uninstall([bool]$RemoveData) {
    $uninstallers = @(Get-ChildItem -LiteralPath $install -Filter 'unins*.exe')
    Assert-True ($uninstallers.Count -eq 1) 'Expected one registered uninstaller.'
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    if ($RemoveData) { $arguments += '/REMOVEUSERDATA=1' }
    Assert-True ((Run-Exe $uninstallers[0].FullName $arguments) -eq 0) 'Uninstall failed.'
    Assert-True (-not (Test-Path $exe)) 'Uninstall left the relay executable.'
    Assert-True (-not (Test-Path $shortcut)) 'Uninstall left the Start menu shortcut.'
    $entries = @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' |
        Where-Object { $_.GetValue('DisplayName') -like 'AgentMon Relay*' })
    Assert-True ($entries.Count -eq 0) 'Uninstall left its Installed Apps entry.'
}

try {
    Assert-True (-not (Test-Path $install) -and -not (Test-Path $data)) 'Test user is not clean.'
    $firewall = Get-FirewallSnapshot
    $networks = Get-NetConnectionProfile | Select-Object InterfaceIndex, NetworkCategory | ConvertTo-Json -Compress
    $roots = @(Get-ChildItem Cert:\CurrentUser\Root | Select-Object -ExpandProperty Thumbprint | Sort-Object) -join ','
    Install-Setup $OldSetup 'old-install.log'
    Assert-True ((Test-Path $exe) -and (Test-Path $shortcut)) 'Per-user files or shortcut missing.'
    Assert-True (-not (Test-Path $data)) 'Installer unexpectedly created pairing data.'
    Assert-True ($null -eq (Get-Startup)) 'Install silently enabled startup.'
    Assert-True ((Get-FirewallSnapshot) -eq $firewall) 'Install changed firewall rules.'
    Start-Relay
    $settingsPath = Join-Path $data 'settings.dpapi'
    $hash = (Get-FileHash $settingsPath -Algorithm SHA256).Hash
    Add-Type -AssemblyName System.Security
    $plain = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($settingsPath),
        $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    try { $settings = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json }
    finally { [Array]::Clear($plain, 0, $plain.Length) }
    $hostId = [guid]::Empty
    Assert-True ([guid]::TryParse($settings.HostId, [ref]$hostId)) 'Relay host identity is invalid.'
    Install-Setup $NewSetup 'busy-install.log' $false
    Assert-True ((Get-FileHash $settingsPath).Hash -eq $hash) 'Blocked upgrade changed pairing data.'
    Stop-Relay

    # Simulate the application's explicit startup opt-in, not an installer side effect.
    New-Item $startupKey -Force | Out-Null
    $startupCommand = "`"$exe`" --background"
    New-ItemProperty $startupKey -Name $startupName -Value $startupCommand -PropertyType String -Force | Out-Null
    Install-Setup $NewSetup 'upgrade.log'
    Assert-True ((Get-FileHash $settingsPath).Hash -eq $hash) 'Upgrade changed protected identity or credentials.'
    Assert-True ((Get-Startup) -eq $startupCommand) 'Upgrade changed existing startup choice.'
    $versionFile = Join-Path $PSScriptRoot 'version.txt'
    Assert-True ((Run-Exe $exe @('--version') $versionFile) -eq 0) 'Installed version command failed.'
    Assert-True ((Get-Content $versionFile -Raw).Trim() -eq $ExpectedVersion) 'Installed version is incorrect.'
    $entries = @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' |
        Where-Object { $_.GetValue('DisplayName') -like 'AgentMon Relay*' })
    Assert-True ($entries.Count -eq 1 -and $entries[0].GetValue('DisplayVersion') -eq $ExpectedVersion) 'Installed Apps version missing.'
    Start-Relay
    Assert-True ((Get-FileHash $settingsPath).Hash -eq $hash) 'Restart changed protected identity or credentials.'
    Stop-Relay
    Install-Setup $OldSetup 'downgrade.log' $false
    Assert-True ((Get-Item $exe).VersionInfo.FileVersion -eq "$ExpectedVersion.0") 'Downgrade replaced executable.'
    Uninstall $false
    Assert-True ((Get-FileHash $settingsPath).Hash -eq $hash) 'Default uninstall removed pairing data.'
    Assert-True ($null -eq (Get-Startup)) 'Uninstall left its owned startup command.'

    Install-Setup $NewSetup 'reinstall.log'
    Assert-True ($null -eq (Get-Startup)) 'Reinstall silently enabled startup.'
    Assert-True ((Get-FileHash $settingsPath).Hash -eq $hash) 'Reinstall replaced retained credentials.'
    $unrelated = '"C:\Unrelated\AgentMonRelay.exe" --background'
    New-ItemProperty $startupKey -Name $startupName -Value $unrelated -PropertyType String -Force | Out-Null
    Uninstall $true
    Assert-True (-not (Test-Path $data)) 'Explicit privacy reset left relay data.'
    Assert-True ((Get-Startup) -eq $unrelated) 'Uninstall removed unrelated startup value.'
    Assert-True ((Get-FirewallSnapshot) -eq $firewall) 'Installer lifecycle changed firewall rules.'
    Assert-True ((Get-NetConnectionProfile | Select-Object InterfaceIndex, NetworkCategory | ConvertTo-Json -Compress) -eq $networks) 'Network profiles changed.'
    Assert-True ((@(Get-ChildItem Cert:\CurrentUser\Root | Select-Object -ExpandProperty Thumbprint | Sort-Object) -join ',') -eq $roots) 'User trust roots changed.'
    foreach ($log in Get-ChildItem $PSScriptRoot -Filter '*.log') {
        $text = Get-Content $log.FullName -Raw
        Assert-True (-not $text.Contains($settings.Token) -and -not $text.Contains($settings.HostId)) 'Installer log contains pairing data.'
        Assert-True (-not $text.Contains($DeveloperRoot)) 'Installer log contains an absolute build path.'
    }
    'PASS: non-admin install, tray launch, version, busy protection, upgrade, downgrade rejection, default retention, explicit reset, owned startup cleanup, firewall/network/trust invariance, sanitized logs.' |
        Set-Content -LiteralPath $result
}
catch {
    # Report test assertions, not values from settings or arbitrary process output.
    $message = if ($_.Exception.Data['InstallerAssertion']) { $_.Exception.Message } else { $_.Exception.GetType().Name }
    "FAIL (line $($_.InvocationInfo.ScriptLineNumber)): $message" | Set-Content -LiteralPath $result
    exit 1
}
finally {
    if ($relayProcess -and -not $relayProcess.HasExited) {
        $shutdownCode = Run-Exe $exe @('--shutdown')
        if ($shutdownCode -ne 0) { Write-Warning 'Test relay did not shut down cleanly.' }
    }
}
