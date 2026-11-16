import AppIntents

// Siri and the Shortcuts app: "Show the table in Matchday", "Who's in form in Matchday"…

struct ShowTableIntent: AppIntent {
    static var title: LocalizedStringResource = "Show the table"
    static var description = IntentDescription("Opens the live league table.")
    static var openAppWhenRun = true

    @Parameter(title: "League", default: .pl) var league: League

    @MainActor func perform() async throws -> some IntentResult {
        AppState.shared.league = league
        AppState.shared.tab = .table
        return .result()
    }
}

struct ShowFormIntent: AppIntent {
    static var title: LocalizedStringResource = "Who’s in form"
    static var description = IntentDescription("Opens the player Form rankings.")
    static var openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        AppState.shared.tab = .form
        return .result()
    }
}

struct ShowNewsIntent: AppIntent {
    static var title: LocalizedStringResource = "Football news"
    static var description = IntentDescription("Opens the latest news.")
    static var openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        AppState.shared.tab = .news
        return .result()
    }
}

struct PlayQuizIntent: AppIntent {
    static var title: LocalizedStringResource = "Play the quiz"
    static var description = IntentDescription("Opens the daily trivia quiz.")
    static var openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        AppState.shared.tab = .games
        return .result()
    }
}

/// Answers without opening the app: "Who's top of the Premier League in Matchday?"
struct LeagueLeaderIntent: AppIntent {
    static var title: LocalizedStringResource = "Who’s top of the league"
    static var description = IntentDescription("Says who leads the league and on how many points.")

    @Parameter(title: "League", default: .pl) var league: League

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let rows = try await DataStore.shared.table(league)
        guard let top = rows.first else { return .result(dialog: "I couldn’t load the \(league.name) table right now.") }
        let second = rows.dropFirst().first
        let gap = second.map { top.points - $0.points } ?? 0
        let lead = second.map { gap > 0 ? ", \(gap) point\(gap == 1 ? "" : "s") clear of \($0.team.short)" : ", level with \($0.team.short)" } ?? ""
        return .result(dialog: "\(top.team.name) are top of the \(league.name) on \(top.points) points after \(top.played) games\(lead).")
    }
}

struct MatchdayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LeagueLeaderIntent(), phrases: [
            "Who’s top of the league in \(.applicationName)",
            "Who’s top of the \(\.$league) in \(.applicationName)",
        ], shortTitle: "Top of the league", systemImageName: "trophy")
        AppShortcut(intent: ShowTableIntent(), phrases: [
            "Show the table in \(.applicationName)",
            "Show the \(\.$league) table in \(.applicationName)",
        ], shortTitle: "League table", systemImageName: "list.number")
        AppShortcut(intent: ShowFormIntent(), phrases: [
            "Who’s in form in \(.applicationName)",
            "Show player form in \(.applicationName)",
        ], shortTitle: "Player form", systemImageName: "chart.line.uptrend.xyaxis")
        AppShortcut(intent: ShowNewsIntent(), phrases: [
            "Show football news in \(.applicationName)",
        ], shortTitle: "News", systemImageName: "newspaper")
        AppShortcut(intent: PlayQuizIntent(), phrases: [
            "Play the \(.applicationName) quiz",
        ], shortTitle: "Quiz", systemImageName: "soccerball")
    }
}
