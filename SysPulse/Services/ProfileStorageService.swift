import Foundation
import SwiftData

@MainActor
protocol ProfileRepository {
    func loadProfiles() throws -> [ServerProfile]
    func saveProfile(_ profile: ServerProfile) throws
    func deleteProfile(_ profile: ServerProfile) throws
    func deleteAllProfiles() throws
}

@MainActor
struct SwiftDataProfileRepository: ProfileRepository {
    private let modelContext: ModelContext
    private let legacyStorage: LegacyProfileStorageService?

    init(modelContext: ModelContext, legacyUserDefaults: UserDefaults? = .standard) {
        self.modelContext = modelContext
        self.legacyStorage = legacyUserDefaults.map { LegacyProfileStorageService(userDefaults: $0) }
    }

    func loadProfiles() throws -> [ServerProfile] {
        let profiles = try fetchProfiles()
        guard profiles.isEmpty, let legacyProfiles = legacyStorage?.loadProfiles(), !legacyProfiles.isEmpty else {
            return profiles
        }

        for profile in legacyProfiles {
            modelContext.insert(profile)
        }
        try modelContext.save()
        legacyStorage?.clearProfiles()
        return try fetchProfiles()
    }

    func saveProfile(_ profile: ServerProfile) throws {
        if let storedProfile = try fetchProfile(id: profile.id) {
            if storedProfile !== profile {
                storedProfile.applyPersistentMetadata(from: profile)
            }
        } else {
            modelContext.insert(profile)
        }
        try modelContext.save()
    }

    func deleteProfile(_ profile: ServerProfile) throws {
        if let storedProfile = try fetchProfile(id: profile.id) {
            modelContext.delete(storedProfile)
        }
        try modelContext.save()
    }

    func deleteAllProfiles() throws {
        for profile in try fetchProfiles() {
            modelContext.delete(profile)
        }
        try modelContext.save()
    }

    private func fetchProfiles() throws -> [ServerProfile] {
        let descriptor = FetchDescriptor<ServerProfile>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.name, order: .forward)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchProfile(id: UUID) throws -> ServerProfile? {
        var descriptor = FetchDescriptor<ServerProfile>(
            predicate: #Predicate { profile in
                profile.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

private extension ServerProfile {
    func applyPersistentMetadata(from profile: ServerProfile) {
        name = profile.name
        host = profile.host
        port = profile.port
        username = profile.username
        authenticationTypeRaw = profile.authenticationTypeRaw
        credentialIdentifier = profile.credentialIdentifier
        tagsCSV = profile.tagsCSV
        groupName = profile.groupName
        icon = profile.icon
        accentHex = profile.accentHex
        serverTypeRaw = profile.serverTypeRaw
        statusRaw = profile.statusRaw
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
    }
}

private struct LegacyProfileStorageService {
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
