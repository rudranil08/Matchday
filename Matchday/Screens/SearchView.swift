import SwiftUI

/// Search players and clubs across all four leagues.
struct SearchView: View {
    @Environment(\.palette) private var t
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var players: [RankedPlayer] = []
    @State private var teams: [Team] = []
    @State private var loading = true
    @State private var openPlayer: RankedPlayer?

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matchedPlayers = q.isEmpty ? Array(players.prefix(8)) : players.filter { $0.player.name.localizedCaseInsensitiveContains(q) }.prefix(20).map { $0 }
        let matchedTeams = q.isEmpty ? [] : teams.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.short.localizedCaseInsensitiveContains(q) }

        NavigationStack {
            List {
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if !matchedTeams.isEmpty {
                    Section("Clubs") {
                        ForEach(matchedTeams, id: \.id) { team in
                            Button {
                                app.league = team.league
                                app.tab = .table
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    CrestView(team: team, size: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(team.name).font(AppFont.bold(15)).foregroundStyle(t.ink)
                                        Text(team.league.name).mutedStyle(t)
                                    }
                                    Spacer()
                                    if app.isFollowed(team) { Image(systemName: "star.fill").foregroundStyle(t.accent) }
                                }
                            }
                            .swipeActions {
                                if !app.isFollowed(team) || app.canUnfollow(team) {
                                    Button(app.isFollowed(team) ? "Unfollow" : "Follow") { app.toggleFollow(team) }.tint(t.accent)
                                }
                            }
                        }
                    }
                }
                if !matchedPlayers.isEmpty {
                    Section(q.isEmpty ? "In form right now" : "Players") {
                        ForEach(matchedPlayers) { r in
                            Button { openPlayer = r } label: {
                                HStack(spacing: 12) {
                                    CrestView(team: r.player.team, size: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.player.name).font(AppFont.bold(15)).foregroundStyle(t.ink)
                                        Text("\(r.player.team.short) · \(r.player.goals) goals · \(r.player.assists) assists").mutedStyle(t)
                                    }
                                    Spacer()
                                    Text("\(r.form.score)").font(AppFont.black(18))
                                        .foregroundStyle(ClubColors(team: r.player.team, dark: scheme == .dark).hi)
                                }
                            }
                        }
                    }
                }
                if !loading, !q.isEmpty, matchedPlayers.isEmpty, matchedTeams.isEmpty {
                    ContentUnavailableView.search(text: q)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Players or clubs")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $openPlayer) { PlayerSheet(item: $0) }
            .task {
                async let p = DataStore.shared.ranked(.all)
                async let tm = DataStore.shared.allTeams()
                players = (try? await p) ?? []
                teams = await tm
                loading = false
            }
        }
    }
}
