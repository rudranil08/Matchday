import SwiftUI

/// Games hub: three calm cards. Today's quiz (status and one button), the leaderboard (top three
/// and your place), and the form duel. Each opens its own focused screen.
struct GamesView: View {
    @Environment(\.palette) private var t
    @Environment(AppState.self) private var app
    @Environment(AuthStore.self) private var auth
    @State private var model = QuizModel()
    @State private var playing = false

    private var player: String { auth.current?.username ?? "guest" }

    var body: some View {
        NavigationStack {
            BandScreen(band: .cobalt, title: "Games") {
                EmptyView()
            } feature: {
                feature
            } content: {
                Overlap { quizCard }
                LeaderboardCard(refresh: model.posted)
                DuelCard()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: GamesRoute.self) { route in
                switch route {
                case .leaderboard: LeaderboardView()
                }
            }
        }
        .fullScreenCover(isPresented: $playing) { QuizPlayView(model: model) }
        .task(id: player) { await model.prepare(player: player, leagues: app.myLeagues, name: auth.leaderboardName) }
    }

    // MARK: band

    private var feature: some View {
        let band = ClubColors.cobalt
        let title: String = model.quiz == nil ? "Getting your questions"
            : model.todayFinished ? "\(model.todayPoints) points"
            : model.todayAnswered > 0 ? "Question \(model.todayAnswered + 1) of \(DailyQuiz.questions)"
            : "Five questions, just for you"
        let sub = model.todayFinished
            ? "New questions \(DailyQuiz.resetsAt.formatted(.relative(presentation: .named)))"
            : "100 points a right answer, more for speed"
        return BandFeature(band: band, kicker: "Today’s quiz", title: title, sub: sub)
    }

    // MARK: today's quiz

    private var quizCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 5) {
                ForEach(0..<DailyQuiz.questions, id: \.self) { k in
                    let picks = model.quiz?.picks ?? []
                    let right = k < picks.count ? picks[k] == model.quiz?.questions[k].answer : nil
                    Capsule().frame(height: 5).foregroundStyle(right == true ? t.accent : right == false ? t.red : t.line)
                }
            }
            if model.todayFinished, let q = model.quiz {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(q.correct) of \(q.questions.count) right").font(AppFont.bold(17)).foregroundStyle(t.ink)
                    Spacer()
                    Text("\(q.total) pts").font(AppFont.bold(17)).foregroundStyle(t.accent).monospacedDigit()
                }
                Button { model.startPractice(); playing = true } label: {
                    Text("Play a bonus round").font(AppFont.bold(16)).foregroundStyle(t.accent)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(t.accent, lineWidth: 1))
                }
                .accessibilityIdentifier("quiz.start")
            } else {
                Button { model.resume(); playing = true } label: {
                    Text(model.todayAnswered > 0 ? "Continue" : "Start today’s quiz")
                        .font(AppFont.bold(17)).foregroundStyle(t.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(t.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(model.quiz == nil)
                .accessibilityIdentifier("quiz.start")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

enum GamesRoute: Hashable { case leaderboard }

// MARK: leaderboard

/// Hub card: today's top three and your place, with a link to the full board.
private struct LeaderboardCard: View {
    @Environment(\.palette) private var t
    let refresh: Int
    @State private var entries: [Leaderboard.Entry] = []
    @State private var me = ""
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        let myIndex = entries.firstIndex { $0.id == me }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TODAY’S LEADERBOARD").font(AppFont.semibold(12)).tracking(1.2).foregroundStyle(t.muted)
                Spacer()
                if !AuthStore.shared.isGuest {
                    NavigationLink("See all", value: GamesRoute.leaderboard).font(AppFont.semibold(14)).foregroundStyle(t.accent)
                }
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                if loading && entries.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(20)
                } else if let error {
                    Text(error).mutedStyle(t).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                } else if entries.isEmpty {
                    Text("No scores yet today. Be the first.").mutedStyle(t).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(entries.prefix(3).enumerated()), id: \.element.id) { i, e in
                        if i > 0 { Divider().overlay(t.line).padding(.leading, 16) }
                        LeaderboardRow(rank: i + 1, entry: e, mine: e.id == me)
                    }
                    if let myIndex, myIndex >= 3 {
                        Divider().overlay(t.line).padding(.leading, 16)
                        LeaderboardRow(rank: myIndex + 1, entry: entries[myIndex], mine: true)
                    }
                }
            }
            .card()
        }
        .padding(.horizontal, 20).padding(.top, 24)
        .task(id: refresh) { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if refresh > 0 { try? await Task.sleep(for: .milliseconds(500)) }
        do {
            let r = try await Leaderboard.shared.top(.today, day: DailyQuiz.today, limit: 5, force: refresh > 0)
            entries = r.entries
            me = r.me
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn’t load the leaderboard."
        }
    }
}

struct LeaderboardRow: View {
    @Environment(\.palette) private var t
    let rank: Int
    let entry: Leaderboard.Entry
    let mine: Bool
    /// Names this person chose to hide (on this iPhone only), by player ID.
    @AppStorage("leaderboard.hidden") private var hiddenIDs = ""
    @State private var confirmReport = false
    @State private var reported: String?

    private var isHidden: Bool { hiddenIDs.split(separator: ",").contains { $0 == entry.id } }

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)").font(AppFont.bold(15)).foregroundStyle(rank <= 3 ? t.accent : t.muted)
                .frame(width: 24, alignment: .leading).monospacedDigit()
            Text(isHidden ? "Hidden player" : entry.name).font(AppFont.semibold(16))
                .foregroundStyle(isHidden ? t.muted : t.ink).lineLimit(1)
            if mine {
                Text("You").font(AppFont.bold(11)).foregroundStyle(t.onAccent)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(t.accent, in: Capsule())
            }
            Spacer()
            Text("\(entry.points)").font(AppFont.bold(16)).foregroundStyle(t.ink).monospacedDigit()
        }
        .padding(.horizontal, 16).frame(height: 50)
        .contentShape(Rectangle())
        .contextMenu {
            if !mine {
                Button(role: .destructive) { confirmReport = true } label: { Label("Report name", systemImage: "exclamationmark.bubble") }
                Button { toggleHidden() } label: {
                    Label(isHidden ? "Show name" : "Hide name", systemImage: isHidden ? "eye" : "eye.slash")
                }
            }
        }
        .confirmationDialog("Report “\(entry.name)”?", isPresented: $confirmReport, titleVisibility: .visible) {
            Button("Report name", role: .destructive) { Task { await report() } }
        } message: {
            Text("Names that break the Terms of Use are removed. The name is also hidden for you.")
        }
        .alert(reported ?? "", isPresented: Binding(get: { reported != nil }, set: { if !$0 { reported = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank), \(isHidden ? "Hidden player" : entry.name)\(mine ? " (you)" : ""), \(entry.points) points")
        .accessibilityAction(named: "Report name") { if !mine { confirmReport = true } }
    }

    private func toggleHidden() {
        var ids = Set(hiddenIDs.split(separator: ",").map(String.init))
        if ids.contains(entry.id) { ids.remove(entry.id) } else { ids.insert(entry.id) }
        hiddenIDs = ids.sorted().joined(separator: ",")
    }

    private func report() async {
        if !isHidden { toggleHidden() }
        do {
            try await Leaderboard.shared.report(entry)
            reported = "Thanks. We’ll review this name."
        } catch {
            reported = (error as? LocalizedError)?.errorDescription ?? "Couldn’t send the report. Try again."
        }
    }
}

/// Full leaderboard: Today and All time, top 10.
struct LeaderboardView: View {
    @Environment(\.palette) private var t
    @State private var board: Leaderboard.Board = .today
    @State private var entries: [Leaderboard.Entry] = []
    @State private var me = ""
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Leaderboard", selection: $board) {
                    ForEach(Leaderboard.Board.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 0) {
                    if loading && entries.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(24)
                    } else if let error {
                        Text(error).mutedStyle(t).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    } else if entries.isEmpty {
                        Text(board == .today ? "No scores yet today. Be the first." : "No scores yet.")
                            .mutedStyle(t).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                            if i > 0 { Divider().overlay(t.line).padding(.leading, 16) }
                            LeaderboardRow(rank: i + 1, entry: e, mine: e.id == me)
                        }
                    }
                }
                .card()

                Text("Everyone gets their own five questions a day. 100 points for each right answer, and up to 50 more for answering within 20 seconds. Bonus rounds don’t count.")
                    .font(AppFont.regular(13)).foregroundStyle(t.muted).padding(.horizontal, 4)
            }
            .padding(20)
        }
        .background(t.bg)
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await load(force: true) }
        .task(id: board) { await load(force: false) }
    }

    private func load(force: Bool) async {
        loading = true
        defer { loading = false }
        do {
            let r = try await Leaderboard.shared.top(board, day: DailyQuiz.today, force: force)
            entries = r.entries
            me = r.me
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn’t load the leaderboard."
        }
    }
}

// MARK: form duel

/// "Who's in better form?", played right on the Games screen: two players face off, tap the one
/// you think has the higher live Form score. Both scores count up, the winner lights up in their
/// club's colour, and your streak updates.
struct DuelCard: View {
    @Environment(\.palette) private var t
    @Environment(\.colorScheme) private var scheme
    @Environment(AppState.self) private var app
    @State private var pool: [RankedPlayer] = []
    @State private var pair: [RankedPlayer] = []
    @State private var pick: Int?
    @State private var revealed = false
    @State private var failed = false
    @State private var streak = 0
    @State private var best = UserDefaults.standard.integer(forKey: "bestDuelStreak")
    @State private var round = 0

    private var winner: Int? {
        guard pair.count == 2 else { return nil }
        return pair[0].form.score > pair[1].form.score ? 0 : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WHO’S IN BETTER FORM?").font(AppFont.semibold(12)).tracking(1.2).foregroundStyle(t.muted)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? Color(hex: "e07b00") : t.muted)
                    Text("\(streak)").monospacedDigit().contentTransition(.numericText())
                    Text("· best \(best)").foregroundStyle(t.muted).monospacedDigit()
                }
                .font(AppFont.semibold(13)).foregroundStyle(t.ink)
                .animation(.snappy, value: streak)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 14) {
                if pair.count == 2 {
                    // VS sits between the two crests, clear of the names.
                    ZStack(alignment: .top) {
                        HStack(spacing: 10) {
                            side(0)
                            side(1)
                        }
                        Text("VS").font(AppFont.display(13)).foregroundStyle(t.ink)
                            .frame(width: 40, height: 40)
                            .background(t.surface, in: Circle())
                            .overlay(Circle().stroke(t.line, lineWidth: 1))
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                            .scaleEffect(revealed ? 0.85 : 1)
                            .opacity(revealed ? 0 : 1)
                            .padding(.top, 24)
                            .accessibilityHidden(true)
                    }
                    .id(round)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    footer
                } else {
                    Text(failed ? "Couldn’t load players right now." : "Finding two in-form players…")
                        .mutedStyle(t).frame(maxWidth: .infinity).frame(height: 180)
                }
            }
            .padding(12)
            .card()
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 8)
        .sensoryFeedback(trigger: revealed) { _, now in
            guard now, let pick, let winner else { return nil }
            return pick == winner ? .success : .error
        }
        .task { await loadPool() }
    }

    // MARK: one player

    private func side(_ k: Int) -> some View {
        let r = pair[k]
        let c = ClubColors(team: r.player.team, dark: scheme == .dark)
        let isWinner = revealed && k == winner
        let isLoser = revealed && k != winner
        return Button { choose(k) } label: {
            VStack(spacing: 10) {
                CrestView(team: r.player.team, size: 52, circle: true)
                    .overlay(Circle().stroke(t.line, lineWidth: 1))
                    .padding(.top, 18)
                VStack(spacing: 2) {
                    Text(r.player.name).font(AppFont.bold(16)).foregroundStyle(isWinner ? c.on : t.ink)
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                    Text(r.player.team.short).font(AppFont.medium(13)).foregroundStyle(isWinner ? c.on.opacity(0.85) : c.hi).lineLimit(1)
                }
                .frame(minHeight: 52, alignment: .top)
                ZStack {
                    if revealed {
                        Text("\(r.form.score)").font(AppFont.displayBlack(34)).foregroundStyle(isWinner ? c.on : t.muted)
                            .monospacedDigit().contentTransition(.numericText())
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("Tap to pick").font(AppFont.semibold(13)).foregroundStyle(t.muted)
                    }
                }
                .frame(height: 44)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isWinner ? c.solid : t.bg)
                    .overlay(alignment: .top) {
                        // Club colour across the top until the reveal.
                        if !revealed { c.solid.frame(height: 5) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(pick == k ? (k == winner || !revealed ? t.ink : t.red) : .clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if revealed && pick == k {
                    Image(systemName: k == winner ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(k == winner ? c.on : t.red)
                        .background(Circle().fill(k == winner ? c.solid : t.surface))
                        .padding(8).transition(.scale.combined(with: .opacity))
                }
            }
            .opacity(isLoser ? 0.6 : 1)
            .scaleEffect(pick == k && !revealed ? 0.97 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(pick == nil)
        .accessibilityIdentifier("duel.\(k)")
        .accessibilityLabel(revealed ? "\(r.player.name), Form \(r.form.score)" : "Pick \(r.player.name), \(r.player.team.short)")
    }

    // MARK: result line and next

    @ViewBuilder private var footer: some View {
        if revealed, let pick, let winner {
            let w = pair[winner], l = pair[1 - winner]
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pick == winner ? (streak > 1 ? "Right · \(streak) in a row" : "Right") : "Not this time")
                        .font(AppFont.bold(16)).foregroundStyle(pick == winner ? t.ink : t.red)
                    Text("\(w.player.name) \(w.form.score) · \(l.player.name) \(l.form.score)")
                        .font(AppFont.regular(13)).foregroundStyle(t.muted).lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer()
                Button { next() } label: {
                    HStack(spacing: 6) {
                        Text("Next pair")
                        Image(systemName: "arrow.right")
                    }
                    .font(AppFont.bold(15)).foregroundStyle(t.onAccent)
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(t.accent, in: Capsule())
                }
                .accessibilityIdentifier("duel.next")
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            Text("Higher live Form score wins. Players are rated against their own position, and recent games count most.")
                .font(AppFont.regular(13)).foregroundStyle(t.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: logic

    private func choose(_ k: Int) {
        guard pick == nil, let winner else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { pick = k }
        let right = k == winner
        // A short beat before the reveal makes the moment land.
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                revealed = true
                streak = right ? streak + 1 : 0
                best = max(best, streak)
            }
            UserDefaults.standard.set(best, forKey: "bestDuelStreak")
        }
    }

    private func next() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            pick = nil
            revealed = false
            round += 1
            shuffle()
        }
    }

    /// Players from your leagues with a real Form score; saved data first so it's instant.
    private func loadPool() async {
        guard pool.isEmpty else { return }
        var players: [RankedPlayer] = []
        for l in app.myLeagues {
            if let saved = await DataStore.shared.savedRanked(.one(l)) { players += saved.prefix(25) }
        }
        if players.count < 2 {
            for l in app.myLeagues { players += ((try? await DataStore.shared.ranked(.one(l))) ?? []).prefix(25) }
        }
        pool = players.filter { $0.form.score > 0 }
        failed = pool.count < 2
        shuffle()
    }

    /// Two players with different scores (no ties), from different clubs when possible.
    private func shuffle() {
        guard pool.count >= 2 else { pair = []; return }
        for _ in 0..<20 {
            let two = Array(pool.shuffled().prefix(2))
            if two[0].form.score != two[1].form.score, two[0].player.team.id != two[1].player.team.id { pair = two; return }
        }
        if let a = pool.randomElement(), let b = pool.first(where: { $0.form.score != a.form.score }) { pair = [a, b] }
    }
}
