import Foundation
import NIOCore
import NIOSSH
import Citadel

final class PTYSession {
    var onOutput: ((String) -> Void)?
    var onData: (([UInt8]) -> Void)?
    var onDisconnect: ((Error?) -> Void)?

    private var task: Task<Void, Never>?
    private var stdinWriter: TTYStdinWriter?
    private var lastSize: (cols: Int, rows: Int)?
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
                try await client.withPTY(Self.defaultPTYRequest) { [weak self] ttyOutput, stdinWriter in
                    self?.stdinWriter = stdinWriter
                    try? await stdinWriter.changeSize(cols: 100, rows: 28, pixelWidth: 800, pixelHeight: 448)
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
                        let bytes: [UInt8]
                        switch chunk {
                        case .stdout(var b): bytes = b.readBytes(length: b.readableBytes) ?? []
                        case .stderr(var b): bytes = b.readBytes(length: b.readableBytes) ?? []
                        }
                        guard !bytes.isEmpty else { continue }
                        let text = String(decoding: bytes, as: UTF8.self)
                        let cb = self?.onOutput
                        let dataCallback = self?.onData
                        await MainActor.run {
                            dataCallback?(bytes)
                            cb?(text)
                        }
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

    func send(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        textContinuation?.yield(String(decoding: bytes, as: UTF8.self))
    }

    func resize(cols: Int, rows: Int) {
        guard cols >= 24, rows >= 8, let stdinWriter else { return }
        if let lastSize, lastSize.cols == cols, lastSize.rows == rows {
            return
        }
        lastSize = (cols, rows)
        Task {
            try? await stdinWriter.changeSize(
                cols: cols,
                rows: rows,
                pixelWidth: cols * 8,
                pixelHeight: rows * 16
            )
        }
    }

    func disconnect() {
        textContinuation?.finish()
        task?.cancel()
        task = nil
        stdinWriter = nil
        lastSize = nil
    }

    private static var bootstrapCommandBuffer: ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: bootstrapCommand.utf8.count)
        buffer.writeString(bootstrapCommand)
        return buffer
    }

    private static var defaultPTYRequest: SSHChannelRequestEvent.PseudoTerminalRequest {
        SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: 100,
            terminalRowHeight: 28,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([
                .ECHO: 0,
                .ICANON: 1,
                .ISIG: 1,
                .IEXTEN: 1,
                .OPOST: 1,
                .ONLCR: 1,
                .ICRNL: 1,
                .IXON: 1,
                .CS8: 1,
                .TTY_OP_ISPEED: 38400,
                .TTY_OP_OSPEED: 38400
            ])
        )
    }

    private static let bootstrapCommand = """
    printf '\\r\\033[2K'; export TERM=xterm-256color CLICOLOR=1 PROMPT_DIRTRIM=3; stty echo 2>/dev/null || true; export LS_COLORS='di=1;34:ln=1;36:ex=1;32:*.sh=1;32:*.py=1;32:*.rb=1;32:*.js=1;32:*.swift=1;35:*.json=0;33:*.log=0;90:*.conf=0;36:*.yml=0;36:*.yaml=0;36:*.md=0;37'; alias ls='ls --color=always -C' 2>/dev/null || true; export PROMPT_COMMAND='printf "\\033]777;cwd:%s;home:%s;host:%s\\007" "$PWD" "$HOME" "$(hostname 2>/dev/null || uname -n)"'; export PS1='\\[\\033[1;32m\\]\\u@\\h\\[\\033[0m\\]:\\[\\033[1;36m\\]\\w\\[\\033[0m\\] \\$ '; printf '\\033]777;cwd:%s;home:%s;host:%s\\007' "$PWD" "$HOME" "$(hostname 2>/dev/null || uname -n)"
    """
}
