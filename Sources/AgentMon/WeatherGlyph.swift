import SwiftUI

struct WeatherGlyph: View {
  private let artwork: WeatherArtwork
  private let label: String

  init(weather: WeatherSnapshot?) {
    artwork = weather?.artwork ?? .unknown
    label = weather?.condition ?? "Weather not configured"
  }

  init(artwork: WeatherArtwork, label: String) {
    self.artwork = artwork
    self.label = label
  }

  var body: some View {
    Canvas { context, size in
      WeatherGlyphRenderer.draw(artwork, in: context, size: size)
    }
    .accessibilityLabel(label)
  }
}

private enum WeatherGlyphRenderer {
  private static let ink = RetroTheme.ink
  private static let paper = RetroTheme.paper

  static func draw(_ artwork: WeatherArtwork, in context: GraphicsContext, size: CGSize) {
    switch artwork {
    case .sunny:
      drawSun(
        in: context, size: size, center: point(0.50, 0.48, in: size), radius: size.width * 0.22)
    case .clearNight:
      drawStars(in: context, size: size)
      drawMoon(
        in: context, size: size, center: point(0.50, 0.48, in: size), radius: size.width * 0.25)
    case .mostlySunny:
      drawSun(
        in: context, size: size, center: point(0.64, 0.32, in: size), radius: size.width * 0.17)
      drawCloud(in: context, rect: rect(0.08, 0.43, 0.75, 0.39, in: size), shade: .light)
    case .mostlyClearNight:
      drawStars(in: context, size: size)
      drawMoon(
        in: context, size: size, center: point(0.65, 0.31, in: size), radius: size.width * 0.19)
      drawCloud(in: context, rect: rect(0.08, 0.49, 0.68, 0.33, in: size), shade: .light)
    case .partlyCloudyDay:
      drawSun(
        in: context, size: size, center: point(0.67, 0.29, in: size), radius: size.width * 0.17)
      drawCloud(in: context, rect: rect(0.06, 0.36, 0.88, 0.48, in: size), shade: .medium)
    case .partlyCloudyNight:
      drawStars(in: context, size: size)
      drawMoon(
        in: context, size: size, center: point(0.69, 0.28, in: size), radius: size.width * 0.19)
      drawCloud(in: context, rect: rect(0.06, 0.39, 0.88, 0.45, in: size), shade: .medium)
    case .mostlyCloudyDay:
      drawSun(
        in: context, size: size, center: point(0.77, 0.24, in: size), radius: size.width * 0.15)
      drawCloud(in: context, rect: rect(0.03, 0.27, 0.94, 0.57, in: size), shade: .heavy)
    case .mostlyCloudyNight:
      drawMoon(
        in: context, size: size, center: point(0.77, 0.23, in: size), radius: size.width * 0.17)
      drawCloud(in: context, rect: rect(0.03, 0.27, 0.94, 0.57, in: size), shade: .heavy)
    case .overcast:
      drawCloud(in: context, rect: rect(0.22, 0.18, 0.72, 0.40, in: size), shade: .medium)
      drawCloud(in: context, rect: rect(0.02, 0.37, 0.94, 0.49, in: size), shade: .heavy)
    case .fog:
      drawCloud(in: context, rect: rect(0.22, 0.12, 0.65, 0.34, in: size), shade: .light)
      drawFog(in: context, size: size)
    case .drizzle:
      drawCloud(in: context, rect: rect(0.04, 0.10, 0.92, 0.48, in: size), shade: .medium)
      drawPrecipitation(in: context, size: size, kind: .drizzle)
    case .rain:
      drawCloud(in: context, rect: rect(0.04, 0.08, 0.92, 0.50, in: size), shade: .heavy)
      drawPrecipitation(in: context, size: size, kind: .rain)
    case .snow:
      drawCloud(in: context, rect: rect(0.04, 0.08, 0.92, 0.50, in: size), shade: .medium)
      drawPrecipitation(in: context, size: size, kind: .snow)
    case .thunderstorm:
      drawCloud(in: context, rect: rect(0.02, 0.06, 0.96, 0.51, in: size), shade: .heavy)
      drawLightning(in: context, size: size)
      drawPrecipitation(in: context, size: size, kind: .storm)
    case .unknown:
      drawUnknown(in: context, size: size)
    }
  }

  private enum CloudShade: Equatable {
    case light
    case medium
    case heavy
  }

  private enum Precipitation: Equatable {
    case drizzle
    case rain
    case snow
    case storm
  }

  private static func drawSun(
    in context: GraphicsContext,
    size: CGSize,
    center: CGPoint,
    radius: CGFloat
  ) {
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
      let inner = radius + 5
      let outer = radius + 12
      var ray = Path()
      ray.move(
        to: CGPoint(
          x: center.x + cos(angle) * Double(inner),
          y: center.y + sin(angle) * Double(inner)
        ))
      ray.addLine(
        to: CGPoint(
          x: center.x + cos(angle) * Double(outer),
          y: center.y + sin(angle) * Double(outer)
        ))
      context.stroke(ray, with: .color(ink), lineWidth: 2)
    }
  }

  private static func drawMoon(
    in context: GraphicsContext,
    size: CGSize,
    center: CGPoint,
    radius: CGFloat
  ) {
    let moon = Path(
      ellipseIn: CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      ))
    context.fill(moon, with: .color(ink))

    let cutout = Path(
      ellipseIn: CGRect(
        x: center.x - radius * 0.25,
        y: center.y - radius * 1.05,
        width: radius * 1.8,
        height: radius * 1.8
      ))
    context.fill(cutout, with: .color(paper))
  }

  private static func drawStars(in context: GraphicsContext, size: CGSize) {
    let stars = [
      point(0.16, 0.18, in: size),
      point(0.27, 0.35, in: size),
      point(0.84, 0.13, in: size),
      point(0.88, 0.44, in: size),
    ]

    for (index, center) in stars.enumerated() {
      let arm: CGFloat = index.isMultiple(of: 2) ? 5 : 3
      var star = Path()
      star.move(to: CGPoint(x: center.x - arm, y: center.y))
      star.addLine(to: CGPoint(x: center.x + arm, y: center.y))
      star.move(to: CGPoint(x: center.x, y: center.y - arm))
      star.addLine(to: CGPoint(x: center.x, y: center.y + arm))
      context.stroke(star, with: .color(ink), lineWidth: 1.5)
    }
  }

  private static func drawCloud(
    in context: GraphicsContext,
    rect: CGRect,
    shade: CloudShade
  ) {
    let cloud = cloudPath(in: rect)
    context.fill(cloud, with: .color(paper))
    context.stroke(cloud, with: .color(ink), lineWidth: 3)

    guard shade != .light else { return }

    context.drawLayer { layer in
      layer.clip(to: cloud)
      var marks = Path()
      let startY = rect.minY + rect.height * (shade == .heavy ? 0.48 : 0.64)
      let spacing: CGFloat = shade == .heavy ? 5 : 7
      var y = startY
      var row = 0

      while y < rect.maxY {
        var x = rect.minX + CGFloat(row % 2) * spacing / 2
        while x < rect.maxX {
          marks.addRect(CGRect(x: x, y: y, width: 2, height: 2))
          x += spacing
        }
        y += spacing
        row += 1
      }
      layer.fill(marks, with: .color(ink))
    }
  }

  private static func cloudPath(in rect: CGRect) -> Path {
    var cloud = Path()
    cloud.move(to: CGPoint(x: rect.minX + rect.width * 0.13, y: rect.maxY))
    cloud.addCurve(
      to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.55),
      control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.94),
      control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.62)
    )
    cloud.addCurve(
      to: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.40),
      control1: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.minY + rect.height * 0.38),
      control2: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.36)
    )
    cloud.addCurve(
      to: CGPoint(x: rect.minX + rect.width * 0.69, y: rect.minY + rect.height * 0.43),
      control1: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY),
      control2: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.minY + rect.height * 0.05)
    )
    cloud.addCurve(
      to: CGPoint(x: rect.minX + rect.width * 0.91, y: rect.minY + rect.height * 0.63),
      control1: CGPoint(x: rect.minX + rect.width * 0.80, y: rect.minY + rect.height * 0.32),
      control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.48)
    )
    cloud.addCurve(
      to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.maxY),
      control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.82),
      control2: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.maxY)
    )
    cloud.closeSubpath()
    return cloud
  }

  private static func drawFog(in context: GraphicsContext, size: CGSize) {
    for index in 0..<4 {
      let y = size.height * (0.52 + CGFloat(index) * 0.12)
      let inset = index.isMultiple(of: 2) ? size.width * 0.08 : size.width * 0.20
      var line = Path()
      line.move(to: CGPoint(x: inset, y: y))
      line.addCurve(
        to: CGPoint(x: size.width - inset, y: y),
        control1: CGPoint(x: size.width * 0.38, y: y - 4),
        control2: CGPoint(x: size.width * 0.62, y: y + 4)
      )
      context.stroke(line, with: .color(ink), lineWidth: index == 0 ? 3 : 2)
    }
  }

  private static func drawPrecipitation(
    in context: GraphicsContext,
    size: CGSize,
    kind: Precipitation
  ) {
    let xs: [CGFloat] = [0.24, 0.42, 0.60, 0.78]

    for (index, fraction) in xs.enumerated() {
      let x = size.width * fraction
      let y = size.height * (index.isMultiple(of: 2) ? 0.64 : 0.70)

      switch kind {
      case .drizzle:
        context.fill(
          Path(ellipseIn: CGRect(x: x - 2, y: y, width: 4, height: 4)),
          with: .color(ink)
        )
        context.fill(
          Path(ellipseIn: CGRect(x: x + 3, y: y + 11, width: 3, height: 3)),
          with: .color(ink)
        )
      case .rain, .storm:
        var drop = Path()
        drop.move(to: CGPoint(x: x + 4, y: y))
        drop.addLine(
          to: CGPoint(
            x: x - (kind == .storm ? 6 : 4),
            y: y + (kind == .storm ? 22 : 18)
          ))
        context.stroke(drop, with: .color(ink), lineWidth: kind == .storm ? 3 : 2)
      case .snow:
        drawSnowflake(in: context, center: CGPoint(x: x, y: y + 8), radius: 6)
      }
    }
  }

  private static func drawSnowflake(
    in context: GraphicsContext,
    center: CGPoint,
    radius: CGFloat
  ) {
    var flake = Path()
    for index in 0..<3 {
      let angle = Double(index) * .pi / 3
      flake.move(
        to: CGPoint(
          x: center.x - cos(angle) * Double(radius),
          y: center.y - sin(angle) * Double(radius)
        ))
      flake.addLine(
        to: CGPoint(
          x: center.x + cos(angle) * Double(radius),
          y: center.y + sin(angle) * Double(radius)
        ))
    }
    context.stroke(flake, with: .color(ink), lineWidth: 1.5)
  }

  private static func drawLightning(in context: GraphicsContext, size: CGSize) {
    var bolt = Path()
    bolt.move(to: point(0.53, 0.49, in: size))
    bolt.addLine(to: point(0.39, 0.72, in: size))
    bolt.addLine(to: point(0.52, 0.70, in: size))
    bolt.addLine(to: point(0.43, 0.95, in: size))
    bolt.addLine(to: point(0.70, 0.62, in: size))
    bolt.addLine(to: point(0.55, 0.64, in: size))
    bolt.closeSubpath()
    context.fill(bolt, with: .color(paper))
    context.stroke(bolt, with: .color(ink), lineWidth: 3)
  }

  private static func drawUnknown(in context: GraphicsContext, size: CGSize) {
    drawCloud(in: context, rect: rect(0.05, 0.25, 0.90, 0.55, in: size), shade: .light)
    context.draw(
      Text("?")
        .font(RetroTheme.font(size: 27, weight: .bold))
        .foregroundStyle(ink),
      at: point(0.50, 0.59, in: size)
    )
  }

  private static func point(_ x: CGFloat, _ y: CGFloat, in size: CGSize) -> CGPoint {
    CGPoint(x: size.width * x, y: size.height * y)
  }

  private static func rect(
    _ x: CGFloat,
    _ y: CGFloat,
    _ width: CGFloat,
    _ height: CGFloat,
    in size: CGSize
  ) -> CGRect {
    CGRect(
      x: size.width * x,
      y: size.height * y,
      width: size.width * width,
      height: size.height * height
    )
  }
}
