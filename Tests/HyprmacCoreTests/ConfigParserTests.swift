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
        XCTAssertEqual(config.general.activeBorder,
                       BorderFill(colors: [ConfigColor(r: 0x33, g: 0xcc, b: 0xff, a: 0xee)],
                                  angleDegrees: 0))
        XCTAssertEqual(config.general.inactiveBorderColor,
                       ConfigColor(r: 0x59, g: 0x59, b: 0x59, a: 0xff))
    }

    func testParsesGradientBorderWithAngle() throws {
        let config = try ConfigParser.parse(
            "general {\n    col.active_border = rgba(33ccffee) rgba(8839efee) 45deg\n}")

        XCTAssertEqual(config.general.activeBorder, BorderFill(
            colors: [ConfigColor(r: 0x33, g: 0xcc, b: 0xff, a: 0xee),
                     ConfigColor(r: 0x88, g: 0x39, b: 0xef, a: 0xee)],
            angleDegrees: 45))
    }

    func testGradientWithoutAngleDefaultsToZero() throws {
        let config = try ConfigParser.parse(
            "general {\n    col.active_border = rgb(ff0000) rgb(0000ff)\n}")

        XCTAssertEqual(config.general.activeBorder.colors.count, 2)
        XCTAssertEqual(config.general.activeBorder.angleDegrees, 0)
    }

    func testInvalidGradientStopThrows() {
        XCTAssertThrowsError(try ConfigParser.parse(
            "general {\n    col.active_border = rgb(ff0000) banana\n}"))
    }

    func testParsesBorderAnimation() throws {
        let rainbow = try ConfigParser.parse("general {\n    border_animation = rainbow\n}")
        XCTAssertEqual(rainbow.general.borderAnimation, .rainbow)

        let none = try ConfigParser.parse("bind = ALT, Q, killactive")
        XCTAssertEqual(none.general.borderAnimation, BorderAnimation.none)

        XCTAssertThrowsError(try ConfigParser.parse(
            "general {\n    border_animation = disco\n}"))
    }

    func testParsesBorderAnimationSpeed() throws {
        let config = try ConfigParser.parse("general {\n    border_animation_speed = 2.5\n}")
        XCTAssertEqual(config.general.borderAnimationSpeed, 2.5)

        XCTAssertThrowsError(try ConfigParser.parse(
            "general {\n    border_animation_speed = -1\n}"))
    }

    func testBorderFillSerializesToConfigText() {
        XCTAssertEqual(BorderFill(colors: [ConfigColor(r: 0x33, g: 0xcc, b: 0xff, a: 0xee)],
                                  angleDegrees: 0).configText,
                       "rgba(33ccffee)")
        XCTAssertEqual(BorderFill(colors: [ConfigColor(r: 0xff, g: 0, b: 0, a: 0xff),
                                           ConfigColor(r: 0, g: 0, b: 0xff, a: 0xff)],
                                  angleDegrees: 45).configText,
                       "rgba(ff0000ff) rgba(0000ffff) 45deg")
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

    func testParsesFloatBelowSize() throws {
        let config = try ConfigParser.parse("general {\n    float_below_size = 400 300\n}")
        XCTAssertEqual(config.general.floatBelowSize, CGSize(width: 400, height: 300))
    }

    func testFloatBelowSizeDefault() throws {
        let config = try ConfigParser.parse("bind = ALT, Q, killactive")
        XCTAssertEqual(config.general.floatBelowSize, CGSize(width: 350, height: 250))
    }

    func testInvalidFloatBelowSizeThrows() {
        XCTAssertThrowsError(try ConfigParser.parse("general {\n    float_below_size = big\n}"))
    }

    func testParsesInputBlockFollowMouse() throws {
        let off = try ConfigParser.parse("input {\n    follow_mouse = 0\n}")
        XCTAssertFalse(off.input.followMouse)

        let on = try ConfigParser.parse("input {\n    follow_mouse = 1\n}")
        XCTAssertTrue(on.input.followMouse)

        let word = try ConfigParser.parse("input {\n    follow_mouse = false\n}")
        XCTAssertFalse(word.input.followMouse)
    }

    func testFollowMouseDefaultsOn() throws {
        let config = try ConfigParser.parse("bind = ALT, Q, killactive")
        XCTAssertTrue(config.input.followMouse)
    }

    func testUnknownInputOptionThrows() {
        XCTAssertThrowsError(try ConfigParser.parse("input {\n    frobnicate = 1\n}"))
    }

    func testBindProvenanceRecordsLineRawModsAndComment() throws {
        let text = """
        $mod = ALT

        bind = $mod, H, movefocus, l  # focus left
        bind = ALT SHIFT, J, movewindow, d
        """
        let config = try ConfigParser.parse(text)

        XCTAssertEqual(config.bindProvenance, [
            BindProvenance(line: 3, rawMods: "$mod", comment: "# focus left"),
            BindProvenance(line: 4, rawMods: "ALT SHIFT", comment: nil),
        ])
        XCTAssertEqual(config.binds.count, config.bindProvenance.count)
    }
}
