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
            git_root: 'C:\Projects\AgentMon'
            repository: "VeryKross/AgentMon"
            branch: 'fix/ken''s-branch'
            name: "Build: relay\nnow \u263a"
            updated_at: 2026-09-23T02:15:01.123Z
            ignored:
              name: Secret nested text
              items: [a, b]
            prompt: SECRET_PROMPT
            """);

        Assert.AreEqual(7, fields.Count);
        Assert.AreEqual("fix/ken's-branch", fields["branch"]);
        Assert.AreEqual("Build: relay\nnow \u263a", fields["name"]);
        Assert.AreEqual(@"C:\Projects\AgentMon", fields["cwd"]);
        Assert.AreEqual(@"C:\Projects\AgentMon", fields["git_root"]);
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
    public void Normalize_BlankWorkspaceTitle_ProducesNonemptyTaskAcceptedByMac()
    {
        var fields = WorkspaceReader.Parse("id: test\nname: '   '\n");
        var session = WorkspaceReader.Normalize(fields, TestDirectory.Now, "ready");
        Assert.AreEqual("Copilot session", session.Task);
        Assert.AreEqual("Untitled Project", session.Project);
    }

    [TestMethod]
    public void Normalize_WorktreeWithoutRepository_UsesCommonGitProjectInsteadOfBranch()
    {
        using var temp = new TestDirectory();
        var project = Path.Combine(temp.Root, "BadCatAgent");
        var gitDir = Path.Combine(project, ".git", "worktrees", "verykross-verbose-journey");
        Directory.CreateDirectory(gitDir);
        File.WriteAllText(Path.Combine(gitDir, "commondir"), "../..");
        var worktree = Path.Combine(temp.Root, "verykross-verbose-journey");
        Directory.CreateDirectory(worktree);
        File.WriteAllText(Path.Combine(worktree, ".git"), $"gitdir: {gitDir}");

        var fields = new Dictionary<string, string>
        {
            ["id"] = "test",
            ["cwd"] = worktree,
            ["branch"] = "verykross-verbose-journey",
            ["name"] = "Bad cat agent"
        };
        var session = WorkspaceReader.Normalize(fields, TestDirectory.Now, "ready");
        Assert.AreEqual("BadCatAgent", session.Project);
        Assert.AreEqual("Bad cat agent", session.Task);
        Assert.AreEqual("verykross-verbose-journey", session.Branch);

        File.WriteAllText(Path.Combine(worktree, ".git"), $"gitdir: {Path.GetRelativePath(worktree, gitDir)}");
        Assert.AreEqual("BadCatAgent", WorkspaceReader.Normalize(fields, TestDirectory.Now, "ready").Project);

        fields["repository"] = "VeryKross/CanonicalRepo";
        Assert.AreEqual("CanonicalRepo", WorkspaceReader.Normalize(fields, TestDirectory.Now, "ready").Project);
    }

    [TestMethod]
    public void Normalize_StandaloneChatWithGeneratedDirectory_UsesChatLabelAndKeepsSubject()
    {
        var fields = WorkspaceReader.Parse("""
            id: chat
            cwd: 'C:\Copilot\worktrees\cautious-system-0de85394'
            name: 'Review the deployment plan'
            """);

        var chat = WorkspaceReader.Normalize(fields, TestDirectory.Now, "ready");
        Assert.AreEqual("Copilot Chat", chat.Project);
        Assert.AreEqual("Review the deployment plan", chat.Task);
        Assert.IsNull(chat.Branch);

        fields["branch"] = "cautious-system-0de85394";
        Assert.AreEqual("cautious-system-0de85394", WorkspaceReader.Normalize(fields, TestDirectory.Now, "ready").Project);
        fields.Remove("branch");

        fields["git_root"] = @"C:\Projects\Project";
        Assert.AreEqual("cautious-system-0de85394", WorkspaceReader.Normalize(fields, TestDirectory.Now, "ready").Project);
        fields.Remove("git_root");

        fields["repository"] = "VeryKross/BadCatAgent";
        Assert.AreEqual("BadCatAgent", WorkspaceReader.Normalize(fields, TestDirectory.Now, "ready").Project);
    }

    [TestMethod]
    [DataRow("""{"type":"assistant.turn_start"}""", true, "working")]
    [DataRow("""{"type":"assistant.turn_end"}""", true, "ready")]
    [DataRow("""{"type":"assistant.turn_start"}""", false, "offline")]
    [DataRow("", true, "ready")]
    [DataRow("""{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""", true, "attention")]
    [DataRow("""{"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}""", false, "offline")]
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
    public void Activity_PreToolAskUserHook_IsAttentionUntilToolExecutes()
    {
        const string waiting = """
            {"type":"assistant.turn_start"}
            {"type":"hook.start","data":{"hookInvocationId":"hook-1","hookType":"preToolUse","input":{"toolCalls":[{"id":"q","name":"ask_user"}]}}}
            """;
        Assert.AreEqual("attention", Activity(waiting));
        var hookCompleted = waiting + "\n" +
            """{"type":"hook.end","data":{"hookInvocationId":"hook-1","hookType":"preToolUse","success":true}}""";
        Assert.AreEqual("attention", Activity(hookCompleted));
        Assert.AreEqual("working", Activity(hookCompleted + "\n" + """
            {"type":"tool.execution_start","data":{"toolCallId":"q","toolName":"ask_user"}}
            {"type":"tool.execution_complete","data":{"toolCallId":"q"}}
            """));
    }

    [TestMethod]
    public void Activity_BadCatAgentHookOnlyInputWaitAfterCompletedFusion_RemainsAttention()
    {
        const string events = """
            {"type":"session.fusion_completed"}
            {"type":"session.fusion_resolved"}
            {"type":"hook.start","data":{"hookType":"userPromptSubmitted"}}
            {"type":"hook.end","data":{"hookType":"userPromptSubmitted","success":true}}
            {"type":"user.message"}
            {"type":"system.message"}
            {"type":"hook.start","data":{"hookType":"preToolUse","input":{"toolCalls":[{"id":"work","name":"powershell"}]}}}
            {"type":"hook.end","data":{"hookType":"preToolUse","success":true}}
            {"type":"hook.start","data":{"hookType":"postToolUse"}}
            {"type":"hook.end","data":{"hookType":"postToolUse","success":true}}
            {"type":"hook.start","data":{"hookType":"preToolUse","input":{"toolCalls":[{"id":"question","name":"ask_user"}]}}}
            {"type":"hook.end","data":{"hookType":"preToolUse","success":true}}
            """;
        var bytes = Encoding.UTF8.GetBytes(events);
        Assert.AreEqual("attention", EventTailReader.Activity(bytes, true,
            TestDirectory.Now.AddHours(-1), TestDirectory.Now));
        Assert.AreEqual("attention", EventTailReader.Activity(bytes, false,
            TestDirectory.Now.AddHours(-1), TestDirectory.Now, hasAvailableWorkspace: true));
    }

    [TestMethod]
    public void Activity_NewerPreToolWorkSupersedesOldQuestionHook()
    {
        const string events = """
            {"type":"assistant.turn_start"}
            {"type":"hook.start","data":{"hookInvocationId":"hook-1","hookType":"preToolUse","input":{"toolCalls":[{"id":"q","name":"ask_user"}]}}}
            {"type":"hook.end","data":{"hookInvocationId":"hook-1","hookType":"preToolUse","success":true}}
            {"type":"hook.start","data":{"hookInvocationId":"hook-2","hookType":"preToolUse","input":{"toolCalls":[{"id":"t","name":"run"}]}}}
            {"type":"hook.end","data":{"hookInvocationId":"hook-2","hookType":"preToolUse","success":true}}
            """;
        Assert.AreEqual("working", Activity(events));
    }

    [TestMethod]
    public void Activity_OldActiveEventsWithLiveProcess_ReturnsReady()
    {
        var bytes = Encoding.UTF8.GetBytes("""{"type":"assistant.turn_start"}""");
        Assert.AreEqual("ready", EventTailReader.Activity(bytes, true, TestDirectory.Now.AddMinutes(-15), TestDirectory.Now));
    }

    [TestMethod]
    public void Activity_AssistantSubturnEnd_RemainsWorkingUntilFusionCompletes()
    {
        const string working = """
            {"type":"user.message"}
            {"type":"session.fusion_commit_started"}
            {"type":"assistant.turn_start"}
            {"type":"tool.execution_start","data":{"toolName":"run","toolCallId":"q"}}
            {"type":"tool.execution_complete","data":{"toolCallId":"q"}}
            {"type":"assistant.turn_end"}
            """;
        Assert.AreEqual("working", Activity(working));
        Assert.AreEqual("ready", Activity(working + "\n" + """{"type":"session.fusion_completed"}"""));
    }

    [TestMethod]
    public void Activity_ModelLifecycle_RemainsWorkingUntilFusionCompletes()
    {
        const string working = """
            {"type":"user.message"}
            {"type":"model.turn_started"}
            {"type":"model.model_call_started"}
            {"type":"model.turn_ended"}
            """;
        Assert.AreEqual("working", Activity(working));
        Assert.AreEqual("ready", Activity(working + "\n" + """{"type":"session.fusion_completed"}"""));
    }

    [TestMethod]
    [DataRow("agentStop", 0)]
    [DataRow("agentStop", 11)]
    [DataRow("agentStop", 16)]
    [DataRow("sessionEnd", 0)]
    [DataRow("sessionEnd", 11)]
    [DataRow("sessionEnd", 16)]
    public void Activity_CompletedStopHookWithoutFusion_ReturnsReady(string hookType, int minutes)
    {
        var events = Encoding.UTF8.GetBytes("""
            {"type":"user.message"}
            {"type":"assistant.turn_start"}
            {"type":"hook.start","data":{"hookType":"preToolUse","input":{"toolCalls":[{"id":"t","name":"run"}]}}}
            {"type":"tool.execution_complete","data":{"toolCallId":"t"}}
            {"type":"assistant.turn_end"}
            {"type":"assistant.turn_start"}
            {"type":"assistant.message"}
            {"type":"assistant.turn_end"}
            """ + "\n" + $$$"""
            {"type":"hook.start","data":{"hookType":"{{{hookType}}}"}}
            {"type":"hook.end","data":{"hookType":"{{{hookType}}}","success":true}}
            {"type":"session.usage_checkpoint"}
            """);
        var updatedAt = TestDirectory.Now.AddMinutes(-minutes);
        Assert.AreEqual("ready", EventTailReader.Activity(events, true, updatedAt, TestDirectory.Now));
        Assert.AreEqual("offline", EventTailReader.Activity(events, false, updatedAt, TestDirectory.Now,
            hasAvailableWorkspace: true));
    }

    [TestMethod]
    [DataRow("agentStop")]
    [DataRow("sessionEnd")]
    public void Activity_StopHookRequiresSuccessfulCompletion(string hookType)
    {
        var events = """
            {"type":"user.message"}
            {"type":"model.turn_started"}
            {"type":"assistant.turn_end"}
            """ + "\n" + $$$"""
            {"type":"hook.start","data":{"hookType":"{{{hookType}}}"}}
            """;
        Assert.AreEqual("working", Activity(events));
        Assert.AreEqual("working", Activity(events + "\n" + $$$"""
            {"type":"hook.end","data":{"hookType":"{{{hookType}}}","success":false}}
            """));
    }

    [TestMethod]
    [DataRow("agentStop")]
    [DataRow("sessionEnd")]
    public void Activity_NewerActivitySupersedesCompletedStopHook(string hookType)
    {
        var completed = $$$"""
            {"type":"hook.end","data":{"hookType":"{{{hookType}}}","success":true}}
            """;
        foreach (var next in new[]
                 {
                     """{"type":"user.message"}""",
                     """{"type":"model.turn_started"}""",
                     """{"type":"assistant.turn_start"}""",
                     """{"type":"hook.start","data":{"hookType":"preToolUse","input":{"toolCalls":[{"id":"t","name":"run"}]}}}"""
                 })
            Assert.AreEqual("working", Activity(completed + "\n" + next));

        const string question = """{"type":"tool.execution_start","data":{"toolCallId":"q","toolName":"ask_user"}}""";
        Assert.AreEqual("ready", Activity(question + "\n" + completed));
        Assert.AreEqual("attention", Activity(completed + "\n" + question));
    }

    [TestMethod]
    public void Activity_ActiveDescendantKeepsCompletedFusionWorking()
    {
        const string events = """
            {"type":"user.message"}
            {"type":"assistant.turn_start"}
            {"type":"assistant.turn_end"}
            {"type":"session.fusion_completed"}
            """;
        Assert.AreEqual("working", EventTailReader.Activity(
            Encoding.UTF8.GetBytes(events), true, TestDirectory.Now, TestDirectory.Now, hasActiveDescendant: true));
    }

    [TestMethod]
    public void Activity_QuestionStillOutranksActiveDescendant()
    {
        const string events = """
            {"type":"session.fusion_completed"}
            {"type":"assistant.turn_start"}
            {"type":"hook.start","data":{"hookType":"preToolUse","input":{"toolCalls":[{"id":"q","name":"ask_user"}]}}}
            """;
        Assert.AreEqual("attention", EventTailReader.Activity(
            Encoding.UTF8.GetBytes(events), true, TestDirectory.Now, TestDirectory.Now, hasActiveDescendant: true));
    }

    [TestMethod]
    public void Activity_UnansweredQuestionRemainsAttentionAfterInactivityUntilAnsweredOrOffline()
    {
        const string events = """
            {"type":"assistant.turn_start"}
            {"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}
            """;
        var stale = TestDirectory.Now.AddHours(-2);
        var unanswered = Encoding.UTF8.GetBytes(events);
        Assert.AreEqual("attention", EventTailReader.Activity(unanswered, true, stale, TestDirectory.Now));
        Assert.AreEqual("offline", EventTailReader.Activity(unanswered, false, stale, TestDirectory.Now));
        var answered = Encoding.UTF8.GetBytes(events + "\n" + """{"type":"tool.execution_complete","data":{"toolCallId":"q"}}""");
        Assert.AreEqual("ready", EventTailReader.Activity(answered, true, stale, TestDirectory.Now));
    }

    [TestMethod]
    [DataRow(0)]
    [DataRow(2)]
    [DataRow(24 * 3)]
    [DataRow(24 * 19)]
    public void Activity_UnansweredQuestionInAvailableWorkspace_RemainsAttentionWithoutProcess(int hours)
    {
        const string events = """
            {"type":"assistant.turn_start"}
            {"type":"tool.execution_start","data":{"toolName":"ask_user","toolCallId":"q"}}
            """;
        var updatedAt = TestDirectory.Now.AddHours(-hours);
        Assert.AreEqual("attention", EventTailReader.Activity(Encoding.UTF8.GetBytes(events), false,
            updatedAt, TestDirectory.Now, hasAvailableWorkspace: true));
        var answered = Encoding.UTF8.GetBytes(events + "\n" +
            """{"type":"tool.execution_complete","data":{"toolCallId":"q"}}""");
        Assert.AreEqual("offline", EventTailReader.Activity(answered, false,
            updatedAt, TestDirectory.Now, hasAvailableWorkspace: true));
        Assert.AreEqual("offline", EventTailReader.Activity(
            Encoding.UTF8.GetBytes("""{"type":"assistant.turn_start"}"""), false,
            updatedAt, TestDirectory.Now, hasAvailableWorkspace: true));
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
