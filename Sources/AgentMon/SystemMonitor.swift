import AppKit
import Darwin
import Foundation

@MainActor
final class SystemMonitor {
  private var previousCPUTicks: [UInt64]?
  private var cachedVolumes: [MountedVolume]?
  private var volumeObservers: [NSObjectProtocol] = []

  init() {
    let center = NSWorkspace.shared.notificationCenter
    volumeObservers = [
      NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
      NSWorkspace.didRenameVolumeNotification,
    ].map { name in
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.cachedVolumes = nil }
      }
    }
  }

  deinit {
    let center = NSWorkspace.shared.notificationCenter
    volumeObservers.forEach(center.removeObserver)
  }

  func snapshot() -> SystemSnapshot {
    let memory = memoryUsage()

    return SystemSnapshot(
      cpuPercent: cpuUsage(),
      memoryUsed: memory.used,
      memoryTotal: memory.total,
      disks: selectedDisks(),
      uptime: ProcessInfo.processInfo.systemUptime,
      hostname: configuredComputerName,
      sampledAt: .now
    )
  }

  /// Lists volumes only when an external disk is selected, and reuses that list until a
  /// volume mounts, unmounts, or is renamed, so slow network mounts are not re-queried
  /// on every sample.
  private func selectedDisks() -> [DiskSnapshot] {
    let selections = Self.configuredDiskSelections()
    guard selections.contains(where: { $0.volumeID != nil }) else {
      return Self.disks(for: selections, volumes: [])
    }
    let volumes = cachedVolumes ?? MountedVolume.current()
    cachedVolumes = volumes
    return Self.disks(for: selections, volumes: volumes)
  }

  static func configuredDiskSelections(
    defaults: UserDefaults = .standard
  ) -> [DiskSelection] {
    let first = defaults.string(forKey: SettingsKeys.firstDisk)
      .flatMap(DiskSelection.init(rawValue:)) ?? SettingsKeys.defaultFirstDisk
    let second = defaults.string(forKey: SettingsKeys.secondDisk)
      .flatMap(DiskSelection.init(rawValue:)) ?? SettingsKeys.defaultSecondDisk
    return [first, second]
  }

  private var configuredComputerName: String {
    let configured = UserDefaults.standard.string(forKey: SettingsKeys.computerName)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let configured, !configured.isEmpty {
      return configured
    }
    return "Ken's M4 Mini"
  }

  private func cpuUsage() -> Double {
    var load = host_cpu_load_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
    )

    let result = withUnsafeMutablePointer(to: &load) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
      }
    }

    guard result == KERN_SUCCESS else { return 0 }

    let ticks = withUnsafeBytes(of: load.cpu_ticks) { rawBuffer in
      Array(rawBuffer.bindMemory(to: UInt32.self)).map(UInt64.init)
    }

    defer { previousCPUTicks = ticks }
    guard let previousCPUTicks, previousCPUTicks.count == ticks.count else {
      return normalizedLoadAverage()
    }

    let deltas = zip(ticks, previousCPUTicks).map { current, previous in
      current >= previous ? current - previous : current
    }
    let total = deltas.reduce(0, +)
    guard total > 0, deltas.indices.contains(Int(CPU_STATE_IDLE)) else { return 0 }

    let idle = deltas[Int(CPU_STATE_IDLE)]
    return min(max((1 - (Double(idle) / Double(total))) * 100, 0), 100)
  }

  private func normalizedLoadAverage() -> Double {
    var averages = [Double](repeating: 0, count: 3)
    guard getloadavg(&averages, 3) > 0 else { return 0 }
    let processors = max(ProcessInfo.processInfo.processorCount, 1)
    return min((averages[0] / Double(processors)) * 100, 100)
  }

  private func memoryUsage() -> (used: UInt64, total: UInt64) {
    let total = ProcessInfo.processInfo.physicalMemory
    var statistics = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
    )

    let result = withUnsafeMutablePointer(to: &statistics) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }

    guard result == KERN_SUCCESS else { return (0, total) }

    let pageSize = UInt64(vm_kernel_page_size)
    let usedPages =
      UInt64(statistics.active_count)
      + UInt64(statistics.wire_count)
      + UInt64(statistics.compressor_page_count)
    return (min(usedPages * pageSize, total), total)
  }

  static func disks(
    for selections: [DiskSelection],
    volumes: [MountedVolume]
  ) -> [DiskSnapshot] {
    var seen = Set<String>()
    return selections.compactMap { selection -> DiskSnapshot? in
      let volume: MountedVolume?
      let fallbackName: String
      switch selection {
      case .none:
        return nil
      case .startup:
        volume = MountedVolume(
          id: "startup", name: "Startup Disk",
          url: URL(fileURLWithPath: NSHomeDirectory()), isStartup: true)
        fallbackName = "Startup Disk"
      case .volume(let id, let name):
        volume = volumes.first { $0.id == id && !$0.isStartup }
        fallbackName = name
      }

      let id = selection == .startup ? "startup" : (selection.volumeID ?? "")
      guard seen.insert(id).inserted else { return nil }
      guard let volume, let capacity = capacity(of: volume.url) else {
        return .unmounted(id: id, name: fallbackName)
      }
      return DiskSnapshot(
        id: id,
        name: selection == .startup ? "Startup Disk" : volume.name,
        used: capacity.used,
        total: capacity.total,
        isMounted: true
      )
    }
  }

  private static func capacity(of url: URL) -> (used: Int64, total: Int64)? {
    guard
      let values = try? url.resourceValues(forKeys: [
        .volumeAvailableCapacityKey, .volumeTotalCapacityKey,
      ]),
      let total = values.volumeTotalCapacity, total > 0
    else { return nil }
    let available = Int64(values.volumeAvailableCapacity ?? 0)
    return (max(Int64(total) - available, 0), Int64(total))
  }
}

extension MountedVolume {
  /// User-visible mounted volumes. The root volume is reported as the startup disk.
  static func current(fileManager: FileManager = .default) -> [MountedVolume] {
    let keys: [URLResourceKey] = [
      .volumeNameKey, .volumeUUIDStringKey, .volumeIsRootFileSystemKey,
    ]
    let urls =
      fileManager.mountedVolumeURLs(
        includingResourceValuesForKeys: keys,
        options: [.skipHiddenVolumes]
      ) ?? []

    return urls.compactMap { url in
      guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
      let isStartup = values.volumeIsRootFileSystem ?? (url.path == "/")
      return MountedVolume(
        id: values.volumeUUIDString ?? "path:\(url.path)",
        name: values.volumeName ?? url.lastPathComponent,
        url: url,
        isStartup: isStartup
      )
    }
  }
}
