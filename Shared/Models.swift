import Foundation

enum League: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case pl, laliga, bundesliga, ligue1

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pl: "Premier League"
        case .laliga: "LaLiga"
        case .bundesliga: "Bundesliga"
        case .ligue1: "Ligue 1"
        }
    }
}

/// A single league, or all four together (Form and Injuries).
enum LeagueFilter: Hashable, Identifiable {
    case all
    case one(League)

    var id: String { leagues.map(\.rawValue).joined(separator: ",") }
    var leagues: [League] { if case .one(let l) = self { [l] } else { League.allCases } }
    var name: String { if case .one(let l) = self { l.name } else { "All leagues" } }
    static var options: [LeagueFilter] { [.all] + League.allCases.map { .one($0) } }
}

struct Team: Hashable, Codable {
    let id: String
    let name: String
    let short: String
    /// Always nil for now: the data licence doesn't cover club logos, so clubs show as badges.
    let crest: URL?
    var color: String?
    var alt: String?
    let league: League
    /// Three-letter code for the badge ("ARS").
    var code: String? = nil
    /// Earlier ids for the same club (the old ESPN id), so saved clubs carry over.
    var aliases: [String]? = nil
}

enum Zone: String, Codable { case ucl, uel, uecl, relegation, other }

struct TableRow: Identifiable, Hashable, Codable {
    var id: String { team.id }
    let team: Team
    let rank: Int
    let played: Int
    let won: Int
    let drawn: Int
    let lost: Int
    let goalDifference: String
    let points: Int
    let zone: Zone?
}

struct PlayerStat: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let team: Team
    let apps: Int
    let goals: Int
    let assists: Int
    /// "GK", "DEF", "MID" or "FWD".
    var position: String? = nil
    var minutes: Int? = nil
    /// Form v2 from the server: rated against the same position, per 90 minutes, recent games
    /// weighted. Missing in older saved data, where the app falls back to its own simpler score.
    var form: ServerForm? = nil

    var positionName: String? {
        switch position {
        case "GK": "Goalkeeper"
        case "DEF": "Defender"
        case "MID": "Midfielder"
        case "FWD": "Forward"
        default: nil
        }
    }
}

struct ServerForm: Hashable, Codable {
    struct Part: Hashable, Codable {
        let label: String
        let note: String
        let verdict: String
        /// 0–1: the share of players in the same position he's better than.
        let value: Double
    }
    /// 0–100, before the injury cut (the app applies that).
    let score: Int
    /// 0–1: how much playing time there is to judge. Low = pulled towards 50.
    let confidence: Double
    let parts: [Part]
}

enum StoryTag: String, Codable { case match = "Result", preview = "Preview", injury = "Injury", transfer = "Transfer" }

struct Story: Identifiable, Hashable, Codable {
    let id: String
    let headline: String
    let description: String
    let published: Date
    let image: URL?
    /// A link to read more, when there is one. Stories written from match data have none.
    let url: URL?
    /// Kick-off, for results and upcoming fixtures.
    var kickoff: Date? = nil
    let teamIDs: [String]
    let athletes: [String]
    let tag: StoryTag
}

enum InjuryStatus: String, Codable { case out = "Out", doubtful = "Doubtful" }

struct Injury: Identifiable, Hashable, Codable {
    var id: Int { playerID }
    let playerID: Int
    let name: String
    let team: String
    /// The club, with its colours, for the badge.
    let club: Team?
    let reason: String
    let status: InjuryStatus
    /// Expected return, in the provider's words ("Late October 2026", "Doubtful").
    let returns: String
}

func timeAgo(_ date: Date) -> String {
    let mins = max(1, Int(Date().timeIntervalSince(date) / 60))
    if mins < 60 { return "\(mins)m" }
    let hours = mins / 60
    if hours < 24 { return "\(hours)h" }
    return "\(hours / 24)d"
}
