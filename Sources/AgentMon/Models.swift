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

struct AgentSession: Identifiable, Equatable, Sendable {
  let id: String
  let project: String
  let task: String
  let repository: String?
  let branch: String?
  let activity: AgentActivity
  let updatedAt: Date
}

struct WeatherSnapshot: Equatable, Sendable {
  let location: String
  let temperature: Double
  let weatherCode: Int
  let isDay: Bool
  let fetchedAt: Date

  var condition: String {
    WeatherCode.description(for: weatherCode)
  }
}

enum WeatherCode {
  static func description(for code: Int) -> String {
    switch code {
    case 0: "Clear"
    case 1, 2: "Partly cloudy"
    case 3: "Overcast"
    case 45, 48: "Fog"
    case 51, 53, 55, 56, 57: "Drizzle"
    case 61, 63, 65, 66, 67, 80, 81, 82: "Rain"
    case 71, 73, 75, 77, 85, 86: "Snow"
    case 95, 96, 99: "Thunderstorms"
    default: "Unknown"
    }
  }
}

enum SettingsKeys {
  static let weatherLocation = "weatherLocation"
  static let fillSecondaryDisplay = "fillSecondaryDisplay"
  static let computerName = "computerName"
  static let defaultWeatherLocation = "30066"
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
