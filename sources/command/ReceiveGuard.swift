// ReceiveGuard.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import ArgumentParser
import Foundation
import ZFSToolsModel

// SSH forced-command guard for a backup RECEIVER. Installed in a push key's authorized_keys as
//   command="/usr/local/bin/zfs-tools receive-guard --pool <pool>",restrict,from="<sender-ip>"
// so that key can run ONLY the `zfs recv/list/destroy` a `sync` sender issues, scoped to <pool>.
// The client's real command arrives in $SSH_ORIGINAL_COMMAND; ReceiveGuardPolicy validates it,
// and an approved command is exec'd DIRECTLY (no shell), inheriting this process's stdio so the
// `zfs recv` stream flows straight through.
struct ReceiveGuard: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "receive-guard",
        abstract:
            "SSH forced-command allowing only the zfs recv/list/destroy a sync sender issues, scoped to --pool."
    )

    @Option(name: .long, help: "The pool that an incoming recv/destroy target must stay within.")
    var pool: String

    func run() throws {
        let originalCommand = ProcessInfo.processInfo.environment["SSH_ORIGINAL_COMMAND"] ?? ""
        switch ReceiveGuardPolicy(pool: pool).validate(originalCommand) {
        case .failure(let rejection):
            FileHandle.standardError.write(Data("receive-guard: rejected (\(rejection))\n".utf8))
            throw ExitCode(126)  // 126 = command found but not permitted, per shell convention
        case .success(let argv):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.resolveZfsPath())
            process.arguments = Array(argv.dropFirst())  // argv[0] is "zfs"; pass the rest
            // stdin/stdout/stderr are inherited from this process (the SSH channel) — the recv
            // byte stream passes through untouched.
            try process.run()
            process.waitUntilExit()
            throw ExitCode(process.terminationStatus)
        }
    }

    /// `zfs` lives in sbin on Debian/Ubuntu/Pop; probe the usual locations, fall back to the
    /// canonical path (a wrong path just fails the exec — fail-closed).
    private static func resolveZfsPath() -> String {
        let candidates = ["/usr/sbin/zfs", "/sbin/zfs", "/usr/local/sbin/zfs"]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return "/usr/sbin/zfs"
    }
}
