import SwiftUI

/// Tools for the checker (highest) account: data-feed health, accounts on this device,
/// and resets. Shows usernames only; passwords are stored as hashes and can't be shown.
struct CheckerView: View {
    @Environment(\.palette) private var t
    @Environment(AppState.self) private var app
    @Environment(AuthStore.self) private var auth

    struct Check: Identifiable {
        let id = UUID()
        let name: String
        var status: Status = .pending
        var detail = ""
        enum Status { case pending, ok, warn, fail }
    }

    @State private var checks: [Check] = []
    @State private var running = false
    @State private var cleared = false

    var body: some View {
        List {
            Section {
                ForEach(checks) { c in
                    HStack(spacing: 12) {
                        icon(c.status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(AppFont.semibold(15))
                            if !c.detail.isEmpty { Text(c.detail).mutedStyle(t) }
                        }
                    }
                }
                Button(running ? "Checking…" : "Run checks again") { Task { await run() } }.disabled(running)
            } header: {
                Text("Data feeds")
            } footer: {
                Text("Calls each live source and reports what came back.")
            }

            Section("Accounts on this iPhone") {
                ForEach(auth.accountNames(), id: \.self) { name in
                    HStack {
                        Text(name.hasPrefix("google.") ? "Google account" : name.hasPrefix("apple.") ? "Apple account" : "@\(name)")
                        Spacer()
                        if name == "1234" { Text("Checker").mutedStyle(t) }
                    }
                }
            }

            Section {
                Button("Clear saved data") {
                    Task { await DataStore.shared.clearAll(); ImageCache.shared.removeAll(); cleared = true }
                }
                Button("Show onboarding again") { app.onboarded = false; app.showSettings = false }
            } header: {
                Text("Reset")
            } footer: {
                if cleared { Text("Saved data cleared. It reloads from the network next time.") }
            }
        }
        .navigationTitle("Checker tools")
        .task { await run() }
    }

    @ViewBuilder private func icon(_ s: Check.Status) -> some View {
        switch s {
        case .pending: ProgressView()
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: "2f9e6b"))
        case .warn: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(t.yellow)
        case .fail: Image(systemName: "xmark.octagon.fill").foregroundStyle(t.red)
        }
    }

    private func run() async {
        running = true
        defer { running = false }
        checks = League.allCases.map { Check(name: "\($0.name) table") } + [Check(name: "News feed"), Check(name: "Player stats"), Check(name: "Injury list")]
        for (i, l) in League.allCases.enumerated() {
            do {
                let rows = try await DataStore.shared.table(l, force: true)
                checks[i].status = rows.isEmpty ? .warn : .ok
                checks[i].detail = rows.first.map { "\(rows.count) clubs · \($0.team.short) top on \($0.points)" } ?? "No rows"
            } catch { checks[i].status = .fail; checks[i].detail = error.localizedDescription }
        }
        let n = League.allCases.count
        do {
            let news = try await DataStore.shared.news(.pl, force: true)
            checks[n].status = news.isEmpty ? .warn : .ok
            checks[n].detail = "\(news.count) stories · latest \(news.first.map { timeAgo($0.published) } ?? "–") ago"
        } catch { checks[n].status = .fail; checks[n].detail = error.localizedDescription }
        do {
            let players = try await DataStore.shared.players(.pl, force: true)
            checks[n + 1].status = players.isEmpty ? .warn : .ok
            checks[n + 1].detail = "\(players.count) Premier League players"
        } catch { checks[n + 1].status = .fail; checks[n + 1].detail = error.localizedDescription }
        let r = await DataStore.shared.injuries(.one(.pl), force: true)
        checks[n + 2].status = r.error == nil ? .ok : .fail
        checks[n + 2].detail = r.error?.localizedDescription
            ?? "\(r.list.count) Premier League players out or doubtful · " + (MatchdayAPI.lastMode == .sample ? "sample data" : "Sportmonks")
    }
}
