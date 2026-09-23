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
    RelayView GetView();
    Task StartAsync();
    Task StopAsync();
    Task SetDisplayNameAsync(string name);
    Task RegenerateTokenAsync();
    Task RegenerateCertificateAsync();
    string RevealToken();
}
