import Darwin
import Foundation

@MainActor
final class SystemMonitor {
  private var previousCPUTicks: [UInt64]?

  func snapshot() -> SystemSnapshot {
    let memory = memoryUsage()
    let disk = diskUsage()

    return SystemSnapshot(
      cpuPercent: cpuUsage(),
      memoryUsed: memory.used,
      memoryTotal: memory.total,
      diskUsed: disk.used,
      diskTotal: disk.total,
      uptime: ProcessInfo.processInfo.systemUptime,
      hostname: configuredComputerName,
      sampledAt: .now
    )
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

  private func diskUsage() -> (used: Int64, total: Int64) {
    do {
      let values = try URL(fileURLWithPath: NSHomeDirectory())
        .resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
      let total = Int64(values.volumeTotalCapacity ?? 0)
      let available = Int64(values.volumeAvailableCapacity ?? 0)
      return (max(total - available, 0), total)
    } catch {
      return (0, 0)
    }
  }
}
