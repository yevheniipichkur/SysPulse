import SwiftData

enum SysPulseModelContainerFactory {
    static let iCloudContainerIdentifier = "iCloud.com.yevheniipichkur.syspulse"

    static let schema = Schema([
        ServerProfile.self,
        TerminalSession.self,
        QuickCommand.self,
        CommandExecution.self,
        ServerGroup.self,
        AlertRule.self,
        ServerEvent.self
    ])

    static func makeContainer(iCloudSyncEnabled: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: iCloudSyncEnabled ? .private(iCloudContainerIdentifier) : .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
