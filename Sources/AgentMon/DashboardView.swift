import SwiftUI

/*
 THESIS: A working System 6 desktop is the instrument; it refuses modern dashboard cards with retro decoration.
 OWN-WORLD: One-bit ink, warm CRT paper, dithered desktop, striped window chrome, pixel icons, and hard offset shadows.
 STORY: Read Mac health, see which Copilot projects are moving, then catch time and weather without touching the screen.
 FIRST VIEWPORT: A menu strip caps a fixed desktop; System Monitor anchors the left rail and Agent Desk owns the broad right field.
 FORM: Macintosh Mission Control, a fixed ambient operations desktop built for one dedicated 1280x720 display.
 */
struct DashboardView: View {
  @EnvironmentObject private var dashboard: DashboardModel
  @State private var pulse = false

  var body: some View {
    GeometryReader { geometry in
      let scale = min(geometry.size.width / 1280, geometry.size.height / 720)

      ZStack(alignment: .topLeading) {
        DitherPattern()

        VStack(spacing: 0) {
          DesktopMenuBar()
            .frame(height: 46)

          HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 14) {
              SystemMonitorWindow()
                .frame(width: 400, height: 432)

              WeatherWindow()
                .frame(width: 400, height: 206)
            }

            AgentDeskWindow(pulse: pulse)
              .frame(width: 826, height: 652)
          }
          .padding(.horizontal, 18)
          .padding(.top, 12)
          .padding(.bottom, 10)
        }
        .frame(width: 1280, height: 720)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(
          width: 1280 * scale,
          height: 720 * scale,
          alignment: .topLeading
        )
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(RetroTheme.desktop)
      .clipped()
    }
    .ignoresSafeArea()
    .preferredColorScheme(.light)
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(650))
        pulse.toggle()
      }
    }
  }
}

private struct DesktopMenuBar: View {
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      HStack(spacing: 24) {
        MiniMacIcon(mood: .happy)
          .frame(width: 28, height: 33)

        Text("AgentMon")
          .font(RetroTheme.font(size: 16, weight: .bold))

        Text("Desk")
        Text("Monitors")
        Text("Window")

        Spacer()

        Text(timeline.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        Text(timeline.date.formatted(.dateTime.hour().minute().second()))
          .frame(width: 160, alignment: .trailing)
      }
      .font(RetroTheme.font(size: 15))
      .foregroundStyle(RetroTheme.ink)
      .padding(.horizontal, 13)
      .background(RetroTheme.paper)
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(RetroTheme.ink)
          .frame(height: 2)
      }
    }
  }
}

private struct SystemMonitorWindow: View {
  @EnvironmentObject private var dashboard: DashboardModel

  var body: some View {
    RetroWindow(title: "This Macintosh") {
      VStack(spacing: 0) {
        HStack(spacing: 14) {
          MiniMacIcon(mood: dashboard.system.healthMood)
            .frame(width: 64, height: 77)

          VStack(alignment: .leading, spacing: 5) {
            Text(
              dashboard.system.healthMood == .happy
                ? "System shipshape." : "Memory is crowded."
            )
            .font(RetroTheme.font(size: 17, weight: .bold))
            Text(dashboard.system.hostname)
              .font(RetroTheme.font(size: 13))
              .foregroundStyle(RetroTheme.muted)
              .lineLimit(1)
            Text("UP \(DisplayFormat.uptime(dashboard.system.uptime))")
              .font(RetroTheme.font(size: 12, weight: .bold))
          }

          Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        Rectangle()
          .fill(RetroTheme.ink)
          .frame(height: 2)

        VStack(spacing: 12) {
          MetricBlock(
            title: "PROCESSOR",
            value: dashboard.system.cpuPercent,
            detail: "\(Int(dashboard.system.cpuPercent.rounded()))%",
            history: dashboard.cpuHistory
          )
          MetricBlock(
            title: "MEMORY",
            value: dashboard.system.memoryPercent,
            detail:
              "\(DisplayFormat.bytes(dashboard.system.memoryUsed)) / \(DisplayFormat.bytes(dashboard.system.memoryTotal))",
            history: dashboard.memoryHistory
          )
          MetricBlock(
            title: "STARTUP DISK",
            value: dashboard.system.diskPercent,
            detail:
              "\(DisplayFormat.bytes(dashboard.system.diskUsed)) / \(DisplayFormat.bytes(dashboard.system.diskTotal))",
            history: nil
          )
        }
        .padding(14)

        Spacer(minLength: 0)

        HStack {
          Text("AUTO-SAMPLING")
          Spacer()
          Text("EVERY 3 SEC")
        }
        .font(RetroTheme.font(size: 11, weight: .bold))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(DitherPattern(spacing: 5, dotSize: 1, background: RetroTheme.paper))
        .overlay(alignment: .top) {
          Rectangle().fill(RetroTheme.ink).frame(height: 1)
        }
      }
    }
  }
}

private struct MetricBlock: View {
  let title: String
  let value: Double
  let detail: String
  let history: [Double]?

  var body: some View {
    VStack(spacing: 7) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(RetroTheme.font(size: 12, weight: .bold))
        Spacer()
        Text(detail)
          .font(RetroTheme.font(size: 12))
      }

      if let history {
        HStack(alignment: .bottom, spacing: 10) {
          SegmentedMeter(value: value, segments: 14)
          BarHistory(values: history)
            .frame(width: 74, height: 24)
        }
      } else {
        SegmentedMeter(value: value, segments: 20)
      }
    }
  }
}

private struct AgentDeskWindow: View {
  @EnvironmentObject private var dashboard: DashboardModel
  let pulse: Bool

  private var visibleSessions: [AgentSession] {
    Array(dashboard.sessions.prefix(4))
  }

  var body: some View {
    RetroWindow(title: "Agent Desk", emphasized: dashboard.attentionCount > 0) {
      VStack(spacing: 0) {
        HStack(alignment: .center, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text(dashboard.summaryLine)
              .font(RetroTheme.font(size: 24, weight: .bold))
            Text("GITHUB COPILOT PROJECT SESSIONS")
              .font(RetroTheme.font(size: 11, weight: .bold))
              .foregroundStyle(RetroTheme.muted)
          }

          Spacer()

          AgentTally(label: "WORKING", count: dashboard.workingAgentCount)
          AgentTally(
            label: "READY", count: dashboard.sessions.filter { $0.activity == .ready }.count)
        }
        .padding(.horizontal, 21)
        .frame(height: 100)

        Rectangle().fill(RetroTheme.ink).frame(height: 2)

        HStack(spacing: 0) {
          Text("STATE")
            .frame(width: 76, alignment: .leading)
          Text("PROJECT / ASSIGNMENT")
          Spacer()
          Text("SEEN")
            .frame(width: 54, alignment: .trailing)
        }
        .font(RetroTheme.font(size: 11, weight: .bold))
        .padding(.horizontal, 18)
        .frame(height: 36)
        .background(DitherPattern(spacing: 5, dotSize: 1, background: RetroTheme.paper))
        .overlay(alignment: .bottom) {
          Rectangle().fill(RetroTheme.ink).frame(height: 1)
        }

        if visibleSessions.isEmpty {
          EmptyAgentDesk()
        } else {
          VStack(spacing: 0) {
            ForEach(visibleSessions) { session in
              AgentRow(session: session, pulse: pulse)
              if session.id != visibleSessions.last?.id {
                DashedRule()
              }
            }
          }
        }

        Spacer(minLength: 0)

        HStack {
          Text("LOCAL SESSION INDEX")
          Spacer()
          if dashboard.sessions.count > visibleSessions.count {
            Text("+\(dashboard.sessions.count - visibleSessions.count) MORE IN DRAWER")
          } else {
            Text("\(dashboard.sessions.count) ON DESK")
          }
        }
        .font(RetroTheme.font(size: 11, weight: .bold))
        .padding(.horizontal, 16)
        .frame(height: 40)
        .overlay(alignment: .top) {
          Rectangle().fill(RetroTheme.ink).frame(height: 2)
        }
      }
    }
  }
}

private struct AgentTally: View {
  let label: String
  let count: Int

  var body: some View {
    VStack(spacing: 2) {
      Text("\(count)")
        .font(RetroTheme.font(size: 25, weight: .bold))
      Text(label)
        .font(RetroTheme.font(size: 9, weight: .bold))
    }
    .frame(width: 72, height: 66)
    .overlay {
      Rectangle().stroke(RetroTheme.ink, lineWidth: 2)
    }
  }
}

private struct AgentRow: View {
  let session: AgentSession
  let pulse: Bool

  var body: some View {
    HStack(spacing: 16) {
      StatusGlyph(activity: session.activity, pulse: pulse)
        .frame(width: 66)

      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 9) {
          Text(session.project)
            .font(RetroTheme.font(size: 18, weight: .bold))
            .lineLimit(1)

          Text(session.activity.title)
            .font(RetroTheme.font(size: 9, weight: .bold))
            .foregroundStyle(
              session.activity == .attention ? RetroTheme.paper : RetroTheme.ink
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
              session.activity == .attention ? RetroTheme.ink : RetroTheme.paper
            )
            .overlay {
              Rectangle().stroke(RetroTheme.ink, lineWidth: 1)
            }
        }

        Text(session.task)
          .font(RetroTheme.font(size: 13))
          .foregroundStyle(RetroTheme.muted)
          .lineLimit(1)

        if let branch = session.branch, !branch.isEmpty {
          Text(branch)
            .font(RetroTheme.font(size: 10))
            .lineLimit(1)
        }
      }

      Spacer(minLength: 8)

      Text(DisplayFormat.relativeTime(from: session.updatedAt))
        .font(RetroTheme.font(size: 12, weight: .bold))
        .frame(width: 48, alignment: .trailing)
    }
    .padding(.horizontal, 17)
    .frame(height: 104)
    .background(session.activity == .attention ? RetroTheme.ink.opacity(0.08) : Color.clear)
  }
}

private struct EmptyAgentDesk: View {
  var body: some View {
    VStack(spacing: 18) {
      PixelFolder()
        .frame(width: 78, height: 58)
      Text("No recent Copilot sessions")
        .font(RetroTheme.font(size: 18, weight: .bold))
      Text("New work will appear here automatically.")
        .font(RetroTheme.font(size: 13))
        .foregroundStyle(RetroTheme.muted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct WeatherWindow: View {
  @EnvironmentObject private var dashboard: DashboardModel

  var body: some View {
    RetroWindow(title: "Weather") {
      HStack(spacing: 20) {
        WeatherGlyph(weather: dashboard.weather)
          .frame(width: 108, height: 100)

        if let weather = dashboard.weather {
          VStack(alignment: .leading, spacing: 5) {
            Text("\(Int(weather.temperature.rounded()))°")
              .font(RetroTheme.font(size: 39, weight: .bold))
            Text(weather.condition.uppercased())
              .font(RetroTheme.font(size: 12, weight: .bold))
            Text(weather.location)
              .font(RetroTheme.font(size: 11))
              .foregroundStyle(RetroTheme.muted)
              .lineLimit(1)
          }
        } else {
          VStack(alignment: .leading, spacing: 7) {
            Text(dashboard.isRefreshing ? "Calling weather…" : "Weather is off duty.")
              .font(RetroTheme.font(size: 16, weight: .bold))
            Text(dashboard.weatherError ?? "Set a town in AgentMon Settings.")
              .font(RetroTheme.font(size: 12))
              .foregroundStyle(RetroTheme.muted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
    }
  }
}

private struct WeatherGlyph: View {
  let weather: WeatherSnapshot?

  var body: some View {
    Canvas { context, size in
      let ink = RetroTheme.ink
      let paper = RetroTheme.paper
      let center = CGPoint(x: size.width * 0.65, y: size.height * 0.29)
      let radius = size.width * 0.16

      context.stroke(
        Path(
          ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
          )),
        with: .color(ink),
        lineWidth: 3
      )

      for index in 0..<12 {
        let angle = Double(index) * .pi / 6
        var ray = Path()
        ray.move(
          to: CGPoint(
            x: center.x + cos(angle) * Double(radius + 4),
            y: center.y + sin(angle) * Double(radius + 4)
          ))
        ray.addLine(
          to: CGPoint(
            x: center.x + cos(angle) * Double(radius + 10),
            y: center.y + sin(angle) * Double(radius + 10)
          ))
        context.stroke(ray, with: .color(ink), lineWidth: 2)
      }

      if weather == nil || weather?.showsClouds == true {
        var cloud = Path()
        cloud.move(to: CGPoint(x: size.width * 0.17, y: size.height * 0.78))
        cloud.addCurve(
          to: CGPoint(x: size.width * 0.16, y: size.height * 0.55),
          control1: CGPoint(x: size.width * 0.08, y: size.height * 0.73),
          control2: CGPoint(x: size.width * 0.08, y: size.height * 0.60)
        )
        cloud.addCurve(
          to: CGPoint(x: size.width * 0.36, y: size.height * 0.48),
          control1: CGPoint(x: size.width * 0.21, y: size.height * 0.48),
          control2: CGPoint(x: size.width * 0.28, y: size.height * 0.47)
        )
        cloud.addCurve(
          to: CGPoint(x: size.width * 0.69, y: size.height * 0.50),
          control1: CGPoint(x: size.width * 0.42, y: size.height * 0.29),
          control2: CGPoint(x: size.width * 0.64, y: size.height * 0.32)
        )
        cloud.addCurve(
          to: CGPoint(x: size.width * 0.89, y: size.height * 0.63),
          control1: CGPoint(x: size.width * 0.80, y: size.height * 0.45),
          control2: CGPoint(x: size.width * 0.89, y: size.height * 0.53)
        )
        cloud.addCurve(
          to: CGPoint(x: size.width * 0.77, y: size.height * 0.79),
          control1: CGPoint(x: size.width * 0.95, y: size.height * 0.70),
          control2: CGPoint(x: size.width * 0.88, y: size.height * 0.79)
        )
        cloud.closeSubpath()
        context.fill(cloud, with: .color(paper))
        context.stroke(cloud, with: .color(ink), lineWidth: 3)

        var dither = Path()
        var y = size.height * 0.67
        var row = 0
        while y < size.height * 0.78 {
          var x = size.width * 0.22 + CGFloat(row % 2) * 3
          while x < size.width * 0.78 {
            dither.addRect(CGRect(x: x, y: y, width: 2, height: 2))
            x += 6
          }
          y += 5
          row += 1
        }
        context.fill(dither, with: .color(ink))

        var contour = Path()
        contour.move(to: CGPoint(x: size.width * 0.27, y: size.height * 0.58))
        contour.addCurve(
          to: CGPoint(x: size.width * 0.73, y: size.height * 0.60),
          control1: CGPoint(x: size.width * 0.38, y: size.height * 0.48),
          control2: CGPoint(x: size.width * 0.61, y: size.height * 0.49)
        )
        context.stroke(
          contour,
          with: .color(ink),
          style: StrokeStyle(lineWidth: 1.5, dash: [2, 3])
        )
      }
    }
    .accessibilityLabel(weather?.condition ?? "Weather not configured")
  }
}

private struct PixelFolder: View {
  var body: some View {
    Canvas { context, size in
      var path = Path()
      path.move(to: CGPoint(x: 1, y: size.height * 0.22))
      path.addLine(to: CGPoint(x: size.width * 0.35, y: size.height * 0.22))
      path.addLine(to: CGPoint(x: size.width * 0.45, y: 1))
      path.addLine(to: CGPoint(x: size.width * 0.72, y: 1))
      path.addLine(to: CGPoint(x: size.width * 0.80, y: size.height * 0.22))
      path.addLine(to: CGPoint(x: size.width - 1, y: size.height * 0.22))
      path.addLine(to: CGPoint(x: size.width - 1, y: size.height - 1))
      path.addLine(to: CGPoint(x: 1, y: size.height - 1))
      path.closeSubpath()
      context.fill(path, with: .color(RetroTheme.paper))
      context.stroke(path, with: .color(RetroTheme.ink), lineWidth: 3)
    }
    .accessibilityHidden(true)
  }
}

private struct DashedRule: View {
  var body: some View {
    Canvas { context, size in
      var path = Path()
      var x: CGFloat = 0
      while x < size.width {
        path.addRect(CGRect(x: x, y: 0, width: 5, height: 1))
        x += 9
      }
      context.fill(path, with: .color(RetroTheme.ink))
    }
    .frame(height: 1)
    .padding(.horizontal, 17)
    .accessibilityHidden(true)
  }
}
