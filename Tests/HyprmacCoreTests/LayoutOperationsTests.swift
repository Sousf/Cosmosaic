import XCTest
@testable import HyprmacCore

/// Frames here use screen coordinates with top-left origin and y increasing
/// downward (the AX/CGWindow convention): "up" means smaller y.
final class LayoutOperationsTests: XCTestCase {

    let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let gaps = Gaps(inner: 10, outer: 20)

    private func threeWindowTree() -> LayoutTree {
        var tree = LayoutTree()
        tree.insert(1, after: nil)
        tree.insert(2, after: 1)
        tree.insert(3, after: 2)
        return tree
    }

    // MARK: neighbor

    func testNeighborRightPicksTopmostOnTie() {
        let frames = threeWindowTree().frames(in: screen, gaps: gaps)
        // 2 and 3 both border 1's right edge with equal overlap; topmost wins.
        XCTAssertEqual(LayoutGeometry.neighbor(of: 1, direction: .right, in: frames), 2)
    }

    func testNeighborDownAndUp() {
        let frames = threeWindowTree().frames(in: screen, gaps: gaps)
        XCTAssertEqual(LayoutGeometry.neighbor(of: 2, direction: .down, in: frames), 3)
        XCTAssertEqual(LayoutGeometry.neighbor(of: 3, direction: .up, in: frames), 2)
    }

    func testNeighborLeftFromStackedWindows() {
        let frames = threeWindowTree().frames(in: screen, gaps: gaps)
        XCTAssertEqual(LayoutGeometry.neighbor(of: 2, direction: .left, in: frames), 1)
        XCTAssertEqual(LayoutGeometry.neighbor(of: 3, direction: .left, in: frames), 1)
    }

    func testNeighborNoneAtScreenEdge() {
        let frames = threeWindowTree().frames(in: screen, gaps: gaps)
        XCTAssertNil(LayoutGeometry.neighbor(of: 1, direction: .left, in: frames))
        XCTAssertNil(LayoutGeometry.neighbor(of: 1, direction: .up, in: frames))
    }

    // MARK: swap

    func testSwapExchangesWindowPositions() {
        var tree = threeWindowTree()
        let before = tree.frames(in: screen, gaps: gaps)

        tree.swap(1, 3)
        let after = tree.frames(in: screen, gaps: gaps)

        XCTAssertEqual(after[3], before[1])
        XCTAssertEqual(after[1], before[3])
        XCTAssertEqual(after[2], before[2])
    }

    // MARK: resize

    func testResizeGrowsFirstWindowByPixels() {
        var tree = LayoutTree()
        tree.insert(1, after: nil)
        tree.insert(2, after: 1)

        tree.resize(1, dx: 100, dy: 0, in: screen, gaps: gaps)
        let frames = tree.frames(in: screen, gaps: gaps)

        XCTAssertEqual(frames[1]?.width, 575)
        XCTAssertEqual(frames[2]?.width, 375)
    }

    func testResizeGrowsSecondWindowByShrinkingFirst() {
        var tree = LayoutTree()
        tree.insert(1, after: nil)
        tree.insert(2, after: 1)

        tree.resize(2, dx: 100, dy: 0, in: screen, gaps: gaps)
        let frames = tree.frames(in: screen, gaps: gaps)

        XCTAssertEqual(frames[2]?.width, 575)
        XCTAssertEqual(frames[1]?.width, 375)
    }

    func testResizeVerticalAdjustsStackedPair() {
        var tree = threeWindowTree()

        tree.resize(2, dx: 0, dy: 50, in: screen, gaps: gaps)
        let frames = tree.frames(in: screen, gaps: gaps)

        XCTAssertEqual(frames[2]?.height, 325)
        XCTAssertEqual(frames[3]?.height, 225)
    }

    func testResizeClampsRatio() {
        var tree = LayoutTree()
        tree.insert(1, after: nil)
        tree.insert(2, after: 1)

        tree.resize(1, dx: 10_000, dy: 0, in: screen, gaps: gaps)
        let frames = tree.frames(in: screen, gaps: gaps)

        // Ratio clamps at 0.9: 950 * 0.9 = 855.
        XCTAssertEqual(frames[1]?.width, 855)
    }
}
