import Foundation

/// Blocks offensive and impersonating usernames and leaderboard names. Catches simple disguises
/// (capitals, dots, underscores, and numbers for letters like 4 → a, 0 → o). A first line of
/// defence: reports and the ban list in Firestore handle what gets through.
enum NameFilter {
    /// Word stems that aren't allowed anywhere in a name.
    private static let blocked = [
        "fuck", "shit", "cunt", "bitch", "bastard", "dick", "cock", "pussy", "wank", "twat", "slut", "whore",
        "nigg", "nigga", "fag", "retard", "spastic", "kike", "chink", "paki", "tranny",
        "nazi", "hitler", "rape", "porn", "sex", "penis", "vagina", "anal", "cum",
    ]
    /// Names that pretend to be the app or its staff.
    private static let impersonation = ["admin", "moderator", "matchday", "official", "support", "staff"]

    static func isAllowed(_ name: String) -> Bool {
        let n = normalized(name)
        guard !n.isEmpty else { return false }
        if impersonation.contains(where: { n.contains($0) }) { return false }
        return !blocked.contains { n.contains($0) }
    }

    private static func normalized(_ s: String) -> String {
        let map: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "@": "a", "$": "s", "!": "i"]
        return String(s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .compactMap { c -> Character? in
                if let m = map[c] { return m }
                return c.isLetter ? c : nil
            })
    }
}
