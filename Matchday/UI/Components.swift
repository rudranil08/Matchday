import SwiftUI

// MARK: screen with a club-colour header band

/// Every screen: a band in the featured club's colour (wordmark, title,
/// league picker, featured club or player), then content that overlaps it.
struct BandScreen<Trailing: View, Feature: View, Content: View>: View {
    @Environment(\.palette) private var t
    @Environment(AppState.self) private var app
    let band: ClubColors
    let title: String
    let offline: Bool
    /// Runs the screen under the status bar (`.ignoresSafeArea(edges: .top)`); the header
    /// contents are pushed down by the status-bar height so they stay readable.
    let ignoresTopSafeArea: Bool
    let onRefresh: (() async -> Void)?
    let trailing: Trailing
    let feature: Feature
    let content: Content

    init(band: ClubColors, title: String, offline: Bool = false, ignoresTopSafeArea: Bool = true, onRefresh: (() async -> Void)? = nil,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder feature: () -> Feature, @ViewBuilder content: () -> Content) {
        self.band = band
        self.title = title
        self.offline = offline
        self.ignoresTopSafeArea = ignoresTopSafeArea
        self.onRefresh = onRefresh
        self.trailing = trailing()
        self.feature = feature()
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            screen(statusBar: ignoresTopSafeArea ? geo.safeAreaInsets.top : 0, inset: geo.safeAreaInsets.top)
        }
    }

    @ViewBuilder private func screen(statusBar: CGFloat, inset: CGFloat) -> some View {
        let scroll = ScrollView {
            ScreenStack {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer()
                        Button { app.showSearch = true } label: {
                            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Search players and clubs")
                        Button { app.showSettings = true } label: {
                            Image(systemName: "gearshape").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Settings")
                    }
                    .padding(.trailing, -4)
                    if offline {
                        Label("Offline · showing saved data", systemImage: "wifi.slash")
                            .font(AppFont.semibold(12)).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(band.on.opacity(0.15), in: Capsule())
                    }
                    HStack(alignment: .center) {
                        Text(title.uppercased()).font(AppFont.display(36)).tracking(-0.4).lineLimit(1).minimumScaleFactor(0.5)
                        Spacer(minLength: 12)
                        trailing.fixedSize()
                    }
                    .padding(.trailing, 8)
                    feature.padding(.top, 18).padding(.trailing, 8)
                }
                .foregroundStyle(band.on)
                .padding(.leading, 20).padding(.trailing, 12).padding(.top, 6 + statusBar).padding(.bottom, 56)
                .background(band.solid.ignoresSafeArea(edges: .top))

                content
            }
            .padding(.bottom, 32)
        }
        .background(t.bg)
        .refreshable { await onRefresh?() }

        if ignoresTopSafeArea {
            // Edge to edge, but the status bar keeps the band colour so scrolled content
            // (and the header buttons) never sit under the clock and battery.
            scroll.ignoresSafeArea(edges: .top)
                .overlay(alignment: .top) {
                    band.solid.frame(height: inset).ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
        } else {
            // Content stays below the status bar, which takes the band colour.
            scroll.overlay(alignment: .top) {
                band.solid.frame(height: inset).offset(y: -inset).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

/// The screen's column. Lazy on iOS 27, so long lists (the injury list can pass 300 players) only
/// build the rows on screen. On iOS 26 a lazy stack under the overlapping cards fell into an endless
/// layout loop when scrolling back to News (found by ReliabilityTests.testTabTour on iOS 26.5), so
/// it's a regular stack there.
struct ScreenStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 27, *) {
            LazyVStack(alignment: .leading, spacing: 0) { content }
        } else {
            VStack(alignment: .leading, spacing: 0) { content }
        }
    }
}

/// The featured club or player inside the band.
struct BandFeature: View {
    let band: ClubColors
    var crest: Team?
    let kicker: String
    let title: String
    var sub: String?

    var body: some View {
        // Names stay in the display face; long titles (headlines) read better in sentence case.
        let long = title.count > 28
        HStack(spacing: 14) {
            if let crest { CrestView(team: crest, size: 60, circle: true) }
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker.uppercased()).font(AppFont.semibold(11)).tracking(1.2).opacity(0.85).lineLimit(1)
                Group {
                    if long {
                        Text(title).font(AppFont.bold(19)).lineLimit(4)
                    } else {
                        Text(title.uppercased()).font(AppFont.display(22)).lineLimit(2).minimumScaleFactor(0.8)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if let sub { Text(sub).font(AppFont.medium(14)).opacity(0.9).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(band.on)
    }
}

/// Cards that overlap the bottom of the band.
struct Overlap<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(.top, -44).padding(.horizontal, 20) }
}

struct CardStyle: ViewModifier {
    @Environment(\.palette) private var t
    func body(content: Content) -> some View {
        content
            .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(t.line, lineWidth: 1))
    }
}
extension View { func card() -> some View { modifier(CardStyle()) } }

/// A club's mark in lists and headers: its badge (colours and code). See `ClubBadge`.
struct CrestView: View {
    let team: Team?
    var size: CGFloat = 28
    var circle = false

    var body: some View { ClubBadge(team: team, size: size, circle: circle) }
}

// MARK: images

/// Decoded images kept in memory (and the HTTP cache on disk), so images don't reload or flash
/// as lists scroll. Each URL is only fetched once at a time.
@MainActor final class ImageCache {
    static let shared = ImageCache()
    private let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 500
        c.totalCostLimit = 60 * 1024 * 1024
        return c
    }()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    /// Memory warning or Settings › Clear: images reload (from the disk HTTP cache) when next shown.
    func removeAll() { cache.removeAllObjects() }

    func load(_ url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        if let running = inFlight[url] { return await running.value }
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            guard let data = try? await Net.data(url), let image = UIImage(data: data) else { return nil }
            // Decode now, off the main thread, so scrolling stays smooth.
            return await image.byPreparingForDisplay() ?? image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            cache.setObject(image, forKey: url as NSURL, cost: cost)
        }
        return image
    }
}

/// A remote image with a placeholder, served from `ImageCache`.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var mode: ContentMode = .fit
    @ViewBuilder var placeholder: Placeholder
    @State private var loaded: UIImage?

    init(url: URL?, mode: ContentMode = .fit, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.mode = mode
        self.placeholder = placeholder()
    }

    private var source: URL? { url }

    var body: some View {
        let shown = loaded ?? source.flatMap { ImageCache.shared.cached($0) }
        Group {
            if let shown {
                Image(uiImage: shown).resizable().aspectRatio(contentMode: mode)
            } else {
                placeholder
            }
        }
        .task(id: source) {
            guard let source, ImageCache.shared.cached(source) == nil else { return }
            loaded = await ImageCache.shared.load(source)
        }
    }
}

/// Text tabs with a thick underline: Form · G+A · Goals.
struct UnderlineTabs<T: Hashable, Trailing: View>: View {
    @Environment(\.palette) private var t
    let options: [(T, String)]
    @Binding var value: T
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 22) {
                ForEach(options, id: \.0) { key, label in
                    let on = key == value
                    Button { value = key } label: {
                        Text(label).font(AppFont.bold(16)).foregroundStyle(on ? t.ink : t.muted)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Rectangle().fill(on ? t.accent : .clear).frame(height: 3) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Spacer()
            trailing.padding(.bottom, 10)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
        .padding(.horizontal, 20).padding(.top, 12)
    }
}

/// "Premier League ▾" in the band.
/// League switcher in the band. Tapping opens Matchday's own league panel
/// (club crests, your club per league, a colour bar on the current one) instead of a system menu.
struct LeagueMenu<Value: Hashable>: View {
    let band: ClubColors
    let options: [(Value, String)]
    @Binding var value: Value
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.0 == value }?.1 ?? "").font(AppFont.semibold(14)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .foregroundStyle(band.on)
            .padding(.leading, 12).padding(.trailing, 10).frame(height: 36)
            .background(band.on.opacity(open ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(band.on.opacity(0.55), lineWidth: 1))
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: open)
        }
        .accessibilityLabel("League: \(options.first { $0.0 == value }?.1 ?? ""). Double-tap to change")
        .sensoryFeedback(.impact(weight: .light), trigger: open)
        #if DEBUG
        // Screenshot hook: -uiTestLeaguePicker opens the panel on launch. Not in Release builds.
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-uiTestLeaguePicker") { open = true } }
        #endif
        .sheet(isPresented: $open) {
            LeaguePanel(options: options, value: $value)
                .presentationDetents([.height(CGFloat(options.count) * 62 + 92)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
    }
}

private struct LeaguePanel<Value: Hashable>: View {
    @Environment(\.palette) private var t
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    let options: [(Value, String)]
    @Binding var value: Value
    @State private var picked: Value?

    private func league(of v: Value) -> League? {
        if let l = v as? League { return l }
        if let f = v as? LeagueFilter, case .one(let l) = f { return l }
        return nil
    }

    private func country(_ l: League) -> String {
        switch l {
        case .pl: "England"
        case .laliga: "Spain"
        case .bundesliga: "Germany"
        case .ligue1: "France"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CHOOSE A LEAGUE").font(AppFont.display(18)).foregroundStyle(t.ink).padding(.top, 28)
            VStack(spacing: 8) {
                ForEach(options, id: \.0) { key, label in
                    let on = key == (picked ?? value)
                    let l = league(of: key)
                    let club = l.flatMap { app.clubs(in: $0).first }
                    let c = club.map { ClubColors(team: $0.team, dark: scheme == .dark) }
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { picked = key }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            value = key
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Group {
                                if let club {
                                    CrestView(team: club.team, size: 40, circle: true).overlay(Circle().stroke(t.line, lineWidth: 1))
                                } else {
                                    Image(systemName: l == nil ? "square.grid.2x2.fill" : "soccerball")
                                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(t.muted)
                                        .frame(width: 40, height: 40).background(t.line, in: Circle())
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label).font(AppFont.bold(16)).foregroundStyle(t.ink)
                                Text(club.map { "Your club · \($0.short)" } ?? l.map(country) ?? "Every league together")
                                    .font(AppFont.medium(13)).foregroundStyle(club != nil ? (c?.hi ?? t.muted) : t.muted)
                            }
                            Spacer()
                            if on {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(c?.solid ?? t.accent)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 10).padding(.horizontal, 14)
                        .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? (c?.solid ?? t.accent) : t.line, lineWidth: on ? 1.5 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.bg)
        .sensoryFeedback(.selection, trigger: picked)
    }
}

struct ProgressBar: View {
    @Environment(\.palette) private var t
    let value: Double
    let color: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(t.line)
                Capsule().fill(color).frame(width: geo.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: height)
    }
}

/// Referee-card status marker.
struct RefereeCard: View {
    @Environment(\.palette) private var t
    let status: InjuryStatus
    var body: some View {
        RoundedRectangle(cornerRadius: 1).fill(status == .out ? t.red : t.yellow)
            .frame(width: 9, height: 13)
            .accessibilityLabel(status.rawValue)
    }
}

struct SectionHead<Trailing: View>: View {
    @Environment(\.palette) private var t
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title.uppercased()).font(AppFont.semibold(12)).tracking(1.2).foregroundStyle(t.ink)
            Spacer()
            trailing
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(t.ink).frame(height: 1) }
        .padding(.horizontal, 20).padding(.top, 20)
    }
}

extension SectionHead where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

struct StateView: View {
    @Environment(\.palette) private var t
    var loading = false
    var error: String?
    var empty: String?
    var retry: (() -> Void)?

    var body: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity).padding(32)
        } else if let error {
            VStack(alignment: .leading, spacing: 10) {
                Text("Couldn’t load live data. \(error)").font(AppFont.regular(15)).foregroundStyle(t.ink)
                if let retry { Button("Try again", action: retry).font(AppFont.bold(15)).foregroundStyle(t.accent) }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card().padding(20)
        } else if let empty {
            Text(empty).font(AppFont.regular(15)).foregroundStyle(t.muted).padding(20)
        }
    }
}

struct Label2: View {
    @Environment(\.palette) private var t
    let text: String
    var color: Color?
    var body: some View { Text(text.uppercased()).font(AppFont.semibold(11)).tracking(1.2).foregroundStyle(color ?? t.muted) }
}

extension Text {
    func mutedStyle(_ t: Palette) -> some View { self.font(AppFont.medium(13)).foregroundStyle(t.muted) }
}
