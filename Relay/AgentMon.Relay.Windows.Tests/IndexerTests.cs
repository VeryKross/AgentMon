using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace AgentMon.Relay.Windows.Tests;

[TestClass]
public sealed class IndexerTests
{
    [TestMethod]
    public void Snapshot_ReportsActualAssemblyVersion()
    {
        var expected = typeof(RelaySnapshot).Assembly.GetName().Version!.ToString(3);
        Assert.AreEqual(expected, RelaySnapshot.ApplicationVersion);
        using var temp = new TestDirectory();
        var indexer = new SessionIndexer(temp.Root, temp.Log);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        Assert.AreEqual(expected, indexer.Snapshot!.RelayVersion);
    }

    [TestMethod]
    public void Scan_SameProjectSessionsRetainIndependentStates()
    {
        using var temp = new TestDirectory();
        var waiting = temp.Session("waiting", """
            {"type":"session.fusion_completed"}
            {"type":"user.message"}
            {"type":"hook.start","data":{"hookType":"preToolUse","input":{"toolCalls":[{"id":"q","name":"ask_user"}]}}}
            {"type":"hook.end","data":{"hookType":"preToolUse","success":true}}
            """, live: true, updatedAt: TestDirectory.Now.AddHours(-1));
        var working = temp.Session("working", """{"type":"assistant.turn_start"}""", live: true);
        var ready = temp.Session("ready", """{"type":"session.fusion_completed"}""", live: true);
        foreach (var directory in new[] { waiting, working, ready })
        {
            var workspace = Path.Combine(directory, "workspace.yaml");
            File.WriteAllText(workspace, File.ReadAllText(workspace).Replace("VeryKross/AgentMon", "VeryKross/BadCatAgent"));
        }
        var indexer = new SessionIndexer(temp.Root, temp.Log);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        var sessions = indexer.Snapshot!.Sessions;
        CollectionAssert.AreEqual(new[] { "attention", "working", "ready" },
            sessions.Select(session => session.Activity).ToArray());
        CollectionAssert.AreEqual(new[] { "waiting", "working", "ready" },
            sessions.Select(session => session.Id).ToArray());
        Assert.IsTrue(sessions.All(session => session.Project == "BadCatAgent"));
    }

    [TestMethod]
    public void Scan_MoreThan50Sessions_PrioritizesStateThenRecencyAndSkipsPendingAndOldOffline()
    {
        using var temp = new TestDirectory();
        for (var i = 0; i < 60; i++)
            temp.Session($"offline-{i:D2}", updatedAt: TestDirectory.Now.AddSeconds(-i));
        temp.Session("working", """{"type":"assistant.turn_start"}""", live: true, TestDirectory.Now.AddMinutes(-10));
        temp.Session("attention", """{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""", live: true);
        temp.Session("dormant-attention", """{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""",
            live: true, updatedAt: TestDirectory.Now.AddDays(-3));
        temp.Session("ready", live: true);
        temp.Session("old", updatedAt: TestDirectory.Now.AddDays(-2));
        temp.Session("pending-session-123", live: true);
        var indexer = new SessionIndexer(temp.Root, temp.Log);

        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        var sessions = indexer.Snapshot!.Sessions;
        Assert.AreEqual(50, sessions.Count);
        CollectionAssert.AreEqual(new[] { "attention", "dormant-attention", "working", "ready", "offline-00" },
            sessions.Take(5).Select(session => session.Id).ToArray());
        Assert.IsFalse(sessions.Any(session => session.Id is "old" or "pending-session-123"));
    }

    [TestMethod]
    [DataRow(89, 0, true, true)]
    [DataRow(90, 0, true, true)]
    [DataRow(90, 1, true, false)]
    [DataRow(201, 0, true, false)]
    [DataRow(90, 0, false, false)]
    [DataRow(90, 1, false, false)]
    [DataRow(201, 0, false, false)]
    public void Scan_SessionAgeCutoff_OverridesAttentionAndProcessLiveness(
        int days, int seconds, bool live, bool included)
    {
        using var temp = new TestDirectory();
        var updatedAt = TestDirectory.Now.AddDays(-days).AddSeconds(-seconds);
        temp.Session("attention",
            """{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""",
            live, updatedAt);
        temp.Session("ready", live: live, updatedAt: updatedAt);
        var indexer = new SessionIndexer(temp.Root, temp.Log);

        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        var sessions = indexer.Snapshot!.Sessions;
        Assert.AreEqual(included, sessions.Any(session => session.Id == "attention"));
        Assert.AreEqual(included && live, sessions.Any(session => session.Id == "ready"));
    }

    [TestMethod]
    public void Scan_AgeCutoff_UsesLatestWorkspaceOrEventTimestamp()
    {
        using var temp = new TestDirectory();
        var old = TestDirectory.Now.AddDays(-201);
        var recentEvents = temp.Session("recent-events",
            """{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""",
            updatedAt: old);
        File.SetLastWriteTimeUtc(Path.Combine(recentEvents, "events.jsonl"), TestDirectory.Now.UtcDateTime);
        var recentWorkspace = temp.Session("recent-workspace", live: true);
        File.SetLastWriteTimeUtc(Path.Combine(recentWorkspace, "events.jsonl"), old.UtcDateTime);
        var indexer = new SessionIndexer(temp.Root, temp.Log);

        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        CollectionAssert.AreEquivalent(new[] { "recent-events", "recent-workspace" },
            indexer.Snapshot!.Sessions.Select(session => session.Id).ToArray());
        Assert.IsTrue(indexer.Snapshot.Sessions.All(session => session.UpdatedAt == TestDirectory.Now));
    }

    [TestMethod]
    public void Scan_SessionCrossesAgeCutoff_RemovesItUntilNewActivity()
    {
        using var temp = new TestDirectory();
        var directory = temp.Session("attention",
            """{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""",
            live: true, updatedAt: TestDirectory.Now.AddDays(-90));
        var indexer = new SessionIndexer(temp.Root, temp.Log);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        Assert.AreEqual(1, indexer.Snapshot!.Sessions.Count);

        var later = TestDirectory.Now.AddSeconds(1);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, later));
        Assert.AreEqual(0, indexer.Snapshot!.Sessions.Count);

        File.SetLastWriteTimeUtc(Path.Combine(directory, "events.jsonl"), later.UtcDateTime);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, later));
        Assert.AreEqual(1, indexer.Snapshot!.Sessions.Count);
        Assert.AreEqual(later, indexer.Snapshot.Sessions[0].UpdatedAt);
    }

    [TestMethod]
    [DataRow(0, 0, true)]
    [DataRow(23, 59, true)]
    [DataRow(24, 0, false)]
    [DataRow(24 * 19, 0, false)]
    public void Scan_UnansweredQuestionWithoutProcessOrWorkspace_UsesOfflineVisibilityWindow(
        int hours, int minutes, bool included)
    {
        using var temp = new TestDirectory();
        var directory = temp.Session("abandoned-question",
            """{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""",
            updatedAt: TestDirectory.Now.AddHours(-hours).AddMinutes(-minutes),
            cwd: temp.FilePath("removed-workspace"));
        File.WriteAllText(Path.Combine(directory, "inuse.2147483647.lock"), "");
        var indexer = new SessionIndexer(temp.Root, temp.Log, _ => false);

        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        var sessions = indexer.Snapshot!.Sessions;
        Assert.AreEqual(included ? 1 : 0, sessions.Count);
        if (included)
            Assert.AreEqual("offline", sessions[0].Activity);
    }

    [TestMethod]
    public void Scan_WaitingProcessStopsWithMissingWorkspace_RemovesStaleQuestionOnNextScan()
    {
        using var temp = new TestDirectory();
        temp.Session("waiting",
            """{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""",
            live: true, updatedAt: TestDirectory.Now.AddDays(-19),
            cwd: temp.FilePath("removed-workspace"));
        var live = true;
        var indexer = new SessionIndexer(temp.Root, temp.Log, _ => live);

        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        Assert.AreEqual("attention", indexer.Snapshot!.Sessions.Single().Activity);

        live = false;
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now.AddSeconds(3)));
        Assert.AreEqual(0, indexer.Snapshot!.Sessions.Count);
    }

    [TestMethod]
    [DataRow(0, true)]
    [DataRow(3, true)]
    [DataRow(19, true)]
    [DataRow(90, true)]
    [DataRow(91, false)]
    public void Scan_UnansweredQuestionInExistingWorkspaceWithoutProcess_RemainsVisibleUntilMaximumAge(
        int days, bool included)
    {
        using var temp = new TestDirectory();
        var workspace = temp.FilePath("resumable-workspace");
        Directory.CreateDirectory(workspace);
        var directory = temp.Session("resumable-question",
            """{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""",
            updatedAt: TestDirectory.Now.AddDays(-days), cwd: workspace);
        File.WriteAllText(Path.Combine(directory, "inuse.2147483647.lock"), "");
        var indexer = new SessionIndexer(temp.Root, temp.Log, _ => false);

        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        var sessions = indexer.Snapshot!.Sessions;
        Assert.AreEqual(included ? 1 : 0, sessions.Count);
        if (included)
            Assert.AreEqual("attention", sessions[0].Activity);
    }

    [TestMethod]
    public void Scan_WaitingWorkspaceIsRemovedAndRestored_ReevaluatesResumabilityOnEachScan()
    {
        using var temp = new TestDirectory();
        var workspace = temp.FilePath("resumable-workspace");
        Directory.CreateDirectory(workspace);
        temp.Session("resumable-question",
            """{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""",
            updatedAt: TestDirectory.Now.AddDays(-3), cwd: workspace);
        var indexer = new SessionIndexer(temp.Root, temp.Log, _ => false);

        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        Assert.AreEqual("attention", indexer.Snapshot!.Sessions.Single().Activity);

        Directory.Delete(workspace);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now.AddSeconds(3)));
        Assert.AreEqual(0, indexer.Snapshot!.Sessions.Count);

        Directory.CreateDirectory(workspace);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now.AddSeconds(6)));
        Assert.AreEqual("attention", indexer.Snapshot!.Sessions.Single().Activity);
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
