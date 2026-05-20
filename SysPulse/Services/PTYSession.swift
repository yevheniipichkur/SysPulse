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
                    try? await stdinWriter.changeSize(cols: 120, rows: 40, pixelWidth: 960, pixelHeight: 640)
                    try? await stdinWriter.write(Self.bootstrapCommandBuffer)

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

    private static var bootstrapCommandBuffer: ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: bootstrapCommand.utf8.count)
        buffer.writeString(bootstrapCommand)
        return buffer
    }

    private static let bootstrapCommand = """
    stty -echo cols 120 rows 40 2>/dev/null; export TERM=xterm-256color CLICOLOR=1; export LS_COLORS='di=1;34:ln=1;36:ex=1;32:*.sh=1;32:*.py=1;32:*.rb=1;32:*.js=1;32:*.swift=1;35:*.json=0;33:*.log=0;90:*.conf=0;36:*.yml=0;36:*.yaml=0;36:*.md=0;37'; export PS1=''; export PROMPT_COMMAND=''; alias ls='ls --color=always -C' 2>/dev/null || true; printf '\\033]777;cwd:%s;home:%s;host:%s\\007' "$PWD" "$HOME" "$(hostname 2>/dev/null || uname -n)"
    """
}
