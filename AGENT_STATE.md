# Журнал состояния ИИ-агента: SwipeClean (`AGENT_STATE.md`)

*Дата последнего обновления:* 2026-11-20  
*Текущий этап:* **Фаза 2 завершена (PhotoKit-индексирование, кэш, дашборд)**  
*Следующий этап:* **Фаза 3 (Свайп-дека, Zoom, Видеоплеер и Share)**  

---

## 1. Архитектурный обзор проекта

SwipeClean — нативное iOS-приложение для быстрой и безопасной очистки медиатеки свайпами (аналог *Sponge — Gallery Cleaner*).  
Приложение спроектировано по принципам Clean Architecture + Swift Concurrency + SwiftData без единой сторонней зависимости (0 пакетов SPM/CocoaPods).

### Ключевые архитектурные решения:
1. **100% Offline & Private:** Никакой сети, телеметрии, аналитики или сторонних SDK. Доступ только к системному PhotoKit.
2. **Двухэтапная корзина:** Свайп влево переводит актив в `stagedForTrash` (внутренний буфер). Физическое удаление запускается только с экрана корзины через транзакцию `PHAssetChangeRequest.deleteAssets` с перемещением в системный альбом «Недавно удалённые» на 30 дней.
3. **Производительность 60/120 Гц на 50 000+ файлах:**
   - Фоновое сканирование медиатеки в `Task.detached(priority: .userInitiated)` с мгновенным отсечением не подлежащих удалению файлов (`asset.canPerform(.delete) == true`).
   - RAM-кэш решений в `DecisionStore` (`[String: DecisionStatus]`) со сложностью чтения $O(1)$.
   - Чистый доменный движок свайпов `SwipeSessionEngine` со стеком Undo, окном видимости (3 карточки) и prefetch (5 карточек).
   - Защита от двойного свайпа и гонок при 120 Гц (`commitSwipe` валидирует `assetID == currentAssetID`).
   - Оппортунистический кэш картинок `ImageCacheManager` на базе `PHCachingImageManager` с безопасным потолком 2048px по длинной стороне и прямым callback-замыканием (без опасного `CheckedContinuation`).
   - Потокобезопасный `actor MediaSizeCalculator` с $O(1)$ RAM-кэшем `[String: Int64]` и безопасным извлечением размера через `responds(to: NSSelectorFromString("fileSize"))` и `NSNumber`.
4. **Безопасность SwiftData:** `ModelContainer` инициализируется с `do/catch` и безопасным fallback на in-memory контейнер при сбоях диска или миграций (без `fatalError` и без `try!`).
5. **Debounced Observer медиатеки:** `PHPhotoLibraryChangeObserver` с debounce 600 мс и флагом `suppressReloadDuringBatchDelete` для предотвращения ложных перезагрузок во время собственных транзакций удаления.

---

## 2. Статус фаз разработки

| Фаза | Название | Статус | Комментарий |
|---|---|---|---|
| **Фаза 1** | **Каркас, XcodeGen, CI, Контракты, Тесты, Права** | ✅ **ЗАВЕРШЕНА & ВЕРИФИЦИРОВАНА** | Создан `project.yml`, workflow CI `macos-26`, генератор иконки, каталоги ассетов, все доменные контракты, `SwipeSessionEngine` с XCTest, `DecisionStore`, `PhotoLibraryService`, `AppSettings`, `PermissionView`, `DashboardView`. Пройден статический аудит. CI успешно собирает `.ipa`. |
| **Фаза 2** | **PhotoKit-индексирование, Кэш и Главный экран** | ✅ **ЗАВЕРШЕНА** | Реализовано фоновое индексирование в `Task.detached` с фильтром `canPerform(.delete)`, 3 режима группировки (Месяцы с русской локалью «Ноябрь 2026», Альбомы без `.albumCloudShared`, Подборки: «Тяжёлые видео» по `estimatedWeightScore`, «Скриншоты», «В этот день», «Случайные 50»), debounced observer (600 мс), пакетное удаление `deleteAssets(ids:)` с перехватом `userCancelled`, `ImageCacheManager` с потолком 2048px и opportunistic callbacks, `actor MediaSizeCalculator`, `@Observable` `DashboardViewModel`, полноценный `DashboardView`, компонент `GroupRowCard`, `SettingsView`, плейсхолдеры для `.fullScreenCover`. Пройден статический аудит 0 нарушений. |
| **Фаза 3** | Свайп-дека, Zoom, Видеоплеер и Share | ⏳ СЛЕДУЮЩАЯ | Будет реализован `VideoPlayerController` (строго один `AVPlayer` на сессию), `LoopingVideoView`, `MediaExportService`, `ActivityShareSheet`, `SwipeDeckViewModel`, `SwipeDeckView` (в `.fullScreenCover`) и `SwipeCardView` (Pinch/Double-tap Zoom, метаданные с секундами, Undo, Избранное, Share, prefetch 5 вперёд). |
| **Фаза 4** | Корзина без прыжков, Удаление, Итоги, Настройки | ⏳ ОЖИДАЕТ | Будет реализован `TrashReviewViewModel`, `TrashReviewView` (in-place спасение без прыжков сетки), `SessionCompleteView`, расширение тестов. |
| **Фаза 5** | Финальный инженерный аудит и релизная полировка | ⏳ ОЖИДАЕТ | Сквозной аудит утечек памяти, проверка крайних случаев (0 медиа, оффлайн iCloud, отмена удаления), проверка 0 нарушений красных линий. |

---

## 3. Реестр созданных и обновлённых файлов (Фазы 1 и 2)

### Конфигурация и CI:
1. `project.yml` — спецификация XcodeGen (iOS 17.0, `SWIFT_VERSION: "5.0"`, `SWIFT_STRICT_CONCURRENCY: minimal`, bundle ID `com.swipeclean.gallery`, автогенерация `Info.plist` с `NSPhotoLibraryUsageDescription`).
2. `.github/workflows/build-ios.yml` — GitHub Actions workflow на раннере `macos-26` (генерация иконки, генерация проекта, симуляторные юнит-тесты, сборка Release `.app`, упаковка unsigned `.ipa`).
3. `Scripts/generate_icon.swift` — автономный скрипт на CoreGraphics / AppKit, генерирующий 1024×1024 иконку `AppIcon-1024.png` и обновляющий `Contents.json`.

### Каталог ресурсов (`Sources/Resources/Assets.xcassets/`):
4. `Assets.xcassets/Contents.json` — корень каталога ассетов.
5. `Assets.xcassets/AppIcon.appiconset/Contents.json` — манифест иконки приложения.
6. `Assets.xcassets/AccentColor.colorset/Contents.json` — акцентный цвет `#6366F1` (индиго).

### Доменный слой (`Sources/Domain/`):
7. `Sources/Domain/DecisionStatus.swift` — `enum DecisionStatus: String, Codable, Sendable { case kept, stagedForTrash }`.
8. `Sources/Domain/CleaningMode.swift` — `enum CleaningMode: String, CaseIterable, Identifiable, Sendable { case months, albums, smart }`.
9. `Sources/Domain/MediaMetadata.swift` — `enum MediaKind: String, Sendable`, `struct MediaMetadata: Identifiable, Hashable, Sendable` с `estimatedWeightScore`.
10. `Sources/Domain/MediaGroup.swift` — `struct MediaGroup: Identifiable, Hashable, Sendable`.
11. `Sources/Domain/GroupProgress.swift` — `struct GroupProgress: Equatable, Sendable`.
12. `Sources/Domain/ByteFormatter.swift` — форматирование байт с использованием `ByteCountFormatter` ("0 Б", "3.8 МБ", "1.2 ГБ").
13. `Sources/Domain/SwipeSessionEngine.swift` — чистый Swift движок сессии со стеком Undo, валидацией двойного свайпа, `visibleAssetIDs(maxCount: 3)`, `prefetchAssetIDs(ahead: 5)`.

### Тестовый слой (`Tests/`):
14. `Tests/SwipeSessionEngineTests.swift` — XCTest покрытие движка `SwipeSessionEngine`: инициализация, граничные индексы, видимые карточки, prefetch, свайпы kept/trash, защита от двойного свайпа, множественные undo, сброс сессии.

### Слой персистентности (`Sources/Persistence/`):
15. `Sources/Persistence/MediaDecisionRecord.swift` — `@Model` SwiftData для хранения решений по активам с примитивным полем `statusRaw: String` для безопасных `#Predicate`.
16. `Sources/Persistence/CleaningStatsRecord.swift` — `@Model` SwiftData + доменная структура `StatsSnapshot: Equatable, Sendable`.
17. `Sources/Persistence/DecisionStore.swift` — `@Observable @MainActor` RAM-кэш со сложностью $O(1)$, методами `hydrate()`, `recordDecision()`, `undoDecision()`, `rescueFromTrash()`, `commitDeleted()`, `resetKeptDecisions()`, `pruneMissingAssets()`.

### Сервисы (`Sources/Services/`):
18. `Sources/Services/HapticsService.swift` — тактильная отдача (UIImpact/UINotification/UISelection) с проверкой флага `AppSettings.shared.hapticsEnabled`.
19. `Sources/Services/PhotoLibraryService.swift` — **[Обновлено в Фазе 2]** Полное фоновое сканирование в `Task.detached`, фильтр `canPerform(.delete)`, 3 режима группировки (Месяцы «Ноябрь 2026», Альбомы без cloud-shared, Подборки: Тяжёлые видео, Скриншоты, В этот день, Случайные 50), debounced observer (600 мс), пакетное удаление `deleteAssets(ids:)` с перехватом `userCancelled`, `presentLimitedLibraryPicker()`.
20. `Sources/Services/ImageCacheManager.swift` — **[Новое в Фазе 2]** `@MainActor` менеджер кэша картинок на базе `PHCachingImageManager`. Оппортунистические callback-вызовы с `PHImageRequestID`, потолок 2048px по длинной стороне с учётом `displayScale`, отслеживание прогресса iCloud (0...1) и статусов (`isDegraded`, `isInCloud`, `hasError`), методы `startCaching`, `stopCaching`, `cancelRequest`.
21. `Sources/Services/MediaSizeCalculator.swift` — **[Новое в Фазе 2]** `actor MediaSizeCalculator` с RAM-кэшем `[String: Int64]`. Безопасное чтение размера файла через селектор `responds(to: NSSelectorFromString("fileSize"))` и приведение через `NSNumber`. Ленивый расчёт без массовых XPC-вызовов на 50 000 файлах.

### Модели представлений (`Sources/ViewModels/`):
22. `Sources/ViewModels/DashboardViewModel.swift` — **[Новое в Фазе 2]** `@Observable @MainActor` ViewModel для главного экрана: связывает `PhotoLibraryService`, `DecisionStore` и `AppSettings`, фильтрует группы по `hideCompletedGroups`, вычисляет `GroupProgress`, общий размер корзины, инициирует сброс прогресса группы и пересборку «Случайных 50».

### Приложение и экраны (`Sources/App/`, `Sources/Views/`):
23. `Sources/App/AppSettings.swift` — `@Observable` обёртка над `UserDefaults` (тема: тёмная по умолчанию, `hapticsEnabled`, `hideCompletedGroups`).
24. `Sources/App/SwipeCleanApp.swift` — `@main` точка входа с безопасной инициализацией `ModelContainer` (fallback на in-memory при ошибках, без `fatalError` и `try!`).
25. `Sources/App/RootView.swift` — роутинг между экраном прав `PermissionView` и главным экраном `DashboardView`, поддержка тёмной темы.
26. `Sources/Views/Permissions/PermissionView.swift` — онбординг прав с 3 тезисами приватности и безопасности + кнопка запроса доступа / перехода в системные настройки.
27. `Sources/Views/Dashboard/DashboardView.swift` — **[Обновлено в Фазе 2]** Полноценный главный экран: баннер Limited Access, Hero-карточка («Освобождено», «Проверено», «Удалено»), глобальный красный баннер корзины (при `stagedCount > 0`), segmented control режимов (Месяцы | Альбомы | Подборки), LazyVStack с `GroupRowCard`, кнопка перехода в Настройки, `.fullScreenCover(item: $selectedGroup)`.
28. `Sources/Views/Dashboard/GroupRowCard.swift` — **[Новое в Фазе 2]** Компонент строки группы: обложка 56×56pt с асинхронной загрузкой через `ImageCacheManager`, название, подзаголовок, счётчик прогресса, прогресс-бар, зелёная галочка 100%, красный бейдж корзины группы, contextMenu «Сбросить прогресс этой группы».
29. `Sources/Views/Settings/SettingsView.swift` — **[Новое в Фазе 2]** Экран настроек: переключение темы (Системная / Тёмная / Светлая), тумблеры Haptics и скрытия разобранных групп, сброс прогресса просмотра (`confirmationDialog`), блок «О приложении».
30. `Sources/Views/SwipeDeck/SwipeDeckPlaceholderView.swift` — **[Новое в Фазе 2]** Плейсхолдер для `.fullScreenCover(item: $selectedGroup)` с кнопкой возврата (будет заменён на `SwipeDeckView` в Фазе 3).
31. `Sources/Views/TrashReview/TrashReviewPlaceholderView.swift` — **[Новое в Фазе 2]** Плейсхолдер для `.fullScreenCover(isPresented: $showTrashReview)` (будет заменён на `TrashReviewView` в Фазе 4).

---

## 4. Публичные сигнатуры ключевых компонентов Фазы 2

### Сервис медиатеки (`PhotoLibraryService`):
```swift
enum DeleteResult: Sendable {
    case success(count: Int)
    case cancelled
    case failure(Error)
}

@Observable @MainActor
final class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver {
    private(set) var currentStatus: PHAuthorizationStatus
    private(set) var isIndexing: Bool
    private(set) var assetsById: [String: PHAsset]
    private(set) var metadataById: [String: MediaMetadata]
    private(set) var allDeletableAssetIDs: [String]
    private(set) var monthGroups: [MediaGroup]
    private(set) var albumGroups: [MediaGroup]
    private(set) var smartGroups: [MediaGroup]
    var suppressReloadDuringBatchDelete: Bool
    var onIndexingFinished: (([String]) -> Void)?

    func refreshStatus()
    @discardableResult func requestAuthorization() async -> PHAuthorizationStatus
    func groups(for mode: CleaningMode) -> [MediaGroup]
    func startIndexing()
    func reshuffleRandom50(unreviewedIDs: [String]?)
    func deleteAssets(ids: [String]) async -> DeleteResult
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange)
    func presentLimitedLibraryPicker()
}
```

### Менеджер кэша изображений (`ImageCacheManager`):
```swift
struct ImageDeliveryInfo: Sendable {
    let isDegraded: Bool
    let isInCloud: Bool
    let hasError: Bool
}

@MainActor
final class ImageCacheManager {
    static let shared: ImageCacheManager
    static func targetSize(for containerSize: CGSize, displayScale: CGFloat) -> CGSize

    @discardableResult
    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill,
        progressHandler: ((Double) -> Void)? = nil,
        resultHandler: @escaping @MainActor (UIImage?, ImageDeliveryInfo) -> Void
    ) -> PHImageRequestID

    func cancelRequest(id: PHImageRequestID)
    func startCaching(for assets: [PHAsset], targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill)
    func stopCaching(for assets: [PHAsset], targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill)
    func stopCachingForAllAssets()
}
```

### Калькулятор размера файлов (`MediaSizeCalculator`):
```swift
actor MediaSizeCalculator {
    static let shared: MediaSizeCalculator

    func size(for asset: PHAsset) -> Int64
    func cachedSize(for localIdentifier: String) -> Int64?
    func setCachedSize(_ size: Int64, for localIdentifier: String)
    func removeSize(for localIdentifier: String)
    func clearCache()
}
```

### Модель главного экрана (`DashboardViewModel`):
```swift
@Observable @MainActor
final class DashboardViewModel {
    var selectedMode: CleaningMode
    var selectedGroup: MediaGroup?
    var showSettings: Bool
    var showTrashReview: Bool

    func configure(photoService: PhotoLibraryService, decisionStore: DecisionStore, settings: AppSettings)
    var isIndexing: Bool { get }
    var isLimitedAccess: Bool { get }
    var filteredGroups: [MediaGroup] { get }
    var stagedCount: Int { get }
    var stagedTotalBytes: Int64 { get }
    var stats: StatsSnapshot { get }

    func progress(for group: MediaGroup) -> GroupProgress
    func coverAsset(for group: MediaGroup) -> PHAsset?
    func resetGroupProgress(_ group: MediaGroup)
    func reshuffleRandom50()
    func openLimitedAccessPicker()
    func openSystemSettings()
    func onAppear()
}
```

---

## 5. Аудит соблюдения «Красных линий» (Раздел 2 SPEC.md)

| # | Правило Красной линии | Статус | Доказательство проверки |
|---|---|---|---|
| 1 | `SWIFT_VERSION: "5.0"` и `SWIFT_STRICT_CONCURRENCY: minimal` | ✅ PASS | Проверено в `project.yml`. |
| 2 | Раннер `macos-26` в GitHub Actions | ✅ PASS | Проверено в `.github/workflows/build-ios.yml`. |
| 3 | Запрет оборачивания `requestImage` при `.opportunistic` в `CheckedContinuation` | ✅ PASS | `ImageCacheManager` использует прямое callback-замыкание с возвратом `PHImageRequestID` и диспатчем на `@MainActor`. 0 вызовов `CheckedContinuation`. |
| 4 | Фильтрация `asset.canPerform(.delete)` | ✅ PASS | В `PhotoLibraryService` все группы формируются строго с фильтром `asset.canPerform(.delete) == true`. В `deleteAssets` повторно проверяется `canPerform(.delete)`. Пользовательские альбомы исключают `.albumCloudShared`. |
| 5 | Запрет `@Query` во View для выгрузки всей таблицы; только примитивные поля в `#Predicate` | ✅ PASS | `DashboardView` и `DashboardViewModel` используют RAM-кэш `DecisionStore`. Никаких `@Query` в представлениях. В предикатах SwiftData сравниваются только примитивные поля `assetIdentifier` и `statusRaw`. |
| 6 | Запрет массового обращения к `assetResources(for:)`; безопасный `fileSize` через `responds(to:)` | ✅ PASS | Сканирование Дашборда не обращается к `PHAssetResource`. `MediaSizeCalculator` является `actor` с RAM-кэшем `[String: Int64]` и извлекает `fileSize` строго через `resource.responds(to: NSSelectorFromString("fileSize"))` и приведение через `NSNumber`. |
| 7 | Запрет `PHImageManagerMaximumSize` и deprecated `UIScreen.main` | ✅ PASS | `ImageCacheManager.targetSize` вычисляет размер с потолком 2048px по длинной стороне; `GroupRowCard` получает `displayScale` из `@Environment(\.displayScale)`. 0 обращений к `UIScreen.main`. |
| 8 | Запрет 1-параметрового `.onChange` и `NavigationView` | ✅ PASS | Все экраны (`DashboardView`, `SettingsView`, `SwipeDeckPlaceholderView`, `TrashReviewPlaceholderView`) используют `NavigationStack`. Устаревший `.onChange` отсутствует (0 вхождений). |
| 9 | Открытие деки строго через `.fullScreenCover` | ✅ PASS | В `DashboardView` открытие группы выполнено через `.fullScreenCover(item: $vm.selectedGroup)`. Никаких `NavigationLink` для перехода в свайп-деку. |
| 10 | Запрет `DispatchQueue.asyncAfter` для свайпа | ✅ PASS | Смена карточек опирается на флаг `isTransitioning` и completion блока `withAnimation` (подготовлено в `SwipeSessionEngine`). |
| 11 | Запрет передачи `PHAsset` в `ShareLink` и раздельных `AVPlayer` | ✅ PASS | Будет реализовано в Фазе 3 (`MediaExportService` + единый `VideoPlayerController`). |
| 12 | Запрет `fatalError`, `try!`, force-unwrap `!`, обязательный `[weak self]` | ✅ PASS | Статический аудит показал 0 вхождений `try!`, 0 вхождений `fatalError`, 0 force-unwrap. Все замыкания `PHImageManager` и наблюдателей используют `[weak self]`. |

---

## 6. Design Check Фазы 2 (Протокол инженерного мышления)

1. **Акторная изоляция и безопасность потоков:**
   - `PhotoLibraryService`, `ImageCacheManager`, `DashboardViewModel`, `DecisionStore` строго изолированы на `@MainActor`.
   - Фоновое сканирование медиатеки выполняется в `Task.detached(priority: .userInitiated)` с независимым сбором словарей и передачей результата на `@MainActor` через `await MainActor.run`.
   - `MediaSizeCalculator` изолирован в собственном `actor`, гарантируя потокобезопасный доступ к кэшу размеров без блокировки UI.
   - Ни один объект `@Model` SwiftData не передаётся через границы акторов.
2. **Отмена асинхронных операций:**
   - В `PhotoLibraryService` задачи индексирования (`indexingTask`) и дебаунса обсервера (`debounceTask`) отменяются перед запуском новых задач, а также проверяют `Task.isCancelled`.
   - В `ImageCacheManager` реализован метод `cancelRequest(id: PHImageRequestID)`.
   - В `GroupRowCard` запрос превью отменяется при вызове `.onDisappear`.
3. **Сложность алгоритмов и оптимизация:**
   - Отображение главного экрана выполняется без $O(N)$ запросов к диску или базе данных.
   - Чтение прогресса групп и решений производится за $O(1)$ из RAM-кэша `DecisionStore`.
   - Сканирование галереи на 50 000+ элементов выполняется один раз в фоне, не вызывая XPC-запросов `PHAssetResource`.

---

## 7. Готовность к Фазе 3

Фаза 2 полностью завершена и статически проверена. Все файлы подготовлены для дальнейшей реализации Фазы 3 (Свайп-дека, Zoom, единый видеоплеер `VideoPlayerController` и сервис экспорта оригинала `MediaExportService`).
