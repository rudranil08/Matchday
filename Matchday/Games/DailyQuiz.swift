import Foundation
import CryptoKit

/// Today's quiz for one player: five questions picked for them alone (seeded by their account and
/// the day), mixing classic trivia with questions built from today's live tables and stats.
/// 100 points a right answer, plus up to 50 for answering within 20 seconds. One scored round a day.
enum DailyQuiz {
    static let questions = 5
    static let perCorrect = 100
    static let maxSpeedBonus = 50
    static let speedWindow: TimeInterval = 20
    static var maxPoints: Int { questions * (perCorrect + maxSpeedBonus) }

    /// Days count from 1 Jan 1970 (UTC), the same everywhere, so the leaderboard day is shared.
    static var today: Int { Int(Date().timeIntervalSince1970 / 86_400) }

    /// The day the leaderboard opened (19 Oct 2026). Account deletion clears every day from here.
    static let firstDay = 20_745

    /// When today's quiz ends, in the person's own time zone.
    static var resetsAt: Date { Date(timeIntervalSince1970: Double(today + 1) * 86_400) }

    static func points(correct: Bool, seconds: TimeInterval) -> Int {
        guard correct else { return 0 }
        let bonus = Double(maxSpeedBonus) * max(0, 1 - seconds / speedWindow)
        return perCorrect + Int(bonus.rounded())
    }

    // MARK: building the questions

    /// Same person, same day → same questions (they're also saved, so live data changing later
    /// in the day doesn't change them). Different people get different sets.
    static func make(for player: String, day: Int, leagues: [League]) async -> [TriviaQuestion] {
        var rng = SeededGenerator(seed: seed(player, day))
        var live: [TriviaQuestion] = []
        for l in (leagues.isEmpty ? League.allCases : leagues) {
            var table = await DataStore.shared.savedTable(l) ?? []
            if table.isEmpty { table = (try? await DataStore.shared.table(l)) ?? [] }
            let players = (try? await DataStore.shared.players(l)) ?? []
            live += liveQuestions(l, table: table, players: players, rng: &rng)
        }
        live.shuffle(using: &rng)
        let classic = trivia.shuffled(using: &rng)
        // Three live, two classic (or all classic if the feeds are down).
        let picked = Array(live.prefix(3)) + Array(classic.prefix(questions - min(3, live.count)))
        return picked.shuffled(using: &rng).map { shuffleOptions($0, rng: &rng) }
    }

    private static func seed(_ player: String, _ day: Int) -> UInt64 {
        let digest = SHA256.hash(data: Data("\(player.lowercased())|\(day)".utf8))
        return digest.prefix(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    private static func shuffleOptions(_ q: TriviaQuestion, rng: inout SeededGenerator) -> TriviaQuestion {
        let order = q.options.indices.shuffled(using: &rng)
        return TriviaQuestion(q: q.q, options: order.map { q.options[$0] }, answer: order.firstIndex(of: q.answer)!, why: q.why)
    }

    /// Questions straight from the live data. Each is only asked when its answer is clear-cut
    /// (no ties), so a right answer is always right.
    static func liveQuestions(_ l: League, table: [TableRow], players: [PlayerStat], rng: inout SeededGenerator) -> [TriviaQuestion] {
        var out: [TriviaQuestion] = []
        let name = l.name
        let the = l == .pl ? "the Premier League" : name

        if table.count >= 8 {
            let top = Array(table.prefix(4))
            if top[0].points > top[1].points {
                out.append(.init(q: "Who is top of \(the) right now?", options: top.map(\.team.name), answer: 0,
                                 why: "\(top[0].team.name) lead on \(top[0].points) points after \(top[0].played) games."))
            }
            let bottom = Array(table.suffix(4).reversed())
            if bottom[0].points < bottom[1].points {
                out.append(.init(q: "Which club is bottom of \(the)?", options: bottom.map(\.team.name), answer: 0,
                                 why: "\(bottom[0].team.name) have \(bottom[0].points) points from \(bottom[0].played) games."))
            }
            let club = table[Int.random(in: 0..<table.count, using: &rng)]
            var options = [club.points]
            for d in [-3, 2, 4, -1, 1, -2, 3].shuffled(using: &rng) where options.count < 4 {
                let v = club.points + d
                if v >= 0, !options.contains(v) { options.append(v) }
            }
            if options.count == 4 {
                out.append(.init(q: "How many points do \(club.team.name) have in \(the)?", options: options.map(String.init), answer: 0,
                                 why: "\(club.team.name) are \(ordinal(club.rank)) with \(club.points) points after \(club.played) games."))
            }
        }

        let scorers = players.sorted { $0.goals > $1.goals }
        if scorers.count >= 4, scorers[0].goals > scorers[1].goals {
            out.append(.init(q: "Who has scored the most \(name) goals this season?", options: scorers.prefix(4).map(\.name), answer: 0,
                             why: "\(scorers[0].name) has \(scorers[0].goals) league goals for \(scorers[0].team.short)."))
        }
        let assisters = players.sorted { $0.assists > $1.assists }
        if assisters.count >= 4, assisters[0].assists > assisters[1].assists {
            out.append(.init(q: "Who has the most \(name) assists this season?", options: assisters.prefix(4).map(\.name), answer: 0,
                             why: "\(assisters[0].name) has \(assisters[0].assists) assists for \(assisters[0].team.short)."))
        }
        let clubs = Set(table.map(\.team.name))
        if clubs.count >= 4, let p = players.filter({ $0.goals + $0.assists >= 2 }).randomElement(using: &rng) {
            let others = clubs.subtracting([p.team.name]).shuffled(using: &rng).prefix(3)
            out.append(.init(q: "Which club does \(p.name) play for?", options: [p.team.name] + others, answer: 0,
                             why: "\(p.name) has \(p.goals) goals and \(p.assists) assists for \(p.team.name) this season."))
        }
        if players.count >= 10 {
            let pool = players.filter { $0.goals > 0 }.shuffled(using: &rng)
            if let a = pool.first, let b = pool.dropFirst().first(where: { $0.goals != a.goals && $0.id != a.id }) {
                let winner = a.goals > b.goals ? a : b
                out.append(.init(q: "Who has more \(name) goals this season?", options: [winner.name, winner.id == a.id ? b.name : a.name], answer: 0,
                                 why: "\(a.name) has \(a.goals), \(b.name) has \(b.goals)."))
            }
        }
        return out
    }

    private static func ordinal(_ n: Int) -> String {
        let suffix = (11...13).contains(n % 100) ? "th" : ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
        return "\(n)\(suffix)"
    }
}

/// One player's round for one day, saved on the iPhone so closing the app can't replay it.
struct QuizDay: Codable, Equatable {
    var day: Int
    var questions: [TriviaQuestion]
    var picks: [Int] = []
    var points: [Int] = []
    /// How many answers the leaderboard has confirmed (nil in rounds saved before this existed).
    var posted: Int?

    var total: Int { points.reduce(0, +) }
    var correct: Int { zip(picks, questions).filter { $0 == $1.answer }.count }
    var finished: Bool { picks.count >= questions.count }

    private static func key(_ player: String) -> String { "quiz." + AppState.profileKey(player) }

    static func load(_ player: String, day: Int) -> QuizDay? {
        guard let data = UserDefaults.standard.data(forKey: key(player)),
              let saved = try? JSONDecoder().decode(QuizDay.self, from: data), saved.day == day else { return nil }
        return saved
    }

    func save(_ player: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key(player))
    }
}
