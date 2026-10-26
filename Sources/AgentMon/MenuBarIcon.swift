import AppKit

/// A template version of the AgentMon app icon (smiling compact Mac with a stopwatch badge),
/// drawn on an 18 pt grid so macOS can tint it for light, dark, and highlighted menu bars.
enum MenuBarIcon {
  static let image: NSImage = {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
      NSColor.black.setFill()
      NSColor.black.setStroke()

      let body = NSBezierPath(
        roundedRect: NSRect(x: 1.75, y: 3.75, width: 12, height: 13.5), xRadius: 1.5, yRadius: 1.5)
      body.lineWidth = 1.5
      body.stroke()

      let screen = NSBezierPath(rect: NSRect(x: 4, y: 6, width: 7.5, height: 5.5))
      screen.lineWidth = 1
      screen.stroke()

      NSRect(x: 5.5, y: 7.5, width: 1, height: 1).fill()
      NSRect(x: 9, y: 7.5, width: 1, height: 1).fill()
      let smile = NSBezierPath()
      smile.move(to: NSPoint(x: 5.5, y: 9.25))
      smile.line(to: NSPoint(x: 6.5, y: 10.25))
      smile.line(to: NSPoint(x: 9, y: 10.25))
      smile.line(to: NSPoint(x: 10, y: 9.25))
      smile.lineWidth = 1
      smile.stroke()

      NSRect(x: 3.5, y: 13.5, width: 5.5, height: 1).fill()
      NSRect(x: 10.5, y: 13.5, width: 1.5, height: 1).fill()

      // Clear a gap around the stopwatch so it reads as a separate badge.
      NSGraphicsContext.current?.compositingOperation = .clear
      NSBezierPath(ovalIn: NSRect(x: 9.25, y: 0.5, width: 8.75, height: 8.75)).fill()
      NSGraphicsContext.current?.compositingOperation = .sourceOver

      let watch = NSBezierPath(ovalIn: NSRect(x: 10.75, y: 2, width: 5.75, height: 5.75))
      watch.lineWidth = 1.25
      watch.stroke()
      NSRect(x: 12.75, y: 0, width: 1.75, height: 1.25).fill()
      let hands = NSBezierPath()
      hands.move(to: NSPoint(x: 13.625, y: 3.25))
      hands.line(to: NSPoint(x: 13.625, y: 4.875))
      hands.line(to: NSPoint(x: 14.875, y: 5.875))
      hands.lineWidth = 1
      hands.stroke()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "AgentMon"
    return image
  }()
}
