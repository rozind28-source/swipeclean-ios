import SwiftUI
import Photos
import Observation

enum SwipeDirection {
    case left   // stagedForTrash (Удалить)
    case right  // kept (Оставить)
}

/// ViewModel для экрана свайп-деки SwipeDeckView.
/// Связывает SwipeSessionEngine, ImageCacheManager, VideoPlayerController,
/// MediaExportService, DecisionStore, PhotoLibraryService и HapticsService.
@Observable
@MainActor
final class SwipeDeckViewModel {
    let group: MediaGroup

    // Сервисы и зависимости
    private let engine: SwipeSessionEngine
    private let photoService: PhotoLibraryService
    private let decisionStore: DecisionStore
    let videoController: VideoPlayerController
    private let imageCache: ImageCacheManager
    private let sizeCalculator: MediaSizeCalculator
    private let haptics: HapticsService

    // Реактивное состояние колоды
    private(set) var visibleAssetIDs: [String] = []
    private(set) var isGroupFinished: Bool = false
    private(set) var currentAssetSize: Int64 = 0
    private(set) var isFavorite: Bool = false

    // Анимация свайпа верхней карточки
    var cardOffset: CGSize = .zero

    // Zoom и панорамирование
    var zoomScale: CGFloat = 1.0
    var zoomOffset: CGSize = .zero

    // Экспорт и Share
    private(set) var isExportingForShare: Bool = false
    nonisolated(unsafe) var shareFileURL: URL? = nil
    var showShareSheet: Bool = false

    // Переход в корзину при завершении группы
    var showTrashReview: Bool = false

    // Контейнерные размеры для prefetch
    private var lastContainerSize: CGSize = CGSize(width: 380, height: 580)
    private var lastDisplayScale: CGFloat = 3.0

    init(
        group: MediaGroup,
        photoService: PhotoLibraryService,
        decisionStore: DecisionStore,
        videoController: VideoPlayerController = .shared,
        imageCache: ImageCacheManager = .shared,
        sizeCalculator: MediaSizeCalculator = .shared,
        haptics: HapticsService = .shared
    ) {
        self.group = group
        self.photoService = photoService
        self.decisionStore = decisionStore
        self.videoController = videoController
        self.imageCache = imageCache
        self.sizeCalculator = sizeCalculator
        self.haptics = haptics

        // Отбираем только неразобранные активы группы
        let unreviewed = group.assetIDs.filter { decisionStore.status(for: $0) == nil }
        self.engine = SwipeSessionEngine(assetIDs: unreviewed, startIndex: 0)

        updateVisibleCards()
    }

    deinit {
        if let url = shareFileURL {
            MediaExportService.cleanupExportedFile(at: url)
        }
    }

    // MARK: - Вычисляемые свойства

    var isTransitioning: Bool {
        engine.isTransitioning
    }

    var canUndo: Bool {
        engine.canUndo && !engine.isTransitioning
    }

    var remainingCount: Int {
        engine.remainingCount
    }

    var totalGroupCount: Int {
        group.assetIDs.count
    }

    var reviewedCount: Int {
        totalGroupCount - remainingCount
    }

    var currentAssetID: String? {
        engine.currentAssetID
    }

    var currentAsset: PHAsset? {
        guard let id = currentAssetID else { return nil }
        return photoService.assetsById[id]
    }

    var currentMetadata: MediaMetadata? {
        guard let id = currentAssetID else { return nil }
        return photoService.metadataById[id]
    }

    var groupProgress: GroupProgress {
        decisionStore.progress(for: group)
    }

    var stagedCountInGroup: Int {
        groupProgress.stagedCount
    }

    var stagedBytesInGroup: Int64 {
        groupProgress.stagedBytes
    }

    // MARK: - Жизненный цикл

    func onAppear(containerSize: CGSize, displayScale: CGFloat) {
        self.lastContainerSize = containerSize
        self.lastDisplayScale = displayScale
        updateVisibleCards()
    }

    func onDisappear() {
        videoController.reset()
        // Остановка кэширования для оставшихся
        let assets = visibleAssetIDs.compactMap { photoService.assetsById[$0] }
        let targetSize = ImageCacheManager.targetSize(for: lastContainerSize, displayScale: lastDisplayScale)
        imageCache.stopCaching(for: assets, targetSize: targetSize)
    }

    // MARK: - Свайпы

    /// Свайп верхней карточки с пружинной анимацией и iOS 17 completion-блоком.
    /// КРАСНАЯ ЛИНИЯ: 0 вызовов DispatchQueue.main.asyncAfter.
    func swipe(direction: SwipeDirection, assetID: String) {
        guard !engine.isTransitioning else { return }
        guard let currentID = engine.currentAssetID, currentID == assetID else { return }

        engine.isTransitioning = true

        let decision: DecisionStatus = (direction == .left) ? .stagedForTrash : .kept
        let targetX: CGFloat = (direction == .left) ? -650 : 650

        if direction == .left {
            haptics.impact(.medium)
        } else {
            haptics.impact(.light)
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            self.cardOffset = CGSize(width: targetX, height: self.cardOffset.height)
        } completion: { [weak self] in
            guard let self = self else { return }

            let estimatedSize = self.currentAssetSize
            guard let committedAction = self.engine.commitSwipe(assetID: assetID, decision: decision) else {
                self.cardOffset = .zero
                self.engine.isTransitioning = false
                return
            }
            self.decisionStore.recordDecision(
                assetID: committedAction.assetID,
                status: committedAction.decision,
                estimatedBytes: estimatedSize
            )

            // Сброс физики для следующей карточки
            self.cardOffset = .zero
            self.zoomScale = 1.0
            self.zoomOffset = .zero
            self.engine.isTransitioning = false

            self.updateVisibleCards()
        }
    }

    // MARK: - Откат (Undo)

    func undo() {
        guard canUndo else { return }
        engine.isTransitioning = true

        guard let undoneAction = engine.undoLastSwipe() else {
            engine.isTransitioning = false
            return
        }

        decisionStore.undoDecision(assetID: undoneAction.assetID)
        haptics.impact(.medium)

        // Подготавливаем карточку для плавного залетания обратно
        cardOffset = CGSize(
            width: undoneAction.decision == .stagedForTrash ? -500 : 500,
            height: 0
        )
        zoomScale = 1.0
        zoomOffset = .zero

        updateVisibleCards()

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            self.cardOffset = .zero
        } completion: { [weak self] in
            self?.engine.isTransitioning = false
        }
    }

    // MARK: - Избранное

    func toggleFavorite() {
        guard let currentID = currentAssetID else { return }
        haptics.selection()

        Task { [weak self] in
            let newFav = await self?.photoService.toggleFavorite(for: currentID) ?? false
            self?.isFavorite = newFav
        }
    }

    // MARK: - Поделиться (Share)

    func exportAndShare() {
        guard let currentID = currentAssetID,
              let asset = photoService.assetsById[currentID],
              !isExportingForShare else { return }

        isExportingForShare = true
        haptics.impact(.light)

        Task { [weak self] in
            do {
                let url = try await MediaExportService.shared.exportOriginal(for: asset)
                guard let self = self else {
                    MediaExportService.cleanupExportedFile(at: url)
                    return
                }
                self.shareFileURL = url
                self.showShareSheet = true
                self.isExportingForShare = false
            } catch {
                self?.isExportingForShare = false
            }
        }
    }

    // MARK: - Вспомогательное обновление карточек и видео

    private func updateVisibleCards() {
        self.visibleAssetIDs = engine.visibleAssetIDs(maxCount: 3)
        self.isGroupFinished = engine.isFinished

        if isGroupFinished {
            videoController.reset()
            return
        }

        guard let currentID = engine.currentAssetID,
              let asset = photoService.assetsById[currentID] else {
            videoController.reset()
            return
        }

        self.isFavorite = asset.isFavorite

        // 1. Управление видеоплеером
        if asset.mediaType == .video {
            videoController.loadVideo(for: asset)
        } else {
            videoController.reset()
        }

        // 2. Расчёт размера текущего файла
        Task { [weak self] in
            guard let self = self else { return }
            let size = await self.sizeCalculator.size(for: asset)
            if self.engine.currentAssetID == currentID {
                self.currentAssetSize = size
            }
        }

        // 3. Prefetch следующих 5 изображений и размеров
        let prefetchIDs = engine.prefetchAssetIDs(ahead: 5)
        var prefetchAssets: [PHAsset] = []
        prefetchAssets.reserveCapacity(prefetchIDs.count)

        for id in prefetchIDs {
            if let a = photoService.assetsById[id] {
                prefetchAssets.append(a)
                Task { [weak self] in
                    guard let self = self else { return }
                    _ = await self.sizeCalculator.size(for: a)
                }
            }
        }

        let targetSize = ImageCacheManager.targetSize(for: lastContainerSize, displayScale: lastDisplayScale)
        imageCache.startCaching(for: prefetchAssets, targetSize: targetSize)
    }

    func asset(for id: String) -> PHAsset? {
        photoService.assetsById[id]
    }

    func metadata(for id: String) -> MediaMetadata? {
        photoService.metadataById[id]
    }
}
