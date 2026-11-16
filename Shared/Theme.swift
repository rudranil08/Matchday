import SwiftUI
import CoreText

// v.3 design: chalk grey ground, navy ink, cobalt for app controls,
// and each club's own colour wherever a club or player is featured.

struct Palette {
    let bg, surface, ink, muted, line, accent, onAccent, red, yellow, yellowText, draw: Color

    static let light = Palette(
        bg: Color(hex: "eef1f5"), surface: .white, ink: Color(hex: "121726"), muted: Color(hex: "5b6272"),
        line: Color(hex: "121726").opacity(0.12), accent: Color(hex: "2747d6"), onAccent: .white,
        red: Color(hex: "c8352b"), yellow: Color(hex: "e0a100"), yellowText: Color(hex: "8a6400"), draw: Color(hex: "c9cdd4")
    )
    static let dark = Palette(
        bg: Color(hex: "0f1320"), surface: Color(hex: "181d2c"), ink: Color(hex: "eef0f6"), muted: Color(hex: "9ba2b4"),
        line: Color(hex: "eef0f6").opacity(0.14), accent: Color(hex: "8ea2ff"), onAccent: Color(hex: "0f1320"),
        red: Color(hex: "e5574b"), yellow: Color(hex: "f0b92b"), yellowText: Color(hex: "f0b92b"), draw: Color(hex: "3a4152")
    )
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.light }
extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: fonts

/// Registers the bundled fonts at launch and remembers their PostScript names.
enum AppFont {
    private static var names: [String: String] = [:]

    static func registerAll() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider), let ps = font.postScriptName {
                names[url.deletingPathExtension().lastPathComponent] = ps as String
            }
        }
    }

    /// Custom fonts scale with the iPhone's text-size setting (Dynamic Type).
    private static func custom(_ file: String, _ size: CGFloat, fallback: Font.Weight) -> Font {
        let style: Font.TextStyle = size >= 40 ? .largeTitle : size >= 26 ? .title : size >= 20 ? .title3 : size >= 15 ? .body : size >= 13 ? .footnote : .caption
        if let ps = names[file] { return .custom(ps, size: size, relativeTo: style) }
        return .system(style, weight: fallback)
    }

    static func display(_ size: CGFloat) -> Font { custom("ArchivoExpanded-800", size, fallback: .heavy) }
    static func displayBlack(_ size: CGFloat) -> Font { custom("ArchivoExpanded-900", size, fallback: .black) }
    static func regular(_ size: CGFloat) -> Font { custom("DMSans_400Regular", size, fallback: .regular) }
    static func medium(_ size: CGFloat) -> Font { custom("DMSans_500Medium", size, fallback: .medium) }
    static func semibold(_ size: CGFloat) -> Font { custom("DMSans_600SemiBold", size, fallback: .semibold) }
    static func bold(_ size: CGFloat) -> Font { custom("DMSans_700Bold", size, fallback: .bold) }
    static func black(_ size: CGFloat) -> Font { custom("DMSans_800ExtraBold", size, fallback: .heavy) }
}

// MARK: club colours

/// ESPN gives each club a primary and alternate hex. From those:
/// `solid` fills header bands and bars, `on` is the text on top of it,
/// `hi` is a version that stays readable as text on the current background.
struct ClubColors {
    let solid: Color
    let on: Color
    let hi: Color

    static let cobalt = ClubColors(solid: Color(hex: "2747d6"), on: .white, hi: Color(hex: "2747d6"))
    static let navy = ClubColors(solid: Color(hex: "1d2540"), on: .white, hi: Color(hex: "2747d6"))

    init(solid: Color, on: Color, hi: Color) {
        self.solid = solid; self.on = on; self.hi = hi
    }

    init(team: Team, dark: Bool) {
        var solid = RGB(hex: team.color ?? "2747d6")
        // White kits read badly as a band: use the alternate colour, else a neutral grey.
        if solid.luminance > 0.85, let alt = team.alt { solid = RGB(hex: alt) }
        if solid.luminance > 0.85 { solid = RGB(hex: "8a92a3") }
        var hi = solid
        if dark {
            for _ in 0..<5 where hi.luminance < 0.18 { hi = hi.mixed(with: .white, 0.3) }
        } else {
            for _ in 0..<5 where hi.luminance > 0.22 { hi = hi.mixed(with: .black, 0.25) }
        }
        self.solid = solid.color
        self.on = solid.luminance > 0.5 ? Color(hex: "121726") : .white
        self.hi = hi.color
    }
}

struct RGB {
    var r, g, b: Double

    static let white = RGB(r: 1, g: 1, b: 1)
    static let black = RGB(r: 0, g: 0, b: 0)

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init(hex: String) {
        let h = hex.replacingOccurrences(of: "#", with: "").padding(toLength: 6, withPad: "0", startingAt: 0)
        let v = UInt64(h.prefix(6), radix: 16) ?? 0
        r = Double((v >> 16) & 0xff) / 255
        g = Double((v >> 8) & 0xff) / 255
        b = Double(v & 0xff) / 255
    }

    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    func mixed(with o: RGB, _ t: Double) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }

    var color: Color { Color(red: r, green: g, blue: b) }
}

extension Color {
    init(hex: String) {
        let c = RGB(hex: hex)
        self.init(red: c.r, green: c.g, blue: c.b)
    }
}
