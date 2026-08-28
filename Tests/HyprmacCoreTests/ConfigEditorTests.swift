import XCTest
@testable import HyprmacCore

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
