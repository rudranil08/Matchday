import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "Catch me up": Apple Intelligence reads your club's latest results, fixtures and injury news
/// (all written from match data) and writes three short points, on the iPhone itself
/// (iOS 26 or later, Apple Intelligence on).
/// Nothing leaves the device. Hidden where the model isn't available.
enum Briefing {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) { return SystemLanguageModel.default.availability == .available }
        #endif
        return false
    }

    /// Same stories → same briefing, without asking the model again.
    @MainActor private static var memo: [String: String] = [:]

    @MainActor static func make(club: String, stories: [Story]) async throws -> String {
        let picked = Array(stories.prefix(8))
        let key = club + picked.map(\.id).joined(separator: ",")
        if let done = memo[key] { return done }
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let session = LanguageModelSession(instructions: """
                You are a football news editor. Summarise the match facts you are given for a fan of \(club):
                results with scorers, upcoming fixtures and injuries.
                Write exactly three short bullet points, each starting with "• ", at most 20 words each.
                Use only the facts given. No predictions, no opinions, no other clubs' news.
                """)
            let list = picked.map { "- \($0.tag.rawValue): \($0.headline). \($0.description.prefix(220))" }.joined(separator: "\n")
            let text = try await session.respond(to: "Latest \(club) news:\n\(list)").content
                .trimmingCharacters(in: .whitespacesAndNewlines)
            memo[key] = text
            return text
        }
        #endif
        throw CancellationError()
    }
}

/// The card in News, under the lead story.
struct BriefingCard: View {
    @Environment(\.palette) private var t
    let club: String
    let stories: [Story]
    let color: Color
    @State private var text: String?
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "apple.intelligence").foregroundStyle(color)
                Text("CATCH ME UP").font(AppFont.semibold(12)).tracking(1.2).foregroundStyle(t.ink)
                Spacer()
                if text == nil {
                    Button(busy ? "Writing…" : "Summarise \(club)") { Task { await run() } }
                        .font(AppFont.bold(14)).foregroundStyle(color).disabled(busy)
                }
            }
            if busy && text == nil {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            }
            if let text {
                Text(text).font(AppFont.regular(15)).foregroundStyle(t.ink).fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                Text("Written on your iPhone by Apple Intelligence from the latest match data. It can make mistakes.")
                    .font(AppFont.regular(12)).foregroundStyle(t.muted)
            } else if failed {
                Text("Couldn’t write a summary right now.").mutedStyle(t)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        .padding(.horizontal, 20).padding(.top, 14)
        .sensoryFeedback(.success, trigger: text != nil)
        .task(id: stories.first?.id) { text = nil; failed = false }
    }

    private func run() async {
        busy = true
        failed = false
        defer { busy = false }
        do {
            let result = try await Briefing.make(club: club, stories: stories)
            withAnimation(.easeOut(duration: 0.25)) { text = result }
        } catch {
            failed = true
        }
    }
}
