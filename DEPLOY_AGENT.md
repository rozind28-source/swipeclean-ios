# SwipeClean — Инструкция автономной сборки и установки на iPhone (`DEPLOY_AGENT.md`)

> **Как запустить (команда для ИИ-агента):**
> Прочитай `DEPLOY_AGENT.md`. Определи мою ОС, проверь и установи все недостающие инструменты, собери приложение (автоматически исправляя ошибки компиляции, если возникнут), получи готовый `.ipa`/`.app` и установи его на мой подключённый iPhone. Строго соблюдай Раздел 1 (Границы безопасности).

---

## 0. Роль и цель агента

Ты — **Autonomous iOS Release & DevOps Engineer**.
Твоя задача — взять готовый код проекта `SwipeClean` в текущей директории и самостоятельно пройти весь путь до запуска приложения на физическом iPhone пользователя с минимальным участием человека:

1. Определить ОС и архитектуру (`macOS`, `Windows` или `Linux`; `x86_64` / `arm64`).
2. Проверить и установить недостающий софт (CLI-утилиты, USB-драйверы Apple, установщик `.ipa`).
3. Скомпилировать проект (локально на Mac **или** через облачный GitHub Actions на Windows/Linux).
4. **Самовосстановление (Self-Healing Loop):** если сборка или юнит-тесты упали — самостоятельно выгрузить логи ошибок Xcode, исправить код (не нарушая `SPEC.md`), пересобрать и повторять до зелёного статуса (максимум 5 итераций подряд, затем отчитаться).
5. Установить готовое приложение на подключённый по USB iPhone и провести пользователя через разовую активацию на самом телефоне.

---

## 1. Границы безопасности (КРИТИЧНО — НАРУШАТЬ ЗАПРЕЩЕНО)

1. **НИКОГДА не проси пользователя писать пароль от Apple ID, код 2FA или токен GitHub в чат!**
2. **НИКОГДА не сохраняй пароли/секреты в файлах проекта, скриптах или переменных окружения.**
3. Все шаги, требующие ввода пароля Apple ID, подтверждения 2FA или нажатия «Доверять» на экране iPhone, выполняются **интерактивно пользователем** (ты подготавливаешь команду/открываешь утилиту и чётко говоришь, что нажать).
4. Перед установкой любого системного ПО с правами администратора (`sudo` / UAC) коротко сообщи пользователю, что именно и зачем ставится.
5. Перед созданием нового GitHub-репозитория уточни у пользователя: **Public** (рекомендуется — безлимитные бесплатные macOS-сборки, секретов в коде нет) или **Private** (~190 бесплатных минут macOS/мес).

---

## 2. Шаг 1 — Автоопределение среды (Диагностика)

Выполни диагностику ОС, архитектуры и установленных утилит:

### macOS / Linux (bash/zsh):
```bash
uname -s -m
command -v git gh curl unzip python3
```
Если `uname -s == Darwin` (macOS), дополнительно проверь:
```bash
xcodebuild -version
command -v brew xcodegen
xcrun devicectl list devices
```
Если `uname -s == Linux`, дополнительно проверь:
```bash
command -v usbmuxd idevice_id plumesign
systemctl is-active usbmuxd 2>/dev/null || true
```

### Windows (PowerShell):
```powershell
[System.Environment]::OSVersion.VersionString
$env:PROCESSOR_ARCHITECTURE
Get-Command git, gh, winget, curl.exe -ErrorAction SilentlyContinue | Format-Table Name, Source
Get-Service "Apple Mobile Device Service" -ErrorAction SilentlyContinue
```

На основе результата выбери **Ветку A (macOS с Xcode)** или **Ветку B (Windows / Linux — облачная сборка через GitHub Actions + локальная заливка на iPhone)**.

---

## 3. Ветка A — Полный автомат на macOS (с Xcode)

### Шаг A1. Установка недостающих инструментов
1. Если нет `Xcode`: попроси пользователя установить Xcode из App Store и один раз открыть его (для принятия лицензии), затем проверь `xcodebuild -version`.
2. Если нет `xcodegen`:
   ```bash
   HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
   ```

### Шаг A2. Генерация иконки, проекта и прогон тестов
```bash
swift Scripts/generate_icon.swift
xcodegen generate
```
Проверь компиляцию и юнит-тесты на симуляторе (динамический поиск доступного iPhone):
```bash
SIM_ID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in sorted(data.get('devices', {}).items(), reverse=True):
    if 'iOS' in runtime:
        for d in devices:
            if d.get('isAvailable') and 'iPhone' in d.get('name', ''):
                print(d['udid']); sys.exit(0)
")
xcodebuild test \
  -project SwipeClean.xcodeproj \
  -scheme SwipeClean \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  CODE_SIGNING_ALLOWED=NO
```
*Если есть ошибки компиляции или падения тестов — исправь код и повтори до 100% успеха.*

### Шаг A3. Обнаружение подключённого iPhone
Попроси пользователя подключить iPhone по кабелю, разблокировать его и нажать **«Доверять»**. Затем найди устройство:
```bash
xcrun devicectl list devices
```
Запомни `Identifier` (UDID) подключённого iPhone.

### Шаг A4. Подпись, сборка под iPhone и установка через CLI
1. Проверь, настроен ли Team в Xcode (`security find-identity -v -p codesigning`).
   - Если сертификата/Team ещё нет — открой `open SwipeClean.xcodeproj` и попроси пользователя один раз добавить свой Apple ID в *Xcode -> Settings -> Accounts* и выбрать свой *Personal Team* в *SwipeClean -> Signing & Capabilities -> Team* (и при конфликте уникального Bundle ID сменить `com.swipeclean.gallery` на `com.swipeclean.<уникальный_суффикс>` в `project.yml`).
2. Собери подписанное приложение и установи его на iPhone прямо из терминала:
```bash
DEVICE_ID="<UDID_ИЗ_DEVICETCTL>"
TEAM_ID="<TEAM_ID_ЕСЛИ_ИЗВЕСТЕН>"

xcodebuild build \
  -project SwipeClean.xcodeproj \
  -scheme SwipeClean \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  ${TEAM_ID:+DEVELOPMENT_TEAM=$TEAM_ID}

xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  "build/Build/Products/Debug-iphoneos/SwipeClean.app"
```
3. Запусти приложение (если на iPhone уже доверен разработчик):
```bash
xcrun devicectl device process launch \
  --terminate-existing \
  --device "$DEVICE_ID" \
  com.swipeclean.gallery
```
*(Если iOS вернёт ошибку о недоверенном профиле или выключенном Developer Mode — перейди к Разделу 5).*

---

## 4. Ветка B — Полный автомат на Windows / Linux (без Mac)

### Шаг B1. Установка базовых CLI-инструментов и USB-драйверов Apple

#### На Windows (PowerShell):
1. Установи `Git` и `GitHub CLI` (если отсутствуют):
   ```powershell
   winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
   winget install --id GitHub.cli -e --accept-source-agreements --accept-package-agreements
   ```
   *(После установки обнови `PATH` в текущей сессии или перезапусти shell).*
2. Установи драйверы USB-связи с iPhone (**обязательно**, иначе ПК не увидит iPhone):
   - Проверь службу `Apple Mobile Device Service`:
     ```powershell
     Get-Service "Apple Mobile Device Service" -ErrorAction SilentlyContinue
     ```
   - Если службы нет — установи классический iTunes от Apple (содержит `Apple Mobile Device Support` и `usbmuxd`):
     ```powershell
     winget install --id Apple.iTunes -e --accept-source-agreements --accept-package-agreements
     ```
   - Убедись, что служба запущена (может потребоваться запуск из-под администратора или перезагрузка, если драйвер только что установился).
3. Установи кроссплатформенный open-source установщик `.ipa` — **`plumesign` (CLI от `claration/Impactor`)**:
   - Определи архитектуру (`x86_64` для обычных ПК, `arm64` для Windows on ARM):
     ```powershell
     $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x86_64" }
     New-Item -ItemType Directory -Force -Path "$HOME\bin" | Out-Null
     curl.exe -fL "https://github.com/claration/Impactor/releases/latest/download/plumesign-windows-$arch.exe" -o "$HOME\bin\plumesign.exe"
     & "$HOME\bin\plumesign.exe" --help
     ```
   - **Резервный вариант (GUI):** если CLI не заработает или пользователю удобнее окно с кнопками, установи `Impactor GUI`:
     ```powershell
     winget install --id CLARATION.Impactor.GUI -e --accept-source-agreements --accept-package-agreements
     ```
     *(Или предложи скачать классический Sideloadly с официального сайта `sideloadly.io`).*

#### На Linux (Ubuntu / Debian — адаптируй под `dnf`/`pacman` при необходимости):
1. Установи `git`, `gh`, `usbmuxd` и `libimobiledevice`:
   ```bash
   sudo apt-get update
   sudo apt-get install -y git curl unzip usbmuxd libimobiledevice-utils
   sudo systemctl enable --now usbmuxd
   ```
   Если `gh` не установлен — установи официальный пакет `gh` (по инструкции `cli.github.com` или `sudo apt-get install -y gh`).
2. Скачай **`plumesign` CLI** от `claration/Impactor`:
   ```bash
   ARCH=$(uname -m)
   [ "$ARCH" = "aarch64" ] && ARCH="arm64"
   mkdir -p "$HOME/.local/bin"
   curl -fL "https://github.com/claration/Impactor/releases/latest/download/plumesign-linux-$ARCH" -o "$HOME/.local/bin/plumesign"
   chmod +x "$HOME/.local/bin/plumesign"
   "$HOME/.local/bin/plumesign" --help
   ```
   *(Резервный CLI для Linux: `Dadoum/Sideloader` или `Impactor-linux-*.AppImage` из релизов `claration/Impactor`).*

---

### Шаг B2. Авторизация в GitHub и публикация репозитория
1. Проверь авторизацию `gh`:
   ```bash
   gh auth status
   ```
   Если не авторизован — попроси пользователя выполнить в терминале `gh auth login --web` (подтвердить одноразовый код в браузере).
2. Проверь наличие git-репозитория и `origin`:
   - Если `.git` нет:
     ```bash
     git init
     git branch -M main
     ```
   - Добавь `.gitignore` (исключи `build/`, `dist/`, `Payload/`, `*.ipa`, `*.xcodeproj`, `.DS_Store`, `DerivedData/`).
   - Сделай коммит:
     ```bash
     git add .
     git commit -m "Build SwipeClean iOS"
     ```
   - Если `git remote get-url origin` не задан — уточни у пользователя видимость (`--public` или `--private`) и создай репозиторий одной командой:
     ```bash
     gh repo create SwipeClean-iOS --public --source=. --remote=origin --push
     ```
   - Если `origin` уже настроен — просто сделай `git push -u origin main`.

---

### Шаг B3. Автономная облачная сборка + Self-Healing цикл (ДО 5 ИТЕРАЦИЙ)

1. Дождись появления запуска workflow (или запусти вручную, если триггер `push` отключён):
   ```bash
   gh workflow run "Build Unsigned iOS IPA" --ref main
   sleep 5
   RUN_ID=$(gh run list --workflow="Build Unsigned iOS IPA" --limit 1 --json databaseId --jq '.[0].databaseId')
   echo "Watching GitHub Actions Run: $RUN_ID"
   ```
2. Следи за сборкой до завершения:
   ```bash
   gh run watch "$RUN_ID" --exit-status
   ```
3. **Если команда вернула ненулевой код (сборка или тесты упали):**
   - Выгрузи логи упавших шагов:
     ```bash
     gh run view "$RUN_ID" --log-failed
     ```
   - Найди точные строки с `error:` (Swift/Xcode/XcodeGen/XCTest).
   - Исправь причину ошибки в исходном коде или `project.yml`, **не нарушая контракты из `SPEC.md`**.
   - Закоммить фикс с понятным сообщением (`git add . && git commit -m "Fix CI build: <причина>" && git push`), обнови `AGENT_STATE.md` и **повтори Шаг B3**.
   - Повторяй цикл до получения зелёной сборки (лимит: 5 автопопыток; если за 5 попыток проблема не решилась — остановись и покажи пользователю точный лог ошибки).

---

### Шаг B4. Скачивание и верификация готового `.ipa`

Когда `gh run watch` завершился успешно:
```bash
rm -rf ./dist
mkdir -p ./dist
gh run download "$RUN_ID" -n SwipeClean-unsigned-ipa -D ./dist
ls -lh ./dist/SwipeClean.ipa
```
Проверь, что файл `./dist/SwipeClean.ipa` существует, его размер больше 100 КБ и внутри архива есть `Payload/SwipeClean.app/Info.plist` и бинарник `Payload/SwipeClean.app/SwipeClean`:
```bash
unzip -l ./dist/SwipeClean.ipa | grep -E "Info\.plist|SwipeClean\.app/SwipeClean$"
```

---

### Шаг B5. Проверка подключения iPhone и установка `.ipa`

1. Попроси пользователя:
   - Подключить iPhone к компьютеру **по USB-кабелю**.
   - Разблокировать экран iPhone и при появлении окна нажать **«Доверять этому компьютеру»** (ввести код-пароль iPhone).
2. Проверь, что система видит подключённый iPhone:
   - **Linux:** `idevice_id -l` (должен вернуть 40-символьный или 24-символьный UDID).
   - **Windows:** проверь список USB-устройств Apple или проверь командой обнаружения устройств внутри `plumesign --help` (например, `plumesign devices` / `plumesign list` — **всегда сначала прочитай актуальный вывод `plumesign --help`**, не угадывай флаги!).
3. **Изучи точные флаги установленной версии `plumesign`:**
   ```bash
   plumesign --help
   ```
   *(Обязательно прочитай справку подкоманд `install` / `sign` / `auth` перед запуском, так как CLI-аргументы могут меняться между релизами).*
4. **Передай пользователю интерактивную команду установки** (чтобы пользователь сам ввёл свой Apple ID и 2FA-код в защищённом терминале — не в чате!):
   - Либо запусти интерактивный терминал / открой `Impactor GUI`, указав точный путь к `./dist/SwipeClean.ipa`.
   - *Рекомендация для пользователя:* при желании можно использовать отдельный запасной Apple ID (burner account) — бесплатный аккаунт подписывает до 3 приложений сроком на 7 дней, затем приложение просто переподписывается без потери данных и прогресса чистки.
   - *Если `plumesign` сообщил об ошибке Anisette-сервера:* переключи Anisette-сервер в настройках `Impactor` (или запусти запасной GUI: `Impactor` / `Sideloadly`).

---

## 5. Финальная активация на iPhone (выполняется пользователем 1 раз)

После того как `.ipa` скопирован и подписан на iPhone, выведи пользователю эту короткую инструкцию (40 секунд):

1. **Включить «Режим разработчика»** *(появляется только после первой установки подписанного приложения)*:
   - *Настройки -> Конфиденциальность и безопасность -> Режим разработчика* (в самом низу) -> **Включить** -> перезагрузить iPhone -> подтвердить включение.
2. **Доверять своему Apple ID:**
   - *Настройки -> Основные -> VPN и управление устройством* -> нажать на свой Apple ID -> **Доверять**.
3. **Запустить SwipeClean** с рабочего стола и выдать доступ к «Фото» (**«Полный доступ»** для лучшей работы).

---

## 6. Опционально: настройка вечного автопродления по Wi-Fi (SideStore)

Если пользователь не хочет подключать iPhone к ПК каждые 7 дней для обновления бесплатной 7-дневной подписи, предложи (по его запросу) автоматическую настройку **SideStore**:
1. Скачать последний официальный `SideStore.ipa` с `https://github.com/SideStore/SideStore/releases/latest`.
2. Установить `SideStore.ipa` и сгенерировать pairing-файл устройства через `Impactor` (поддерживает установку SideStore + pairing-файл в один клик).
3. Передать `./dist/SwipeClean.ipa` на iPhone (через «Файлы» / локальный HTTP-сервер в Wi-Fi: `python3 -m http.server 8080 --directory ./dist` -> открыть в Safari на iPhone и сохранить в «Файлы»).
4. Установить `SwipeClean.ipa` внутри SideStore — далее SideStore будет продлевать подпись по Wi-Fi без компьютера.

---

## 7. Чек-лист завершения деплоя (отчёт агента)

Считай задачу завершённой только когда подтверждены все пункты:
- [ ] Сборка (`xcodebuild build`) и юнит-тесты (`xcodebuild test`) завершились без ошибок.
- [ ] Артефакт `./dist/SwipeClean.ipa` (или `.app` на macOS) получен и проверен на целостность.
- [ ] Необходимые локальные драйверы/утилиты установлены, подключённый iPhone обнаружен.
- [ ] Приложение установлено на iPhone (или пользователю выдана готовая проверенная интерактивная команда/окно `Impactor` с точным путём к `SwipeClean.ipa`).
- [ ] Ни один пароль, токен или 2FA-код не запрашивался в чате и не попал в файлы репозитория.