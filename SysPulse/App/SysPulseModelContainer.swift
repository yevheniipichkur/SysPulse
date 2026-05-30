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
        ServerEvent.self,
        MetricSnapshot.self,
        SSHTunnel.self,
        CommandSnippet.self,
        SSHKeyPair.self
    ])

    static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
