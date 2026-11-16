import AppIntents

// App Intents types shared by the widgets (configuration) and the app (Siri / Shortcuts).

extension League: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "League" }
    static var caseDisplayRepresentations: [League: DisplayRepresentation] {
        [.pl: "Premier League", .laliga: "LaLiga", .bundesliga: "Bundesliga", .ligue1: "Ligue 1"]
    }
}

/// League choice that also allows "All leagues" (Form widget).
enum LeagueOption: String, AppEnum {
    case all, pl, laliga, bundesliga, ligue1

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Leagues" }
    static var caseDisplayRepresentations: [LeagueOption: DisplayRepresentation] {
        [.all: "All leagues", .pl: "Premier League", .laliga: "LaLiga", .bundesliga: "Bundesliga", .ligue1: "Ligue 1"]
    }

    var filter: LeagueFilter { League(rawValue: rawValue).map { .one($0) } ?? .all }
}

/// A club, picked from the live tables (widget highlight).
struct ClubEntity: AppEntity, Hashable {
    let id: String
    let name: String
    let league: League

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Club" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(league.name)") }
    static var defaultQuery = ClubQuery()
}

struct ClubQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ClubEntity] {
        await all().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [ClubEntity] {
        await all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
    func suggestedEntities() async throws -> [ClubEntity] { await all() }

    private func all() async -> [ClubEntity] {
        await DataStore.shared.allTeams().map { ClubEntity(id: $0.id, name: $0.name, league: $0.league) }
    }
}

/// Deep links shared by widgets and the app: matchday://table?league=pl
enum DeepLink {
    static func url(tab: String, league: League? = nil) -> URL {
        var c = URLComponents()
        c.scheme = "matchday"
        c.host = tab
        if let league { c.queryItems = [URLQueryItem(name: "league", value: league.rawValue)] }
        return c.url!
    }
}
