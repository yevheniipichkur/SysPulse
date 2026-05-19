# SysPulse

**Linux Monitor & SSH Terminal** — премиальное iOS-приложение для мониторинга Linux-серверов, Raspberry Pi, VPS, Docker-hosts, NAS и домашней инфраструктуры.

SysPulse создаётся как нативный SwiftUI-продукт: красивый мониторинг, защищённый SSH Terminal, быстрые команды, диагностика missing tools, demo mode для App Store Review и архитектура, готовая к реальной SSH-интеграции.

## Главные функции

- Demo Mode без реального сервера: Raspberry Pi Home Server, VPS Production, Docker Lab.
- Liquid Glass-style UI: glass cards, floating tab bar, blur materials, soft shadows, dark mode first.
- Servers screen с CPU, RAM, Disk, Network, Temperature, Uptime, Health Score и sparkline.
- Server details: Overview, Processes, Disks, Docker, Services, Logs, Packages, Terminal, Actions.
- SSH Terminal UI с tabs, history, accessory bar, themes и mock session.
- Quick Commands с safety levels и обязательным подтверждением dangerous actions.
- Command safety analyzer для `reboot`, `rm`, `docker rm`, `systemctl stop`, `kill`, `ufw` changes и package manager actions.
- Missing Tools screen с preview install commands и ручным подтверждением.
- Metadata-only persistence для server profiles; секреты остаются только в Keychain.
- StoreKit 2 paywall skeleton: Monthly, Yearly, Lifetime.
- Settings: security, appearance, language, data, hidden Developer / QA menu.
- WidgetKit, ActivityKit и App Intents scaffolds.
- Keychain wrapper и Face ID / Touch ID unlock service.
- GitHub Actions build workflow для Windows-разработки без Mac.

## Скриншоты

Плейсхолдеры для App Store Connect:

- `Screenshots/01-Servers.png`
- `Screenshots/02-Monitor.png`
- `Screenshots/03-Terminal.png`
- `Screenshots/04-Commands.png`
- `Screenshots/05-Paywall.png`

## Free vs Pro

Free:

- 1 real server profile.
- Basic dashboard.
- Basic terminal.
- 3 quick commands.
- 1 terminal theme.
- Manual refresh.

Pro:

- Unlimited servers.
- Unlimited terminal sessions.
- Docker monitoring.
- systemd monitoring.
- Logs viewer.
- Widgets and Live Activities.
- iCloud sync placeholder.
- Premium terminal themes.
- Command snippets and groups.
- Smart Insights.
- Export session logs.
- Advanced security settings.

## Технологии

- SwiftUI, SwiftData.
- Keychain, LocalAuthentication.
- StoreKit 2.
- WidgetKit.
- ActivityKit / Live Activities.
- App Intents / Shortcuts.
- Localizable.strings: English, Ukrainian, Russian, Polish.
- XcodeGen + xcodebuild.
- GitHub Actions.

Минимальная версия: **iOS 18**.

## Безопасность

- Пароли и SSH keys должны храниться только в iOS Keychain.
- Server profile storage сохраняет только metadata и Keychain reference, без secret material.
- В репозитории нет сертификатов, `.p12`, provisioning profiles или `.env`.
- Dangerous commands требуют подтверждения.
- Установка пакетов не запускается автоматически.
- Demo Mode позволяет Apple Review тестировать UI и Pro flows без настоящего SSH-сервера.

Подробнее: [SECURITY.md](SECURITY.md).

## Как собрать

На Mac:

```bash
brew install xcodegen
xcodegen generate
xcodebuild build -project SysPulse.xcodeproj -scheme SysPulse -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO
```

Через GitHub Actions:

1. Откройте репозиторий на GitHub.
2. Перейдите в **Actions**.
3. Выберите **iOS Build**.
4. Нажмите **Run workflow**.
5. Дождитесь сборки.
6. Скачайте artifact или проверьте TestFlight, если настроены signing secrets.

Подробнее: [BUILD.md](BUILD.md) и [GITHUB_SETUP.md](GITHUB_SETUP.md).

## Roadmap

MVP:

- SwiftUI structure.
- Demo Mode.
- Server list.
- Server details.
- Mock metrics.
- Terminal UI.
- Quick Commands.
- Settings.
- Paywall.
- Localization.
- GitHub Actions.

Next:

- Real SSH integration через SwiftNIO SSH, NMSSH или libssh2-compatible layer.
- Реальный Docker/systemd/logs monitoring.
- Widgets with shared App Group storage.
- Live Activities updates.
- iCloud sync.
- TestFlight upload.

Future:

- Optional backend for push monitoring.
- Team accounts.
- Web dashboard.
- Encrypted profile sharing.

## App Store notes

См. [APPSTORE_NOTES.md](APPSTORE_NOTES.md). Приложение не скачивает и не исполняет код локально на iPhone. Remote commands выполняются только на серверах пользователя через SSH и только после явного действия пользователя.
