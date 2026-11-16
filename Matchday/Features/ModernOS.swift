import SwiftUI

// Newer-iOS touches, each falling back cleanly on older versions (the app supports iOS 17).

// MARK: iOS 26+: your club above the tab bar; on iOS 27 the bar also shrinks on scroll

struct ModernTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory { ClubAccessory() }
        } else if #available(iOS 26, *) {
            // Shrinking the bar is kept to iOS 27, where it's tested with the club strip and our lists.
            content.tabViewBottomAccessory { ClubAccessory() }
        } else {
            content
        }
    }
}

/// "Arsenal · 2nd · 19 pts": your main club's place in its table. Tap to open that table.
private struct ClubAccessory: View {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var t
    @State private var row: TableRow?

    var body: some View {
        let club = app.clubs(in: app.homeLeague).first
        Button {
            guard let club else { return }
            app.league = club.league
            app.tab = .table
        } label: {
            HStack(spacing: 10) {
                CrestView(team: club?.team, size: 24)
                if let club {
                    Text(club.short).font(AppFont.bold(14)).foregroundStyle(t.ink).lineLimit(1)
                    if let row {
                        Text("\(ordinal(row.rank)) · \(row.points) pts").font(AppFont.medium(13)).foregroundStyle(t.muted)
                            .monospacedDigit().lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text("Table").font(AppFont.semibold(13)).foregroundStyle(t.accent)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(t.accent)
            }
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(club.map { c in "\(c.name)" + (row.map { ", \(ordinal($0.rank)) on \($0.points) points" } ?? "") + ". Open the table" } ?? "Table")
        .task(id: club?.id) {
            guard let club else { row = nil; return }
            if let saved = await DataStore.shared.savedTable(club.league) { row = saved.first { $0.team.id == club.id } }
            if let fresh = try? await DataStore.shared.table(club.league) { row = fresh.first { $0.team.id == club.id } }
        }
    }

    private func ordinal(_ n: Int) -> String {
        let suffix = (11...13).contains(n % 100) ? "th" : ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
        return "\(n)\(suffix)"
    }
}

// MARK: iOS 27: swipe actions on our own rows (not just Lists)

/// Swipe a club in the Table to follow it (or unfollow a club outside your leagues).
struct FollowSwipe: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var t
    let team: Team

    func body(content: Content) -> some View {
        let following = app.isFollowed(team)
        if #available(iOS 27, *), !following || app.canUnfollow(team) {
            content.swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button { app.toggleFollow(team) } label: {
                    Label(following ? "Unfollow" : "Follow", systemImage: following ? "star.slash" : "star.fill")
                }
                .tint(following ? t.muted : t.accent)
            } onPresentationChanged: { _ in }
        } else {
            content
        }
    }
}

struct SwipeContainer: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27, *) { content.swipeActionsContainer() } else { content }
    }
}

// MARK: iOS 27: drag to reorder

/// Your leagues in Settings. On iOS 27, drag to reorder, or swipe a league to make it the main one;
/// on older iOS, press and hold it. The top league is the main one.
struct ReorderableLeagues<Row: View>: View {
    @Environment(AppState.self) private var app
    @ViewBuilder let row: (League) -> Row

    var body: some View {
        if #available(iOS 27, *) {
            VStack(spacing: 0) {
                ForEach(app.myLeagues) { league in
                    row(league).modifier(MakeMain(league: league))
                }
                .reorderable()
            }
            .reorderContainer(for: League.self) { diff in
                let target: String? = switch diff.destination.position {
                case .before(let id): id
                case .end: nil
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { app.moveLeagues(diff.sources, before: target) }
            }
            .swipeActionsContainer()
        } else {
            VStack(spacing: 0) { ForEach(app.myLeagues) { row($0).modifier(MakeMain(league: $0)) } }
        }
    }
}

/// "Make main league" for any league that isn't first: a swipe action (iOS 27) and a press-and-hold menu.
private struct MakeMain: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(\.palette) private var t
    let league: League

    func body(content: Content) -> some View {
        let isMain = app.myLeagues.first == league
        let action = {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { app.moveLeagues([league.id], before: app.myLeagues.first?.id) }
        }
        if isMain {
            content
        } else if #available(iOS 27, *) {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button(action: action) { Label("Make main", systemImage: "star.fill") }.tint(t.accent)
                } onPresentationChanged: { _ in }
                .contextMenu { Button(action: action) { Label("Make main league", systemImage: "star.fill") } }
        } else {
            content.contextMenu { Button(action: action) { Label("Make main league", systemImage: "star.fill") } }
        }
    }
}
