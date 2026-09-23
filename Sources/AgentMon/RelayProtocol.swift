import Foundation

enum RelayProtocol {
  static let version = 1
  static let defaultPort = 47_831
  static let maximumSnapshotAge: TimeInterval = 30
}

struct RelaySnapshot: Decodable, Sendable {
  let protocolVersion: Int
  let relayVersion: String
  let generatedAt: Date
  let host: Host
  let sessions: [Session]

  struct Host: Decodable, Sendable {
    let id: String
    let name: String
    let platform: AgentHostPlatform
  }

  struct Session: Decodable, Sendable {
    let id: String
    let project: String
    let task: String
    let repository: String?
    let branch: String?
    let activity: AgentActivity
    let updatedAt: Date
  }

  var agentHost: AgentHost {
    AgentHost(
      id: host.id,
      name: host.name,
      platform: host.platform,
      isLocal: false
    )
  }

  func agentSessions() -> [AgentSession] {
    let host = agentHost
    return sessions.map {
      AgentSession(
        id: "\(host.id):\($0.id)",
        project: $0.project,
        task: $0.task,
        repository: $0.repository,
        branch: $0.branch,
        activity: $0.activity,
        updatedAt: $0.updatedAt,
        host: host
      )
    }
  }
}

enum RelaySnapshotDecoder {
  static func decode(_ data: Data) throws -> RelaySnapshot {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)

      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: value) {
        return date
      }

      let standard = ISO8601DateFormatter()
      if let date = standard.date(from: value) {
        return date
      }

      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected an RFC 3339 timestamp."
      )
    }
    return try decoder.decode(RelaySnapshot.self, from: data)
  }
}
