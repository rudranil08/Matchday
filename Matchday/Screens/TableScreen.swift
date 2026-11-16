import SwiftUI

struct TableScreen: View {
    @Environment(\.palette) private var t
    @Environment(\.colorScheme) private var scheme
    @Environment(AppState.self) private var app
    @State private var table: Loadable<[TableRow]> = .loading
    @State private var offline = false

    var body: some View {
        @Bindable var app = app
        let dark = scheme == .dark
        let rows = table.value ?? []
        let leader = rows.first
        let band = leader.map { ClubColors(team: $0.team, dark: dark) } ?? .cobalt

        BandScreen(band: band, title: "Table", offline: offline, onRefresh: { await load(force: true) }) {
            LeagueMenu(band: band, options: League.allCases.map { ($0, $0.name) }, value: $app.league)
        } feature: {
            if let leader {
                BandFeature(band: band, crest: leader.team, kicker: "Top of \(app.league.name) · after \(leader.played) games",
                            title: leader.team.name, sub: "Goal difference \(leader.goalDifference)")
            }
        } content: {
            Overlap {
                if let leader {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(leader.points)").font(AppFont.displayBlack(50)).foregroundStyle(band.hi)
                            Text("Points").mutedStyle(t)
                        }
                        .padding(14).frame(width: 120, alignment: .leading).card()
                        HStack(spacing: 0) {
                            stat("Won", leader.won)
                            Divider().overlay(t.line)
                            stat("Drawn", leader.drawn)
                            Divider().overlay(t.line)
                            stat("Lost", leader.lost)
                        }
                        .frame(maxHeight: .infinity).card()
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    StateView(loading: table.isLoading, error: table.error) { Task { await load(force: true) } }
                        .frame(maxWidth: .infinity).card()
                }
            }

            if !rows.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Label2(text: "#").frame(width: 30, alignment: .leading)
                        Label2(text: "Club")
                        Spacer()
                        ForEach(["P", "GD", "Pts"], id: \.self) { Label2(text: $0).frame(width: 38, alignment: .trailing) }
                    }
                    .padding(.bottom, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(t.ink).frame(height: 1) }

                    ForEach(rows) { r in
                        let mine = app.isFollowed(r.team)
                        HStack(spacing: 0) {
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 2).fill(zoneColor(r.zone)).frame(width: 3, height: 18)
                                Text("\(r.rank)").font(AppFont.bold(14)).foregroundStyle(t.muted)
                            }
                            .frame(width: 30, alignment: .leading)
                            HStack(spacing: 10) {
                                CrestView(team: r.team, size: 22)
                                Text(r.team.short).font(AppFont.semibold(15)).foregroundStyle(t.ink).lineLimit(1)
                                if mine { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(ClubColors(team: r.team, dark: dark).hi).accessibilityLabel("Your club") }
                            }
                            Spacer()
                            Text("\(r.played)").font(AppFont.medium(14)).foregroundStyle(t.muted).frame(width: 38, alignment: .trailing)
                            Text(r.goalDifference).font(AppFont.medium(14)).foregroundStyle(t.muted).frame(width: 38, alignment: .trailing)
                            Text("\(r.points)").font(AppFont.bold(16)).foregroundStyle(mine ? ClubColors(team: r.team, dark: dark).hi : t.ink).frame(width: 38, alignment: .trailing)
                        }
                        .monospacedDigit()
                        .frame(height: 40)
                        .padding(.horizontal, mine ? 8 : 0)
                        .background(mine ? ClubColors(team: r.team, dark: dark).solid.opacity(0.12) : .clear)
                        .padding(.horizontal, mine ? -8 : 0)
                        .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
                        .contentShape(Rectangle())
                        .modifier(FollowSwipe(team: r.team))
                        .contextMenu {
                            Button { app.toggleFollow(r.team) } label: {
                                Label(mine ? "Unfollow \(r.team.short)" : "Follow \(r.team.short)", systemImage: mine ? "star.slash" : "star")
                            }
                            .disabled(mine && !app.canUnfollow(r.team))
                            if mine && !app.canUnfollow(r.team) {
                                Text("Your \(r.team.league.name) club. Follow another club here to swap.")
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(r.rank), \(r.team.name), \(r.points) points, played \(r.played)\(mine ? ", your club" : "")")
                    }

                    HStack(spacing: 14) {
                        ForEach(zonesPresent(rows), id: \.1) { zone, label in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(zoneColor(zone)).frame(width: 3, height: 12)
                                Text(label).mutedStyle(t)
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, 12)
                    Text("Live standings. Pull down to refresh. Swipe or press and hold a club to follow it.").mutedStyle(t)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    if MatchdayAPI.lastMode == .sample {
                        DataSourceNote().frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                }
                .sensoryFeedback(.success, trigger: app.clubs)
                .modifier(SwipeContainer())
                .padding(.horizontal, 20).padding(.top, 18)
            }
        }
        .task(id: app.league) { await load(force: false) }
    }

    private func stat(_ label: String, _ v: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(v)").font(AppFont.bold(26)).foregroundStyle(t.ink)
            Text(label).mutedStyle(t)
        }
        .frame(maxWidth: .infinity)
    }

    private func zoneColor(_ z: Zone?) -> Color {
        switch z {
        case .ucl: t.accent
        case .uel: Color(hex: "e07b00")
        case .uecl: Color(hex: "2f9e6b")
        case .relegation: t.red
        case .other: t.muted
        case nil: .clear
        }
    }

    private func zonesPresent(_ rows: [TableRow]) -> [(Zone, String)] {
        let all: [(Zone, String)] = [(.ucl, "Champions League"), (.uel, "Europa League"), (.uecl, "Conference League"), (.relegation, "Relegation")]
        return all.filter { z in rows.contains { $0.zone == z.0 } }
    }

    private func load(force: Bool) async {
        let league = app.league
        if !force { table = await DataStore.shared.savedTable(league).map { .loaded($0) } ?? .loading }
        let result: Loadable<[TableRow]>
        do { result = .loaded(try await DataStore.shared.table(league, force: force)) } catch { result = .failed(friendlyError(error)) }
        let isOffline = await DataStore.shared.isOffline(.one(league))
        guard !Task.isCancelled, league == app.league else { return }
        table = result
        offline = isOffline
    }
}
