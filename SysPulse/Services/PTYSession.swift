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

    func connect(
        to server: ServerProfile,
        jumpHost: ServerProfile? = nil,
        using sshClient: SSHClientProtocol,
        initialSize: PTYTerminalSize? = nil
    ) {
        task?.cancel()
        let (textStream, textCont) = AsyncStream<String>.makeStream()
        textContinuation = textCont
        let connectServer = jumpHost ?? server
        let usesJump = jumpHost != nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try await sshClient.makeCitadelClient(for: connectServer)
                defer { Task { await sshClient.releaseClient(for: connectServer) } }
                let ptySize = initialSize ?? Self.defaultSize
                try await client.withPTY(Self.ptyRequest(size: ptySize)) { [weak self] ttyOutput, stdinWriter in
                    self?.stdinWriter = stdinWriter
                    self?.lastSize = (ptySize.cols, ptySize.rows)
                    try? await stdinWriter.changeSize(
                        cols: ptySize.cols,
                        rows: ptySize.rows,
                        pixelWidth: ptySize.pixelWidth,
                        pixelHeight: ptySize.pixelHeight
                    )
                    if usesJump {
                        var jumpBuffer = ByteBufferAllocator().buffer(capacity: SSHJumpHost.interactiveSSHLaunch(target: server).utf8.count)
                        jumpBuffer.writeString(SSHJumpHost.interactiveSSHLaunch(target: server))
                        try? await stdinWriter.write(jumpBuffer)
                    } else {
                        try? await stdinWriter.write(Self.bootstrapCommandBuffer)
                    }

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

    private static let defaultSize = PTYTerminalSize(cols: 80, rows: 24)

    private static func ptyRequest(size: PTYTerminalSize) -> SSHChannelRequestEvent.PseudoTerminalRequest {
        SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: size.cols,
            terminalRowHeight: size.rows,
            terminalPixelWidth: size.pixelWidth,
            terminalPixelHeight: size.pixelHeight,
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

struct PTYTerminalSize: Equatable, Hashable {
    var cols: Int
    var rows: Int

    var pixelWidth: Int { cols * 8 }
    var pixelHeight: Int { rows * 16 }

    var isUsable: Bool {
        cols >= 24 && rows >= 8
    }
}
