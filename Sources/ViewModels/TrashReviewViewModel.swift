import Foundation
import Photos
import Observation

@Observable
@MainActor
final class TrashReviewViewModel {
    // MARK: - Свойства контекста

    let group: MediaGroup?
    let groupID: String?

    private let photoService: PhotoLibraryService
    private let decisionStore: DecisionStore
    private let mediaSizeCalculator: MediaSizeCalculator

    // MARK: - Состояние списка активов (неизменяемый исходный порядок для сетки без прыжков)

    private(set) var assetIDs: [String] = []
    private(set) var assetsById: [String: PHAsset] = [:]
    private(set) var metadataById: [String: MediaMetadata] = [:]

    // Множество спасённых ID (переключение in-place)
    var rescuedIDs: Set<String> = []

    // Кэш размеров файлов [localIdentifier: bytes]
    private(set) var assetSizes: [String: Int64] = [:]

    // MARK: - Состояние выполнения операций

    var isDeleting: Bool = false
    var showSessionComplete: Bool = false
    var deletedCountInSession: Int = 0
    var freedBytesInSession: Int64 = 0

    // Ошибки системных запросов
    var errorMessage: String? = nil
    var showError: Bool = false

    // Задача ленивого расчёта размеров
    nonisolated(unsafe) private var sizeCalculationTask: Task<Void, Never>?

    // MARK: - Инициализация и деинициализация

    init(
        group: MediaGroup? = nil,
        groupID: String? = nil,
        photoService: PhotoLibraryService,
        decisionStore: DecisionStore,
        mediaSizeCalculator: MediaSizeCalculator = .shared
    ) {
        self.group = group
        self.groupID = groupID ?? group?.id
        self.photoService = photoService
        self.decisionStore = decisionStore
        self.mediaSizeCalculator = mediaSizeCalculator

        loadItems()
    }

    deinit {
        sizeCalculationTask?.cancel()
    }

    // MARK: - Загрузка элементов корзины

    private func loadItems() {
        // 1. Определение целевого набора ID (глобальная корзина или корзина конкретной группы)
        let targetIDs: [String]
        if let group = self.group {
            targetIDs = group.assetIDs.filter { decisionStore.status(for: $0) == .stagedForTrash }
        } else if let gid = self.groupID,
                  let foundGroup = (photoService.monthGroups + photoService.albumGroups + photoService.smartGroups).first(where: { $0.id == gid }) {
            targetIDs = foundGroup.assetIDs.filter { decisionStore.status(for: $0) == .stagedForTrash }
        } else {
            // Глобальная корзина всей медиатеки
            targetIDs = decisionStore.stagedAssetIDs
        }

        self.assetIDs = targetIDs

        // 2. Сбор PHAsset и MediaMetadata
        var localAssets: [String: PHAsset] = [:]
        var localMetadata: [String: MediaMetadata] = [:]
        var missingAssetIDs: [String] = []

        for id in targetIDs {
            if let asset = photoService.assetsById[id] {
                localAssets[id] = asset
            } else {
                missingAssetIDs.append(id)
            }

            if let meta = photoService.metadataById[id] {
                localMetadata[id] = meta
            }

            // Предварительно заполняем размер из RAM-кэша DecisionStore
            if let size = decisionStore.stagedSizes[id], size > 0 {
                assetSizes[id] = size
            }
        }

        // Если часть ассетов не была в RAM PhotoService — догружаем через PhotoKit
        if !missingAssetIDs.isEmpty {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: missingAssetIDs, options: nil)
            for i in 0..<fetched.count {
                let asset = fetched.object(at: i)
                localAssets[asset.localIdentifier] = asset
            }
        }

        self.assetsById = localAssets
        self.metadataById = localMetadata

        // 3. Асинхронный расчёт недостающих размеров
        startCalculatingSizes()
    }

    // MARK: - Расчёт веса через MediaSizeCalculator

    private func startCalculatingSizes() {
        sizeCalculationTask?.cancel()
        sizeCalculationTask = Task { [weak self] in
            guard let self = self else { return }

            for id in self.assetIDs {
                if Task.isCancelled { break }

                // Проверяем, известен ли уже размер
                if (self.assetSizes[id] ?? 0) <= 0, let asset = self.assetsById[id] {
                    let calculatedSize = await self.mediaSizeCalculator.size(for: asset)
                    if !Task.isCancelled {
                        self.assetSizes[id] = calculatedSize
                        self.decisionStore.setStagedSize(for: id, bytes: calculatedSize)
                    }
                }
            }
        }
    }

    // MARK: - Вычисляемые свойства

    var totalCount: Int {
        assetIDs.count
    }

    var rescuedCount: Int {
        rescuedIDs.count
    }

    var itemsToDeleteCount: Int {
        max(0, totalCount - rescuedCount)
    }

    var areAllRescued: Bool {
        totalCount > 0 && rescuedCount == totalCount
    }

    var idsToDelete: [String] {
        assetIDs.filter { !rescuedIDs.contains($0) }
    }

    var bytesToDelete: Int64 {
        idsToDelete.reduce(0) { total, id in
            total + (assetSizes[id] ?? decisionStore.stagedSizes[id] ?? 0)
        }
    }

    var bytesRescued: Int64 {
        rescuedIDs.reduce(0) { total, id in
            total + (assetSizes[id] ?? decisionStore.stagedSizes[id] ?? 0)
        }
    }

    var totalBytes: Int64 {
        bytesToDelete + bytesRescued
    }

    // MARK: - Пользовательские действия (Спасение и Выбор)

    func toggleRescue(id: String) {
        guard assetIDs.contains(id) else { return }
        if rescuedIDs.contains(id) {
            rescuedIDs.remove(id)
        } else {
            rescuedIDs.insert(id)
        }
        HapticsService.shared.selection()
    }

    func rescueAll() {
        rescuedIDs = Set(assetIDs)
        HapticsService.shared.selection()
    }

    func selectAllForDeletion() {
        rescuedIDs.removeAll()
        HapticsService.shared.selection()
    }

    // MARK: - Сохранение спасённых и закрытие

    func saveRescuedAndDismiss(onDismiss: (() -> Void)? = nil) {
        if !rescuedIDs.isEmpty {
            decisionStore.rescueMultipleFromTrash(assetIDs: Array(rescuedIDs))
            HapticsService.shared.notification(.success)
        }
        onDismiss?()
    }

    // MARK: - Пакетное удаление через PhotoLibraryService

    func executeBatchDelete(onDismiss: (() -> Void)? = nil) async {
        let targetIDs = idsToDelete
        guard !targetIDs.isEmpty else {
            saveRescuedAndDismiss(onDismiss: onDismiss)
            return
        }

        isDeleting = true
        let freedBytes = bytesToDelete

        // Вызов PhotoLibraryService.deleteAssets с системным запросом iOS
        let result = await photoService.deleteAssets(ids: targetIDs)

        switch result {
        case .cancelled:
            // КРАСНАЯ ЛИНИЯ: тихая обработка отмены пользователем iOS.
            // Никаких ошибок не показываем, состояние не сбрасываем, кнопка просто восстанавливается.
            isDeleting = false

        case .success(let count):
            // 1. Переводим спасённые файлы в статус .kept (totalReviewedCount не меняется)
            if !rescuedIDs.isEmpty {
                decisionStore.rescueMultipleFromTrash(assetIDs: Array(rescuedIDs))
            }

            // 2. Фиксируем физическое удаление в DecisionStore (totalDeletedCount += count, totalBytesFreed += freedBytes)
            decisionStore.commitDeleted(assetIDs: targetIDs, freedBytes: freedBytes)

            // 3. Сохраняем итоги сессии для SessionCompleteView
            deletedCountInSession = count
            freedBytesInSession = freedBytes

            isDeleting = false
            HapticsService.shared.notification(.success)
            self.showSessionComplete = true

        case .failure(let error):
            isDeleting = false
            errorMessage = error.localizedDescription
            showError = true
            HapticsService.shared.notification(.error)
        }
    }

    func cancelTasks() {
        sizeCalculationTask?.cancel()
    }
}
