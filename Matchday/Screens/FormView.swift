import SwiftUI

/// Player form for the user's league, in sections (In form, with a position filter; Top scorers,
/// Top assists, Your club). Each shows three players; More expands it in place, like News.
struct FormView: View {
    enum Metric { case form, goals, assists }

    @Environment(\.palette) private var t
    @Environment(\.colorScheme) private var scheme
    @Environment(AppState.self) private var app
    @State private var data: Loadable<[RankedPlayer]> = .loading
    @State private var open: RankedPlayer?
    @State private var offline = false
    @State private var chosen: League?
    /// "In form" position filter: nil = everyone.
    @State private var position: String?

    private var league: League { chosen.flatMap { app.myLeagues.contains($0) ? $0 : nil } ?? app.homeLeague }

    var body: some View {
        let dark = scheme == .dark
        let all = data.value ?? []
        let lead = all.first
        let band = lead.map { ClubColors(team: $0.player.team, dark: dark) } ?? .cobalt
        let mine = app.clubs(in: league)
        let mineIDs = Set(mine.map(\.id))
        let fitnessKnown = lead.map { $0.form.fitness != .unknown } ?? false

        BandScreen(band: band, title: "Form", offline: offline, ignoresTopSafeArea: false, onRefresh: { await load(force: true) }) {
            LeagueMenu(band: band, options: app.myLeagues.map { ($0, $0.name) },
                       value: Binding(get: { league }, set: { chosen = $0 }))
        } feature: {
            if let lead {
                BandFeature(band: band, crest: lead.player.team, kicker: "Best form in the \(league.name)",
                            title: lead.player.name, sub: lead.player.team.name)
            }
        } content: {
            Overlap {
                if let lead {
                    HStack(spacing: 10) {
                        Button { open = lead } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(lead.form.score)").font(AppFont.displayBlack(56)).foregroundStyle(band.hi)
                                Text("Form score").mutedStyle(t)
                            }
                            .padding(14).frame(width: 132, alignment: .leading).frame(maxHeight: .infinity).card()
                        }
                        .buttonStyle(.plain)
                        HStack(spacing: 0) {
                            stat("Goals", lead.player.goals)
                            Divider().overlay(t.line)
                            stat("Assists", lead.player.assists)
                            Divider().overlay(t.line)
                            stat("Apps", lead.player.apps)
                        }
                        .frame(maxHeight: .infinity).card()
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    StateView(loading: data.isLoading, error: data.error) { Task { await load(force: true) } }
                        .frame(maxWidth: .infinity).card()
                }
            }

            if !all.isEmpty {
                let hasPositions = all.contains { $0.player.position != nil }
                if hasPositions {
                    UnderlineTabs(options: [(String?.none, "All"), ("GK", "GK"), ("DEF", "DEF"), ("MID", "MID"), ("FWD", "FWD")], value: $position) { EmptyView() }
                        .padding(.top, 8)
                        .sensoryFeedback(.selection, trigger: position)
                }
                if let position {
                    PlayerSection(title: "In form · " + (all.first { $0.player.position == position }?.player.positionName.map { $0 + "s" } ?? position),
                                  players: all.filter { $0.player.position == position }, metric: .form,
                                  empty: "No players in this position yet.", open: $open)
                        .id(position)
                } else {
                    PlayerSection(title: "In form", players: Array(all.dropFirst()), metric: .form, startRank: 2, open: $open)
                }
                PlayerSection(title: "Top scorers", players: all.sorted { ($0.player.goals, $0.form.score) > ($1.player.goals, $1.form.score) }, metric: .goals, open: $open)
                PlayerSection(title: "Top assists", players: all.sorted { ($0.player.assists, $0.form.score) > ($1.player.assists, $1.form.score) }, metric: .assists, open: $open)
                if !mine.isEmpty {
                    PlayerSection(title: mine.count == 1 ? "Your club · \(mine[0].short)" : "Your clubs · " + mine.map(\.short).joined(separator: ", "),
                                  players: all.filter { mineIDs.contains($0.player.team.id) }, metric: .form,
                                  empty: "None of your clubs’ players have played yet.", open: $open)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(all.first?.form.v2 != nil
                         ? "Each player is compared with others in his position, per 90 minutes, and his last five games count as much as the season. Playing time decides how sure a score is, not how high." + (fitnessKnown ? " An injury lowers the score until he’s back." : "")
                         : "Goals, assists and appearances, updated through the day." + (fitnessKnown ? " Injuries count towards fitness." : " Injury data is unavailable right now, so fitness isn’t counted."))
                        .mutedStyle(t)
                    if MatchdayAPI.lastMode == .sample { DataSourceNote() }
                }
                .padding(20)
            }
        }
        .task(id: league) { await load(force: false) }
        .sheet(item: $open) { PlayerSheet(item: $0) }
    }

    private func stat(_ label: String, _ v: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(v)").font(AppFont.bold(26)).foregroundStyle(t.ink)
            Text(label).mutedStyle(t)
        }
        .frame(maxWidth: .infinity)
    }

    private func load(force: Bool) async {
        let league = self.league
        if !force { data = await DataStore.shared.savedRanked(.one(league)).map { .loaded($0) } ?? .loading }
        let result: Loadable<[RankedPlayer]>
        do { result = .loaded(try await DataStore.shared.ranked(.one(league), force: force)) } catch { result = .failed(friendlyError(error)) }
        let isOffline = await DataStore.shared.isOffline(.one(league))
        guard !Task.isCancelled, league == self.league else { return }
        data = result
        offline = isOffline
    }
}

/// Three players to start; More shows up to ten.
private struct PlayerSection: View {
    @Environment(\.palette) private var t
    @Environment(\.colorScheme) private var scheme
    @Environment(AppState.self) private var app
    let title: String
    let players: [RankedPlayer]
    let metric: FormView.Metric
    var startRank = 1
    var empty: String?
    @Binding var open: RankedPlayer?
    @State private var expanded = false

    var body: some View {
        let shown = Array(players.prefix(expanded ? 10 : 3))
        // Own container: the same player can be in several sections, and repeated ids in one
        // stack make SwiftUI drop rows.
        VStack(alignment: .leading, spacing: 0) {
        SectionHead(title: title)
        if players.isEmpty, let empty {
            Text(empty).mutedStyle(t).padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        }
        ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
            row(r, rank: i + startRank)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if players.count > 3 {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(expanded ? "Show less" : "More · top 10").font(AppFont.bold(14))
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

    private func row(_ r: RankedPlayer, rank: Int) -> some View {
        let c = ClubColors(team: r.player.team, dark: scheme == .dark)
        let value = metric == .form ? r.form.score : metric == .goals ? r.player.goals : r.player.assists
        return Button { open = r } label: {
            HStack(spacing: 10) {
                Text("\(rank)").font(AppFont.semibold(14)).foregroundStyle(t.muted).frame(width: 22, alignment: .leading)
                CrestView(team: r.player.team, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(r.player.name).font(AppFont.bold(15)).foregroundStyle(t.ink).lineLimit(1)
                        if app.isFollowed(r.player.team) { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(c.hi) }
                        if r.form.fitness == .out { RefereeCard(status: .out) }
                        if r.form.fitness == .doubtful { RefereeCard(status: .doubtful) }
                    }
                    if metric == .form, let v2 = r.form.v2, let lead = v2.parts.first {
                        // What counts most for his position: "Defender · 4.2 tackles, interceptions and clearances a game".
                        Text([r.player.positionName, lead.note].compactMap { $0 }.joined(separator: " · "))
                            .font(AppFont.medium(13)).foregroundStyle(t.muted).lineLimit(1)
                    } else {
                        (Text("\(r.player.goals)").font(AppFont.bold(13)).foregroundColor(t.ink)
                         + Text(" goals · ").font(AppFont.medium(13)).foregroundColor(t.muted)
                         + Text("\(r.player.assists)").font(AppFont.bold(13)).foregroundColor(t.ink)
                         + Text(r.player.assists == 1 ? " assist" : " assists").font(AppFont.medium(13)).foregroundColor(t.muted))
                    }
                    if metric == .form { ProgressBar(value: Double(r.form.score) / 100, color: c.hi).padding(.top, 2) }
                }
                Spacer(minLength: 8)
                Text("\(value)").font(AppFont.black(20)).foregroundStyle(t.ink).frame(width: 40, alignment: .trailing)
            }
            .monospacedDigit()
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}
