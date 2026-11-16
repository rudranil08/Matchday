import WidgetKit
import SwiftUI
import AppIntents

struct FormWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Form leader"
    static var description = IntentDescription("The player in the best form right now.")

    @Parameter(title: "Leagues", default: .all) var leagues: LeagueOption
}

struct FormEntry: TimelineEntry {
    struct Player: Identifiable {
        let id: String
        let name: String
        let team: Team
        let score: Int
        let goals: Int
        let assists: Int
    }

    let date: Date
    let scope: String
    let players: [Player]
    var failed = false

    static var placeholder: FormEntry {
        let team = Team(id: "0", name: "Club", short: "Club", crest: nil, color: "dc052d", alt: nil, league: .pl)
        return FormEntry(date: .now, scope: "All leagues", players: [
            .init(id: "1", name: "Player One", team: team, score: 96, goals: 12, assists: 3),
            .init(id: "2", name: "Player Two", team: team, score: 78, goals: 10, assists: 1),
            .init(id: "3", name: "Player Three", team: team, score: 74, goals: 6, assists: 5),
        ])
    }
}

struct FormProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FormEntry { .placeholder }

    func snapshot(for configuration: FormWidgetIntent, in context: Context) async -> FormEntry {
        context.isPreview ? .placeholder : await entry(configuration)
    }

    func timeline(for configuration: FormWidgetIntent, in context: Context) async -> Timeline<FormEntry> {
        Timeline(entries: [await entry(configuration)], policy: .after(.now.addingTimeInterval(60 * 60)))
    }

    private func entry(_ c: FormWidgetIntent) async -> FormEntry {
        let filter = c.leagues.filter
        guard let ranked = try? await DataStore.shared.ranked(filter, withInjuries: false) else {
            return FormEntry(date: .now, scope: filter.name, players: [], failed: true)
        }
        let players = ranked.prefix(3).map { r in
            FormEntry.Player(id: r.id, name: r.player.name, team: r.player.team, score: r.form.score,
                             goals: r.player.goals, assists: r.player.assists)
        }
        return FormEntry(date: .now, scope: filter.name, players: players)
    }
}

struct FormWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: FormEntry

    var body: some View {
        let t = widgetPalette(scheme)
        Group {
            if let top = entry.players.first {
                switch family {
                case .systemSmall: small(top)
                case .accessoryRectangular: rectangular(top)
                case .accessoryInline: Text("In form: \(top.name) \(top.score)").containerBackground(.clear, for: .widget)
                default: medium(t)
                }
            } else {
                Text(entry.failed ? "Can’t load player form right now." : "No players yet.")
                    .font(AppFont.medium(13)).foregroundStyle(t.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .containerBackground(t.bg, for: .widget)
            }
        }
        .widgetURL(DeepLink.url(tab: "form"))
    }

    private func small(_ p: FormEntry.Player) -> some View {
        let c = ClubColors(team: p.team, dark: false)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("IN FORM").font(AppFont.semibold(11)).tracking(1).opacity(0.85)
                Spacer()
                ClubBadge(team: p.team, size: 28, circle: true).overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1.5))
            }
            Spacer(minLength: 0)
            Text("\(p.score)").font(AppFont.displayBlack(40))
            Text(p.name.uppercased()).font(AppFont.display(12)).lineLimit(2).minimumScaleFactor(0.7)
            Text("\(p.goals) goals · \(p.assists) assists").font(AppFont.semibold(11)).opacity(0.9)
        }
        .foregroundStyle(c.on)
        .containerBackground(c.solid, for: .widget)
    }

    private func medium(_ t: Palette) -> some View {
        let dark = scheme == .dark
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("IN FORM").font(AppFont.display(12)).foregroundStyle(t.ink)
                Spacer()
                Text(entry.scope.uppercased()).font(AppFont.semibold(10)).tracking(1).foregroundStyle(t.muted)
            }
            ForEach(entry.players) { p in
                let c = ClubColors(team: p.team, dark: dark)
                HStack(spacing: 10) {
                    ClubBadge(team: p.team, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name).font(AppFont.bold(14)).foregroundStyle(t.ink).lineLimit(1)
                        Text("\(p.goals) goals · \(p.assists) assists").font(AppFont.medium(11)).foregroundStyle(t.muted)
                    }
                    Spacer()
                    Text("\(p.score)").font(AppFont.black(20)).foregroundStyle(c.hi).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(t.bg, for: .widget)
    }

    private func rectangular(_ p: FormEntry.Player) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("IN FORM").font(.system(size: 11, weight: .bold)).widgetAccentable()
            Text(p.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Text("Form \(p.score) · \(p.goals)G \(p.assists)A").font(.system(size: 12)).monospacedDigit()
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct FormWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MatchdayForm", intent: FormWidgetIntent.self, provider: FormProvider()) { entry in
            FormWidgetView(entry: entry)
        }
        .configurationDisplayName("Form leader")
        .description("The player in the best form, in their club colour.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
