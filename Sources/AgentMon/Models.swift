import Foundation

struct SystemSnapshot: Equatable, Sendable {
  var cpuPercent: Double
  var memoryUsed: UInt64
  var memoryTotal: UInt64
  var disks: [DiskSnapshot]
  var uptime: TimeInterval
  var hostname: String
  var sampledAt: Date

  static let placeholder = SystemSnapshot(
    cpuPercent: 0,
    memoryUsed: 0,
    memoryTotal: 1,
    disks: [],
    uptime: 0,
    hostname: Host.current().localizedName ?? "This Macintosh",
    sampledAt: .now
  )

  var memoryPercent: Double {
    Self.percentage(numerator: Double(memoryUsed), denominator: Double(memoryTotal))
  }

  var nearlyFullDisk: DiskSnapshot? {
    disks.first { $0.isMounted && $0.percent >= 96 }
  }

  var healthMood: SystemHealthMood {
    if cpuPercent >= 92 || memoryPercent >= 94 || nearlyFullDisk != nil {
      return .concerned
    }
    return .happy
  }

  var healthMessage: String {
    if cpuPercent >= 92 { return "Processor is busy." }
    if memoryPercent >= 94 { return "Memory is crowded." }
    if let disk = nearlyFullDisk { return "\(disk.name) is nearly full." }
    return "System shipshape."
  }

  static func percentage(numerator: Double, denominator: Double) -> Double {
    guard denominator > 0 else { return 0 }
    return min(max((numerator / denominator) * 100, 0), 100)
  }
}

struct DiskSnapshot: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let used: Int64
  let total: Int64
  let isMounted: Bool

  var label: String { name.uppercased() }

  var percent: Double {
    SystemSnapshot.percentage(numerator: Double(used), denominator: Double(total))
  }

  static func unmounted(id: String, name: String) -> DiskSnapshot {
    DiskSnapshot(id: id, name: name, used: 0, total: 0, isMounted: false)
  }
}

/// A dashboard disk slot. Volumes are remembered by UUID with their last known name,
/// so an unplugged drive still shows a labeled "not mounted" meter.
enum DiskSelection: Hashable, Sendable, RawRepresentable {
  case none
  case startup
  case volume(id: String, name: String)

  init?(rawValue: String) {
    switch rawValue {
    case "none": self = .none
    case "startup": self = .startup
    default:
      guard rawValue.hasPrefix("volume:") else { return nil }
      let parts = rawValue.dropFirst("volume:".count)
        .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
      guard let id = parts.first, !id.isEmpty else { return nil }
      let name = parts.count > 1 ? String(parts[1]) : String(id)
      self = .volume(id: String(id), name: name)
    }
  }

  var rawValue: String {
    switch self {
    case .none: "none"
    case .startup: "startup"
    case .volume(let id, let name): "volume:\(id)\n\(name)"
    }
  }

  var volumeID: String? {
    if case .volume(let id, _) = self { return id }
    return nil
  }
}

struct MountedVolume: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let url: URL
  let isStartup: Bool
}

enum SystemHealthMood: Sendable {
  case happy
  case concerned
}

enum AgentActivity: String, Codable, Sendable {
  case working
  case ready
  case attention
  case offline

  var title: String {
    switch self {
    case .working: "WORKING"
    case .ready: "READY"
    case .attention: "NEEDS YOU"
    case .offline: "ASLEEP"
    }
  }

  var sortOrder: Int {
    switch self {
    case .attention: 0
    case .working: 1
    case .ready: 2
    case .offline: 3
    }
  }
}

enum AgentHostPlatform: String, Codable, Sendable {
  case macOS = "macos"
  case windows
  case unknown

  var label: String {
    switch self {
    case .macOS: "MAC"
    case .windows: "PC"
    case .unknown: "HOST"
    }
  }
}

struct AgentHost: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let platform: AgentHostPlatform
  let isLocal: Bool

  static let local = AgentHost(
    id: "local",
    name: "This Mac",
    platform: .macOS,
    isLocal: true
  )
}

struct AgentSession: Identifiable, Equatable, Sendable {
  let id: String
  let project: String
  let task: String
  let repository: String?
  let branch: String?
  let activity: AgentActivity
  let updatedAt: Date
  let host: AgentHost

  init(
    id: String,
    project: String,
    task: String,
    repository: String?,
    branch: String?,
    activity: AgentActivity,
    updatedAt: Date,
    host: AgentHost = .local
  ) {
    self.id = id
    self.project = project
    self.task = task
    self.repository = repository
    self.branch = branch
    self.activity = activity
    self.updatedAt = updatedAt
    self.host = host
  }

  func assigning(host: AgentHost) -> AgentSession {
    AgentSession(
      id: "\(host.id):\(id)",
      project: project,
      task: task,
      repository: repository,
      branch: branch,
      activity: activity,
      updatedAt: updatedAt,
      host: host
    )
  }

  var sourceLine: String {
    let source = "\(host.platform.label) • \(host.name)"
    guard let branch, !branch.isEmpty else { return source }
    return "\(source) • \(branch)"
  }

  static func merged(
    local: [AgentSession],
    remote: [AgentSession],
    now: Date
  ) -> [AgentSession] {
    (local + remote)
      .filter { $0.isWithinMaximumAge(now: now) }
      .sorted(by: priorityOrdered)
  }

  func isWithinMaximumAge(now: Date) -> Bool {
    now.timeIntervalSince(updatedAt) <= 90 * 86_400
  }

  static func priorityOrdered(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
    if lhs.activity.sortOrder != rhs.activity.sortOrder {
      return lhs.activity.sortOrder < rhs.activity.sortOrder
    }
    return lhs.updatedAt > rhs.updatedAt
  }

  /// Priority order with finished-but-unseen sessions promoted directly below NEEDS YOU.
  static func displayOrdered(
    _ sessions: [AgentSession],
    unseenCompletions: Set<String>
  ) -> [AgentSession] {
    func rank(_ session: AgentSession) -> Int {
      if session.activity == .attention { return 0 }
      if session.activity == .ready && unseenCompletions.contains(session.id) { return 1 }
      return session.activity.sortOrder + 1
    }
    return sessions.sorted { lhs, rhs in
      let left = rank(lhs)
      let right = rank(rhs)
      return left != right ? left < right : priorityOrdered(lhs, rhs)
    }
  }
}

struct WeatherSnapshot: Equatable, Sendable {
  let location: String
  let temperature: Double
  let weatherCode: Int
  let cloudCover: Double
  let isDay: Bool
  let observedCondition: ObservedWeatherCondition?
  let fetchedAt: Date

  var condition: String {
    if let observedCondition {
      return observedCondition.description(isDay: isDay)
    }
    return WeatherCode.description(
      for: weatherCode,
      cloudCover: cloudCover,
      isDay: isDay
    )
  }

  var artwork: WeatherArtwork {
    if let observedCondition {
      return observedCondition.artwork(isDay: isDay)
    }
    return WeatherCode.artwork(
      for: weatherCode,
      cloudCover: cloudCover,
      isDay: isDay
    )
  }
}

enum ObservedWeatherCondition: Equatable, Sendable {
  case clear
  case mostlyClear
  case partlyCloudy
  case mostlyCloudy
  case overcast
  case fog
  case drizzle
  case rain
  case snow
  case thunderstorm

  init?(description: String) {
    let value = description.lowercased()

    if value.contains("thunder") {
      self = .thunderstorm
    } else if value.contains("snow") || value.contains("flurr") || value.contains("ice pellet") {
      self = .snow
    } else if value.contains("rain") || value.contains("shower") {
      self = .rain
    } else if value.contains("drizzle") {
      self = .drizzle
    } else if value.contains("fog") || value.contains("mist") || value.contains("haze") {
      self = .fog
    } else if value.contains("mostly cloudy") || value.contains("broken") {
      self = .mostlyCloudy
    } else if value.contains("partly cloudy") || value.contains("scattered") {
      self = .partlyCloudy
    } else if value.contains("mostly clear") || value.contains("few cloud") {
      self = .mostlyClear
    } else if value.contains("overcast") || value == "cloudy" {
      self = .overcast
    } else if value.contains("clear") || value.contains("fair") || value.contains("sunny") {
      self = .clear
    } else {
      return nil
    }
  }

  func description(isDay: Bool) -> String {
    switch self {
    case .clear: isDay ? "Sunny" : "Clear"
    case .mostlyClear: isDay ? "Mostly sunny" : "Mostly clear"
    case .partlyCloudy: "Partly cloudy"
    case .mostlyCloudy: "Mostly cloudy"
    case .overcast: "Overcast"
    case .fog: "Fog"
    case .drizzle: "Drizzle"
    case .rain: "Rain"
    case .snow: "Snow"
    case .thunderstorm: "Thunderstorms"
    }
  }

  func artwork(isDay: Bool) -> WeatherArtwork {
    switch self {
    case .clear: isDay ? .sunny : .clearNight
    case .mostlyClear: isDay ? .mostlySunny : .mostlyClearNight
    case .partlyCloudy: isDay ? .partlyCloudyDay : .partlyCloudyNight
    case .mostlyCloudy: isDay ? .mostlyCloudyDay : .mostlyCloudyNight
    case .overcast: .overcast
    case .fog: .fog
    case .drizzle: .drizzle
    case .rain: .rain
    case .snow: .snow
    case .thunderstorm: .thunderstorm
    }
  }
}

enum WeatherArtwork: String, CaseIterable, Sendable {
  case sunny
  case clearNight
  case mostlySunny
  case mostlyClearNight
  case partlyCloudyDay
  case partlyCloudyNight
  case mostlyCloudyDay
  case mostlyCloudyNight
  case overcast
  case fog
  case drizzle
  case rain
  case snow
  case thunderstorm
  case unknown

  var displayName: String {
    switch self {
    case .sunny: "Sunny"
    case .clearNight: "Clear night"
    case .mostlySunny: "Mostly sunny"
    case .mostlyClearNight: "Mostly clear night"
    case .partlyCloudyDay: "Partly cloudy"
    case .partlyCloudyNight: "Partly cloudy night"
    case .mostlyCloudyDay: "Mostly cloudy"
    case .mostlyCloudyNight: "Mostly cloudy night"
    case .overcast: "Overcast"
    case .fog: "Fog"
    case .drizzle: "Drizzle"
    case .rain: "Rain"
    case .snow: "Snow"
    case .thunderstorm: "Thunderstorm"
    case .unknown: "Unknown"
    }
  }
}

enum WeatherCode {
  static func description(
    for code: Int,
    cloudCover: Double? = nil,
    isDay: Bool = true
  ) -> String {
    switch code {
    case 0...3:
      if let cloudCover {
        return skyDescription(cloudCover: cloudCover, isDay: isDay)
      }
      return wmoSkyDescription(for: code, isDay: isDay)
    case 45, 48: return "Fog"
    case 51, 53, 55, 56, 57: return "Drizzle"
    case 61, 63, 65, 66, 67, 80, 81, 82: return "Rain"
    case 71, 73, 75, 77, 85, 86: return "Snow"
    case 95, 96, 99: return "Thunderstorms"
    default: return "Unknown"
    }
  }

  static func artwork(
    for code: Int,
    cloudCover: Double,
    isDay: Bool
  ) -> WeatherArtwork {
    switch code {
    case 0...3:
      return skyArtwork(cloudCover: cloudCover, isDay: isDay)
    case 45, 48:
      return .fog
    case 51, 53, 55, 56, 57:
      return .drizzle
    case 61, 63, 65, 66, 67, 80, 81, 82:
      return .rain
    case 71, 73, 75, 77, 85, 86:
      return .snow
    case 95, 96, 99:
      return .thunderstorm
    default:
      return .unknown
    }
  }

  private static func skyDescription(cloudCover: Double, isDay: Bool) -> String {
    switch min(max(cloudCover, 0), 100) {
    case 0..<13:
      isDay ? "Sunny" : "Clear"
    case 13..<38:
      isDay ? "Mostly sunny" : "Mostly clear"
    case 38..<63:
      "Partly cloudy"
    case 63..<88:
      "Mostly cloudy"
    default:
      "Overcast"
    }
  }

  private static func wmoSkyDescription(for code: Int, isDay: Bool) -> String {
    switch code {
    case 0:
      isDay ? "Sunny" : "Clear"
    case 1:
      isDay ? "Mostly sunny" : "Mostly clear"
    case 2:
      "Partly cloudy"
    default:
      "Overcast"
    }
  }

  private static func skyArtwork(cloudCover: Double, isDay: Bool) -> WeatherArtwork {
    switch min(max(cloudCover, 0), 100) {
    case 0..<13:
      isDay ? .sunny : .clearNight
    case 13..<38:
      isDay ? .mostlySunny : .mostlyClearNight
    case 38..<63:
      isDay ? .partlyCloudyDay : .partlyCloudyNight
    case 63..<88:
      isDay ? .mostlyCloudyDay : .mostlyCloudyNight
    default:
      .overcast
    }
  }
}

enum SettingsKeys {
  static let weatherLocation = "weatherLocation"
  static let fillSecondaryDisplay = "fillSecondaryDisplay"
  static let computerName = "computerName"
  static let defaultWeatherLocation = "30066"
  static let relayEnabled = "relayEnabled"
  static let relayURL = "relayURL"
  static let relayFingerprint = "relayFingerprint"
  static let firstDisk = "firstDisk"
  static let secondDisk = "secondDisk"
  static let defaultFirstDisk = DiskSelection.startup
  static let defaultSecondDisk = DiskSelection.none
}

enum DisplayFormat {
  static let byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useTB]
    formatter.countStyle = .memory
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter
  }()

  static func bytes(_ value: UInt64) -> String {
    byteFormatter.string(fromByteCount: Int64(clamping: value))
  }

  static func bytes(_ value: Int64) -> String {
    byteFormatter.string(fromByteCount: value)
  }

  static func uptime(_ interval: TimeInterval) -> String {
    let totalMinutes = max(Int(interval / 60), 0)
    let days = totalMinutes / 1_440
    let hours = (totalMinutes % 1_440) / 60
    let minutes = totalMinutes % 60

    if days > 0 {
      return "\(days)d \(hours)h"
    }
    if hours > 0 {
      return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
  }

  static func duration(_ interval: TimeInterval) -> String {
    let seconds = max(Int(interval), 0)
    switch seconds {
    case 0..<60: return "\(seconds)S"
    case 60..<3_600: return "\(seconds / 60)M"
    case 3_600..<86_400:
      let minutes = (seconds % 3_600) / 60
      return minutes == 0 ? "\(seconds / 3_600)H" : "\(seconds / 3_600)H \(minutes)M"
    default:
      let hours = (seconds % 86_400) / 3_600
      return hours == 0 ? "\(seconds / 86_400)D" : "\(seconds / 86_400)D \(hours)H"
    }
  }

  static func relativeTime(from date: Date, now: Date = .now) -> String {
    let seconds = max(Int(now.timeIntervalSince(date)), 0)
    switch seconds {
    case 0..<60: return "NOW"
    case 60..<3_600: return "\(seconds / 60)M"
    case 3_600..<86_400: return "\(seconds / 3_600)H"
    default: return "\(seconds / 86_400)D"
    }
  }
}
