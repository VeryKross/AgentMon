using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;

namespace AgentMon.Relay.Windows;

internal sealed record RelaySettings(string HostId, string DisplayName, string Token, byte[] Certificate)
{
    public bool StartHidden { get; init; }
}

internal sealed class ProtectedSettingsStore(string directory)
{
    private readonly string path = Path.Combine(directory, "settings.dpapi");
    internal string SettingsPath => path;

    internal RelaySettings LoadOrCreate()
    {
        Directory.CreateDirectory(directory);
        if (File.Exists(path))
        {
            var protectedBytes = File.ReadAllBytes(path);
            var bytes = ProtectedData.Unprotect(protectedBytes, null, DataProtectionScope.CurrentUser);
            try
            {
                var settings = JsonSerializer.Deserialize<RelaySettings>(bytes)
                    ?? throw new InvalidDataException("Invalid relay settings.");
                Validate(settings);
                return settings;
            }
            finally
            {
                CryptographicOperations.ZeroMemory(bytes);
            }
        }

        var created = new RelaySettings(Guid.NewGuid().ToString(), Environment.MachineName,
            NewToken(), NewCertificate());
        Save(created);
        return created;
    }

    internal void Save(RelaySettings settings)
    {
        Validate(settings);
        Directory.CreateDirectory(directory);
        var plain = JsonSerializer.SerializeToUtf8Bytes(settings);
        byte[] encrypted;
        try
        {
            encrypted = ProtectedData.Protect(plain, null, DataProtectionScope.CurrentUser);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plain);
        }
        var temporary = Path.Combine(directory, $"settings-{Guid.NewGuid():N}.tmp");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                       4096, FileOptions.WriteThrough))
            {
                stream.Write(encrypted);
                stream.Flush(true);
            }
            File.Move(temporary, path, true);
        }
        finally
        {
            if (File.Exists(temporary))
                File.Delete(temporary);
        }
    }

    internal static string NewToken() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));

    internal static byte[] NewCertificate()
    {
        using var key = RSA.Create(3072);
        var request = new CertificateRequest("CN=AgentMon Relay", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
        request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(
            new OidCollection { new("1.3.6.1.5.5.7.3.1") }, true));
        var names = new SubjectAlternativeNameBuilder();
        names.AddDnsName("agentmon.local");
        request.CertificateExtensions.Add(names.Build());
        using var certificate = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(5));
        return certificate.Export(X509ContentType.Pfx);
    }

    internal static X509Certificate2 OpenCertificate(RelaySettings settings)
        // Schannel needs a Windows key container. UserKeySet is OS-protected and deleted on disposal;
        // only the DPAPI envelope is retained across launches.
        => new(settings.Certificate, (string?)null, X509KeyStorageFlags.UserKeySet);

    internal static string Fingerprint(X509Certificate2 certificate)
        => string.Join(':', certificate.GetCertHash(HashAlgorithmName.SHA256).Select(value => value.ToString("x2")));

    private static void Validate(RelaySettings settings)
    {
        if (!Guid.TryParse(settings.HostId, out _) || string.IsNullOrWhiteSpace(settings.DisplayName) ||
            settings.DisplayName.EnumerateRunes().Take(121).Count() > 120 || settings.DisplayName.Any(char.IsControl) ||
            string.IsNullOrEmpty(settings.Token) || settings.Certificate is null)
            throw new InvalidDataException("Invalid relay settings.");
        Span<byte> token = stackalloc byte[32];
        if (!Convert.TryFromBase64String(settings.Token, token, out var length) || length != 32)
            throw new InvalidDataException("Invalid pairing token.");
        using var certificate = OpenCertificate(settings);
        if (!certificate.HasPrivateKey)
            throw new InvalidDataException("Certificate has no private key.");
    }
}
