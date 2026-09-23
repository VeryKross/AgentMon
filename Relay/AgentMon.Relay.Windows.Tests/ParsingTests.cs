using System.Diagnostics;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace AgentMon.Relay.Windows.Tests;

[TestClass]
public sealed class ParsingTests
{
    [TestMethod]
    public void Parse_QuotedYamlAndNestedKeys_ReadsOnlyTopLevelMetadata()
    {
        var fields = WorkspaceReader.Parse("""
            id: test
            cwd: 'C:\Projects\AgentMon'
            repository: "VeryKross/AgentMon"
            branch: 'fix/ken''s-branch'
            name: "Build: relay\nnow \u263a"
            updated_at: 2026-09-23T02:15:01.123Z
            ignored:
              name: Secret nested text
              items: [a, b]
            prompt: SECRET_PROMPT
            """);

        Assert.AreEqual(6, fields.Count);
        Assert.AreEqual("fix/ken's-branch", fields["branch"]);
        Assert.AreEqual("Build: relay\nnow \u263a", fields["name"]);
        Assert.AreEqual(@"C:\Projects\AgentMon", fields["cwd"]);
        Assert.AreEqual(TimeSpan.Zero, WorkspaceReader.UpdatedAt(fields)!.Value.Offset);
    }

    [TestMethod]
    public void Normalize_NullRepositoryAndLongUnicodeTitle_UsesBasenameAnd120Scalars()
    {
        var fields = WorkspaceReader.Parse("id: test\ncwd: 'C:\\Users\\SECRET_USER\\Projects\\Relay'\nrepository: null\nbranch: ~\n");
        fields["name"] = string.Concat(Enumerable.Repeat("\U0001F680", 150));
        var session = WorkspaceReader.Normalize(fields, TestDirectory.Now, "ready");
        Assert.AreEqual("Relay", session.Project);
        Assert.IsNull(session.Repository);
        Assert.IsNull(session.Branch);
        Assert.AreEqual(120, session.Task.EnumerateRunes().Count());
        Assert.IsFalse(session.Task.Contains("SECRET_USER", StringComparison.Ordinal));
    }

    [TestMethod]
    [DataRow("""{"type":"assistant.turn_start"}""", true, "working")]
    [DataRow("""{"type":"assistant.turn_end"}""", true, "ready")]
    [DataRow("""{"type":"assistant.turn_start"}""", false, "offline")]
    [DataRow("", true, "ready")]
    [DataRow("""{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""", true, "attention")]
    [DataRow("""{"type":"tool.execution_start","data":{"toolName":"run","toolCallId":"q","arguments":{"toolName":"ask_user"}}}""", true, "ready")]
    [DataRow("""{"type":"tool.execution_start","data":{"toolName":"ask_user"}}""", true, "ready")]
    [DataRow("""{"type":123}""", true, "ready")]
    [DataRow("""["assistant.turn_start"]""", true, "ready")]
    public void Activity_EventTypesAndLiveness_MatchesMac(string events, bool live, string expected)
        => Assert.AreEqual(expected, EventTailReader.Activity(Encoding.UTF8.GetBytes(events), live, TestDirectory.Now, TestDirectory.Now));

    [TestMethod]
    public void Activity_AnsweredQuestionIsNotAttention_OtherUnresolvedQuestionsRemainAttention()
    {
        const string events = """
            {"type":"assistant.turn_start"}
            {"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q1"}}
            {"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q2"}}
            {"type":"tool.execution_complete","data":{"toolCallId":"q2","result":"PRIVATE_RESULT"}}
            """;
        Assert.AreEqual("attention", Activity(events));
        Assert.AreEqual("working", Activity(events + "\n" + """{"type":"tool.execution_complete","data":{"toolCallId":"q1"}}"""));
        Assert.AreEqual("ready", Activity(events + "\n" + """{"type":"assistant.turn_end"}"""));
    }

    [TestMethod]
    public void Activity_OldActiveEventsWithLiveProcess_ReturnsReady()
    {
        var bytes = Encoding.UTF8.GetBytes("""{"type":"assistant.turn_start"}""");
        Assert.AreEqual("ready", EventTailReader.Activity(bytes, true, TestDirectory.Now.AddMinutes(-15), TestDirectory.Now));
    }

    [TestMethod]
    public void Activity_PartialAndMalformedLines_UsesLastCompleteEvent()
    {
        Assert.AreEqual("working", Activity("{bad json}\n{\"type\":\"assistant.turn_start\"}\n{\"type\":\"assistant.turn_"));
        Assert.AreEqual("working", Activity("{\"type\":\"assistant.turn_start\"}\r\n"));
    }

    [TestMethod]
    public void Read_LargeTailAndPartialLeadingLine_NeverExceeds128KiB()
    {
        using var temp = new TestDirectory();
        var path = temp.FilePath("events.jsonl");
        File.WriteAllText(path, "{\"type\":\"assistant.turn_start\",\"data\":\"" +
            new string('x', 200 * 1024) + "\"}\n{\"type\":\"assistant.turn_end\"}\n");
        var tail = EventTailReader.Read(path);
        Assert.IsTrue(tail.Length <= EventTailReader.MaximumBytes);
        Assert.AreEqual("ready", EventTailReader.Activity(tail, true, TestDirectory.Now, TestDirectory.Now));
        Assert.IsFalse(Encoding.UTF8.GetString(tail).Contains('x'));
        File.WriteAllText(path, new string('x', EventTailReader.MaximumBytes + 1));
        Assert.AreEqual(0, EventTailReader.Read(path).Length);
    }

    [TestMethod]
    public void Read_ExactByteBoundary_HandlesUtf8AndReleasesFile()
    {
        using var temp = new TestDirectory();
        var path = temp.FilePath("events.jsonl");
        File.WriteAllText(path, new string('x', EventTailReader.MaximumBytes - 1) + "\n", new UTF8Encoding(false));
        Assert.AreEqual(EventTailReader.MaximumBytes, EventTailReader.Read(path).Length);
        File.Move(path, temp.FilePath("replaced.jsonl"));
        File.WriteAllText(path, """{"type":"assistant.turn_start"}""");
        Assert.AreEqual("working", EventTailReader.Activity(EventTailReader.Read(path), true, TestDirectory.Now, TestDirectory.Now));
    }

    [TestMethod]
    public void HasLiveProcess_DeadMalformedAndLivePidLocks_VerifiesPid()
    {
        using var temp = new TestDirectory();
        File.WriteAllText(temp.FilePath("inuse.not-a-pid.lock"), "");
        File.WriteAllText(temp.FilePath("inuse.0.lock"), "");
        File.WriteAllText(temp.FilePath("inuse.2147483647.lock"), "");
        Assert.IsFalse(SessionIndexer.HasLiveProcess(temp.Root, pid => pid == Environment.ProcessId));
        File.WriteAllText(temp.FilePath($"inuse.{Environment.ProcessId}.lock"), "");
        Assert.IsTrue(SessionIndexer.HasLiveProcess(temp.Root, pid => pid == Environment.ProcessId));
        temp.Session("live", live: true);
        var indexer = new SessionIndexer(temp.Root, temp.Log);
        Assert.IsTrue(indexer.Scan(TestDirectory.Host, TestDirectory.Now));
        Assert.AreEqual("ready", indexer.Snapshot!.Sessions.Single().Activity);
        using var process = Process.GetCurrentProcess();
        Assert.IsFalse(process.HasExited);
    }

    private static string Activity(string events)
        => EventTailReader.Activity(Encoding.UTF8.GetBytes(events), true, TestDirectory.Now, TestDirectory.Now);
}
