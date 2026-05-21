import XCTest

final class SysPulseScreenshotUITests: XCTestCase {
    private var screenshotDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["SYSPULSE_SCREENSHOT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("SysPulseScreenshots", isDirectory: true)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
    }

    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-sysPulseScreenshotMode",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 12), "Main tab bar did not appear.")

        try capture("01-servers", app: app)

        openTab("Monitor", in: app)
        XCTAssertTrue(app.staticTexts["Production API"].waitForExistence(timeout: 5))
        try capture("02-monitor", app: app)

        openTab("Terminal", in: app)
        XCTAssertTrue(app.staticTexts["api.sys.example"].waitForExistence(timeout: 5))
        try capture("03-terminal", app: app)

        openTab("Commands", in: app)
        XCTAssertTrue(app.staticTexts["Commands"].waitForExistence(timeout: 5))
        try capture("04-commands", app: app)

        openTab("Settings", in: app)
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        try capture("05-settings", app: app)

        let manageSubscription = app.buttons["Manage subscription"].firstMatch
        XCTAssertTrue(manageSubscription.waitForExistence(timeout: 5))
        manageSubscription.tap()
        XCTAssertTrue(app.staticTexts["Unlock Pro Monitoring"].waitForExistence(timeout: 5))
        try capture("06-paywall", app: app)
    }

    private func openTab(_ title: String, in app: XCUIApplication) {
        let tabButton = app.tabBars.buttons[title].firstMatch
        if tabButton.waitForExistence(timeout: 5) {
            tabButton.tap()
            waitForRender()
            return
        }

        let fallbackButton = app.buttons[title].firstMatch
        XCTAssertTrue(fallbackButton.waitForExistence(timeout: 5), "Could not find \(title) tab.")
        fallbackButton.tap()
        waitForRender()
    }

    private func capture(_ name: String, app: XCUIApplication) throws {
        waitForRender()
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let outputURL = screenshotDirectory.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: outputURL, options: .atomic)
    }

    private func waitForRender() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }
}
