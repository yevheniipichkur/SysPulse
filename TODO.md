# TODO.md

## MVP

- [x] SwiftUI structure.
- [x] Auto-seeding removed; app starts from real saved SSH profiles only.
- [x] Server list.
- [x] Add/Edit Server profile form.
- [x] Server details.
- [x] Real SSH metrics refresh.
- [x] Terminal UI.
- [x] Mobile-first SSH terminal layout with connection bar and accessory keys.
- [x] Quick Commands.
- [x] Settings.
- [x] Paywall.
- [x] Localization.
- [x] Runtime language switching in Settings.
- [x] Expanded EN/UK/RU/PL localization for main app, widgets and permission prompts.
- [x] GitHub Actions.
- [x] Local metadata persistence for saved profiles.
- [x] Command safety analyzer tests.

## Next

- [x] Real SSH integration for password auth and command execution.
- [x] Private key SSH authentication for OpenSSH RSA and ED25519 keys.
- [x] Real Linux metrics collection over SSH.
- [x] Move profile persistence fully into SwiftData-backed repository.
- [x] Docker monitoring command builders and real SSH run actions.
- [x] systemd monitoring command builders and real SSH run actions.
- [x] Widgets snapshot data bridge with App Group-ready fallback.
- [x] Live Activities updates from active app usage.
- [x] iCloud sync.
- [x] TestFlight upload with production signing profiles.
- [x] Real StoreKit 2 product loading, purchase, restore and entitlement listener.
- [x] StoreKit product configuration in App Store Connect.
- [x] Real server profile persistence through SwiftData UI.
- [x] App icon.
- [ ] App Store screenshots.
- [x] App Group entitlements for app and WidgetKit extension.
- [x] Enable App Group capability in Apple Developer and provisioning profiles.
- [x] Parse real Docker/systemd/process/log command output into structured SwiftUI lists.

## Pro Features

- [x] SSH Port Forwarding / Tunnels — define tunnel rules, test reachability, copy desktop SSH command.
- [x] Custom Quick Commands — user-defined commands stored in SwiftData, CRUD UI in Commands tab.
- [x] Server Groups / Tags — group filter chips in ServersView, groupName already on ServerProfile.
- [x] Log Browser — browse /var/log/*.log files over SSH, tail content, search within output.
- [x] SSH Key Manager — generate ED25519 key pairs via CryptoKit, store private key in Keychain, copy public key.
- [x] Command Snippets — multi-line reusable snippets with categories, copy/insert actions.

## Future

- [ ] Optional backend for push monitoring.
- [ ] Team accounts.
- [ ] Web dashboard.
- [ ] Encrypted profile sharing.
- [ ] Alert rules and notification scheduling.
- [ ] Cloud-based status history.

