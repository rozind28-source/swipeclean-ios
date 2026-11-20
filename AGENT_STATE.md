# Журнал состояния ИИ-агента: SwipeClean (`AGENT_STATE.md`)

*Дата последнего обновления:* 2026-11-20  
*Текущий этап:* **Фаза 3 завершена (Свайп-дека, Zoom, Видеоплеер и Share)**  
*Следующий этап:* **Фаза 4 (Корзина без прыжков, Удаление, Итоги, Настройки)**  

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
   - **[Новое в Фазе 3]** Строго один `AVPlayer` в `@Observable @MainActor VideoPlayerController` с защитой от видео-призрака (`activeAssetID`, `activeRequestID`), зацикливанием по `AVPlayerItemDidPlayToEndTime` с `[weak self]` и умной `AVAudioSession` (ambient по умолчанию, playback при explicit unmute).
   - **[Новое в Фазе 3]** Свайп и смена карточек на пружинной анимации iOS 17 `withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { ... } completion: { ... }` с защитой флагом `isTransitioning` (0 вызовов `DispatchQueue.main.asyncAfter`).
   - **[Новое в Фазе 3]** Pinch-to-Zoom (`MagnifyGesture`) + двойной тап (1× ↔ 2.5×) с отключением свайпа при `zoomScale > 1.01` и включением панорамирования.
   - **[Новое в Фазе 3]** Безопасный экспорт оригинала фото/видео во временную директорию через `MediaExportService` и передача в `ActivityShareSheet` с гарантированным удалением файла в `completionWithItemsHandler` (0 утечек `tmp/`).
4. **Безопасность SwiftData:** `ModelContainer` инициализируется с `do/catch` и безопасным fallback на in-memory контейнер при сбоях диска или миграций (без `fatalError` и без `try!`).
5. **Debounced Observer медиатеки:** `PHPhotoLibraryChangeObserver` с debounce 600 мс и флагом `suppressReloadDuringBatchDelete` для предотвращения ложных перезагрузок во время собственных транзакций удаления.

---

## 2. Статус фаз разработки

| Фаза | Название | Статус | Комментарий |
|---|---|---|---|
| **Фаза 1** | **Каркас, XcodeGen, CI, Контракты, Тесты, Права** | ✅ **ЗАВЕРШЕНА & ВЕРИФИЦИРОВАНА** | Создан `project.yml`, workflow CI `macos-26`, генератор иконки, каталоги ассетов, все доменные контракты, `SwipeSessionEngine` с XCTest, `DecisionStore`, `PhotoLibraryService`, `AppSettings`, `PermissionView`, `DashboardView`. Пройден статический аудит. CI успешно собирает `.ipa`. |
| **Фаза 2** | **PhotoKit-индексирование, Кэш и Главный экран** | ✅ **ЗАВЕРШЕНА** | Фоновое индексирование в `Task.detached` с фильтром `canPerform(.delete)`, 3 режима группировки (Месяцы «Ноябрь 2026», Альбомы без `.albumCloudShared`, Подборки: Тяжёлые видео, Скриншоты, В этот день, Случайные 50), debounced observer (600 мс), пакетное удаление `deleteAssets(ids:)` с перехватом `userCancelled`, `ImageCacheManager` с потолком 2048px, `actor MediaSizeCalculator`, `@Observable` `DashboardViewModel`, `DashboardView`, `GroupRowCard`, `SettingsView`. Пройден статический аудит. |
| **Фаза 3** | **Свайп-дека, Zoom, Видеоплеер и Share** | ✅ **ЗАВЕРШЕНА & ВЕРИФИЦИРОВАНА** | Реализован `VideoPlayerController` (один `AVPlayer`, токен актуальности, умная `AVAudioSession`), `LoopingVideoView` (UIViewRepresentable, `.resizeAspectFill`, 0 force-unwrap), `MediaExportService` (экспорт в `tmp/`), `ActivityShareSheet` (очистка в completion), `SwipeDeckViewModel`, `SwipeCardView` (Pinch/Double-tap Zoom, панорамирование, метаданные с секундами, бейджи, iCloud %, штампы «УДАЛИТЬ»/«ОСТАВИТЬ»), `SwipeDeckView` (ZStack 3 карточек, ForEach по `\.localIdentifier`, 5 кнопок действий, экран завершения с корзиной), обновлён `DashboardView` (.fullScreenCover). Пройден статический аудит 0 нарушений. |
| **Фаза 4** | Корзина без прыжков, Удаление, Итоги, Настройки | ⏳ СЛЕДУЮЩАЯ | Будет реализован `TrashReviewViewModel`, `TrashReviewView` (in-place спасение без прыжков сетки), `SessionCompleteView`, расширение тестов граничных случаев. |
| **Фаза 5** | Финальный инженерный аудит и релизная полировка | ⏳ ОЖИДАЕТ | Сквозной аудит утечек памяти, проверка крайних случаев (0 медиа, оффлайн iCloud, отмена удаления), проверка 0 нарушений красных линий. |

---

## 3. Реестр созданных и обновлённых файлов (Фазы 1, 2 и 3)

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
19. `Sources/Services/PhotoLibraryService.swift` — **[Обновлено в Фазе 3]** Фоновое сканирование, `canPerform(.delete)`, 3 режима группировки, debounced observer, пакетное удаление, `toggleFavorite(for assetID: String) async -> Bool`.
20. `Sources/Services/ImageCacheManager.swift` — `@MainActor` менеджер кэша картинок на базе `PHCachingImageManager`. Оппортунистические callback-вызовы с `PHImageRequestID`, потолок 2048px по длинной стороне с учётом `displayScale`, отслеживание прогресса iCloud (0...1) и статусов (`isDegraded`, `isInCloud`, `hasError`), `startCaching`, `stopCaching`, `cancelRequest`.
21. `Sources/Services/MediaSizeCalculator.swift` — `actor MediaSizeCalculator` с RAM-кэшем `[String: Int64]`. Безопасное чтение размера файла через селектор `responds(to: NSSelectorFromString("fileSize"))` и приведение через `NSNumber`.
22. `Sources/Services/VideoPlayerController.swift` — **[Новое в Фазе 3]** `@Observable @MainActor` контроллер строго единого `AVPlayer` на всю сессию свайпов: защита от видео-призраков через `activeAssetID` и `activeRequestID`, умная `AVAudioSession` (ambient по умолчанию, playback при explicit unmute, возврат в ambient при mute / inactive), зацикливание с `[weak self]`.
23. `Sources/Services/MediaExportService.swift` — **[Новое в Фазе 3]** Сервис экспорта оригиналов фото (`requestImageDataAndOrientation`) и видео (`writeData` / `requestExportSession`) в `FileManager.default.temporaryDirectory` с последующей очисткой.

### Модели представлений (`Sources/ViewModels/`):
24. `Sources/ViewModels/DashboardViewModel.swift` — `@Observable @MainActor` ViewModel для главного экрана: связывает `PhotoLibraryService`, `DecisionStore` и `AppSettings`, фильтрует группы, рассчитывает `GroupProgress`.
25. `Sources/ViewModels/SwipeDeckViewModel.swift` — **[Новое в Фазе 3]** `@Observable @MainActor` ViewModel для свайп-деки: связывает `SwipeSessionEngine`, `ImageCacheManager`, `VideoPlayerController`, `MediaExportService`, `DecisionStore`, `PhotoLibraryService` и `HapticsService`; управляет вылетом карточки через spring completion, сбросом зума, Undo, Избранным и Share.

### Приложение и экраны (`Sources/App/`, `Sources/Views/`):
26. `Sources/App/AppSettings.swift` — `@Observable` обёртка над `UserDefaults` (тема, haptics, скрытие разобранных групп).
27. `Sources/App/SwipeCleanApp.swift` — `@main` точка входа с безопасной инициализацией `ModelContainer` (fallback на in-memory без `fatalError` и `try!`).
28. `Sources/App/RootView.swift` — роутинг между экраном прав `PermissionView` и главным экраном `DashboardView`.
29. `Sources/Views/Permissions/PermissionView.swift` — онбординг прав доступа с кнопкой запроса.
30. `Sources/Views/Dashboard/DashboardView.swift` — **[Обновлено в Фазе 3]** Главный экран: открытие группы через `.fullScreenCover(item: $vm.selectedGroup)` с реальным `SwipeDeckView`.
31. `Sources/Views/Dashboard/GroupRowCard.swift` — компонент строки группы с обложкой 56×56, прогресс-баром и contextMenu сброса.
32. `Sources/Views/Settings/SettingsView.swift` — экран настроек (тема, Haptics, сброс прогресса, «О приложении»).
33. `Sources/Views/SwipeDeck/LoopingVideoView.swift` — **[Новое в Фазе 3]** `UIViewRepresentable` для `AVPlayerLayer` с `videoGravity = .resizeAspectFill` и 0 force-unwrap.
34. `Sources/Views/SwipeDeck/ActivityShareSheet.swift` — **[Новое в Фазе 3]** `UIViewControllerRepresentable` для `UIActivityViewController` с гарантированным удалением временного файла в `completionWithItemsHandler`.
35. `Sources/Views/SwipeDeck/SwipeCardView.swift` — **[Новое в Фазе 3]** Карточка свайпа: фото/видео/LivePhoto, Pinch-to-Zoom (`MagnifyGesture`) + двойной тап (1× ↔ 2.5×), панорамирование при зуме, метаданные с секундами внизу поверх градиента, бейджи, капсула загрузки из iCloud, оверлеи штампов «УДАЛИТЬ» (красный) / «ОСТАВИТЬ» (зелёный).
36. `Sources/Views/SwipeDeck/SwipeDeckView.swift` — **[Новое в Фазе 3]** Экран свайп-деки: верхняя панель (✕, остаток, корзина группы), ZStack из 3 карточек (ForEach с `id: \.localIdentifier`), 5 нижних кнопок действий, экран завершения группы с приглашением в корзину при `stagedCount > 0`.
37. `Sources/Views/TrashReview/TrashReviewPlaceholderView.swift` — плейсхолдер для `.fullScreenCover(isPresented: $showTrashReview)` (будет заменён на `TrashReviewView` в Фазе 4).

---

## 4. Публичные сигнатуры ключевых компонентов Фазы 3

### Контроллер видеоплеера (`VideoPlayerController`):
```swift
@Observable @MainActor
final class VideoPlayerController {
    static let shared: VideoPlayerController
    let player: AVPlayer
    private(set) var activeAssetID: String?
    private(set) var activeRequestID: PHImageRequestID?
    private(set) var isPlaying: Bool
    private(set) var isMuted: Bool

    func loadVideo(for asset: PHAsset)
    func play()
    func pause()
    func togglePlayPause()
    func toggleMute()
    func setMuted(_ muted: Bool)
    func handleScenePhaseChange(_ phase: ScenePhase)
    func reset()
}
```

### Представление зацикленного видео (`LoopingVideoView`):
```swift
struct LoopingVideoView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView
    func updateUIView(_ uiView: PlayerUIView, context: Context)
}
```

### Сервис экспорта медиа (`MediaExportService`):
```swift
enum MediaExportError: LocalizedError {
    case assetNotFound
    case exportFailed(String)
    case cancelled
}

final class MediaExportService: Sendable {
    static let shared: MediaExportService
    func exportOriginal(for asset: PHAsset) async throws -> URL
    static func cleanupExportedFile(at url: URL)
}
```

### Системный лист «Поделиться» (`ActivityShareSheet`):
```swift
struct ActivityShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    var onComplete: (() -> Void)?
    func makeUIViewController(context: Context) -> UIActivityViewController
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context)
}
```

### Модель свайп-деки (`SwipeDeckViewModel`):
```swift
enum SwipeDirection {
    case left   // stagedForTrash
    case right  // kept
}

@Observable @MainActor
final class SwipeDeckViewModel {
    let group: MediaGroup
    let videoController: VideoPlayerController

    private(set) var visibleAssetIDs: [String]
    private(set) var isGroupFinished: Bool
    private(set) var currentAssetSize: Int64
    private(set) var isFavorite: Bool

    var cardOffset: CGSize
    var zoomScale: CGFloat
    var zoomOffset: CGSize

    private(set) var isExportingForShare: Bool
    var shareFileURL: URL?
    var showShareSheet: Bool
    var showTrashReview: Bool

    var isTransitioning: Bool { get }
    var canUndo: Bool { get }
    var remainingCount: Int { get }
    var totalGroupCount: Int { get }
    var reviewedCount: Int { get }
    var currentAssetID: String? { get }
    var currentAsset: PHAsset? { get }
    var currentMetadata: MediaMetadata? { get }
    var groupProgress: GroupProgress { get }
    var stagedCountInGroup: Int { get }
    var stagedBytesInGroup: Int64 { get }

    func onAppear(containerSize: CGSize, displayScale: CGFloat)
    func onDisappear()
    func swipe(direction: SwipeDirection, assetID: String)
    func undo()
    func toggleFavorite()
    func exportAndShare()
    func asset(for id: String) -> PHAsset?
    func metadata(for id: String) -> MediaMetadata?
}
```

---

## 5. Аудит соблюдения «Красных линий» (Раздел 2 SPEC.md)

| # | Правило Красной линии | Статус | Доказательство проверки |
|---|---|---|---|
| 1 | `SWIFT_VERSION: "5.0"` и `SWIFT_STRICT_CONCURRENCY: minimal` | ✅ PASS | Проверено в `project.yml`. |
| 2 | Раннер `macos-26` в GitHub Actions | ✅ PASS | Проверено в `.github/workflows/build-ios.yml`. |
| 3 | Запрет оборачивания `requestImage` при `.opportunistic` в `CheckedContinuation` | ✅ PASS | `ImageCacheManager` использует прямое callback-замыкание с возвратом `PHImageRequestID` и диспатчем на `@MainActor`. 0 вызовов `CheckedContinuation` для оппортунистических картинок. |
| 4 | Фильтрация `asset.canPerform(.delete)` | ✅ PASS | В `PhotoLibraryService` все группы формируются строго с фильтром `asset.canPerform(.delete) == true`. В `deleteAssets` повторно проверяется `canPerform(.delete)`. Пользовательские альбомы исключают `.albumCloudShared`. |
| 5 | Запрет `@Query` во View для выгрузки всей таблицы; только примитивные поля в `#Predicate` | ✅ PASS | `DashboardView`, `SwipeDeckView`, `SwipeDeckViewModel` используют RAM-кэш `DecisionStore`. Никаких `@Query` в представлениях. В предикатах SwiftData сравниваются только примитивные поля `assetIdentifier` и `statusRaw`. |
| 6 | Запрет массового обращения к `assetResources(for:)`; безопасный `fileSize` через `responds(to:)` | ✅ PASS | Сканирование Дашборда не обращается к `PHAssetResource`. `MediaSizeCalculator` является `actor` с RAM-кэшем `[String: Int64]` и извлекает `fileSize` строго через `resource.responds(to: NSSelectorFromString("fileSize"))` и приведение через `NSNumber`. |
| 7 | Запрет `PHImageManagerMaximumSize` и deprecated `UIScreen.main` | ✅ PASS | `ImageCacheManager.targetSize` вычисляет размер с потолком 2048px по длинной стороне; `SwipeCardView` и `SwipeDeckView` получают `displayScale` из `@Environment(\.displayScale)` и геометрию из `GeometryReader`. 0 обращений к `UIScreen.main`. |
| 8 | Запрет 1-параметрового `.onChange` и `NavigationView` | ✅ PASS | Все представления используют 2-параметровый `.onChange(of:) { _, newValue in }` (в `SwipeCardView` и `SwipeDeckView`). Все навигационные контейнеры — `NavigationStack`. `NavigationView` отсутствует (0 вхождений). |
| 9 | Открытие деки строго через `.fullScreenCover` | ✅ PASS | В `DashboardView` открытие группы выполнено через `.fullScreenCover(item: $vm.selectedGroup) { group in SwipeDeckView(...) }`. Никаких `NavigationLink` для перехода в свайп-деку. |
| 10 | Запрет `DispatchQueue.asyncAfter` для свайпа | ✅ PASS | Смена карточек в `SwipeDeckViewModel` опирается на iOS 17 `withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { ... } completion: { ... }` и флаг `isTransitioning` в `SwipeSessionEngine`. 0 вхождений `asyncAfter`. `ForEach` в деке использует строго `id: \.localIdentifier`. |
| 11 | Запрет передачи `PHAsset` в `ShareLink` и раздельных `AVPlayer` | ✅ PASS | Реализован `MediaExportService` (экспорт оригинала в `tmp/`) + `ActivityShareSheet` с очисткой в `completionWithItemsHandler` (0 вызовов `ShareLink`). Строго один `AVPlayer` на сессию в `VideoPlayerController` с токенами `activeAssetID` и `activeRequestID`. |
| 12 | Запрет `fatalError`, `try!`, force-unwrap `!`, обязательный `[weak self]` | ✅ PASS | Статический аудит 32 swift-файлов показал: 0 вхождений `try!`, 0 вхождений `fatalError`, 0 force-cast (`as!`), 0 force-unwrap опционалов. Все замыкания `PHImageManager`, `NotificationCenter` и анимаций содержат `[weak self]`. |

---

## 6. Design Check Фазы 3 (Протокол инженерного мышления)

1. **Акторная изоляция и безопасность потоков:**
   - `VideoPlayerController`, `SwipeDeckViewModel`, `ImageCacheManager`, `DecisionStore`, `PhotoLibraryService` строго изолированы на `@MainActor`.
   - `MediaExportService` работает асинхронно, экспортируя бинарные данные оригинала через потокобезопасные PhotoKit API с блокировкой `NSLock` против повторных вызовов `continuation.resume`.
   - `LoopingVideoView` и `ActivityShareSheet` реализованы как UIKit-обёртки на главном потоке.
   - Ни один объект `@Model` SwiftData не передаётся через границы акторов.
2. **Отмена асинхронных операций:**
   - В `VideoPlayerController` при смене карточки, закрытии экрана или паузе отменяется предыдущий `activeRequestID` (`cancelImageRequest`), вызывается `player.pause()`, очищается `replaceCurrentItem(with: nil)`, а в callback проверяется `guard self.activeAssetID == targetAssetID else { return }`.
   - Умная `AVAudioSession`: в фоне (`scenePhase != .active`) или при возврате в mute плеер ставится на паузу, аудиосессия переводится в `.ambient` и деактивируется с `.notifyOthersOnDeactivation`.
   - В `SwipeCardView` запрос превью `requestID` отменяется в `.onDisappear` и при смене `localIdentifier`.
   - Временный файл экспорта удаляется в `completionWithItemsHandler` `ActivityShareSheet`.
3. **Сложность алгоритмов и оптимизация:**
   - `ZStack` в `SwipeDeckView` рендерит максимум 3 видимые карточки (`visibleAssetIDs.prefix(3)`).
   - Префетч изображений и расчёт веса выполняется лениво для следующих 5 карточек вперед.
   - Форматирование даты с секундами кэшировано в статическом `DateFormatter` с русской локалью `ru_RU`.
   - Никаких $O(N)$ операций внутри `body` представлений.

---

## 7. Готовность к Фазе 4

Фаза 3 полностью завершена, статически проверена и готова к началу Фазы 4 (Корзина без прыжков `TrashReviewView`, пакетное удаление, экран итогов `SessionCompleteView`, настройки и расширение юнит-тестов).
