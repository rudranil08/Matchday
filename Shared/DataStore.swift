import Foundation

/// Cache shared by every screen and the widgets.
/// Memory first, then a fresh saved copy on disk, then the network. Every good response is
/// saved to disk, so screens can show the last data instantly (`saved…`) while they refresh,
/// and the app still works with no signal. Old and unused saved data is pruned (`prune`).
actor DataStore {
    static let shared = DataStore()

    private var entries: [String: (at: Date, task: Task<Any, Error>)] = [:]
    /// How long data counts as fresh: no network call inside this window.
    private let ttl: TimeInterval = 5 * 60
    private(set) var offlineKeys: Set<String> = []

    private let folder: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MatchdayData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private struct Saved<T: Codable>: Codable { let at: Date; let value: T }

    private func file(_ key: String) -> URL {
        folder.appendingPathComponent(key.replacingOccurrences(of: ":", with: "_") + ".json")
    }

    private func readSaved<T: Codable>(_ key: String, as: T.Type) -> Saved<T>? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? JSONDecoder().decode(Saved<T>.self, from: data)
    }

    private func cached<T: Codable>(_ key: String, force: Bool, _ load: @escaping () async throws -> T) async throws -> T {
        if !force, let hit = entries[key], Date().timeIntervalSince(hit.at) < ttl {
            return try await hit.task.value as! T
        }
        // Reopened the app a minute after last time? The saved copy is still fresh: no network.
        if !force, entries[key] == nil, let saved = readSaved(key, as: T.self), Date().timeIntervalSince(saved.at) < ttl {
            entries[key] = (saved.at, Task<Any, Error> { saved.value })
            return saved.value
        }
        let task = Task<Any, Error> { try await load() }
        entries[key] = (Date(), task)
        dropExpired()
        do {
            let value = try await task.value as! T
            offlineKeys.remove(key)
            if let data = try? JSONEncoder().encode(Saved(at: Date(), value: value)) {
                try? data.write(to: file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            return value
        } catch {
            entries[key] = nil
            // No network (or the feed failed): fall back to the last saved copy.
            if let saved = readSaved(key, as: T.self) {
                offlineKeys.insert(key)
                return saved.value
            }
            throw error
        }
    }

    // MARK: instant start

    /// The last saved copy, without touching the network: screens show this straight away,
    /// then swap in fresh data when it arrives.
    func savedTable(_ l: League) -> [TableRow]? { readSaved("tbl:\(l.rawValue)", as: [TableRow].self)?.value }
    func savedNews(_ l: League) -> [Story]? { readSaved("feed:\(l.rawValue)", as: [Story].self)?.value }
    func savedInjuries(_ f: LeagueFilter) -> [Injury]? {
        let lists = f.leagues.compactMap { readSaved("injury:\($0.rawValue)", as: [Injury].self)?.value }
        return lists.count == f.leagues.count ? lists.flatMap { $0 } : nil
    }

    /// Form ranking from saved data only (players + table, plus injuries if saved).
    func savedRanked(_ f: LeagueFilter) -> [RankedPlayer]? {
        var players: [PlayerStat] = []
        var games: [String: Int] = [:]
        var index: [League: [String: Injury]] = [:]
        for l in f.leagues {
            guard let p = readSaved("ply:\(l.rawValue)", as: [PlayerStat].self)?.value,
                  let rows = readSaved("tbl:\(l.rawValue)", as: [TableRow].self)?.value else { return nil }
            players += p
            for row in rows { games[row.team.id] = row.played }
            if let inj = readSaved("injury:\(l.rawValue)", as: [Injury].self)?.value { index[l] = Self.injuryIndex(inj) }
        }
        return Self.rank(players, games: games, injuries: index)
    }

    /// Warm the cache for the user's leagues (launch, coming back to the app, background refresh),
    /// so every tab opens without waiting. Injuries (the heaviest feed) only for the main league.
    func prefetch(_ leagues: [League]) async {
        await withTaskGroup(of: Void.self) { group in
            for l in leagues {
                group.addTask { _ = try? await self.table(l) }
                group.addTask { _ = try? await self.news(l) }
                group.addTask { _ = try? await self.players(l) }
            }
            if let main = leagues.first { group.addTask { _ = try? await self.injuries(main) } }
        }
    }

    // MARK: offloading

    /// Forget in-memory results that have gone stale (they're on disk if needed again).
    private func dropExpired() {
        let now = Date()
        for (key, entry) in entries where now.timeIntervalSince(entry.at) > ttl * 6 { entries[key] = nil }
    }

    /// iOS is short of memory, or the app went to the background: keep only the user's leagues in memory.
    func trimMemory(keeping leagues: [League]) {
        let keep = Set(leagues.map(\.rawValue))
        for key in entries.keys where !keep.contains(String(key.split(separator: ":").last ?? "")) { entries[key] = nil }
    }

    /// Deletes saved data nobody needs: files from the old data feeds, anything older than a week,
    /// other leagues' data after a day, and the oldest files if the folder passes 20 MB.
    func prune(keeping leagues: [League]) {
        let fm = FileManager.default
        let keep = Set(leagues.map(\.rawValue))
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let now = Date()
        var survivors: [(url: URL, date: Date, size: Int)] = []
        for url in files {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let date = values?.contentModificationDate ?? .distantPast
            let age = now.timeIntervalSince(date)
            let league = url.deletingPathExtension().lastPathComponent.split(separator: "_").last.map(String.init) ?? ""
            let name = url.lastPathComponent
            let retired = ["table_", "news_", "players_", "inj_"].contains { name.hasPrefix($0) }
            if retired || age > 7 * 86_400 || (!keep.contains(league) && age > 86_400) {
                try? fm.removeItem(at: url)
            } else {
                survivors.append((url, date, values?.fileSize ?? 0))
            }
        }
        var total = survivors.reduce(0) { $0 + $1.size }
        for f in survivors.sorted(by: { $0.date < $1.date }) where total > 20 * 1024 * 1024 {
            try? fm.removeItem(at: f.url)
            total -= f.size
        }
    }

    /// Bytes saved on the iPhone: feed data plus the image and HTTP cache.
    func storageUsed() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let data = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return data + (Net.session.configuration.urlCache?.currentDiskUsage ?? 0)
    }

    /// Settings › Clear saved data. Everything reloads from the network next time.
    func clearAll() {
        entries = [:]
        offlineKeys = []
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Net.session.configuration.urlCache?.removeAllCachedResponses()
    }

    /// True when any of these leagues is currently showing saved (offline) data.
    func isOffline(_ f: LeagueFilter) -> Bool {
        f.leagues.contains { l in offlineKeys.contains { $0.hasSuffix(":\(l.rawValue)") } }
    }

    // Everything comes from Matchday's server (MatchdayAPI), which reads the licensed provider.

    func table(_ l: League, force: Bool = false) async throws -> [TableRow] {
        try await cached("tbl:\(l.rawValue)", force: force) { try await MatchdayAPI.table(l) }
    }

    /// The News feed: results, fixtures and new injuries, written from match data.
    func news(_ l: League, force: Bool = false) async throws -> [Story] {
        try await cached("feed:\(l.rawValue)", force: force) { try await MatchdayAPI.feed(l) }
    }

    func players(_ l: League, force: Bool = false) async throws -> [PlayerStat] {
        try await cached("ply:\(l.rawValue)", force: force) { try await MatchdayAPI.players(l) }
    }

    func injuries(_ l: League, force: Bool = false) async throws -> [Injury] {
        try await cached("injury:\(l.rawValue)", force: force) { try await MatchdayAPI.injuries(l) }
    }

    /// Injury list across leagues (loaded side by side), with the first error if any league failed.
    func injuries(_ f: LeagueFilter, force: Bool = false) async -> (list: [Injury], error: Error?) {
        let byLeague = await injuriesByLeague(f, force: force)
        let list = f.leagues.flatMap { byLeague.lists[$0] ?? [] }
        return (list, byLeague.error)
    }

    private func injuriesByLeague(_ f: LeagueFilter, force: Bool) async -> (lists: [League: [Injury]], error: Error?) {
        var lists: [League: [Injury]] = [:]
        var firstError: Error?
        await withTaskGroup(of: (League, Result<[Injury], Error>).self) { group in
            for l in f.leagues {
                group.addTask {
                    do { return (l, .success(try await self.injuries(l, force: force))) } catch { return (l, .failure(error)) }
                }
            }
            for await (l, result) in group {
                switch result {
                case .success(let list): lists[l] = list
                case .failure(let e): firstError = firstError ?? e
                }
            }
        }
        return (lists, firstError)
    }

    func injuryNews(_ f: LeagueFilter, force: Bool = false) async throws -> [Story] {
        var all: [Story] = []
        try await withThrowingTaskGroup(of: [Story].self) { group in
            for l in f.leagues { group.addTask { try await self.news(l, force: force) } }
            for try await chunk in group { all += chunk }
        }
        // The same story can appear in two leagues' feeds.
        var seen = Set<String>()
        return all.filter { $0.tag == .injury && seen.insert($0.id).inserted }.sorted { $0.published > $1.published }
    }

    /// Players ranked by Form Score, from live goals, assists, apps, team games and injuries.
    /// Widgets pass `withInjuries: false` to keep their refresh light.
    func ranked(_ f: LeagueFilter, force: Bool = false, withInjuries: Bool = true) async throws -> [RankedPlayer] {
        var players: [PlayerStat] = []
        var games: [String: Int] = [:]
        try await withThrowingTaskGroup(of: ([PlayerStat], [TableRow]).self) { group in
            for l in f.leagues {
                group.addTask { (try await self.players(l, force: force), try await self.table(l, force: force)) }
            }
            for try await (p, rows) in group {
                players += p
                for row in rows { games[row.team.id] = row.played }
            }
        }
        // Match injuries to players within the same league only (fewer false matches), by
        // first initial + surname. Only call players "Fit" when that league's list loaded.
        var index: [League: [String: Injury]] = [:]
        if withInjuries {
            let byLeague = await injuriesByLeague(f, force: force)
            for (l, list) in byLeague.lists { index[l] = Self.injuryIndex(list) }
        }
        return Self.rank(players, games: games, injuries: index)
    }

    /// Injuries by player id and by name ("h kane"): the id when both lists come from the same
    /// provider, the name otherwise.
    private static func injuryIndex(_ list: [Injury]) -> [String: Injury] {
        var index: [String: Injury] = [:]
        for i in list {
            index["id:\(i.playerID)"] = index["id:\(i.playerID)"] ?? i
            if let key = NameKey.of(i.name) { index[key] = index[key] ?? i }
        }
        return index
    }

    private static func rank(_ players: [PlayerStat], games: [String: Int], injuries index: [League: [String: Injury]]) -> [RankedPlayer] {
        players
            .map { p in
                let known = index[p.team.league]
                let inj = known?["id:\(p.id)"] ?? NameKey.of(p.name).flatMap { known?[$0] }
                let fitness: Fitness = inj.map { Fitness($0.status) } ?? (known != nil ? .fit : .unknown)
                return RankedPlayer(player: p, form: FormScore.compute(p, teamGames: games[p.team.id] ?? p.apps, fitness: fitness))
            }
            .sorted { ($0.form.score, $0.player.goals, $0.player.name) > ($1.form.score, $1.player.goals, $1.player.name) }
    }

    /// Every club in the four leagues (for search and the widget's club picker).
    func allTeams() async -> [Team] {
        var teams: [Team] = []
        await withTaskGroup(of: [TableRow].self) { group in
            for l in League.allCases { group.addTask { (try? await self.table(l)) ?? [] } }
            for await rows in group { teams += rows.map(\.team) }
        }
        return teams.sorted { $0.name < $1.name }
    }
}

/// Loading state for a screen.
enum Loadable<T> {
    case loading
    case loaded(T)
    case failed(String)

    var value: T? { if case .loaded(let v) = self { v } else { nil } }
    var isLoading: Bool { if case .loading = self { true } else { false } }
    var error: String? { if case .failed(let e) = self { e } else { nil } }
}
