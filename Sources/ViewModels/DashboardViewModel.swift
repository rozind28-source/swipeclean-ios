import SwiftUI
import Photos
import Observation

@Observable
@MainActor
final class DashboardViewModel {
    // Выбранный режим группировки
    var selectedMode: CleaningMode = .months

    // Выбранная группа для открытия экрана свайпа (.fullScreenCover)
    var selectedGroup: MediaGroup? = nil

    // Управление модальными окнами
    var showSettings: Bool = false
    var showTrashReview: Bool = false

    // Связанные сервисы и хранилища
    private(set) var photoService: PhotoLibraryService?
    private(set) var decisionStore: DecisionStore?
    private(set) var settings: AppSettings?

    init(
        photoService: PhotoLibraryService? = nil,
        decisionStore: DecisionStore? = nil,
        settings: AppSettings? = nil
    ) {
        self.photoService = photoService
        self.decisionStore = decisionStore
        self.settings = settings
    }

    /// Привязка зависимостей из SwiftUI окружения
    func configure(
        photoService: PhotoLibraryService,
        decisionStore: DecisionStore,
        settings: AppSettings
    ) {
        self.photoService = photoService
        self.decisionStore = decisionStore
        self.settings = settings

        // Связываем завершение индексирования с очисткой удалённых активов в DecisionStore
        photoService.onIndexingFinished = { [weak decisionStore] validIDs in
            decisionStore?.pruneMissingAssets(validIDs: Set(validIDs))
        }
    }

    // MARK: - Вычисляемые свойства для UI

    var isIndexing: Bool {
        photoService?.isIndexing ?? false
    }

    var isLimitedAccess: Bool {
        photoService?.currentStatus == .limited
    }

    /// Фильтрованный список групп с учётом настройки «Скрывать разобранные»
    var filteredGroups: [MediaGroup] {
        guard let photoService else { return [] }
        let groups = photoService.groups(for: selectedMode)
        let hideCompleted = settings?.hideCompletedGroups ?? false

        guard hideCompleted, let decisionStore else {
            return groups
        }

        return groups.filter { group in
            !decisionStore.progress(for: group).isCompleted
        }
    }

    /// Количество файлов, отложенных в корзину
    var stagedCount: Int {
        decisionStore?.stagedCount ?? 0
    }

    /// Общий размер файлов в корзине
    var stagedTotalBytes: Int64 {
        decisionStore?.stagedTotalBytes ?? 0
    }

    /// Глобальная статистика
    var stats: StatsSnapshot {
        decisionStore?.stats ?? .empty
    }

    // MARK: - Операции с группами

    /// Расчёт прогресса группы за O(1) чтением решений из RAM
    func progress(for group: MediaGroup) -> GroupProgress {
        guard let decisionStore else {
            return GroupProgress(totalCount: group.assetIDs.count, keptCount: 0, stagedCount: 0, stagedBytes: 0)
        }
        return decisionStore.progress(for: group)
    }

    /// Получение PHAsset для обложки группы
    func coverAsset(for group: MediaGroup) -> PHAsset? {
        guard let coverID = group.coverAssetID else { return nil }
        return photoService?.assetsById[coverID]
    }

    /// Сброс прогресса группы (удаляет только kept-решения)
    func resetGroupProgress(_ group: MediaGroup) {
        decisionStore?.resetKeptDecisions(for: group.assetIDs)
        HapticsService.shared.notification(.success)
    }

    /// Пересборка подборки «Случайные 50» из неразобранных файлов
    func reshuffleRandom50() {
        guard let photoService, let decisionStore else { return }
        let unreviewed = photoService.allDeletableAssetIDs.filter {
            decisionStore.status(for: $0) == nil
        }
        photoService.reshuffleRandom50(unreviewedIDs: unreviewed)
        HapticsService.shared.impact(.medium)
    }

    // MARK: - Системные действия

    func openLimitedAccessPicker() {
        photoService?.presentLimitedLibraryPicker()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Жизненный цикл

    func onAppear() {
        photoService?.refreshStatus()
        decisionStore?.hydrate()

        if let service = photoService,
           (service.currentStatus == .authorized || service.currentStatus == .limited),
           service.assetsById.isEmpty,
           !service.isIndexing {
            service.startIndexing()
        }
    }
}
