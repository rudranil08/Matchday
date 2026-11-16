import SwiftUI

/// The quiz, full screen and on its own: progress at the top, one question, big answers.
/// Closing keeps your place; the scored round can't be replayed.
struct QuizPlayView: View {
    @Environment(\.palette) private var t
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth
    @Bindable var model: QuizModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if let round = model.round {
                ScrollView {
                    Group {
                        if model.showing >= round.questions.count {
                            summary(round)
                        } else {
                            question(round, index: model.showing)
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 24)
                    .id(model.showing)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
                .scrollBounceBehavior(.basedOnSize)
                footer(round)
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .background(t.bg.ignoresSafeArea())
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: model.showing)
        .sensoryFeedback(trigger: model.round?.picks.count) { _, _ in
            guard let r = model.round, let last = r.picks.last, r.picks.count <= r.questions.count else { return nil }
            return last == r.questions[r.picks.count - 1].answer ? .success : .error
        }
    }

    // MARK: top: close, progress, points

    private var header: some View {
        let round = model.round
        return VStack(spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(t.ink)
                        .frame(width: 36, height: 36).background(t.line, in: Circle())
                }
                .accessibilityLabel("Close")
                Spacer()
                Text(model.isPractice ? "Bonus round" : "Today’s quiz").font(AppFont.semibold(15)).foregroundStyle(t.muted)
                Spacer()
                Text(model.isPractice ? " " : "\(model.todayPoints)")
                    .font(AppFont.bold(17)).foregroundStyle(t.accent).monospacedDigit()
                    .contentTransition(.numericText()).animation(.snappy, value: model.todayPoints)
                    .frame(width: 36, alignment: .trailing)
                    .accessibilityLabel("\(model.todayPoints) points")
            }
            HStack(spacing: 6) {
                ForEach(0..<(round?.questions.count ?? DailyQuiz.questions), id: \.self) { k in
                    let picks = round?.picks ?? []
                    let right = k < picks.count ? picks[k] == round?.questions[k].answer : nil
                    Capsule().frame(height: 5).foregroundStyle(
                        right == true ? t.accent : right == false ? t.red : k == model.showing ? t.ink.opacity(0.35) : t.line)
                }
            }
            .animation(.easeOut(duration: 0.25), value: round?.picks.count)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
    }

    // MARK: question

    private func question(_ round: QuizDay, index i: Int) -> some View {
        let q = round.questions[i]
        let pick: Int? = i < round.picks.count ? round.picks[i] : nil
        return VStack(alignment: .leading, spacing: 22) {
            Text("Question \(i + 1) of \(round.questions.count)").font(AppFont.semibold(13)).foregroundStyle(t.muted)
            Text(q.q).font(AppFont.black(26)).foregroundStyle(t.ink).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { j, option in
                    let state: String? = pick == nil ? nil : j == q.answer ? "right" : j == pick ? "wrong" : "dim"
                    Button { model.answer(j, name: auth.leaderboardName) } label: {
                        HStack(spacing: 12) {
                            Text(option).font(AppFont.semibold(17)).foregroundStyle(state == "right" ? t.onAccent : t.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if state == "right" { Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(t.onAccent) }
                            if state == "wrong" { Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(t.red) }
                        }
                        .padding(.horizontal, 18).frame(minHeight: 58)
                        .background(state == "right" ? t.accent : t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(state == "wrong" ? t.red : state == "right" ? t.accent : t.line, lineWidth: state == nil ? 1 : 1.5))
                        .opacity(state == "dim" ? 0.45 : 1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quiz.option.\(j)")
                    // Locked after answering, without the system's greyed-out look.
                    .allowsHitTesting(pick == nil)
                    .animation(.easeOut(duration: 0.18), value: pick)
                }
            }
            if let pick {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(pick == q.answer ? "Right" : "Not this one").font(AppFont.bold(17)).foregroundStyle(pick == q.answer ? t.accent : t.red)
                        Spacer()
                        if !model.isPractice, let earned = model.earned, earned > 0 {
                            Text("+\(earned) pts").font(AppFont.bold(17)).foregroundStyle(t.accent).monospacedDigit()
                        }
                    }
                    Text(q.why).font(AppFont.regular(16)).foregroundStyle(t.ink).fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: result

    private func summary(_ round: QuizDay) -> some View {
        VStack(spacing: 10) {
            Image(systemName: round.correct >= 4 ? "trophy.fill" : round.correct >= 2 ? "star.fill" : "figure.soccer")
                .font(.system(size: 44)).foregroundStyle(t.accent).padding(.bottom, 6)
            if model.isPractice {
                Text("\(round.correct) of \(round.questions.count)").font(AppFont.displayBlack(48)).foregroundStyle(t.ink)
                Text("Bonus rounds are just for fun. They don’t count towards the leaderboard.")
                    .font(AppFont.regular(16)).foregroundStyle(t.muted).multilineTextAlignment(.center)
            } else {
                Text("\(round.total)").font(AppFont.displayBlack(64)).foregroundStyle(t.ink).monospacedDigit()
                Text("points today").font(AppFont.semibold(17)).foregroundStyle(t.muted)
                Text("\(round.correct) of \(round.questions.count) right. " + (round.correct >= 4 ? "Pundit level." : round.correct >= 2 ? "Solid shift." : "Back to the training ground."))
                    .font(AppFont.regular(16)).foregroundStyle(t.ink).multilineTextAlignment(.center).padding(.top, 8)
                Text("New questions \(DailyQuiz.resetsAt.formatted(.relative(presentation: .named))).")
                    .font(AppFont.regular(15)).foregroundStyle(t.muted)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }

    // MARK: bottom action

    @ViewBuilder private func footer(_ round: QuizDay) -> some View {
        let answered = model.showing < round.picks.count
        let finished = model.showing >= round.questions.count
        VStack(spacing: 10) {
            if finished {
                big(model.isPractice ? "Done" : "Back to Games", filled: true) {
                    if model.isPractice { model.endPractice() }
                    dismiss()
                }
            } else if answered {
                big(model.showing + 1 == round.questions.count ? "See result" : "Next question", filled: true) { model.next() }
            } else {
                Text(model.isPractice ? "Just for fun" : "Faster answers score more").font(AppFont.medium(13)).foregroundStyle(t.muted).frame(height: 54)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    private func big(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(AppFont.bold(17)).foregroundStyle(filled ? t.onAccent : t.accent)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(filled ? t.accent : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
