namespace AgentMon.Relay.Windows;

internal static class RelayApplication
{
    private static readonly string DataDirectory =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AgentMonRelay");
    internal static string LogDirectory => Path.Combine(DataDirectory, "Logs");
    private static readonly SafeLog Log = new(LogDirectory);

    internal static IRelayController CreateController()
        => new RelayController(new ProtectedSettingsStore(DataDirectory), Log,
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".copilot", "session-state"));

    internal static void LogFailure(string operation, Exception error) => Log.Write(LogEvent.UiFailed, error);
}
