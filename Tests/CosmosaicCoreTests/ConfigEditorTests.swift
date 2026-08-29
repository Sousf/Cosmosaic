import XCTest
@testable import CosmosaicCore

final class ConfigEditorTests: XCTestCase {

    let text = """
    # my config
    $mod = ALT

    bind = $mod, H, movefocus, l  # focus left
    bind = ALT SHIFT, J, movewindow, d

    general {
        gaps_in = 6
    }
    """

    private func provenance(_ config: Config, _ index: Int) -> BindProvenance {
        config.bindProvenance[index]
    }

    func testUpdateKeyKeepsRawModsVariableAndComment() throws {
        let config = try ConfigParser.parse(text)
        let old = config.binds[0]
        var new = old
        new.key = "N"

        let result = ConfigEditor.updateBind(in: text, provenance: provenance(config, 0),
                                             oldBind: old, newBind: new)

        XCTAssertTrue(result.contains("bind = $mod, N, movefocus, l  # focus left"))
        XCTAssertFalse(result.contains("bind = $mod, H"))
        // Everything else untouched.
        XCTAssertTrue(result.contains("# my config"))
        XCTAssertTrue(result.contains("bind = ALT SHIFT, J, movewindow, d"))
    }

    func testUpdateChangedModsWritesLiteralCanonicalOrder() throws {
        let config = try ConfigParser.parse(text)
        let old = config.binds[0]
        var new = old
        new.mods = [.shift, .alt, .ctrl]

        let result = ConfigEditor.updateBind(in: text, provenance: provenance(config, 0),
                                             oldBind: old, newBind: new)

        XCTAssertTrue(result.contains("bind = CTRL ALT SHIFT, H, movefocus, l  # focus left"))
    }

    func testUpdateDispatcherRewritesActionAndArg() throws {
        let config = try ConfigParser.parse(text)
        let old = config.binds[1]
        var new = old
        new.dispatcher = .exec("open -a Music")

        let result = ConfigEditor.updateBind(in: text, provenance: provenance(config, 1),
                                             oldBind: old, newBind: new)

        XCTAssertTrue(result.contains("bind = ALT SHIFT, J, exec, open -a Music"))
    }

    func testAddBindInsertsAfterLastBindLine() throws {
        let config = try ConfigParser.parse(text)
        let bind = Keybind(mods: [.alt], key: "F", dispatcher: .fullscreen)

        let result = ConfigEditor.addBind(to: text, bind,
                                          afterLine: config.bindProvenance.last?.line)

        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines[4], "bind = ALT SHIFT, J, movewindow, d")
        XCTAssertEqual(lines[5], "bind = ALT, F, fullscreen")
        // Re-parse round-trip: the new config has one more bind.
        XCTAssertEqual(try ConfigParser.parse(result).binds.count, 3)
    }

    func testAddBindToFileWithNoBindsAppendsAtEnd() throws {
        let bare = "general {\n    gaps_in = 6\n}"
        let bind = Keybind(mods: [.super], key: "SPACE", dispatcher: .workspace(2))

        let result = ConfigEditor.addBind(to: bare, bind, afterLine: nil)

        XCTAssertTrue(result.hasSuffix("bind = SUPER, SPACE, workspace, 2\n"))
        XCTAssertEqual(try ConfigParser.parse(result).binds.count, 1)
    }

    func testDeleteBindRemovesOnlyItsLine() throws {
        let config = try ConfigParser.parse(text)

        let result = ConfigEditor.deleteBind(in: text, provenance: provenance(config, 0))

        XCTAssertFalse(result.contains("movefocus"))
        XCTAssertTrue(result.contains("bind = ALT SHIFT, J, movewindow, d"))
        XCTAssertTrue(result.contains("# my config"))
        XCTAssertEqual(try ConfigParser.parse(result).binds.count, 1)
    }

    func testSetOptionReplacesValueKeepingCommentAndIndent() throws {
        let text = """
        input {
            follow_mouse = 1    # hover focus
        }
        """
        let result = ConfigEditor.setOption(in: text, block: "input",
                                            key: "follow_mouse", value: "0")

        XCTAssertTrue(result.contains("    follow_mouse = 0    # hover focus"))
        XCTAssertFalse(try ConfigParser.parse(result).input.followMouse)
    }

    func testSetOptionAddsKeyToExistingBlock() throws {
        let text = "general {\n    gaps_in = 6\n}"
        let result = ConfigEditor.setOption(in: text, block: "general",
                                            key: "gaps_out", value: "20")

        XCTAssertTrue(result.contains("    gaps_out = 20"))
        XCTAssertEqual(try ConfigParser.parse(result).general.gapsOut, 20)
        XCTAssertEqual(try ConfigParser.parse(result).general.gapsIn, 6)
    }

    func testSetOptionCreatesMissingBlock() throws {
        let text = "bind = ALT, Q, killactive"
        let result = ConfigEditor.setOption(in: text, block: "input",
                                            key: "follow_mouse", value: "0")

        XCTAssertFalse(try ConfigParser.parse(result).input.followMouse)
        XCTAssertEqual(try ConfigParser.parse(result).binds.count, 1)
    }

    func testColorSerializesToRgbaText() {
        XCTAssertEqual(ConfigColor(r: 0x33, g: 0xcc, b: 0xff, a: 0xee).rgbaText,
                       "rgba(33ccffee)")
        XCTAssertEqual(ConfigColor(r: 0, g: 0x0a, b: 0xff, a: 0xff).rgbaText,
                       "rgba(000affff)")
    }

    func testColorRoundTripsThroughParser() throws {
        let color = ConfigColor(r: 0x88, g: 0x39, b: 0xef, a: 0xee)
        let text = ConfigEditor.setOption(in: "general {\n    gaps_in = 6\n}",
                                          block: "general",
                                          key: "col.active_border",
                                          value: color.rgbaText)
        XCTAssertEqual(try ConfigParser.parse(text).general.activeBorder,
                       BorderFill(colors: [color]))
    }

    func testSerializeAllDispatcherShapes() {
        XCTAssertEqual(ConfigEditor.serialize(
            Keybind(mods: [.alt], key: "Q", dispatcher: .killactive)),
            "bind = ALT, Q, killactive")
        XCTAssertEqual(ConfigEditor.serialize(
            Keybind(mods: [.alt, .ctrl], key: "L", dispatcher: .resizeactive(dx: 40, dy: 0))),
            "bind = CTRL ALT, L, resizeactive, 40 0")
        XCTAssertEqual(ConfigEditor.serialize(
            Keybind(mods: [.super, .shift], key: "3", dispatcher: .movetoworkspace(3))),
            "bind = SUPER SHIFT, 3, movetoworkspace, 3")
    }
}
