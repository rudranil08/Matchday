import SwiftUI

/// Today's quiz state, shared by the Games hub (status card) and the full-screen quiz.
@MainActor @Observable final class QuizModel {
    /// Today's scored round (saved on the iPhone) and an optional unscored bonus round.
    var quiz: QuizDay?
    var practice: QuizDay?
    /// The question on screen, when it appeared (for the speed bonus), and what the last answer earned.
    var showing = 0
    var shownAt = Date()
    var earned: Int?
    /// Bumped when a finished round's score has been posted, so leaderboards refresh.
    var posted = 0

    private var player = ""

    var round: QuizDay? { practice ?? quiz }
    var isPractice: Bool { practice != nil }
    var todayPoints: Int { quiz?.total ?? 0 }
    var todayFinished: Bool { quiz?.finished == true }
    var todayAnswered: Int { quiz?.picks.count ?? 0 }

    func prepare(player: String, leagues: [League], name: String) async {
        self.player = player
        self.name = name
        let day = DailyQuiz.today
        if let saved = QuizDay.load(player, day: day) {
            quiz = saved
        } else {
            let fresh = QuizDay(day: day, questions: await DailyQuiz.make(for: player, day: day, leagues: leagues))
            fresh.save(player)
            quiz = fresh
        }
        practice = nil
        resume()
        // A post that didn't get through last time (no signal, app closed): send it now.
        if let q = quiz, q.picks.count > (q.posted ?? 0) { post(q) }
    }

    private var name = "Player"

    private func post(_ q: QuizDay) {
        guard !AuthStore.shared.isGuest else { return }   // guest mode: nothing leaves the iPhone
        let player = self.player, name = self.name
        Task {
            do {
                try await Leaderboard.shared.submit(day: q.day, points: q.total, correct: q.correct, answered: q.picks.count,
                                                    final: q.finished, name: name)
                if var current = quiz, current.day == q.day, (current.posted ?? 0) < q.picks.count {
                    current.posted = q.picks.count
                    current.save(player)
                    quiz = current
                }
                if q.finished { posted += 1 }
            } catch {
                // Kept on the iPhone; posted next time Games opens.
            }
        }
    }

    /// Opening the quiz: carry on from the first unanswered question.
    func resume() {
        showing = round?.picks.count ?? 0
        shownAt = Date()
        earned = nil
    }

    func answer(_ j: Int, name: String) {
        let seconds = Date().timeIntervalSince(shownAt)
        if var p = practice {
            guard p.picks.count == showing else { return }
            p.picks.append(j)
            p.points.append(0)
            practice = p
            return
        }
        guard var q = quiz, q.picks.count == showing, showing < q.questions.count else { return }
        let points = DailyQuiz.points(correct: j == q.questions[showing].answer, seconds: seconds)
        q.picks.append(j)
        q.points.append(points)
        q.save(player)
        quiz = q
        earned = points
        self.name = name
        post(q)
    }

    func next() {
        showing += 1
        shownAt = Date()
        earned = nil
    }

    func startPractice() {
        var rng = SystemRandomNumberGenerator()
        practice = QuizDay(day: DailyQuiz.today, questions: Array(trivia.shuffled(using: &rng).prefix(DailyQuiz.questions)))
        resume()
    }

    func endPractice() {
        practice = nil
        resume()
    }
}
