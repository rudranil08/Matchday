import Foundation

/// Matchday's own data server, which reads the licensed provider (Sportmonks) and caches it.
/// Replies are already in the app's shapes. No provider key is ever on the iPhone.
enum MatchdayAPI {
    /// "live" (licensed data) or "sample" (the server has no provider key yet).
    enum Mode: String, Codable { case live, sample }

    private struct Envelope<T: Decodable>: Decodable {
        let mode: Mode
        let data: T
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return d
    }()

    private static func get<T: Decodable>(_ league: League, _ kind: String, as: T.Type) async throws -> T {
        let url = ServerConfig.baseURL.appendingPathComponent("v1/\(league.rawValue)/\(kind)")
        let body = try decoder.decode(Envelope<T>.self, from: try await Net.data(url))
        lastMode = body.mode
        return body.data
    }

    /// The mode of the last reply, remembered so screens can say when they're showing sample data.
    static var lastMode: Mode {
        get { Mode(rawValue: UserDefaults.standard.string(forKey: "server.mode") ?? "") ?? .live }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "server.mode") }
    }

    static func table(_ l: League) async throws -> [TableRow] { try await get(l, "table", as: [TableRow].self) }
    static func players(_ l: League) async throws -> [PlayerStat] { try await get(l, "players", as: [PlayerStat].self) }
    static func injuries(_ l: League) async throws -> [Injury] { try await get(l, "injuries", as: [Injury].self) }
    static func feed(_ l: League) async throws -> [Story] { try await get(l, "feed", as: [Story].self) }
}

/// Loose name match between lists ("H. Kane" vs "Harry Kane").
enum NameKey {
    /// "harry kane" → "h kane": first initial and surname, without accents or punctuation.
    static func of(_ s: String) -> String? {
        let parts = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.letters.union(.whitespaces).inverted).joined()
            .split(separator: " ").map(String.init)
        guard let last = parts.last, let first = parts.first?.first else { return nil }
        return "\(first) \(last)"
    }
}
