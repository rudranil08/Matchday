import SwiftUI

struct InjuriesView: View {
    enum Filter: String, CaseIterable { case all = "All", out = "Out", doubtful = "Doubtful" }

    @Environment(\.palette) private var t
    @Environment(AppState.self) private var app
    @State private var league: LeagueFilter = .all
    @State private var filter: Filter = .all
    @State private var injuries: Loadable<[Injury]> = .loading
    @State private var news: Loadable<[Story]> = .loading
    @State private var offline = false
    @State private var picked = false
    @State private var open: Story?

    var body: some View {
        // A list across many clubs: the band stays a neutral navy here.
        let band = ClubColors.navy
        let all = injuries.value ?? []
        let list = all.filter { filter == .all || $0.status.rawValue == filter.rawValue }
        let followed = Set(app.clubs.map(\.id))
        let mine = all.filter { i in i.club.map { followed.contains($0.id) } ?? false }
        let mineIDs = Set(mine.map(\.id))
        let top = mine.first { $0.status == .out } ?? all.first { $0.status == .out } ?? all.first

        BandScreen(band: band, title: "Injuries", offline: offline, onRefresh: { await load(force: true) }) {
            LeagueMenu(band: band, options: LeagueFilter.options.map { ($0, $0.name) }, value: $league)
        } feature: {
            if let top {
                BandFeature(band: band, crest: top.club, kicker: mineIDs.contains(top.id) ? "Biggest absence for your clubs" : "Out right now",
                            title: top.name, sub: "\(top.team) · \(top.returns)")
            }
        } content: {
            Overlap {
                if injuries.value != nil {
                    HStack(spacing: 0) {
                        stat(all.filter { $0.status == .out }.count, "Out", t.red)
                        Divider().overlay(t.line)
                        stat(all.filter { $0.status == .doubtful }.count, "Doubtful", t.yellowText)
                        if !mine.isEmpty {
                            Divider().overlay(t.line)
                            stat(mine.count, "Your clubs", t.ink)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true).card()
                } else {
                    StateView(loading: injuries.isLoading, error: injuries.error) { Task { await load(force: true) } }
                        .frame(maxWidth: .infinity).card()
                }
            }

            if injuries.value != nil {
                UnderlineTabs(options: Filter.allCases.map { ($0, $0.rawValue) }, value: $filter) { EmptyView() }
                if list.isEmpty { StateView(empty: "Nobody on the list.") }
                // Your club's players first.
                ForEach(list.sorted { (mineIDs.contains($0.id) ? 0 : 1) < (mineIDs.contains($1.id) ? 0 : 1) }) { i in
                    HStack(spacing: 12) {
                        CrestView(team: i.club, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(i.name).font(AppFont.bold(15)).foregroundStyle(t.ink).lineLimit(1).minimumScaleFactor(0.85)
                                if mineIDs.contains(i.id) { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(t.accent).accessibilityLabel("Your club") }
                            }
                            Text(i.team).mutedStyle(t)
                        }
                        Spacer()
                        Text(i.returns).font(AppFont.medium(13)).foregroundStyle(i.status == .out ? t.muted : t.yellowText)
                            .multilineTextAlignment(.trailing).lineLimit(2)
                        RefereeCard(status: i.status)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
                    .padding(.horizontal, 20)
                    .accessibilityElement(children: .combine)
                }
                DataSourceNote().padding(20)
            }

            SectionHead(title: "New this week")
            StateView(loading: news.isLoading, error: news.error,
                      empty: news.value?.isEmpty == true ? "No new injuries this week." : nil) { Task { await load(force: true) } }
            ForEach((news.value ?? []).prefix(8)) { s in
                Button { open = s } label: {
                    HStack(spacing: 12) {
                        RefereeCard(status: .out)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.headline).font(AppFont.semibold(15)).foregroundStyle(t.ink).lineLimit(2).multilineTextAlignment(.leading)
                            Text("\(timeAgo(s.published)) ago" + (s.athletes.first.map { " · \($0)" } ?? "")).mutedStyle(t)
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
        .sheet(item: $open) { StorySheet(story: $0) }
        .task(id: league) {
            // Start on the user's league; changing `league` re-runs this task.
            if !picked { picked = true; if league != .one(app.homeLeague) { league = .one(app.homeLeague); return } }
            await load(force: false)
        }
    }

    private func stat(_ n: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(AppFont.bold(26)).foregroundStyle(color).monospacedDigit()
            Text(label).mutedStyle(t)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load(force: Bool) async {
        let league = self.league
        if !force {
            injuries = await DataStore.shared.savedInjuries(league).map { .loaded($0) } ?? .loading
            if news.value == nil { news = .loading }
        }
        async let n = DataStore.shared.injuryNews(league, force: force)
        let result = await DataStore.shared.injuries(league, force: force)
        let list: Loadable<[Injury]> = result.error.map { .failed(friendlyError($0)) } ?? .loaded(result.list)
        let stories: Loadable<[Story]>
        do { stories = .loaded(try await n) } catch { stories = .failed(friendlyError(error)) }
        let isOffline = await DataStore.shared.isOffline(league)
        guard !Task.isCancelled, league == self.league else { return }
        injuries = list
        news = stories
        offline = isOffline
    }
}
