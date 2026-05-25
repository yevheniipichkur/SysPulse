# GITHUB_SETUP.md

Инструкция для работы с SysPulse через GitHub, если вы используете Windows / VS Code и не работаете на Mac.

## Клонировать репозиторий

```bash
git clone https://github.com/yevheniipichkur/SysPulse.git
cd SysPulse
```

## Открыть проект в VS Code

```bash
code .
```

Основные файлы:

- `project.yml` — описание Xcode-проекта для XcodeGen.
- `SysPulse/` — iOS app source.
- `SysPulseWidgets/` — WidgetKit extension.
- `.github/workflows/ios-build.yml` — сборка в GitHub Actions.

## Как пушить изменения

```bash
git status
git add .
git commit -m "Describe change"
git push origin main
```

Push в `main` автоматически запускает workflow **iOS Build**.

## Как включить GitHub Actions

1. Откройте репозиторий GitHub.
2. Перейдите во вкладку **Actions**.
3. Если GitHub попросит разрешить workflows, нажмите **I understand my workflows, go ahead and enable them**.
4. Выберите workflow **iOS Build**.

## Ручной запуск сборки

1. Откройте GitHub repository.
2. Перейдите в **Actions**.
3. Выберите **iOS Build**.
4. Нажмите **Run workflow**.
5. Выберите branch `main`.
6. Включите `run_tests`, только если хотите отдельно прогнать XCTest перед упаковкой.
7. Включите `validate_with_altool`, только если нужен отдельный App Store Connect validation pass перед upload.
8. Нажмите зелёную кнопку **Run workflow**.

Для быстрых TestFlight-сборок оставляйте `run_tests` и `validate_with_altool` выключенными. Workflow всё равно соберёт signed archive, экспортирует IPA и перед upload проверит bundle version, icon metadata и widget extension.

## Где скачать artifact

1. Откройте конкретный workflow run.
2. Дождитесь завершения.
3. Внизу страницы найдите **Artifacts**.
4. Скачайте `syspulse-ios-build`.

Artifact содержит логи сборки и exported IPA, если он был создан. Большой archive и SwiftPM cache не загружаются, чтобы TestFlight-пуш проходил быстрее.

## Какие secrets добавить

Repository → Settings → Secrets and variables → Actions → New repository secret.

Нужны:

- `APPLE_TEAM_ID`
- `APPLE_BUNDLE_ID`
- `APPLE_CERTIFICATE_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`
- `APPLE_PROVISIONING_PROFILE_WIDGETS_BASE64`
- `APPSTORE_CONNECT_API_KEY_ID`
- `APPSTORE_CONNECT_API_ISSUER_ID`
- `APPSTORE_CONNECT_API_KEY_BASE64`

## Как получить Apple certificate

Нужен Mac или доступ к macOS runner/помощнику с Keychain.

Общий процесс:

1. В Apple Developer создайте **Apple Distribution Certificate**.
2. Сгенерируйте CSR через Keychain Access.
3. Скачайте certificate.
4. Установите certificate в Keychain.
5. Экспортируйте certificate + private key в `.p12`.
6. Задайте пароль.
7. Закодируйте `.p12` в Base64:

```bash
base64 -i certificate.p12 | pbcopy
```

На Windows можно использовать:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("certificate.p12")) | Set-Clipboard
```

Скопированное значение добавьте в `APPLE_CERTIFICATE_BASE64`.

## Как получить provisioning profile

В Apple Developer:

1. Certificates, Identifiers & Profiles.
2. Identifiers → создайте App ID для Bundle ID.
3. Profiles → создайте App Store provisioning profile.
4. Выберите App ID и distribution certificate.
5. Скачайте `.mobileprovision`.
6. Закодируйте в Base64:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("profile.mobileprovision")) | Set-Clipboard
```

Добавьте значение в `APPLE_PROVISIONING_PROFILE_BASE64`.

Для WidgetKit extension нужен отдельный App ID `com.yevheniipichkur.syspulse.widgets` и отдельный provisioning profile. Его Base64 добавьте в `APPLE_PROVISIONING_PROFILE_WIDGETS_BASE64`.

## Как включить App Group для виджетов

В Apple Developer:

1. Certificates, Identifiers & Profiles → Identifiers.
2. App Groups → создайте `group.com.yevheniipichkur.syspulse`.
3. Откройте App ID `com.yevheniipichkur.syspulse` → включите **App Groups** → отметьте `group.com.yevheniipichkur.syspulse`.
4. Откройте App ID `com.yevheniipichkur.syspulse.widgets` → включите **App Groups** → отметьте тот же group.
5. Пересоздайте App Store provisioning profile для app и widget.
6. Обновите secrets `APPLE_PROVISIONING_PROFILE_BASE64` и `APPLE_PROVISIONING_PROFILE_WIDGETS_BASE64`.

После этого приложение и WidgetKit extension смогут читать один shared defaults store для snapshots.

## Как добавить App Store Connect API key

В App Store Connect:

1. Users and Access.
2. Integrations → App Store Connect API.
3. Создайте key с доступом для TestFlight upload.
4. Скачайте `.p8`.
5. Сохраните:
   - Key ID → `APPSTORE_CONNECT_API_KEY_ID`
   - Issuer ID → `APPSTORE_CONNECT_API_ISSUER_ID`
   - `.p8` в Base64 → `APPSTORE_CONNECT_API_KEY_BASE64`

Windows Base64:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8")) | Set-Clipboard
```

## Как отправить билд в TestFlight

1. Настройте Bundle ID в App Store Connect.
2. Добавьте signing secrets.
3. Добавьте App Store Connect API secrets.
4. Запустите **iOS Build** вручную или сделайте push в `main`.
5. Workflow экспортирует IPA и выполнит `xcrun altool --upload-app`.
6. После обработки билд появится в TestFlight.

## Что делать, если нет Mac

Можно вести разработку на Windows:

- писать Swift-код и docs в VS Code;
- коммитить и пушить в GitHub;
- использовать GitHub Actions для compile check и archive;
- для production signing всё равно нужны Apple certificate и provisioning profile, которые обычно создаются через Apple Developer + Keychain на Mac.

Если Mac совсем недоступен, попросите доверенного человека один раз создать `.p12` и provisioning profile, затем храните их только в GitHub Actions Secrets.
