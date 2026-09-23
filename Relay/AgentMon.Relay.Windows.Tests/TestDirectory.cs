using Microsoft.VisualStudio.TestTools.UnitTesting;

[assembly: Parallelize(Workers = 4, Scope = ExecutionScope.MethodLevel)]

namespace AgentMon.Relay.Windows.Tests;

internal sealed class TestDirectory : IDisposable
{
    internal string Root { get; } = Path.Combine(Path.GetTempPath(), "AgentMonRelayTests", Guid.NewGuid().ToString("N"));

    internal TestDirectory() => Directory.CreateDirectory(Root);
    internal string FilePath(string name) => Path.Combine(Root, name);
    internal SafeLog Log => new(FilePath("logs"));
    internal static DateTimeOffset Now => new(2026, 9, 23, 12, 0, 0, TimeSpan.Zero);
    internal static RelayHost Host => new("c87c6241-8ef1-492a-8cd6-f78ae969323c", "Test PC");

    internal string Session(string id, string events = "", bool live = false, DateTimeOffset? updatedAt = null)
    {
        var directory = FilePath(id);
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "workspace.yaml"),
            $"id: {id}\ncwd: 'C:\\Projects\\AgentMon'\nrepository: VeryKross/AgentMon\nbranch: main\nname: Test session\nupdated_at: {(updatedAt ?? Now):O}\n");
        File.WriteAllText(Path.Combine(directory, "events.jsonl"), events);
        File.SetLastWriteTimeUtc(Path.Combine(directory, "events.jsonl"), (updatedAt ?? Now).UtcDateTime);
        if (live)
            File.WriteAllText(Path.Combine(directory, $"inuse.{Environment.ProcessId}.lock"), "");
        return directory;
    }

    public void Dispose() => Directory.Delete(Root, true);
}
