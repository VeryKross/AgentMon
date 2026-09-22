import Foundation
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

@Test func treatsMissingProcessAsOffline() {
  let activity = AgentEventParser.activity(
    from: Data(),
    hasLiveProcess: false,
    updatedAt: .now,
    now: .now
  )

  #expect(activity == .offline)
}

@Test func mapsWeatherCodes() {
  #expect(WeatherCode.description(for: 0) == "Clear")
  #expect(WeatherCode.description(for: 63) == "Rain")
  #expect(WeatherCode.description(for: 95) == "Thunderstorms")
}
