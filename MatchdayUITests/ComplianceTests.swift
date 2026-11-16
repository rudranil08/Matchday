import XCTest

/// Age gate, guest mode, legal pages and leaderboard moderation.
final class ComplianceTests: XCTestCase {
    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func pick(_ app: XCUIApplication, menu: String, item: String) {
        let wheel = app.pickerWheels.element(boundBy: menu == "Month" ? 0 : 1)
        XCTAssertTrue(wheel.waitForExistence(timeout: 5), "No \(menu) wheel")
        wheel.adjust(toPickerWheelValue: item)
    }

    /// New install: the welcome screen offers only "Get started"; the age question has no defaults;
    /// 13 or over then sees the sign-in options and the Terms / Privacy line.
    func testAgeGateAdult() throws {
        let app = launch(["-uiTestAge", "unknown", "-uiTestNoSession"])
        let start = app.buttons["welcome.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "No Get started button")
        XCTAssertFalse(app.buttons["Continue with Google"].exists, "Sign-in shown before the age question")
        start.tap()
        let cont = app.buttons["age.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5))
        XCTAssertFalse(cont.isEnabled, "Continue must wait for an answer")
        snap(app, "age question")
        pick(app, menu: "Month", item: "March")
        pick(app, menu: "Year", item: "1995")
        cont.tap()
        XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 5), "13 or over should see sign-in")
        XCTAssertTrue(app.links["Privacy Policy"].exists || app.buttons["Privacy Policy"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Privacy Policy'")).firstMatch.exists)
        snap(app, "welcome adult")
    }

    /// Under 13: guest mode only. No sign-in options; continuing goes straight to choosing leagues.
    func testAgeGateChildGuest() throws {
        let app = launch(["-uiTestAge", "unknown", "-uiTestNoSession"])
        app.buttons["welcome.start"].tap()
        pick(app, menu: "Month", item: "June")
        let thisYear = Calendar.current.component(.year, from: Date())
        pick(app, menu: "Year", item: String(thisYear - 9))
        app.buttons["age.continue"].tap()
        let guest = app.buttons["welcome.guest"]
        XCTAssertTrue(guest.waitForExistence(timeout: 5), "Under 13 should get guest mode")
        XCTAssertFalse(app.buttons["Continue with Google"].exists)
        XCTAssertFalse(app.buttons["Sign in with email or username"].exists)
        snap(app, "welcome child")
        guest.tap()
        // A first-time guest picks leagues; a returning guest (saved on this iPhone) goes straight home.
        let leagues = app.staticTexts["PICK YOUR LEAGUES"], home = app.tabBars.firstMatch
        XCTAssertTrue(leagues.waitForExistence(timeout: 5) || home.exists, "Guest didn't get into the app")
        snap(app, "guest in")
    }

    /// A guest using Games: the quiz works, the leaderboard is off and nothing is posted.
    func testGuestGames() throws {
        let app = launch(["-uiTestAge", "child", "-uiTestGuest", "-uiTestClubs", "-uiTestTab", "games"])
        XCTAssertTrue(app.buttons["quiz.start"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["The leaderboard isn’t available in guest mode."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["See all"].exists)
        snap(app, "guest games")
    }

    /// The legal pages open from Settings.
    func testLegalPagesInSettings() throws {
        let app = launch(["-uiTestChecker", "-uiTestClubs", "-uiTestSettings"])
        let row = app.buttons["Privacy Policy"]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        snap(app, "settings legal")
        row.tap()
        XCTAssertTrue(app.staticTexts["PRIVACY POLICY"].waitForExistence(timeout: 5))
        snap(app, "privacy page")
    }

    /// Press and hold a leaderboard name: Report and Hide are offered; Hide works (on this iPhone).
    func testHideName() throws {
        let app = launch(["-uiTestChecker", "-uiTestClubs", "-uiTestTab", "games"])
        let other = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '2, '")).firstMatch
        guard other.waitForExistence(timeout: 20) else { throw XCTSkip("Only one player on today's board") }
        other.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Report name"].waitForExistence(timeout: 3), "No Report option")
        snap(app, "name menu")
        app.buttons["Hide name"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '2, Hidden player'")).firstMatch.waitForExistence(timeout: 3))
        // Undo, so the board looks normal for the next run.
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '2, '")).firstMatch.press(forDuration: 1.0)
        app.buttons["Show name"].tap()
    }
}
