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
