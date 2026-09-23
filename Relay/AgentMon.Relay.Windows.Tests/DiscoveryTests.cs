using System.Net;
using System.Net.Sockets;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace AgentMon.Relay.Windows.Tests;

[TestClass]
public sealed class DiscoveryTests
{
    [TestMethod]
    public async Task Start_NoPrivateInterfaces_DoesNotAdvertise()
    {
        using var temp = new TestDirectory();
        await using var discovery = new MdnsAdvertisement(temp.Log);
        await discovery.StartAsync(Guid.NewGuid().ToString(), []);
        Assert.AreEqual("mDNS unavailable on some interfaces; use manual pairing", discovery.Status);
    }

    [TestMethod]
    [TestCategory("NetworkDiscovery")]
    public async Task NativeDiscovery_PrivateLan_AdvertisesVersionAndWithdrawsOnStop()
    {
        if (Environment.GetEnvironmentVariable("AGENTMON_TEST_MDNS") != "1")
            Assert.Inconclusive("Opt-in LAN test: set AGENTMON_TEST_MDNS=1 on a trusted Private network.");
        var address = new PrivateNetworkProvider().GetAddresses().FirstOrDefault();
        Assert.IsNotNull(address, "This opt-in test requires a Private IPv4 LAN.");
        using var temp = new TestDirectory();
        await using var discovery = new MdnsAdvertisement(temp.Log);
        var id = Guid.NewGuid().ToString();
        await discovery.StartAsync(id, [address]);
        Assert.AreEqual("mDNS advertised (version=1)", discovery.Status);
        var serviceName = $"AgentMon-{id}._agentmon._tcp.local";
        Assert.IsTrue(await QueryAsync(address.Address, serviceName), "Expected native DNS-SD TXT version=1 response.");
        await discovery.DisposeAsync();
        Assert.IsFalse(await QueryAsync(address.Address, serviceName), "Stopped relay must withdraw its DNS-SD registration.");
    }

    private static async Task<bool> QueryAsync(IPAddress localAddress, string serviceName)
    {
        using var socket = new UdpClient(new IPEndPoint(localAddress, 0));
        socket.Client.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastInterface, localAddress.GetAddressBytes());
        var packet = new List<byte> { 0x41, 0x4D, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0 };
        foreach (var label in serviceName.Split('.'))
        {
            var bytes = Encoding.ASCII.GetBytes(label);
            packet.Add((byte)bytes.Length);
            packet.AddRange(bytes);
        }
        packet.AddRange([0, 0, 16, 0, 1]); // TXT, IN; ephemeral source port requests a unicast reply.
        await socket.SendAsync(packet.ToArray(), new IPEndPoint(IPAddress.Parse("224.0.0.251"), 5353));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(4));
        try
        {
            while (true)
            {
                var response = await socket.ReceiveAsync(timeout.Token);
                if (response.Buffer.Length >= 12 && (response.Buffer[2] & 0x80) != 0 &&
                    Encoding.ASCII.GetString(response.Buffer).Contains("version=1", StringComparison.Ordinal))
                    return true;
            }
        }
        catch (OperationCanceledException) when (timeout.IsCancellationRequested)
        {
            return false;
        }
    }
}
