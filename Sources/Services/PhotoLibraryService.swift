import UIKit
import Photos
import Observation

enum DeleteResult: Sendable {
    case success(count: Int)
    case cancelled
    case failure(Error)
}

@Observable
@MainActor
final class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver {
    // MARK: - Публичные свойства состояния

    private(set) var currentStatus: PHAuthorizationStatus
    private(set) var isIndexing: Bool = false

    // Быстрый доступ к ассетам и метаданным в RAM
    private(set) var assetsById: [String: PHAsset] = [:]
    private(set) var metadataById: [String: MediaMetadata] = [:]
    private(set) var allDeletableAssetIDs: [String] = []

    // Сгруппированные коллекции по режимам
    private(set) var monthGroups: [MediaGroup] = []
    private(set) var albumGroups: [MediaGroup] = []
    private(set) var smartGroups: [MediaGroup] = []

    // Флаг подавления повторной загрузки при собственном пакетном удалении
    var suppressReloadDuringBatchDelete: Bool = false

    // Callback завершения фонового сканирования (для DecisionStore.pruneMissingAssets)
    var onIndexingFinished: (([String]) -> Void)?

    // Внутренние задачи для безопасной отмены
    private var indexingTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    // MARK: - Инициализация и деинициализация

    override init() {
        self.currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - Авторизация

    func refreshStatus() {
        self.currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    @discardableResult
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        self.currentStatus = status
        if status == .authorized || status == .limited {
            startIndexing()
        }
        return status
    }

    // MARK: - Получение групп по режиму

    func groups(for mode: CleaningMode) -> [MediaGroup] {
        switch mode {
        case .months:
            return monthGroups
        case .albums:
            return albumGroups
        case .smart:
            return smartGroups
        }
    }

    // MARK: - Фоновое индексирование медиатеки 50 000+ файлов

    func startIndexing() {
        guard currentStatus == .authorized || currentStatus == .limited else {
            self.isIndexing = false
            self.assetsById = [:]
            self.metadataById = [:]
            self.allDeletableAssetIDs = []
            self.monthGroups = []
            self.albumGroups = []
            self.smartGroups = []
            return
        }

        indexingTask?.cancel()
        self.isIndexing = true

        indexingTask = Task.detached(priority: .userInitiated) { [weak self] in
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let allAssetsFetch = PHAsset.fetchAssets(with: fetchOptions)

            var localAssetsById: [String: PHAsset] = [:]
            localAssetsById.reserveCapacity(allAssetsFetch.count)

            var localMetadataById: [String: MediaMetadata] = [:]
            localMetadataById.reserveCapacity(allAssetsFetch.count)

            var deletableIDs: [String] = []
            deletableIDs.reserveCapacity(allAssetsFetch.count)

            // 1. Сбор детерминированного пула активов с canPerform(.delete) == true
            for i in 0..<allAssetsFetch.count {
                if Task.isCancelled { return }
                let asset = allAssetsFetch.object(at: i)

                // КРАСНАЯ ЛИНИЯ: строго отсекаем активы, запрещённые к удалению
                guard asset.canPerform(.delete) else { continue }

                let id = asset.localIdentifier
                localAssetsById[id] = asset
                deletableIDs.append(id)

                let kind: MediaKind
                if asset.mediaType == .video {
                    kind = .video
                } else if asset.mediaSubtypes.contains(.photoScreenshot) {
                    kind = .screenshot
                } else if asset.mediaSubtypes.contains(.photoLive) {
                    kind = .livePhoto
                } else {
                    kind = .photo
                }

                let meta = MediaMetadata(
                    localIdentifier: id,
                    creationDate: asset.creationDate,
                    kind: kind,
                    duration: asset.duration,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    isFavorite: asset.isFavorite
                )
                localMetadataById[id] = meta
            }

            if Task.isCancelled { return }
            let deletableSet = Set(deletableIDs)

            // 2. Группировка 1: «Месяцы» (русская локаль, с заглавной буквы: «Ноябрь 2026»)
            let monthFormatter = DateFormatter()
            monthFormatter.locale = Locale(identifier: "ru_RU")
            monthFormatter.dateFormat = "LLLL yyyy"

            let calendar = Calendar.current
            var monthMap: [String: (title: String, sortKey: Int, assetIDs: [String])] = [:]
            var noDateAssetIDs: [String] = []

            for id in deletableIDs {
                guard let meta = localMetadataById[id] else { continue }
                if let date = meta.creationDate {
                    let year = calendar.component(.year, from: date)
                    let month = calendar.component(.month, from: date)
                    let groupID = "month-\(year)-\(String(format: "%02d", month))"
                    let sortKey = year * 100 + month

                    if monthMap[groupID] == nil {
                        let rawTitle = monthFormatter.string(from: date)
                        let capitalizedTitle = rawTitle.prefix(1).uppercased() + rawTitle.dropFirst()
                        monthMap[groupID] = (title: capitalizedTitle, sortKey: sortKey, assetIDs: [id])
                    } else {
                        monthMap[groupID]?.assetIDs.append(id)
                    }
                } else {
                    noDateAssetIDs.append(id)
                }
            }

            let sortedMonthTuples = monthMap.values.sorted { $0.sortKey > $1.sortKey }
            var computedMonthGroups: [MediaGroup] = []
            computedMonthGroups.reserveCapacity(sortedMonthTuples.count + (noDateAssetIDs.isEmpty ? 0 : 1))

            for item in sortedMonthTuples {
                let year = item.sortKey / 100
                let month = item.sortKey % 100
                let groupID = "month-\(year)-\(String(format: "%02d", month))"
                computedMonthGroups.append(
                    MediaGroup(
                        id: groupID,
                        title: item.title,
                        subtitle: "\(item.assetIDs.count) медиа",
                        mode: .months,
                        assetIDs: item.assetIDs,
                        coverAssetID: item.assetIDs.first
                    )
                )
            }

            if !noDateAssetIDs.isEmpty {
                computedMonthGroups.append(
                    MediaGroup(
                        id: "month-no-date",
                        title: "Без даты",
                        subtitle: "\(noDateAssetIDs.count) медиа",
                        mode: .months,
                        assetIDs: noDateAssetIDs,
                        coverAssetID: noDateAssetIDs.first
                    )
                )
            }

            if Task.isCancelled { return }

            // 3. Группировка 2: «Альбомы» (без .albumCloudShared, без пустых, только deletable)
            var computedAlbumGroups: [MediaGroup] = []

            // 3a. Пользовательские альбомы
            let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            for i in 0..<userAlbums.count {
                let collection = userAlbums.object(at: i)
                // КРАСНАЯ ЛИНИЯ: исключаем общие альбомы .albumCloudShared
                guard collection.assetCollectionSubtype != .albumCloudShared else { continue }

                let assetsInAlbum = PHAsset.fetchAssets(in: collection, options: nil)
                var albumAssetIDs: [String] = []
                albumAssetIDs.reserveCapacity(assetsInAlbum.count)
                for j in 0..<assetsInAlbum.count {
                    let a = assetsInAlbum.object(at: j)
                    if deletableSet.contains(a.localIdentifier) {
                        albumAssetIDs.append(a.localIdentifier)
                    }
                }

                // Пропускаем пустые альбомы
                guard !albumAssetIDs.isEmpty else { continue }

                let title = collection.localizedTitle ?? "Альбом"
                computedAlbumGroups.append(
                    MediaGroup(
                        id: "album-\(collection.localIdentifier)",
                        title: title,
                        subtitle: "\(albumAssetIDs.count) медиа",
                        mode: .albums,
                        assetIDs: albumAssetIDs,
                        coverAssetID: albumAssetIDs.first
                    )
                )
            }

            // 3b. Смарт-альбомы
            let smartSubtypes: [PHAssetCollectionSubtype] = [
                .smartAlbumFavorites,
                .smartAlbumScreenshots,
                .smartAlbumSelfPortraits,
                .smartAlbumPanoramas,
                .smartAlbumLivePhotos,
                .smartAlbumVideos,
                .smartAlbumDepthEffect
            ]

            for subtype in smartSubtypes {
                let smartCollections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
                for i in 0..<smartCollections.count {
                    let collection = smartCollections.object(at: i)
                    let assetsInAlbum = PHAsset.fetchAssets(in: collection, options: nil)
                    var albumAssetIDs: [String] = []
                    albumAssetIDs.reserveCapacity(assetsInAlbum.count)
                    for j in 0..<assetsInAlbum.count {
                        let a = assetsInAlbum.object(at: j)
                        if deletableSet.contains(a.localIdentifier) {
                            albumAssetIDs.append(a.localIdentifier)
                        }
                    }

                    guard !albumAssetIDs.isEmpty else { continue }

                    let title = collection.localizedTitle ?? "Смарт-альбом"
                    computedAlbumGroups.append(
                        MediaGroup(
                            id: "album-smart-\(collection.localIdentifier)",
                            title: title,
                            subtitle: "\(albumAssetIDs.count) медиа",
                            mode: .albums,
                            assetIDs: albumAssetIDs,
                            coverAssetID: albumAssetIDs.first
                        )
                    )
                }
            }

            if Task.isCancelled { return }

            // 4. Группировка 3: «Подборки» (smart)
            var computedSmartGroups: [MediaGroup] = []

            // 4a. «Тяжёлые видео» (мгновенно по estimatedWeightScore в RAM)
            let videoIDs = deletableIDs.filter { localMetadataById[$0]?.kind == .video }
            let sortedVideoIDs = videoIDs.sorted { id1, id2 in
                let score1 = localMetadataById[id1]?.estimatedWeightScore ?? 0
                let score2 = localMetadataById[id2]?.estimatedWeightScore ?? 0
                return score1 > score2
            }

            if !sortedVideoIDs.isEmpty {
                computedSmartGroups.append(
                    MediaGroup(
                        id: "smart-videos",
                        title: "Тяжёлые видео",
                        subtitle: "По размеру и длительности",
                        mode: .smart,
                        assetIDs: sortedVideoIDs,
                        coverAssetID: sortedVideoIDs.first
                    )
                )
            }

            // 4b. «Скриншоты»
            let screenshotIDs = deletableIDs.filter { localMetadataById[$0]?.kind == .screenshot }
            if !screenshotIDs.isEmpty {
                computedSmartGroups.append(
                    MediaGroup(
                        id: "smart-screenshots",
                        title: "Скриншоты",
                        subtitle: "Снимки экрана",
                        mode: .smart,
                        assetIDs: screenshotIDs,
                        coverAssetID: screenshotIDs.first
                    )
                )
            }

            // 4c. «В этот день» (текущий день и месяц прошлых лет, количество >= 1)
            let today = Date()
            let currentDay = calendar.component(.day, from: today)
            let currentMonth = calendar.component(.month, from: today)
            let currentYear = calendar.component(.year, from: today)

            let onThisDayIDs = deletableIDs.filter { id in
                guard let date = localMetadataById[id]?.creationDate else { return false }
                let year = calendar.component(.year, from: date)
                guard year < currentYear else { return false }
                let day = calendar.component(.day, from: date)
                let month = calendar.component(.month, from: date)
                return day == currentDay && month == currentMonth
            }

            if !onThisDayIDs.isEmpty {
                computedSmartGroups.append(
                    MediaGroup(
                        id: "smart-on-this-day",
                        title: "В этот день",
                        subtitle: "Воспоминания прошлых лет",
                        mode: .smart,
                        assetIDs: onThisDayIDs,
                        coverAssetID: onThisDayIDs.first
                    )
                )
            }

            // 4d. «Случайные 50» (до 50 случайных элементов)
            let random50IDs = Array(deletableIDs.shuffled().prefix(50))
            if !random50IDs.isEmpty {
                computedSmartGroups.append(
                    MediaGroup(
                        id: "smart-random-50",
                        title: "Случайные 50",
                        subtitle: "Случайная выборка",
                        mode: .smart,
                        assetIDs: random50IDs,
                        coverAssetID: random50IDs.first
                    )
                )
            }

            if Task.isCancelled { return }

            // 5. Обновление состояния на @MainActor
            await MainActor.run { [weak self] in
                guard let self = self, !Task.isCancelled else { return }
                self.assetsById = localAssetsById
                self.metadataById = localMetadataById
                self.allDeletableAssetIDs = deletableIDs
                self.monthGroups = computedMonthGroups
                self.albumGroups = computedAlbumGroups
                self.smartGroups = computedSmartGroups
                self.isIndexing = false
                self.onIndexingFinished?(deletableIDs)
            }
        }
    }

    // MARK: - Перемешивание «Случайные 50»

    func reshuffleRandom50(unreviewedIDs: [String]? = nil) {
        let pool = unreviewedIDs ?? allDeletableAssetIDs
        let selected = Array(pool.shuffled().prefix(50))
        guard !selected.isEmpty else { return }

        let newGroup = MediaGroup(
            id: "smart-random-50",
            title: "Случайные 50",
            subtitle: "Случайная выборка",
            mode: .smart,
            assetIDs: selected,
            coverAssetID: selected.first
        )

        if let index = smartGroups.firstIndex(where: { $0.id == "smart-random-50" }) {
            smartGroups[index] = newGroup
        } else {
            smartGroups.append(newGroup)
        }
    }

    // MARK: - Пакетное удаление (Batch Delete)

    func deleteAssets(ids: [String]) async -> DeleteResult {
        guard !ids.isEmpty else { return .success(count: 0) }

        // 1. Повторный фетч живых PHAsset и проверка canPerform(.delete)
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var deletableAssets: [PHAsset] = []
        deletableAssets.reserveCapacity(fetched.count)

        for i in 0..<fetched.count {
            let asset = fetched.object(at: i)
            if asset.canPerform(.delete) {
                deletableAssets.append(asset)
            }
        }

        guard !deletableAssets.isEmpty else { return .success(count: 0) }

        // Флаг подавления observer, чтобы не сбросить состояние посреди удаления
        self.suppressReloadDuringBatchDelete = true
        defer {
            self.suppressReloadDuringBatchDelete = false
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(deletableAssets as NSArray)
            }
            // Удаление прошло успешно -> обновляем медиатеку
            startIndexing()
            return .success(count: deletableAssets.count)
        } catch {
            let nsError = error as NSError
            // Пользователь нажал «Отмена» в системном диалоге iOS (PHPhotosError.userCancelled или код 3072)
            if (error as? PHPhotosError)?.code == .userCancelled || nsError.code == 3072 {
                return .cancelled
            }
            return .failure(error)
        }
    }

    // MARK: - Debounced PHPhotoLibraryChangeObserver (600 мс)

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard !self.suppressReloadDuringBatchDelete else { return }

            self.debounceTask?.cancel()
            self.debounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 600_000_000) // 600 мс
                guard !Task.isCancelled, let self = self else { return }
                self.startIndexing()
            }
        }
    }

    // MARK: - Ограниченный доступ (Limited Library Picker)

    func presentLimitedLibraryPicker() {
        guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }
        var topController = rootVC
        while let presented = topController.presentedViewController {
            topController = presented
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: topController)
    }
}
