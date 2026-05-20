import Foundation
import NIOCore
import Citadel

final class PTYSession {
    var onOutput: ((String) -> Void)?
    var onDisconnect: ((Error?) -> Void)?

    private var task: Task<Void, Never>?
    // Use String stream to avoid ByteBuffer Sendability concerns
    private var textContinuation: AsyncStream<String>.Continuation?

    func connect(to server: ServerProfile, using sshClient: SSHClientProtocol) {
        task?.cancel()
        let (textStream, textCont) = AsyncStream<String>.makeStream()
        textContinuation = textCont
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try await sshClient.makeCitadelClient(for: server)
                defer { Task { try? await client.close() } }
                try await client.withTTY { [weak self] ttyOutput, stdinWriter in
                    // Stdin in separate task; String is Sendable so capture is safe
                    let stdinTask = Task { [weak self] in
                        for await text in textStream {
                            guard !Task.isCancelled else { break }
                            var buffer = ByteBufferAllocator().buffer(capacity: text.utf8.count)
                            buffer.writeString(text)
                            do {
                                try await stdinWriter.write(buffer)
                            } catch {
                                let cb = self?.onOutput
                                await MainActor.run { cb?("\n[stdin error: \(error.localizedDescription)]\n") }
                            }
                        }
                    }
                    defer { stdinTask.cancel() }

                    for try await chunk in ttyOutput {
                        guard !Task.isCancelled else { break }
                        let text: String
                        switch chunk {
                        case .stdout(var b): text = b.readString(length: b.readableBytes) ?? ""
                        case .stderr(var b): text = b.readString(length: b.readableBytes) ?? ""
                        }
                        guard !text.isEmpty else { continue }
                        let cb = self?.onOutput
                        await MainActor.run { cb?(text) }
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
        textContinuation?.yield(text)
    }

    func disconnect() {
        textContinuation?.finish()
        task?.cancel()
        task = nil
    }
}
