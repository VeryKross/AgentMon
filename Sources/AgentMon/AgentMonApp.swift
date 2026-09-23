import AppKit
import SwiftUI

@main
struct AgentMonApp: App {
  @StateObject private var dashboard = DashboardModel()

  var body: some Scene {
    WindowGroup("AgentMon", id: "dashboard") {
      DashboardView()
        .environmentObject(dashboard)
        .background(
          DashboardWindowAccessor { window in
            DashboardWindowController.shared.configure(window)
          }
        )
        .onAppear {
          dashboard.start()
        }
        .onDisappear {
          dashboard.stop()
        }
    }
    .defaultSize(width: 1280, height: 720)
    .commands {
      CommandGroup(replacing: .newItem) {}
    }

    MenuBarExtra("AgentMon", systemImage: "display") {
      MenuBarPanel()
        .environmentObject(dashboard)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environmentObject(dashboard)
    }
  }
}

private struct DashboardWindowAccessor: NSViewRepresentable {
  let onWindowAvailable: (NSWindow) -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        onWindowAvailable(window)
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      if let window = nsView.window {
        onWindowAvailable(window)
      }
    }
  }
}

@MainActor
final class DashboardWindowController {
  static let shared = DashboardWindowController()

  private var configuredWindows = Set<ObjectIdentifier>()

  func configure(_ window: NSWindow) {
    let identifier = ObjectIdentifier(window)
    guard configuredWindows.insert(identifier).inserted else { return }

    window.title = "AgentMon"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.backgroundColor = NSColor(RetroTheme.desktop)
    window.collectionBehavior.insert(.fullScreenPrimary)
    window.collectionBehavior.insert(.stationary)
    window.contentMinSize = NSSize(width: 960, height: 540)

    guard UserDefaults.standard.object(forKey: SettingsKeys.fillSecondaryDisplay) as? Bool ?? true,
      let targetScreen = secondaryScreen()
    else { return }

    fill(window, on: targetScreen)
  }

  func fillSecondaryDisplay() {
    guard let window = NSApp.windows.first(where: { $0.title == "AgentMon" }),
      let targetScreen = secondaryScreen()
    else { return }

    fill(window, on: targetScreen)
  }

  func useWindowedMode() {
    guard let window = NSApp.windows.first(where: { $0.title == "AgentMon" }) else { return }

    window.level = .normal
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.setContentSize(NSSize(width: 1280, height: 720))
    window.center()
    window.makeKeyAndOrderFront(nil)
  }

  private func fill(_ window: NSWindow, on screen: NSScreen) {
    window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    window.styleMask = [.borderless, .resizable]
    window.setFrame(screen.frame, display: true, animate: false)
    window.makeKeyAndOrderFront(nil)
  }

  private func secondaryScreen() -> NSScreen? {
    let screens = NSScreen.screens
    guard screens.count > 1 else { return nil }
    return screens.first(where: { $0 != NSScreen.main }) ?? screens.last
  }
}

private struct MenuBarPanel: View {
  @Environment(\.openWindow) private var openWindow
  @EnvironmentObject private var dashboard: DashboardModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        MiniMacIcon(mood: dashboard.system.healthMood)
          .frame(width: 32, height: 38)
        VStack(alignment: .leading, spacing: 2) {
          Text("AgentMon")
            .font(.headline)
          Text(dashboard.summaryLine)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      Label("\(Int(dashboard.system.cpuPercent.rounded()))% processor", systemImage: "cpu")
      Label("\(dashboard.workingAgentCount) agents working", systemImage: "person.2")

      Divider()

      Button("Show Dashboard") {
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
      }

      Button("Fill Secondary Display") {
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          DashboardWindowController.shared.fillSecondaryDisplay()
        }
      }

      Button("Use Windowed Mode") {
        DashboardWindowController.shared.useWindowedMode()
      }

      SettingsLink {
        Text("Settings…")
      }

      Divider()

      Button("Quit AgentMon") {
        NSApplication.shared.terminate(nil)
      }
    }
    .padding(14)
    .frame(width: 250)
  }
}
