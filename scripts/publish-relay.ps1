[CmdletBinding()]
param(
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$relay = Join-Path $repo 'Relay'
$output = Join-Path $repo "dist\AgentMonRelay-$Runtime"
$archive = Join-Path $repo "dist\AgentMonRelay-$Runtime.zip"

Push-Location $relay
try {
    dotnet restore .\AgentMon.Relay.Windows\AgentMon.Relay.Windows.csproj --locked-mode -p:SelfContained=true
    if ($LASTEXITCODE -ne 0) { throw 'Relay restore failed.' }

    dotnet publish .\AgentMon.Relay.Windows\AgentMon.Relay.Windows.csproj `
        -c Release -r $Runtime --self-contained true --no-restore `
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:EnableCompressionInSingleFile=true -p:PublishTrimmed=false `
        -p:DebugType=None -p:DebugSymbols=false -p:ContinuousIntegrationBuild=true `
        --output $output --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Relay publish failed.' }

    Copy-Item (Join-Path $relay 'THIRD-PARTY-NOTICES.txt') $output
    Copy-Item (Join-Path $repo 'docs\windows-relay.md') (Join-Path $output 'README.md')
    # Package only named release files; never include an old build's credentials or debug artifacts.
    $files = @(
        (Join-Path $output 'AgentMonRelay.exe'),
        (Join-Path $output 'THIRD-PARTY-NOTICES.txt'),
        (Join-Path $output 'Microsoft.NETCore.App-LICENSE.txt'),
        (Join-Path $output 'Microsoft.NETCore.App-NOTICES.txt'),
        (Join-Path $output 'Microsoft.AspNetCore.App-NOTICES.txt'),
        (Join-Path $output 'Microsoft.WindowsDesktop.App-LICENSE.txt'),
        (Join-Path $output 'README.md')
    )
    Compress-Archive -LiteralPath $files -DestinationPath $archive -Force
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $(Split-Path $archive -Leaf)" | Set-Content -LiteralPath "$archive.sha256" -Encoding ascii
    Write-Output "Release archive: $archive"
    Write-Output "SHA-256: $archive.sha256"
}
finally {
    Pop-Location
}
