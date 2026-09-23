[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)

$ErrorActionPreference = 'Stop'
if (-not $env:RELAY_SIGNING_PFX_BASE64 -or -not $env:RELAY_SIGNING_PFX_PASSWORD) {
    throw 'Both signing credential environment variables are required.'
}
if (-not $env:RELAY_SIGNING_TIMESTAMP_URL) {
    throw 'A signing timestamp URL is required.'
}
$timestamp = [uri]$env:RELAY_SIGNING_TIMESTAMP_URL
if ($timestamp.Scheme -notin @('http', 'https') -or $timestamp.UserInfo) {
    throw 'Use an HTTP(S) timestamp service without embedded credentials.'
}
$certificate = $null
$bytes = $null
try {
    $bytes = [Convert]::FromBase64String($env:RELAY_SIGNING_PFX_BASE64)
    # The Windows-protected temporary key container is removed on disposal.
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $bytes, $env:RELAY_SIGNING_PFX_PASSWORD,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet)
    if (-not $certificate.HasPrivateKey) { throw 'The signing certificate has no private key.' }
    $signature = Set-AuthenticodeSignature -LiteralPath $Path -Certificate $certificate `
        -HashAlgorithm SHA256 -TimestampServer $timestamp.AbsoluteUri
    if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) {
        throw 'Authenticode signing or timestamp verification failed.'
    }
}
catch {
    # Do not include certificate-import inputs or tool diagnostics in CI output.
    throw "Artifact signing failed ($($_.Exception.GetType().Name))."
}
finally {
    if ($certificate) { $certificate.Dispose() }
    if ($bytes) { [Array]::Clear($bytes, 0, $bytes.Length) }
}
