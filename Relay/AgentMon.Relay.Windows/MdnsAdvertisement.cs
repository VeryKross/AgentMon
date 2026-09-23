using System.Runtime.InteropServices;

namespace AgentMon.Relay.Windows;

internal sealed class MdnsAdvertisement : IAsyncDisposable
{
    private readonly List<Registration> registrations = [];
    private readonly SafeLog log;
    internal string Status { get; private set; } = "Not advertising";

    internal MdnsAdvertisement(SafeLog log) => this.log = log;

    internal async Task StartAsync(string hostId, IReadOnlyList<PrivateAddress> addresses)
    {
        var succeeded = 0;
        foreach (var address in addresses.DistinctBy(address => address.InterfaceIndex))
        {
            var registration = new Registration($"AgentMon-{hostId}._agentmon._tcp.local",
                $"agentmon-{hostId}.local", address, log);
            registrations.Add(registration);
            if (await registration.StartAsync().ConfigureAwait(false))
                succeeded++;
        }
        Status = succeeded == registrations.Count && succeeded > 0
            ? "mDNS advertised (version=1)" : "mDNS unavailable on some interfaces; use manual pairing";
    }

    public async ValueTask DisposeAsync()
    {
        foreach (var registration in registrations)
            await registration.DisposeAsync().ConfigureAwait(false);
        registrations.Clear();
        Status = "Not advertising";
    }

    private sealed class Registration(string serviceName, string hostName, PrivateAddress address, SafeLog log)
        : IAsyncDisposable
    {
        private Operation? pending;
        private bool registered;

        internal async Task<bool> StartAsync()
        {
            try
            {
                pending = new Operation(serviceName, hostName, address, deregister: false);
                var status = await pending.Completion.WaitAsync(TimeSpan.FromSeconds(3)).ConfigureAwait(false);
                pending = null;
                registered = status == 0;
                if (!registered)
                    log.Write(LogEvent.DiscoveryFailed);
                return registered;
            }
            catch (Exception ex) when (ex is EntryPointNotFoundException or DllNotFoundException or TimeoutException)
            {
                log.Write(LogEvent.DiscoveryFailed, ex);
                pending?.Cancel();
                return false;
            }
        }

        public async ValueTask DisposeAsync()
        {
            if (pending is not null)
            {
                pending.Cancel();
                // Native buffers must survive a late callback. The continuation also removes a late success.
                _ = RemoveLateRegistrationAsync(pending.Completion);
                pending = null;
            }
            if (registered)
                await DeregisterAsync().ConfigureAwait(false);
            registered = false;
        }

        private async Task RemoveLateRegistrationAsync(Task<uint> completion)
        {
            if (await completion.ConfigureAwait(false) == 0)
                await DeregisterAsync().ConfigureAwait(false);
        }

        private async Task DeregisterAsync()
        {
            try
            {
                var operation = new Operation(serviceName, hostName, address, deregister: true);
                if (await operation.Completion.WaitAsync(TimeSpan.FromSeconds(3)).ConfigureAwait(false) != 0)
                    log.Write(LogEvent.DiscoveryFailed);
            }
            catch (Exception ex) when (ex is EntryPointNotFoundException or DllNotFoundException or TimeoutException)
            {
                log.Write(LogEvent.DiscoveryFailed, ex);
            }
        }
    }

    private sealed class Operation
    {
        private readonly object gate = new();
        private readonly TaskCompletionSource<uint> completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private IntPtr instance;
        private IntPtr request;
        private IntPtr cancellation;
        private GCHandle root;
        private bool finished;
        private readonly bool deregister;
        internal Task<uint> Completion => completion.Task;
        private static readonly RegisterComplete Callback = Complete;

        internal Operation(string serviceName, string hostName, PrivateAddress address, bool deregister)
        {
            this.deregister = deregister;
            try
            {
                uint ipv4 = BitConverter.ToUInt32(address.Address.GetAddressBytes());
                instance = DnsServiceConstructInstance(serviceName, hostName, ref ipv4, IntPtr.Zero,
                    RelaySnapshot.Port, 0, 0, 1, ["version"], ["1"]);
                if (instance == IntPtr.Zero)
                {
                    completion.SetResult(8);
                    return;
                }
                root = GCHandle.Alloc(this);
                var value = new RegisterRequest
                {
                    Version = 1,
                    InterfaceIndex = address.InterfaceIndex,
                    Instance = instance,
                    Callback = Marshal.GetFunctionPointerForDelegate(Callback),
                    Context = GCHandle.ToIntPtr(root)
                };
                request = Marshal.AllocHGlobal(Marshal.SizeOf<RegisterRequest>());
                Marshal.StructureToPtr(value, request, false);
                cancellation = Marshal.AllocHGlobal(IntPtr.Size);
                Marshal.WriteIntPtr(cancellation, IntPtr.Zero);
                var status = deregister ? DnsServiceDeRegister(request, IntPtr.Zero) : DnsServiceRegister(request, cancellation);
                if (status != 9506) // DNS_REQUEST_PENDING: callback owns all buffers from here.
                    Finish(status, IntPtr.Zero);
            }
            catch
            {
                Finish(1, IntPtr.Zero);
                throw;
            }
        }

        internal void Cancel()
        {
            lock (gate)
            {
                if (!finished && !deregister && cancellation != IntPtr.Zero)
                    DnsServiceRegisterCancel(cancellation);
            }
        }

        private static void Complete(uint status, IntPtr context, IntPtr result)
            => ((Operation)GCHandle.FromIntPtr(context).Target!).Finish(status, result);

        private void Finish(uint status, IntPtr result)
        {
            lock (gate)
            {
                if (result != IntPtr.Zero && result != instance)
                    DnsServiceFreeInstance(result);
                if (finished)
                    return;
                finished = true;
                if (instance != IntPtr.Zero)
                    DnsServiceFreeInstance(instance);
                if (request != IntPtr.Zero)
                    Marshal.FreeHGlobal(request);
                if (cancellation != IntPtr.Zero)
                    Marshal.FreeHGlobal(cancellation);
                if (root.IsAllocated)
                    root.Free();
                completion.TrySetResult(status);
            }
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RegisterRequest
    {
        internal uint Version;
        internal uint InterfaceIndex;
        internal IntPtr Instance;
        internal IntPtr Callback;
        internal IntPtr Context;
        internal IntPtr Credentials;
        internal int UnicastEnabled;
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate void RegisterComplete(uint status, IntPtr context, IntPtr instance);

    [DllImport("dnsapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern IntPtr DnsServiceConstructInstance(
        string serviceName, string hostName, ref uint ipv4, IntPtr ipv6, ushort port, ushort priority,
        ushort weight, uint propertyCount,
        [In, MarshalAs(UnmanagedType.LPArray, ArraySubType = UnmanagedType.LPWStr, SizeParamIndex = 7)] string[] keys,
        [In, MarshalAs(UnmanagedType.LPArray, ArraySubType = UnmanagedType.LPWStr, SizeParamIndex = 7)] string[] values);

    [DllImport("dnsapi.dll", ExactSpelling = true)]
    private static extern uint DnsServiceRegister(IntPtr request, IntPtr cancellation);

    [DllImport("dnsapi.dll", ExactSpelling = true)]
    private static extern uint DnsServiceDeRegister(IntPtr request, IntPtr cancellation);

    [DllImport("dnsapi.dll", ExactSpelling = true)]
    private static extern uint DnsServiceRegisterCancel(IntPtr cancellation);

    [DllImport("dnsapi.dll", ExactSpelling = true)]
    private static extern void DnsServiceFreeInstance(IntPtr instance);
}
