# SwipeClean для iOS (v2.0): Полное руководство и ТЗ для ИИ-агента

Документ состоит из двух частей:
1. **Инструкция для владельца** — запуск агента по принципу *CI-First*, сборка `.ipa` (с Mac или без Mac) и установка на iPhone.
2. **Системная спецификация для ИИ-агента** — протокол инженерного мышления, жёсткие контракты, защита от скрытых багов iOS/PhotoKit/SwiftData и эталонные конфиги XcodeGen/CI.

---

# ЧАСТЬ 1. Инструкция для владельца

## Шаг 1. Подготовка и старт ИИ-агента
1. Создайте пустую папку `SwipeClean-iOS` и сохраните этот файл внутри как `SPEC.md`.
2. Откройте папку в **Cursor**, **Claude Code**, **Windsurf** или **Cline**.
3. Отправьте агенту команду:
   > Прочитай `SPEC.md` (Часть 2). Строго соблюдай Протокол мышления (Раздел 0), Красные линии (Раздел 2), Контракты (Раздел 4) и ведение `AGENT_STATE.md`. Выполни ТОЛЬКО **Фазу 1**, проведи проверку, обнови `AGENT_STATE.md` и остановись.

## Шаг 2. Принцип «CI-First» (Windows / Linux без Mac)
Не ждите окончания всех 5 фаз для первой проверки компиляции:
1. **Сразу после Фазы 1** создайте репозиторий на GitHub и отправьте каркас:
   ```bash
   git init
   git add .
   git commit -m "Phase 1: scaffold, XcodeGen, icon generator, CI, contracts"
   git branch -M main
   git remote add origin https://github.com/ВАШ_ЛОГИН/swipeclean-ios.git
   git push -u origin main
   ```
   > **Совет по лимитам GitHub Actions:** в коде нет серверов и секретных ключей. В **публичном (Public)** репозитории macOS-сборки полностью бесплатны и безлимитны. В **приватном (Private)** репозитории macOS-раннеры расходуют бесплатную квоту примерно в 10 раз быстрее Linux (~190 минут/мес) — в этом случае закомментируйте блок `push:` в `.github/workflows/build-ios.yml` и запускайте сборку вручную через **Actions -> Build Unsigned iOS IPA -> Run workflow** после Фазы 1, Фазы 3 и Фазы 5.
2. Дождитесь зелёной галочки в **Actions** (~3–5 минут). Это докажет, что `project.yml`, генерация иконки, юнит-тесты и упаковка `.ipa` работают.
3. Напишите агенту:
   > Фаза 1 собралась успешно. Прочитай `AGENT_STATE.md` и `SPEC.md`, выполни **Фазу 2** и остановись.
4. Повторите для Фаз 3, 4 и 5. Если CI упал — скопируйте строки с `error:` из лога и отправьте агенту: *«Исправь ошибки компиляции из лога Xcode, не меняя контракты из SPEC.md»*.

## Шаг 3. Сборка на Mac (если есть Mac)
```bash
brew install xcodegen
swift Scripts/generate_icon.swift
xcodegen generate
open SwipeClean.xcodeproj
```
Выберите Apple ID в **Signing & Capabilities -> Team**, подключите iPhone и нажмите **⌘R**.

## Шаг 4. Установка `.ipa` на iPhone (без Mac)
Скачайте `SwipeClean.ipa` из **Artifacts** успешного запуска GitHub Actions:
- **Быстрый тест — Sideloadly (Windows/macOS):** установите классический iTunes (с сайта Apple, не из Microsoft Store) и iCloud -> перетащите `SwipeClean.ipa` в Sideloadly -> введите Apple ID -> **Start**.
- **На постоянку — SideStore:** ставится один раз с ПК, затем автоматически продлевает 7-дневную бесплатную подпись по Wi-Fi прямо на телефоне.
- **На iPhone (один раз):** *Настройки -> Конфиденциальность и безопасность -> Режим разработчика (Вкл)* и *Настройки -> Основные -> VPN и управление устройством -> Доверять*.
- *Лимит бесплатного Apple ID:* одновременно можно держать подписанными до 3 сторонних приложений (включая сам SideStore).

---
---

# ЧАСТЬ 2. Системная спецификация v2.0 для ИИ-агента

## 0. Протокол инженерного мышления (ОБЯЗАТЕЛЬНО)

Ты — **Principal iOS Engineer** (SwiftUI, PhotoKit, AVFoundation, SwiftData, Swift Concurrency).

Перед написанием кода и при сдаче каждой фазы соблюдай 5 правил:
1. **Память между фазами (`AGENT_STATE.md`):** в конце каждой фазы создавай/обновляй `AGENT_STATE.md` в корне проекта (список файлов, их публичные сигнатуры, статус фаз, риски). В начале новой фазы **сначала прочитай `AGENT_STATE.md`**.
2. **Design Check перед кодом (кратко, 3–4 пункта в начале отчёта):**
   - Какие типы живут на `@MainActor`, что выполняется в `Task.detached` / `actor`, и гарантировано ли, что ни один `@Model` SwiftData не пересекает границу актора?
   - Какие `PHImageRequestID`, `Task` и `AVPlayerItem` отменяются при свайпе, закрытии экрана и уходе в фон?
   - Нет ли `O(N)` операций внутри SwiftUI `body` и массовых XPC-вызовов `PHAssetResource` на галерее из 50 000 файлов?
3. **Никаких заглушек** (`// TODO`, `fatalError("Not implemented")`, моковых массивов вместо PhotoKit). Единственное исключение — минимальный `DashboardView` в Фазе 1 для smoke-теста CI, полностью заменяемый в Фазе 2.
4. **Верификация в конце каждой фазы:**
   - Если доступен macOS с Xcode: выполни `swift Scripts/generate_icon.swift && xcodegen generate` и тестовую сборку.
   - Если окружение без Xcode (Windows/Linux): проведи **Статический аудит** всех `.swift`, `.yml`, `.json` файлов на отсутствующие `import`, несовпадение типов с Разделом 4 и нарушения Раздела 2.
5. **Строгая пофазность:** выполняй строго одну фазу за раз и останавливайся для подтверждения пользователя.

---

## 1. Цель и инварианты продукта

Разработать нативное iOS-приложение **SwipeClean** (аналог *Sponge — Gallery Cleaner*) для разбора фото и видео свайпами.

1. **100% оффлайн и приватно:** без сети (кроме системного iCloud PhotoKit), серверов, аналитики и сторонних зависимостей (0 пакетов SPM/CocoaPods).
2. **Двухэтапное безопасное удаление:** свайп влево никогда не удаляет файл мгновенно — он переводит его в буферную Корзину (`stagedForTrash`). Физическое удаление выполняется только с экрана Корзины одним системным запросом iOS (файлы перемещаются в системный альбом «Недавно удалённые» на 30 дней и синхронно удаляются из iCloud).
3. **Плавность 60/120 Гц на 50 000+ файлах:** O(1)-кэш решений в RAM, ленивый подсчёт веса, prefetch следующих 5 фото, один переиспользуемый `AVPlayer`.

---

## 2. «Красные линии» — Строго запрещённые антипаттерны

Нарушение любого пункта ниже считается критическим дефектом:

1. ❌ `SWIFT_VERSION: "5.9"` в `project.yml` — Xcode принимает только мажорный языковой режим (`"5.0"` или `"6.0"`). Используй строго **`SWIFT_VERSION: "5.0"`** + **`SWIFT_STRICT_CONCURRENCY: minimal`**.
2. ❌ Устаревший раннер `macos-14` в GitHub Actions — используй **`macos-26`**.
3. ❌ Оборачивание `PHImageManager.requestImage` (при `deliveryMode = .opportunistic`) в `withCheckedContinuation` / `withCheckedThrowingContinuation` — `.opportunistic` вызывает callback несколько раз и гарантированно крашит приложение. Используй callback-замыкание с хранением `PHImageRequestID`.
4. ❌ Включение в группы и пакетное удаление активов с `asset.canPerform(.delete) == false` (общие альбомы `.albumCloudShared` и фото, синхронизированные с ПК) — это валит всю транзакцию `PHAssetChangeRequest.deleteAssets`.
5. ❌ Использование `@Query` во View для выгрузки всей таблицы решений (тормоза на 50 000 записей) и сравнение `enum` внутри SwiftData `#Predicate` (в `#Predicate` сравнивай только примитивные `String` поля вроде `statusRaw`).
6. ❌ Массовый вызов `PHAssetResource.assetResources(for:)` при сканировании Дашборда или обращение к `value(forKey: "fileSize")` без предварительной проверки `responds(to: NSSelectorFromString("fileSize"))` и приведения через `NSNumber`.
7. ❌ Запрос `PHImageManagerMaximumSize` для карточек свайпа (риск OOM на 48 МП ProRAW) и использование deprecated `UIScreen.main` (используй `@Environment(\.displayScale)` и `GeometryReader`).
8. ❌ Однопараметровый `.onChange(of:) { value in }` и `NavigationView` (используй iOS 17 синтаксис `.onChange(of:) { _, newValue in }` и `NavigationStack`).
9. ❌ Открытие `SwipeDeckView` через `NavigationLink` (системный свайп «Назад» от левого края конфликтует со свайпом карточки вправо) — открывай строго через **`.fullScreenCover`**.
10. ❌ Использование `DispatchQueue.main.asyncAfter` для синхронизации вылета карточки и удаления элемента из стека (используй iOS 17 `withAnimation(.spring(...)) { ... } completion: { ... }` + флаг `isTransitioning` в `SwipeSessionEngine`) и `ForEach(items.indices)` (только `id: \.localIdentifier`).
11. ❌ Передача `PHAsset` в `ShareLink` (используй `MediaExportService` + `ActivityShareSheet`) или создание отдельного `AVPlayer` внутри каждой карточки.
12. ❌ Ручное создание/редактирование `.xcodeproj`, вызовы `fatalError`, `try!`, force-unwrap `!` на опционалах PhotoKit и замыкания `NotificationCenter`/`PHImageManager` без `[weak self]`.

---

## 3. Структура проекта

```text
SwipeClean/
├── AGENT_STATE.md                        # Живой журнал состояния между фазами
├── project.yml                           # Эталонный XcodeGen конфиг (Раздел 5)
├── Scripts/
│   └── generate_icon.swift               # Генератор 1024×1024 AppIcon на CoreGraphics
├── .github/
│   └── workflows/
│       └── build-ios.yml                 # Эталонный CI-workflow (Раздел 6)
├── Sources/
│   ├── App/
│   │   ├── SwipeCleanApp.swift           # @main, безопасная инициализация ModelContainer
│   │   ├── RootView.swift                # Роутинг прав доступа + схема темы
│   │   └── AppSettings.swift             # @Observable обёртка над UserDefaults
│   ├── Domain/                           # Чистый Swift (0 зависимостей UIKit/PhotoKit)
│   │   ├── DecisionStatus.swift
│   │   ├── CleaningMode.swift
│   │   ├── MediaMetadata.swift
│   │   ├── MediaGroup.swift
│   │   ├── GroupProgress.swift
│   │   ├── SwipeSessionEngine.swift      # Стек, Undo, защита от гонок при 120 Гц
│   │   └── ByteFormatter.swift
│   ├── Persistence/
│   │   ├── MediaDecisionRecord.swift     # @Model SwiftData
│   │   ├── CleaningStatsRecord.swift     # @Model SwiftData + StatsSnapshot
│   │   └── DecisionStore.swift           # @MainActor: O(1) RAM-кэш + Fetch-Upsert
│   ├── Services/
│   │   ├── PhotoLibraryService.swift     # Права, фоновый скан, группы, debounced observer, delete
│   │   ├── ImageCacheManager.swift       # PHCachingImageManager, prefetch 5, iCloud %
│   │   ├── MediaSizeCalculator.swift     # actor-кэш + безопасный responds(to:) для fileSize
│   │   ├── VideoPlayerController.swift   # Единый AVPlayer, токен актуальности, умная AVAudioSession
│   │   ├── MediaExportService.swift      # Экспорт оригинала фото/видео в tmp/ для Share
│   │   └── HapticsService.swift          # Тактильный отклик с учётом AppSettings
│   ├── ViewModels/
│   │   ├── DashboardViewModel.swift
│   │   ├── SwipeDeckViewModel.swift
│   │   └── TrashReviewViewModel.swift
│   ├── Views/
│   │   ├── Permissions/
│   │   │   └── PermissionView.swift
│   │   ├── Dashboard/
│   │   │   ├── DashboardView.swift
│   │   │   └── GroupRowCard.swift
│   │   ├── SwipeDeck/
│   │   │   ├── SwipeDeckView.swift
│   │   │   ├── SwipeCardView.swift
│   │   │   ├── LoopingVideoView.swift
│   │   │   └── ActivityShareSheet.swift
│   │   ├── TrashReview/
│   │   │   ├── TrashReviewView.swift
│   │   │   └── SessionCompleteView.swift
│   │   └── Settings/
│   │       └── SettingsView.swift
│   └── Resources/
│       └── Assets.xcassets/
│           ├── Contents.json
│           ├── AppIcon.appiconset/
│           │   └── Contents.json
│           └── AccentColor.colorset/
│               └── Contents.json
└── Tests/
    └── SwipeSessionEngineTests.swift
```

---

## 4. Замороженные контракты домена (ИМЕНА НЕ МЕНЯТЬ)

```swift
// Sources/Domain/DecisionStatus.swift
enum DecisionStatus: String, Codable, Sendable {
    case kept
    case stagedForTrash
}

// Sources/Domain/CleaningMode.swift
enum CleaningMode: String, CaseIterable, Identifiable, Sendable {
    case months     // "Месяцы"
    case albums     // "Альбомы"
    case smart      // "Подборки"
    var id: String { rawValue }
}

// Sources/Domain/MediaMetadata.swift
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

    /// Мгновенная эвристика «тяжести» видео в RAM без обращения к PHAssetResource
    var estimatedWeightScore: Double {
        duration * Double(max(pixelWidth, 1) * max(pixelHeight, 1))
    }
}

// Sources/Domain/MediaGroup.swift
struct MediaGroup: Identifiable, Hashable, Sendable {
    let id: String              // Напр. "month-2026-11", "album-<id>", "smart-videos"
    let title: String
    let subtitle: String?
    let mode: CleaningMode
    let assetIDs: [String]      // Только deletable localIdentifier
    let coverAssetID: String?
}

// Sources/Domain/GroupProgress.swift
struct GroupProgress: Equatable, Sendable {
    let totalCount: Int
    let keptCount: Int
    let stagedCount: Int
    let stagedBytes: Int64

    var reviewedCount: Int { keptCount + stagedCount }
    var remainingCount: Int { max(0, totalCount - reviewedCount) }
    var completionRatio: Double {
        guard totalCount > 0 else { return 1.0 }
        return Double(reviewedCount) / Double(totalCount)
    }
    var isCompleted: Bool { totalCount > 0 && remainingCount == 0 }
}

// Sources/Persistence/CleaningStatsRecord.swift
struct StatsSnapshot: Equatable, Sendable {
    let totalReviewedCount: Int
    let totalDeletedCount: Int
    let totalBytesFreed: Int64
    static let empty = StatsSnapshot(totalReviewedCount: 0, totalDeletedCount: 0, totalBytesFreed: 0)
}
```

---

## 5. Эталонный `project.yml` и генератор иконки

### 5.1. `project.yml` (использовать точно эту структуру)
Блок `info:` заставляет XcodeGen автоматически создать валидный `Info.plist` со всеми обязательными системными ключами (`CFBundleExecutable`, `CFBundleIdentifier`, `CFBundlePackageType` и др.), чтобы `.ipa` гарантированно принимался Sideloadly и SideStore.

```yaml
name: SwipeClean
options:
  bundleIdPrefix: com.swipeclean
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.0"
    SWIFT_STRICT_CONCURRENCY: minimal
    TARGETED_DEVICE_FAMILY: "1"
    SUPPORTS_MACCATALYST: NO
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"

targets:
  SwipeClean:
    type: application
    platform: iOS
    sources:
      - path: Sources
        excludes:
          - "App/Info.plist"
    info:
      path: Sources/App/Info.plist
      properties:
        CFBundleDisplayName: SwipeClean
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        ITSAppUsesNonExemptEncryption: false
        NSPhotoLibraryUsageDescription: "Приложению нужен доступ к фото и видео, чтобы вы могли удобно разбирать галерею свайпами и освобождать память. Все данные обрабатываются строго на вашем устройстве."
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.swipeclean.gallery
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        CODE_SIGN_STYLE: Automatic
    scheme:
      testTargets:
        - SwipeCleanTests

  SwipeCleanTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
    dependencies:
      - target: SwipeClean
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.swipeclean.gallery.tests
        GENERATE_INFOPLIST_FILE: YES
```

### 5.2. `Scripts/generate_icon.swift` и `Assets.xcassets`
- Напиши автономный скрипт `Scripts/generate_icon.swift` (`import Foundation`, `import CoreGraphics`, `import AppKit`), который рисует аккуратную градиентную иконку `1024×1024` (тёмно-индиговый градиент, стилизованная стопка карточек со свайпом и искрой) и сохраняет её в `Sources/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, обновляя `Contents.json` (добавляя `"filename": "AppIcon-1024.png"`).
- По умолчанию в репозитории `AppIcon.appiconset/Contents.json` хранится валидным **без** поля `"filename"` (чтобы не ломать сборку, если скрипт ещё не запускался).
- `AccentColor.colorset/Contents.json`: яркий акцентный цвет (`#6366F1` / индиго).

---

## 6. Эталонный `.github/workflows/build-ios.yml`

```yaml
name: Build Unsigned iOS IPA

on:
  workflow_dispatch:
  push:
    branches: [ main ]
    paths:
      - 'Sources/**'
      - 'Tests/**'
      - 'Scripts/**'
      - 'project.yml'
      - '.github/workflows/build-ios.yml'

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    runs-on: macos-26
    env:
      HOMEBREW_NO_AUTO_UPDATE: "1"
      HOMEBREW_NO_INSTALL_CLEANUP: "1"

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Toolchain Info
        run: |
          xcodebuild -version
          swift --version

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate App Icon (1024x1024)
        run: swift Scripts/generate_icon.swift

      - name: Generate Xcode Project
        run: xcodegen generate

      - name: Run Unit Tests (iOS Simulator)
        run: |
          set -o pipefail
          SIM_ID=$(xcrun simctl list devices available -j | python3 -c "
          import json, sys
          data = json.load(sys.stdin)
          for runtime, devices in sorted(data.get('devices', {}).items(), reverse=True):
              if 'iOS' in runtime:
                  for d in devices:
                      if d.get('isAvailable') and 'iPhone' in d.get('name', ''):
                          print(d['udid'])
                          sys.exit(0)
          ")
          echo "Using Simulator UDID: $SIM_ID"
          xcodebuild test \
            -project SwipeClean.xcodeproj \
            -scheme SwipeClean \
            -destination "platform=iOS Simulator,id=$SIM_ID" \
            CODE_SIGNING_ALLOWED=NO

      - name: Build Unsigned Release App
        run: |
          set -o pipefail
          xcodebuild build \
            -project SwipeClean.xcodeproj \
            -scheme SwipeClean \
            -configuration Release \
            -sdk iphoneos \
            -destination "generic/platform=iOS" \
            -derivedDataPath build \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            DEVELOPMENT_TEAM=""

      - name: Package & Verify Unsigned IPA
        run: |
          APP_PATH="build/Build/Products/Release-iphoneos/SwipeClean.app"
          test -d "$APP_PATH"
          test -f "$APP_PATH/SwipeClean"
          test -f "$APP_PATH/Info.plist"
          rm -rf Payload SwipeClean.ipa
          mkdir -p Payload
          cp -R "$APP_PATH" Payload/
          zip -r -y SwipeClean.ipa Payload
          ls -lh SwipeClean.ipa

      - name: Upload IPA Artifact
        uses: actions/upload-artifact@v4
        with:
          name: SwipeClean-unsigned-ipa
          path: SwipeClean.ipa
          retention-days: 14
```

---

## 7. Архитектурная логика подсистем

### 7.1. Права доступа (`PhotoLibraryService` + `PermissionView`)
- Читай статус через `PHPhotoLibrary.authorizationStatus(for: .readWrite)`.
- **НЕ вызывай `requestAuthorization` автоматически в `.onAppear`** (чтобы не вешать UI-тесты на симуляторе) — запрашивай только по нажатию кнопки в `PermissionView`.
- Состояния:
  - `.notDetermined` -> онбординг (3 тезиса о приватности и 30 днях в «Недавно удалённых») + кнопка «Разрешить доступ».
  - `.authorized` -> `DashboardView`.
  - `.limited` -> `DashboardView` + верхний баннер («Выбрать ещё» через `presentLimitedLibraryPicker(from:)` и «Настройки» через `UIApplication.openSettingsURLString`).
  - `.denied` / `.restricted` -> экран с инструкцией и кнопкой перехода в Настройки.

### 7.2. Быстрое индексирование 50 000+ фото (`PhotoLibraryService`)
- Сканирование выполняется в `Task.detached(priority: .userInitiated)` и строит словарь `[String: PHAsset]`, `[String: MediaMetadata]` и списки `MediaGroup`.
- **Обязательный фильтр:** включай только активы с `asset.canPerform(.delete) == true`.
- **3 режима группировки:**
  1. **Месяцы (`CleaningMode.months`):** по `Year + Month` (`creationDate`, от новых к старым, русская локаль `Locale(identifier: "ru_RU")` с заглавной буквы: «Ноябрь 2026»). Без даты -> «Без даты» в конце.
  2. **Альбомы (`CleaningMode.albums`):** пользовательские альбомы (`.album`, **исключая `.albumCloudShared`**) + смарт-альбомы (Избранное, Скриншоты, Селфи, Панорамы, Live Photos, Видео, Портреты). Внутри брать только ID из проверенного пула `canPerform(.delete)`. Пустые альбомы пропускать.
  3. **Подборки (`CleaningMode.smart`):**
     - *«Тяжёлые видео»* — все `.video`, отсортированные мгновенно по убыванию `estimatedWeightScore` (0 мс, без XPC!).
     - *«Скриншоты»* — `kind == .screenshot`.
     - *«В этот день»* — медиафайлы за текущий день и месяц прошлых лет (показывать при количестве ≥ 1).
     - *«Случайные 50»* — до 50 случайных неразобранных (`status == nil`) файлов из всей медиатеки (с возможностью пересобрать).
- **Debounced Observer (`PHPhotoLibraryChangeObserver`):** debounce **600 мс** (отмена предыдущей `Task` + `Task.sleep(for: .milliseconds(600))`), флаг `suppressReloadDuringBatchDelete` на время нашего удаления, затем фоновое переиндексирование и вызов `decisionStore.pruneMissingAssets(validIDs:)`.
- **Пакетное удаление (`deleteAssets(ids:)`):**
  1. Повторно фетчит живые `PHAsset` (`PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)`) и фильтрует `canPerform(.delete)`.
  2. Вызывает `PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets as NSArray) }`.
  3. При отказе пользователя (`PHPhotosError.userCancelled` / код `3072`) возвращает `.cancelled` без показа ошибки и без изменения корзины/статистики.

### 7.3. Картинки, iCloud и вес (`ImageCacheManager`, `MediaSizeCalculator`)
- `ImageCacheManager`: один `PHCachingImageManager`, получает `displayScale: CGFloat` из `@Environment(\.displayScale)`.
  - `targetSize` = размер контейнера × `displayScale`, ограниченный потолком `2048 px` по длинной стороне.
  - Опции: `isNetworkAccessAllowed = true`, `deliveryMode = .opportunistic`, `resizeMode = .fast`.
  - Callback-метод (БЕЗ `CheckedContinuation`!) возвращает `PHImageRequestID`, передаёт на `@MainActor` прогресс iCloud (`progressHandler`: `0...1`) и результат (`image`, `isDegraded`, `isInCloud`, `hasError`), игнорируя `PHImageCancelledKey`.
  - Оффлайн iCloud: при `isInCloud && hasError` не вешай вечный спиннер — покажи бейдж *«В iCloud (нет сети)»*, оставляя карточку доступной для свайпа.
  - Prefetching: `startCachingImages` для следующих **5** карточек и `stopCachingImages` для пройденных; отмена `PHImageRequestID` в `.onDisappear`.
- `MediaSizeCalculator`: `actor` с RAM-кэшем `[String: Int64]`, вызывается лениво (текущая карточка, +5 вперёд, корзина):
  ```swift
  private static let fileSizeSelector = NSSelectorFromString("fileSize")

  private static func safeResourceSize(_ resource: PHAssetResource) -> Int64 {
      guard resource.responds(to: fileSizeSelector),
            let number = resource.value(forKey: "fileSize") as? NSNumber else { return 0 }
      return number.int64Value
  }
  ```

### 7.4. Видеоплеер и экспорт (`VideoPlayerController`, `MediaExportService`)
- `VideoPlayerController` (`@Observable @MainActor`): **строго один `AVPlayer`** на весь `SwipeDeckView`.
  - Защита от «видео-призрака»: хранит `activeAssetID: String?` и `activeRequestID: PHImageRequestID`. При смене карточки отменяет прошлый запрос, ставит паузу, очищает `replaceCurrentItem(with: nil)`, а в callback `requestPlayerItem` проверяет `guard self.activeAssetID == requestedID else { return }`.
  - Умная `AVAudioSession`:
    - `isMuted == true` (по умолчанию): `.setCategory(.ambient, options: .mixWithOthers)` — не ставит на паузу Spotify / Apple Music / подкасты.
    - Явный Unmute (`isMuted == false`): `.setCategory(.playback, options: .mixWithOthers)` + `.setActive(true)` — звук играет даже при включённом рычажке беззвучного режима iPhone.
    - Возврат в Mute, закрытие экрана или `scenePhase != .active`: пауза + возврат `.ambient` + `setActive(false, options: .notifyOthersOnDeactivation)`.
  - Зацикливание через `AVPlayerItemDidPlayToEndTime` с `[weak self]`.
- `MediaExportService`: асинхронно экспортирует оригинал фото (`requestImageDataAndOrientation`) или видео (`PHAssetResourceManager.writeData` / `requestAVAsset`) в `FileManager.default.temporaryDirectory`, передаёт `URL` в `ActivityShareSheet` (`UIActivityViewController`), в `completionWithItemsHandler` удаляет временный файл.

### 7.5. Хранилище и движок свайпов (`DecisionStore`, `SwipeSessionEngine`)
- `DecisionStore` (`@Observable @MainActor`):
  - В `SwipeCleanApp` создание `ModelContainer` обёрнуто в `do/catch` с fallback на in-memory контейнер (**без `fatalError`**).
  - Однократно гидратируется при запуске в RAM-словари `decisions: [String: DecisionStatus]` и `stagedSizes: [String: Int64]` (O(1) чтение прогресса для 50 000 фото).
  - Запись — через явный `FetchDescriptor` по примитивному `assetIdentifier` -> update или insert -> `try? context.save()`.
  - Точные правила статистики:
    - Первый свайп (`kept` / `stagedForTrash`) -> `totalReviewedCount += 1`.
    - `Undo` -> удаляет запись и делает `totalReviewedCount = max(0, totalReviewedCount - 1)`.
    - Успешное удаление из Корзины -> удаляет записи удалённых ID, `totalDeletedCount += N`, `totalBytesFreed += bytes`.
    - «Спасение» из Корзины -> переводит статус в `.kept` (`totalReviewedCount` не меняется).
    - «Сброс прогресса» -> удаляет только записи `kept` (не трогает `stagedForTrash` и `CleaningStatsRecord`).
- `SwipeSessionEngine` (чистый Swift в `Sources/Domain/`, покрыт `XCTest`):
  - Хранит очередь неразобранных `assetIDs`, `currentIndex`, стек `undoStack`, флаг `isTransitioning`.
  - `visibleAssetIDs(maxCount: 3)` и `prefetchAssetIDs(ahead: 5)`.
  - `commitSwipe(assetID:decision:)` проверяет `assetID == currentAssetID` (защита от двойного свайпа).
  - `undoLastSwipe()` откатывает `currentIndex` на 1 и возвращает запись для отката в `DecisionStore`.

---

## 8. UX/UI экранов

Стиль: тёмная эстетика по умолчанию (`#0B0C10` фон, `#16181F` карточки), скругления `24pt`, материалы `.ultraThinMaterial`, отклики через `HapticsService` (уважают `AppSettings.hapticsEnabled`).

1. **`DashboardView` + `GroupRowCard`:**
   - Заголовок «SwipeClean», кнопка Настроек, фильтр «Скрывать разобранные», баннер `.limited` при частичном доступе.
   - Hero-карточка: крупно «Освобождено: X ГБ», ниже «Проверено» и «Удалено».
   - Глобальный красный баннер корзины (при `totalStagedCount > 0`): «В корзине N файлов (X МБ) — Проверить и удалить».
   - Вкладки `Месяцы | Альбомы | Подборки` + `LazyVStack` с `GroupRowCard` (обложка `56×56pt`, прогресс `42 / 120`, прогресс-бар, зелёная галочка 100%, красный бейдж корзины группы, **Context Menu** «Сбросить прогресс этой группы»).
   - Открытие группы — строго через **`.fullScreenCover(item: $selectedGroup)`** со своим `NavigationStack` внутри.
2. **`SwipeDeckView` + `SwipeCardView`:**
   - Верхняя панель: `✕`, название группы, остаток (`14 из 85`), пилюля корзины группы (`🗑 7 • 34 МБ`).
   - `ZStack` из максимум 3 карточек (`ForEach(visibleItems, id: \.localIdentifier)`, `.allowsHitTesting(isTop)`), нижние карточки плавно подтягиваются по `scaleEffect` (`0.95`/`0.90`) и `offset(y:)`.
   - **Pinch-to-Zoom (`MagnifyGesture`) + двойной тап (1× ↔ 2.5×):** при `zoomScale > 1.01` свайп карточки отключён и работает панорамирование увеличенного фото; при смене карточки зум сбрасывается.
   - При `zoomScale == 1.0`: `DragGesture` (X/Y, наклон `±14°`), красная рамка + штамп **«УДАЛИТЬ»** (влево), зелёная + **«ОСТАВИТЬ»** (вправо); порог `> 110pt` или флинг `> 220pt`; вылет через iOS 17 `withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { ... } completion: { ... }` с защитой `isTransitioning`.
   - Внизу карточки поверх градиента: дата и время **с секундами** (`14 нояб. 2026, 18:42:07`), разрешение (`4032×3024`), размер (`3.8 МБ`), бейджи (`ВИДЕО 0:18`, `LIVE`, `СКРИНШОТ`), кнопка звука/паузы для видео; в центре при скачивании — капсула `Загрузка из iCloud 45%`.
   - 5 нижних кнопок: **Undo**, красная **Удалить**, **Поделиться** (с мини-спиннером экспорта), зелёная **Оставить**, **Избранное** (`PHAssetChangeRequest` toggle `isFavorite`).
   - Конец группы: если в корзине группы есть файлы — приглашение перейти в корзину; если пуста — `SessionCompleteView`.
3. **`TrashReviewView` (без прыжков сетки):**
   - Сетка 3 колонки (`LazyVGrid`, отступ `2pt`), подсказка «Нажмите на фото, чтобы спасти его от удаления».
   - **Тап по ячейке на месте** переключает её в `rescuedIDs` (приглушённая плитка `opacity 0.45` + зелёная галочка «Оставить»); сетка не прыгает! В тулбаре «Спасти все / Выбрать все».
   - Закреплённая нижняя панель: «К удалению: 14 из 18 • 248 МБ» + кнопка **«Удалить выбранные (14)»** (при 0 выбранных -> «Сохранить спасённые и закрыть»).
   - При отмене iOS — тихое восстановление кнопки без ошибок и без потери состояния. При успехе — коммит `rescued -> kept`, удаление записей, обновление статистики, haptic `.success` -> `SessionCompleteView`.
4. **`SessionCompleteView`:** `.symbolEffect(.bounce)`, статистика сессии (удалено файлов, освобождено памяти), памятка про 30 дней в «Недавно удалённых» и iCloud, кнопка «На главную».
5. **`SettingsView`:** тема (Системная / Тёмная по умолчанию / Светлая), тумблер Haptics, тумблер «Скрывать полностью разобранные группы», кнопка «Сбросить весь прогресс просмотра» (`confirmationDialog`, удаляет только `kept`), блок «О приложении» (`1.0.0`, 100% оффлайн).

---

## 9. План разработки по фазам (CI-First) и финальный аудит

- **Фаза 1 (Каркас, XcodeGen, Иконка, CI, Контракты, Тесты, Права):**
  - Создай `project.yml`, `.github/workflows/build-ios.yml`, `Scripts/generate_icon.swift`, `Assets.xcassets`.
  - Создай `Sources/Domain/*` (контракты + `SwipeSessionEngine` + `ByteFormatter`) и `Tests/SwipeSessionEngineTests.swift`.
  - Создай `Sources/Persistence/*`, `Sources/App/*`, `HapticsService`, минимальный `PhotoLibraryService` (права доступа), `PermissionView` и временный `DashboardView` («Готово к Фазе 2»).
  - Обнови `AGENT_STATE.md`. **Остановись — владелец проверит первый зелёный `.ipa` и тесты в GitHub Actions.**
- **Фаза 2 (PhotoKit-индексирование, Кэш и Главный экран):**
  - Заверши `PhotoLibraryService` (фоновое индексирование, `canPerform(.delete)`, 3 вкладки включая «В этот день», debounced observer, пакетное удаление).
  - Реализуй `ImageCacheManager`, `MediaSizeCalculator`, `DashboardViewModel`, полноценный `DashboardView` и `GroupRowCard`.
  - Обнови `AGENT_STATE.md` и остановись.
- **Фаза 3 (Свайп-дека, Zoom, Видеоплеер и Share):**
  - Реализуй `VideoPlayerController`, `LoopingVideoView`, `MediaExportService`, `ActivityShareSheet`.
  - Реализуй `SwipeDeckViewModel`, `SwipeDeckView` (в `.fullScreenCover`) и `SwipeCardView` (физика, Pinch/Double-Tap Zoom, метаданные с секундами, iCloud %, Undo, Избранное, Share, prefetch 5 вперёд).
  - Обнови `AGENT_STATE.md` и остановись.
- **Фаза 4 (Корзина без прыжков, Пакетное удаление, Итоги, Настройки):**
  - Реализуй `TrashReviewViewModel`, `TrashReviewView`, `SessionCompleteView`, `SettingsView`.
  - Расширь `Tests/SwipeSessionEngineTests.swift` тестами граничных случаев (пустая очередь, двойной свайп, Undo на 0-м элементе, расчёт `GroupProgress`).
  - Обнови `AGENT_STATE.md` и остановись.
- **Фаза 5 (Финальный инженерный аудит):**
  - Построчно проверь проект на 0 нарушений **Раздела 2 (Красные линии)** и 100% соответствие **Разделу 4 (Контракты)**.
  - Проверь отсутствие утечек памяти (`[weak self]`), висящих временных файлов Share, недостающих `import` и необработанных пустых состояний (пустая галерея, 0 видео, 0 скриншотов, отмена удаления, оффлайн iCloud, 0 выбранных в корзине).
  - Обнови `AGENT_STATE.md` финальным отчётом.