[CmdletBinding()]
param([Parameter(Mandatory)][string]$Version)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $repo 'dist'
$expected = @('AgentMonRelay.exe', 'THIRD-PARTY-NOTICES.txt', 'Microsoft.NETCore.App-LICENSE.txt',
    'Microsoft.NETCore.App-NOTICES.txt', 'Microsoft.AspNetCore.App-NOTICES.txt',
    'Microsoft.WindowsDesktop.App-LICENSE.txt', 'README.md') | Sort-Object
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($runtime in @('win-x64', 'win-arm64')) {
    $label = if ($env:RELAY_SIGNING_PFX_BASE64) { 'signed' } else { 'unsigned' }
    $stem = "AgentMonRelay-$Version-$runtime-$label"
    foreach ($suffix in @('.zip', '-Setup.exe')) {
        $path = Join-Path $dist "$stem$suffix"
        $checksum = (Get-Content -LiteralPath "$path.sha256" -Raw).Trim()
        $expectedChecksum = "$((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant())  $(Split-Path $path -Leaf)"
        if ($checksum -cne $expectedChecksum) { throw "Artifact checksum mismatch: $stem$suffix" }
    }
    $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $dist "$stem.zip"))
    try {
        $names = @($archive.Entries.FullName | Sort-Object)
        if (Compare-Object $names $expected) { throw 'Unexpected or missing files in portable archive.' }
        foreach ($entry in $archive.Entries | Where-Object { $_.Name -ne 'AgentMonRelay.exe' }) {
            $reader = [IO.StreamReader]::new($entry.Open())
            try {
                if ($reader.ReadToEnd().Contains($repo)) { throw 'Archive contains an absolute build path.' }
            }
            finally { $reader.Dispose() }
        }
    }
    finally { $archive.Dispose() }
    $executable = Join-Path $dist "$stem\AgentMonRelay.exe"
    $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($executable))
    try {
        $reader.BaseStream.Position = 0x3c
        $offset = $reader.ReadInt32()
        $reader.BaseStream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550) { throw 'Invalid PE executable.' }
        $machine = $reader.ReadUInt16()
        $expectedMachine = if ($runtime -eq 'win-x64') { 0x8664 } else { 0xaa64 }
        if ($machine -ne $expectedMachine) { throw 'Artifact architecture mismatch.' }
    }
    finally { $reader.Dispose() }
    foreach ($file in @($executable, (Join-Path $dist "$stem-Setup.exe"))) {
        $signature = Get-AuthenticodeSignature -LiteralPath $file
        if ($label -eq 'signed' -and ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate)) {
            throw 'Signed artifact lacks a valid timestamped signature.'
        }
        if ($label -eq 'unsigned' -and $signature.Status -ne 'NotSigned') {
            throw 'Unsigned label does not match artifact signature state.'
        }
    }
}
Write-Output 'Artifact names, checksums, allowlisted content, architecture, and signing labels verified.'
