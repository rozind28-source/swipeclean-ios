import Foundation

struct SwipeAction: Equatable, Sendable {
    let assetID: String
    let decision: DecisionStatus
    let index: Int
}

final class SwipeSessionEngine {
    private(set) var assetIDs: [String]
    private(set) var currentIndex: Int
    private(set) var undoStack: [SwipeAction]
    var isTransitioning: Bool

    init(assetIDs: [String], startIndex: Int = 0) {
        self.assetIDs = assetIDs
        self.currentIndex = max(0, min(startIndex, assetIDs.count))
        self.undoStack = []
        self.isTransitioning = false
    }

    var totalCount: Int {
        assetIDs.count
    }

    var remainingCount: Int {
        max(0, totalCount - currentIndex)
    }

    var reviewedCount: Int {
        min(currentIndex, totalCount)
    }

    var isFinished: Bool {
        currentIndex >= totalCount
    }

    var currentAssetID: String? {
        guard currentIndex < assetIDs.count else { return nil }
        return assetIDs[currentIndex]
    }

    var canUndo: Bool {
        !undoStack.isEmpty && currentIndex > 0
    }

    /// Возвращает до maxCount идентификаторов видимых карточек (начиная с currentIndex)
    func visibleAssetIDs(maxCount: Int = 3) -> [String] {
        guard currentIndex < assetIDs.count, maxCount > 0 else { return [] }
        let endIndex = min(currentIndex + maxCount, assetIDs.count)
        return Array(assetIDs[currentIndex..<endIndex])
    }

    /// Возвращает до ahead идентификаторов для предварительной загрузки (начиная с currentIndex)
    func prefetchAssetIDs(ahead: Int = 5) -> [String] {
        guard currentIndex < assetIDs.count, ahead > 0 else { return [] }
        let endIndex = min(currentIndex + ahead, assetIDs.count)
        return Array(assetIDs[currentIndex..<endIndex])
    }

    /// Защищённая фиксация свайпа. Защищает от двойного свайпа и гонок при 120 Гц:
    /// если assetID не совпадает с currentAssetID, свайп отклоняется и возвращается nil.
    @discardableResult
    func commitSwipe(assetID: String, decision: DecisionStatus) -> SwipeAction? {
        guard let current = currentAssetID, current == assetID else {
            return nil
        }
        let action = SwipeAction(assetID: assetID, decision: decision, index: currentIndex)
        undoStack.append(action)
        currentIndex += 1
        return action
    }

    /// Откатывает последний свайп назад на 1 позицию и возвращает действие для отката в хранилище
    @discardableResult
    func undoLastSwipe() -> SwipeAction? {
        guard let lastAction = undoStack.popLast() else {
            return nil
        }
        currentIndex = max(0, currentIndex - 1)
        return lastAction
    }

    /// Сброс сессии
    func reset(with newAssetIDs: [String]? = nil, startIndex: Int = 0) {
        if let newAssetIDs = newAssetIDs {
            self.assetIDs = newAssetIDs
        }
        self.currentIndex = max(0, min(startIndex, assetIDs.count))
        self.undoStack.removeAll()
        self.isTransitioning = false
    }
}
