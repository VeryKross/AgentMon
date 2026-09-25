import SwiftUI

struct RetroWindow<Content: View>: View {
  let title: String
  var emphasized = false
  @ViewBuilder let content: Content

  init(title: String, emphasized: Bool = false, @ViewBuilder content: () -> Content) {
    self.title = title
    self.emphasized = emphasized
    self.content = content()
  }

  var body: some View {
    ZStack {
      Rectangle()
        .fill(RetroTheme.ink.opacity(0.78))
        .offset(x: 5, y: 5)

      VStack(spacing: 0) {
        ZStack {
          if emphasized {
            RetroTheme.ink
          } else {
            HorizontalStripes()
              .background(RetroTheme.paper)
          }

          Text(title)
            .font(RetroTheme.font(size: 15, weight: .bold))
            .foregroundStyle(emphasized ? RetroTheme.paper : RetroTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(emphasized ? RetroTheme.ink : RetroTheme.paper)

          HStack {
            RetroCloseBox()
            Spacer()
            RetroZoomBox()
          }
          .padding(.horizontal, 7)
        }
        .frame(height: 38)
        .overlay(alignment: .bottom) {
          Rectangle()
            .fill(RetroTheme.ink)
            .frame(height: 2)
        }

        content
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(RetroTheme.paper)
      }
      .foregroundStyle(RetroTheme.ink)
      .background(RetroTheme.paper)
      .overlay {
        Rectangle()
          .stroke(RetroTheme.ink, lineWidth: 3)
      }
    }
  }
}

private struct RetroCloseBox: View {
  var body: some View {
    ZStack {
      Rectangle().fill(RetroTheme.paper)
      Rectangle().stroke(RetroTheme.ink, lineWidth: 2)
    }
    .frame(width: 22, height: 22)
  }
}

private struct RetroZoomBox: View {
  var body: some View {
    ZStack(alignment: .topTrailing) {
      Rectangle().fill(RetroTheme.paper)
      Rectangle().stroke(RetroTheme.ink, lineWidth: 2)
      Rectangle()
        .stroke(RetroTheme.ink, lineWidth: 1)
        .frame(width: 13, height: 13)
    }
    .frame(width: 22, height: 22)
  }
}

struct SegmentedMeter: View {
  let value: Double
  var segments = 18

  var body: some View {
    GeometryReader { geometry in
      let gap: CGFloat = 3
      let segmentWidth = max(
        (geometry.size.width - CGFloat(segments - 1) * gap) / CGFloat(segments),
        1
      )
      let filled = Int((min(max(value, 0), 100) / 100 * Double(segments)).rounded(.up))

      HStack(spacing: gap) {
        ForEach(0..<segments, id: \.self) { index in
          Rectangle()
            .fill(index < filled ? RetroTheme.ink : Color.clear)
            .overlay {
              Rectangle()
                .stroke(RetroTheme.ink, lineWidth: 1)
            }
            .frame(width: segmentWidth)
        }
      }
    }
    .frame(height: 22)
    .accessibilityValue("\(Int(value.rounded())) percent")
  }
}

struct BarHistory: View {
  let values: [Double]

  var body: some View {
    GeometryReader { geometry in
      let count = max(values.count, 1)
      let gap: CGFloat = 2
      let width = max(
        (geometry.size.width - CGFloat(count - 1) * gap) / CGFloat(count),
        1
      )

      HStack(alignment: .bottom, spacing: gap) {
        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
          Rectangle()
            .fill(RetroTheme.ink)
            .frame(
              width: width,
              height: max(2, geometry.size.height * min(max(value, 0), 100) / 100)
            )
        }
      }
      .frame(maxHeight: .infinity, alignment: .bottom)
    }
    .accessibilityHidden(true)
  }
}

struct MiniMacIcon: View {
  let mood: SystemHealthMood

  var body: some View {
    Canvas { context, size in
      let scale = min(size.width / 30, size.height / 36)
      func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
      }

      let body = Path(roundedRect: rect(1, 1, 28, 32), cornerRadius: 2 * scale)
      context.fill(body, with: .color(RetroTheme.paper))
      context.stroke(body, with: .color(RetroTheme.ink), lineWidth: max(scale * 1.5, 1))

      let screen = Path(roundedRect: rect(5, 5, 20, 15), cornerRadius: scale)
      context.stroke(screen, with: .color(RetroTheme.ink), lineWidth: max(scale, 1))

      context.fill(Path(rect(9, 10, 2, 2)), with: .color(RetroTheme.ink))
      context.fill(Path(rect(19, 10, 2, 2)), with: .color(RetroTheme.ink))

      var mouth = Path()
      if mood == .happy {
        mouth.move(to: CGPoint(x: 11 * scale, y: 15 * scale))
        mouth.addLine(to: CGPoint(x: 13 * scale, y: 17 * scale))
        mouth.addLine(to: CGPoint(x: 17 * scale, y: 17 * scale))
        mouth.addLine(to: CGPoint(x: 19 * scale, y: 15 * scale))
      } else {
        mouth.move(to: CGPoint(x: 11 * scale, y: 17 * scale))
        mouth.addLine(to: CGPoint(x: 13 * scale, y: 15 * scale))
        mouth.addLine(to: CGPoint(x: 17 * scale, y: 15 * scale))
        mouth.addLine(to: CGPoint(x: 19 * scale, y: 17 * scale))
      }
      context.stroke(mouth, with: .color(RetroTheme.ink), lineWidth: max(scale, 1))

      context.fill(Path(rect(5, 24, 20, 2)), with: .color(RetroTheme.ink))
      context.fill(Path(rect(22, 28, 3, 2)), with: .color(RetroTheme.ink))
    }
    .accessibilityLabel(mood == .happy ? "System healthy" : "System needs attention")
  }
}

struct StatusGlyph: View {
  let activity: AgentActivity

  var body: some View {
    ZStack {
      Rectangle()
        .fill(activity == .attention ? RetroTheme.ink : RetroTheme.paper)
        .overlay {
          Rectangle().stroke(RetroTheme.ink, lineWidth: 2)
        }

      glyph
        .foregroundStyle(activity == .attention ? RetroTheme.paper : RetroTheme.ink)
    }
    .frame(width: 50, height: 50)
    .accessibilityLabel(activity.title)
  }

  @ViewBuilder
  private var glyph: some View {
    switch activity {
    case .working:
      PixelWatch()
    case .ready:
      Image(systemName: "checkmark")
        .font(.system(size: 21, weight: .black))
    case .attention:
      Text("?")
        .font(RetroTheme.font(size: 27, weight: .bold))
    case .offline:
      Image(systemName: "moon.fill")
        .font(.system(size: 18, weight: .black))
    }
  }
}

private struct PixelWatch: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    if reduceMotion {
      watchFace(tick: 0)
    } else {
      TimelineView(.periodic(from: .now, by: 1)) { timeline in
        watchFace(tick: Int(timeline.date.timeIntervalSinceReferenceDate))
      }
    }
  }

  private func watchFace(tick: Int) -> some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = min(size.width, size.height) * 0.28
      context.stroke(
        Path(
          ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
          )),
        with: .color(RetroTheme.ink),
        lineWidth: 2
      )
      context.fill(
        Path(CGRect(x: center.x - 4, y: 2, width: 8, height: 4)),
        with: .color(RetroTheme.ink)
      )
      var hands = Path()
      let longAngle = CGFloat(tick % 12) * .pi / 6 - .pi / 2
      let shortAngle = CGFloat((tick / 4 + 3) % 12) * .pi / 6 - .pi / 2
      hands.move(to: center)
      hands.addLine(
        to: CGPoint(
          x: center.x + cos(longAngle) * (radius - 3),
          y: center.y + sin(longAngle) * (radius - 3)
        ))
      hands.move(to: center)
      hands.addLine(
        to: CGPoint(
          x: center.x + cos(shortAngle) * (radius - 7),
          y: center.y + sin(shortAngle) * (radius - 7)
        ))
      context.stroke(hands, with: .color(RetroTheme.ink), lineWidth: 2)
      context.fill(
        Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)),
        with: .color(RetroTheme.ink)
      )
    }
  }
}
