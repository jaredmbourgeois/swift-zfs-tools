// SyncerTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

final class SyncerTest: XCTestCase {
    func testSyncsNewLocalSnapshotsToRemote() async throws {
        let config = SyncerConfigTest.executingSync(pruneRemoteSnapshots: true)
        let (
            expectDelete20220804,
            expectDelete20220802,
            expectDeleteAlt20220803,
            expectSend20220805,
            expectSendAlt20220805
        ) = (
            expectation(description: "delete 20220804"),
            expectation(description: "delete 20220802"),
            expectation(description: "delete alt 20220803"),
            expectation(description: "send 20220805"),
            expectation(description: "send alt 20220805")
        )
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout(
                    """
                        nas_12tb/nas/documents
                        nas_12tb/nas/documents-alt
                        """
                )
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220803-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                    "nas_12tb/nas/documents-alt@20220805-000000",
                    "nas_12tb/nas/documents-alt@20220801-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220804-000000",
                    "nas_12tb/nas/documents@20220803-000000",
                    "nas_12tb/nas/documents@20220802-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                    "nas_12tb/nas/documents-alt@20220803-000000",
                    "nas_12tb/nas/documents-alt@20220801-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs destroy nas_12tb/nas/documents@20220804-000000'":
                expectDelete20220804.fulfill()
                return .emptySuccess()
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs destroy nas_12tb/nas/documents@20220802-000000'":
                expectDelete20220802.fulfill()
                return .emptySuccess()
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs destroy nas_12tb/nas/documents-alt@20220803-000000'":
                expectDeleteAlt20220803.fulfill()
                return .emptySuccess()
            case "set -o pipefail; zfs send -v -i nas_12tb/nas/documents@20220803-000000 nas_12tb/nas/documents@20220805-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F nas_12tb/nas/documents@20220805-000000'":
                expectSend20220805.fulfill()
                return .emptySuccess()
            case "set -o pipefail; zfs send -v -i nas_12tb/nas/documents-alt@20220801-000000 nas_12tb/nas/documents-alt@20220805-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F nas_12tb/nas/documents-alt@20220805-000000'":
                expectSendAlt20220805.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(
            config: config,
            dateFormatter: dateFormatter,
            shell: shell,
            dryRunShell: .unusedDryRunShell()
        )
        try await syncer.sync()
        await fulfillment(
            of: [
                expectDelete20220804,
                expectDelete20220802,
                expectDeleteAlt20220803,
                expectSend20220805,
                expectSendAlt20220805,
            ],
            timeout: 1,
            enforceOrder: false
        )
    }

    /// The owed snapshots after a common SNAPSHOT go out as one `-I` stream into the dataset, not one
    /// send per snapshot (2.2.0).
    func testSyncOnlyFutureAreSent() async throws {
        let config = SyncerConfigTest.executingSync(pruneRemoteSnapshots: true)
        let expectSend20220806Through20220807 = expectation(description: "one stream carries 20220806 and 20220807")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout(
                    """
                        nas_12tb/nas/documents
                        """
                )
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220807-000000",
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220803-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))
            case "set -o pipefail; zfs send -v -I nas_12tb/nas/documents@20220805-000000 nas_12tb/nas/documents@20220807-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F nas_12tb/nas/documents'":
                expectSend20220806Through20220807.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(
            config: config,
            dateFormatter: dateFormatter,
            shell: shell,
            dryRunShell: .unusedDryRunShell()
        )
        try await syncer.sync()
        await fulfillment(
            of: [expectSend20220806Through20220807],
            timeout: 1,
            enforceOrder: false
        )
    }

    func testSyncResetsIncremental() async throws {
        let config = SyncerConfigTest.executingSync(pruneRemoteSnapshots: true)
        let (
            expectDelete20220804,
            expectDelete20220802,
            expectSend20220806Through20220807
        ) = (
            expectation(description: "delete 20220804"),
            expectation(description: "delete 20220802"),
            expectation(description: "one stream carries 20220806 and 20220807")
        )
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout(
                    """
                        nas_12tb/nas/documents
                        """
                )
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220807-000000",
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220803-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220804-000000",
                    "nas_12tb/nas/documents@20220803-000000",
                    "nas_12tb/nas/documents@20220802-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs destroy nas_12tb/nas/documents@20220804-000000'":
                expectDelete20220804.fulfill()
                return .emptySuccess()
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs destroy nas_12tb/nas/documents@20220802-000000'":
                expectDelete20220802.fulfill()
                return .emptySuccess()
            case "set -o pipefail; zfs send -v -I nas_12tb/nas/documents@20220803-000000 nas_12tb/nas/documents@20220807-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F nas_12tb/nas/documents'":
                expectSend20220806Through20220807.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(
            config: config,
            dateFormatter: dateFormatter,
            shell: shell,
            dryRunShell: .unusedDryRunShell()
        )
        try await syncer.sync()
        await fulfillment(
            of: [
                expectDelete20220804,
                expectDelete20220802,
                expectSend20220806Through20220807,
            ],
            timeout: 1,
            enforceOrder: false
        )
    }

    // MARK: - Remote path remapping (1.2.1)

    /// Regression guard: with neither remotePathStrip nor remotePathRoot set, sync emits
    /// the same receive path. Mirror of testSyncOnlyFutureAreSent reduced to one send.
    func testSyncWithoutRemotePath_Unchanged() async throws {
        let config = SyncerConfigTest.executingSync(pruneRemoteSnapshots: true)
        let expectSend20220806 = expectation(description: "send 20220806 with unchanged path")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("nas_12tb/nas/documents")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecordOutput(["nas_12tb/nas/documents@20220805-000000"]))
            case "set -o pipefail; zfs send -v -i nas_12tb/nas/documents@20220805-000000 nas_12tb/nas/documents@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F nas_12tb/nas/documents@20220806-000000'":
                expectSend20220806.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
        await fulfillment(of: [expectSend20220806], timeout: 1, enforceOrder: false)
    }

    func testSyncWithSendRateLimitAddsPvStage() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: SyncerConfigTest.datasetGrep,
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: "20M",
            pruneRemoteSnapshots: true,
            sentBookmarkName: nil,
            remotePathStrip: nil,
            remotePathRoot: nil
        )
        let expectThrottledSend = expectation(description: "send command includes pv rate limit")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("nas_12tb/nas/documents")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecordOutput(["nas_12tb/nas/documents@20220805-000000"]))
            case "set -o pipefail; zfs send -v -i nas_12tb/nas/documents@20220805-000000 nas_12tb/nas/documents@20220806-000000 | pv -q -L 20M | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F nas_12tb/nas/documents@20220806-000000'":
                expectThrottledSend.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
        await fulfillment(of: [expectThrottledSend], timeout: 1, enforceOrder: false)
    }

    func testSyncWithInvalidSendRateLimitFailsBeforeShellExecution() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: SyncerConfigTest.datasetGrep,
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: "20M; rm -rf /",
            pruneRemoteSnapshots: true,
            sentBookmarkName: nil,
            remotePathStrip: nil,
            remotePathRoot: nil
        )
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            XCTFail("invalid rate should fail before shell execution: \(command)")
            return .emptySuccess()
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        do {
            try await syncer.sync()
            XCTFail("invalid sendRateLimit should throw")
        } catch ErrorType.invalidArgument(let name, let value, _, _) {
            XCTAssertEqual(name, "sendRateLimit")
            XCTAssertEqual(value, "20M; rm -rf /")
        }
    }

    func testSyncWithInvalidSentBookmarkNameFailsBeforeShellExecution() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: SyncerConfigTest.datasetGrep,
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: nil,
            pruneRemoteSnapshots: true,
            sentBookmarkName: "bad/name",
            remotePathStrip: nil,
            remotePathRoot: nil
        )
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            XCTFail("invalid bookmark name should fail before shell execution: \(command)")
            return .emptySuccess()
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        do {
            try await syncer.sync()
            XCTFail("invalid sentBookmarkName should throw")
        } catch ErrorType.invalidArgument(let name, let value, _, _) {
            XCTAssertEqual(name, "sentBookmarkName")
            XCTAssertEqual(value, "bad/name")
        }
    }

    /// `--remote-path-root pool_b/backups` redirects recv into pool_b/backups/<source-path>.
    /// Local listing greps with the user-supplied pattern; remote listing greps with the
    /// transformed pattern (root-prefixed) so the remote filter actually matches the on-disk
    /// names. Remote snapshots come back with the prefix and are reverse-mapped internally.
    func testSyncWithRemotePathRootOnly() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: SyncerConfigTest.datasetGrep,
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: nil,
            pruneRemoteSnapshots: true,
            sentBookmarkName: nil,
            remotePathStrip: nil,
            remotePathRoot: "pool_b/backups"
        )
        let expectSend20220806 = expectation(description: "send 20220806 with prefixed recv target")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("nas_12tb/nas/documents")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecord(snapshotGuid("nas_12tb/nas/documents@20220805-000000"), snapshotCreatetxg("nas_12tb/nas/documents@20220805-000000"), "pool_b/backups/nas_12tb/nas/documents@20220805-000000"))
            case "set -o pipefail; zfs send -v -i nas_12tb/nas/documents@20220805-000000 nas_12tb/nas/documents@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F pool_b/backups/nas_12tb/nas/documents@20220806-000000'":
                expectSend20220806.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
        await fulfillment(of: [expectSend20220806], timeout: 1, enforceOrder: false)
    }

    /// `--remote-path-strip <prefix>` strips the prefix from local paths before send.
    /// Useful when relaying snapshots from a box that received them under a prefix
    /// and wants to forward them with the prefix removed. (Rare, but the inverse of
    /// the root-only case must work for symmetry.)
    func testSyncWithRemotePathStripOnly() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: "pool_b/backups/nas_12tb/nas",
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: nil,
            pruneRemoteSnapshots: true,
            sentBookmarkName: nil,
            remotePathStrip: "pool_b/backups",
            remotePathRoot: nil
        )
        let expectSend20220806 = expectation(description: "send 20220806 with stripped recv target")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("pool_b/backups/nas_12tb/nas/documents")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "pool_b/backups/nas_12tb/nas/documents@20220806-000000",
                    "pool_b/backups/nas_12tb/nas/documents@20220805-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecord(snapshotGuid("pool_b/backups/nas_12tb/nas/documents@20220805-000000"), snapshotCreatetxg("pool_b/backups/nas_12tb/nas/documents@20220805-000000"), "nas_12tb/nas/documents@20220805-000000"))
            case "set -o pipefail; zfs send -v -i pool_b/backups/nas_12tb/nas/documents@20220805-000000 pool_b/backups/nas_12tb/nas/documents@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F nas_12tb/nas/documents@20220806-000000'":
                expectSend20220806.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
        await fulfillment(of: [expectSend20220806], timeout: 1, enforceOrder: false)
    }

    /// Both flags set: strip then prepend. Models the relay topology where NAS-side data lives
    /// at <nas-root>/<source-pool>/... and is forwarded to bc-backup at <backup-root>/<source-pool>/...
    func testSyncWithRemotePathStripAndRoot() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: "nas_pool/archive/source-pool",
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: nil,
            pruneRemoteSnapshots: true,
            sentBookmarkName: nil,
            remotePathStrip: "nas_pool/archive",
            remotePathRoot: "backup_pool"
        )
        let expectSend20220806 = expectation(description: "send with both strip and root")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("nas_pool/archive/source-pool/data")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_pool/archive/source-pool/data@20220806-000000",
                    "nas_pool/archive/source-pool/data@20220805-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecord(snapshotGuid("nas_pool/archive/source-pool/data@20220805-000000"), snapshotCreatetxg("nas_pool/archive/source-pool/data@20220805-000000"), "backup_pool/source-pool/data@20220805-000000"))
            case "set -o pipefail; zfs send -v -i nas_pool/archive/source-pool/data@20220805-000000 nas_pool/archive/source-pool/data@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F backup_pool/source-pool/data@20220806-000000'":
                expectSend20220806.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
        await fulfillment(of: [expectSend20220806], timeout: 1, enforceOrder: false)
    }

    /// Incremental diff still picks the correct base when remote names carry the prefix.
    /// Local has @20220801, @20220803, @20220805, @20220807; remote (under prefix) has
    /// @20220803, @20220805 → expect incremental sends from @20220805 to @20220807, not from @20220801.
    func testSyncWithRemotePathSnapshotDiff_IncrementalBase() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: SyncerConfigTest.datasetGrep,
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: nil,
            pruneRemoteSnapshots: true,
            sentBookmarkName: nil,
            remotePathStrip: nil,
            remotePathRoot: "pool_b/backups"
        )
        let expectSend20220807 = expectation(description: "incremental send from 20220805 to 20220807")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("nas_12tb/nas/documents")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220807-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220803-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout([
                    snapshotRecord(snapshotGuid("nas_12tb/nas/documents@20220805-000000"), snapshotCreatetxg("nas_12tb/nas/documents@20220805-000000"), "pool_b/backups/nas_12tb/nas/documents@20220805-000000"),
                    snapshotRecord(snapshotGuid("nas_12tb/nas/documents@20220803-000000"), snapshotCreatetxg("nas_12tb/nas/documents@20220803-000000"), "pool_b/backups/nas_12tb/nas/documents@20220803-000000"),
                ].joined(separator: "\n"))
            case "set -o pipefail; zfs send -v -i nas_12tb/nas/documents@20220805-000000 nas_12tb/nas/documents@20220807-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F pool_b/backups/nas_12tb/nas/documents@20220807-000000'":
                expectSend20220807.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
        await fulfillment(of: [expectSend20220807], timeout: 1, enforceOrder: false)
    }

    /// When a remote-only snapshot must be destroyed, the destroy command targets the
    /// transformed (remote-side) name. Local has @20220806 only; remote has @20220804
    /// (with prefix) which doesn't exist locally → must be destroyed under its prefixed name.
    func testSyncWithRemotePath_DestroyUsesRemoteName() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: SyncerConfigTest.datasetGrep,
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: nil,
            pruneRemoteSnapshots: true,
            sentBookmarkName: nil,
            remotePathStrip: nil,
            remotePathRoot: "pool_b/backups"
        )
        let expectDelete20220804 = expectation(description: "destroy uses prefixed remote name")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("nas_12tb/nas/documents")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput(["nas_12tb/nas/documents@20220806-000000"]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout([
                    snapshotRecord(snapshotGuid("nas_12tb/nas/documents@20220806-000000"), snapshotCreatetxg("nas_12tb/nas/documents@20220806-000000"), "pool_b/backups/nas_12tb/nas/documents@20220806-000000"),
                    snapshotRecord(snapshotGuid("pool_b/backups/nas_12tb/nas/documents@20220804-000000"), snapshotCreatetxg("pool_b/backups/nas_12tb/nas/documents@20220804-000000"), "pool_b/backups/nas_12tb/nas/documents@20220804-000000"),
                ].joined(separator: "\n"))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs destroy pool_b/backups/nas_12tb/nas/documents@20220804-000000'":
                expectDelete20220804.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
        await fulfillment(of: [expectDelete20220804], timeout: 1, enforceOrder: false)
    }

    func testSyncPruningKeepsRemoteSnapshotWithMatchingGuidAndDifferentName() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: SyncerConfigTest.datasetGrep,
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: nil,
            pruneRemoteSnapshots: true,
            sentBookmarkName: nil,
            remotePathStrip: nil,
            remotePathRoot: "pool_b/backups"
        )
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("nas_12tb/nas/documents")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecord("shared-guid", 10, "nas_12tb/nas/documents@manual-local"))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecord("shared-guid", 10, "pool_b/backups/nas_12tb/nas/documents@received-remote"))
            default:
                XCTFail("matching GUID should not send or destroy despite different names: \(command)")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
    }

    /// Without `pruneRemoteSnapshots` — what a config or command line that omits it gets — a
    /// snapshot only the destination holds is left alone: the sync sends and destroys nothing.
    func testSyncCanLeaveRemoteOnlySnapshotsUnpruned() async throws {
        let config = SyncerConfigTest.executingSync(pruneRemoteSnapshots: false)
        let expectSend20220806 = expectation(description: "send without pruning")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("nas_12tb/nas/documents")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220804-000000",
                ]))
            case "set -o pipefail; zfs send -v -i nas_12tb/nas/documents@20220805-000000 nas_12tb/nas/documents@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F nas_12tb/nas/documents@20220806-000000'":
                expectSend20220806.fulfill()
                return .emptySuccess()
            default:
                if command.contains("zfs destroy") {
                    XCTFail("remote-only snapshots should not be pruned when pruneRemoteSnapshots is false: \(command)")
                } else {
                    XCTFail("unexpected command: \(command)")
                }
                return .emptySuccess()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
        await fulfillment(of: [expectSend20220806], timeout: 1, enforceOrder: false)
    }

    func testRemotePathStripRequiresComponentBoundary() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: "poolish/data",
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: nil,
            pruneRemoteSnapshots: true,
            sentBookmarkName: nil,
            remotePathStrip: "pool",
            remotePathRoot: nil
        )
        let expectSend = expectation(description: "send keeps poolish prefix")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("poolish/data")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput(["poolish/data@20220806-000000"]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout("")
            case "set -o pipefail; zfs send -v poolish/data@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F poolish/data@20220806-000000'":
                expectSend.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
        await fulfillment(of: [expectSend], timeout: 1, enforceOrder: false)
    }

    func testSyncOrdersByCreatetxgAndMatchesByGuidNotSnapshotName() async throws {
        let config = SyncerConfigTest.executingSync(pruneRemoteSnapshots: false)
        let expectSendLatest = expectation(description: "send latest from guid-matched base")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("nas_12tb/nas/documents")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout([
                    snapshotRecord("manual-guid", 10, "nas_12tb/nas/documents@pre-consolidation-20260607-084107"),
                    snapshotRecord("received-guid", 20, "nas_12tb/nas/documents@20260705-220120"),
                    snapshotRecord("local-guid", 30, "nas_12tb/nas/documents@20260705-205519"),
                ].joined(separator: "\n"))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecord("received-guid", 20, "nas_12tb/nas/documents@20260705-220120"))
            case "set -o pipefail; zfs send -v -i nas_12tb/nas/documents@20260705-220120 nas_12tb/nas/documents@20260705-205519 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F nas_12tb/nas/documents@20260705-205519'":
                expectSendLatest.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
        await fulfillment(of: [expectSendLatest], timeout: 1, enforceOrder: false)
    }

    func testSyncUsesBookmarkBaseWhenSourceSnapshotWasPruned() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: SyncerConfigTest.datasetGrep,
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: nil,
            pruneRemoteSnapshots: false,
            sentBookmarkName: "sent-serverMTB",
            remotePathStrip: nil,
            remotePathRoot: nil
        )
        let expectSend = expectation(description: "send from bookmark base")
        let expectCreateTemporaryBookmark = expectation(description: "create temporary bookmark")
        let expectDestroyBookmark = expectation(description: "destroy old bookmark")
        let expectCreateBookmark = expectation(description: "create new bookmark")
        let expectDestroyTemporaryBookmarkAfterCreate = expectation(description: "destroy temporary bookmark after stable update")
        // The bookmark listing holds no stale `.tmp`, so no destroy is issued for one: a destroy
        // goes only to a bookmark the run's own listing saw (no `|| true` to swallow a real failure).
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("nas_12tb/nas/documents")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecord("new-guid", 30, "nas_12tb/nas/documents@20220807-000000"))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecord("bookmark-guid", 20, "nas_12tb/nas/documents@20220805-000000"))
            case "zfs list -t bookmark -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecord("bookmark-guid", 20, "nas_12tb/nas/documents#sent-serverMTB"))
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents#sent-serverMTB' nas_12tb/nas/documents@20220807-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F nas_12tb/nas/documents@20220807-000000'":
                expectSend.fulfill()
                return .emptySuccess()
            case "zfs destroy 'nas_12tb/nas/documents#sent-serverMTB.tmp'":
                expectDestroyTemporaryBookmarkAfterCreate.fulfill()
                return .emptySuccess()
            case "zfs bookmark nas_12tb/nas/documents@20220807-000000 'nas_12tb/nas/documents#sent-serverMTB.tmp'":
                expectCreateTemporaryBookmark.fulfill()
                return .emptySuccess()
            case "zfs destroy 'nas_12tb/nas/documents#sent-serverMTB'":
                expectDestroyBookmark.fulfill()
                return .emptySuccess()
            case "zfs bookmark nas_12tb/nas/documents@20220807-000000 'nas_12tb/nas/documents#sent-serverMTB'":
                expectCreateBookmark.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
        await fulfillment(
            of: [
                expectSend,
                expectCreateTemporaryBookmark,
                expectDestroyBookmark,
                expectCreateBookmark,
                expectDestroyTemporaryBookmarkAfterCreate,
            ],
            timeout: 1,
            enforceOrder: true
        )
    }

    func testSyncTotalReset() async throws {
        let config = SyncerConfigTest.executingSync(pruneRemoteSnapshots: true)
        let (
            expectDelete20220801,
            expectDelete20220805,
            expectSend20220806,
            expectSend20220807
        ) = (
            expectation(description: "delete 20220801"),
            expectation(description: "delete 20220805"),
            expectation(description: "send 20220806"),
            expectation(description: "send 20220807 as the -I stream after the full send")
        )
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout(
                    """
                        nas_12tb/nas/documents
                        """
                )
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220807-000000",
                    "nas_12tb/nas/documents@20220806-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs destroy nas_12tb/nas/documents@20220801-000000'":
                expectDelete20220801.fulfill()
                return .emptySuccess()
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs destroy nas_12tb/nas/documents@20220805-000000'":
                expectDelete20220805.fulfill()
                return .emptySuccess()
            case "set -o pipefail; zfs send -v nas_12tb/nas/documents@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F nas_12tb/nas/documents@20220806-000000'":
                expectSend20220806.fulfill()
                return .emptySuccess()
            case "set -o pipefail; zfs send -v -I nas_12tb/nas/documents@20220806-000000 nas_12tb/nas/documents@20220807-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F nas_12tb/nas/documents'":
                expectSend20220807.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(
            config: config,
            dateFormatter: dateFormatter,
            shell: shell,
            dryRunShell: .unusedDryRunShell()
        )
        try await syncer.sync()
        await fulfillment(
            of: [
                expectDelete20220801,
                expectDelete20220805,
                expectSend20220806,
                expectSend20220807,
            ],
            timeout: 1,
            enforceOrder: false
        )
    }

    // MARK: - Quoting at the Syncer boundary

    /// Hardening guard: interpolated values are single-quoted into emitted commands. A sshKeyPath
    /// containing a space must appear as `-i '/my keys/id_rsa'`, not split into two arguments.
    func testSyncQuotesSSHKeyPathWithSpace() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: SyncerConfigTest.datasetGrep,
            execute: true,
            sshKeyPath: "/my keys/id_rsa",
            sendRateLimit: nil,
            pruneRemoteSnapshots: true,
            sentBookmarkName: nil,
            remotePathStrip: nil,
            remotePathRoot: nil
        )
        let expectQuotedSend = expectation(description: "send command quotes the spaced ssh key path")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            if command.contains("zfs send") {
                XCTAssertTrue(command.contains("-i '/my keys/id_rsa'"), "send must quote spaced ssh key path: \(command)")
                expectQuotedSend.fulfill()
                return .emptySuccess()
            } else if command.contains("ssh ") && command.contains("-t snapshot") {
                return .successWithUTF8Stdout(snapshotRecordOutput(["nas_12tb/nas/documents@20220805-000000"]))
            } else if command.contains("-t snapshot") {
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                ]))
            } else if command.contains("zfs list -o name -H") {
                return .successWithUTF8Stdout("nas_12tb/nas/documents")
            }
            XCTFail("unexpected command: \(command)")
            return .emptySuccess()
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell, dryRunShell: .unusedDryRunShell())
        try await syncer.sync()
        await fulfillment(of: [expectQuotedSend], timeout: 1, enforceOrder: false)
    }

    /// A dataset name containing spaces is legal in ZFS. Each remote command line must reach the
    /// remote shell as one quoted ssh argument, so `zfs destroy` / `zfs recv` receive the whole
    /// spaced name as a single argument instead of a word-split one.
    func testSyncHandlesDatasetNameWithSpace() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: "tank/my data",
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: nil,
            pruneRemoteSnapshots: true,
            sentBookmarkName: nil,
            remotePathStrip: nil,
            remotePathRoot: nil
        )
        let (expectDelete20220804, expectSend20220805) = (
            expectation(description: "delete 20220804"),
            expectation(description: "send 20220805")
        )
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("tank/my data")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput(["tank/my data@20220805-000000"]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecordOutput(["tank/my data@20220804-000000"]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs destroy '\\''tank/my data@20220804-000000'\\'''":
                expectDelete20220804.fulfill()
                return .emptySuccess()
            case "set -o pipefail; zfs send -v 'tank/my data@20220805-000000' | ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs recv -F '\\''tank/my data@20220805-000000'\\'''":
                expectSend20220805.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command")
                return .emptySuccess()
            }
        }
        let syncer = Syncer(
            config: config,
            dateFormatter: dateFormatter,
            shell: shell,
            dryRunShell: .unusedDryRunShell()
        )
        try await syncer.sync()
        await fulfillment(
            of: [
                expectDelete20220804,
                expectSend20220805,
            ],
            timeout: 1,
            enforceOrder: false
        )
    }
}
