// SyncerSendStepsTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

/// How a dataset's owed snapshots become streams (2.2.0): at most two sends however many snapshots
/// are owed, the bookmark advanced once, and datasets in name order.
final class SyncerSendStepsTest: XCTestCase {
    private func record(_ createtxg: UInt64, _ name: String) -> SnapshotRecord {
        SnapshotRecord(guid: "guid-\(createtxg)", createtxg: createtxg, name: name)
    }

    private func owed(_ createtxgs: [UInt64]) -> [SnapshotRecord] {
        createtxgs.map { record($0, "pool/data@s\($0)") }
    }

    func testNothingOwedIsNoStep() {
        XCTAssertEqual(Syncer.sendSteps(base: nil, owed: []), [])
    }

    func testOneSnapshotAfterASnapshotBaseIsOneIncrementalSend() {
        let base = Syncer.SnapshotBase(record: record(10, "pool/data@s10"))
        let snapshots = owed([20])
        XCTAssertEqual(
            Syncer.sendSteps(base: base, owed: snapshots),
            [Syncer.SendStep(kind: .incremental, from: "pool/data@s10", to: snapshots[0])])
    }

    func testManySnapshotsAfterASnapshotBaseAreOneIntermediaryStream() {
        let base = Syncer.SnapshotBase(record: record(10, "pool/data@s10"))
        let snapshots = owed([20, 30, 40, 50])
        XCTAssertEqual(
            Syncer.sendSteps(base: base, owed: snapshots),
            [Syncer.SendStep(kind: .intermediary, from: "pool/data@s10", to: snapshots[3])])
    }

    /// `-I` cannot start at a bookmark, so a bookmark base costs one `-i` to the first owed
    /// snapshot, then one `-I` from there.
    func testABookmarkBaseIsAnIncrementalThenOneIntermediaryStream() {
        let base = Syncer.SnapshotBase(record: record(10, "pool/data#sent-mtb"))
        let snapshots = owed([20, 30, 40])
        XCTAssertEqual(
            Syncer.sendSteps(base: base, owed: snapshots),
            [
                Syncer.SendStep(kind: .incremental, from: "pool/data#sent-mtb", to: snapshots[0]),
                Syncer.SendStep(kind: .intermediary, from: "pool/data@s20", to: snapshots[2]),
            ])
    }

    func testNoBaseIsAFullSendThenOneIntermediaryStream() {
        let snapshots = owed([20, 30, 40])
        XCTAssertEqual(
            Syncer.sendSteps(base: nil, owed: snapshots),
            [
                Syncer.SendStep(kind: .full, from: nil, to: snapshots[0]),
                Syncer.SendStep(kind: .intermediary, from: "pool/data@s20", to: snapshots[2]),
            ])
        XCTAssertEqual(
            Syncer.sendSteps(base: nil, owed: [snapshots[0]]),
            [Syncer.SendStep(kind: .full, from: nil, to: snapshots[0])])
    }

    /// `-I` sends every snapshot between its two ends, so it is only used when the owed list is
    /// provably that run. A list that is not falls back to one `-i` per snapshot, which is correct
    /// for any list.
    func testAnOwedListThatIsNotOneAscendingRunFallsBackToOneSendPerSnapshot() {
        let base = Syncer.SnapshotBase(record: record(10, "pool/data@s10"))
        let repeatedCreatetxg = [record(20, "pool/data@a"), record(20, "pool/data@b"), record(30, "pool/data@c")]
        XCTAssertEqual(
            Syncer.sendSteps(base: base, owed: repeatedCreatetxg),
            [
                Syncer.SendStep(kind: .incremental, from: "pool/data@s10", to: repeatedCreatetxg[0]),
                Syncer.SendStep(kind: .incremental, from: "pool/data@a", to: repeatedCreatetxg[1]),
                Syncer.SendStep(kind: .incremental, from: "pool/data@b", to: repeatedCreatetxg[2]),
            ])

        let olderThanBase = owed([5, 20])
        XCTAssertEqual(Syncer.sendSteps(base: base, owed: olderThanBase).count, 2)
        XCTAssertTrue(Syncer.sendSteps(base: base, owed: olderThanBase).allSatisfy { $0.kind == .incremental })

        let twoDatasets = [record(20, "pool/data@s20"), record(30, "pool/other@s30")]
        XCTAssertFalse(Syncer.isContiguous(twoDatasets, after: base))
        let otherDatasetBase = Syncer.SnapshotBase(record: record(10, "pool/other@s10"))
        XCTAssertFalse(Syncer.isContiguous(owed([20, 30]), after: otherDatasetBase))
    }

    /// The bookmark is advanced ONCE per dataset, to the newest snapshot, after both streams land —
    /// not five commands per snapshot as before.
    func testSyncFromABookmarkBaseSendsTwoStreamsAndAdvancesTheBookmarkOnce() async throws {
        let config = SyncerConfigTest.syncConfig(
            execute: true,
            pruneRemoteSnapshots: false,
            sentBookmarkName: "sent-serverMTB"
        )
        let ssh = "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP'"
        let commands = Locked<[String]>([])
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ dryRun: Bool,
            _ estimatedOutputSize: Int?,
            _ estimatedErrorSize: Int?,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H | grep 'nas_12tb/nas' || true":
                return .success(stdout: "nas_12tb/nas/documents")!
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: [
                    snapshotRecord("guid-30", 30, "nas_12tb/nas/documents@20220807-000000"),
                    snapshotRecord("guid-40", 40, "nas_12tb/nas/documents@20220808-000000"),
                    snapshotRecord("guid-50", 50, "nas_12tb/nas/documents@20220809-000000"),
                ].joined(separator: "\n"))!
            case "\(ssh) 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg' | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecord("bookmark-guid", 20, "nas_12tb/nas/documents@20220805-000000"))!
            case "zfs list -t bookmark -H -p -o guid,createtxg,name -s createtxg | grep '#sent-serverMTB' || true":
                return .success(stdout: snapshotRecord("bookmark-guid", 20, "nas_12tb/nas/documents#sent-serverMTB"))!
            default:
                commands.withLock { $0.append(command) }
                return .success()
            }
        }
        try await Syncer(config: config, dateFormatter: dateFormatter, shell: shell).sync()

        XCTAssertEqual(
            commands.withLock { $0 },
            [
                "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents#sent-serverMTB' 'nas_12tb/nas/documents@20220807-000000' | \(ssh) 'zfs recv -F '\\''nas_12tb/nas/documents@20220807-000000'\\'''",
                "set -o pipefail; zfs send -v -I 'nas_12tb/nas/documents@20220807-000000' 'nas_12tb/nas/documents@20220809-000000' | \(ssh) 'zfs recv -F '\\''nas_12tb/nas/documents'\\'''",
                "zfs destroy 'nas_12tb/nas/documents#sent-serverMTB.tmp' || true",
                "zfs bookmark 'nas_12tb/nas/documents@20220809-000000' 'nas_12tb/nas/documents#sent-serverMTB.tmp'",
                "zfs destroy 'nas_12tb/nas/documents#sent-serverMTB' || true",
                "zfs bookmark 'nas_12tb/nas/documents@20220809-000000' 'nas_12tb/nas/documents#sent-serverMTB'",
                "zfs destroy 'nas_12tb/nas/documents#sent-serverMTB.tmp' || true",
            ])
    }

    /// A failed stream leaves the bookmark where it was: it must never name a snapshot the
    /// destination does not hold.
    func testAFailedStreamDoesNotAdvanceTheBookmark() async throws {
        let config = SyncerConfigTest.syncConfig(
            execute: true,
            pruneRemoteSnapshots: false,
            sentBookmarkName: "sent-serverMTB"
        )
        let ssh = "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP'"
        let bookmarkCommands = Locked<Int>(0)
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ dryRun: Bool,
            _ estimatedOutputSize: Int?,
            _ estimatedErrorSize: Int?,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H | grep 'nas_12tb/nas' || true":
                return .success(stdout: "nas_12tb/nas/documents")!
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: [
                    snapshotRecord("guid-20", 20, "nas_12tb/nas/documents@20220805-000000"),
                    snapshotRecord("guid-30", 30, "nas_12tb/nas/documents@20220807-000000"),
                    snapshotRecord("guid-40", 40, "nas_12tb/nas/documents@20220808-000000"),
                ].joined(separator: "\n"))!
            case "\(ssh) 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg' | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecord("guid-20", 20, "nas_12tb/nas/documents@20220805-000000"))!
            case "zfs list -t bookmark -H -p -o guid,createtxg,name -s createtxg | grep '#sent-serverMTB' || true":
                return .success(stdout: "")!
            default:
                if command.contains("zfs send") {
                    return ShellResult(
                        error: ShellAtPathError(kind: .termination(1), userInfo: [:]),
                        processOutput: .init(stderr: Data("cannot receive: connection lost".utf8), stdout: Data()),
                        termination: .init(reason: .exit, status: 1)
                    )
                }
                bookmarkCommands.withLock { $0 += 1 }
                return .success()
            }
        }
        do {
            try await Syncer(config: config, dateFormatter: dateFormatter, shell: shell).sync()
            XCTFail("a failed stream must fail the sync")
        } catch {}
        XCTAssertEqual(bookmarkCommands.withLock { $0 }, 0)
    }

    /// Datasets go in name order, so a parent is received before its children however the
    /// listing returned them.
    func testSyncSendsDatasetsInNameOrder() async throws {
        let config = SyncerConfigTest.syncConfig(execute: true, pruneRemoteSnapshots: false)
        let sent = Locked<[String]>([])
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ dryRun: Bool,
            _ estimatedOutputSize: Int?,
            _ estimatedErrorSize: Int?,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H | grep 'nas_12tb/nas' || true":
                return .success(stdout: "nas_12tb/nas/media/photos\nnas_12tb/nas/media\nnas_12tb/nas/documents")!
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: [
                    snapshotRecord("guid-1", 1, "nas_12tb/nas/documents@20220805-000000"),
                    snapshotRecord("guid-2", 2, "nas_12tb/nas/media@20220805-000000"),
                    snapshotRecord("guid-3", 3, "nas_12tb/nas/media/photos@20220805-000000"),
                ].joined(separator: "\n"))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg' | grep 'nas_12tb/nas' || true":
                return .success(stdout: "")!
            default:
                sent.withLock { $0.append(command) }
                return .success()
            }
        }
        try await Syncer(config: config, dateFormatter: dateFormatter, shell: shell).sync()

        let order = sent.withLock { $0 }.map { command in
            ["documents@", "media@", "media/photos@"].first { command.contains("nas_12tb/nas/\($0)") } ?? command
        }
        XCTAssertEqual(order, ["documents@", "media@", "media/photos@"])
    }
}
