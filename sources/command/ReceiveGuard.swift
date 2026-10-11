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
// and an approved command is exec'd DIRECTLY (no shell), on this process's own stdio so the
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
        let root = try CommandRoot.readingThisProcess()
        // sshd sets the variable only when the client asked for a command; a login with none reads
        // as the empty command, which the policy rejects.
        let originalCommand = root.environment["SSH_ORIGINAL_COMMAND"] ?? ""
        switch ReceiveGuardPolicy(pool: pool).validate(originalCommand) {
        case .failure(let rejection):
            root.diagnostics("receive-guard: rejected (\(rejection))")
            throw ExitCode(126)  // 126 = command found but not permitted, per shell convention
        case .success(let argv):
            let status = try root.runOnOwnStandardStreams(
                executablePath: ReceiveGuardPolicy.zfsExecutablePath(isExecutableFile: root.fileSystem.isExecutableFile),
                arguments: Array(argv.dropFirst())  // argv[0] is "zfs"; pass the rest
            )
            throw ExitCode(status)
        }
    }
}
