import SwiftUI

// MARK: step 1: leagues (at least two)

/// Pick your leagues: at least `AppState.minLeagues`. News and Form switch between them.
struct LeagueSelectView: View {
    @Binding var selected: [League]
    var editing = false
    var onContinue: () -> Void
    @State private var leaders: [League: [Team]] = [:]

    private var needed: Int { max(0, AppState.minLeagues - selected.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(editing ? "YOUR LEAGUES" : "STEP 1 OF 2").font(AppFont.semibold(12)).tracking(1.4).opacity(0.7)
                Text("PICK YOUR LEAGUES").font(AppFont.display(28))
                Text("Choose at least \(AppState.minLeagues). News and Form switch between them, and you can check any table.")
                    .font(AppFont.regular(15)).opacity(0.85).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.top, 16)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(League.allCases) { league in
                        let on = selected.contains(league)
                        Button { toggle(league) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(on ? Palette.light.accent : Palette.light.line)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(league.name.uppercased()).font(AppFont.display(18)).foregroundStyle(Color(hex: "121726")).lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                                    Text(country(league)).font(AppFont.medium(13)).foregroundStyle(Palette.light.muted)
                                }
                                Spacer()
                                HStack(spacing: -8) {
                                    ForEach(leaders[league] ?? [], id: \.id) { team in
                                        CrestView(team: team, size: 34, circle: true)
                                            .overlay(Circle().stroke(Palette.light.line, lineWidth: 1))
                                    }
                                }
                            }
                            .padding(18)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? Palette.light.accent : .clear, lineWidth: 3))
                            .scaleEffect(on ? 1 : 0.98)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(league.name), \(country(league))")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(20)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
            }
            .sensoryFeedback(.selection, trigger: selected)

            Button(action: onContinue) {
                Text(needed > 0 ? "Pick \(needed) more league\(needed == 1 ? "" : "s")" : "Continue with \(selected.count) leagues")
                    .font(AppFont.bold(17))
                    .foregroundStyle(Color(hex: "121726").opacity(needed > 0 ? 0.5 : 1))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(.white.opacity(needed > 0 ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(needed > 0)
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .task {
            await withTaskGroup(of: (League, [Team]).self) { group in
                for l in League.allCases {
                    group.addTask { (l, ((try? await DataStore.shared.table(l)) ?? []).prefix(3).map(\.team)) }
                }
                for await (l, teams) in group { leaders[l] = teams }
            }
        }
    }

    private func toggle(_ l: League) {
        if let i = selected.firstIndex(of: l) { selected.remove(at: i) } else { selected.append(l) }
    }

    private func country(_ l: League) -> String {
        switch l {
        case .pl: "England · 20 clubs"
        case .laliga: "Spain · 20 clubs"
        case .bundesliga: "Germany · 18 clubs"
        case .ligue1: "France · 18 clubs"
        }
    }
}

// MARK: step 2: clubs (one in each chosen league)

/// Pick your clubs: one tab per chosen league, exactly one club in each.
/// The screen takes the colour of the club you last picked; Continue sweeps it into the app.
struct ClubSelectView: View {
    let leagues: [League]
    var editing = false
    var onBack: () -> Void
    var onDone: () -> Void
    @Environment(AppState.self) private var app
    @State private var teams: [League: [Team]] = [:]
    @State private var selected: [Team] = []
    @State private var tab: League?
    @State private var lastPicked: Team?
    @State private var failed = false
    @State private var revealing = false
    @State private var showWelcome = false

    private let need = AppState.clubsPerLeague

    private func count(_ l: League) -> Int { selected.filter { $0.league == l }.count }
    private var incomplete: [League] { leagues.filter { count($0) < need } }

    var body: some View {
        let colors = lastPicked.map { ClubColors(team: $0, dark: false) }
        let bandColor = colors?.solid ?? Color(hex: "0f1320")
        let onBand = colors?.on ?? .white
        let current = tab ?? leagues.first ?? .pl
        let clubs = teams[current] ?? []
        let firstMissing = incomplete.first

        ZStack {
            bandColor.opacity(lastPicked == nil ? 0 : 0.92).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Button(action: onBack) {
                    Label("Change leagues", systemImage: "chevron.left").font(AppFont.semibold(15)).foregroundStyle(onBand)
                }
                .padding(.horizontal, 20).padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text(editing ? "YOUR CLUBS" : "STEP 2 OF 2").font(AppFont.semibold(12)).tracking(1.4).opacity(0.7)
                    Text("PICK YOUR CLUBS").font(AppFont.display(28))
                    Text("Choose one club in each league. Their stories come first and they’re highlighted everywhere.")
                        .font(AppFont.regular(15)).opacity(0.85).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(onBand)
                .padding(.horizontal, 20).padding(.top, 12)

                // One tab per chosen league, with its progress.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(leagues) { l in
                            let n = count(l), on = l == current, done = n >= need
                            Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = l } } label: {
                                HStack(spacing: 6) {
                                    Text(l.name).font(AppFont.bold(14))
                                    if done, let club = selected.first(where: { $0.league == l }) {
                                        CrestView(team: club, size: 18)
                                        Image(systemName: "checkmark.circle.fill").font(.system(size: 13, weight: .bold))
                                    } else {
                                        Text("Pick 1").font(AppFont.bold(12))
                                    }
                                }
                                .foregroundStyle(on ? (colors == nil ? Color(hex: "121726") : bandColor) : onBand)
                                .padding(.horizontal, 12).frame(height: 36)
                                .background(on ? AnyShapeStyle(.white) : AnyShapeStyle(onBand.opacity(0.14)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .accessibilityLabel(done ? "\(l.name), club picked" : "\(l.name), pick a club")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 16)

                ScrollView {
                    if clubs.isEmpty {
                        VStack(spacing: 12) {
                            if failed {
                                Text("Couldn’t load the clubs.").font(AppFont.medium(15)).foregroundStyle(onBand)
                                Button("Try again") { Task { await load() } }.font(AppFont.bold(15)).foregroundStyle(onBand)
                            } else {
                                ProgressView().tint(onBand)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(clubs, id: \.id) { team in
                                ClubTile(team: team, selected: selected.contains { $0.id == team.id }) { toggle(team) }
                            }
                        }
                        .padding(20)
                        .id(current)
                        .transition(.opacity)
                    }
                }
                .sensoryFeedback(.selection, trigger: selected.count)

                Button(action: finish) {
                    Text(firstMissing.map { "Pick a club in \($0.name)" } ?? (editing ? "Save" : "Continue with \(selected.count) clubs"))
                        .font(AppFont.bold(17))
                        .foregroundStyle(firstMissing != nil ? Color(hex: "121726").opacity(0.5) : (colors == nil ? Color(hex: "121726") : bandColor))
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(.white.opacity(firstMissing != nil ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(firstMissing != nil)
                .padding(.horizontal, 20).padding(.bottom, 16)
            }

            // The colour sweep into the app.
            if !editing, let first = selected.first {
                let c = ClubColors(team: first, dark: false)
                GeometryReader { geo in
                    let d = hypot(geo.size.width, geo.size.height) * 2.2
                    Circle().fill(c.solid)
                        .frame(width: d, height: d)
                        .scaleEffect(revealing ? 1 : 0.001, anchor: .center)
                        .position(x: geo.size.width / 2, y: geo.size.height - 40)
                }
                .ignoresSafeArea()
                .allowsHitTesting(revealing)

                if showWelcome {
                    VStack(spacing: 16) {
                        HStack(spacing: -12) {
                            ForEach(selected.prefix(6), id: \.id) { CrestView(team: $0, size: 64, circle: true) }
                        }
                        Text("WELCOME TO MATCHDAY").font(AppFont.semibold(13)).tracking(1.6).opacity(0.85)
                        Text("\(selected.count) CLUBS · \(leagues.count) LEAGUES").font(AppFont.display(24))
                    }
                    .foregroundStyle(c.on)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: lastPicked?.id)
        .sensoryFeedback(.success, trigger: showWelcome)
        .task { await load() }
    }

    /// One club per league: tapping another club in the same league swaps it.
    private func toggle(_ team: Team) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            if let i = selected.firstIndex(where: { $0.id == team.id }) {
                selected.remove(at: i)
                lastPicked = selected.last
            } else {
                selected.removeAll { $0.league == team.league }
                selected.append(team)
                lastPicked = team
            }
        }
        // That league is done: move on to the next one still needing clubs.
        if count(team.league) == need, let next = incomplete.first, next != team.league {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = next }
            }
        }
    }

    private func finish() {
        guard incomplete.isEmpty else { return }
        app.setChoices(leagues: leagues, clubs: selected)
        if editing { onDone(); return }
        withAnimation(.easeIn(duration: 0.55)) { revealing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showWelcome = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { onDone() }
    }

    private func load() async {
        failed = false
        if tab == nil { tab = leagues.first }
        var loaded: [League: [Team]] = [:]
        await withTaskGroup(of: (League, [Team]).self) { group in
            for l in leagues { group.addTask { (l, ((try? await DataStore.shared.table(l)) ?? []).map(\.team).sorted { $0.short < $1.short }) } }
            for await (l, t) in group { loaded[l] = t }
        }
        teams = loaded
        failed = loaded.values.allSatisfy(\.isEmpty)
        // Keep clubs already chosen (Settings, or coming back from step 1).
        if selected.isEmpty {
            let ids = Set(app.clubs.map(\.id))
            // At most one per league, keeping the first one found.
            for l in leagues {
                if let t = (loaded[l] ?? []).first(where: { ids.contains($0.id) }) { selected.append(t) }
            }
            lastPicked = selected.last
        }
    }
}

private struct ClubTile: View {
    let team: Team
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let c = ClubColors(team: team, dark: false)
        Button(action: action) {
            VStack(spacing: 8) {
                CrestView(team: team, size: 46)
                Text(team.short).font(AppFont.semibold(13)).lineLimit(2).multilineTextAlignment(.center)
                    .foregroundStyle(selected ? c.on : Color(hex: "121726"))
                    .frame(height: 34, alignment: .top)
            }
            .frame(maxWidth: .infinity).padding(.top, 14).padding(.bottom, 8).padding(.horizontal, 6)
            .background(selected ? c.solid : .white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? .white : .clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, c.solid).padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(selected ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(team.name)\(selected ? ", selected" : "")")
    }
}

// MARK: Settings editor (same rules as onboarding)

/// Change leagues and clubs later, with the same minimums.
struct LeaguesAndClubsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var leagues: [League] = []
    @State private var onClubs = false

    var body: some View {
        ZStack {
            Color(hex: "0f1320").ignoresSafeArea()
            if onClubs {
                ClubSelectView(leagues: leagues, editing: true, onBack: { onClubs = false }) { dismiss() }
                    .transition(.move(edge: .trailing))
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button("Cancel") { dismiss() }.font(AppFont.semibold(16)).foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.top, 16)
                    LeagueSelectView(selected: $leagues, editing: true) { withAnimation { onClubs = true } }
                }
                .transition(.move(edge: .leading))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { if leagues.isEmpty { leagues = app.myLeagues } }
    }
}
