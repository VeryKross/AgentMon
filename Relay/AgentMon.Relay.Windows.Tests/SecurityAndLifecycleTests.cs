using System.Net;
using System.Security.Cryptography;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace AgentMon.Relay.Windows.Tests;

[TestClass]
public sealed class SecurityAndLifecycleTests
{
    [TestMethod]
    public void LoadOrCreate_Restart_PreservesHostTokenCertificateAndFingerprint()
    {
        using var temp = new TestDirectory();
        var store = new ProtectedSettingsStore(temp.Root);
        var original = store.LoadOrCreate();
        var loaded = new ProtectedSettingsStore(temp.Root).LoadOrCreate();
        using var originalCertificate = ProtectedSettingsStore.OpenCertificate(original);
        using var loadedCertificate = ProtectedSettingsStore.OpenCertificate(loaded);

        Assert.IsTrue(Guid.TryParse(original.HostId, out _));
        Assert.AreEqual(original.HostId, loaded.HostId);
        Assert.IsTrue(RelayServer.IsAuthorized("Bearer " + original.Token, loaded.Token));
        Assert.AreEqual(32, Convert.FromBase64String(loaded.Token).Length);
        Assert.AreEqual(ProtectedSettingsStore.Fingerprint(originalCertificate), ProtectedSettingsStore.Fingerprint(loadedCertificate));
        Assert.IsTrue(loadedCertificate.HasPrivateKey);
        StringAssert.Matches(ProtectedSettingsStore.Fingerprint(loadedCertificate),
            new System.Text.RegularExpressions.Regex(@"^([0-9a-f]{2}:){31}[0-9a-f]{2}$"));
        var stored = Encoding.UTF8.GetString(File.ReadAllBytes(store.SettingsPath));
        Assert.IsFalse(stored.Contains(original.Token, StringComparison.Ordinal));
        Assert.IsFalse(stored.Contains(Convert.ToBase64String(original.Certificate), StringComparison.Ordinal));
        Assert.IsFalse(stored.Contains(original.HostId, StringComparison.Ordinal));
    }

    [TestMethod]
    public void LoadOrCreate_Corruption_FailsWithoutReplacingIdentity()
    {
        using var temp = new TestDirectory();
        var store = new ProtectedSettingsStore(temp.Root);
        store.LoadOrCreate();
        byte[] broken = [1, 2, 3, 4];
        File.WriteAllBytes(store.SettingsPath, broken);
        Assert.ThrowsExactly<CryptographicException>(() => store.LoadOrCreate());
        CollectionAssert.AreEqual(broken, File.ReadAllBytes(store.SettingsPath));
    }

    [TestMethod]
    public void Save_ExplicitRotation_PreservesHostAndChangesOnlySelectedCredential()
    {
        using var temp = new TestDirectory();
        var store = new ProtectedSettingsStore(temp.Root);
        var original = store.LoadOrCreate();
        store.Save(original with { Token = ProtectedSettingsStore.NewToken() });
        var rotatedToken = store.LoadOrCreate();
        Assert.AreEqual(original.HostId, rotatedToken.HostId);
        Assert.IsFalse(RelayServer.IsAuthorized("Bearer " + original.Token, rotatedToken.Token));
        CollectionAssert.AreEqual(original.Certificate, rotatedToken.Certificate);
        store.Save(rotatedToken with { Certificate = ProtectedSettingsStore.NewCertificate() });
        var rotatedCertificate = store.LoadOrCreate();
        Assert.AreEqual(original.HostId, rotatedCertificate.HostId);
        Assert.IsTrue(RelayServer.IsAuthorized("Bearer " + rotatedToken.Token, rotatedCertificate.Token));
        using var before = ProtectedSettingsStore.OpenCertificate(original);
        using var after = ProtectedSettingsStore.OpenCertificate(rotatedCertificate);
        Assert.AreNotEqual(ProtectedSettingsStore.Fingerprint(before), ProtectedSettingsStore.Fingerprint(after));
        Assert.AreEqual(0, Directory.GetFiles(temp.Root, "*.tmp").Length);
    }

    [TestMethod]
    [DataRow("")]
    [DataRow("Bearer")]
    [DataRow("Basic secret")]
    [DataRow("Bearer wrong")]
    [DataRow("Bearer secret, Bearer secret")]
    public void IsAuthorized_MissingMalformedOrWrongToken_Rejects(string header)
        => Assert.IsFalse(RelayServer.IsAuthorized(header, "secret"));

    [TestMethod]
    public void Contains_SameSubnetOnly_RejectsUnrelatedAndHandlesHostPrefix()
    {
        var address = new PrivateAddress(IPAddress.Parse("192.168.1.10"), 24, 1);
        Assert.IsTrue(address.Contains(IPAddress.Parse("192.168.1.25")));
        Assert.IsFalse(address.Contains(IPAddress.Parse("192.168.2.25")));
        Assert.IsTrue((address with { PrefixLength = 32 }).Contains(address.Address));
        Assert.IsFalse((address with { PrefixLength = 32 }).Contains(IPAddress.Parse("192.168.1.25")));
    }

    [TestMethod]
    public void GetAddresses_NativeWindowsProfileQuery_OnlyReturnsExplicitIpv4Interfaces()
    {
        var addresses = new PrivateNetworkProvider().GetAddresses();
        Assert.IsTrue(addresses.All(address => address.InterfaceIndex > 0 &&
            address.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork &&
            !address.Address.Equals(IPAddress.Any) && !IPAddress.IsLoopback(address.Address)));
    }

    [TestMethod]
    public async Task Controller_NoPrivateNetwork_IndexesWithoutListeningAndStopsCleanly()
    {
        using var temp = new TestDirectory();
        var sessionRoot = temp.FilePath("sessions");
        Directory.CreateDirectory(sessionRoot);
        await using var controller = new RelayController(new ProtectedSettingsStore(temp.FilePath("state")),
            temp.Log, sessionRoot, new NoPrivateNetworks());
        await controller.StartAsync();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        while (controller.GetView().LastIndexedAt is null || controller.GetView().State == "Stopped")
            await Task.Delay(20, timeout.Token);
        Assert.AreEqual("Waiting for private network", controller.GetView().State);
        Assert.AreEqual(0, controller.GetView().Urls.Count);
        await controller.StopAsync();
        Assert.AreEqual("Stopped", controller.GetView().State);
        var indexed = controller.GetView().LastIndexedAt;
        await controller.SetDisplayNameAsync("Renamed PC");
        Assert.AreEqual("Renamed PC", controller.GetView().DisplayName);
        Assert.AreEqual(indexed, controller.GetView().LastIndexedAt);
        await controller.StartAsync();
        await controller.StopAsync();
    }

    private sealed class NoPrivateNetworks : IPrivateNetworkProvider
    {
        public IReadOnlyList<PrivateAddress> GetAddresses() => [];
    }
}
