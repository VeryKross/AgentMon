[CmdletBinding()]
param(
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64',
    [switch]$Installer,
    [string]$CompilerPath,
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$relay = Join-Path $repo 'Relay'
if (-not $Version) {
    [xml]$project = Get-Content (Join-Path $relay 'AgentMon.Relay.Windows\AgentMon.Relay.Windows.csproj') -Raw
    $Version = [string]$project.Project.PropertyGroup.Version
}
if ($Version -notmatch '^\d+\.\d+\.\d+$' -or
    @($Version.Split('.') | Where-Object { [long]$_ -gt 65535 }).Count -gt 0) {
    throw 'The package version must contain three numeric components in the range 0..65535.'
}
$signing = [bool]$env:RELAY_SIGNING_PFX_BASE64
if ($signing -ne [bool]$env:RELAY_SIGNING_PFX_PASSWORD) {
    throw 'Incomplete signing credentials.'
}
$label = if ($signing) { 'signed' } else { 'unsigned' }
$stem = "AgentMonRelay-$Version-$Runtime-$label"
$output = Join-Path $repo "dist\$stem"
$archive = Join-Path $repo "dist\$stem.zip"
if ($Installer) {
    if (-not $CompilerPath) {
        $toolchain = Get-Content (Join-Path $relay 'installer-toolchain.json') -Raw | ConvertFrom-Json
        $CompilerPath = Join-Path $repo "dist\tools\inno-$($toolchain.version)\ISCC.exe"
    }
    if (-not (Test-Path -LiteralPath $CompilerPath)) {
        throw 'Pinned Inno Setup compiler is missing. Run .\scripts\install-inno-setup.ps1 first.'
    }
}

Push-Location $relay
try {
    dotnet restore .\AgentMon.Relay.Windows\AgentMon.Relay.Windows.csproj --locked-mode -p:SelfContained=true
    if ($LASTEXITCODE -ne 0) { throw 'Relay restore failed.' }

    dotnet publish .\AgentMon.Relay.Windows\AgentMon.Relay.Windows.csproj `
        -c Release -r $Runtime --self-contained true --no-restore `
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:EnableCompressionInSingleFile=true -p:PublishTrimmed=false `
        -p:DebugType=None -p:DebugSymbols=false -p:ContinuousIntegrationBuild=true `
        "-p:Version=$Version" "-p:PathMap=$repo=/_/AgentMon" `
        --output $output --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Relay publish failed.' }

    if ($signing) { & (Join-Path $PSScriptRoot 'sign-relay.ps1') -Path (Join-Path $output 'AgentMonRelay.exe') }
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

    if ($Installer) {
        $arguments = @(
            '/Qp', "/DAppVersion=$Version", "/DRuntime=$Runtime", "/DSigningLabel=$label",
            "/DSourceDir=$output", "/DArtifactDir=$(Join-Path $repo 'dist')"
        )
        if ($signing) {
            $signScript = Join-Path $PSScriptRoot 'sign-relay.ps1'
            $pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
            # $f and $q are Inno's filename/quote substitutions, not signing credentials.
            $signCommand = '$q' + $pwsh + '$q -NoProfile -NonInteractive -File $q' + $signScript + '$q -Path $f'
            $arguments += '/DSignRelay'
            $arguments += "/Srelay=$signCommand"
        }
        & $CompilerPath @arguments (Join-Path $relay 'Installer\AgentMonRelay.iss')
        if ($LASTEXITCODE -ne 0) { throw 'Relay installer compilation failed.' }
        $setup = Join-Path $repo "dist\$stem-Setup.exe"
        if (-not (Test-Path -LiteralPath $setup)) { throw 'Installer output is missing.' }
        if ($signing) {
            $signature = Get-AuthenticodeSignature -LiteralPath $setup
            if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) {
                throw 'Installer signature or timestamp is invalid.'
            }
        }
        $hash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $(Split-Path $setup -Leaf)" | Set-Content -LiteralPath "$setup.sha256" -Encoding ascii
        Write-Output "Installer: $setup"
    }
}
finally {
    Pop-Location
}
