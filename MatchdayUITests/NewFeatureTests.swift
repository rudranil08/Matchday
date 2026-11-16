import XCTest

/// Taps through the newer-iOS features on a simulator. Launch flags (-uiTest…) are DEBUG-only
/// hooks that sign in the checker with Arsenal + Barcelona, so no real account is needed.
final class NewFeatureTests: XCTestCase {
    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestChecker", "-uiTestClubs"] + args
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// iOS 27: swipe a Bundesliga club (not one of our leagues) and follow it.
    func testSwipeToFollow() throws {
        guard #available(iOS 27, *) else { throw XCTSkip("Swipe actions on custom rows need iOS 27") }
        let app = launch(["-uiTestTab", "table"])
        element(app, containing: "League:").tap()
        let bundesliga = element(app, containing: "Bundesliga")
        XCTAssertTrue(bundesliga.waitForExistence(timeout: 5))
        bundesliga.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '1, ' AND label CONTAINS 'points'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Bundesliga table didn't load")
        let club = row.label
        row.swipeLeft()
        snap(app, "after swipe")
        let follow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Follow'")).firstMatch
        XCTAssertTrue(follow.waitForExistence(timeout: 5), "No Follow swipe action")
        snap(app, "swipe")
        follow.tap()
        let followed = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS 'your club'", String(club.prefix(12)))).firstMatch
        XCTAssertTrue(followed.waitForExistence(timeout: 5), "Row wasn't marked as followed: \(club)")
    }

    /// iOS 27: swipe LaLiga and make it the main league.
    func testMakeMainLeague() throws {
        guard #available(iOS 27, *) else { throw XCTSkip("Swipe actions on custom rows need iOS 27") }
        let app = launch(["-uiTestSettings"])
        let barca = app.staticTexts.matching(identifier: "Barcelona").firstMatch
        XCTAssertTrue(barca.waitForExistence(timeout: 5))
        barca.swipeRight()
        let make = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Make main'")).firstMatch
        XCTAssertTrue(make.waitForExistence(timeout: 5), "No Make main swipe action")
        snap(app, "make main")
        make.tap()
        let main = app.staticTexts.matching(identifier: "LaLiga · main league").firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 5), "LaLiga didn't become the main league")
        snap(app, "after make main")
    }

    /// iOS 26+: Catch me up writes a three-point summary with Apple Intelligence.
    func testCatchMeUp() throws {
        let app = launch(["-uiTestTab", "news"])
        let button = app.buttons["Summarise Arsenal"]
        guard button.waitForExistence(timeout: 20) else { throw XCTSkip("Apple Intelligence isn't available on this simulator") }
        button.tap()
        let bullet = element(app, containing: "•")
        XCTAssertTrue(bullet.waitForExistence(timeout: 60), "No summary appeared")
        snap(app, "catch me up")
    }

    /// Games: the hub opens the full-screen quiz (today's round, or a bonus round once it's done).
    func testDailyQuiz() throws {
        let app = launch(["-uiTestTab", "games"])
        let start = app.buttons["quiz.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "Quiz card didn't load")
        snap(app, "games hub")
        start.tap()
        let option = app.buttons["quiz.option.0"]
        XCTAssertTrue(option.waitForExistence(timeout: 10), "Quiz screen didn't open")
        snap(app, "quiz screen")
        option.tap()
        let feedback = app.staticTexts.matching(NSPredicate(format: "label IN {'Right', 'Not this one'}")).firstMatch
        XCTAssertTrue(feedback.waitForExistence(timeout: 5), "No answer feedback")
        snap(app, "quiz answered")
        app.buttons["Close"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Didn't return to the hub")
    }

    /// Plays the rest of today's round, then checks the score is on both leaderboards.
    /// Needs Firestore and Anonymous sign-in turned on in the Firebase project.
    func testLeaderboardEndToEnd() throws {
        let app = launch(["-uiTestTab", "games"])
        let start = app.buttons["quiz.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "Quiz card didn't load")
        if start.label != "Play a bonus round" {
            start.tap()
            let done = app.staticTexts["points today"]
            for _ in 0..<6 where !done.exists {
                let option = app.buttons["quiz.option.0"]
                if option.waitForExistence(timeout: 3), option.isEnabled { option.tap() }
                let next = app.buttons.matching(NSPredicate(format: "label IN {'Next question', 'See result'}")).firstMatch
                if next.waitForExistence(timeout: 3) { next.tap() }
            }
            XCTAssertTrue(done.waitForExistence(timeout: 5), "Round didn't finish")
            snap(app, "round finished")
            app.buttons["Back to Games"].tap()
        }
        let me = element(app, containing: "(you)")
        XCTAssertTrue(me.waitForExistence(timeout: 20), "Score didn't show on the hub's leaderboard")
        snap(app, "hub with score")
        app.buttons["See all"].tap()
        XCTAssertTrue(me.waitForExistence(timeout: 20), "Score didn't show on Today's leaderboard")
        app.buttons["All time"].tap()
        XCTAssertTrue(me.waitForExistence(timeout: 20), "Score didn't show on the All time leaderboard")
        snap(app, "all time board")
    }

    /// Games: the form duel is played on the hub. Pick, see both scores, next pair.
    func testFormDuel() throws {
        let app = launch(["-uiTestTab", "games"])
        let left = app.buttons["duel.0"]
        XCTAssertTrue(left.waitForExistence(timeout: 20), "Duel didn't load")
        app.swipeUp()
        snap(app, "duel before")
        left.tap()
        let next = app.buttons["duel.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "No result after picking")
        snap(app, "duel after")
        next.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pick '")).firstMatch.waitForExistence(timeout: 5), "Next pair didn't appear")
    }
}
