import Darwin
import Foundation

struct CopilotSessionMonitor {
  private let fileManager = FileManager.default

  func sessions(now: Date = .now) -> [AgentSession] {
    let root = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".copilot/session-state", isDirectory: true)

    guard
      let directories = try? fileManager.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    return directories.compactMap { directory in
      guard !directory.lastPathComponent.hasPrefix("pending-session") else { return nil }
      return session(at: directory, now: now)
    }
    .filter { $0.isWithinMaximumAge(now: now) }
    .filter { $0.activity != .offline || now.timeIntervalSince($0.updatedAt) < 86_400 }
    .sorted(by: AgentSession.priorityOrdered)
  }

  private func session(at directory: URL, now: Date) -> AgentSession? {
    let workspaceURL = directory.appendingPathComponent("workspace.yaml")
    guard let workspaceText = try? String(contentsOf: workspaceURL, encoding: .utf8) else {
      return nil
    }

    let fields = WorkspaceYAMLParser.parse(workspaceText)
    guard let id = fields["id"] else { return nil }

    let eventsURL = directory.appendingPathComponent("events.jsonl")
    let eventDate = modificationDate(for: eventsURL)
    let workspaceDate = parseDate(fields["updated_at"]) ?? modificationDate(for: workspaceURL)
    let updatedAt = max(eventDate, workspaceDate)
    let hasLiveProcess = liveSessionPID(in: directory) != nil
    let activity = AgentEventParser.activity(
      from: Self.tail(of: eventsURL),
      hasLiveProcess: hasLiveProcess,
      updatedAt: updatedAt,
      now: now,
      hasAvailableWorkspace: Self.hasAvailableWorkspace(from: fields)
    )

    let repository = fields["repository"]
    let project = Self.projectName(from: fields)
    let rawName = fields["name"] ?? "Copilot session"
    let task = conciseTaskName(rawName, project: project)

    return AgentSession(
      id: id,
      project: project,
      task: task,
      repository: repository,
      branch: fields["branch"],
      activity: activity,
      updatedAt: updatedAt
    )
  }

  static func hasAvailableWorkspace(from fields: [String: String]) -> Bool {
    guard let cwd = fields["cwd"], cwd.hasPrefix("/") else { return false }
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  static func projectName(from fields: [String: String]) -> String {
    if let repositoryName = fields["repository"]?.split(separator: "/").last {
      return String(repositoryName)
    }

    let cwd = fields["cwd"] ?? ""
    let directory = URL(fileURLWithPath: cwd)
    let name = directory.lastPathComponent
    if fields["branch"] == nil,
      fields["git_root"] == nil,
      name.range(of: "^[a-z]+-[a-z]+-[0-9a-f]{8}$", options: .regularExpression) != nil,
      !FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path)
    {
      return "Copilot Chat"
    }
    return name.nonEmpty ?? "Untitled Project"
  }

  private func modificationDate(for url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
      ?? .distantPast
  }

  private func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    return ISO8601DateFormatter().date(from: value)
  }

  private func liveSessionPID(in directory: URL) -> Int32? {
    guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
      return nil
    }

    for name in names where name.hasPrefix("inuse.") && name.hasSuffix(".lock") {
      let pidText =
        name
        .dropFirst("inuse.".count)
        .dropLast(".lock".count)
      guard let pid = Int32(pidText), kill(pid, 0) == 0 else { continue }
      return pid
    }

    return nil
  }

  static func tail(
    of url: URL,
    initialBytes: UInt64 = 128 * 1_024,
    maximumBytes: UInt64 = 4 * 1_024 * 1_024
  ) -> Data {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
    defer { try? handle.close() }

    let size = (try? handle.seekToEnd()) ?? 0
    var byteCount = min(initialBytes, maximumBytes)

    while true {
      let offset = size > byteCount ? size - byteCount : 0
      try? handle.seek(toOffset: offset)
      let data = (try? handle.readToEnd()) ?? Data()

      if offset == 0 || containsActivityBoundary(data) || byteCount >= maximumBytes {
        return data
      }
      byteCount = min(byteCount * 2, maximumBytes)
    }
  }

  private static func containsActivityBoundary(_ data: Data) -> Bool {
    for line in data.split(separator: 0x0A) {
      guard
        let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
        let type = object["type"] as? String
      else { continue }

      if type.hasPrefix("session.fusion_")
        || type.hasPrefix("model.")
        || type == "user.message"
      {
        return true
      }
      if type == "tool.execution_start",
        let payload = object["data"] as? [String: Any],
        payload["toolName"] as? String == "ask_user"
      {
        return true
      }
    }
    return false
  }

  private func conciseTaskName(_ rawName: String, project: String) -> String {
    let cleaned =
      rawName
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if cleaned.count <= 72 {
      return cleaned
    }

    if project != "Copilot Chat" && cleaned.localizedCaseInsensitiveContains(project) {
      return "Copilot project session"
    }

    return String(cleaned.prefix(69)).trimmingCharacters(in: .whitespaces) + "…"
  }
}

enum WorkspaceYAMLParser {
  static func parse(_ source: String) -> [String: String] {
    var result: [String: String] = [:]

    for line in source.split(whereSeparator: \.isNewline) {
      guard !line.hasPrefix(" "),
        let separator = line.firstIndex(of: ":")
      else { continue }

      let key = String(line[..<separator])
      var value = String(line[line.index(after: separator)...])
        .trimmingCharacters(in: .whitespaces)

      if value.count >= 2,
        value.hasPrefix("'") && value.hasSuffix("'")
          || value.hasPrefix("\"") && value.hasSuffix("\"")
      {
        value.removeFirst()
        value.removeLast()
      }

      result[key] = value.replacingOccurrences(of: "''", with: "'")
    }

    return result
  }
}

enum AgentEventParser {
  static func activity(
    from data: Data,
    hasLiveProcess: Bool,
    updatedAt: Date,
    now: Date,
    hasAvailableWorkspace: Bool = false
  ) -> AgentActivity {
    let recent = now.timeIntervalSince(updatedAt) < 15 * 60

    let lines = data.split(separator: 0x0A).reversed()
    var completedToolCalls = Set<String>()
    var assistantTurnEnded = false

    for line in lines {
      guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
        let type = object["type"] as? String
      else { continue }

      if type == "session.fusion_completed" {
        return hasLiveProcess ? .ready : .offline
      }

      if type == "session.fusion_commit_started"
        || type == "session.fusion_handoff"
        || type.hasPrefix("model.")
      {
        guard hasLiveProcess else { return .offline }
        return recent ? .working : .ready
      }

      if type == "tool.execution_complete",
        let payload = object["data"] as? [String: Any],
        let toolCallID = payload["toolCallId"] as? String
      {
        completedToolCalls.insert(toolCallID)
        continue
      }

      if type == "tool.execution_start",
        let payload = object["data"] as? [String: Any],
        payload["toolName"] as? String == "ask_user",
        let toolCallID = payload["toolCallId"] as? String,
        !completedToolCalls.contains(toolCallID),
        !assistantTurnEnded
      {
        return hasLiveProcess || hasAvailableWorkspace ? .attention : .offline
      }

      if type == "assistant.turn_start" {
        guard !assistantTurnEnded else { continue }
        guard hasLiveProcess else { return .offline }
        return recent ? .working : .ready
      }
      if type == "assistant.turn_end" {
        assistantTurnEnded = true
        continue
      }
      if type == "user.message" {
        if assistantTurnEnded {
          return hasLiveProcess ? .ready : .offline
        }
        guard hasLiveProcess else { return .offline }
        return recent ? .working : .ready
      }
    }

    return hasLiveProcess ? .ready : .offline
  }
}

extension String {
  fileprivate var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
