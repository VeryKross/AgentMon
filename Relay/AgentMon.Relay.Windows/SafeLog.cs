using System.Globalization;

namespace AgentMon.Relay.Windows;

internal enum LogEvent
{
    Started, Stopped, IndexFailed, NetworkFailed, ListenerFailed, RequestFailed,
    DiscoveryFailed, SettingsFailed, UiFailed
}

internal sealed class SafeLog(string directory)
{
    private readonly object gate = new();
    internal bool WriteFailed { get; private set; }

    internal void Write(LogEvent operation, Exception? error = null)
    {
        lock (gate)
        {
            try
            {
                Directory.CreateDirectory(directory);
                var path = Path.Combine(directory, "relay.log");
                if (File.Exists(path) && new FileInfo(path).Length > 1024 * 1024)
                    File.Move(path, Path.Combine(directory, "relay.previous.log"), true);
                var line = $"{DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture)} {operation}";
                if (error is not null)
                    line += $" {error.GetType().Name}";
                File.AppendAllText(path, line + Environment.NewLine);
                WriteFailed = false;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                WriteFailed = true;
            }
        }
    }
}
