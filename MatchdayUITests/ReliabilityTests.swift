import XCTest

/// Offline behaviour, launch time, and a full tour of every tab (for memory checks).
final class ReliabilityTests: XCTestCase {
    private func app(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestChecker", "-uiTestClubs"] + args
        return app
    }

    /// With no signal, every tab still shows the last saved data instead of an error.
    func testOfflineShowsSavedData() throws {
        // Warm the saved data first.
        let online = app(["-uiTestTab", "news"])
        online.launch()
        XCTAssertTrue(online.buttons["leadStory"].waitForExistence(timeout: 20))
        online.terminate()

        let offline = app(["-uiTestTab", "news", "-uiTestOffline"])
        offline.launch()
        XCTAssertTrue(offline.buttons["leadStory"].waitForExistence(timeout: 5), "News didn't show saved stories offline")
        for tab in ["Table", "Form", "Injuries"] {
            offline.tabBars.buttons[tab].tap()
            let error = offline.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Couldn’t load'")).firstMatch
            XCTAssertFalse(error.waitForExistence(timeout: 3), "\(tab) showed an error offline instead of saved data")
        }
        let shot = XCTAttachment(screenshot: offline.screenshot()); shot.name = "offline"; shot.lifetime = .keepAlways; add(shot)
    }

    /// Cold launch to first frame.
    func testLaunchTime() throws {
        measure(metrics: [XCTApplicationLaunchMetric()], options: { let o = XCTMeasureOptions(); o.iterationCount = 3; return o }()) {
            app(["-uiTestTab", "news"]).launch()
        }
    }

    /// Visits every tab, sheet and league; the test runner samples memory while it does.
    func testTabTour() throws {
        let a = app(["-uiTestTab", "news"])
        a.launch()
        XCTAssertTrue(a.buttons["leadStory"].waitForExistence(timeout: 20))
        // The iOS 26 tab bar shrinks while scrolling down; scrolling back up brings it back.
        func open(_ tab: String) {
            // Shrunk to one button? Tap it to expand, as a person would.
            if !a.tabBars.buttons[tab].exists { a.tabBars.buttons.firstMatch.tap() }
            XCTAssertTrue(a.tabBars.buttons[tab].waitForExistence(timeout: 3), "Tab bar didn't expand")
            a.tabBars.buttons[tab].tap()
        }
        for _ in 0..<2 {
            for tab in ["Table", "Form", "Injuries", "Games", "News"] {
                open(tab)
                a.swipeUp(); a.swipeUp(); a.swipeDown(); a.swipeDown(); a.swipeDown()
            }
        }
        open("Table")
        for league in ["LaLiga", "Bundesliga", "Ligue 1", "Premier League"] {
            a.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'League:'")).firstMatch.tap()
            let row = a.descendants(matching: .any).matching(NSPredicate(format: "label == %@", league)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            sleep(2)
            a.swipeUp(); a.swipeDown()
        }
        // Leave the app running so its memory can be read from outside.
        sleep(12)
    }
}
