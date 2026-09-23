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

  var workingAgentCount: Int {
    sessions.filter { $0.activity == .working }.count
  }

  var attentionCount: Int {
    sessions.filter { $0.activity == .attention }.count
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
      return "\(attentionCount) session\(attentionCount == 1 ? "" : "s") need attention"
    }
    if workingAgentCount > 0 {
      return "\(workingAgentCount) agent\(workingAgentCount == 1 ? "" : "s") working"
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

  private func mergeSessions() {
    sessions = (localSessions + remoteSessions)
      .sorted {
        if $0.activity.sortOrder != $1.activity.sortOrder {
          return $0.activity.sortOrder < $1.activity.sortOrder
        }
        return $0.updatedAt > $1.updatedAt
      }
  }

  private func append(_ value: Double, to history: inout [Double]) {
    history.append(value)
    if history.count > 28 {
      history.removeFirst(history.count - 28)
    }
  }

  private func loadDemoData(now: Date = .now) {
    system = SystemSnapshot(
      cpuPercent: 37,
      memoryUsed: 18_400_000_000,
      memoryTotal: 32_000_000_000,
      diskUsed: 612_000_000_000,
      diskTotal: 1_000_000_000_000,
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
    localSessions = [
      AgentSession(
        id: "agentmon",
        project: "AgentMon",
        task: "Building Macintosh Mission Control",
        repository: "VeryKross/AgentMon",
        branch: "main",
        activity: .working,
        updatedAt: now,
        host: mac
      ),
      AgentSession(
        id: "orbit-notes",
        project: "OrbitNotes",
        task: "Refining offline sync behavior",
        repository: "sample/OrbitNotes",
        branch: "feature/offline-sync",
        activity: .working,
        updatedAt: now.addingTimeInterval(-180),
        host: mac
      ),
    ]
    remoteSessions = [
      AgentSession(
        id: "pixel-weather",
        project: "PixelWeather",
        task: "Forecast artwork ready for review",
        repository: "sample/PixelWeather",
        branch: "design/weather-icons",
        activity: .attention,
        updatedAt: now.addingTimeInterval(-720),
        host: windows
      ),
      AgentSession(
        id: "tiny-build",
        project: "TinyBuild",
        task: "Release checks complete",
        repository: "sample/TinyBuild",
        branch: "release/1.0",
        activity: .ready,
        updatedAt: now.addingTimeInterval(-3_600),
        host: windows
      ),
    ]
    remoteHost = windows
    mergeSessions()
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

extension String {
  fileprivate var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
