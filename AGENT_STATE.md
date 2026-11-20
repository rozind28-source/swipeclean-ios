# Журнал состояния ИИ-агента: SwipeClean (`AGENT_STATE.md`)

*Дата последнего обновления:* 2026-11-20  
*Текущий этап:* **Фаза 4 завершена (Корзина без прыжков, Удаление, Итоги, Настройки)**  
*Следующий этап:* **Фаза 5 (Финальный инженерный аудит и релизная полировка)**  

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
   - Строго один `AVPlayer` в `@Observable @MainActor VideoPlayerController` с защитой от видео-призрака (`activeAssetID`, `activeRequestID`), зацикливанием по `AVPlayerItemDidPlayToEndTime` с `[weak self]` и умной `AVAudioSession`.
   - Свайп и смена карточек на пружинной анимации iOS 17 `withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { ... } completion: { ... }` с защитой флагом `isTransitioning` (0 вызовов `DispatchQueue.main.asyncAfter`).
   - Pinch-to-Zoom (`MagnifyGesture`) + двойной тап (1× ↔ 2.5×) с отключением свайпа при `zoomScale > 1.01` и включением панорамирования.
   - Безопасный экспорт оригинала фото/видео во временную директорию через `MediaExportService` и передача в `ActivityShareSheet` с гарантированным удалением файла в `completionWithItemsHandler` (0 утечек `tmp/`).
   - **[Новое в Фазе 4] Сетка корзины без прыжков (`TrashReviewView`):** `LazyVGrid` на 3 колонки (spacing 2pt), в которой тап по ячейке переключает её в `rescuedIDs` на месте (`opacity 0.45` + зелёный чекмарк «Оставить»), без удаления плитки из массива до подтверждения.
   - **[Новое в Фазе 4] Пакетное удаление с тихой отменой:** Вызов `PhotoLibraryService.deleteAssets(ids:)` с системным диалогом iOS; при отказе пользователя (`.cancelled`) — тихое восстановление состояния без показа ошибки. При успехе — `rescued -> kept` (статистика reviewed не меняется), удалённые записи удаляются из базы (`totalDeletedCount += N`, `totalBytesFreed += bytes`).
   - **[Новое в Фазе 4] Экран завершения сессии (`SessionCompleteView`):** Иконка с `.symbolEffect(.bounce)`, сводка освобождённой памяти и удалённых файлов, памятка про 30 дней в «Недавно удалённых» и iCloud.
   - **[Новое в Фазе 4] Полнофункциональные настройки (`SettingsView`):** Выбор темы (Системная / Тёмная / Светлая), виброотклик, скрытие завершённых групп, подтверждение сброса (`confirmationDialog`), удаляющее строго записи `kept` без изменения корзины и статистики.
4. **Безопасность SwiftData:** `ModelContainer` инициализируется с `do/catch` и безопасным fallback на in-memory контейнер при сбоях диска или миграций (без `fatalError` и без `try!`).
5. **Debounced Observer медиатеки:** `PHPhotoLibraryChangeObserver` с debounce 600 мс и флагом `suppressReloadDuringBatchDelete` для предотвращения ложных перезагрузок во время собственных транзакций удаления.

---

## 2. Статус фаз разработки

| Фаза | Название | Статус | Комментарий |
|---|---|---|---|
| **Фаза 1** | **Каркас, XcodeGen, CI, Контракты, Тесты, Права** | ✅ **ЗАВЕРШЕНА & ВЕРИФИЦИРОВАНА** | Создан `project.yml`, workflow CI `macos-26`, генератор иконки, каталоги ассетов, все доменные контракты, `SwipeSessionEngine` с XCTest, `DecisionStore`, `PhotoLibraryService`, `AppSettings`, `PermissionView`, `DashboardView`. Пройден статический аудит. CI успешно собирает `.ipa`. |
| **Фаза 2** | **PhotoKit-индексирование, Кэш и Главный экран** | ✅ **ЗАВЕРШЕНА & ВЕРИФИЦИРОВАНА** | Фоновое индексирование в `Task.detached` с фильтром `canPerform(.delete)`, 3 режима группировки (Месяцы «Ноябрь 2026», Альбомы без `.albumCloudShared`, Подборки: Тяжёлые видео, Скриншоты, В этот день, Случайные 50), debounced observer (600 мс), пакетное удаление `deleteAssets(ids:)` с перехватом `userCancelled`, `ImageCacheManager` с потолком 2048px, `actor MediaSizeCalculator`, `@Observable` `DashboardViewModel`, `DashboardView`, `GroupRowCard`, `SettingsView`. Пройден статический аудит. |
| **Фаза 3** | **Свайп-дека, Zoom, Видеоплеер и Share** | ✅ **ЗАВЕРШЕНА & ВЕРИФИЦИРОВАНА** | Реализован `VideoPlayerController` (один `AVPlayer`, токен актуальности, умная `AVAudioSession`), `LoopingVideoView` (UIViewRepresentable, `.resizeAspectFill`, 0 force-unwrap), `MediaExportService` (экспорт в `tmp/`), `ActivityShareSheet` (очистка в completion), `SwipeDeckViewModel`, `SwipeCardView` (Pinch/Double-tap Zoom, панорамирование, метаданные с секундами, бейджи, iCloud %, штампы «УДАЛИТЬ»/«ОСТАВИТЬ»), `SwipeDeckView` (ZStack 3 карточек, ForEach по `\.localIdentifier`, 5 кнопок действий, экран завершения с корзиной), обновлён `DashboardView` (.fullScreenCover). Пройден статический аудит 0 нарушений. |
| **Фаза 4** | **Корзина без прыжков, Удаление, Итоги, Настройки** | ✅ **ЗАВЕРШЕНА & ВЕРИФИЦИРОВАНА** | Реализованы `TrashReviewViewModel` (@Observable @MainActor), `TrashReviewView` (LazyVGrid 3 колонки, in-place спасение без прыжков сетки, тулбар, закреплённая нижняя панель), `SessionCompleteView` (.symbolEffect(.bounce), статистика сессии, памятка 30 дней/iCloud), верифицирован `SettingsView` (тема, haptics, скрытие групп, confirmationDialog со сбросом только kept), удалён плейсхолдер корзины, расширены юнит-тесты `SwipeSessionEngineTests` (пустая очередь, защита от двойного свайпа, undo на 0-м элементе, множественный undo, расчёт `GroupProgress`). Пройден статический аудит 0 нарушений. |
| **Фаза 5** | Финальный инженерный аудит и релизная полировка | ⏳ ОЖИДАЕТ | Сквозной аудит утечек памяти, проверка крайних случаев (0 медиа, оффлайн iCloud, отмена удаления), проверка 0 нарушений красных линий. |

---

## 3. Реестр файлов проекта (Фазы 1 – 4)

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
14. `Tests/SwipeSessionEngineTests.swift` — **[Расширено в Фазе 4]** Полное XCTest покрытие: инициализация, пустая очередь, настраиваемый стартовый индекс, видимые карточки, prefetch, свайпы kept/trash, защита от двойного свайпа и гонок 120 Гц, Undo на 0-м элементе, множественный Undo до начала очереди, расчёт `GroupProgress` (пустая группа, 50% разбор, 100% kept, 100% staged, смешанная группа, нетронутая группа), сброс сессии, флаг перехода.

### Слой персистентности (`Sources/Persistence/`):
15. `Sources/Persistence/MediaDecisionRecord.swift` — `@Model` SwiftData для хранения решений по активам с примитивным полем `statusRaw: String` для безопасных `#Predicate`.
16. `Sources/Persistence/CleaningStatsRecord.swift` — `@Model` SwiftData + доменная структура `StatsSnapshot: Equatable, Sendable`.
17. `Sources/Persistence/DecisionStore.swift` — `@Observable @MainActor` RAM-кэш со сложностью $O(1)$, методами `hydrate()`, `recordDecision()`, `undoDecision()`, `rescueFromTrash()`, `rescueMultipleFromTrash()`, `commitDeleted()`, `resetKeptDecisions()`, `pruneMissingAssets()`.

### Сервисы (`Sources/Services/`):
18. `Sources/Services/HapticsService.swift` — тактильная отдача (UIImpact/UINotification/UISelection) с проверкой флага `AppSettings.shared.hapticsEnabled`.
19. `Sources/Services/PhotoLibraryService.swift` — фоновое сканирование, `canPerform(.delete)`, 3 режима группировки, debounced observer, пакетное удаление `deleteAssets(ids:)` с тихой обработкой `userCancelled`, `toggleFavorite(for:)`.
20. `Sources/Services/ImageCacheManager.swift` — `@MainActor` менеджер кэша картинок на базе `PHCachingImageManager`. Оппортунистические callback-вызовы с `PHImageRequestID`, потолок 2048px по длинной стороне с учётом `displayScale`, отслеживание прогресса iCloud (0...1) и статусов (`isDegraded`, `isInCloud`, `hasError`), `startCaching`, `stopCaching`, `cancelRequest`.
21. `Sources/Services/MediaSizeCalculator.swift` — `actor MediaSizeCalculator` с RAM-кэшем `[String: Int64]`. Безопасное чтение размера файла через селектор `responds(to: NSSelectorFromString("fileSize"))` и приведение через `NSNumber`.
22. `Sources/Services/VideoPlayerController.swift` — `@Observable @MainActor` контроллер строго единого `AVPlayer` на всю сессию свайпов: защита от видео-призраков через `activeAssetID` и `activeRequestID`, умная `AVAudioSession` (ambient по умолчанию, playback при explicit unmute), зацикливание с `[weak self]`.
23. `Sources/Services/MediaExportService.swift` — сервис экспорта оригиналов фото (`requestImageDataAndOrientation`) и видео (`writeData` / `requestAVAsset`) в `FileManager.default.temporaryDirectory` с последующей очисткой.

### Модели представлений (`Sources/ViewModels/`):
24. `Sources/ViewModels/DashboardViewModel.swift` — `@Observable @MainActor` ViewModel для главного экрана: связывает `PhotoLibraryService`, `DecisionStore` и `AppSettings`, фильтрует группы, рассчитывает `GroupProgress`.
25. `Sources/ViewModels/SwipeDeckViewModel.swift` — `@Observable @MainActor` ViewModel для свайп-деки: связывает `SwipeSessionEngine`, `ImageCacheManager`, `VideoPlayerController`, `MediaExportService`, `DecisionStore`, `PhotoLibraryService` и `HapticsService`; управляет вылетом карточки через spring completion, сбросом зума, Undo, Избранным и Share.
26. `Sources/ViewModels/TrashReviewViewModel.swift` — **[Новое в Фазе 4]** `@Observable @MainActor` ViewModel для экрана корзины: поддержка глобальной корзины и корзины группы (`groupID`), `rescuedIDs: Set<String>`, фоновый расчёт веса через `MediaSizeCalculator`, методы `toggleRescue(id:)`, `rescueAll()`, `selectAllForDeletion()`, `executeBatchDelete(onDismiss:)`, `saveRescuedAndDismiss(onDismiss:)`.

### Приложение и экраны (`Sources/App/`, `Sources/Views/`):
27. `Sources/App/AppSettings.swift` — `@Observable` обёртка над `UserDefaults` (тема, haptics, скрытие разобранных групп).
28. `Sources/App/SwipeCleanApp.swift` — `@main` точка входа с безопасной инициализацией `ModelContainer` (fallback на in-memory без `fatalError` и `try!`).
29. `Sources/App/RootView.swift` — роутинг между экраном прав `PermissionView` и главным экраном `DashboardView`.
30. `Sources/Views/Permissions/PermissionView.swift` — онбординг прав доступа с кнопкой запроса.
31. `Sources/Views/Dashboard/DashboardView.swift` — **[Обновлено в Фазе 4]** Главный экран: открытие группы через `.fullScreenCover` со `SwipeDeckView`, глобальная корзина через `.fullScreenCover` с `TrashReviewView`.
32. `Sources/Views/Dashboard/GroupRowCard.swift` — компонент строки группы с обложкой 56×56, прогресс-баром и contextMenu сброса.
33. `Sources/Views/Settings/SettingsView.swift` — экран настроек (тема, Haptics, сброс прогресса через `confirmationDialog` с удалением только `kept`, «О приложении» v1.0.0).
34. `Sources/Views/SwipeDeck/LoopingVideoView.swift` — `UIViewRepresentable` для `AVPlayerLayer` с `videoGravity = .resizeAspectFill` и 0 force-unwrap.
35. `Sources/Views/SwipeDeck/ActivityShareSheet.swift` — `UIViewControllerRepresentable` для `UIActivityViewController` с гарантированным удалением временного файла в `completionWithItemsHandler`.
36. `Sources/Views/SwipeDeck/SwipeCardView.swift` — карточка свайпа: фото/видео/LivePhoto, Pinch-to-Zoom (`MagnifyGesture`) + двойной тап (1× ↔ 2.5×), панорамирование при зуме, метаданные с секундами внизу поверх градиента, бейджи, капсула загрузки из iCloud, оверлеи штампов «УДАЛИТЬ» (красный) / «ОСТАВИТЬ» (зелёный).
37. `Sources/Views/SwipeDeck/SwipeDeckView.swift` — **[Обновлено в Фазе 4]** Экран свайп-деки: замена плейсхолдера корзины на полнофункциональный `TrashReviewView(group: ...)`.
38. `Sources/Views/TrashReview/TrashReviewView.swift` — **[Новое в Фазе 4]** Полноценный экран корзины в `NavigationStack`: `LazyVGrid` на 3 колонки (spacing 2pt), ячейка с `ImageCacheManager`, in-place спасение без прыжков сетки (`opacity 0.45` + зелёный чекмарк «Оставить»), тулбар «Спасти все / Выбрать все», закреплённая нижняя панель с текстом «К удалению: N из Total • X МБ» и кнопкой удаления / сохранения спасённых, обработка отмены iOS.
39. `Sources/Views/TrashReview/SessionCompleteView.swift` — **[Новое в Фазе 4]** Экран завершения сессии: `.symbolEffect(.bounce)`, статистика сессии (удалено файлов, освобождено места), памятка про 30 дней в «Недавно удалённых» и iCloud, кнопка «На главную».

---

## 4. Публичные сигнатуры ключевых компонентов Фазы 4

### Модель представления корзины (`TrashReviewViewModel`):
```swift
@Observable @MainActor
final class TrashReviewViewModel {
    let group: MediaGroup?
    let groupID: String?

    private(set) var assetIDs: [String]
    private(set) var assetsById: [String: PHAsset]
    private(set) var metadataById: [String: MediaMetadata]

    var rescuedIDs: Set<String>
    private(set) var assetSizes: [String: Int64]

    var isDeleting: Bool
    var showSessionComplete: Bool
    var deletedCountInSession: Int
    var freedBytesInSession: Int64

    var errorMessage: String?
    var showError: Bool

    var totalCount: Int { get }
    var rescuedCount: Int { get }
    var itemsToDeleteCount: Int { get }
    var areAllRescued: Bool { get }
    var idsToDelete: [String] { get }
    var bytesToDelete: Int64 { get }
    var bytesRescued: Int64 { get }
    var totalBytes: Int64 { get }

    init(
        group: MediaGroup? = nil,
        groupID: String? = nil,
        photoService: PhotoLibraryService,
        decisionStore: DecisionStore,
        mediaSizeCalculator: MediaSizeCalculator = .shared
    )

    func toggleRescue(id: String)
    func rescueAll()
    func selectAllForDeletion()
    func saveRescuedAndDismiss(onDismiss: (() -> Void)?)
    func executeBatchDelete(onDismiss: (() -> Void)?) async
    func cancelTasks()
}
```

### Экран корзины (`TrashReviewView`):
```swift
struct TrashReviewView: View {
    let group: MediaGroup?
    let photoService: PhotoLibraryService
    let decisionStore: DecisionStore
    var onDismiss: () -> Void

    init(
        group: MediaGroup? = nil,
        groupID: String? = nil,
        photoService: PhotoLibraryService,
        decisionStore: DecisionStore,
        onDismiss: @escaping () -> Void
    )
}

struct TrashAssetCell: View {
    let asset: PHAsset
    let metadata: MediaMetadata?
    let isRescued: Bool
    let sizeBytes: Int64?
    let onTap: () -> Void
}
```

### Экран завершения сессии (`SessionCompleteView`):
```swift
struct SessionCompleteView: View {
    let deletedCount: Int
    let freedBytes: Int64
    let onFinish: () -> Void
}
```

---

## 5. Аудит соблюдения «Красных линий» (Раздел 2 SPEC.md)

| # | Правило Красной линии | Статус | Доказательство проверки |
|---|---|---|---|
| 1 | `SWIFT_VERSION: "5.0"` и `SWIFT_STRICT_CONCURRENCY: minimal` | ✅ PASS | Проверено в `project.yml`. |
| 2 | Раннер `macos-26` в GitHub Actions | ✅ PASS | Проверено в `.github/workflows/build-ios.yml`. |
| 3 | Запрет оборачивания `requestImage` при `.opportunistic` в `CheckedContinuation` | ✅ PASS | `TrashAssetCell` вызывает `ImageCacheManager.shared.requestImage`, использующий безопасное callback-замыкание с сохранением `PHImageRequestID` и отменой в `.onDisappear`. 0 `CheckedContinuation`. |
| 4 | Фильтрация `asset.canPerform(.delete)` | ✅ PASS | В `PhotoLibraryService` все группы и пакетное удаление `deleteAssets(ids:)` строго проверяют `asset.canPerform(.delete) == true`. |
| 5 | Запрет `@Query` во View для выгрузки всей таблицы; только примитивные поля в `#Predicate` | ✅ PASS | `TrashReviewView` и `TrashReviewViewModel` опираются на RAM-кэш `DecisionStore`. Никаких `@Query` в SwiftUI представлениях. В предикатах SwiftData сравниваются только примитивные строки. |
| 6 | Запрет массового обращения к `assetResources(for:)`; безопасный `fileSize` через `responds(to:)` | ✅ PASS | Размеры файлов в корзине берутся из RAM-кэша `decisionStore.stagedSizes` и лениво догружаются через `actor MediaSizeCalculator`, который извлекает размер строго через `responds(to: NSSelectorFromString("fileSize"))` и `NSNumber`. |
| 7 | Запрет `PHImageManagerMaximumSize` и deprecated `UIScreen.main` | ✅ PASS | Ячейки корзины рассчитывают `targetSize` через `ImageCacheManager.targetSize(for:displayScale:)` с потолком 2048px по длинной стороне и `@Environment(\.displayScale)`. 0 обращений к `UIScreen.main`. |
| 8 | Запрет 1-параметрового `.onChange` и `NavigationView` | ✅ PASS | В проекте нет вызовов 1-параметрового `.onChange`. Все экраны упакованы в `NavigationStack`. `NavigationView` отсутствует (0 вхождений). |
| 9 | Открытие деки и корзины строго через `.fullScreenCover` | ✅ PASS | `DashboardView` и `SwipeDeckView` открывают `TrashReviewView` через `.fullScreenCover(isPresented:)`. Конфликты системного жеста «Назад» исключены. |
| 10 | Запрет `DispatchQueue.asyncAfter` для свайпа | ✅ PASS | Все анимации и переходы работают на нативных spring-анимациях iOS 17. 0 вхождений `asyncAfter`. Сетка корзины не удаляет элементы при нажатии — статус меняется in-place (`rescuedIDs: Set<String>`), сетка не прыгает. |
| 11 | Запрет передачи `PHAsset` в `ShareLink` и раздельных `AVPlayer` | ✅ PASS | Экспорт медиа строго через `MediaExportService` + `ActivityShareSheet`. Видеоплеер строго один в `VideoPlayerController`. В ячейках корзины видео отображается статическим постером с бейджем длительности. |
| 12 | Запрет `fatalError`, `try!`, force-unwrap `!`, обязательный `[weak self]` | ✅ PASS | Статический аудит всего репозитория (`Sources/` и `Tests/`) подтвердил: 0 вызовов `fatalError`, 0 вызовов `try!`, 0 force-cast (`as!`), 0 force-unwrap опционалов PhotoKit. Все замыкания `Task` содержат `[weak self]`. |

---

## 6. Design Check Фазы 4 (Протокол инженерного мышления)

1. **Акторная изоляция и безопасность потоков:**
   - `TrashReviewViewModel`, `TrashReviewView`, `SessionCompleteView`, `DecisionStore`, `PhotoLibraryService` строго изолированы на `@MainActor`.
   - `MediaSizeCalculator` является потокобезопасным `actor`.
   - Фоновый расчёт размеров недостающих активов запускается в `Task [weak self]` и возвращает результаты на `@MainActor`.
   - Ни один объект `@Model` SwiftData не передаётся через границы акторов.
2. **Отмена асинхронных операций и управление ресурсами:**
   - В `TrashReviewView` каждая ячейка `TrashAssetCell` отменяет свой `PHImageRequestID` в `.onDisappear` через `ImageCacheManager.shared.cancelRequest(id:)`.
   - Фоновая задача расчёта веса `sizeCalculationTask` отменяется при закрытии экрана (`cancelTasks()`) и в `deinit` ViewModel.
   - Пакетное удаление через `photoService.deleteAssets(ids:)` устанавливает флаг `suppressReloadDuringBatchDelete`, предотвращая дребезг observer PhotoKit во время транзакции.
3. **Сложность алгоритмов и UX без прыжков:**
   - Сетка `LazyVGrid` состоит из неизменяемого массива `assetIDs`.
   - Тап по плитке модифицирует `rescuedIDs: Set<String>` за $O(1)$.
   - Ни один элемент не удаляется из сетки до явного подтверждения физического удаления. Это гарантирует абсолютно статичное положение карточек без рывков скролла и перекомпоновки сетки.
   - Подсчёт веса и количества выполняется за $O(N)$ по количеству элементов корзины через мгновенный RAM-кэш $O(1)$.

---

## 7. Готовность к Фазе 5

Фаза 4 полностью завершена, статически проверена и готова к началу Фазы 5 (Финальный инженерный аудит, релизная полировка и проверка крайних случаев).
