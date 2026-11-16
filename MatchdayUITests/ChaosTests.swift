import XCTest

/// The app under an overloaded network: slow replies, dropped connections, server errors and
/// garbage bodies on every request (-uiTestChaos). Nothing here checks content; it checks the app
/// never crashes or hangs while a person uses every screen.
final class ChaosTests: XCTestCase {
    private var app: XCUIApplication!

    private func alive(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.state, .runningForeground, "App stopped running after: \(step)", file: file, line: line)
    }

    private func any(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    private func tab(_ name: String) {
        if !app.tabBars.buttons[name].exists { app.tabBars.buttons.firstMatch.tap() }
        if app.tabBars.buttons[name].waitForExistence(timeout: 3) { app.tabBars.buttons[name].tap() }
        alive("open \(name)")
    }

    func testEverythingUnderChaos() throws {
        app = XCUIApplication()
        app.launchArguments = ["-uiTestChecker", "-uiTestClubs", "-uiTestChaos", "-uiTestFreshInstall", "-uiTestTab", "news"]
        app.launch()
        sleep(4); alive("launch with no saved data")

        for round in 1...2 {
            for name in ["News", "Table", "Form", "Injuries", "Games"] {
                tab(name)
                app.swipeDown()                      // pull to refresh while requests fail
                sleep(1)
                app.swipeUp(); app.swipeUp(); app.swipeDown(); app.swipeDown(); app.swipeDown()
                alive("scroll \(name) (round \(round))")
            }
            // Switch leagues quickly on the Table while feeds fail.
            tab("Table")
            for league in ["LaLiga", "Bundesliga", "Ligue 1", "Premier League"] {
                let menu = any("League:")
                if menu.waitForExistence(timeout: 3) { menu.tap() }
                let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", league)).firstMatch
                if row.waitForExistence(timeout: 3) { row.tap() }
                alive("switch to \(league)")
            }
            // Search and Settings sheets.
            let search = app.buttons["Search players and clubs"]
            if search.waitForExistence(timeout: 3) {
                search.tap(); sleep(2); alive("search")
                let field = app.searchFields.firstMatch
                if field.waitForExistence(timeout: 3) {
                    field.tap()
                    field.typeText("ka"); sleep(2); alive("search typing")
                }
                if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            }
            let settings = app.buttons["Settings"]
            if settings.waitForExistence(timeout: 3) {
                settings.tap(); sleep(2); app.swipeUp(); alive("settings")
                if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            }
            // Games: quiz, duel, leaderboard.
            tab("Games")
            let start = app.buttons["quiz.start"]
            if start.waitForExistence(timeout: 15) {
                start.tap()
                for _ in 0..<6 {
                    let option = app.buttons["quiz.option.1"]
                    if option.waitForExistence(timeout: 3) { option.tap() }
                    let next = app.buttons.matching(NSPredicate(format: "label IN {'Next question', 'See result', 'Back to Games', 'Done'}")).firstMatch
                    if next.waitForExistence(timeout: 3) { next.tap() }
                    alive("quiz answer")
                }
                // The quiz may already have closed itself ("Back to Games"); only tap Close if it's still there.
                let close = app.buttons["Close"]
                if close.exists, close.isHittable { close.tap() }
            }
            let duel = app.buttons["duel.0"]
            if duel.waitForExistence(timeout: 8) {
                for _ in 0..<3 {
                    // Each new pair slides in; wait for it before tapping.
                    guard duel.waitForExistence(timeout: 5), duel.isHittable else { break }
                    duel.tap()
                    if app.buttons["duel.next"].waitForExistence(timeout: 3) { app.buttons["duel.next"].tap() }
                    alive("duel")
                }
            }
            if app.buttons["See all"].waitForExistence(timeout: 3) {
                app.buttons["See all"].tap(); sleep(2); app.swipeDown(); alive("leaderboard")
                if app.buttons["All time"].exists { app.buttons["All time"].tap(); sleep(2) }
                app.navigationBars.buttons.firstMatch.tap()
                alive("leaderboard back")
            }
        }
        // Background and foreground (prefetch, trimming memory, background refresh booking).
        XCUIDevice.shared.press(.home); sleep(2)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App didn't come back from the background")
        sleep(2)
        alive("back from background")
    }

    /// Ten cold launches in a row with chaos and no saved data.
    func testColdLaunchesUnderChaos() throws {
        for i in 1...10 {
            app = XCUIApplication()
            app.launchArguments = ["-uiTestChecker", "-uiTestClubs", "-uiTestChaos", "-uiTestFreshInstall",
                                   "-uiTestTab", ["news", "table", "form", "injuries", "games"][i % 5]]
            app.launch()
            sleep(3)
            alive("cold launch \(i)")
            app.terminate()
        }
    }
}
