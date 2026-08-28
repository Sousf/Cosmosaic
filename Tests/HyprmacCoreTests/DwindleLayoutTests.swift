import XCTest
@testable import HyprmacCore

final class DwindleLayoutTests: XCTestCase {

    let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let gaps = Gaps(inner: 10, outer: 20)

    func testSingleWindowFillsScreenMinusOuterGaps() {
        var tree = LayoutTree()
        tree.insert(1, after: nil)

        let frames = tree.frames(in: screen, gaps: gaps)

        XCTAssertEqual(frames, [1: CGRect(x: 20, y: 20, width: 960, height: 560)])
    }

    func testTwoWindowsSplitSideBySideWithInnerGap() {
        var tree = LayoutTree()
        tree.insert(1, after: nil)
        tree.insert(2, after: 1)

        let frames = tree.frames(in: screen, gaps: gaps)

        XCTAssertEqual(frames[1], CGRect(x: 20, y: 20, width: 475, height: 560))
        XCTAssertEqual(frames[2], CGRect(x: 505, y: 20, width: 475, height: 560))
    }

    func testThirdWindowDwindlesIntoVerticalSplit() {
        var tree = LayoutTree()
        tree.insert(1, after: nil)
        tree.insert(2, after: 1)
        tree.insert(3, after: 2)

        let frames = tree.frames(in: screen, gaps: gaps)

        // Window 1 keeps the left half; 2's region (475x560, taller than wide)
        // splits top/bottom between 2 and 3 — the classic dwindle spiral.
        XCTAssertEqual(frames[1], CGRect(x: 20, y: 20, width: 475, height: 560))
        XCTAssertEqual(frames[2], CGRect(x: 505, y: 20, width: 475, height: 275))
        XCTAssertEqual(frames[3], CGRect(x: 505, y: 305, width: 475, height: 275))
    }

    func testRemovingWindowCollapsesSiblingIntoParentSpace() {
        var tree = LayoutTree()
        tree.insert(1, after: nil)
        tree.insert(2, after: 1)
        tree.insert(3, after: 2)

        tree.remove(2)
        let frames = tree.frames(in: screen, gaps: gaps)

        XCTAssertEqual(frames[1], CGRect(x: 20, y: 20, width: 475, height: 560))
        XCTAssertEqual(frames[3], CGRect(x: 505, y: 20, width: 475, height: 560))
        XCTAssertNil(frames[2])
    }

    func testRemovingLastWindowEmptiesTree() {
        var tree = LayoutTree()
        tree.insert(1, after: nil)
        tree.remove(1)

        XCTAssertTrue(tree.isEmpty)
        XCTAssertEqual(tree.frames(in: screen, gaps: gaps), [:])
    }

    func testInsertAfterFocusedSplitsThatLeafNotTheLast() {
        var tree = LayoutTree()
        tree.insert(1, after: nil)
        tree.insert(2, after: 1)
        // Focus back on 1, then open a new window: it must split 1's region.
        tree.insert(3, after: 1)

        let frames = tree.frames(in: screen, gaps: gaps)

        XCTAssertEqual(frames[1], CGRect(x: 20, y: 20, width: 475, height: 275))
        XCTAssertEqual(frames[3], CGRect(x: 20, y: 305, width: 475, height: 275))
        XCTAssertEqual(frames[2], CGRect(x: 505, y: 20, width: 475, height: 560))
    }

    func testWindowsListsAllLeavesInOrder() {
        var tree = LayoutTree()
        tree.insert(1, after: nil)
        tree.insert(2, after: 1)
        tree.insert(3, after: 2)

        XCTAssertEqual(tree.windows, [1, 2, 3])
    }
}
