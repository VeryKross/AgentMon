using System.Net;
using System.Security.Cryptography.X509Certificates;
using System.Text;

namespace AgentMon.Relay.Windows;

internal sealed class RelayController : IRelayController
{
    private readonly ProtectedSettingsStore store;
    private readonly SafeLog log;
    private readonly SessionIndexer indexer;
    private readonly IPrivateNetworkProvider networks;
    private readonly SemaphoreSlim lifecycle = new(1, 1);
    private readonly SemaphoreSlim listenerGate = new(1, 1);
    private RelaySettings settings;
    private RelayView view;
    private CancellationTokenSource? cancellation;
    private Task? indexingTask;
    private Task? networkingTask;
    private RelayServer? server;
    private X509Certificate2? certificate;
    private byte[]? servingCertificate;
    private MdnsAdvertisement? discovery;
    private IReadOnlyList<PrivateAddress> bindings = [];
    private bool disposed;

    internal RelayController(ProtectedSettingsStore store, SafeLog log, string sessionRoot,
        IPrivateNetworkProvider? networks = null)
    {
        this.store = store;
        this.log = log;
        this.networks = networks ?? new PrivateNetworkProvider();
        settings = store.LoadOrCreate();
        indexer = new SessionIndexer(sessionRoot, log);
        using var initialCertificate = ProtectedSettingsStore.OpenCertificate(settings);
        view = new RelayView("Stopped", settings.DisplayName, [], ProtectedSettingsStore.Fingerprint(initialCertificate),
            0, null, null, "Not advertising");
    }

    public RelayView GetView()
    {
        var current = Volatile.Read(ref view);
        var snapshot = indexer.Snapshot;
        return current with
        {
            DisplayName = Volatile.Read(ref settings).DisplayName,
            SessionCount = snapshot?.Sessions.Count ?? 0,
            LastIndexedAt = snapshot?.GeneratedAt,
            Error = current.Error ?? (indexer.LastScanFailed ? "Indexing failed; serving the last successful snapshot." :
                log.WriteFailed ? "The log could not be written. Check your local application data permissions." : null)
        };
    }

    public async Task StartAsync()
    {
        await lifecycle.WaitAsync().ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (cancellation is not null)
                return;
            cancellation = new CancellationTokenSource();
            var token = cancellation.Token;
            indexingTask = Task.Run(() => IndexLoopAsync(token), token);
            networkingTask = Task.Run(() => NetworkLoopAsync(token), token);
            log.Write(LogEvent.Started);
        }
        finally
        {
            lifecycle.Release();
        }
    }

    public async Task StopAsync()
    {
        await lifecycle.WaitAsync().ConfigureAwait(false);
        try
        {
            if (cancellation is null)
                return;
            await cancellation.CancelAsync().ConfigureAwait(false);
            try
            {
                await Task.WhenAll(indexingTask!, networkingTask!).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
            {
                // Polling is cancelled before listener resources are released.
            }
            await listenerGate.WaitAsync().ConfigureAwait(false);
            try
            {
                await StopListenerAsync().ConfigureAwait(false);
                Volatile.Write(ref view, view with { State = "Stopped", Urls = [], Error = null, DiscoveryStatus = "Not advertising" });
            }
            finally
            {
                listenerGate.Release();
                cancellation.Dispose();
                cancellation = null;
            }
            log.Write(LogEvent.Stopped);
        }
        finally
        {
            lifecycle.Release();
        }
    }

    public Task SetDisplayNameAsync(string name)
    {
        name = name.Trim();
        if (name.Length == 0 || name.EnumerateRunes().Take(121).Count() > 120 || name.Any(char.IsControl))
            throw new ArgumentException("Use 1 to 120 characters without control characters.", nameof(name));
        return UpdateSettingsAsync(current => current with { DisplayName = name });
    }

    public Task RegenerateTokenAsync()
        => UpdateSettingsAsync(current => current with { Token = ProtectedSettingsStore.NewToken() });

    public Task RegenerateCertificateAsync()
        => UpdateSettingsAsync(current => current with { Certificate = ProtectedSettingsStore.NewCertificate() });

    public string RevealToken() => Volatile.Read(ref settings).Token;

    private async Task UpdateSettingsAsync(Func<RelaySettings, RelaySettings> update)
    {
        await lifecycle.WaitAsync().ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            var changed = await Task.Run(() =>
            {
                var result = update(settings);
                store.Save(result);
                return result;
            }).ConfigureAwait(false);
            Volatile.Write(ref settings, changed);
            using var updatedCertificate = ProtectedSettingsStore.OpenCertificate(changed);
            Volatile.Write(ref view, view with { Fingerprint = ProtectedSettingsStore.Fingerprint(updatedCertificate) });
            if (cancellation is not null)
                await RefreshNetworkAsync(cancellation.Token).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            log.Write(LogEvent.SettingsFailed, ex);
            throw;
        }
        finally
        {
            lifecycle.Release();
        }
    }

    private async Task IndexLoopAsync(CancellationToken token)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(3));
        do
        {
            var current = Volatile.Read(ref settings);
            try
            {
                indexer.Scan(new RelayHost(current.HostId, current.DisplayName), DateTimeOffset.UtcNow);
            }
            catch (Exception ex)
            {
                // Keep the poller alive, but never publish a fabricated successful scan.
                log.Write(LogEvent.IndexFailed, ex);
                Volatile.Write(ref view, view with { Error = "Indexing failed; serving the last successful snapshot." });
            }
        } while (await timer.WaitForNextTickAsync(token).ConfigureAwait(false));
    }

    private async Task NetworkLoopAsync(CancellationToken token)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(3));
        do
        {
            await RefreshNetworkAsync(token).ConfigureAwait(false);
        } while (await timer.WaitForNextTickAsync(token).ConfigureAwait(false));
    }

    private async Task RefreshNetworkAsync(CancellationToken token)
    {
        await listenerGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            var addresses = networks.GetAddresses();
            var current = Volatile.Read(ref settings);
            if (server is not null && addresses.SequenceEqual(bindings) && ReferenceEquals(servingCertificate, current.Certificate))
                return;
            await StopListenerAsync().ConfigureAwait(false);
            if (addresses.Count == 0)
            {
                Volatile.Write(ref view, view with
                {
                    State = "Waiting for private network", Urls = [], Error = null, DiscoveryStatus = "Not advertising"
                });
                return;
            }
            certificate = ProtectedSettingsStore.OpenCertificate(current);
            if (certificate.NotAfter.ToUniversalTime() <= DateTime.UtcNow)
                throw new InvalidOperationException("Certificate expired.");
            servingCertificate = current.Certificate;
            bindings = addresses;
            server = new RelayServer(addresses.Select(address => address.Address).ToArray(), RelaySnapshot.Port,
                certificate, () => Volatile.Read(ref settings).Token, () => indexer.Snapshot, ConnectionAllowed, log);
            await server.StartAsync(token).ConfigureAwait(false);
            Volatile.Write(ref view, view with
            {
                State = "Running", Urls = server.Urls, Error = null,
                Fingerprint = ProtectedSettingsStore.Fingerprint(certificate), DiscoveryStatus = "Starting mDNS"
            });
            discovery = new MdnsAdvertisement(log);
            await discovery.StartAsync(current.HostId, addresses).ConfigureAwait(false);
            Volatile.Write(ref view, view with { DiscoveryStatus = discovery.Status });
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            log.Write(LogEvent.ListenerFailed, ex);
            await StopListenerAsync().ConfigureAwait(false);
            Volatile.Write(ref view, view with
            {
                State = "Error", Urls = [], DiscoveryStatus = "Not advertising",
                Error = "Could not start the private-network listener. Check the network profile, port, certificate, and logs."
            });
        }
        finally
        {
            listenerGate.Release();
        }
    }

    private bool ConnectionAllowed(IPAddress? local, IPAddress? remote)
    {
        if (local is null || remote is null)
            return false;
        try
        {
            // Recheck the Windows profile on every request, including existing keep-alive connections.
            return networks.GetAddresses().Any(address => address.Address.Equals(local) && address.Contains(remote));
        }
        catch (Exception ex)
        {
            log.Write(LogEvent.NetworkFailed, ex);
            return false;
        }
    }

    private async Task StopListenerAsync()
    {
        try
        {
            if (server is not null)
                await server.DisposeAsync().ConfigureAwait(false);
        }
        finally
        {
            server = null;
            certificate?.Dispose();
            certificate = null;
            servingCertificate = null;
            bindings = [];
            if (discovery is not null)
                await discovery.DisposeAsync().ConfigureAwait(false);
            discovery = null;
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (disposed)
            return;
        await StopAsync().ConfigureAwait(false);
        disposed = true;
        lifecycle.Dispose();
        listenerGate.Dispose();
    }
}
