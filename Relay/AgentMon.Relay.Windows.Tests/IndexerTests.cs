using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace AgentMon.Relay.Windows.Tests;

[TestClass]
public sealed class IndexerTests
{
    [TestMethod]
    public void Scan_MoreThan50Sessions_PrioritizesStateThenRecencyAndSkipsPendingAndOldOffline()
    {
        using var temp = new TestDirectory();
        for (var i = 0; i < 60; i++)
            temp.Session($"offline-{i:D2}", updatedAt: TestDirectory.Now.AddSeconds(-i));
        temp.Session("working", """{"type":"assistant.turn_start"}""", live: true, TestDirectory.Now.AddMinutes(-10));
        temp.Session("attention", """{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""", live: true);
        temp.Session("ready", live: true);
        temp.Session("old", updatedAt: TestDirectory.Now.AddDays(-2));
        temp.Session("pending-session-123", live: true);
        var indexer = new SessionIndexer(temp.Root, temp.Log);

        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        var sessions = indexer.Snapshot!.Sessions;
        Assert.AreEqual(50, sessions.Count);
        CollectionAssert.AreEqual(new[] { "attention", "working", "ready", "offline-00", "offline-01" },
            sessions.Take(5).Select(session => session.Id).ToArray());
        Assert.IsFalse(sessions.Any(session => session.Id is "old" or "pending-session-123"));
    }

    [TestMethod]
    public void Scan_LockedWorkspace_KeepsWholeSnapshotAndOriginalGeneratedAtThenRecovers()
    {
        using var temp = new TestDirectory();
        var directory = temp.Session("session");
        var indexer = new SessionIndexer(temp.Root, temp.Log);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        var before = indexer.Snapshot;
        using (var locked = new FileStream(Path.Combine(directory, "workspace.yaml"), FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            Assert.IsFalse(indexer.Scan(TestDirectory.Host, TestDirectory.Now.AddMinutes(1)));
            Assert.AreSame(before, indexer.Snapshot);
            Assert.AreEqual(TestDirectory.Now, indexer.Snapshot!.GeneratedAt);
        }
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now.AddMinutes(2)));
        Assert.AreEqual(TestDirectory.Now.AddMinutes(2), indexer.Snapshot!.GeneratedAt);
    }

    [TestMethod]
    public void Scan_PartialWorkspaceOrMissingKnownEventFile_DoesNotFreshenSnapshot()
    {
        using var temp = new TestDirectory();
        var directory = temp.Session("session");
        var indexer = new SessionIndexer(temp.Root, temp.Log);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        var before = indexer.Snapshot;
        File.WriteAllText(Path.Combine(directory, "workspace.yaml"), "id: 'partial");
        Assert.IsFalse(indexer.Scan(TestDirectory.Host, TestDirectory.Now.AddSeconds(4)));
        Assert.AreSame(before, indexer.Snapshot);
        temp.Session("session");
        File.Delete(Path.Combine(directory, "events.jsonl"));
        Assert.IsFalse(indexer.Scan(TestDirectory.Host, TestDirectory.Now.AddSeconds(8)));
        Assert.AreSame(before, indexer.Snapshot);
    }

    [TestMethod]
    public void Scan_MissingRootBeforeFirstUse_IsEmptyButDisappearingRootIsFailure()
    {
        using var temp = new TestDirectory();
        var root = temp.FilePath("sessions");
        var indexer = new SessionIndexer(root, temp.Log);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        Assert.AreEqual(0, indexer.Snapshot!.Sessions.Count);
        Directory.CreateDirectory(root);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now.AddSeconds(1)));
        Directory.Delete(root);
        Assert.IsFalse(indexer.Scan(TestDirectory.Host, TestDirectory.Now.AddSeconds(2)));
        Assert.AreEqual(TestDirectory.Now.AddSeconds(1), indexer.Snapshot!.GeneratedAt);
    }

    [TestMethod]
    public void Snapshot_JsonShapeDatesAndRedaction_MatchesV1ContractExactly()
    {
        using var temp = new TestDirectory();
        temp.Session("test", """
            {"type":"user.message","data":{"content":"SECRET_PROMPT"}}
            {"type":"assistant.message","data":{"content":"SECRET_CODE"}}
            {"type":"tool.execution_start","data":{"toolName":"run","arguments":"SECRET_ARGUMENTS"}}
            {"type":"tool.execution_complete","data":{"toolCallId":"c","result":"SECRET_OUTPUT"}}
            """);
        var indexer = new SessionIndexer(temp.Root, temp.Log);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        var json = JsonSerializer.Serialize(indexer.Snapshot, RelaySnapshot.JsonOptions);
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        CollectionAssert.AreEquivalent(new[] { "protocolVersion", "relayVersion", "generatedAt", "host", "sessions" },
            root.EnumerateObject().Select(property => property.Name).ToArray());
        var session = root.GetProperty("sessions")[0];
        CollectionAssert.AreEquivalent(new[] { "id", "project", "task", "repository", "branch", "activity", "updatedAt" },
            session.EnumerateObject().Select(property => property.Name).ToArray());
        CollectionAssert.AreEquivalent(new[] { "id", "name", "platform" },
            root.GetProperty("host").EnumerateObject().Select(property => property.Name).ToArray());
        Assert.AreEqual(1, root.GetProperty("protocolVersion").GetInt32());
        Assert.AreEqual("windows", root.GetProperty("host").GetProperty("platform").GetString());
        StringAssert.Matches(root.GetProperty("generatedAt").GetString()!, new Regex(@"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d+Z$"));
        Assert.AreEqual(TimeSpan.Zero, session.GetProperty("updatedAt").GetDateTimeOffset().Offset);
        Assert.IsFalse(json.Contains("SECRET_", StringComparison.Ordinal));
        Assert.IsFalse(json.Contains("C:\\", StringComparison.Ordinal));
        temp.Log.Write(LogEvent.IndexFailed, new IOException("SECRET_PROMPT SECRET_PATH SECRET_TOKEN"));
        var logs = File.ReadAllText(Path.Combine(temp.Root, "logs", "relay.log"));
        Assert.IsFalse(logs.Contains("SECRET_", StringComparison.Ordinal));
        StringAssert.Contains(logs, nameof(IOException));
    }
}
