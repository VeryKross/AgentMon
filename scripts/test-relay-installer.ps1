[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OldSetup,
    [Parameter(Mandatory)][string]$NewSetup,
    [Parameter(Mandatory)][string]$ExpectedVersion
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run isolated installer tests from an elevated PowerShell; a temporary standard user is created and removed.'
}
$repo = Split-Path -Parent $PSScriptRoot
$name = 'AMRelayTest' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$stage = Join-Path $env:ProgramData "AgentMonRelayInstallerTests\$name"
$user = $null
$child = $null
try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    $password = ConvertTo-SecureString ("AMr!9" + [guid]::NewGuid().ToString('N')) -AsPlainText -Force
    $user = New-LocalUser -Name $name -Password $password -Description 'Temporary AgentMon installer acceptance account'
    Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $user
    $acl = Get-Acl -LiteralPath $stage
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $user.SID, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    Set-Acl -LiteralPath $stage -AclObject $acl
    Copy-Item -LiteralPath $OldSetup -Destination (Join-Path $stage 'old.exe')
    Copy-Item -LiteralPath $NewSetup -Destination (Join-Path $stage 'new.exe')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test-relay-installer-user.ps1') -Destination $stage
    $credential = [pscredential]::new("$env:COMPUTERNAME\$name", $password)
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = @('-NoProfile', '-NonInteractive', '-File', "`"$stage\test-relay-installer-user.ps1`"",
        '-OldSetup', "`"$stage\old.exe`"", '-NewSetup', "`"$stage\new.exe`"",
        '-ExpectedVersion', $ExpectedVersion, '-ExpectedUser', $name, '-DeveloperRoot', "`"$repo`"")
    $child = Start-Process -FilePath $windowsPowerShell -Credential $credential -LoadUserProfile `
        -WorkingDirectory $stage -ArgumentList $arguments -PassThru `
        -RedirectStandardError (Join-Path $stage 'launch-error.txt') -RedirectStandardOutput (Join-Path $stage 'launch-output.txt')
    if (-not $child.WaitForExit(600000)) { throw 'Isolated installer suite timed out.' }
    $child.Refresh()
    $result = Join-Path $stage 'result.txt'
    if (-not (Test-Path $result)) {
        Get-Content (Join-Path $stage 'launch-error.txt')
        throw "Isolated test user did not report a result (exit $($child.ExitCode))."
    }
    $summary = Get-Content $result -Raw
    Write-Output $summary
    if ($child.ExitCode -ne 0 -or -not $summary.StartsWith('PASS:')) { throw 'Installer acceptance failed.' }
}
finally {
    if ($child -and -not $child.HasExited) { Stop-Process -Id $child.Id -Force }
    if ($user) {
        # Match the exact disposable account SID, never a name/glob shared with real users.
        $profile = Get-CimInstance Win32_UserProfile -Filter "SID='$($user.SID.Value)'"
        if ($profile) {
            if ($profile.Loaded) { throw 'Disposable profile is still loaded; preserve it for diagnosis instead of deleting active data.' }
            $profile | Remove-CimInstance
        }
        Remove-LocalUser -SID $user.SID
    }
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
