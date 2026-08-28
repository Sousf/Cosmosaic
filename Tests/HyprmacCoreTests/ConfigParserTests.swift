import XCTest
@testable import HyprmacCore

final class ConfigParserTests: XCTestCase {

    func testParsesBindWithExecDispatcher() throws {
        let config = try ConfigParser.parse("bind = ALT, RETURN, exec, open -a Ghostty")

        XCTAssertEqual(config.binds, [
            Keybind(mods: [.alt], key: "RETURN", dispatcher: .exec("open -a Ghostty"))
        ])
    }

    func testIgnoresCommentsAndBlankLines() throws {
        let text = """
        # launch terminal

        bind = ALT, RETURN, exec, open -a Ghostty  # trailing comment
        """
        let config = try ConfigParser.parse(text)

        XCTAssertEqual(config.binds, [
            Keybind(mods: [.alt], key: "RETURN", dispatcher: .exec("open -a Ghostty"))
        ])
    }

    func testParsesMultipleModifiers() throws {
        let config = try ConfigParser.parse("bind = ALT SHIFT, 1, movetoworkspace, 1")

        XCTAssertEqual(config.binds.first?.mods, [.alt, .shift])
    }

    func testParsesAllDispatchers() throws {
        let text = """
        bind = ALT, Q, killactive
        bind = ALT, H, movefocus, l
        bind = ALT, L, movewindow, r
        bind = ALT, 3, workspace, 3
        bind = ALT SHIFT, 5, movetoworkspace, 5
        bind = ALT, V, togglefloating
        bind = ALT, F, fullscreen
        bind = ALT, R, resizeactive, 10 0
        bind = ALT SHIFT, C, reload
        """
        let config = try ConfigParser.parse(text)

        XCTAssertEqual(config.binds.map(\.dispatcher), [
            .killactive,
            .movefocus(.left),
            .movewindow(.right),
            .workspace(3),
            .movetoworkspace(5),
            .togglefloating,
            .fullscreen,
            .resizeactive(dx: 10, dy: 0),
            .reload,
        ])
    }

    func testUnknownDispatcherErrorIncludesLineNumber() {
        let text = """
        bind = ALT, RETURN, exec, open -a Ghostty
        bind = ALT, Z, frobnicate
        """
        XCTAssertThrowsError(try ConfigParser.parse(text)) { error in
            let configError = error as? ConfigError
            XCTAssertEqual(configError?.line, 2)
            XCTAssertTrue(configError?.message.contains("frobnicate") ?? false)
        }
    }

    func testInvalidWorkspaceNumberThrows() {
        XCTAssertThrowsError(try ConfigParser.parse("bind = ALT, X, workspace, banana"))
    }

    func testSubstitutesVariables() throws {
        let text = """
        $mod = ALT
        $term = open -a Ghostty
        bind = $mod, RETURN, exec, $term
        """
        let config = try ConfigParser.parse(text)

        XCTAssertEqual(config.binds, [
            Keybind(mods: [.alt], key: "RETURN", dispatcher: .exec("open -a Ghostty"))
        ])
    }

    func testParsesGeneralBlock() throws {
        let text = """
        general {
            gaps_in = 4
            gaps_out = 12
            border_size = 2
            col.active_border = rgba(33ccffee)
            col.inactive_border = rgb(595959)
        }
        """
        let config = try ConfigParser.parse(text)

        XCTAssertEqual(config.general.gapsIn, 4)
        XCTAssertEqual(config.general.gapsOut, 12)
        XCTAssertEqual(config.general.borderSize, 2)
        XCTAssertEqual(config.general.activeBorderColor,
                       ConfigColor(r: 0x33, g: 0xcc, b: 0xff, a: 0xee))
        XCTAssertEqual(config.general.inactiveBorderColor,
                       ConfigColor(r: 0x59, g: 0x59, b: 0x59, a: 0xff))
    }

    func testGeneralDefaultsWhenAbsent() throws {
        let config = try ConfigParser.parse("bind = ALT, Q, killactive")

        XCTAssertEqual(config.general.gapsIn, 5)
        XCTAssertEqual(config.general.gapsOut, 10)
    }

    func testParsesWindowRule() throws {
        let config = try ConfigParser.parse("windowrule = float, ^(System Settings)$")

        XCTAssertEqual(config.windowRules, [
            WindowRule(effect: .float, appPattern: "^(System Settings)$")
        ])
    }

    func testInvalidWindowRuleRegexThrows() {
        XCTAssertThrowsError(try ConfigParser.parse("windowrule = float, ^(unclosed"))
    }

    func testUnclosedBlockThrows() {
        XCTAssertThrowsError(try ConfigParser.parse("general {\n    gaps_in = 4\n"))
    }
}
