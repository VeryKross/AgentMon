import AppKit
import SwiftUI

enum RetroTheme {
  static let ink = Color(red: 0.045, green: 0.05, blue: 0.043)
  static let paper = Color(red: 0.91, green: 0.90, blue: 0.84)
  static let desktop = Color(red: 0.67, green: 0.67, blue: 0.61)
  static let muted = Color(red: 0.32, green: 0.33, blue: 0.30)

  static func font(size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
    let renderedSize = size * 1.5
    if let monaco = NSFont(name: "Monaco", size: renderedSize) {
      if weight.rawValue >= NSFont.Weight.semibold.rawValue {
        let bold = NSFontManager.shared.convert(monaco, toHaveTrait: .boldFontMask)
        return Font(bold)
      }
      return Font(monaco)
    }
    return Font(NSFont.monospacedSystemFont(ofSize: renderedSize, weight: weight))
  }
}

struct DitherPattern: View {
  var spacing: CGFloat = 4
  var dotSize: CGFloat = 1
  var foreground = RetroTheme.ink
  var background = RetroTheme.desktop

  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
      var path = Path()
      var y: CGFloat = 0
      var row = 0
      while y < size.height {
        var x: CGFloat = row.isMultiple(of: 2) ? 0 : spacing / 2
        while x < size.width {
          path.addRect(CGRect(x: x, y: y, width: dotSize, height: dotSize))
          x += spacing
        }
        y += spacing
        row += 1
      }
      context.fill(path, with: .color(foreground.opacity(0.42)))
    }
    .accessibilityHidden(true)
  }
}

struct HorizontalStripes: View {
  var body: some View {
    Canvas { context, size in
      var path = Path()
      var y: CGFloat = 1
      while y < size.height {
        path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
        y += 3
      }
      context.fill(path, with: .color(RetroTheme.ink))
    }
    .accessibilityHidden(true)
  }
}
