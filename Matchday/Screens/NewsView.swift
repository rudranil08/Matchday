import SwiftUI

/// News for the user's league, written from match data: results, the next fixtures and new
/// injuries, split into sections (Your club, Results, Coming up, Injuries). Each shows three
/// stories; More expands it in place.
struct NewsView: View {
    @Environment(\.palette) private var t
    @Environment(\.colorScheme) private var scheme
    @Environment(AppState.self) private var app
    @State private var news: Loadable<[Story]> = .loading
    @State private var table: [TableRow] = []
    @State private var open: Story?
    @State private var offline = false
    /// Which of the user's leagues is showing (defaults to their first).
    @State private var chosen: League?
    /// Apple Intelligence availability, checked when News opens, never during layout: on some systems
    /// it flips while the model gets ready, and asking on every redraw caused a layout loop.
    @State private var briefingAvailable = false
    @Environment(\.scenePhase) private var phase

    private var league: League { chosen.flatMap { app.myLeagues.contains($0) ? $0 : nil } ?? app.homeLeague }

    var body: some View {
        let dark = scheme == .dark
        let teams = Dictionary(table.map { ($0.team.id, $0.team) }, uniquingKeysWith: { a, _ in a })
        let stories = news.value ?? []
        let teamOf: (Story) -> Team? = { s in s.teamIDs.lazy.compactMap { teams[$0] }.first }
        let mine = app.clubs(in: league)
        let mineIDs = Set(mine.map(\.id))
        let mineStories = stories.filter { !mineIDs.isDisjoint(with: $0.teamIDs) }
        // Top story: the newest about your club, else the newest with a club attached.
        let lead = mineStories.first ?? stories.first { teamOf($0) != nil } ?? stories.first
        let leadTeam = lead.flatMap(teamOf)
        // The band wears your club's colour, so it carries on from the onboarding sweep.
        let band = mine.first.map { ClubColors(team: $0.team, dark: dark) } ?? leadTeam.map { ClubColors(team: $0, dark: dark) } ?? .cobalt
        let rest = stories.filter { $0.id != lead?.id }

        BandScreen(band: band, title: "News", offline: offline, onRefresh: { await load(force: true) }) {
            LeagueMenu(band: band, options: app.myLeagues.map { ($0, $0.name) },
                       value: Binding(get: { league }, set: { chosen = $0 }))
        } feature: {
            if let lead {
                BandFeature(band: band, crest: leadTeam,
                            kicker: (mineStories.first == lead ? "Your club · " : "Top story · ") + lead.kicker,
                            title: lead.headline)
            }
        } content: {
            Overlap {
                if let lead {
                    VStack(alignment: .leading, spacing: 12) {
                        if !lead.description.isEmpty {
                            Text(lead.description).font(AppFont.regular(16)).foregroundStyle(t.ink).lineLimit(3)
                        }
                        Button { open = lead } label: {
                            Text(lead.tag == .preview ? "Match details" : "More").font(AppFont.bold(15)).foregroundStyle(band.on)
                                .padding(.horizontal, 16).frame(height: 40)
                                .background(band.solid, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .accessibilityIdentifier("leadStory")
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
                } else {
                    StateView(loading: news.isLoading, error: news.error, empty: "No stories right now.") { Task { await load(force: true) } }
                        .frame(maxWidth: .infinity).card()
                }
            }

            // iOS 26+: three-point summary of your club's news, written on the iPhone.
            if briefingAvailable, let club = mine.first, !mineStories.isEmpty {
                BriefingCard(club: club.short, stories: mineStories, color: ClubColors(team: club.team, dark: dark).hi)
            }

            if news.value != nil {
                if !mine.isEmpty {
                    NewsSection(title: mine.count == 1 ? "Your club · \(mine[0].short)" : "Your clubs · " + mine.map(\.short).joined(separator: ", "),
                                stories: rest.filter { !mineIDs.isDisjoint(with: $0.teamIDs) },
                                empty: "No new stories about your clubs right now.", teamOf: teamOf, open: $open)
                }
                NewsSection(title: "Results", stories: rest.filter { $0.tag == .match }, empty: "No results in the last week.", teamOf: teamOf, open: $open)
                NewsSection(title: "Coming up", stories: rest.filter { $0.tag == .preview }.sorted { ($0.kickoff ?? .distantFuture) < ($1.kickoff ?? .distantFuture) },
                            empty: "No fixtures in the next week.", teamOf: teamOf, open: $open)
                NewsSection(title: "Injuries", stories: rest.filter { $0.tag == .injury }, empty: "No new injuries this week.", teamOf: teamOf, open: $open)
                DataSourceNote().padding(.horizontal, 20).padding(.top, 8)
            }

            if !table.isEmpty {
                SectionHead(title: "Top of the table") {
                    Button("Full table") { app.league = league; app.tab = .table }.font(AppFont.semibold(12)).foregroundStyle(t.accent)
                }
                let top = Array(table.prefix(3))
                let extra = table.filter { mineIDs.contains($0.team.id) && $0.rank > 3 }
                ForEach(top + extra) { r in
                    let isMine = mineIDs.contains(r.team.id)
                    HStack(spacing: 10) {
                        Text("\(r.rank)").font(AppFont.bold(15)).foregroundStyle(t.muted).frame(width: 22, alignment: .leading)
                        CrestView(team: r.team, size: 24)
                        Text(r.team.short).font(AppFont.semibold(15)).foregroundStyle(t.ink)
                        if isMine { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(ClubColors(team: r.team, dark: dark).hi) }
                        Spacer()
                        Text("\(r.points) pts").font(AppFont.bold(16)).foregroundStyle(ClubColors(team: r.team, dark: dark).hi)
                    }
                    .monospacedDigit()
                    .frame(height: 40)
                    .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
                    .padding(.horizontal, 20)
                }
            }
        }
        .task(id: league) { await load(force: false) }
        .task(id: phase) { if phase == .active { briefingAvailable = Briefing.isAvailable } }
        .sheet(item: $open) { StorySheet(story: $0) }
    }

    private func load(force: Bool) async {
        let league = self.league
        // New league (or first open): show the saved copy at once, then refresh.
        // Pull to refresh keeps what's on screen until the new data lands.
        if !force {
            if let saved = await DataStore.shared.savedNews(league) {
                news = .loaded(saved)
                table = await DataStore.shared.savedTable(league) ?? []
            } else {
                news = .loading
            }
        }
        async let n = DataStore.shared.news(league, force: force)
        async let tb = DataStore.shared.table(league, force: force)
        let result: Loadable<[Story]>
        do { result = .loaded(try await n) } catch { result = .failed(friendlyError(error)) }
        let rows = (try? await tb) ?? []
        let isOffline = await DataStore.shared.isOffline(.one(league))
        // Switched league while this was loading? Its results belong to the old league.
        guard !Task.isCancelled, league == self.league else { return }
        news = result
        table = rows
        offline = isOffline
    }
}

/// A titled group of stories: three to start, More expands it in place.
private struct NewsSection: View {
    @Environment(\.palette) private var t
    @Environment(\.colorScheme) private var scheme
    let title: String
    let stories: [Story]
    var empty: String?
    let teamOf: (Story) -> Team?
    @Binding var open: Story?
    @State private var expanded = false

    var body: some View {
        if !stories.isEmpty || empty != nil {
            // Own container: a story can be in two sections, and repeated ids in one stack drop rows.
            VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: title)
            if stories.isEmpty, let empty {
                Text(empty).mutedStyle(t).padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(expanded ? stories : Array(stories.prefix(3))) { s in
                StoryRow(story: s, team: teamOf(s)) { open = s }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if stories.count > 3 {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(expanded ? "Show less" : "More · \(stories.count - 3)").font(AppFont.bold(14))
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .foregroundStyle(t.accent)
                    .frame(maxWidth: .infinity).frame(height: 44)
                }
                .sensoryFeedback(.selection, trigger: expanded)
                .padding(.horizontal, 20)
            }
            }
        }
    }
}

private struct StoryRow: View {
    @Environment(\.palette) private var t
    @Environment(\.colorScheme) private var scheme
    let story: Story
    let team: Team?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let team { CrestView(team: team, size: 34) } else { Circle().fill(t.line).frame(width: 34, height: 34) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if story.tag == .injury { RefereeCard(status: .out) }
                        Label2(text: story.kicker)
                    }
                    Text(story.headline).font(AppFont.semibold(15)).foregroundStyle(t.ink).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

struct StorySheet: View {
    @Environment(\.palette) private var t
    @Environment(\.openURL) private var openURL
    let story: Story

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label2(text: story.kicker)
                Text(story.headline.uppercased()).font(AppFont.display(22)).foregroundStyle(t.ink)
                if let kickoff = story.kickoff, story.tag == .preview {
                    Label(kickoff.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()), systemImage: "calendar")
                        .font(AppFont.semibold(15)).foregroundStyle(t.muted)
                }
                if let image = story.image {
                    Color.clear
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay { RemoteImage(url: image, mode: .fill) { t.line } }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text(story.description).font(AppFont.regular(16)).foregroundStyle(t.ink)
                if let url = story.url {
                    Button { openURL(url) } label: {
                        Text("Read more").font(AppFont.bold(16)).foregroundStyle(t.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(t.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                ShareLink(item: "\(story.headline). \(story.description)", subject: Text(story.headline)) {
                    Label("Share", systemImage: "square.and.arrow.up").font(AppFont.bold(16)).foregroundStyle(t.accent)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.accent, lineWidth: 1))
                }
                DataSourceNote()
            }
            .padding(20)
        }
        .background(t.bg)
        .presentationDetents([.large])
    }
}

extension Story {
    /// "Result · 2h ago", "Preview · Sat 15:00", "Injury · 1d ago".
    var kicker: String {
        if tag == .preview, let kickoff {
            return "\(tag.rawValue) · " + kickoff.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return "\(tag.rawValue) · \(timeAgo(published)) ago"
    }
}

/// Where the data comes from, and a clear note while the server is on sample data.
struct DataSourceNote: View {
    @Environment(\.palette) private var t
    var body: some View {
        if MatchdayAPI.lastMode == .sample {
            Label("Sample data: the data server has no provider key yet.", systemImage: "flask")
                .font(AppFont.semibold(13)).foregroundStyle(t.yellowText)
        } else {
            Text("Written from licensed match data. Results, fixtures and injuries update through the day.").mutedStyle(t)
        }
    }
}
