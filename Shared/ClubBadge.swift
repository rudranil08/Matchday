import SwiftUI

/// A club shown as its own colours and a three-letter code, in place of the crest.
/// Club crests are trademarks the data licence doesn't cover, so Matchday never shows them.
/// Used in the app and the widgets.
struct ClubBadge: View {
    let team: Team?
    var size: CGFloat = 28
    /// Round (headers, pickers) or a soft square (lists).
    var circle = false

    var body: some View {
        if let team {
            let look = BadgeLook(team)
            // Small badges (list rows) get bigger letters and no inner ring, so the code stays readable.
            let small = size < 30
            let scale: CGFloat = look.code.count >= 4 ? (small ? 0.24 : 0.19) : look.code.count == 3 ? (small ? 0.31 : 0.24) : (small ? 0.38 : 0.3)
            let shape = circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            ZStack {
                shape.fill(look.fill)
                if let trim = look.trim, !small {
                    // A thin inner ring in the second club colour, like the trim on a shirt.
                    (circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)))
                        .stroke(trim, lineWidth: max(1, size * 0.05))
                        .padding(size * 0.08)
                }
                Text(look.code)
                    .font(AppFont.displayBlack(size * scale))
                    .foregroundStyle(look.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, size * (small ? 0.07 : 0.17))
            }
            .overlay { if look.needsEdge { shape.stroke(Color.black.opacity(0.12), lineWidth: 1) } }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
            Circle().fill(Color.secondary.opacity(0.2)).frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}

/// The badge's colours, worked out from the club's two colours so the code is always readable.
struct BadgeLook {
    let fill: Color
    let ink: Color
    let trim: Color?
    let needsEdge: Bool
    let code: String

    init(_ team: Team) {
        let main = RGB(hex: team.color ?? "2747d6")
        let second = team.alt.map { RGB(hex: $0) }
        fill = main.color
        // White or very pale kits need an edge, or the badge disappears on a white screen.
        needsEdge = main.luminance > 0.8
        let plain = main.luminance > 0.5 ? RGB(hex: "121726") : RGB.white
        // Use the second colour for the code when it's clearly readable, else black or white.
        let ink = second.flatMap { BadgeLook.contrast($0, main) >= 3 ? $0 : nil } ?? plain
        self.ink = ink.color
        trim = second.flatMap { BadgeLook.contrast($0, main) >= 1.6 ? $0.color.opacity(0.85) : nil }
        code = BadgeLook.code(for: team)
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// The server's code ("ARS"), else letters from the name: "Some Town United" → "STU", "Leeds" → "LEE".
    static func code(for team: Team) -> String {
        if let c = team.code, !c.isEmpty { return c.uppercased() }
        let words = team.short.folding(options: .diacriticInsensitive, locale: nil)
            .split(whereSeparator: { !$0.isLetter }).map(String.init)
        if words.count >= 2 { return String(words.prefix(3).compactMap(\.first)).uppercased() }
        return String((words.first ?? "?").prefix(3)).uppercased()
    }
}
