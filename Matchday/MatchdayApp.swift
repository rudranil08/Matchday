import SwiftUI
import CryptoKit
import BackgroundTasks

@main
struct MatchdayApp: App {
    init() { AppFont.registerAll() }

    var body: some Scene {
        WindowGroup { RootView() }
            // iOS wakes the app now and then to refresh your leagues, so it opens on fresh data.
            .backgroundTask(.appRefresh(Refresh.id)) {
                Refresh.schedule()
                let leagues = await AppState.shared.myLeagues
                await DataStore.shared.prefetch(leagues)
                await DataStore.shared.prune(keeping: leagues)
            }
    }
}

/// Background refresh (BGAppRefreshTask). The id is listed in Info.plist.
enum Refresh {
    static let id = "com.matchday.app.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = Date().addingTimeInterval(45 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

enum AppTab: String, CaseIterable { case news, table, form, injuries, games }

/// A club the user follows: remembered on this device only.
struct FollowedClub: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let short: String
    let league: League
    let crest: URL?
    let color: String?
    let alt: String?
    /// Badge code ("ARS"). Missing for clubs saved before badges replaced crests.
    var code: String? = nil

    init(_ t: Team) {
        id = t.id; name = t.name; short = t.short; league = t.league; crest = t.crest; color = t.color; alt = t.alt; code = t.code
    }

    var team: Team { Team(id: id, name: name, short: short, crest: crest, color: color, alt: alt, league: league, code: code) }
}

/// App-wide state: tab, Table league, sheets, and the user's leagues and clubs.
/// A shared instance so Siri / Shortcuts intents and deep links can drive it.
@MainActor @Observable final class AppState {
    static let shared = AppState()

    /// Onboarding rules: at least 2 leagues, and exactly one club in each of them.
    static let minLeagues = 2
    static let clubsPerLeague = 1

    var tab: AppTab = .news
    /// League shown in the Table (any league).
    var league: League = .pl
    var showSearch = false
    var showSettings = false
    var onboarded = UserDefaults.standard.bool(forKey: "onboarded") {
        didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded"); saveProfile() }
    }

    /// The user's leagues, in the order they picked them. News and Form switch between these.
    var myLeagues: [League] = [] {
        didSet { UserDefaults.standard.set(myLeagues.map(\.rawValue), forKey: "myLeagues"); saveProfile() }
    }

    /// The user's clubs: one per chosen league (plus any extra clubs followed from other leagues).
    var clubs: [FollowedClub] = [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(clubs), forKey: "myClubs"); saveProfile() }
    }

    /// First chosen league: the default for News, Form and Injuries.
    var homeLeague: League { myLeagues.first ?? .pl }

    /// First chosen club: its colour leads the onboarding sweep.
    var primaryClub: FollowedClub? { clubs.first }

    func clubs(in league: League) -> [FollowedClub] { clubs.filter { $0.league == league } }

    /// True once there are enough leagues, each with enough clubs.
    var isSetupComplete: Bool {
        myLeagues.count >= Self.minLeagues && myLeagues.allSatisfy { clubs(in: $0).count == Self.clubsPerLeague }
    }

    /// Save the onboarding (or Settings) choices together.
    func setChoices(leagues: [League], clubs chosen: [Team]) {
        myLeagues = leagues
        clubs = chosen.filter { leagues.contains($0.league) }.map(FollowedClub.init)
        league = leagues.first ?? league
    }

    func finishOnboarding() { onboarded = true }

    /// Brings saved clubs up to date with the data server: carries clubs saved under an old id
    /// (from before the switch to licensed data) over to the new one, and refreshes names,
    /// colours and badge codes. Clubs it can't find are left as they are.
    func reconcileClubs() async {
        let saved = clubs
        guard !saved.isEmpty else { return }
        var teams: [Team] = []
        for league in Set(saved.map(\.league)) {
            teams += (try? await DataStore.shared.table(league))?.map(\.team) ?? []
        }
        // Someone changed their clubs while this was loading: leave their new choice alone.
        guard !teams.isEmpty, clubs == saved else { return }
        let updated = saved.map { club -> FollowedClub in
            let same = teams.filter { $0.league == club.league }
            let match = same.first { $0.id == club.id }
                ?? same.first { ($0.aliases ?? []).contains(club.id) }
                ?? same.first { $0.name.caseInsensitiveCompare(club.name) == .orderedSame }
            return match.map(FollowedClub.init) ?? club
        }
        if updated != saved { clubs = updated }
    }

    /// Settings › drag to reorder (iOS 27). The first league becomes the main one, and clubs follow
    /// the same order so the main club's colour leads.
    func moveLeagues(_ ids: [String], before target: String?) {
        var list = myLeagues
        let moving = list.filter { ids.contains($0.id) }
        list.removeAll { ids.contains($0.id) }
        if let target, let i = list.firstIndex(where: { $0.id == target }) { list.insert(contentsOf: moving, at: i) } else { list += moving }
        guard list != myLeagues else { return }
        myLeagues = list
        clubs.sort { (list.firstIndex(of: $0.league) ?? 99) < (list.firstIndex(of: $1.league) ?? 99) }
    }

    /// After an account is deleted: forget everything this app saved on the iPhone.
    func eraseLocalData() {
        clubs = []
        myLeagues = []
        onboarded = false
        showSettings = false
        tab = .news
        let d = UserDefaults.standard
        for key in ["myLeagues", "myClubs", "followedClub", "homeLeague", "bestDuelStreak", "auth.failures", "auth.lockedUntil"] {
            d.removeObject(forKey: key)
        }
        d.set(false, forKey: "onboarded")
        Task { await DataStore.shared.clearAll() }
        ImageCache.shared.removeAll()
    }

    // MARK: per-account choices

    /// One account's leagues and clubs, saved on this iPhone so signing back in goes straight home.
    struct Profile: Codable {
        var leagues: [League]
        var clubs: [FollowedClub]
        var onboarded: Bool
    }

    /// Whose choices are on screen. Edits are saved to this account's profile.
    private var activeUser: String?
    private var switching = false

    /// Key for an account's profile. The username is hashed so it isn't stored in plain text.
    nonisolated static func profileKey(_ username: String) -> String {
        let digest = SHA256.hash(data: Data(username.lowercased().utf8))
        return "profile." + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private func saveProfile() {
        guard !switching, let user = activeUser else { return }
        let p = Profile(leagues: myLeagues, clubs: clubs, onboarded: onboarded)
        UserDefaults.standard.set(try? JSONEncoder().encode(p), forKey: Self.profileKey(user))
    }

    /// Called whenever someone signs in or out. Brings back that account's leagues and clubs;
    /// a brand-new account starts with none and goes through league and club selection.
    private func accountChanged(_ account: Account?) {
        let d = UserDefaults.standard
        guard let account else {
            // Signed out: put this account's choices away so the next person starts clean.
            activeUser = nil
            switching = true
            myLeagues = []; clubs = []; onboarded = false
            switching = false
            return
        }
        activeUser = account.username
        switching = true
        defer { switching = false; saveProfile() }
        if let data = d.data(forKey: Self.profileKey(account.username)),
           let p = try? JSONDecoder().decode(Profile.self, from: data) {
            myLeagues = p.leagues
            clubs = p.clubs
            onboarded = p.onboarded
        } else if !d.bool(forKey: "profiles.migrated") {
            // Choices made before accounts kept their own: they belong to the first account that signs in.
        } else {
            myLeagues = []; clubs = []; onboarded = false
        }
        d.set(true, forKey: "profiles.migrated")
        if onboarded && !isSetupComplete { onboarded = false }
        league = homeLeague
        Task { await reconcileClubs() }
    }

    /// Sign out. Your leagues and clubs are saved with your account, so signing back in goes straight home.
    func signOut() {
        AuthStore.shared.signOut()
        showSettings = false
        tab = .news
    }

    /// Developer setting (checker account only): every cold launch makes the checker a brand-new user.
    var newUserMode = UserDefaults.standard.bool(forKey: "dev.newUserMode") {
        didSet { UserDefaults.standard.set(newUserMode, forKey: "dev.newUserMode") }
    }

    private init() {
        let d = UserDefaults.standard
        if newUserMode {
            // Developer setting for the checker account only. Other accounts on this iPhone are never
            // touched: they stay signed in and keep their leagues and clubs.
            d.removeObject(forKey: Self.profileKey(AuthStore.checkerUsername))
            if AuthStore.shared.isChecker {
                // Fresh start: signed out, no leagues or clubs, full onboarding.
                AuthStore.shared.signOut()
                for key in ["myLeagues", "myClubs", "followedClub", "homeLeague"] { d.removeObject(forKey: key) }
                d.set(false, forKey: "onboarded")
                onboarded = false
            }
        }
        myLeagues = (d.stringArray(forKey: "myLeagues") ?? []).compactMap(League.init(rawValue:))
        clubs = d.data(forKey: "myClubs").flatMap { try? JSONDecoder().decode([FollowedClub].self, from: $0) } ?? []
        // Older single-club setups: carry the club over.
        if clubs.isEmpty, let data = d.data(forKey: "followedClub"), let old = try? JSONDecoder().decode(FollowedClub.self, from: data) {
            clubs = [old]
            myLeagues = [old.league]
            d.removeObject(forKey: "followedClub")
        }
        // Not enough leagues or clubs (e.g. an older setup)? Finish choosing next time.
        if onboarded && !isSetupComplete { onboarded = false }
        league = homeLeague
        Task { await reconcileClubs() }
        let auth = AuthStore.shared
        auth.onAccountChange = { [weak self] in self?.accountChanged($0) }
        if let user = auth.current { accountChanged(user) }
        #if DEBUG
        // Screenshot / UI-test hook: -uiTestTab form opens that tab. Not in Release builds.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-uiTestTab"), i + 1 < args.count, let tab = AppTab(rawValue: args[i + 1]) { self.tab = tab }
        if args.contains("-uiTestSettings") { showSettings = true }
        // -uiTestNoSession: start signed out. -uiTestGuest: start as the under-13 guest.
        if args.contains("-uiTestNoSession") { AuthStore.shared.signOut() }
        // -uiTestAge adult|child|unknown: set the age-gate answer for a test run.
        if let i = args.firstIndex(of: "-uiTestAge"), i + 1 < args.count {
            AgeGate.status = AgeGate.Status(rawValue: args[i + 1])
        }
        if args.contains("-uiTestGuest") { AuthStore.shared.signInAsGuest() }
        // -uiTestFreshInstall: start with no saved data at all (worst case for the chaos test).
        if args.contains("-uiTestFreshInstall") {
            let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MatchdayData")
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            Net.session.configuration.urlCache?.removeAllCachedResponses()
        }
        // -uiTestClubs: Arsenal + Barcelona, set up and onboarded, for screenshots.
        if args.contains("-uiTestClubs") {
            // The ids are the sample server's; real ids are carried over by `reconcileClubs`.
            func club(_ id: String, _ name: String, _ code: String, _ color: String, _ alt: String, _ l: League) -> Team {
                Team(id: id, name: name, short: name, crest: nil, color: color, alt: alt, league: l, code: code)
            }
            setChoices(leagues: [.pl, .laliga], clubs: [club("359", "Arsenal", "ARS", "e20520", "003399", .pl),
                                                        club("83", "Barcelona", "BAR", "990000", "FCE38A", .laliga)])
            onboarded = true
        }
        #endif
    }

    func isFollowed(_ team: Team) -> Bool { clubs.contains { $0.id == team.id } }

    /// Your league's club can be swapped but not removed (each league keeps one club).
    func canUnfollow(_ team: Team) -> Bool { !myLeagues.contains(team.league) }

    /// Follow or unfollow from anywhere (Table, Search, a player). One club per league:
    /// following a club swaps out the one you had in that league.
    func toggleFollow(_ team: Team) {
        if isFollowed(team) {
            guard canUnfollow(team) else { return }
            clubs.removeAll { $0.id == team.id }
        } else {
            clubs.removeAll { $0.league == team.league }
            clubs.append(FollowedClub(team))
        }
    }

    /// matchday://table?league=pl, matchday://form, matchday://news, …
    func open(_ url: URL) {
        guard url.scheme == "matchday" else { return }
        if let host = url.host, let tab = AppTab(rawValue: host) { self.tab = tab }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let raw = items.first(where: { $0.name == "league" })?.value, let l = League(rawValue: raw) { league = l }
        showSearch = false
        showSettings = false
    }
}

struct RootView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase
    @State private var app = AppState.shared
    @State private var auth = AuthStore.shared

    /// Signed in from before the age question existed: ask once (the checker test account is exempt).
    private var needsAge: Bool {
        _ = ageAnswered   // re-checked once the question is answered
        return auth.isSignedIn && AgeGate.status == nil && !auth.isChecker && !auth.isGuest
    }
    @State private var ageAnswered = 0

    var body: some View {
        let palette = scheme == .dark ? Palette.dark : Palette.light
        ZStack {
            if !auth.isSignedIn || !app.onboarded {
                OnboardingView(step: auth.isSignedIn ? .league : Self.firstStep)
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                tabs(palette)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.55), value: auth.isSignedIn && app.onboarded)
        .fullScreenCover(isPresented: .constant(needsAge)) {
            ZStack {
                PitchBackground()
                AgeStep(onDone: { status in
                    // Under 13: no account features from now on; carry on as a guest on this iPhone.
                    if status == .child { app.signOut(); auth.signInAsGuest() }
                    ageAnswered += 1
                }, onBack: nil)
            }
            .preferredColorScheme(.dark)
        }
        .onOpenURL { app.open($0) }
        .task { await auth.refreshEmailSession() }
        // Fetch your leagues ahead of time and tidy saved data, each time the app comes forward.
        // Going to the background: let go of memory and book the next background refresh.
        .task(id: phase) {
            switch phase {
            case .active:
                // Signed in with Apple but revoked in Settings › Apple ID? Sign out.
                await auth.checkAppleCredential()
                let leagues = app.myLeagues
                await DataStore.shared.prefetch(leagues)
                await DataStore.shared.prune(keeping: leagues)
                // Fresh tables in hand: keep saved clubs matched if the server's ids changed.
                await app.reconcileClubs()
            case .background:
                await DataStore.shared.trimMemory(keeping: app.myLeagues)
                Refresh.schedule()
            default: break
            }
        }
        // Just picked (or changed) leagues: get them ready before the user opens a tab.
        .onChange(of: app.myLeagues) { _, leagues in Task(priority: .utility) { await DataStore.shared.prefetch(leagues) } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            ImageCache.shared.removeAll()
            Task { await DataStore.shared.trimMemory(keeping: app.myLeagues) }
        }
        // Hide what's on screen (e.g. a typed password) in the app switcher.
        .overlay { if phase != .active { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea() } }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .environment(app)
        .environment(auth)
        .environment(\.palette, palette)
    }

    private static var firstStep: OnboardingView.Step {
        #if DEBUG
        // Screenshot hook: -uiTestSignIn opens the sign-in form. Not in Release builds.
        if ProcessInfo.processInfo.arguments.contains("-uiTestSignIn") { return .signIn }
        #endif
        return .welcome
    }

    @ViewBuilder private func tabs(_ palette: Palette) -> some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            NewsView().tabItem { Label("News", systemImage: "newspaper") }.tag(AppTab.news)
            TableScreen().tabItem { Label("Table", systemImage: "list.number") }.tag(AppTab.table)
            FormView().tabItem { Label("Form", systemImage: "chart.line.uptrend.xyaxis") }.tag(AppTab.form)
            InjuriesView().tabItem { Label("Injuries", systemImage: "cross.case") }.tag(AppTab.injuries)
            GamesView().tabItem { Label("Games", systemImage: "soccerball") }.tag(AppTab.games)
        }
        .tint(palette.accent)
        .sensoryFeedback(.selection, trigger: app.tab)
        .sensoryFeedback(.selection, trigger: app.league)
        .sheet(isPresented: $app.showSearch) { SearchView() }
        .sheet(isPresented: $app.showSettings) { SettingsView() }
        .modifier(ModernTabBar())
    }
}
