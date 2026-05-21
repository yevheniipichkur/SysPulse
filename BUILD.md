# BUILD.md

Документ описывает сборку SysPulse локально и через GitHub Actions.

## Требования

- Xcode 16.x или новее.
- iOS SDK 18 или новее.
- XcodeGen.
- Apple Developer Account нужен только для signed IPA и TestFlight.

## Локальная сборка через Xcode

На Mac:

```bash
brew install xcodegen
xcodegen generate
open SysPulse.xcodeproj
```

В Xcode:

1. Выберите scheme `SysPulse`.
2. Выберите iPhone Simulator или Generic iOS Device.
3. Для локального запуска на симуляторе нажмите Run.
4. Для устройства укажите Team ID и Bundle ID в Signing & Capabilities.

## Сборка через xcodebuild

Unsigned compile check:

```bash
xcodegen generate
xcodebuild build \
  -project SysPulse.xcodeproj \
  -scheme SysPulse \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

Tests:

```bash
xcodebuild test \
  -project SysPulse.xcodeproj \
  -scheme SysPulse \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  CODE_SIGNING_ALLOWED=NO
```

Archive:

```bash
xcodebuild archive \
  -project SysPulse.xcodeproj \
  -scheme SysPulse \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/SysPulse.xcarchive
```

## Сборка через GitHub Actions

Workflow: `.github/workflows/ios-build.yml`.

Запускается:

- при push в `main`;
- вручную через `workflow_dispatch`.

Что делает workflow:

1. Checkout repository.
2. Select Xcode.
3. Print Xcode version.
4. Install XcodeGen.
5. Generate `SysPulse.xcodeproj`.
6. Cache Swift packages.
7. Build unsigned debug, если signing secrets отсутствуют или включён ручной `run_tests`.
8. Run tests только при ручном запуске с `run_tests=true`.
9. Create signed archive при наличии signing secrets.
10. Patch archive `CFBundleVersion` номером GitHub Actions run.
11. Export IPA при наличии signing secrets.
12. Upload artifacts.
13. Upload to TestFlight при наличии App Store Connect secrets.

## Signing secrets

Добавьте в GitHub repository settings:

- `APPLE_TEAM_ID`
- `APPLE_BUNDLE_ID`
- `APPLE_CERTIFICATE_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`
- `APPLE_PROVISIONING_PROFILE_WIDGETS_BASE64`
- `APPSTORE_CONNECT_API_KEY_ID`
- `APPSTORE_CONNECT_API_ISSUER_ID`
- `APPSTORE_CONNECT_API_KEY_BASE64`

Если secrets отсутствуют, workflow всё равно выполняет unsigned compile check. Тесты по умолчанию отключены для ускорения TestFlight-сборок; включите `run_tests` при ручном запуске workflow.

## Генерация IPA

IPA появляется только если есть certificate и provisioning profile.

Важно: для WidgetKit extension нужен отдельный provisioning profile для bundle id `com.yevheniipichkur.syspulse.widgets`. Если включён App Group `group.com.yevheniipichkur.syspulse`, App Group должен быть включён и в app profile, и в widget profile.

## Где менять Bundle ID

В `project.yml`:

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.yevheniipichkur.syspulse
```

Для widget:

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.yevheniipichkur.syspulse.widgets
```

В GitHub Actions можно переопределить app bundle через secret:

```text
APPLE_BUNDLE_ID
```

## Где менять Team ID

Team ID задаётся в GitHub secret:

```text
APPLE_TEAM_ID
```

Для локального Xcode можно указать Team вручную в Signing & Capabilities после генерации проекта.

## Troubleshooting

`xcodegen: command not found`:

```bash
brew install xcodegen
```

`No profiles for bundle id`:

- Проверьте `APPLE_BUNDLE_ID`.
- Проверьте provisioning profile.
- Для widget extension создайте отдельный profile или wildcard profile.

`Signing certificate is invalid`:

- Пересоздайте Apple Distribution certificate.
- Проверьте пароль `APPLE_CERTIFICATE_PASSWORD`.
- Убедитесь, что `.p12` экспортирован вместе с private key.

`Simulator iPhone 16 not found`:

- Измените destination в workflow на доступный симулятор.
- Посмотрите список в логе шага `xcrun simctl list runtimes`.

`Export IPA failed`:

- Проверьте method в `ExportOptions.plist`.
- Проверьте Team ID.
- Проверьте, что provisioning profile соответствует certificate.

## Windows / VS Code

На Windows нельзя локально собрать iOS IPA через Xcode. Рабочий путь:

1. Редактировать код в VS Code.
2. Commit и push в GitHub.
3. Запускать GitHub Actions.
4. Скачивать artifact из Actions.
5. Для TestFlight настроить Apple secrets.
