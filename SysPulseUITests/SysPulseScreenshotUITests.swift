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
            "UITEST_SCREENSHOTS",
            "DISABLE_ANIMATIONS",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 12), "Main tab bar did not appear.")
        XCTAssertTrue(waitForScreen(.servers, in: app), "Servers screen did not appear.")

        try capture("01-servers", app: app)

        openTab(.monitor, in: app)
        try capture("02-monitor", app: app)

        openTab(.terminal, in: app)
        try capture("03-terminal", app: app)

        openTab(.commands, in: app)
        try capture("04-commands", app: app)
    }

    private func openTab(_ tab: ScreenshotTab, in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Tab bar did not exist before opening \(tab.tabIdentifier).")

        let tabButton = tabBar.buttons[tab.tabIdentifier].firstMatch
        if tabButton.waitForExistence(timeout: 3), tabButton.isHittable {
            tabButton.tap()
        } else {
            tapTabByCoordinate(tab, tabBar: tabBar)
        }

        waitForRender()
        XCTAssertTrue(waitForScreen(tab, in: app), "\(tab.screenIdentifier) did not appear after tapping \(tab.tabIdentifier).")
    }

    private func tapTabByCoordinate(_ tab: ScreenshotTab, tabBar: XCUIElement) {
        let normalizedX = (CGFloat(tab.index) + 0.5) / CGFloat(ScreenshotTab.visibleTabCount)
        let coordinate = tabBar.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: 0.5))
        coordinate.tap()
    }

    private func waitForScreen(_ tab: ScreenshotTab, in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)[tab.screenIdentifier].waitForExistence(timeout: 8)
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    }
}

private enum ScreenshotTab {
    case servers
    case monitor
    case terminal
    case commands

    static let visibleTabCount = 5

    var index: Int {
        switch self {
        case .servers:
            0
        case .monitor:
            1
        case .terminal:
            2
        case .commands:
            3
        }
    }

    var tabIdentifier: String {
        switch self {
        case .servers:
            "tab_servers"
        case .monitor:
            "tab_monitor"
        case .terminal:
            "tab_terminal"
        case .commands:
            "tab_commands"
        }
    }

    var screenIdentifier: String {
        switch self {
        case .servers:
            "screen_servers"
        case .monitor:
            "screen_monitor"
        case .terminal:
            "screen_terminal"
        case .commands:
            "screen_commands"
        }
    }
}
