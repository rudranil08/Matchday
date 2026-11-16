import Foundation

/// Form Score (0–100).
/// v2 (from the server): rated against the same position, per 90 minutes, with the last five games
/// counting as much as the season; playing time decides how sure the score is, not how high.
/// The app applies the injury cut on top. Older saved data without a v2 score falls back to the
/// original formula: goals + assists per game (70%) and availability (30%).
enum Fitness: Equatable {
    case fit, doubtful, out, unknown

    init(_ status: InjuryStatus) { self = status == .out ? .out : .doubtful }

    var factor: Double {
        switch self {
        case .fit, .unknown: 1
        case .doubtful: 0.75
        case .out: 0.4
        }
    }
}

struct Form: Hashable {
    let score: Int
    let gaPerGame: Double
    let output: Double
    let availability: Double
    let teamGames: Int
    let fitness: Fitness
    /// The server's v2 breakdown, when there is one.
    var v2: ServerForm? = nil
}

struct RankedPlayer: Identifiable, Hashable {
    var id: String { player.id }
    let player: PlayerStat
    let form: Form
}

enum FormScore {
    static func compute(_ p: PlayerStat, teamGames: Int, fitness: Fitness) -> Form {
        let games = max(teamGames, p.apps, 1)
        if let v2 = p.form {
            let gaPerGame = p.apps > 0 ? Double(p.goals + p.assists) / Double(p.apps) : 0
            let score = Int((Double(v2.score) * fitness.factor).rounded())
            return Form(score: score, gaPerGame: gaPerGame, output: Double(v2.score) / 100, availability: v2.confidence,
                        teamGames: games, fitness: fitness, v2: v2)
        }
        let ga = Double(p.goals + p.assists)
        let gaPerGame = p.apps > 0 ? ga / Double(p.apps) : 0
        // Small samples: count at least half the team's games, so one good cameo can't top the list.
        let fairGames = max(Double(p.apps), Double(games) / 2, 1)
        let output = min(ga / fairGames / 2.0, 1)
        let availability = min(Double(p.apps) / Double(games), 1)
        let score = Int((100 * (0.7 * output + 0.3 * availability) * fitness.factor).rounded())
        return Form(score: score, gaPerGame: gaPerGame, output: output, availability: availability, teamGames: games, fitness: fitness)
    }

    struct Reason: Identifiable {
        var id: String { label }
        let label: String
        let note: String
        let verdict: String
        let value: Double
        let muted: Bool
    }

    /// Plain-language reasons for the player sheet: no maths shown.
    static func reasons(_ p: PlayerStat, _ f: Form) -> [Reason] {
        if let v2 = f.v2 {
            let parts = v2.parts.map { Reason(label: $0.label, note: $0.note, verdict: $0.verdict, value: $0.value, muted: false) }
            let minutes = p.minutes ?? 0
            let judged = v2.confidence >= 0.7 ? "Plenty to judge" : v2.confidence >= 0.45 ? "Enough to judge" : "Early days"
            let time = Reason(label: "Playing time", note: "\(minutes) minutes in \(p.apps) games · decides how sure the score is",
                              verdict: judged, value: v2.confidence, muted: false)
            return parts + [time, fitnessReason(f)]
        }
        let ga = f.gaPerGame
        let outputNote: String
        if ga >= 0.95 {
            outputNote = "About \(String(format: "%.1f", ga).replacingOccurrences(of: ".0", with: "")) goals or assists a game"
        } else if ga > 0 {
            outputNote = "A goal or assist every \(max(1, Int((1 / ga).rounded()))) games"
        } else {
            outputNote = "No goals or assists yet"
        }
        let outputVerdict = f.output >= 0.6 ? "Elite" : f.output >= 0.4 ? "Strong" : f.output >= 0.2 ? "Decent" : "Quiet"
        let timeVerdict = f.availability >= 1 ? "Every game" : f.availability >= 0.75 ? "Regular" : f.availability >= 0.5 ? "Rotation" : "Bit part"

        return [
            Reason(label: "Scoring and creating", note: outputNote, verdict: outputVerdict, value: f.output, muted: false),
            Reason(label: "Playing time", note: "Played \(p.apps) of \(f.teamGames) games", verdict: timeVerdict, value: f.availability, muted: false),
            fitnessReason(f),
        ]
    }

    private static func fitnessReason(_ f: Form) -> Reason {
        let fitNote: String, fitVerdict: String
        switch f.fitness {
        case .unknown: fitNote = "Injury data not connected"; fitVerdict = "Not checked"
        case .fit: fitNote = "No injury listed"; fitVerdict = "Fully fit"
        case .doubtful: fitNote = "A doubt for the next game · score × 0.75"; fitVerdict = "Doubtful"
        case .out: fitNote = "Out injured · score × 0.4 until he’s back"; fitVerdict = "Out"
        }
        return Reason(label: "Fitness", note: fitNote, verdict: fitVerdict, value: f.fitness.factor == 1 ? 1 : f.fitness.factor, muted: f.fitness == .unknown)
    }
}
