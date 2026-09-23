import Foundation

struct SystemSnapshot: Equatable, Sendable {
  var cpuPercent: Double
  var memoryUsed: UInt64
  var memoryTotal: UInt64
  var diskUsed: Int64
  var diskTotal: Int64
  var uptime: TimeInterval
  var hostname: String
  var sampledAt: Date

  static let placeholder = SystemSnapshot(
    cpuPercent: 0,
    memoryUsed: 0,
    memoryTotal: 1,
    diskUsed: 0,
    diskTotal: 1,
    uptime: 0,
    hostname: Host.current().localizedName ?? "This Macintosh",
    sampledAt: .now
  )

  var memoryPercent: Double {
    percentage(numerator: Double(memoryUsed), denominator: Double(memoryTotal))
  }

  var diskPercent: Double {
    percentage(numerator: Double(diskUsed), denominator: Double(diskTotal))
  }

  var healthMood: SystemHealthMood {
    if cpuPercent >= 92 || memoryPercent >= 94 || diskPercent >= 96 {
      return .concerned
    }
    return .happy
  }

  private func percentage(numerator: Double, denominator: Double) -> Double {
    guard denominator > 0 else { return 0 }
    return min(max((numerator / denominator) * 100, 0), 100)
  }
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
