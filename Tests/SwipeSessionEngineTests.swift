import XCTest
@testable import SwipeClean

final class SwipeSessionEngineTests: XCTestCase {

    func testInitialization() {
        let emptyEngine = SwipeSessionEngine(assetIDs: [])
        XCTAssertEqual(emptyEngine.totalCount, 0)
        XCTAssertEqual(emptyEngine.currentIndex, 0)
        XCTAssertNil(emptyEngine.currentAssetID)
        XCTAssertTrue(emptyEngine.isFinished)
        XCTAssertFalse(emptyEngine.canUndo)
        XCTAssertTrue(emptyEngine.visibleAssetIDs().isEmpty)
        XCTAssertTrue(emptyEngine.prefetchAssetIDs().isEmpty)

        let items = ["id1", "id2", "id3", "id4", "id5"]
        let engine = SwipeSessionEngine(assetIDs: items)
        XCTAssertEqual(engine.totalCount, 5)
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.remainingCount, 5)
        XCTAssertEqual(engine.reviewedCount, 0)
        XCTAssertEqual(engine.currentAssetID, "id1")
        XCTAssertFalse(engine.isFinished)
        XCTAssertFalse(engine.canUndo)
    }

    func testInitializationWithCustomStartIndex() {
        let items = ["id1", "id2", "id3"]
        let engine = SwipeSessionEngine(assetIDs: items, startIndex: 2)
        XCTAssertEqual(engine.currentIndex, 2)
        XCTAssertEqual(engine.currentAssetID, "id3")
        XCTAssertEqual(engine.remainingCount, 1)

        let outOfBoundsEngine = SwipeSessionEngine(assetIDs: items, startIndex: 10)
        XCTAssertEqual(outOfBoundsEngine.currentIndex, 3)
        XCTAssertNil(outOfBoundsEngine.currentAssetID)
        XCTAssertTrue(outOfBoundsEngine.isFinished)
    }

    func testVisibleAssetIDs() {
        let items = ["id1", "id2", "id3", "id4", "id5"]
        let engine = SwipeSessionEngine(assetIDs: items)

        XCTAssertEqual(engine.visibleAssetIDs(maxCount: 3), ["id1", "id2", "id3"])
        XCTAssertEqual(engine.visibleAssetIDs(maxCount: 2), ["id1", "id2"])

        engine.commitSwipe(assetID: "id1", decision: .kept)
        XCTAssertEqual(engine.visibleAssetIDs(maxCount: 3), ["id2", "id3", "id4"])

        engine.commitSwipe(assetID: "id2", decision: .stagedForTrash)
        engine.commitSwipe(assetID: "id3", decision: .kept)
        engine.commitSwipe(assetID: "id4", decision: .stagedForTrash)
        XCTAssertEqual(engine.visibleAssetIDs(maxCount: 3), ["id5"])

        engine.commitSwipe(assetID: "id5", decision: .kept)
        XCTAssertTrue(engine.visibleAssetIDs(maxCount: 3).isEmpty)
    }

    func testPrefetchAssetIDs() {
        let items = (1...10).map { "photo-\($0)" }
        let engine = SwipeSessionEngine(assetIDs: items)

        XCTAssertEqual(engine.prefetchAssetIDs(ahead: 5), ["photo-1", "photo-2", "photo-3", "photo-4", "photo-5"])

        engine.commitSwipe(assetID: "photo-1", decision: .kept)
        engine.commitSwipe(assetID: "photo-2", decision: .stagedForTrash)
        engine.commitSwipe(assetID: "photo-3", decision: .kept)

        XCTAssertEqual(engine.prefetchAssetIDs(ahead: 5), ["photo-4", "photo-5", "photo-6", "photo-7", "photo-8"])

        let nearEndEngine = SwipeSessionEngine(assetIDs: items, startIndex: 8)
        XCTAssertEqual(nearEndEngine.prefetchAssetIDs(ahead: 5), ["photo-9", "photo-10"])
    }

    func testCommitSwipeKeptAndStagedForTrash() {
        let items = ["id1", "id2"]
        let engine = SwipeSessionEngine(assetIDs: items)

        let action1 = engine.commitSwipe(assetID: "id1", decision: .kept)
        XCTAssertNotNil(action1)
        XCTAssertEqual(action1?.assetID, "id1")
        XCTAssertEqual(action1?.decision, .kept)
        XCTAssertEqual(action1?.index, 0)
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.currentAssetID, "id2")
        XCTAssertTrue(engine.canUndo)

        let action2 = engine.commitSwipe(assetID: "id2", decision: .stagedForTrash)
        XCTAssertNotNil(action2)
        XCTAssertEqual(action2?.assetID, "id2")
        XCTAssertEqual(action2?.decision, .stagedForTrash)
        XCTAssertEqual(action2?.index, 1)
        XCTAssertEqual(engine.currentIndex, 2)
        XCTAssertNil(engine.currentAssetID)
        XCTAssertTrue(engine.isFinished)
    }

    func testDoubleSwipeProtection() {
        let items = ["id1", "id2", "id3"]
        let engine = SwipeSessionEngine(assetIDs: items)

        // 1. Trying to commit an ID that is not current
        let invalidAction = engine.commitSwipe(assetID: "id2", decision: .kept)
        XCTAssertNil(invalidAction)
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.currentAssetID, "id1")

        // 2. Commit id1 properly
        let validAction = engine.commitSwipe(assetID: "id1", decision: .kept)
        XCTAssertNotNil(validAction)
        XCTAssertEqual(engine.currentIndex, 1)

        // 3. Immediately trying to commit id1 again (simulating delayed second touch / 120Hz gesture burst)
        let doubleSwipeAction = engine.commitSwipe(assetID: "id1", decision: .stagedForTrash)
        XCTAssertNil(doubleSwipeAction)
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.currentAssetID, "id2")
    }

    func testUndoLastSwipe() {
        let items = ["id1", "id2"]
        let engine = SwipeSessionEngine(assetIDs: items)

        // Undo on empty stack should return nil
        XCTAssertNil(engine.undoLastSwipe())

        engine.commitSwipe(assetID: "id1", decision: .stagedForTrash)
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.currentAssetID, "id2")

        let undone = engine.undoLastSwipe()
        XCTAssertNotNil(undone)
        XCTAssertEqual(undone?.assetID, "id1")
        XCTAssertEqual(undone?.decision, .stagedForTrash)
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.currentAssetID, "id1")
        XCTAssertFalse(engine.canUndo)

        // Can re-commit after undo
        let recommit = engine.commitSwipe(assetID: "id1", decision: .kept)
        XCTAssertNotNil(recommit)
        XCTAssertEqual(recommit?.decision, .kept)
        XCTAssertEqual(engine.currentIndex, 1)
    }

    func testMultipleSwipesAndUndos() {
        let items = ["id1", "id2", "id3", "id4"]
        let engine = SwipeSessionEngine(assetIDs: items)

        engine.commitSwipe(assetID: "id1", decision: .kept)
        engine.commitSwipe(assetID: "id2", decision: .stagedForTrash)
        engine.commitSwipe(assetID: "id3", decision: .kept)
        XCTAssertEqual(engine.currentIndex, 3)
        XCTAssertEqual(engine.undoStack.count, 3)

        let undo3 = engine.undoLastSwipe()
        XCTAssertEqual(undo3?.assetID, "id3")
        XCTAssertEqual(engine.currentIndex, 2)

        let undo2 = engine.undoLastSwipe()
        XCTAssertEqual(undo2?.assetID, "id2")
        XCTAssertEqual(engine.currentIndex, 1)

        let undo1 = engine.undoLastSwipe()
        XCTAssertEqual(undo1?.assetID, "id1")
        XCTAssertEqual(engine.currentIndex, 0)

        XCTAssertNil(engine.undoLastSwipe())
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.currentAssetID, "id1")
    }

    func testReset() {
        let items = ["id1", "id2"]
        let engine = SwipeSessionEngine(assetIDs: items)
        engine.isTransitioning = true
        engine.commitSwipe(assetID: "id1", decision: .kept)

        engine.reset()
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertFalse(engine.isTransitioning)
        XCTAssertTrue(engine.undoStack.isEmpty)
        XCTAssertEqual(engine.currentAssetID, "id1")

        let newItems = ["newA", "newB", "newC"]
        engine.reset(with: newItems, startIndex: 1)
        XCTAssertEqual(engine.totalCount, 3)
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.currentAssetID, "newB")
    }

    func testTransitioningFlag() {
        let engine = SwipeSessionEngine(assetIDs: ["id1"])
        XCTAssertFalse(engine.isTransitioning)
        engine.isTransitioning = true
        XCTAssertTrue(engine.isTransitioning)
    }
}
