import XCTest
@testable import CosmosaicCore

final class KeyCodesTests: XCTestCase {

    func testMapsCommonKeyNamesToCarbonKeyCodes() {
        XCTAssertEqual(KeyCodes.keyCode(for: "RETURN"), 36)
        XCTAssertEqual(KeyCodes.keyCode(for: "A"), 0)
        XCTAssertEqual(KeyCodes.keyCode(for: "H"), 4)
        XCTAssertEqual(KeyCodes.keyCode(for: "1"), 18)
        XCTAssertEqual(KeyCodes.keyCode(for: "SPACE"), 49)
        XCTAssertEqual(KeyCodes.keyCode(for: "LEFT"), 123)
    }

    func testKeyLookupIsCaseInsensitive() {
        XCTAssertEqual(KeyCodes.keyCode(for: "return"), 36)
    }

    func testUnknownKeyReturnsNil() {
        XCTAssertNil(KeyCodes.keyCode(for: "FROB"))
    }

    func testReverseLookupReturnsKeyName() {
        XCTAssertEqual(KeyCodes.name(for: 36), "RETURN")
        XCTAssertEqual(KeyCodes.name(for: 4), "H")
        XCTAssertEqual(KeyCodes.name(for: 18), "1")
        XCTAssertNil(KeyCodes.name(for: 999))
    }

    func testModifierCarbonFlags() {
        XCTAssertEqual(KeyCodes.carbonFlags(for: [.super]), 256)
        XCTAssertEqual(KeyCodes.carbonFlags(for: [.shift]), 512)
        XCTAssertEqual(KeyCodes.carbonFlags(for: [.alt]), 2048)
        XCTAssertEqual(KeyCodes.carbonFlags(for: [.ctrl]), 4096)
        XCTAssertEqual(KeyCodes.carbonFlags(for: [.alt, .shift]), 2560)
    }
}
