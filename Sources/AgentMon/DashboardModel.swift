import Combine
import Foundation

enum RelayConnectionState: Equatable {
  case disabled
  case connecting
  case connected(host: String)
  case unavailable(message: String)

  var description: String {
    switch self {
    case .disabled: "Remote relay is off."
    case .connecting: "Connecting to the Windows relay…"
    case .connected(let host): "Connected to \(host)."
    case .unavailable(let message): message
    }
  }
}

@MainActor
final class DashboardModel: ObservableObject {
  @Published private(set) var system = SystemSnapshot.placeholder
  @Published private(set) var sessions: [AgentSession] = []
  @Published private(set) var weather: WeatherSnapshot?
  @Published private(set) var weatherError: String?
  @Published private(set) var cpuHistory = [Double](repeating: 0, count: 28)
  @Published private(set) var memoryHistory = [Double](repeating: 0, count: 28)
  @Published private(set) var isRefreshing = false
  @Published private(set) var relayState: RelayConnectionState = .disabled
  @Published private(set) var completionFlashCounts: [String: Int] = [:]
  @Published private(set) var stateSince: [String: Date] = [:]
  @Published private(set) var unseenCompletions: Set<String> = []
  @Published private(set) var recentEvents: [SessionActivityEvent] = []

  private let systemMonitor = SystemMonitor()
  private let sessionMonitor = CopilotSessionMonitor()
  private let weatherService = WeatherService()
  private let relayClient = RelayClient()
  private let demoMode =
    ProcessInfo.processInfo.arguments.contains("--demo")
    || ProcessInfo.processInfo.environment["AGENTMON_DEMO_MODE"] == "1"
  private var timer: Timer?
  private var lastWeatherLocation = ""
  private var lastWeatherRefresh = Date.distantPast
  private var lastRelayRefresh = Date.distantPast
  private var localSessions: [AgentSession] = []
  private var remoteSessions: [AgentSession] = []
  private var remoteHost: AgentHost?
  private var relayTask: Task<Void, Never>?
  private var activityTracker = SessionActivityTracker()
  private var demoHistoryLoaded = false

  var workingAgentCount: Int {
    sessions.filter { $0.activity == .working }.count
  }

  var attentionCount: Int {
    sessions.filter { $0.activity == .attention }.count
  }

  var doneCount: Int {
    sessions.filter { isUnseenCompletion($0) }.count
  }

  var readyCount: Int {
    sessions.filter { $0.activity == .ready && !isUnseenCompletion($0) }.count
  }

  func isUnseenCompletion(_ session: AgentSession) -> Bool {
    session.activity == .ready && unseenCompletions.contains(session.id)
  }

  func stateSince(for session: AgentSession) -> Date {
    stateSince[session.id] ?? session.updatedAt
  }

  func acknowledgeCompletion(of sessionID: String) {
    activityTracker.acknowledge(sessionID)
    publishTracker()
  }

  func acknowledgeAllCompletions() {
    activityTracker.acknowledgeAll()
    publishTracker()
  }

  var hostCount: Int {
    1 + (remoteHost == nil ? 0 : 1)
  }

  var hostSummary: String {
    if remoteHost != nil {
      return "\(hostCount) HOSTS • 1 REMOTE"
    }
    if case .unavailable = relayState {
      return "1 HOST • REMOTE OFFLINE"
    }
    return "LOCAL HOST"
  }

  var summaryLine: String {
    if attentionCount > 0 {
      return "\(attentionCount) session\(attentionCount == 1 ? " needs" : "s need") attention"
    }
    if workingAgentCount > 0 {
      return "\(workingAgentCount) agent\(workingAgentCount == 1 ? "" : "s") working"
    }
    if doneCount > 0 {
      return "\(doneCount) session\(doneCount == 1 ? "" : "s") finished"
    }
    return "All quiet"
  }

  func start() {
    guard timer == nil else { return }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.refresh()
      }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    relayTask?.cancel()
    relayTask = nil
  }

  func refresh(forceWeather: Bool = false) {
    if demoMode {
      loadDemoData()
      return
    }

    system = systemMonitor.snapshot()
    let localHost = AgentHost(
      id: "local",
      name: system.hostname,
      platform: .macOS,
      isLocal: true
    )
    localSessions = sessionMonitor.sessions()
      .prefix(10)
      .map { $0.assigning(host: localHost) }
    mergeSessions()
    refreshRelay()
    append(system.cpuPercent, to: &cpuHistory)
    append(system.memoryPercent, to: &memoryHistory)

    let location =
      UserDefaults.standard.string(forKey: SettingsKeys.weatherLocation)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nonEmpty ?? SettingsKeys.defaultWeatherLocation
    let weatherIsDue = Date().timeIntervalSince(lastWeatherRefresh) > 15 * 60

    guard !location.isEmpty,
      forceWeather || location != lastWeatherLocation || weatherIsDue
    else {
      if location.isEmpty {
        weather = nil
        weatherError = nil
      }

      return
    }

    lastWeatherLocation = location
    lastWeatherRefresh = .now
    isRefreshing = true

    Task {
      do {
        let snapshot = try await weatherService.fetch(location: location)
        weather = snapshot
        weatherError = nil
      } catch {
        weatherError = error.localizedDescription
      }
      isRefreshing = false
    }
  }

  func refreshRelay(force: Bool = false) {
    guard !demoMode else { return }

    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: SettingsKeys.relayEnabled) else {
      relayTask?.cancel()
      relayTask = nil
      remoteSessions = []
      remoteHost = nil
      relayState = .disabled
      mergeSessions()
      return
    }

    guard let configuration = RelayConfiguration.load() else {
      remoteSessions = []
      remoteHost = nil
      relayState = .unavailable(message: "Complete the Windows relay pairing settings.")
      mergeSessions()
      return
    }

    let isDue = Date().timeIntervalSince(lastRelayRefresh) >= 3
    guard relayTask == nil, force || isDue else { return }

    lastRelayRefresh = .now
    relayState = .connecting
    relayTask = Task { [weak self] in
      guard let self else { return }
      do {
        let snapshot = try await relayClient.fetchSnapshot(configuration: configuration)
        guard !Task.isCancelled else { return }
        remoteSessions = snapshot.agentSessions()
        remoteHost = snapshot.agentHost
        relayState = .connected(host: snapshot.host.name)
      } catch {
        guard !Task.isCancelled else { return }
        remoteSessions = []
        remoteHost = nil
        relayState = .unavailable(message: error.localizedDescription)
      }
      mergeSessions()
      relayTask = nil
    }
  }

  private func mergeSessions(now: Date = .now) {
    let merged = AgentSession.merged(local: localSessions, remote: remoteSessions, now: now)
    activityTracker.update(with: merged, now: now)
    let unseen = activityTracker.unseenCompletions
    sessions = AgentSession.displayOrdered(merged, unseenCompletions: unseen)
    publishTracker()
  }

  private func publishTracker() {
    if completionFlashCounts != activityTracker.generations {
      completionFlashCounts = activityTracker.generations
    }
    if stateSince != activityTracker.stateSince {
      stateSince = activityTracker.stateSince
    }
    if recentEvents != activityTracker.events {
      recentEvents = activityTracker.events
    }
    if unseenCompletions != activityTracker.unseenCompletions {
      unseenCompletions = activityTracker.unseenCompletions
      sessions = AgentSession.displayOrdered(sessions, unseenCompletions: unseenCompletions)
    }
  }

  private func append(_ value: Double, to history: inout [Double]) {
    history.append(value)
    if history.count > 28 {
      history.removeFirst(history.count - 28)
    }
  }

  func loadDemoData(now: Date = .now) {
    system = SystemSnapshot(
      cpuPercent: 37,
      memoryUsed: 18_400_000_000,
      memoryTotal: 32_000_000_000,
      disks: [
        DiskSnapshot(
          id: "startup", name: "Startup Disk", used: 338_000_000_000,
          total: 494_000_000_000, isMounted: true),
        DiskSnapshot(
          id: "demo-project", name: "Project Disk", used: 18_600_000_000,
          total: 254_000_000_000, isMounted: true),
      ],
      uptime: 286_200,
      hostname: "Ken's M4 Mini",
      sampledAt: now
    )
    let mac = AgentHost(id: "demo-mac", name: "Ken's M4 Mini", platform: .macOS, isLocal: true)
    let windows = AgentHost(
      id: "demo-windows",
      name: "Windows Desktop",
      platform: .windows,
      isLocal: false
    )
    func demoSessions(
      at time: Date,
      agentMon: AgentActivity = .working,
      pixelWeather: AgentActivity = .attention,
      tinyBuild: AgentActivity = .ready
    ) -> (local: [AgentSession], remote: [AgentSession]) {
      (
        [
          AgentSession(
            id: "agentmon", project: "AgentMon", task: "Building Macintosh Mission Control",
            repository: "VeryKross/AgentMon", branch: "main",
            activity: agentMon, updatedAt: time, host: mac),
          AgentSession(
            id: "orbit-notes", project: "OrbitNotes", task: "Refining offline sync behavior",
            repository: "sample/OrbitNotes", branch: "feature/offline-sync",
            activity: .working, updatedAt: time, host: mac),
        ],
        [
          AgentSession(
            id: "pixel-weather", project: "PixelWeather",
            task: "Forecast artwork ready for review",
            repository: "sample/PixelWeather", branch: "design/weather-icons",
            activity: pixelWeather, updatedAt: time, host: windows),
          AgentSession(
            id: "tiny-build", project: "TinyBuild", task: "Release checks complete",
            repository: "sample/TinyBuild", branch: "release/1.0",
            activity: tinyBuild, updatedAt: time, host: windows),
        ]
      )
    }

    remoteHost = windows
    if !demoHistoryLoaded {
      demoHistoryLoaded = true
      // Replay a short sample history so the demo shows durations, DONE, and the event log.
      let history: [(TimeInterval, AgentActivity, AgentActivity, AgentActivity)] = [
        (-1_920, .ready, .working, .working),
        (-720, .ready, .attention, .working),
        (-300, .ready, .attention, .ready),
        (-140, .working, .attention, .ready),
      ]
      for (offset, agentMon, pixelWeather, tinyBuild) in history {
        let time = now.addingTimeInterval(offset)
        (localSessions, remoteSessions) = demoSessions(
          at: time, agentMon: agentMon, pixelWeather: pixelWeather, tinyBuild: tinyBuild)
        mergeSessions(now: time)
      }
    }
    (localSessions, remoteSessions) = demoSessions(at: now)
    mergeSessions(now: now)
    relayState = .connected(host: windows.name)
    weather = WeatherSnapshot(
      location: "Marietta, Georgia",
      temperature: 76,
      weatherCode: 3,
      cloudCover: 92,
      isDay: true,
      observedCondition: nil,
      fetchedAt: now
    )
    weatherError = nil
    cpuHistory = [22, 31, 28, 42, 38, 51, 47, 62, 45, 37, 41, 35, 39, 37]
    memoryHistory = [48, 50, 51, 52, 53, 54, 55, 56, 56, 57, 57, 58, 57, 58]
  }
}

struct SessionActivityEvent: Identifiable, Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case started
    case resumed
    case finished(after: TimeInterval)
    case ready
    case needsYou
    case asleep
  }

  let id: Int
  let sessionID: String
  let project: String
  let platform: AgentHostPlatform
  let kind: Kind
  let date: Date

  var message: String {
    switch kind {
    case .started: "started working"
    case .resumed: "resumed working"
    case .finished(let after): "finished after \(DisplayFormat.duration(after))"
    case .ready: "is ready"
    case .needsYou: "needs you"
    case .asleep: "went to sleep"
    }
  }
}

/// Derives client-side history from successive session snapshots: when each session entered
/// its current state, completion flashes, finished-but-unseen sessions, and a recent event log.
struct SessionActivityTracker {
  /// Sessions missing from a snapshot keep their history this long, so a relay blip or the
  /// local top-ten cutoff does not reset durations or drop unseen completions.
  static let retention: TimeInterval = 10 * 60
  static let eventLimit = 20

  private struct Record {
    var activity: AgentActivity
    var since: Date
    var lastSeen: Date
  }

  private var records: [String: Record] = [:]
  private var nextEventID = 0
  private(set) var generations: [String: Int] = [:]
  private(set) var unseenCompletions: Set<String> = []
  private(set) var events: [SessionActivityEvent] = []

  var stateSince: [String: Date] {
    records.mapValues(\.since)
  }

  mutating func update(with sessions: [AgentSession], now: Date = .now) {
    var present = Set<String>()

    for session in sessions {
      present.insert(session.id)
      guard var record = records[session.id] else {
        records[session.id] = Record(
          activity: session.activity,
          since: min(session.updatedAt, now),
          lastSeen: now
        )
        continue
      }

      record.lastSeen = now
      let previous = record.activity
      if previous != session.activity {
        let elapsed = now.timeIntervalSince(record.since)
        record.activity = session.activity
        record.since = now

        if previous == .working && session.activity == .ready {
          generations[session.id, default: 0] += 1
          unseenCompletions.insert(session.id)
        } else {
          unseenCompletions.remove(session.id)
        }

        let kind: SessionActivityEvent.Kind =
          switch session.activity {
          case .working: previous == .attention ? .resumed : .started
          case .ready: previous == .working ? .finished(after: elapsed) : .ready
          case .attention: .needsYou
          case .offline: .asleep
          }
        appendEvent(
          SessionActivityEvent(
            id: nextEventID,
            sessionID: session.id,
            project: session.project,
            platform: session.host.platform,
            kind: kind,
            date: now
          ))
        nextEventID += 1
      }
      records[session.id] = record
    }

    records = records.filter {
      present.contains($0.key) || now.timeIntervalSince($0.value.lastSeen) < Self.retention
    }
    generations = generations.filter { present.contains($0.key) }
    unseenCompletions = unseenCompletions.filter { records[$0] != nil }
  }

  mutating func acknowledge(_ sessionID: String) {
    unseenCompletions.remove(sessionID)
  }

  mutating func acknowledgeAll() {
    unseenCompletions.removeAll()
  }

  private mutating func appendEvent(_ event: SessionActivityEvent) {
    events.insert(event, at: 0)
    if events.count > Self.eventLimit {
      events.removeLast(events.count - Self.eventLimit)
    }
  }
}

extension String {
  fileprivate var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
