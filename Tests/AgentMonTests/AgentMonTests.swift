import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentMon

@Test func parsesWorkspaceMetadata() {
  let source = """
    id: abc-123
    cwd: /Users/example/Repos/AgentMon
    repository: VeryKross/AgentMon
    branch: main
    name: 'Retro status dashboard'
    updated_at: 2026-09-22T01:02:14.092Z
    """

  let fields = WorkspaceYAMLParser.parse(source)

  #expect(fields["id"] == "abc-123")
  #expect(fields["repository"] == "VeryKross/AgentMon")
  #expect(fields["name"] == "Retro status dashboard")
}

@Test func labelsStandaloneChatWithoutHidingProjectSessions() {
  var fields = WorkspaceYAMLParser.parse("""
    id: chat
    cwd: /tmp/studious-meme-4bae8aac
    name: 'A chat about build issues'
    """)
  #expect(CopilotSessionMonitor.projectName(from: fields) == "Copilot Chat")

  fields["branch"] = "studious-meme-4bae8aac"
  #expect(CopilotSessionMonitor.projectName(from: fields) == "studious-meme-4bae8aac")
  fields.removeValue(forKey: "branch")

  fields["git_root"] = "/tmp/AgentMon"
  #expect(CopilotSessionMonitor.projectName(from: fields) == "studious-meme-4bae8aac")
  fields.removeValue(forKey: "git_root")

  fields["repository"] = "VeryKross/AgentMon"
  #expect(CopilotSessionMonitor.projectName(from: fields) == "AgentMon")
  fields.removeValue(forKey: "repository")

  fields["cwd"] = "/tmp/ordinary-folder"
  #expect(CopilotSessionMonitor.projectName(from: fields) == "ordinary-folder")
}

@Test func detectsWorkingAgentFromUnfinishedTurn() throws {
  let events = """
    {"type":"assistant.turn_end"}
    {"type":"assistant.turn_start"}
    {"type":"tool.execution_start"}
    """.data(using: .utf8)!

  let activity = AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  )

  #expect(activity == .working)
}

@Test func detectsReadyAgentFromFinishedTurn() throws {
  let events = """
    {"type":"assistant.turn_start"}
    {"type":"assistant.turn_end"}
    """.data(using: .utf8)!

  let activity = AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  )

  #expect(activity == .ready)
}

@Test func keepsWorkingAcrossCompletedAssistantSubturns() {
  let events = """
    {"type":"user.message"}
    {"type":"session.fusion_commit_started"}
    {"type":"assistant.turn_start"}
    {"type":"tool.execution_start","data":{"toolCallId":"tool-1","toolName":"bash"}}
    {"type":"tool.execution_complete","data":{"toolCallId":"tool-1"}}
    {"type":"assistant.turn_end"}
    """.data(using: .utf8)!

  #expect(AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  ) == .working)
}

@Test func modelLifecycleRemainsWorkingUntilFusionCompletes() {
  let working = """
    {"type":"user.message"}
    {"type":"model.turn_started"}
    {"type":"model.model_call_started"}
    {"type":"model.turn_ended"}
    """

  #expect(AgentEventParser.activity(
    from: Data(working.utf8),
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  ) == .working)
  #expect(AgentEventParser.activity(
    from: Data((working + "\n" + #"{"type":"session.fusion_completed"}"#).utf8),
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  ) == .ready)
}

@Test(arguments: ["agentStop", "sessionEnd"], [0.0, 11 * 60.0, 16 * 60.0])
func completedStopHookEndsTurnWithoutFusionEvent(hookType: String, age: TimeInterval) {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let events = """
    {"type":"user.message"}
    {"type":"assistant.turn_start"}
    {"type":"hook.start","data":{"hookType":"preToolUse","input":{"toolCalls":[{"id":"tool-1","name":"bash"}]}}}
    {"type":"tool.execution_complete","data":{"toolCallId":"tool-1"}}
    {"type":"assistant.turn_end"}
    {"type":"assistant.turn_start"}
    {"type":"assistant.message"}
    {"type":"assistant.turn_end"}
    {"type":"hook.start","data":{"hookType":"\(hookType)"}}
    {"type":"hook.end","data":{"hookType":"\(hookType)","success":true}}
    {"type":"session.usage_checkpoint"}
    """

  for live in [true, false] {
    #expect(AgentEventParser.activity(
      from: Data(events.utf8),
      hasLiveProcess: live,
      updatedAt: now.addingTimeInterval(-age),
      now: now,
      hasAvailableWorkspace: true
    ) == (live ? .ready : .offline))
  }
}

@Test(arguments: ["agentStop", "sessionEnd"])
func stopHookDoesNotFinishTurnBeforeSuccessfulCompletion(hookType: String) {
  let events = """
    {"type":"user.message"}
    {"type":"model.turn_started"}
    {"type":"assistant.turn_end"}
    {"type":"hook.start","data":{"hookType":"\(hookType)"}}
    """

  for suffix in ["", "\n" + """
    {"type":"hook.end","data":{"hookType":"\(hookType)","success":false}}
    """] {
    #expect(AgentEventParser.activity(
      from: Data((events + suffix).utf8),
      hasLiveProcess: true,
      updatedAt: .now,
      now: .now
    ) == .working)
  }
}

@Test(arguments: ["agentStop", "sessionEnd"])
func newerActivitySupersedesCompletedStopHook(hookType: String) {
  let completed = """
    {"type":"hook.end","data":{"hookType":"\(hookType)","success":true}}
    """
  for next in [
    #"{"type":"user.message"}"#,
    #"{"type":"model.turn_started"}"#,
    #"{"type":"assistant.turn_start"}"#,
    #"{"type":"hook.start","data":{"hookType":"preToolUse","input":{"toolCalls":[{"id":"tool-2","name":"bash"}]}}}"#,
  ] {
    #expect(AgentEventParser.activity(
      from: Data((completed + "\n" + next).utf8),
      hasLiveProcess: true,
      updatedAt: .now,
      now: .now
    ) == .working)
  }

  let question = """
    {"type":"tool.execution_start","data":{"toolCallId":"question-1","toolName":"ask_user"}}
    """
  #expect(AgentEventParser.activity(
    from: Data((question + "\n" + completed).utf8),
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  ) == .ready)
  #expect(AgentEventParser.activity(
    from: Data((completed + "\n" + question).utf8),
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  ) == .attention)
}

@Test func activeDescendantKeepsCompletedFusionWorking() {
  let events = """
    {"type":"user.message"}
    {"type":"assistant.turn_start"}
    {"type":"assistant.turn_end"}
    {"type":"session.fusion_completed"}
    """.data(using: .utf8)!

  #expect(AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    hasActiveDescendant: true,
    updatedAt: .now,
    now: .now
  ) == .working)
}

@Test func questionStillOutranksActiveDescendant() {
  let events = """
    {"type":"session.fusion_completed"}
    {"type":"assistant.turn_start"}
    {"type":"hook.start","data":{"hookType":"preToolUse","input":{"toolCalls":[{"id":"question-1","name":"ask_user"}]}}}
    """.data(using: .utf8)!

  #expect(AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    hasActiveDescendant: true,
    updatedAt: .now,
    now: .now
  ) == .attention)
}

@Test func processTreeFindsWorkButIgnoresPersistentHelpers() {
  let tree = ProcessTreeSnapshot(entries: [
    .init(pid: 20, parentPID: 10, command: "/plugins/computer-use/computer-use-mcp"),
    .init(pid: 30, parentPID: 10, command: "/usr/bin/xcodebuild test"),
    .init(pid: 40, parentPID: 20, command: "/plugins/helper-child"),
    .init(pid: 60, parentPID: 50, command: "/plugins/computer-use/computer-use-mcp"),
    .init(pid: 70, parentPID: 60, command: "/plugins/helper-child"),
  ])

  #expect(tree.hasActiveDescendant(of: 10))
  #expect(!tree.hasActiveDescendant(of: 50))
  #expect(!tree.hasActiveDescendant(of: 999))
}

@Test func processTreeCaptureFindsLiveChild() throws {
  let child = Process()
  child.executableURL = URL(fileURLWithPath: "/bin/sleep")
  child.arguments = ["5"]
  try child.run()
  defer {
    if child.isRunning {
      child.terminate()
    }
    child.waitUntilExit()
  }

  #expect(ProcessTreeSnapshot.capture().hasActiveDescendant(of: getpid()))
}

@Test func completedSessionWithPersistentExtensionRuntimeIsReady() {
  let tree = ProcessTreeSnapshot(entries: [
    .init(pid: 20, parentPID: 10, command: "/plugins/computer-use/computer-use-mcp"),
    .init(pid: 30, parentPID: 10, command: "/cache/cli/1.0.94-3/copilot extension_bootstrap.mjs"),
  ])
  #expect(!tree.hasActiveDescendant(of: 10))
  let events = Data("""
    {"type":"user.message"}
    {"type":"assistant.turn_start"}
    {"type":"assistant.turn_end"}
    {"type":"session.fusion_completed"}
    {"type":"session.usage_checkpoint"}
    """.utf8)
  #expect(AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    hasActiveDescendant: tree.hasActiveDescendant(of: 10),
    updatedAt: .now,
    now: .now
  ) == .ready)
  #expect(AgentEventParser.activity(
    from: Data(),
    hasLiveProcess: true,
    hasActiveDescendant: tree.hasActiveDescendant(of: 10),
    updatedAt: .now,
    now: .now
  ) == .ready)
}

@Test func extensionHelperDoesNotHideSeparateWorkOrSimilarCommands() {
  let tree = ProcessTreeSnapshot(entries: [
    .init(pid: 20, parentPID: 10, command: "/cache/copilot extension_bootstrap.mjs"),
    .init(pid: 30, parentPID: 10, command: "/usr/bin/xcodebuild test"),
    .init(pid: 50, parentPID: 40, command: "/cache/copilot --server --stdio"),
    .init(pid: 70, parentPID: 60, command: "/bin/echo copilot extension_bootstrap.mjs"),
    .init(pid: 90, parentPID: 80, command: "/cache/copilot some_other_script.mjs"),
  ])
  for pid: Int32 in [10, 40, 60, 80] {
    #expect(tree.hasActiveDescendant(of: pid))
  }
}

@Test func findsLatestTurnIntervalFromPromptToCompletion() throws {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let completed = Data("""
    {"type":"user.message","timestamp":"2026-10-25T17:00:00.000Z"}
    {"type":"hook.end","data":{"hookType":"agentStop","success":true},"timestamp":"2026-10-25T17:05:00.000Z"}
    {"type":"user.message","timestamp":"2026-10-25T17:17:12.560Z"}
    {"type":"assistant.turn_end"}
    {"type":"hook.end","data":{"hookType":"agentStop","success":true},"timestamp":"2026-10-25T17:17:18.193Z"}
    {"type":"session.usage_checkpoint","timestamp":"2026-10-25T17:17:20.000Z"}
    """.utf8)
  let interval = try #require(AgentEventParser.latestTurnInterval(from: completed, now: now))
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  let prompt = try #require(formatter.date(from: "2026-10-25T17:17:12.560Z"))
  let stop = try #require(formatter.date(from: "2026-10-25T17:17:18.193Z"))
  #expect(interval.contains(prompt.addingTimeInterval(1)))
  #expect(!interval.contains(prompt.addingTimeInterval(-2)))
  #expect(!interval.contains(stop.addingTimeInterval(60)))

  let running = Data("""
    {"type":"user.message","timestamp":"2026-10-25T17:17:12Z"}
    {"type":"assistant.turn_start"}
    """.utf8)
  #expect(AgentEventParser.latestTurnInterval(from: running, now: stop.addingTimeInterval(600))?
    .contains(stop.addingTimeInterval(300)) == true)
  #expect(AgentEventParser.latestTurnInterval(from: Data(#"{"type":"assistant.turn_end"}"#.utf8), now: now) == nil)
}

@Test func sharedRuntimeCountsOnlyChildrenStartedDuringTheSessionsTurn() {
  let sessionLoaded = Date(timeIntervalSince1970: 1_800_000_000)
  let turn = DateInterval(start: sessionLoaded.addingTimeInterval(2), duration: 6)
  let tree = ProcessTreeSnapshot(entries: [
    .init(pid: 20, parentPID: 10, command: "npm exec scholar-sidekick-mcp@0.8.8", startedAt: sessionLoaded),
    .init(pid: 21, parentPID: 10, command: "/usr/bin/swift build", startedAt: sessionLoaded.addingTimeInterval(600)),
    .init(pid: 22, parentPID: 10, command: "/bin/bash -c make", startedAt: nil),
  ])
  #expect(!tree.hasActiveDescendant(of: 10, startedDuring: turn))
  #expect(tree.hasActiveDescendant(of: 10))

  let busy = ProcessTreeSnapshot(entries: [
    .init(pid: 20, parentPID: 10, command: "npm exec scholar-sidekick-mcp@0.8.8", startedAt: sessionLoaded),
    .init(pid: 23, parentPID: 10, command: "/usr/bin/xcodebuild test", startedAt: turn.start.addingTimeInterval(3)),
  ])
  #expect(busy.hasActiveDescendant(of: 10, startedDuring: turn))
}

@Test func turnFilterSearchesGrandchildrenButNotHelperSubtrees() {
  let loaded = Date(timeIntervalSince1970: 1_800_000_000)
  let turn = DateInterval(start: loaded.addingTimeInterval(60), duration: 30)
  let duringTurn = turn.start.addingTimeInterval(5)
  let tree = ProcessTreeSnapshot(entries: [
    .init(pid: 20, parentPID: 10, command: "/bin/zsh -i", startedAt: loaded),
    .init(pid: 30, parentPID: 20, command: "/usr/bin/swift test", startedAt: duringTurn),
    .init(pid: 40, parentPID: 11, command: "npm exec scholar-sidekick-mcp", startedAt: loaded),
    .init(pid: 50, parentPID: 40, command: "node server.js", startedAt: loaded),
    .init(pid: 60, parentPID: 12, command: "/plugins/computer-use/computer-use-mcp", startedAt: loaded),
    .init(pid: 70, parentPID: 60, command: "/plugins/helper-child", startedAt: duringTurn),
    .init(pid: 80, parentPID: 13, command: "/bin/zsh -i", startedAt: loaded),
    .init(pid: 81, parentPID: 80, command: "/bin/sleep 9", startedAt: nil),
  ])
  #expect(tree.hasActiveDescendant(of: 10, startedDuring: turn))
  #expect(!tree.hasActiveDescendant(of: 11, startedDuring: turn))
  #expect(!tree.hasActiveDescendant(of: 12, startedDuring: turn))
  #expect(!tree.hasActiveDescendant(of: 13, startedDuring: turn))
}

@Test func processTreeCaptureRecordsChildStartTime() throws {
  let before = Date.now.addingTimeInterval(-1)
  let child = Process()
  child.executableURL = URL(fileURLWithPath: "/bin/sleep")
  child.arguments = ["5"]
  try child.run()
  defer {
    if child.isRunning { child.terminate() }
    child.waitUntilExit()
  }
  let window = DateInterval(start: before, end: .now.addingTimeInterval(1))
  #expect(ProcessTreeSnapshot.capture().hasActiveDescendant(of: getpid(), startedDuring: window))
  #expect(
    !ProcessTreeSnapshot.capture().hasActiveDescendant(
      of: getpid(), startedDuring: DateInterval(start: before.addingTimeInterval(-60), duration: 30)))
}

@Test func verifiesLiveSessionStatusWhenRequested() throws {
  let environment = ProcessInfo.processInfo.environment
  guard let id = environment["AGENTMON_TEST_SESSION_ID"],
    let expected = environment["AGENTMON_TEST_SESSION_ACTIVITY"]
  else { return }
  let session = try #require(CopilotSessionMonitor().sessions().first { $0.id == id })
  #expect(session.activity.rawValue == expected)
}

@Test func expandsEventTailPastHookTrafficToFindLifecycle() throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("agentmon-events-\(UUID().uuidString).jsonl")
  defer { try? FileManager.default.removeItem(at: url) }

  var events = Data("{\"type\":\"user.message\"}\n".utf8)
  let hook = Data(
    "{\"type\":\"hook.end\",\"data\":{\"padding\":\"session.fusion_completed ".utf8
  )
    + Data(repeating: 0x78, count: 2_048)
    + Data("\"}}\n".utf8)
  for _ in 0..<100 {
    events.append(hook)
  }
  try events.write(to: url)

  let tail = CopilotSessionMonitor.tail(of: url)
  #expect(tail.count > 128 * 1_024)
  #expect(AgentEventParser.activity(
    from: tail,
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  ) == .working)
}

@Test(arguments: ["agentStop", "sessionEnd"])
func completedStopHookIsEventTailBoundary(hookType: String) throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("agentmon-events-\(UUID().uuidString).jsonl")
  defer { try? FileManager.default.removeItem(at: url) }

  var events = Data("{\"type\":\"user.message\"}\n".utf8)
  events.append(Data(repeating: 0x20, count: 160 * 1_024))
  events.append(Data("""

    {"type":"hook.end","data":{"hookType":"\(hookType)","success":true}}
    {"type":"session.usage_checkpoint"}
    """.utf8))
  try events.write(to: url)

  let tail = CopilotSessionMonitor.tail(of: url)
  #expect(tail.count <= 128 * 1_024)
  #expect(AgentEventParser.activity(
    from: tail,
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  ) == .ready)
}

@Test func detectsWorkingAgentBeforeAssistantTurnStarts() {
  let events = """
    {"type":"assistant.turn_start"}
    {"type":"assistant.turn_end"}
    {"type":"user.message"}
    {"type":"hook.start"}
    {"type":"hook.end"}
    """.data(using: .utf8)!

  let activity = AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  )

  #expect(activity == .working)
}

@Test func ignoresStaleMessageWithoutAssistantTurn() {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let activity = AgentEventParser.activity(
    from: Data(#"{"type":"user.message"}"#.utf8),
    hasLiveProcess: true,
    updatedAt: now.addingTimeInterval(-16 * 60),
    now: now
  )

  #expect(activity == .ready)
}

@Test func detectsAgentWaitingForUser() {
  let events = """
    {"type":"assistant.turn_start"}
    {"type":"tool.execution_start","data":{"toolCallId":"question-1","toolName":"ask_user"}}
    """.data(using: .utf8)!

  let activity = AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  )

  #expect(activity == .attention)
}

@Test func detectsAgentBlockedBeforeAskUserExecution() {
  let events = """
    {"type":"assistant.turn_start"}
    {"type":"hook.start","data":{"hookInvocationId":"hook-1","hookType":"preToolUse","input":{"toolCalls":[{"id":"question-1","name":"ask_user"}]}}}
    """.data(using: .utf8)!

  #expect(AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  ) == .attention)
}

@Test func preToolHookEndDoesNotMeanUserAnswered() {
  let events = """
    {"type":"assistant.turn_start"}
    {"type":"hook.start","data":{"hookInvocationId":"hook-1","hookType":"preToolUse","input":{"toolCalls":[{"id":"question-1","name":"ask_user"}]}}}
    {"type":"hook.end","data":{"hookInvocationId":"hook-1","hookType":"preToolUse","success":true}}
    """.data(using: .utf8)!

  #expect(AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  ) == .attention)
}

@Test func ignoresAnsweredAskUserPreToolHook() {
  let events = """
    {"type":"assistant.turn_start"}
    {"type":"hook.start","data":{"hookInvocationId":"hook-1","hookType":"preToolUse","input":{"toolCalls":[{"id":"question-1","name":"ask_user"}]}}}
    {"type":"hook.end","data":{"hookInvocationId":"hook-1","hookType":"preToolUse","success":true}}
    {"type":"tool.execution_start","data":{"toolCallId":"question-1","toolName":"ask_user"}}
    {"type":"tool.execution_complete","data":{"toolCallId":"question-1"}}
    """.data(using: .utf8)!

  #expect(AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  ) == .working)
}

@Test func newerPreToolWorkSupersedesOldQuestionHook() {
  let events = """
    {"type":"assistant.turn_start"}
    {"type":"hook.start","data":{"hookInvocationId":"hook-1","hookType":"preToolUse","input":{"toolCalls":[{"id":"question-1","name":"ask_user"}]}}}
    {"type":"hook.end","data":{"hookInvocationId":"hook-1","hookType":"preToolUse","success":true}}
    {"type":"hook.start","data":{"hookInvocationId":"hook-2","hookType":"preToolUse","input":{"toolCalls":[{"id":"tool-2","name":"bash"}]}}}
    {"type":"hook.end","data":{"hookInvocationId":"hook-2","hookType":"preToolUse","success":true}}
    """.data(using: .utf8)!

  #expect(AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  ) == .working)
}

@Test func ignoresAnsweredUserQuestion() {
  let events = """
    {"type":"assistant.turn_start"}
    {"type":"tool.execution_start","data":{"toolCallId":"question-1","toolName":"ask_user"}}
    {"type":"tool.execution_complete","data":{"toolCallId":"question-1"}}
    {"type":"assistant.turn_end"}
    """.data(using: .utf8)!

  let activity = AgentEventParser.activity(
    from: events,
    hasLiveProcess: true,
    updatedAt: .now,
    now: .now
  )

  #expect(activity == .ready)
}

@Test func keepsUnansweredQuestionUntilAnsweredOrOfflineDespiteInactivity() {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let stale = now.addingTimeInterval(-2 * 3_600)
  let events = """
    {"type":"assistant.turn_start"}
    {"type":"tool.execution_start","data":{"toolCallId":"question-1","toolName":"ask_user"}}
    """

  #expect(AgentEventParser.activity(
    from: Data(events.utf8),
    hasLiveProcess: true,
    updatedAt: stale,
    now: now
  ) == .attention)
  #expect(AgentEventParser.activity(
    from: Data(events.utf8),
    hasLiveProcess: false,
    updatedAt: stale,
    now: now
  ) == .offline)
  #expect(AgentEventParser.activity(
    from: Data((events + "\n" + """
      {"type":"tool.execution_complete","data":{"toolCallId":"question-1"}}
      """).utf8),
    hasLiveProcess: true,
    updatedAt: stale,
    now: now
  ) == .ready)
  #expect(AgentEventParser.activity(
    from: Data(#"{"type":"assistant.turn_start"}"#.utf8),
    hasLiveProcess: true,
    updatedAt: stale,
    now: now
  ) == .ready)
}

@Test(arguments: [0.0, 2 * 3_600.0, 19 * 86_400.0])
func classifiesDormantQuestionByWorkspaceAvailability(age: TimeInterval) {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let events = """
    {"type":"assistant.turn_start"}
    {"type":"tool.execution_start","data":{"toolCallId":"question-1","toolName":"ask_user"}}
    """

  #expect(AgentEventParser.activity(
    from: Data(events.utf8),
    hasLiveProcess: false,
    updatedAt: now.addingTimeInterval(-age),
    now: now
  ) == .offline)
  #expect(AgentEventParser.activity(
    from: Data(events.utf8),
    hasLiveProcess: false,
    updatedAt: now.addingTimeInterval(-age),
    now: now,
    hasAvailableWorkspace: true
  ) == .attention)
  #expect(AgentEventParser.activity(
    from: Data((events + "\n" + """
      {"type":"tool.execution_complete","data":{"toolCallId":"question-1"}}
      """).utf8),
    hasLiveProcess: false,
    updatedAt: now.addingTimeInterval(-age),
    now: now,
    hasAvailableWorkspace: true
  ) == .offline)
}

@Test func recognizesOnlyExistingAbsoluteWorkspaceDirectories() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("agentmon-workspace-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: directory) }

  #expect(CopilotSessionMonitor.hasAvailableWorkspace(from: ["cwd": directory.path]))
  #expect(!CopilotSessionMonitor.hasAvailableWorkspace(from: [:]))
  #expect(!CopilotSessionMonitor.hasAvailableWorkspace(from: ["cwd": ""]))
  #expect(!CopilotSessionMonitor.hasAvailableWorkspace(from: ["cwd": "."]))
  #expect(!CopilotSessionMonitor.hasAvailableWorkspace(
    from: ["cwd": directory.appendingPathComponent("removed-worktree").path]))

  let file = directory.appendingPathComponent("not-a-directory")
  try Data().write(to: file)
  #expect(!CopilotSessionMonitor.hasAvailableWorkspace(from: ["cwd": file.path]))
}

@Test func treatsMissingProcessAsOffline() {
  let activity = AgentEventParser.activity(
    from: Data(),
    hasLiveProcess: false,
    updatedAt: .now,
    now: .now
  )

  #expect(activity == .offline)
}

@Test func prioritizesDormantAttentionSessionOverRecentActivity() {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  func session(_ id: String, _ activity: AgentActivity, updatedAt: Date) -> AgentSession {
    AgentSession(
      id: id,
      project: "AgentMon",
      task: id,
      repository: nil,
      branch: nil,
      activity: activity,
      updatedAt: updatedAt
    )
  }

  let sessions = [
    session("ready-now", .ready, updatedAt: now),
    session("working-now", .working, updatedAt: now),
    session("waiting-yesterday", .attention, updatedAt: now.addingTimeInterval(-86_400)),
  ].sorted(by: AgentSession.priorityOrdered)

  #expect(sessions.map(\.id) == ["waiting-yesterday", "working-now", "ready-now"])
}

@Test func badCatAgentHookOnlyInputWaitAfterCompletedFusionRemainsAttention() {
  let events = """
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
    """
  let now = Date.now
  #expect(AgentEventParser.activity(
    from: Data(events.utf8),
    hasLiveProcess: true,
    updatedAt: now.addingTimeInterval(-3_600),
    now: now
  ) == .attention)
}

@Test func sameProjectAcrossHostsKeepsEverySessionAndItsOwnState() {
  let now = Date.now
  let pc = AgentHost(id: "pc", name: "Windows Desktop", platform: .windows, isLocal: false)
  let mac = AgentHost(id: "local", name: "Mac Mini", platform: .macOS, isLocal: true)
  func session(_ id: String, _ activity: AgentActivity, host: AgentHost) -> AgentSession {
    AgentSession(
      id: id, project: "BadCatAgent", task: "Collaborative work",
      repository: "VeryKross/BadCatAgent", branch: host.isLocal ? "mac-work" : "windows-work",
      activity: activity, updatedAt: now
    ).assigning(host: host)
  }

  let local = [session("shared-id", .working, host: mac), session("ready", .ready, host: mac)]
  let remote = RelaySnapshot(
    protocolVersion: 1, relayVersion: "0.2.5", generatedAt: now,
    host: .init(id: pc.id, name: pc.name, platform: pc.platform),
    sessions: [
      .init(id: "shared-id", project: "BadCatAgent", task: "Collaborative work",
        repository: "VeryKross/BadCatAgent", branch: "windows-work",
        activity: .attention, updatedAt: now),
      .init(id: "ready", project: "BadCatAgent", task: "Collaborative work",
        repository: "VeryKross/BadCatAgent", branch: "windows-work",
        activity: .offline, updatedAt: now),
    ]
  ).agentSessions()
  let merged = AgentSession.merged(local: local, remote: remote, now: now)
  #expect(merged.map(\.id) == ["pc:shared-id", "local:shared-id", "local:ready", "pc:ready"])
  #expect(merged.map(\.activity) == [.attention, .working, .ready, .offline])
  #expect(merged.allSatisfy { $0.project == "BadCatAgent" })
  #expect(merged[0].sourceLine == "PC • Windows Desktop • windows-work")
  #expect(merged[1].sourceLine == "MAC • Mac Mini • mac-work")

  var tracker = SessionActivityTracker()
  tracker.update(with: merged)
  let updated = AgentSession.merged(
    local: [session("shared-id", .ready, host: mac), session("ready", .ready, host: mac)],
    remote: remote, now: now
  )
  tracker.update(with: updated)
  #expect(tracker.generations == ["local:shared-id": 1])
  #expect(updated.first?.activity == .attention)
}

@Test @MainActor func rendersCollaborativeSessionRows() throws {
  let pc = AgentHost(id: "pc", name: "Windows Desktop", platform: .windows, isLocal: false)
  let model = DashboardModel()
  let sessions = [
    AgentSession(id: "waiting", project: "BadCatAgent", task: "Waiting for installation choices",
      repository: "VeryKross/BadCatAgent", branch: "windows-work",
      activity: .attention, updatedAt: .now, host: pc),
    AgentSession(id: "working", project: "BadCatAgent", task: "Implementing the Mac companion",
      repository: "VeryKross/BadCatAgent", branch: "mac-work",
      activity: .working, updatedAt: .now),
    AgentSession(id: "ready", project: "BadCatAgent", task: "Ready for the next assignment",
      repository: "VeryKross/BadCatAgent", branch: nil,
      activity: .ready, updatedAt: .now, host: pc),
    AgentSession(id: "long", project: "A collaborative project with an unusually long name",
      task: "Host and state should remain visible when the project name is truncated",
      repository: nil, branch: "a-very-long-branch-name-with-additional-work-in-progress",
      activity: .attention, updatedAt: .now, host: pc),
  ]
  let content = VStack(spacing: 0) {
    ForEach(sessions) { session in
      AgentRow(session: session)
    }
  }
  .frame(width: 820, height: 416)
  .background(RetroTheme.paper)
  .environmentObject(model)
  let renderer = ImageRenderer(content: content)
  let image = try #require(renderer.nsImage)
  #expect(image.size == NSSize(width: 820, height: 416))
  if let outputPath = ProcessInfo.processInfo.environment["AGENTMON_SESSION_SNAPSHOT"] {
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
  }
}

@Test func excludesSessionsOver90DaysRegardlessOfActivityOrHost() {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let remote = AgentHost(id: "windows", name: "Windows", platform: .windows, isLocal: false)

  for host in [AgentHost.local, remote] {
    for activity in [AgentActivity.attention, .working, .ready, .offline] {
      for age in [89 * 86_400, 90 * 86_400, 90 * 86_400 + 1, 201 * 86_400] {
        let session = AgentSession(
          id: "session",
          project: "AgentMon",
          task: "Old session",
          repository: nil,
          branch: nil,
          activity: activity,
          updatedAt: now.addingTimeInterval(-Double(age)),
          host: host
        )
        #expect(session.isWithinMaximumAge(now: now) == (age <= 90 * 86_400))
      }
    }
  }
}

@Test func sessionCrossing90DayCutoffBecomesIneligible() {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let session = AgentSession(
    id: "session",
    project: "AgentMon",
    task: "Pending question",
    repository: nil,
    branch: nil,
    activity: .attention,
    updatedAt: now.addingTimeInterval(-90 * 86_400)
  )

  #expect(session.isWithinMaximumAge(now: now))
  #expect(!session.isWithinMaximumAge(now: now.addingTimeInterval(1)))
}

@Test func flashesOnlyWhenAnExistingWorkingSessionBecomesReady() {
  var tracker = SessionActivityTracker()

  func session(_ id: String, _ activity: AgentActivity) -> AgentSession {
    AgentSession(
      id: id,
      project: "AgentMon",
      task: "Working",
      repository: nil,
      branch: nil,
      activity: activity,
      updatedAt: .now
    )
  }

  tracker.update(with: [session("a", .ready), session("b", .working)])
  #expect(tracker.generations.isEmpty)

  tracker.update(with: [session("a", .working), session("b", .ready)])
  #expect(tracker.generations == ["b": 1])

  tracker.update(with: [session("a", .ready), session("b", .ready)])
  #expect(tracker.generations == ["a": 1, "b": 1])

  tracker.update(with: [session("a", .ready), session("b", .ready)])
  #expect(tracker.generations == ["a": 1, "b": 1])

  tracker.update(with: [session("a", .attention), session("b", .working)])
  tracker.update(with: [session("a", .ready), session("b", .ready)])
  #expect(tracker.generations == ["a": 1, "b": 2])

  tracker.update(with: [])
  tracker.update(with: [session("b", .ready)])
  #expect(tracker.generations.isEmpty)
}

private func trackedSession(
  _ id: String, _ activity: AgentActivity, updatedAt: Date, project: String = "AgentMon"
) -> AgentSession {
  AgentSession(
    id: id, project: project, task: "Work", repository: nil, branch: nil,
    activity: activity, updatedAt: updatedAt)
}

@Test func tracksTimeInCurrentStateFromFirstSightingAndTransitions() {
  let start = Date(timeIntervalSince1970: 1_800_000_000)
  var tracker = SessionActivityTracker()

  tracker.update(
    with: [trackedSession("a", .ready, updatedAt: start.addingTimeInterval(-600))], now: start)
  #expect(tracker.stateSince["a"] == start.addingTimeInterval(-600))

  let later = start.addingTimeInterval(30)
  tracker.update(with: [trackedSession("a", .ready, updatedAt: later)], now: later)
  #expect(tracker.stateSince["a"] == start.addingTimeInterval(-600))

  let working = start.addingTimeInterval(60)
  tracker.update(with: [trackedSession("a", .working, updatedAt: working)], now: working)
  #expect(tracker.stateSince["a"] == working)

  let future = start.addingTimeInterval(9_999)
  tracker.update(with: [trackedSession("b", .ready, updatedAt: future)], now: working)
  #expect(tracker.stateSince["b"] == working)
}

@Test func marksFinishedSessionsUnseenUntilAcknowledgedOrActiveAgain() {
  let t0 = Date(timeIntervalSince1970: 1_800_000_000)
  var tracker = SessionActivityTracker()

  tracker.update(with: [trackedSession("a", .working, updatedAt: t0), trackedSession("b", .ready, updatedAt: t0)], now: t0)
  #expect(tracker.unseenCompletions.isEmpty)

  let t1 = t0.addingTimeInterval(1_020)
  tracker.update(with: [trackedSession("a", .ready, updatedAt: t1), trackedSession("b", .ready, updatedAt: t1)], now: t1)
  #expect(tracker.unseenCompletions == ["a"])

  tracker.acknowledge("a")
  #expect(tracker.unseenCompletions.isEmpty)

  tracker.update(with: [trackedSession("a", .working, updatedAt: t1)], now: t1.addingTimeInterval(3))
  tracker.update(with: [trackedSession("a", .ready, updatedAt: t1)], now: t1.addingTimeInterval(6))
  #expect(tracker.unseenCompletions == ["a"])
  tracker.update(with: [trackedSession("a", .working, updatedAt: t1)], now: t1.addingTimeInterval(9))
  #expect(tracker.unseenCompletions.isEmpty)

  tracker.update(with: [trackedSession("a", .ready, updatedAt: t1)], now: t1.addingTimeInterval(12))
  tracker.acknowledgeAll()
  #expect(tracker.unseenCompletions.isEmpty)
}

@Test func keepsHistoryThroughBriefAbsenceButForgetsAfterRetention() {
  let t0 = Date(timeIntervalSince1970: 1_800_000_000)
  var tracker = SessionActivityTracker()
  tracker.update(with: [trackedSession("a", .working, updatedAt: t0)], now: t0)
  tracker.update(with: [trackedSession("a", .ready, updatedAt: t0)], now: t0.addingTimeInterval(60))
  let finishedAt = t0.addingTimeInterval(60)

  tracker.update(with: [], now: t0.addingTimeInterval(120))
  #expect(tracker.unseenCompletions == ["a"])
  tracker.update(with: [trackedSession("a", .ready, updatedAt: t0)], now: t0.addingTimeInterval(180))
  #expect(tracker.unseenCompletions == ["a"])
  #expect(tracker.stateSince["a"] == finishedAt)

  let gone = t0.addingTimeInterval(180 + SessionActivityTracker.retention)
  tracker.update(with: [], now: gone)
  #expect(tracker.unseenCompletions.isEmpty)
  #expect(tracker.stateSince["a"] == nil)
}

@Test func logsStateChangesNewestFirstWithBoundedHistory() {
  let t0 = Date(timeIntervalSince1970: 1_800_000_000)
  var tracker = SessionActivityTracker()
  tracker.update(with: [trackedSession("a", .working, updatedAt: t0, project: "Frontend")], now: t0)
  #expect(tracker.events.isEmpty)

  let steps: [(TimeInterval, AgentActivity)] = [
    (1_020, .ready), (1_100, .attention), (1_200, .working), (1_300, .offline), (1_400, .ready),
    (1_500, .working),
  ]
  for (offset, activity) in steps {
    tracker.update(
      with: [trackedSession("a", activity, updatedAt: t0, project: "Frontend")],
      now: t0.addingTimeInterval(offset))
  }
  #expect(
    tracker.events.map(\.message) == [
      "started working", "is ready", "went to sleep", "resumed working", "needs you",
      "finished after 17M",
    ])
  #expect(tracker.events.first?.date == t0.addingTimeInterval(1_500))
  #expect(tracker.events.allSatisfy { $0.project == "Frontend" && $0.platform == .macOS })

  for index in 0..<40 {
    tracker.update(
      with: [trackedSession("a", index.isMultiple(of: 2) ? .ready : .working, updatedAt: t0)],
      now: t0.addingTimeInterval(2_000 + Double(index)))
  }
  #expect(tracker.events.count == SessionActivityTracker.eventLimit)
  #expect(Set(tracker.events.map(\.id)).count == SessionActivityTracker.eventLimit)
}

@Test func ordersUnseenCompletionsDirectlyBelowAttention() {
  let now = Date.now
  let sessions = [
    trackedSession("ready", .ready, updatedAt: now),
    trackedSession("working", .working, updatedAt: now),
    trackedSession("done", .ready, updatedAt: now.addingTimeInterval(-600)),
    trackedSession("asleep", .offline, updatedAt: now),
    trackedSession("waiting", .attention, updatedAt: now),
  ]
  let ordered = AgentSession.displayOrdered(sessions, unseenCompletions: ["done"])
  #expect(ordered.map(\.id) == ["waiting", "done", "working", "ready", "asleep"])
  #expect(
    AgentSession.displayOrdered(sessions, unseenCompletions: []).map(\.id)
      == ["waiting", "working", "ready", "done", "asleep"])
}

@Test func formatsDurations() {
  #expect(DisplayFormat.duration(-5) == "0S")
  #expect(DisplayFormat.duration(45) == "45S")
  #expect(DisplayFormat.duration(17 * 60 + 40) == "17M")
  #expect(DisplayFormat.duration(3_600) == "1H")
  #expect(DisplayFormat.duration(3_900) == "1H 5M")
  #expect(DisplayFormat.duration(2 * 86_400 + 3 * 3_600) == "2D 3H")
}

@Test @MainActor func roundTripsDiskSelections() {
  for selection in [
    DiskSelection.none, .startup, .volume(id: "E47CE629-334B", name: "Project Disk"),
  ] {
    #expect(DiskSelection(rawValue: selection.rawValue) == selection)
  }
  #expect(DiskSelection(rawValue: "volume:") == nil)
  #expect(DiskSelection(rawValue: "garbage") == nil)
  #expect(DiskSelection(rawValue: "volume:abc") == .volume(id: "abc", name: "abc"))

  let defaults = try! #require(UserDefaults(suiteName: "AgentMonTests.disks.\(UUID())"))
  #expect(SystemMonitor.configuredDiskSelections(defaults: defaults) == [.startup, .none])
  defaults.set("none", forKey: SettingsKeys.firstDisk)
  defaults.set(DiskSelection.volume(id: "x", name: "Project Disk").rawValue, forKey: SettingsKeys.secondDisk)
  #expect(
    SystemMonitor.configuredDiskSelections(defaults: defaults)
      == [.none, .volume(id: "x", name: "Project Disk")])
}

@Test @MainActor func samplesSelectedDisksAndReportsMissingVolumes() throws {
  let directory = FileManager.default.temporaryDirectory
  let volumes = [
    MountedVolume(id: "project-uuid", name: "Project Disk", url: directory, isStartup: false),
    MountedVolume(id: "root-uuid", name: "Macintosh HD", url: URL(fileURLWithPath: "/"), isStartup: true),
  ]

  let disks = SystemMonitor.disks(
    for: [.startup, .volume(id: "project-uuid", name: "Old Name")], volumes: volumes)
  #expect(disks.map(\.label) == ["STARTUP DISK", "PROJECT DISK"])
  #expect(disks.allSatisfy { $0.isMounted && $0.total > 0 && $0.used <= $0.total })

  let unplugged = SystemMonitor.disks(
    for: [.none, .volume(id: "gone", name: "Archive")], volumes: volumes)
  #expect(unplugged == [.unmounted(id: "gone", name: "Archive")])

  #expect(SystemMonitor.disks(for: [.none, .none], volumes: volumes).isEmpty)
  #expect(SystemMonitor.disks(for: [.startup, .startup], volumes: volumes).count == 1)
  #expect(
    SystemMonitor.disks(for: [.volume(id: "root-uuid", name: "Macintosh HD")], volumes: volumes)
      == [.unmounted(id: "root-uuid", name: "Macintosh HD")])
}

@Test func listsDiskOptionsIncludingUnmountedSelection() {
  let volumes = [
    MountedVolume(id: "root", name: "Macintosh HD", url: URL(fileURLWithPath: "/"), isStartup: true),
    MountedVolume(id: "p", name: "Project Disk", url: URL(fileURLWithPath: "/Volumes/Project Disk"), isStartup: false),
  ]
  #expect(
    SettingsView.diskOptions(current: .startup, volumes: volumes).map(\.1)
      == ["None", "Startup Disk", "Project Disk"])
  let renamed = DiskSelection.volume(id: "p", name: "Old Name")
  #expect(SettingsView.diskOptions(current: renamed, volumes: volumes).map(\.0).contains(renamed))
  #expect(
    SettingsView.diskOptions(current: .volume(id: "gone", name: "Archive"), volumes: volumes)
      .last?.1 == "Archive (not mounted)")
}

@Test func reportsWhichResourceIsUnhealthy() {
  func snapshot(cpu: Double = 10, memory: UInt64 = 10, disks: [DiskSnapshot] = []) -> SystemSnapshot {
    SystemSnapshot(
      cpuPercent: cpu, memoryUsed: memory, memoryTotal: 100, disks: disks, uptime: 0,
      hostname: "Mac", sampledAt: .now)
  }
  let full = DiskSnapshot(id: "p", name: "Project Disk", used: 97, total: 100, isMounted: true)
  #expect(snapshot().healthMessage == "System shipshape.")
  #expect(snapshot().healthMood == .happy)
  #expect(snapshot(cpu: 95).healthMessage == "Processor is busy.")
  #expect(snapshot(memory: 95).healthMessage == "Memory is crowded.")
  #expect(snapshot(disks: [full]).healthMessage == "Project Disk is nearly full.")
  #expect(snapshot(disks: [full]).healthMood == .concerned)
  #expect(snapshot(disks: [.unmounted(id: "p", name: "Project Disk")]).healthMood == .happy)
}

@Test @MainActor func rendersDemoDashboard() throws {
  let model = DashboardModel()
  model.loadDemoData()
  #expect(model.doneCount == 1)
  #expect(model.sessions.first?.activity == .attention)
  #expect(model.recentEvents.first?.message == "started working")
  #expect(model.recentEvents.contains { $0.message == "finished after 27M" })

  let content = DashboardView()
    .environmentObject(model)
    .frame(width: 1280, height: 720)
  let renderer = ImageRenderer(content: content)
  renderer.proposedSize = ProposedViewSize(width: 1280, height: 720)
  let image = try #require(renderer.nsImage)
  #expect(image.size == NSSize(width: 1280, height: 720))
  guard let outputPath = ProcessInfo.processInfo.environment["AGENTMON_DASHBOARD_SNAPSHOT"] else {
    return
  }
  // ImageRenderer leaves ScrollView content blank, so render the desk rows separately too.
  let rows = VStack(spacing: 0) {
    ForEach(model.sessions) { AgentRow(session: $0) }
  }
  .environmentObject(model)
  .frame(width: 822)
  .background(RetroTheme.paper)
  for (view, path) in [
    (AnyView(content), outputPath), (AnyView(rows), outputPath + "-rows.png"),
  ] {
    let renderer = ImageRenderer(content: view)
    let tiff = try #require(renderer.nsImage?.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
  }
}

@Test func mapsWeatherCodes() {
  #expect(WeatherCode.description(for: 0) == "Sunny")
  #expect(WeatherCode.description(for: 1) == "Mostly sunny")
  #expect(WeatherCode.description(for: 1, isDay: false) == "Mostly clear")
  #expect(WeatherCode.description(for: 2) == "Partly cloudy")
  #expect(WeatherCode.description(for: 63) == "Rain")
  #expect(WeatherCode.description(for: 95) == "Thunderstorms")
}

@Test func describesSkyFromCloudCover() {
  #expect(WeatherCode.description(for: 0, cloudCover: 0) == "Sunny")
  #expect(WeatherCode.description(for: 0, cloudCover: 20) == "Mostly sunny")
  #expect(WeatherCode.description(for: 1, cloudCover: 50) == "Partly cloudy")
  #expect(WeatherCode.description(for: 2, cloudCover: 75) == "Mostly cloudy")
  #expect(WeatherCode.description(for: 3, cloudCover: 95) == "Overcast")
  #expect(WeatherCode.description(for: 0, cloudCover: 20, isDay: false) == "Mostly clear")
}

@Test func precipitationTakesPriorityOverCloudCover() {
  #expect(WeatherCode.description(for: 63, cloudCover: 10) == "Rain")
  #expect(WeatherCode.description(for: 95, cloudCover: 20) == "Thunderstorms")
}

@Test func mapsObservedWeatherDescriptions() throws {
  let mostlyClear = try #require(ObservedWeatherCondition(description: "Mostly Clear"))
  #expect(mostlyClear.description(isDay: true) == "Mostly sunny")
  #expect(mostlyClear.description(isDay: false) == "Mostly clear")
  #expect(mostlyClear.artwork(isDay: true) == .mostlySunny)

  #expect(ObservedWeatherCondition(description: "Partly Cloudy") == .partlyCloudy)
  #expect(ObservedWeatherCondition(description: "Mostly Cloudy") == .mostlyCloudy)
  #expect(ObservedWeatherCondition(description: "Fog/Mist") == .fog)
  #expect(ObservedWeatherCondition(description: "Light Rain") == .rain)
  #expect(ObservedWeatherCondition(description: "Snow Showers") == .snow)
  #expect(ObservedWeatherCondition(description: "Thunderstorm in Vicinity") == .thunderstorm)
  #expect(ObservedWeatherCondition(description: "Unknown Precipitation") == nil)
}

@Test func recognizesUSZipLocations() {
  #expect(WeatherLocationParser.usZipCode(from: "30066") == "30066")
  #expect(WeatherLocationParser.usZipCode(from: " 30066 ") == "30066")
  #expect(WeatherLocationParser.usZipCode(from: "30066-1234") == "30066")
  #expect(WeatherLocationParser.usZipCode(from: "Marietta, Georgia") == nil)
  #expect(WeatherLocationParser.usZipCode(from: "SW1A 1AA") == nil)
}

@Test func decodesRelaySnapshotAndAssignsHost() throws {
  let data = """
    {
      "protocolVersion": 1,
      "relayVersion": "0.1.0",
      "generatedAt": "2026-09-23T02:15:01.123Z",
      "host": {
        "id": "windows-1",
        "name": "Windows Desktop",
        "platform": "windows"
      },
      "sessions": [{
        "id": "session-1",
        "project": "AgentMon",
        "task": "Build the relay",
        "repository": "VeryKross/AgentMon",
        "branch": "main",
        "activity": "working",
        "updatedAt": "2026-09-23T02:14:57Z"
      }]
    }
    """.data(using: .utf8)!

  let snapshot = try RelaySnapshotDecoder.decode(data)
  let session = try #require(snapshot.agentSessions().first)

  #expect(snapshot.protocolVersion == 1)
  #expect(session.id == "windows-1:session-1")
  #expect(session.host.name == "Windows Desktop")
  #expect(session.host.platform == .windows)
  #expect(session.activity == .working)
}

@Test func normalizesRelayCertificateFingerprint() {
  let fingerprint = "AA:01 bb-23"
  #expect(PinnedRelayDelegate.normalize(fingerprint) == "aa01bb23")
}

@Test func fetchesPinnedRelaySnapshot() async throws {
  let environment = ProcessInfo.processInfo.environment
  guard let rawURL = environment["AGENTMON_TEST_RELAY_URL"],
    let url = URL(string: rawURL),
    let token = environment["AGENTMON_TEST_RELAY_TOKEN"],
    let fingerprint = environment["AGENTMON_TEST_RELAY_FINGERPRINT"]
  else {
    return
  }

  let snapshot = try await RelayClient().fetchSnapshot(
    configuration: RelayConfiguration(
      baseURL: url,
      certificateFingerprint: fingerprint,
      token: token
    )
  )

  #expect(snapshot.host.name == "Mock Windows Desktop")
  #expect(snapshot.sessions.count == 1)
  #expect(snapshot.sessions.first?.activity == .working)
}

@Test func mapsEveryWeatherFamilyToDistinctArtwork() {
  #expect(WeatherCode.artwork(for: 0, cloudCover: 0, isDay: true) == .sunny)
  #expect(WeatherCode.artwork(for: 0, cloudCover: 0, isDay: false) == .clearNight)
  #expect(WeatherCode.artwork(for: 0, cloudCover: 20, isDay: true) == .mostlySunny)
  #expect(WeatherCode.artwork(for: 0, cloudCover: 20, isDay: false) == .mostlyClearNight)
  #expect(WeatherCode.artwork(for: 1, cloudCover: 50, isDay: true) == .partlyCloudyDay)
  #expect(WeatherCode.artwork(for: 1, cloudCover: 50, isDay: false) == .partlyCloudyNight)
  #expect(WeatherCode.artwork(for: 2, cloudCover: 75, isDay: true) == .mostlyCloudyDay)
  #expect(WeatherCode.artwork(for: 2, cloudCover: 75, isDay: false) == .mostlyCloudyNight)
  #expect(WeatherCode.artwork(for: 3, cloudCover: 95, isDay: true) == .overcast)
  #expect(WeatherCode.artwork(for: 45, cloudCover: 100, isDay: true) == .fog)
  #expect(WeatherCode.artwork(for: 53, cloudCover: 100, isDay: true) == .drizzle)
  #expect(WeatherCode.artwork(for: 63, cloudCover: 100, isDay: true) == .rain)
  #expect(WeatherCode.artwork(for: 73, cloudCover: 100, isDay: true) == .snow)
  #expect(WeatherCode.artwork(for: 95, cloudCover: 100, isDay: true) == .thunderstorm)
  #expect(WeatherCode.artwork(for: -1, cloudCover: 0, isDay: true) == .unknown)
}

@Test @MainActor func rendersEveryWeatherArtwork() throws {
  let renderer = ImageRenderer(content: WeatherArtworkGallery())
  renderer.proposedSize = ProposedViewSize(width: 1280, height: 720)

  let image = try #require(renderer.nsImage)
  let tiff = try #require(image.tiffRepresentation)
  let bitmap = try #require(NSBitmapImageRep(data: tiff))
  let png = try #require(bitmap.representation(using: .png, properties: [:]))

  if let outputPath = ProcessInfo.processInfo.environment["AGENTMON_ARTWORK_SNAPSHOT"] {
    try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
  }

  #expect(image.size.width == 1280)
  #expect(image.size.height == 720)
}

private struct WeatherArtworkGallery: View {
  private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

  var body: some View {
    LazyVGrid(columns: columns, spacing: 8) {
      ForEach(WeatherArtwork.allCases, id: \.self) { artwork in
        VStack(spacing: 5) {
          WeatherGlyph(artwork: artwork, label: artwork.displayName)
            .frame(width: 108, height: 100)
          Text(artwork.displayName)
            .font(RetroTheme.font(size: 9, weight: .bold))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 206)
        .background(RetroTheme.paper)
        .overlay {
          Rectangle().stroke(RetroTheme.ink, lineWidth: 2)
        }
      }
    }
    .padding(18)
    .frame(width: 1280, height: 720)
    .background(DitherPattern())
  }
}
