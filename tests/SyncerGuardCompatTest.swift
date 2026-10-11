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

    func testEveryRemoteCommandOfASyncIsAcceptedByTheGuard() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: SyncerConfigTest.datasetGrep,
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: "20M",
            pruneRemoteSnapshots: true,
            sentBookmarkName: "sent-serverMTB",
            remotePathStrip: nil,
            remotePathRoot: nil
        )
        let recorder = RecordingShell { command in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("nas_12tb/nas/documents\nnas_12tb/nas/my data")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220801-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/my data@20220806-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                // The destination holds one stale snapshot (pruned) and the common base.
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220730-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))
            case "zfs list -t bookmark -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout("")
            default:
                return nil
            }
        }
        try await Syncer(config: config, dateFormatter: dateFormatter, shell: recorder.shell, dryRunShell: recorder.dryRunShell).sync()

        let remoteCommands = recorder.all.map(\.command).compactMap(remoteCommand(inLocalCommandLine:))
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

    /// A quoted token and a bare one are the same argv to the guard, which is why a sender may quote
    /// only the tokens that need it. On the wire the guard has received bare words from every
    /// version: a 2.1.0 sender quoted each argument, but for its own local shell, which stripped the
    /// quotes before `ssh` ran; since 2.2.0 the remote line is one ssh argument, and a quote reaches
    /// the guard only around a name that needs one (`remote_shapes/` records each version's lines).
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
