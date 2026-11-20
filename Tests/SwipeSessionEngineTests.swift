import XCTest
@testable import SwipeClean

final class SwipeSessionEngineTests: XCTestCase {

    // MARK: - Базовая инициализация и граничные индексы

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

    // MARK: - Граничные случаи: Пустая очередь

    func testEmptyQueueDetailed() {
        let engine = SwipeSessionEngine(assetIDs: [])

        XCTAssertEqual(engine.totalCount, 0)
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.remainingCount, 0)
        XCTAssertEqual(engine.reviewedCount, 0)
        XCTAssertNil(engine.currentAssetID)
        XCTAssertTrue(engine.isFinished)
        XCTAssertFalse(engine.canUndo)

        XCTAssertTrue(engine.visibleAssetIDs(maxCount: 3).isEmpty)
        XCTAssertTrue(engine.visibleAssetIDs(maxCount: 0).isEmpty)
        XCTAssertTrue(engine.prefetchAssetIDs(ahead: 5).isEmpty)
        XCTAssertTrue(engine.prefetchAssetIDs(ahead: 0).isEmpty)

        // Попытка свайпа в пустой очереди возвращает nil
        let swipeKept = engine.commitSwipe(assetID: "nonexistent", decision: .kept)
        XCTAssertNil(swipeKept)

        let swipeTrash = engine.commitSwipe(assetID: "nonexistent", decision: .stagedForTrash)
        XCTAssertNil(swipeTrash)

        // Undo в пустой очереди возвращает nil
        XCTAssertNil(engine.undoLastSwipe())
        XCTAssertEqual(engine.currentIndex, 0)

        // Сброс пустой очереди
        engine.reset()
        XCTAssertEqual(engine.totalCount, 0)
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertTrue(engine.isFinished)
    }

    // MARK: - Видимые карточки и упреждающая загрузка (Prefetch)

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

    // MARK: - Свайпы: Kept и StagedForTrash

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

    // MARK: - Защита от двойного свайпа и гонок при 120 Гц

    func testDoubleSwipeProtection() {
        let items = ["id1", "id2", "id3"]
        let engine = SwipeSessionEngine(assetIDs: items)

        // 1. Попытка свайпнуть ID, который не является текущим
        let invalidAction = engine.commitSwipe(assetID: "id2", decision: .kept)
        XCTAssertNil(invalidAction)
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.currentAssetID, "id1")

        // 2. Валидный свайп id1
        let validAction = engine.commitSwipe(assetID: "id1", decision: .kept)
        XCTAssertNotNil(validAction)
        XCTAssertEqual(engine.currentIndex, 1)

        // 3. Мгновенная повторная попытка свайпнуть id1 (эмуляция дребезга тача 120 Гц)
        let doubleSwipeAction = engine.commitSwipe(assetID: "id1", decision: .stagedForTrash)
        XCTAssertNil(doubleSwipeAction)
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.currentAssetID, "id2")
    }

    func testDoubleSwipeProtectionExtended() {
        let items = ["a", "b", "c"]
        let engine = SwipeSessionEngine(assetIDs: items)

        // Свайп несуществующего актива
        XCTAssertNil(engine.commitSwipe(assetID: "unknown", decision: .kept))
        XCTAssertEqual(engine.currentIndex, 0)

        // Первый валидный свайп
        let a = engine.commitSwipe(assetID: "a", decision: .kept)
        XCTAssertEqual(a?.assetID, "a")

        // 5 подряд повторных попыток свайпнуть 'a' отклоняются
        for _ in 0..<5 {
            XCTAssertNil(engine.commitSwipe(assetID: "a", decision: .stagedForTrash))
        }
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.currentAssetID, "b")

        // Завершаем оставшиеся
        XCTAssertNotNil(engine.commitSwipe(assetID: "b", decision: .stagedForTrash))
        XCTAssertNotNil(engine.commitSwipe(assetID: "c", decision: .kept))
        XCTAssertTrue(engine.isFinished)

        // Попытка свайпнуть после завершения сессии
        XCTAssertNil(engine.commitSwipe(assetID: "c", decision: .kept))
        XCTAssertNil(engine.commitSwipe(assetID: "any", decision: .stagedForTrash))
    }

    // MARK: - Undo на 0-м элементе и откат

    func testUndoLastSwipe() {
        let items = ["id1", "id2"]
        let engine = SwipeSessionEngine(assetIDs: items)

        // Undo на пустом стеке должен вернуть nil
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

        // Возможность повторного свайпа после undo
        let recommit = engine.commitSwipe(assetID: "id1", decision: .kept)
        XCTAssertNotNil(recommit)
        XCTAssertEqual(recommit?.decision, .kept)
        XCTAssertEqual(engine.currentIndex, 1)
    }

    func testUndoAtZeroIndexExplicit() {
        let items = ["first", "second"]
        let engine = SwipeSessionEngine(assetIDs: items)

        // На 0-м элементе до свайпов Undo невозможен
        XCTAssertFalse(engine.canUndo)
        XCTAssertNil(engine.undoLastSwipe())
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.currentAssetID, "first")

        // Повторные вызовы undo на 0-м элементе безопасны
        XCTAssertNil(engine.undoLastSwipe())
        XCTAssertNil(engine.undoLastSwipe())
        XCTAssertEqual(engine.currentIndex, 0)

        // Свайпаем 1 элемент и откатываем
        XCTAssertNotNil(engine.commitSwipe(assetID: "first", decision: .kept))
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertTrue(engine.canUndo)

        let undone = engine.undoLastSwipe()
        XCTAssertEqual(undone?.assetID, "first")
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertFalse(engine.canUndo)

        // Повторный вызов после возврата на 0-й элемент
        XCTAssertNil(engine.undoLastSwipe())
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.currentAssetID, "first")
    }

    // MARK: - Множественный Undo до начала сессии

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

    func testMultipleUndosBackToBeginning() {
        let count = 10
        let items = (0..<count).map { "item-\($0)" }
        let engine = SwipeSessionEngine(assetIDs: items)

        // Проходим всю очередь из 10 элементов
        for i in 0..<count {
            let decision: DecisionStatus = (i % 2 == 0) ? .kept : .stagedForTrash
            let action = engine.commitSwipe(assetID: items[i], decision: decision)
            XCTAssertNotNil(action)
            XCTAssertEqual(action?.index, i)
        }

        XCTAssertEqual(engine.currentIndex, count)
        XCTAssertEqual(engine.remainingCount, 0)
        XCTAssertEqual(engine.reviewedCount, count)
        XCTAssertTrue(engine.isFinished)
        XCTAssertTrue(engine.canUndo)

        // Откатываем все 10 действий подряд до самого начала
        for expectedIndex in stride(from: count - 1, through: 0, by: -1) {
            XCTAssertTrue(engine.canUndo)
            let action = engine.undoLastSwipe()
            XCTAssertNotNil(action)
            XCTAssertEqual(action?.index, expectedIndex)
            XCTAssertEqual(action?.assetID, items[expectedIndex])
            XCTAssertEqual(engine.currentIndex, expectedIndex)
        }

        // Мы вернулись в самое начало
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.currentAssetID, "item-0")
        XCTAssertFalse(engine.canUndo)
        XCTAssertFalse(engine.isFinished)
        XCTAssertEqual(engine.remainingCount, count)
        XCTAssertEqual(engine.reviewedCount, 0)

        // 11-й Undo возвращает nil и не ломает состояние
        XCTAssertNil(engine.undoLastSwipe())
        XCTAssertEqual(engine.currentIndex, 0)

        // Повторный свайп с 0-го индекса проходит успешно
        let reAction = engine.commitSwipe(assetID: "item-0", decision: .kept)
        XCTAssertNotNil(reAction)
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.currentAssetID, "item-1")
    }

    // MARK: - Расчёт GroupProgress (total, reviewed, completionRatio, isCompleted)

    func testGroupProgressCalculations() {
        // 1. Пустая группа
        let emptyProgress = GroupProgress(totalCount: 0, keptCount: 0, stagedCount: 0, stagedBytes: 0)
        XCTAssertEqual(emptyProgress.totalCount, 0)
        XCTAssertEqual(emptyProgress.reviewedCount, 0)
        XCTAssertEqual(emptyProgress.remainingCount, 0)
        XCTAssertEqual(emptyProgress.completionRatio, 1.0)
        XCTAssertFalse(emptyProgress.isCompleted, "Пустая группа не считается завершённой (totalCount == 0)")

        // 2. Частично разобранная группа (50%)
        let partialProgress = GroupProgress(
            totalCount: 20,
            keptCount: 6,
            stagedCount: 4,
            stagedBytes: 15_728_640 // 15 МБ
        )
        XCTAssertEqual(partialProgress.totalCount, 20)
        XCTAssertEqual(partialProgress.keptCount, 6)
        XCTAssertEqual(partialProgress.stagedCount, 4)
        XCTAssertEqual(partialProgress.reviewedCount, 10)
        XCTAssertEqual(partialProgress.remainingCount, 10)
        XCTAssertEqual(partialProgress.completionRatio, 0.5, accuracy: 0.001)
        XCTAssertFalse(partialProgress.isCompleted)
        XCTAssertEqual(partialProgress.stagedBytes, 15_728_640)

        // 3. Полностью разобранная группа (100% - все оставлены)
        let allKeptProgress = GroupProgress(
            totalCount: 15,
            keptCount: 15,
            stagedCount: 0,
            stagedBytes: 0
        )
        XCTAssertEqual(allKeptProgress.totalCount, 15)
        XCTAssertEqual(allKeptProgress.reviewedCount, 15)
        XCTAssertEqual(allKeptProgress.remainingCount, 0)
        XCTAssertEqual(allKeptProgress.completionRatio, 1.0, accuracy: 0.001)
        XCTAssertTrue(allKeptProgress.isCompleted)

        // 4. Полностью разобранная группа (100% - все в корзине)
        let allStagedProgress = GroupProgress(
            totalCount: 8,
            keptCount: 0,
            stagedCount: 8,
            stagedBytes: 42_000_000
        )
        XCTAssertEqual(allStagedProgress.totalCount, 8)
        XCTAssertEqual(allStagedProgress.reviewedCount, 8)
        XCTAssertEqual(allStagedProgress.remainingCount, 0)
        XCTAssertEqual(allStagedProgress.completionRatio, 1.0, accuracy: 0.001)
        XCTAssertTrue(allStagedProgress.isCompleted)
        XCTAssertEqual(allStagedProgress.stagedBytes, 42_000_000)

        // 5. Полностью разобранная группа (смешанный результат: 7 kept + 5 staged)
        let mixedCompleteProgress = GroupProgress(
            totalCount: 12,
            keptCount: 7,
            stagedCount: 5,
            stagedBytes: 8_388_608
        )
        XCTAssertEqual(mixedCompleteProgress.totalCount, 12)
        XCTAssertEqual(mixedCompleteProgress.reviewedCount, 12)
        XCTAssertEqual(mixedCompleteProgress.remainingCount, 0)
        XCTAssertEqual(mixedCompleteProgress.completionRatio, 1.0, accuracy: 0.001)
        XCTAssertTrue(mixedCompleteProgress.isCompleted)
        XCTAssertEqual(mixedCompleteProgress.stagedBytes, 8_388_608)

        // 6. Не начатая группа (0 reviewed)
        let untouchedProgress = GroupProgress(
            totalCount: 50,
            keptCount: 0,
            stagedCount: 0,
            stagedBytes: 0
        )
        XCTAssertEqual(untouchedProgress.reviewedCount, 0)
        XCTAssertEqual(untouchedProgress.remainingCount, 50)
        XCTAssertEqual(untouchedProgress.completionRatio, 0.0, accuracy: 0.001)
        XCTAssertFalse(untouchedProgress.isCompleted)
    }

    // MARK: - Сброс и флаг анимации перехода

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
