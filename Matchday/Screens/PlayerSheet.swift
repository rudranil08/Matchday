import SwiftUI

struct PlayerSheet: View {
    @Environment(\.palette) private var t
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    let item: RankedPlayer
    @State private var shareImage: Image?

    var body: some View {
        let p = item.player
        let f = item.form
        let c = ClubColors(team: p.team, dark: scheme == .dark)
        let fitLine: String = switch f.fitness {
        case .unknown: "Fitness not checked"
        case .fit: "Fit · no injury listed"
        case .doubtful: "Doubtful for the next game"
        case .out: "Out injured"
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label2(text: "\(p.team.name) · \(p.team.league.name)", color: c.on.opacity(0.9))
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)) }
                            .frame(width: 44, height: 44).accessibilityLabel("Close")
                    }
                    HStack(alignment: .bottom) {
                        Text(p.name.uppercased()).font(AppFont.display(32))
                        Spacer()
                        CrestView(team: p.team, size: 72, circle: true)
                    }
                    Label2(text: [p.positionName, fitLine].compactMap { $0 }.joined(separator: " · "), color: c.on).padding(.top, 8)
                }
                .foregroundStyle(c.on)
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 20)
                .background(c.solid)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(f.score)").font(AppFont.displayBlack(84)).foregroundStyle(c.hi)
                            Text("Form score out of 100").mutedStyle(t)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: 0) {
                            row("Apps", "\(p.apps) / \(f.teamGames)")
                            if let minutes = p.minutes { row("Minutes", "\(minutes)") }
                            row("Goals", "\(p.goals)")
                            row("Assists", "\(p.assists)")
                            if p.minutes == nil { row("G+A a game", String(format: "%.1f", f.gaPerGame)) }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Label2(text: "Why \(f.score)").padding(.top, 24)
                    VStack(spacing: 16) {
                        ForEach(FormScore.reasons(p, f)) { r in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.label).font(AppFont.bold(15)).foregroundStyle(t.ink)
                                        Text(r.note).font(AppFont.regular(13)).foregroundStyle(t.muted)
                                    }
                                    Spacer()
                                    Text(r.verdict).font(AppFont.bold(14)).foregroundStyle(r.muted ? t.muted : c.hi)
                                }
                                ProgressBar(value: r.value, color: r.muted ? t.line : c.hi, height: 4)
                            }
                        }
                    }
                    .padding(.top, 12)

                    Text(f.v2 != nil
                         ? "Compared with other \((p.positionName ?? "player").lowercased())s in the \(p.team.league.name), per 90 minutes, with the last five games counting as much as the whole season. Playing time decides how sure the score is, not how high: with few minutes, a score stays near 50. An injury lowers it until they’re back."
                         : "Goals and assists count the most, then how often the player plays. An injury lowers the score until they’re back.")
                        .font(AppFont.regular(13)).foregroundStyle(t.muted).padding(.top, 16)

                    HStack(spacing: 10) {
                        let following = app.isFollowed(p.team)
                        Button { app.toggleFollow(p.team) } label: {
                            Label(following ? "Following \(p.team.short)" : "Follow \(p.team.short)", systemImage: following ? "star.fill" : "star")
                                .font(AppFont.bold(16)).foregroundStyle(c.on)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(c.solid, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(following && !app.canUnfollow(p.team))
                        .sensoryFeedback(.success, trigger: following)
                        if let shareImage {
                            ShareLink(item: shareImage, subject: Text("\(p.name) · Form \(f.score)"),
                                      preview: SharePreview("\(p.name) · Form \(f.score)", image: shareImage)) {
                                Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .semibold)).foregroundStyle(c.hi)
                                    .frame(width: 50, height: 50)
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(c.hi, lineWidth: 1))
                            }
                            .accessibilityLabel("Share \(p.name)'s form card")
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(20)
            }
        }
        .background(t.bg)
        .presentationDetents([.large])
        .task { await renderShareCard() }
    }

    /// Renders a shareable image of the player's form card.
    @MainActor private func renderShareCard() async {
        // The card is always light, so use the light-mode club colours whatever the phone's mode.
        let renderer = ImageRenderer(content: ShareCard(item: item, colors: ClubColors(team: item.player.team, dark: false)))
        renderer.scale = 3
        if let ui = renderer.uiImage { shareImage = Image(uiImage: ui) }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(AppFont.medium(14)).foregroundStyle(t.muted)
            Spacer()
            Text(v).font(AppFont.bold(17)).foregroundStyle(t.ink).monospacedDigit()
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
    }
}

/// The image people share: club colour band, big score, the three reasons.
struct ShareCard: View {
    let item: RankedPlayer
    let colors: ClubColors

    var body: some View {
        let p = item.player
        let f = item.form
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MATCHDAY · FORM").font(AppFont.semibold(13)).tracking(1.4).opacity(0.85)
                    Text(p.name.uppercased()).font(AppFont.display(30)).lineLimit(2)
                    Text(p.team.name).font(AppFont.medium(16)).opacity(0.9)
                }
                Spacer()
                ClubBadge(team: p.team, size: 88, circle: true)
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
            }
            .foregroundStyle(colors.on)
            .padding(24)
            .background(colors.solid)

            HStack(alignment: .lastTextBaseline, spacing: 16) {
                Text("\(f.score)").font(AppFont.displayBlack(110)).foregroundStyle(colors.hi)
                VStack(alignment: .leading, spacing: 6) {
                    if let v2 = f.v2, let lead = v2.parts.first, p.position == "GK" || p.position == "DEF" {
                        Text(lead.note).font(AppFont.bold(18)).lineLimit(2)
                    } else {
                        Text("\(p.goals) goals · \(p.assists) assists").font(AppFont.bold(18))
                    }
                    Text([p.positionName, "\(p.apps) apps", p.team.league.name].compactMap { $0 }.joined(separator: " · "))
                        .font(AppFont.medium(15)).foregroundStyle(Palette.light.muted)
                }
                .foregroundStyle(Palette.light.ink)
            }
            .padding(24)

            Text("Form score out of 100 · live stats")
                .font(AppFont.medium(13)).foregroundStyle(Palette.light.muted)
                .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .frame(width: 400)
        .background(Palette.light.bg)
    }
}
