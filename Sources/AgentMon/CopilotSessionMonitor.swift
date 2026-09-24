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
    .filter { $0.activity != .offline || now.timeIntervalSince($0.updatedAt) < 86_400 }
    .sorted {
      if $0.activity.sortOrder != $1.activity.sortOrder {
        return $0.activity.sortOrder < $1.activity.sortOrder
      }
      return $0.updatedAt > $1.updatedAt
    }
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
      from: tail(of: eventsURL),
      hasLiveProcess: hasLiveProcess,
      updatedAt: updatedAt,
      now: now
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

  private func tail(of url: URL, maximumBytes: UInt64 = 128 * 1_024) -> Data {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
    defer { try? handle.close() }

    let size = (try? handle.seekToEnd()) ?? 0
    let offset = size > maximumBytes ? size - maximumBytes : 0
    try? handle.seek(toOffset: offset)
    return (try? handle.readToEnd()) ?? Data()
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
    now: Date
  ) -> AgentActivity {
    guard hasLiveProcess else { return .offline }

    let recent = now.timeIntervalSince(updatedAt) < 15 * 60

    let lines = data.split(separator: 0x0A).reversed()
    var completedToolCalls = Set<String>()

    for line in lines {
      guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
        let type = object["type"] as? String
      else { continue }

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
        !completedToolCalls.contains(toolCallID)
      {
        return .attention
      }

      if type == "assistant.turn_start" {
        return recent ? .working : .ready
      }
      if type == "assistant.turn_end" {
        return .ready
      }
    }

    return .ready
  }
}

extension String {
  fileprivate var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
