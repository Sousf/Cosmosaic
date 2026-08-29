import XCTest
@testable import CosmosaicCore

final class LaunchCommandTests: XCTestCase {

    func testExecForAppLaunchesNewInstance() {
        XCTAssertEqual(LaunchCommand.exec(forApp: "Google Chrome"),
                       "open -n -a \"Google Chrome\"")
        XCTAssertEqual(LaunchCommand.exec(forApp: "Safari"),
                       "open -n -a \"Safari\"")
    }

    func testAppNameFromNewInstanceExec() {
        XCTAssertEqual(LaunchCommand.appName(fromExec: "open -n -a \"Ghostty\""),
                       "Ghostty")
    }

    func testAppNameFromQuotedExec() {
        XCTAssertEqual(LaunchCommand.appName(fromExec: "open -a \"Google Chrome\""),
                       "Google Chrome")
    }

    func testAppNameFromUnquotedExec() {
        XCTAssertEqual(LaunchCommand.appName(fromExec: "open -a Safari"), "Safari")
    }

    func testAppNameToleratesWhitespace() {
        XCTAssertEqual(LaunchCommand.appName(fromExec: "  open -a \"Ghostty\"  "),
                       "Ghostty")
    }

    func testNonLaunchCommandsReturnNil() {
        XCTAssertNil(LaunchCommand.appName(fromExec: "echo hello"))
        XCTAssertNil(LaunchCommand.appName(fromExec: "open https://example.com"))
        XCTAssertNil(LaunchCommand.appName(fromExec: "open -a"))
        XCTAssertNil(LaunchCommand.appName(fromExec: "open -a Safari --args -x"))
    }

    func testRoundTrip() {
        let command = LaunchCommand.exec(forApp: "Activity Monitor")
        XCTAssertEqual(LaunchCommand.appName(fromExec: command), "Activity Monitor")
    }
}
