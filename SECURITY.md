# SECURITY.md

SysPulse проектируется как privacy-first приложение для администрирования собственных Linux-серверов пользователя.

## Keychain storage

- SSH passwords, private keys and passphrases must be stored only in iOS Keychain.
- `KeychainService` uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Plain text secrets must never be written to SwiftData, UserDefaults, logs or repository files.

## Face ID / Touch ID

- `BiometricLockService` uses LocalAuthentication.
- Saved profiles can be protected before opening sensitive credentials.
- If biometrics are unavailable, the app can fall back to device authentication in a later implementation.

## Command confirmation

Dangerous commands require explicit confirmation.

Examples:

- `reboot`
- `shutdown`
- `rm`
- `docker rm`
- `systemctl stop`
- `kill`
- `ufw` changes

Shortcuts / App Intents must not execute dangerous commands without opening SysPulse confirmation UI.

## Missing tools

- SysPulse may check commands like `command -v sensors`, `command -v docker`, `command -v jq`.
- Installation commands are shown as preview.
- Installation is never automatic.
- Docker installation is not automated; only guidance and warning are shown.

## Certificates and secrets

Never commit:

- `.p12`
- `.mobileprovision`
- `.env`
- private keys
- App Store Connect API keys
- provisioning profiles

`.gitignore` is configured to block these files.

## Telemetry

- No telemetry should be added without explicit consent.
- Demo Mode must work offline.
- Future analytics must be opt-in and documented in Privacy Policy.

## Remote execution model

- SysPulse does not download or execute code locally on iOS.
- SSH commands execute only on user-provided remote Linux servers.
- The user must initiate or confirm actions that can change server state.

## Reporting security issues

Until a public security email is configured, use GitHub Issues with no secrets attached. For private reports, add a dedicated support address before App Store release.
