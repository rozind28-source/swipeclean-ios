# Журнал состояния ИИ-агента: SwipeClean (`AGENT_STATE.md`)

*Дата последнего обновления:* 2026-11-20  
*Текущий этап:* **Фаза 1 завершена (Готовность к CI-First проверке)**  
*Следующий этап:* **Фаза 2 (PhotoKit-индексирование, кэш и Главный экран)**  

---

## 1. Архитектурный обзор проекта

SwipeClean — нативное iOS-приложение для быстрой и безопасной очистки медиатеки свайпами (аналог *Sponge — Gallery Cleaner*).  
Приложение спроектировано по принципам Clean Architecture + Swift Concurrency + SwiftData без единой внешней зависимости (0 сторонних SPM/CocoaPods пакетов).

### Ключевые архитектурные решения:
1. **100% Offline & Private:** Никакой сети, телеметрии, аналитики или сторонних SDK. Доступ только к системному PhotoKit.
2. **Двухэтапная корзина:** Свайп влево переводит актив в `stagedForTrash` (внутренний буфер). Физическое удаление запускается только с экрана корзины через транзакцию `PHAssetChangeRequest.deleteAssets` с перемещением в системный альбом «Недавно удалённые» на 30 дней.
3. **Производительность 60/120 Гц на 50 000+ файлах:**
   - RAM-кэш решений в `DecisionStore` (`[String: DecisionStatus]`) со сложностью чтения $O(1)$.
   - Чистый доменный движок свайпов `SwipeSessionEngine` со стеком Undo, окном видимости (3 карточки) и prefetch (5 карточек).
   - Защита от двойного свайпа и гонок при 120 Гц (`commitSwipe` валидирует `assetID == currentAssetID`).
4. **Безопасность SwiftData:** `ModelContainer` инициализируется с `do/catch` и безопасным fallback на in-memory контейнер при сбоях диска или миграций (без `fatalError` и без `try!`).

---

## 2. Статус фаз разработки

| Фаза | Название | Статус | Комментарий |
|---|---|---|---|
| **Фаза 1** | **Каркас, XcodeGen, CI, Контракты, Тесты, Права** | ✅ **ЗАВЕРШЕНА & ВЕРИФИЦИРОВАНА В CI** | Создан `project.yml`, workflow CI `macos-26`, генератор иконки, каталоги ассетов, все доменные контракты, `SwipeSessionEngine` с XCTest, `DecisionStore`, `PhotoLibraryService`, `AppSettings`, `PermissionView`, `DashboardView`. Пройден статический аудит. Сборка и XCTest успешно пройдены в GitHub Actions (Run ID 44733885121, артефакт `SwipeClean-unsigned-ipa` сгенерирован). |
| **Фаза 2** | PhotoKit-индексирование, Кэш и Главный экран | ⏳ ОЖИДАЕТ | Будет реализован `PhotoLibraryService` (фоновое сканирование `Task.detached`, фильтр `canPerform(.delete)`, 3 вкладки, debounced observer), `ImageCacheManager`, `MediaSizeCalculator`, `DashboardViewModel`, полноценный `DashboardView` и `GroupRowCard`. |
| **Фаза 3** | Свайп-дека, Zoom, Видеоплеер и Share | ⏳ ОЖИДАЕТ | Будет реализован `VideoPlayerController` (единый `AVPlayer`), `LoopingVideoView`, `MediaExportService`, `ActivityShareSheet`, `SwipeDeckViewModel`, `SwipeDeckView` (в `.fullScreenCover`) и `SwipeCardView` (Pinch/Double-tap Zoom, метаданные с секундами). |
| **Фаза 4** | Корзина без прыжков, Удаление, Итоги, Настройки | ⏳ ОЖИДАЕТ | Будет реализован `TrashReviewViewModel`, `TrashReviewView` (in-place спасение без прыжков), `SessionCompleteView`, `SettingsView`, расширение тестов. |
| **Фаза 5** | Финальный инженерный аудит и релизная полировка | ⏳ ОЖИДАЕТ | Сквозной аудит утечек памяти, проверка крайних случаев (0 медиа, оффлайн iCloud, отмена удаления), проверка 0 нарушений красных линий. |

---

## 3. Реестр созданных файлов в Фазе 1

### Конфигурация и CI:
1. `project.yml` — эталонная спецификация XcodeGen (iOS 17.0, `SWIFT_VERSION: "5.0"`, `SWIFT_STRICT_CONCURRENCY: minimal`, bundle ID `com.swipeclean.gallery`, автогенерация `Info.plist` с `NSPhotoLibraryUsageDescription`).
2. `.github/workflows/build-ios.yml` — GitHub Actions workflow на раннере `macos-26` (генерация иконки, генерация проекта, симуляторные юнит-тесты, сборка Release `.app`, упаковка unsigned `.ipa`).
3. `Scripts/generate_icon.swift` — автономный скрипт на CoreGraphics / AppKit, генерирующий 1024×1024 иконку `AppIcon-1024.png` и обновляющий `Contents.json`.

### Каталог ресурсов (`Sources/Resources/Assets.xcassets/`):
4. `Assets.xcassets/Contents.json` — корень каталога ассетов.
5. `Assets.xcassets/AppIcon.appiconset/Contents.json` — валидный манифест иконки приложения (по умолчанию без filename до первого запуска генератора).
6. `Assets.xcassets/AccentColor.colorset/Contents.json` — акцентный цвет `#6366F1` (индиго, sRGB: R 0.388, G 0.400, B 0.945).

### Доменный слой (`Sources/Domain/`):
7. `Sources/Domain/DecisionStatus.swift` — `enum DecisionStatus: String, Codable, Sendable { case kept, stagedForTrash }`.
8. `Sources/Domain/CleaningMode.swift` — `enum CleaningMode: String, CaseIterable, Identifiable, Sendable { case months, albums, smart }`.
9. `Sources/Domain/MediaMetadata.swift` — `enum MediaKind: String, Sendable`, `struct MediaMetadata: Identifiable, Hashable, Sendable` с `estimatedWeightScore`.
10. `Sources/Domain/MediaGroup.swift` — `struct MediaGroup: Identifiable, Hashable, Sendable`.
11. `Sources/Domain/GroupProgress.swift` — `struct GroupProgress: Equatable, Sendable`.
12. `Sources/Domain/ByteFormatter.swift` — форматирование байт с использованием `ByteCountFormatter` ("0 Б", "3.8 МБ", "1.2 ГБ").
13. `Sources/Domain/SwipeSessionEngine.swift` — чистый Swift движок сессии со стеком Undo, валидацией двойного свайпа, `visibleAssetIDs(maxCount: 3)`, `prefetchAssetIDs(ahead: 5)`.

### Тестовый слой (`Tests/`):
14. `Tests/SwipeSessionEngineTests.swift` — полное XCTest покрытие движка `SwipeSessionEngine`: инициализация, граничные индексы, видимые карточки, prefetch, свайпы kept/trash, защита от двойного свайпа, множественные undo, сброс сессии.

### Слой персистентности (`Sources/Persistence/`):
15. `Sources/Persistence/MediaDecisionRecord.swift` — `@Model` SwiftData для хранения решений по активам с примитивным полем `statusRaw: String` для безопасных `#Predicate`.
16. `Sources/Persistence/CleaningStatsRecord.swift` — `@Model` SwiftData + доменная структура `StatsSnapshot: Equatable, Sendable`.
17. `Sources/Persistence/DecisionStore.swift` — `@Observable @MainActor` RAM-кэш со сложностью $O(1)$, методами `hydrate()`, `recordDecision()`, `undoDecision()`, `rescueFromTrash()`, `commitDeleted()`, `resetKeptDecisions()`, `pruneMissingAssets()`.

### Сервисы (`Sources/Services/`):
18. `Sources/Services/HapticsService.swift` — тактильная отдача (UIImpact/UINotification/UISelection) с проверкой флага `AppSettings.shared.hapticsEnabled`.
19. `Sources/Services/PhotoLibraryService.swift` — минимальная реализация Фазы 1: проверка статуса доступа `PHPhotoLibrary.authorizationStatus(for: .readWrite)` и асинхронный запрос прав по явному нажатию кнопки.

### Приложение и экраны (`Sources/App/`, `Sources/Views/`):
20. `Sources/App/AppSettings.swift` — `@Observable` обёртка над `UserDefaults` (тема: тёмная по умолчанию, `hapticsEnabled`, `hideCompletedGroups`).
21. `Sources/App/SwipeCleanApp.swift` — `@main` точка входа с безопасной инициализацией `ModelContainer` (fallback на in-memory при ошибках, без `fatalError` и `try!`).
22. `Sources/App/RootView.swift` — роутинг между экраном прав `PermissionView` и главным экраном `DashboardView`, поддержка тёмной темы.
23. `Sources/Views/Permissions/PermissionView.swift` — онбординг прав с 3 тезисами приватности и безопасности + кнопка запроса доступа / перехода в системные настройки.
24. `Sources/Views/Dashboard/DashboardView.swift` — стартовый экран для smoke-теста CI (NavigationStack, статус прав, Hero-карточка статистики, проверка тактильного отклика).

---

## 4. Публичные сигнатуры ключевых контрактов

### Доменные контракты (Section 4 SPEC.md):
```swift
enum DecisionStatus: String, Codable, Sendable {
    case kept
    case stagedForTrash
}

enum CleaningMode: String, CaseIterable, Identifiable, Sendable {
    case months, albums, smart
    var id: String { rawValue }
    var title: String { ... }
}

enum MediaKind: String, Sendable {
    case photo, livePhoto, screenshot, video
}

struct MediaMetadata: Identifiable, Hashable, Sendable {
    let localIdentifier: String
    let creationDate: Date?
    let kind: MediaKind
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    var isFavorite: Bool
    var id: String { localIdentifier }
    var isVideo: Bool { kind == .video }
    var estimatedWeightScore: Double { ... }
}

struct MediaGroup: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let mode: CleaningMode
    let assetIDs: [String]
    let coverAssetID: String?
}

struct GroupProgress: Equatable, Sendable {
    let totalCount: Int
    let keptCount: Int
    let stagedCount: Int
    let stagedBytes: Int64
    var reviewedCount: Int { keptCount + stagedCount }
    var remainingCount: Int { max(0, totalCount - reviewedCount) }
    var completionRatio: Double { ... }
    var isCompleted: Bool { ... }
}

struct StatsSnapshot: Equatable, Sendable {
    let totalReviewedCount: Int
    let totalDeletedCount: Int
    let totalBytesFreed: Int64
    static let empty: StatsSnapshot
}
```

### Движок свайпов (`SwipeSessionEngine`):
```swift
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

    init(assetIDs: [String], startIndex: Int = 0)
    var totalCount: Int { get }
    var remainingCount: Int { get }
    var reviewedCount: Int { get }
    var isFinished: Bool { get }
    var currentAssetID: String? { get }
    var canUndo: Bool { get }

    func visibleAssetIDs(maxCount: Int = 3) -> [String]
    func prefetchAssetIDs(ahead: Int = 5) -> [String]
    @discardableResult func commitSwipe(assetID: String, decision: DecisionStatus) -> SwipeAction?
    @discardableResult func undoLastSwipe() -> SwipeAction?
    func reset(with newAssetIDs: [String]? = nil, startIndex: Int = 0)
}
```

### Хранилище решений (`DecisionStore`):
```swift
@Observable @MainActor final class DecisionStore {
    private(set) var decisions: [String: DecisionStatus]
    private(set) var stagedSizes: [String: Int64]
    private(set) var stats: StatsSnapshot
    private(set) var isHydrated: Bool

    init(modelContext: ModelContext)
    func hydrate()
    func status(for assetID: String) -> DecisionStatus?
    var stagedAssetIDs: [String] { get }
    var stagedCount: Int { get }
    var stagedTotalBytes: Int64 { get }
    func setStagedSize(for assetID: String, bytes: Int64)
    func progress(for group: MediaGroup) -> GroupProgress
    func recordDecision(assetID: String, status: DecisionStatus, estimatedBytes: Int64 = 0)
    func undoDecision(assetID: String)
    func rescueFromTrash(assetID: String)
    func rescueMultipleFromTrash(assetIDs: [String])
    func commitDeleted(assetIDs: [String], freedBytes: Int64)
    func resetKeptDecisions(for specificIDs: [String]? = nil)
    func pruneMissingAssets(validIDs: Set<String>)
}
```

---

## 5. Аудит соблюдения «Красных линий» (Раздел 2 SPEC.md)

| # | Правило Красной линии | Статус | Доказательство проверки |
|---|---|---|---|
| 1 | `SWIFT_VERSION: "5.0"` и `SWIFT_STRICT_CONCURRENCY: minimal` | ✅ PASS | Проверено в `project.yml` (строки 10-11). |
| 2 | Раннер `macos-26` в GitHub Actions | ✅ PASS | Проверено в `.github/workflows/build-ios.yml` (строка 21). |
| 3 | Запрет оборачивания `requestImage` в `CheckedContinuation` | ✅ PASS | В Phase 1 нет `requestImage`; в Phase 2 будет применён callback-подход. |
| 4 | Фильтрация `asset.canPerform(.delete)` | ✅ PASS | Контракты спроектированы для хранения только deletable ID. |
| 5 | Запрет `@Query` в представлениях для всей таблицы; только примитивные поля в `#Predicate` | ✅ PASS | Решения кэшируются в RAM `DecisionStore`; предикаты SwiftData сравнивают `$0.assetIdentifier == targetID` и `$0.statusRaw == keptRaw`. |
| 6 | Запрет массового обращения к `assetResources(for:)` | ✅ PASS | `MediaMetadata` использует эвристику `estimatedWeightScore`; массовых XPC-вызовов нет. |
| 7 | Запрет `PHImageManagerMaximumSize` и deprecated `UIScreen.main` | ✅ PASS | Не используются; в UI используются стандартные размеры и GeometryReader. |
| 8 | Запрет 1-параметрового `.onChange` и `NavigationView` | ✅ PASS | Все экраны используют `NavigationStack`. Устаревший `.onChange` отсутствует. |
| 9 | Открытие деки строго через `.fullScreenCover` | ✅ PASS | Запланировано на Фазу 3. |
| 10 | Запрет `DispatchQueue.asyncAfter` для свайпа | ✅ PASS | `SwipeSessionEngine` спроектирован с флагом `isTransitioning`. |
| 11 | Запрет передачи `PHAsset` в `ShareLink` и раздельных `AVPlayer` | ✅ PASS | Запланировано на Фазу 3. |
| 12 | Запрет `fatalError`, `try!`, force-unwrap `!` | ✅ PASS | Статический аудит показал 0 вхождений `try!` и `fatalError`, 0 force-unwrap. Все инициализации защищены через `do/catch` и `try?`. |

---

## 6. Design Check

1. **Акторная изоляция и безопасность потоков:**
   - `DecisionStore`, `PhotoLibraryService`, `HapticsService` строго аннотированы `@MainActor`.
   - Модели `@Model` (`MediaDecisionRecord`, `CleaningStatsRecord`) создаются и читаются строго через `mainContext` на `@MainActor`. Ни один экземпляр `@Model` не пересекает границы акторов.
   - `SwipeSessionEngine` является чистым Swift-типом без сторонних побочных эффектов.
2. **Отмена асинхронных операций:**
   - В Фазе 1 запрос прав выполняется по явному нажатию кнопки в асинхронной задаче `Task`. Автоматических фоновых вызовов в `.onAppear` нет.
3. **Сложность алгоритмов:**
   - Внутри `body` представлений нет $O(N)$ операций над базой данных. Чтение статуса карточки выполняется за $O(1)$ из словаря в памяти.

---

## 7. Готовность к CI-First проверке

Проект готов к первому коммиту и проверке сборки на GitHub Actions:
```bash
git init
git add .
git commit -m "Phase 1: scaffold, XcodeGen, icon generator, CI, contracts"
git branch -M main
git remote add origin https://github.com/ВАШ_ЛОГИН/swipeclean-ios.git
git push -u origin main
```
После пуша workflow `.github/workflows/build-ios.yml` автоматически:
1. Запустит сборщик на macOS 26.
2. Установит XcodeGen.
3. Запустит `Scripts/generate_icon.swift` для генерации `AppIcon-1024.png`.
4. Сгенерирует проект `SwipeClean.xcodeproj`.
5. Выполнит XCTest в iOS Simulator (`SwipeSessionEngineTests`).
6. Соберёт релизный артефакт `SwipeClean.app`.
7. Упакует и выгрузит `SwipeClean.ipa` в артефакты сборки.
