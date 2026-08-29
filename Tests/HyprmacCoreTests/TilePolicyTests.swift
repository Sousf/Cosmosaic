import XCTest
@testable import HyprmacCore

final class TilePolicyTests: XCTestCase {

    let threshold = CGSize(width: 350, height: 250)

    private func verdict(rules: [WindowRule] = [],
                         appName: String = "SomeApp",
                         title: String = "Document",
                         resizable: Bool = true,
                         size: CGSize = CGSize(width: 900, height: 700),
                         floatBelow: CGSize? = nil) -> TilePolicy.Verdict {
        TilePolicy.verdict(rules: rules, appName: appName, title: title,
                           isResizable: resizable, size: size,
                           floatBelowSize: floatBelow ?? threshold)
    }

    func testDefaultIsTile() {
        XCTAssertEqual(verdict(), .tile)
    }

    func testFloatRuleMatchesAppName() {
        let rules = [WindowRule(effect: .float, appPattern: "^(SomeApp)$")]
        XCTAssertEqual(verdict(rules: rules), .float)
    }

    func testFloatRuleMatchesTitle() {
        let rules = [WindowRule(effect: .float, appPattern: "Picture-in-Picture")]
        XCTAssertEqual(verdict(rules: rules, title: "Picture-in-Picture"), .float)
    }

    func testTileRuleOverridesEveryHeuristic() {
        // Non-resizable AND tiny, but the user said tile: tile wins.
        let rules = [WindowRule(effect: .tile, appPattern: "^(SomeApp)$")]
        XCTAssertEqual(verdict(rules: rules, resizable: false,
                               size: CGSize(width: 200, height: 100)), .tile)
    }

    func testTileRuleBeatsFloatRuleWhenBothMatch() {
        let rules = [WindowRule(effect: .float, appPattern: "SomeApp"),
                     WindowRule(effect: .tile, appPattern: "SomeApp")]
        XCTAssertEqual(verdict(rules: rules), .tile)
    }

    func testNonResizableFloats() {
        XCTAssertEqual(verdict(resizable: false), .float)
    }

    func testSmallInBothDimensionsFloats() {
        XCTAssertEqual(verdict(size: CGSize(width: 300, height: 200)), .float)
    }

    func testSmallInOneDimensionStillTiles() {
        XCTAssertEqual(verdict(size: CGSize(width: 300, height: 800)), .tile)
        XCTAssertEqual(verdict(size: CGSize(width: 1200, height: 200)), .tile)
    }

    func testZeroThresholdDisablesSizeHeuristic() {
        XCTAssertEqual(verdict(size: CGSize(width: 10, height: 10),
                               floatBelow: .zero), .tile)
    }

    func testWindowRuleMatchesAppNameOrTitle() {
        let rule = WindowRule(effect: .float, appPattern: "Settings")
        XCTAssertTrue(rule.matches(appName: "System Settings", title: "General"))
        XCTAssertTrue(rule.matches(appName: "MyApp", title: "Settings — MyApp"))
        XCTAssertFalse(rule.matches(appName: "MyApp", title: "Document"))
    }
}
