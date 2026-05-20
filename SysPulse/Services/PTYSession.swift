import Foundation
import NIOCore
import Citadel

final class PTYSession {
    var onOutput: ((String) -> Void)?
    var onDisconnect: ((Error?) -> Void)?

    private var task: Task<Void, Never>?
    private var inputContinuation: AsyncStream<ByteBuffer>.Continuation?

    func connect(to server: ServerProfile, using sshClient: SSHClientProtocol) {
        task?.cancel()
        let (inputStream, inputCont) = AsyncStream<ByteBuffer>.makeStream()
        inputContinuation = inputCont
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try await sshClient.makeCitadelClient(for: server)
                defer { Task { try? await client.close() } }
                try await client.withTTY { ttyOutput, stdinWriter in
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await buffer in inputStream {
                                try Task.checkCancellation()
                                try await stdinWriter.write(buffer)
                            }
                        }
                        group.addTask { [weak self] in
                            for try await chunk in ttyOutput {
                                try Task.checkCancellation()
                                let text: String
                                switch chunk {
                                case .stdout(var b):
                                    text = b.readString(length: b.readableBytes) ?? ""
                                case .stderr(var b):
                                    text = b.readString(length: b.readableBytes) ?? ""
                                }
                                guard !text.isEmpty else { continue }
                                let cb = self?.onOutput
                                await MainActor.run { cb?(text) }
                            }
                        }
                        try await group.waitForAll()
                    }
                }
                let cb = self.onDisconnect
                await MainActor.run { cb?(nil) }
            } catch is CancellationError {
                // user-initiated disconnect
            } catch {
                let cb = self.onDisconnect
                await MainActor.run { cb?(error) }
            }
        }
    }

    func send(_ text: String) {
        var buffer = ByteBufferAllocator().buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        inputContinuation?.yield(buffer)
    }

    func disconnect() {
        inputContinuation?.finish()
        task?.cancel()
        task = nil
    }
}
