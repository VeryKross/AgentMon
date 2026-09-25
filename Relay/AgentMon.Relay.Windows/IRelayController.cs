namespace AgentMon.Relay.Windows;

internal sealed record RelayView(
    string State,
    string DisplayName,
    IReadOnlyList<string> Urls,
    string Fingerprint,
    int SessionCount,
    DateTimeOffset? LastIndexedAt,
    string? Error,
    string DiscoveryStatus);

internal interface IRelayController : IAsyncDisposable
{
    bool StartHidden { get; }
    RelayView GetView();
    Task StartAsync();
    Task StopAsync();
    Task SetStartHiddenAsync(bool startHidden);
    Task SetDisplayNameAsync(string name);
    Task RegenerateTokenAsync();
    Task RegenerateCertificateAsync();
    string RevealToken();
}
