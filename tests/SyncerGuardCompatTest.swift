// SyncerGuardCompatTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

/// The two sides of the wire in one test: every remote command the `Syncer` sends over ssh is the
/// `SSH_ORIGINAL_COMMAND` a receiver's `receive-guard` validates, and every one must be accepted.
/// The sender and the guard cannot share a type across the wire, so this pins the contract — a
/// sender change that the guard would reject fails here, before a fleet host finds out at 04:00.
final class SyncerGuardCompatTest: XCTestCase {
    private let policy = ReceiveGuardPolicy(pool: "nas_12tb")

    /// The ssh argument from a rendered `ssh … '<remote command>'` line — exactly what sshd hands the
    /// forced command as `SSH_ORIGINAL_COMMAND`.
    private func remoteCommand(in line: String) -> String? {
        // A send pipeline ends in the ssh stage; a bare ssh line is the stage itself.
        let sshStage = line.components(separatedBy: " | ssh ").last.map { line.contains(" | ssh ") ? "ssh " + $0 : $0 } ?? line
        guard sshStage.hasPrefix("ssh ") else { return nil }
        return ReceiveGuardPolicy.tokenize(sshStage)?.last
    }

    func testEveryRemoteCommandOfASyncIsAcceptedByTheGuard() async throws {
        let config = SyncerConfigTest.syncConfig(
            execute: true,
            sendRateLimit: "20M",
            sentBookmarkName: "sent-serverMTB"
        )
        let recorder = RecordingShell { command in
            switch command {
            case "zfs list -o name -H":
                return .success(stdout: "nas_12tb/nas/documents\nnas_12tb/nas/my data")!
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220801-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/my data@20220806-000000",
                ]))!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                // The destination holds one stale snapshot (pruned) and the common base.
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220730-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))!
            case "zfs list -t bookmark -H -p -o guid,createtxg,name -s createtxg":
                return .success(stdout: "")!
            default:
                return nil
            }
        }
        try await Syncer(config: config, dateFormatter: dateFormatter, shell: recorder.shell).sync()

        let remoteCommands = recorder.all.map(\.command).compactMap(remoteCommand(in:))
        // Enumerate, snapshot-destroy, a two-snapshot `-I` receive into the dataset, a full receive
        // of a spaced name: the four shapes a receiver sees.
        XCTAssertEqual(
            [
                "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg",
                "zfs destroy nas_12tb/nas/documents@20220730-000000",
                "zfs recv -F nas_12tb/nas/documents",
                "zfs recv -F 'nas_12tb/nas/my data@20220806-000000'",
            ],
            remoteCommands
        )
        for command in remoteCommands {
            switch policy.validate(command) {
            case .success: break
            case .failure(let rejection): XCTFail("the guard rejects `\(command)`: \(rejection)")
            }
        }
    }

    /// The exact argv the guard will exec for each shape, so a quoting change on either side shows
    /// up as a different argv, not as a silent accept of the wrong thing.
    func testRemoteShapesTokenizeToTheArgvTheGuardExecutes() throws {
        XCTAssertEqual(
            ["zfs", "list", "-t", "snapshot", "-H", "-p", "-o", "guid,createtxg,name", "-s", "createtxg", "-r", "nas_12tb"],
            try policy.validate(ZFS.listSnapshotRecords().commandLine).get()
        )
        XCTAssertEqual(
            ["zfs", "destroy", "nas_12tb/nas/my data@20220806-000000"],
            try policy.validate(ZFS.destroy(subject: "nas_12tb/nas/my data@20220806-000000").commandLine).get()
        )
        XCTAssertEqual(
            ["zfs", "recv", "-F", "nas_12tb/nas/documents"],
            try policy.validate(ZFS.receive(target: "nas_12tb/nas/documents").commandLine).get()
        )
    }

    /// A 2.1.0 sender quoted every argument; a 2.2.0 receiver still accepts that sender during a
    /// lockstep upgrade, and a 2.2.0 sender's bare arguments are accepted by a 2.1.0 guard (the same
    /// tokenizer) — the two shapes are one argv.
    func testQuotedAndBareShapesAreTheSameArgv() throws {
        XCTAssertEqual(
            try policy.validate("zfs destroy 'nas_12tb/nas/documents@20220806-000000'").get(),
            try policy.validate("zfs destroy nas_12tb/nas/documents@20220806-000000").get()
        )
        XCTAssertEqual(
            try policy.validate("zfs recv -F 'nas_12tb/nas/documents@20220806-000000'").get(),
            try policy.validate("zfs recv -F nas_12tb/nas/documents@20220806-000000").get()
        )
    }
}
