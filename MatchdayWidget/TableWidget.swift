import WidgetKit
import SwiftUI
import AppIntents

struct TableWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "League table"
    static var description = IntentDescription("The live table, with your club highlighted.")

    @Parameter(title: "League", default: .pl) var league: League
    @Parameter(title: "Highlight club") var club: ClubEntity?
}

struct TableEntry: TimelineEntry {
    struct Row: Identifiable {
        var id: String { teamID }
        let teamID: String
        let rank: Int
        let name: String
        let short: String
        let points: Int
        let played: Int
        let team: Team
    }

    let date: Date
    let league: League
    let rows: [Row]
    let highlightID: String?
    var failed = false

    static func placeholder(_ league: League) -> TableEntry {
        let names = ["Club One", "Club Two", "Club Three", "Club Four", "Club Five", "Club Six", "Club Seven", "Club Eight", "Club Nine", "Club Ten"]
        let rows = names.enumerated().map { i, n in
            Row(teamID: "\(i)", rank: i + 1, name: n, short: n, points: 21 - i * 2, played: 8,
                team: Team(id: "\(i)", name: n, short: n, crest: nil, color: "2747d6", alt: nil, league: league))
        }
        return TableEntry(date: .now, league: league, rows: rows, highlightID: nil)
    }
}

struct TableProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TableEntry { .placeholder(.pl) }

    func snapshot(for configuration: TableWidgetIntent, in context: Context) async -> TableEntry {
        context.isPreview ? .placeholder(configuration.league) : await entry(for: configuration, rows: 10)
    }

    func timeline(for configuration: TableWidgetIntent, in context: Context) async -> Timeline<TableEntry> {
        let count = context.family == .systemLarge ? 10 : 5
        let e = await entry(for: configuration, rows: count)
        return Timeline(entries: [e], policy: .after(.now.addingTimeInterval(30 * 60)))
    }

    private func entry(for c: TableWidgetIntent, rows count: Int) async -> TableEntry {
        guard let table = try? await DataStore.shared.table(c.league) else {
            return TableEntry(date: .now, league: c.league, rows: [], highlightID: c.club?.id, failed: true)
        }
        // Widgets set up before the switch to the new data provider saved the club's old id.
        let saved = c.club?.league == c.league ? c.club?.id : nil
        let highlight = saved.flatMap { id in table.first { $0.team.id == id || ($0.team.aliases ?? []).contains(id) }?.team.id }
        var picked = Array(table.prefix(count))
        if let highlight, !picked.contains(where: { $0.team.id == highlight }), let mine = table.first(where: { $0.team.id == highlight }) {
            picked[picked.count - 1] = mine
        }
        let rows = picked.map { r in
            TableEntry.Row(teamID: r.team.id, rank: r.rank, name: r.team.name, short: r.team.short, points: r.points,
                           played: r.played, team: r.team)
        }
        return TableEntry(date: .now, league: c.league, rows: rows, highlightID: highlight)
    }
}

struct TableWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: TableEntry

    var body: some View {
        let t = widgetPalette(scheme)
        Group {
            if entry.rows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.league.name.uppercased()).font(AppFont.semibold(11)).tracking(1).foregroundStyle(t.muted)
                    Text(entry.failed ? "Can’t load the table right now." : "No table yet.").font(AppFont.medium(13)).foregroundStyle(t.ink)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .containerBackground(t.bg, for: .widget)
            } else {
                switch family {
                case .systemSmall: small(t)
                case .accessoryRectangular: rectangular
                case .accessoryInline: inline
                default: list(t)
                }
            }
        }
        .widgetURL(DeepLink.url(tab: "table", league: entry.league))
    }

    // Leader in their club colour.
    private func small(_ t: Palette) -> some View {
        let top = entry.rows[0]
        let c = ClubColors(team: top.team, dark: false)
        let gap = entry.rows.count > 1 ? top.points - entry.rows[1].points : 0
        let mine = entry.highlightID.flatMap { id in entry.rows.first { $0.teamID == id } }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(shortLeague.uppercased()).font(AppFont.semibold(11)).tracking(1).opacity(0.85)
                Spacer()
                ClubBadge(team: top.team, size: 30, circle: true).overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1.5))
            }
            Spacer(minLength: 0)
            Text(top.short.uppercased()).font(AppFont.display(15)).lineLimit(1).minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(top.points)").font(AppFont.displayBlack(34))
                Text("pts").font(AppFont.semibold(13)).opacity(0.85)
            }
            if let mine, mine.teamID != top.teamID {
                Text("\(mine.short): \(ordinal(mine.rank)), \(mine.points) pts").font(AppFont.semibold(11)).lineLimit(1).opacity(0.9)
            } else {
                Text(gap > 0 ? "\(gap) pt\(gap == 1 ? "" : "s") clear" : "Level on top").font(AppFont.semibold(11)).opacity(0.9)
            }
        }
        .foregroundStyle(c.on)
        .containerBackground(c.solid, for: .widget)
    }

    // Top 5 (medium) or top 10 (large).
    private func list(_ t: Palette) -> some View {
        let dark = scheme == .dark
        return VStack(alignment: .leading, spacing: family == .systemLarge ? 6 : 3) {
            HStack {
                Text(entry.league.name.uppercased()).font(AppFont.display(12)).foregroundStyle(t.ink)
                Spacer()
                Text("PTS").font(AppFont.semibold(10)).tracking(1).foregroundStyle(t.muted)
            }
            ForEach(entry.rows) { r in
                let c = ClubColors(team: r.team, dark: dark)
                let mine = r.teamID == entry.highlightID
                HStack(spacing: 8) {
                    Text("\(r.rank)").font(AppFont.bold(12)).foregroundStyle(t.muted).frame(width: 16, alignment: .leading)
                    ClubBadge(team: r.team, size: 18)
                    Text(r.short).font(AppFont.semibold(13)).foregroundStyle(t.ink).lineLimit(1)
                    if mine { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(c.hi) }
                    Spacer()
                    Text("\(r.points)").font(AppFont.bold(14)).foregroundStyle(c.hi)
                }
                .monospacedDigit()
                .padding(.vertical, 1).padding(.horizontal, 4)
                .background(mine ? c.solid.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 4))
            }
            Spacer(minLength: 0)
        }
        .containerBackground(t.bg, for: .widget)
    }

    // Lock Screen.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(shortLeague.uppercased()).font(.system(size: 11, weight: .bold)).widgetAccentable()
            ForEach(entry.rows.prefix(3)) { r in
                HStack {
                    Text("\(r.rank) \(r.short)").lineLimit(1)
                    Spacer()
                    Text("\(r.points)").monospacedDigit()
                }
                .font(.system(size: 13, weight: r.teamID == entry.highlightID ? .bold : .medium))
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var inline: some View {
        let top = entry.rows[0]
        return Text("\(top.short) top · \(top.points) pts").containerBackground(.clear, for: .widget)
    }

    private var shortLeague: String {
        switch entry.league {
        case .pl: "Premier League"
        case .laliga: "LaLiga"
        case .bundesliga: "Bundesliga"
        case .ligue1: "Ligue 1"
        }
    }

    private func ordinal(_ n: Int) -> String {
        let s = (n % 100 >= 11 && n % 100 <= 13) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
        return "\(n)\(s)"
    }
}

struct TableWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MatchdayTable", intent: TableWidgetIntent.self, provider: TableProvider()) { entry in
            TableWidgetView(entry: entry)
        }
        .configurationDisplayName("League table")
        .description("Live standings with the leader in their club colour. Pick a club to highlight.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}
