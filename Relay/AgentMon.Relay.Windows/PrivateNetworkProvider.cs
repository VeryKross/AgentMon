using System.Collections;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;

namespace AgentMon.Relay.Windows;

internal sealed record PrivateAddress(IPAddress Address, int PrefixLength, uint InterfaceIndex)
{
    internal bool Contains(IPAddress remote)
    {
        if (PrefixLength is <= 0 or > 32 ||
            (remote.AddressFamily != AddressFamily.InterNetwork && !remote.IsIPv4MappedToIPv6))
            return false;
        var localBytes = Address.GetAddressBytes();
        var remoteBytes = remote.MapToIPv4().GetAddressBytes();
        if (localBytes.Length != remoteBytes.Length)
            return false;
        var mask = uint.MaxValue << (32 - PrefixLength);
        return (System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(localBytes) & mask) ==
               (System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(remoteBytes) & mask);
    }
}

internal interface IPrivateNetworkProvider
{
    IReadOnlyList<PrivateAddress> GetAddresses();
}

internal sealed class PrivateNetworkProvider : IPrivateNetworkProvider
{
    public IReadOnlyList<PrivateAddress> GetAddresses()
    {
        var allowed = PrivateAdapters();
        return NetworkInterface.GetAllNetworkInterfaces()
            .Where(adapter => adapter.OperationalStatus == OperationalStatus.Up &&
                              adapter.Supports(NetworkInterfaceComponent.IPv4) &&
                              Guid.TryParse(adapter.Id, out var id) && allowed.Contains(id))
            .SelectMany(adapter =>
            {
                var properties = adapter.GetIPProperties();
                var index = checked((uint)properties.GetIPv4Properties().Index);
                return properties.UnicastAddresses
                    .Where(address => address.Address.AddressFamily == AddressFamily.InterNetwork &&
                                      !IPAddress.IsLoopback(address.Address) &&
                                      address.PrefixLength is > 0 and <= 32)
                    .Select(address => new PrivateAddress(address.Address, address.PrefixLength, index));
            })
            .Distinct().OrderBy(address => address.Address.ToString(), StringComparer.Ordinal).ToArray();
    }

    private static HashSet<Guid> PrivateAdapters()
    {
        // NLM categories, not RFC1918 address guessing, decide which adapters may listen.
        var type = Type.GetTypeFromCLSID(new Guid("DCB00C01-570F-4A9B-8D69-199FDBA5723B"), true)!;
        var manager = Activator.CreateInstance(type)!;
        object? connections = null;
        var categories = new Dictionary<Guid, bool>();
        try
        {
            connections = ((dynamic)manager).GetNetworkConnections();
            foreach (object connection in (IEnumerable)connections)
            {
                object? network = null;
                try
                {
                    network = ((dynamic)connection).GetNetwork();
                    Guid adapterId = ((INetworkConnection)connection).GetAdapterId();
                    var isPrivate = (int)((dynamic)network).GetCategory() == 1;
                    categories[adapterId] = categories.GetValueOrDefault(adapterId, true) && isPrivate;
                }
                finally
                {
                    if (network is not null)
                        Marshal.ReleaseComObject(network);
                    Marshal.ReleaseComObject(connection);
                }
            }
        }
        finally
        {
            if (connections is not null)
                Marshal.ReleaseComObject(connections);
            Marshal.ReleaseComObject(manager);
        }
        return categories.Where(pair => pair.Value).Select(pair => pair.Key).ToHashSet();
    }

    // GUID return values in NLM are not Automation variants; call the typed dual interface.
    [ComImport]
    [Guid("DCB00005-570F-4A9B-8D69-199FDBA5723B")]
    [InterfaceType(ComInterfaceType.InterfaceIsDual)]
    private interface INetworkConnection
    {
        [return: MarshalAs(UnmanagedType.Interface)]
        object GetNetwork();
        bool IsConnectedToInternet { [return: MarshalAs(UnmanagedType.VariantBool)] get; }
        bool IsConnected { [return: MarshalAs(UnmanagedType.VariantBool)] get; }
        int GetConnectivity();
        Guid GetConnectionId();
        Guid GetAdapterId();
        int GetDomainType();
    }
}
