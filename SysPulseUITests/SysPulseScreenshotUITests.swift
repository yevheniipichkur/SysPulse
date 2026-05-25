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
        for tab in ScreenshotTab.captureOrder {
            let app = launchApp(on: tab)
            guard app.tabBars.firstMatch.waitForExistence(timeout: 12) else {
                try? capture("00-\(tab.rawValue)-missing-tabbar", app: app)
                XCTFail("Main tab bar did not appear for \(tab.rawValue).")
                app.terminate()
                return
            }
            guard waitForScreen(tab, in: app) else {
                try? capture("00-\(tab.rawValue)-missing-screen", app: app)
                XCTFail("\(tab.screenIdentifier) did not appear for \(tab.rawValue).")
                app.terminate()
                return
            }
            try capture(tab.filename, app: app)
            app.terminate()
        }
    }

    private func launchApp(on tab: ScreenshotTab) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-sysPulseScreenshotMode",
            "-sysPulseScreenshotTab",
            tab.rawValue,
            "UITEST_SCREENSHOTS",
            "DISABLE_ANIMATIONS",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launch()
        return app
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

private enum ScreenshotTab: String {
    case servers
    case monitor
    case terminal
    case sftp
    case settings

    static let captureOrder: [ScreenshotTab] = [.servers, .monitor, .terminal, .sftp, .settings]

    var screenIdentifier: String {
        switch self {
        case .servers:
            "screen_servers"
        case .monitor:
            "screen_monitor"
        case .terminal:
            "screen_terminal"
        case .sftp:
            "screen_sftp"
        case .settings:
            "screen_settings"
        }
    }

    var filename: String {
        switch self {
        case .servers:
            "01-servers"
        case .monitor:
            "02-monitor"
        case .terminal:
            "03-terminal"
        case .sftp:
            "04-files"
        case .settings:
            "05-settings"
        }
    }
}
