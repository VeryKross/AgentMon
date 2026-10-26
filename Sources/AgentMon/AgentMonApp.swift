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

    MenuBarExtra {
      MenuBarPanel()
        .environmentObject(dashboard)
    } label: {
      MenuBarLabel()
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environmentObject(dashboard)
        .background(
          SettingsWindowAccessor { window in
            SettingsWindowController.shared.configure(window)
          }
        )
    }
  }
}

private struct DashboardWindowAccessor: NSViewRepresentable {
  let onWindowAvailable: (NSWindow) -> Void

  func makeNSView(context: Context) -> WindowObservingView {
    let view = WindowObservingView()
    view.onWindowAvailable = onWindowAvailable
    return view
  }

  func updateNSView(_ nsView: WindowObservingView, context: Context) {
    nsView.onWindowAvailable = onWindowAvailable
    if let window = nsView.window {
      DispatchQueue.main.async { onWindowAvailable(window) }
    }
  }
}

/// Reports its window as soon as AppKit attaches it, rather than polling after an async hop.
final class WindowObservingView: NSView {
  var onWindowAvailable: ((NSWindow) -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let window {
      onWindowAvailable?(window)
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

    // SwiftUI may restore its autosaved frame after the window first appears; fill again once it settles.
    for delay in [0.5, 1.5] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak window, weak self] in
        guard let window, let self, let screen = self.secondaryScreen(),
          window.frame != screen.frame
        else { return }
        self.fill(window, on: screen)
      }
    }
  }

  func fillSecondaryDisplay() {
    guard let window = NSApp.windows.first(where: { $0.title == "AgentMon" }),
      let targetScreen = secondaryScreen()
    else { return }

    fill(window, on: targetScreen)
  }

  func showDashboard() {
    guard let window = NSApp.windows.first(where: { $0.title == "AgentMon" }) else { return }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
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
    window.level = .normal
    window.styleMask = [.borderless, .resizable]
    window.setFrame(screen.frame, display: true, animate: false)
    window.makeKeyAndOrderFront(nil)
  }

  private func secondaryScreen() -> NSScreen? {
    Self.secondary(of: NSScreen.screens)
  }

  /// The first screen is the one with the menu bar; `NSScreen.main` follows the key window instead,
  /// which points at the dashboard's own display once it has focus.
  nonisolated static func secondary<Screen>(of screens: [Screen]) -> Screen? {
    screens.dropFirst().first
  }
}

private struct MenuBarLabel: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Image(nsImage: MenuBarIcon.image)
      .accessibilityLabel("AgentMon")
      .task {
        // The dashboard owns refresh, so make sure it exists even if window restoration skipped it.
        try? await Task.sleep(for: .seconds(2))
        if !NSApp.windows.contains(where: { $0.title == "AgentMon" }) {
          openWindow(id: "dashboard")
        }
      }
  }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
  let onWindowAvailable: (NSWindow) -> Void

  func makeNSView(context: Context) -> WindowObservingView {
    let view = WindowObservingView()
    view.onWindowAvailable = onWindowAvailable
    return view
  }

  func updateNSView(_ nsView: WindowObservingView, context: Context) {
    nsView.onWindowAvailable = onWindowAvailable
    if let window = nsView.window {
      DispatchQueue.main.async { onWindowAvailable(window) }
    }
  }
}

@MainActor
final class SettingsWindowController {
  static let shared = SettingsWindowController()

  private var configuredWindows = Set<ObjectIdentifier>()

  func configure(_ window: NSWindow) {
    let identifier = ObjectIdentifier(window)
    if configuredWindows.insert(identifier).inserted {
      window.title = "AgentMon Settings"
      window.collectionBehavior.insert(.moveToActiveSpace)

      if let primaryScreen = NSScreen.screens.first {
        let visibleFrame = primaryScreen.visibleFrame
        window.setFrameOrigin(
          NSPoint(
            x: visibleFrame.midX - window.frame.width / 2,
            y: visibleFrame.midY - window.frame.height / 2
          )
        )
      } else {
        window.center()
      }
    }

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
}

private struct MenuBarPanel: View {
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
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

      Button("Settings…") {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
      }

      Button("Mark All Seen") {
        dashboard.acknowledgeAllCompletions()
      }
      .disabled(dashboard.unseenCompletions.isEmpty)

      Divider()

      Button("Quit AgentMon") {
        NSApplication.shared.terminate(nil)
      }
    }
    .padding(14)
    .frame(width: 250)
  }
}
