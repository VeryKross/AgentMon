[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$toolchain = Get-Content (Join-Path $repo 'Relay\installer-toolchain.json') -Raw | ConvertFrom-Json
$tools = Join-Path $repo 'dist\tools'
$destination = Join-Path $tools "inno-$($toolchain.version)"
$compiler = Join-Path $destination 'ISCC.exe'
if (Test-Path -LiteralPath $compiler) { Write-Output $compiler; return }
New-Item -ItemType Directory -Path $tools -Force | Out-Null
$download = Join-Path $tools "innosetup-$($toolchain.version).exe"
Invoke-WebRequest -Uri $toolchain.url -OutFile $download
if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ine $toolchain.sha256) {
    throw 'Inno Setup download checksum mismatch.'
}
$process = Start-Process -FilePath $download -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER',
    "/DIR=`"$destination`"", '/NOICONS', '/MERGETASKS=!fileassoc'
) -Wait -PassThru
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $compiler)) {
    throw 'Inno Setup tool installation failed.'
}
Remove-Item -LiteralPath $download
Write-Output $compiler
