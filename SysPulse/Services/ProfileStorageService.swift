import Foundation

struct ProfileStorageService {
    private let key = "SysPulse.savedServerProfiles.v1"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadProfiles() -> [ServerProfile] {
        guard let data = userDefaults.data(forKey: key),
              let snapshots = try? JSONDecoder().decode([StoredServerProfile].self, from: data) else {
            return []
        }
        return snapshots.map { $0.makeServerProfile() }
    }

    func saveProfiles(_ profiles: [ServerProfile]) {
        let snapshots = profiles.map { StoredServerProfile(profile: $0) }
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        userDefaults.set(data, forKey: key)
    }

    func clearProfiles() {
        userDefaults.removeObject(forKey: key)
    }
}

private struct StoredServerProfile: Codable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authenticationTypeRaw: String
    var credentialIdentifier: String?
    var tagsCSV: String
    var groupName: String?
    var icon: String
    var accentHex: String
    var serverTypeRaw: String
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(profile: ServerProfile) {
        self.id = profile.id
        self.name = profile.name
        self.host = profile.host
        self.port = profile.port
        self.username = profile.username
        self.authenticationTypeRaw = profile.authenticationTypeRaw
        self.credentialIdentifier = profile.credentialIdentifier
        self.tagsCSV = profile.tagsCSV
        self.groupName = profile.groupName
        self.icon = profile.icon
        self.accentHex = profile.accentHex
        self.serverTypeRaw = profile.serverTypeRaw
        self.statusRaw = profile.statusRaw
        self.createdAt = profile.createdAt
        self.updatedAt = profile.updatedAt
    }

    func makeServerProfile() -> ServerProfile {
        let profile = ServerProfile(
            id: id,
            name: name,
            host: host,
            port: port,
            username: username,
            authenticationType: SSHAuthenticationType(rawValue: authenticationTypeRaw) ?? .password,
            credentialIdentifier: credentialIdentifier,
            tags: tagsCSV.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) },
            groupName: groupName,
            icon: icon,
            accentHex: accentHex,
            serverType: ServerType(rawValue: serverTypeRaw) ?? .custom,
            status: ServerStatus(rawValue: statusRaw) ?? .unknown
        )
        profile.createdAt = createdAt
        profile.updatedAt = updatedAt
        return profile
    }
}

struct SettingsStorageService {
    private let settingsKey = "SysPulse.settings.v1"
    private let subscriptionKey = "SysPulse.subscription.v1"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadSettings() -> AppSettings {
        guard let data = userDefaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: settingsKey)
    }

    func loadSubscription() -> SubscriptionState {
        guard let data = userDefaults.data(forKey: subscriptionKey),
              let state = try? JSONDecoder().decode(SubscriptionState.self, from: data) else {
            return SubscriptionState()
        }
        return state
    }

    func saveSubscription(_ state: SubscriptionState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: subscriptionKey)
    }
}
