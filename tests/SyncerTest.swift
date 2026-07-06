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
        let config = SyncerConfigTest.syncConfig(execute: true)
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
            _ dryRun: Bool,
            _ estimatedOutputSize: Int?,
            _ estimatedErrorSize: Int?,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H | grep 'nas_12tb/nas' || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents
                        nas_12tb/nas/documents-alt
                        """
                )!
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220803-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                    "nas_12tb/nas/documents-alt@20220805-000000",
                    "nas_12tb/nas/documents-alt@20220801-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220804-000000",
                    "nas_12tb/nas/documents@20220803-000000",
                    "nas_12tb/nas/documents@20220802-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                    "nas_12tb/nas/documents-alt@20220803-000000",
                    "nas_12tb/nas/documents-alt@20220801-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs destroy 'nas_12tb/nas/documents@20220804-000000'":
                expectDelete20220804.fulfill()
                return .success()
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs destroy 'nas_12tb/nas/documents@20220802-000000'":
                expectDelete20220802.fulfill()
                return .success()
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs destroy 'nas_12tb/nas/documents-alt@20220803-000000'":
                expectDeleteAlt20220803.fulfill()
                return .success()
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents@20220803-000000' 'nas_12tb/nas/documents@20220805-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20220805-000000'":
                expectSend20220805.fulfill()
                return .success()
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents-alt@20220801-000000' 'nas_12tb/nas/documents-alt@20220805-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents-alt@20220805-000000'":
                expectSendAlt20220805.fulfill()
                return .success()
            default:
                XCTFail("unexpected command")
                return .success()
            }
        }
        let syncer = Syncer(
            config: config,
            dateFormatter: dateFormatter,
            shell: shell
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

    func testSyncOnlyFutureAreSent() async throws {
        let config = SyncerConfigTest.syncConfig(execute: true)
        let (
            expectSend20220806,
            expectSend20220807
        ) = (
            expectation(description: "expect send 20220806"),
            expectation(description: "expect send 20220807")
        )
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
                return .success(
                    stdout: """
                        nas_12tb/nas/documents
                        """
                )!
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220807-000000",
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220803-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))!
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents@20220805-000000' 'nas_12tb/nas/documents@20220806-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20220806-000000'":
                expectSend20220806.fulfill()
                return .success()
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents@20220806-000000' 'nas_12tb/nas/documents@20220807-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20220807-000000'":
                expectSend20220807.fulfill()
                return .success()
            default:
                XCTFail("unexpected command")
                return .success()
            }
        }
        let syncer = Syncer(
            config: config,
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await syncer.sync()
        await fulfillment(
            of: [
                expectSend20220806,
                expectSend20220807,
            ],
            timeout: 1,
            enforceOrder: false
        )
    }

    func testSyncResetsIncremental() async throws {
        let config = SyncerConfigTest.syncConfig(execute: true)
        let (
            expectDelete20220804,
            expectDelete20220802,
            expectSend20220806,
            expectSend20220807
        ) = (
            expectation(description: "delete 20220804"),
            expectation(description: "delete 20220802"),
            expectation(description: "send 20220806"),
            expectation(description: "send 20220807")
        )
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
                return .success(
                    stdout: """
                        nas_12tb/nas/documents
                        """
                )!
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220807-000000",
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220803-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220804-000000",
                    "nas_12tb/nas/documents@20220803-000000",
                    "nas_12tb/nas/documents@20220802-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs destroy 'nas_12tb/nas/documents@20220804-000000'":
                expectDelete20220804.fulfill()
                return .success()
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs destroy 'nas_12tb/nas/documents@20220802-000000'":
                expectDelete20220802.fulfill()
                return .success()
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents@20220803-000000' 'nas_12tb/nas/documents@20220806-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20220806-000000'":
                expectSend20220806.fulfill()
                return .success()
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents@20220806-000000' 'nas_12tb/nas/documents@20220807-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20220807-000000'":
                expectSend20220807.fulfill()
                return .success()
            default:
                XCTFail("unexpected command")
                return .success()
            }
        }
        let syncer = Syncer(
            config: config,
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await syncer.sync()
        await fulfillment(
            of: [
                expectDelete20220804,
                expectDelete20220802,
                expectSend20220806,
                expectSend20220807,
            ],
            timeout: 1,
            enforceOrder: false
        )
    }

    // MARK: - Remote path remapping (1.2.1)

    /// Regression guard: with neither remotePathStrip nor remotePathRoot set, sync emits
    /// the same receive path. Mirror of testSyncOnlyFutureAreSent reduced to one send.
    func testSyncWithoutRemotePath_Unchanged() async throws {
        let config = SyncerConfigTest.syncConfig(execute: true)
        let expectSend20220806 = expectation(description: "send 20220806 with unchanged path")
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
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecordOutput(["nas_12tb/nas/documents@20220805-000000"]))!
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents@20220805-000000' 'nas_12tb/nas/documents@20220806-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20220806-000000'":
                expectSend20220806.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        try await syncer.sync()
        await fulfillment(of: [expectSend20220806], timeout: 1, enforceOrder: false)
    }

    func testSyncWithSendRateLimitAddsPvStage() async throws {
        let config = SyncerConfigTest.syncConfig(execute: true, sendRateLimit: "20M")
        let expectThrottledSend = expectation(description: "send command includes pv rate limit")
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
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecordOutput(["nas_12tb/nas/documents@20220805-000000"]))!
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents@20220805-000000' 'nas_12tb/nas/documents@20220806-000000' | pv -q -L '20M' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20220806-000000'":
                expectThrottledSend.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        try await syncer.sync()
        await fulfillment(of: [expectThrottledSend], timeout: 1, enforceOrder: false)
    }

    func testSyncWithInvalidSendRateLimitFailsBeforeShellExecution() async throws {
        let config = SyncerConfigTest.syncConfig(execute: true, sendRateLimit: "20M; rm -rf /")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ dryRun: Bool,
            _ estimatedOutputSize: Int?,
            _ estimatedErrorSize: Int?,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            XCTFail("invalid rate should fail before shell execution: \(command)")
            return .success()
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        do {
            try await syncer.sync()
            XCTFail("invalid sendRateLimit should throw")
        } catch ErrorType.invalidArgument(let name, let value, _, _) {
            XCTAssertEqual(name, "sendRateLimit")
            XCTAssertEqual(value, "20M; rm -rf /")
        }
    }

    func testSyncWithInvalidSentBookmarkNameFailsBeforeShellExecution() async throws {
        let config = SyncerConfigTest.syncConfig(execute: true, sentBookmarkName: "bad/name")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ dryRun: Bool,
            _ estimatedOutputSize: Int?,
            _ estimatedErrorSize: Int?,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            XCTFail("invalid bookmark name should fail before shell execution: \(command)")
            return .success()
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
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
            execute: true,
            remotePathRoot: "pool_b/backups"
        )
        let expectSend20220806 = expectation(description: "send 20220806 with prefixed recv target")
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
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'pool_b/backups/nas_12tb/nas' || true":
                return .success(stdout: snapshotRecord(snapshotGuid("nas_12tb/nas/documents@20220805-000000"), snapshotCreatetxg("nas_12tb/nas/documents@20220805-000000"), "pool_b/backups/nas_12tb/nas/documents@20220805-000000"))!
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents@20220805-000000' 'nas_12tb/nas/documents@20220806-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'pool_b/backups/nas_12tb/nas/documents@20220806-000000'":
                expectSend20220806.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
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
            remotePathStrip: "pool_b/backups"
        )
        let expectSend20220806 = expectation(description: "send 20220806 with stripped recv target")
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
            case "zfs list -o name -H | grep 'pool_b/backups/nas_12tb/nas' || true":
                return .success(stdout: "pool_b/backups/nas_12tb/nas/documents")!
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'pool_b/backups/nas_12tb/nas' || true":
                return .success(stdout: snapshotRecordOutput([
                    "pool_b/backups/nas_12tb/nas/documents@20220806-000000",
                    "pool_b/backups/nas_12tb/nas/documents@20220805-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecord(snapshotGuid("pool_b/backups/nas_12tb/nas/documents@20220805-000000"), snapshotCreatetxg("pool_b/backups/nas_12tb/nas/documents@20220805-000000"), "nas_12tb/nas/documents@20220805-000000"))!
            case "set -o pipefail; zfs send -v -i 'pool_b/backups/nas_12tb/nas/documents@20220805-000000' 'pool_b/backups/nas_12tb/nas/documents@20220806-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20220806-000000'":
                expectSend20220806.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        try await syncer.sync()
        await fulfillment(of: [expectSend20220806], timeout: 1, enforceOrder: false)
    }

    /// Both flags set: strip then prepend. Models the relay topology where NAS-side data lives
    /// at <nas-root>/<source-pool>/... and is forwarded to bc-backup at <backup-root>/<source-pool>/...
    func testSyncWithRemotePathStripAndRoot() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: "nas_pool/archive/source-pool",
            execute: true,
            remotePathStrip: "nas_pool/archive",
            remotePathRoot: "backup_pool"
        )
        let expectSend20220806 = expectation(description: "send with both strip and root")
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
            case "zfs list -o name -H | grep 'nas_pool/archive/source-pool' || true":
                return .success(stdout: "nas_pool/archive/source-pool/data")!
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_pool/archive/source-pool' || true":
                return .success(stdout: snapshotRecordOutput([
                    "nas_pool/archive/source-pool/data@20220806-000000",
                    "nas_pool/archive/source-pool/data@20220805-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'backup_pool/source-pool' || true":
                return .success(stdout: snapshotRecord(snapshotGuid("nas_pool/archive/source-pool/data@20220805-000000"), snapshotCreatetxg("nas_pool/archive/source-pool/data@20220805-000000"), "backup_pool/source-pool/data@20220805-000000"))!
            case "set -o pipefail; zfs send -v -i 'nas_pool/archive/source-pool/data@20220805-000000' 'nas_pool/archive/source-pool/data@20220806-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'backup_pool/source-pool/data@20220806-000000'":
                expectSend20220806.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        try await syncer.sync()
        await fulfillment(of: [expectSend20220806], timeout: 1, enforceOrder: false)
    }

    /// Incremental diff still picks the correct base when remote names carry the prefix.
    /// Local has @20220801, @20220803, @20220805, @20220807; remote (under prefix) has
    /// @20220803, @20220805 → expect incremental sends from @20220805 to @20220807, not from @20220801.
    func testSyncWithRemotePathSnapshotDiff_IncrementalBase() async throws {
        let config = SyncerConfigTest.syncConfig(
            execute: true,
            remotePathRoot: "pool_b/backups"
        )
        let expectSend20220807 = expectation(description: "incremental send from 20220805 to 20220807")
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
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220807-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220803-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'pool_b/backups/nas_12tb/nas' || true":
                return .success(stdout: [
                    snapshotRecord(snapshotGuid("nas_12tb/nas/documents@20220805-000000"), snapshotCreatetxg("nas_12tb/nas/documents@20220805-000000"), "pool_b/backups/nas_12tb/nas/documents@20220805-000000"),
                    snapshotRecord(snapshotGuid("nas_12tb/nas/documents@20220803-000000"), snapshotCreatetxg("nas_12tb/nas/documents@20220803-000000"), "pool_b/backups/nas_12tb/nas/documents@20220803-000000"),
                ].joined(separator: "\n"))!
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents@20220805-000000' 'nas_12tb/nas/documents@20220807-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'pool_b/backups/nas_12tb/nas/documents@20220807-000000'":
                expectSend20220807.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        try await syncer.sync()
        await fulfillment(of: [expectSend20220807], timeout: 1, enforceOrder: false)
    }

    /// When a remote-only snapshot must be destroyed, the destroy command targets the
    /// transformed (remote-side) name. Local has @20220806 only; remote has @20220804
    /// (with prefix) which doesn't exist locally → must be destroyed under its prefixed name.
    func testSyncWithRemotePath_DestroyUsesRemoteName() async throws {
        let config = SyncerConfigTest.syncConfig(
            execute: true,
            remotePathRoot: "pool_b/backups"
        )
        let expectDelete20220804 = expectation(description: "destroy uses prefixed remote name")
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
                return .success(stdout: snapshotRecordOutput(["nas_12tb/nas/documents@20220806-000000"]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'pool_b/backups/nas_12tb/nas' || true":
                return .success(stdout: [
                    snapshotRecord(snapshotGuid("nas_12tb/nas/documents@20220806-000000"), snapshotCreatetxg("nas_12tb/nas/documents@20220806-000000"), "pool_b/backups/nas_12tb/nas/documents@20220806-000000"),
                    snapshotRecord(snapshotGuid("pool_b/backups/nas_12tb/nas/documents@20220804-000000"), snapshotCreatetxg("pool_b/backups/nas_12tb/nas/documents@20220804-000000"), "pool_b/backups/nas_12tb/nas/documents@20220804-000000"),
                ].joined(separator: "\n"))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs destroy 'pool_b/backups/nas_12tb/nas/documents@20220804-000000'":
                expectDelete20220804.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        try await syncer.sync()
        await fulfillment(of: [expectDelete20220804], timeout: 1, enforceOrder: false)
    }

    func testSyncPruningKeepsRemoteSnapshotWithMatchingGuidAndDifferentName() async throws {
        let config = SyncerConfigTest.syncConfig(execute: true, remotePathRoot: "pool_b/backups")
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
                return .success(stdout: snapshotRecord("shared-guid", 10, "nas_12tb/nas/documents@manual-local"))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'pool_b/backups/nas_12tb/nas' || true":
                return .success(stdout: snapshotRecord("shared-guid", 10, "pool_b/backups/nas_12tb/nas/documents@received-remote"))!
            default:
                XCTFail("matching GUID should not send or destroy despite different names: \(command)")
                return .success()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        try await syncer.sync()
    }

    func testSyncCanLeaveRemoteOnlySnapshotsUnpruned() async throws {
        let config = SyncerConfigTest.syncConfig(execute: true, pruneRemoteSnapshots: false)
        let expectSend20220806 = expectation(description: "send without pruning")
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
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220804-000000",
                ]))!
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents@20220805-000000' 'nas_12tb/nas/documents@20220806-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20220806-000000'":
                expectSend20220806.fulfill()
                return .success()
            default:
                if command.contains("zfs destroy") {
                    XCTFail("remote-only snapshots should not be pruned when pruneRemoteSnapshots is false: \(command)")
                } else {
                    XCTFail("unexpected command: \(command)")
                }
                return .success()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        try await syncer.sync()
        await fulfillment(of: [expectSend20220806], timeout: 1, enforceOrder: false)
    }

    func testRemotePathStripRequiresComponentBoundary() async throws {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: "poolish/data",
            execute: true,
            remotePathStrip: "pool"
        )
        let expectSend = expectation(description: "send keeps poolish prefix")
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
            case "zfs list -o name -H | grep 'poolish/data' || true":
                return .success(stdout: "poolish/data")!
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'poolish/data' || true":
                return .success(stdout: snapshotRecordOutput(["poolish/data@20220806-000000"]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'poolish/data' || true":
                return .success(stdout: "")!
            case "set -o pipefail; zfs send -v 'poolish/data@20220806-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'poolish/data@20220806-000000'":
                expectSend.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        try await syncer.sync()
        await fulfillment(of: [expectSend], timeout: 1, enforceOrder: false)
    }

    func testSyncOrdersByCreatetxgAndMatchesByGuidNotSnapshotName() async throws {
        let config = SyncerConfigTest.syncConfig(execute: true, pruneRemoteSnapshots: false)
        let expectSendLatest = expectation(description: "send latest from guid-matched base")
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
                    snapshotRecord("manual-guid", 10, "nas_12tb/nas/documents@pre-consolidation-20260607-084107"),
                    snapshotRecord("received-guid", 20, "nas_12tb/nas/documents@20260705-220120"),
                    snapshotRecord("local-guid", 30, "nas_12tb/nas/documents@20260705-205519"),
                ].joined(separator: "\n"))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecord("received-guid", 20, "nas_12tb/nas/documents@20260705-220120"))!
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents@20260705-220120' 'nas_12tb/nas/documents@20260705-205519' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20260705-205519'":
                expectSendLatest.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        try await syncer.sync()
        await fulfillment(of: [expectSendLatest], timeout: 1, enforceOrder: false)
    }

    func testSyncUsesBookmarkBaseWhenSourceSnapshotWasPruned() async throws {
        let config = SyncerConfigTest.syncConfig(
            execute: true,
            pruneRemoteSnapshots: false,
            sentBookmarkName: "sent-serverMTB"
        )
        let expectSend = expectation(description: "send from bookmark base")
        let expectDestroyTemporaryBookmarkBeforeCreate = expectation(description: "destroy stale temporary bookmark")
        let expectCreateTemporaryBookmark = expectation(description: "create temporary bookmark")
        let expectDestroyBookmark = expectation(description: "destroy old bookmark")
        let expectCreateBookmark = expectation(description: "create new bookmark")
        let expectDestroyTemporaryBookmarkAfterCreate = expectation(description: "destroy temporary bookmark after stable update")
        let temporaryBookmarkDestroyCount = Locked<Int>(0)
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
                return .success(stdout: snapshotRecord("new-guid", 30, "nas_12tb/nas/documents@20220807-000000"))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecord("bookmark-guid", 20, "nas_12tb/nas/documents@20220805-000000"))!
            case "zfs list -t bookmark -H -p -o guid,createtxg,name -s createtxg | grep '#sent-serverMTB' || true":
                return .success(stdout: snapshotRecord("bookmark-guid", 20, "nas_12tb/nas/documents#sent-serverMTB"))!
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents#sent-serverMTB' 'nas_12tb/nas/documents@20220807-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20220807-000000'":
                expectSend.fulfill()
                return .success()
            case "zfs destroy 'nas_12tb/nas/documents#sent-serverMTB.tmp' || true":
                let count = temporaryBookmarkDestroyCount.withLock { count in
                    count += 1
                    return count
                }
                if count == 1 {
                    expectDestroyTemporaryBookmarkBeforeCreate.fulfill()
                } else {
                    expectDestroyTemporaryBookmarkAfterCreate.fulfill()
                }
                return .success()
            case "zfs bookmark 'nas_12tb/nas/documents@20220807-000000' 'nas_12tb/nas/documents#sent-serverMTB.tmp'":
                expectCreateTemporaryBookmark.fulfill()
                return .success()
            case "zfs destroy 'nas_12tb/nas/documents#sent-serverMTB' || true":
                expectDestroyBookmark.fulfill()
                return .success()
            case "zfs bookmark 'nas_12tb/nas/documents@20220807-000000' 'nas_12tb/nas/documents#sent-serverMTB'":
                expectCreateBookmark.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        try await syncer.sync()
        await fulfillment(
            of: [
                expectSend,
                expectDestroyTemporaryBookmarkBeforeCreate,
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
        let config = SyncerConfigTest.syncConfig(execute: true)
        let (
            expectDelete20220801,
            expectDelete20220805,
            expectSend20220806,
            expectSend20220807
        ) = (
            expectation(description: "delete 20220801"),
            expectation(description: "delete 20220805"),
            expectation(description: "send 20220806"),
            expectation(description: "send 20220807")
        )
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
                return .success(
                    stdout: """
                        nas_12tb/nas/documents
                        """
                )!
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220807-000000",
                    "nas_12tb/nas/documents@20220806-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'nas_12tb/nas' || true":
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                ]))!
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs destroy 'nas_12tb/nas/documents@20220801-000000'":
                expectDelete20220801.fulfill()
                return .success()
            case "ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs destroy 'nas_12tb/nas/documents@20220805-000000'":
                expectDelete20220805.fulfill()
                return .success()
            case "set -o pipefail; zfs send -v 'nas_12tb/nas/documents@20220806-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20220806-000000'":
                expectSend20220806.fulfill()
                return .success()
            case "set -o pipefail; zfs send -v -i 'nas_12tb/nas/documents@20220806-000000' 'nas_12tb/nas/documents@20220807-000000' | ssh -p 'sshPort' -i 'sshKeyPath' 'sshUser'@'sshIP' zfs recv -F 'nas_12tb/nas/documents@20220807-000000'":
                expectSend20220807.fulfill()
                return .success()
            default:
                XCTFail("unexpected command")
                return .success()
            }
        }
        let syncer = Syncer(
            config: config,
            dateFormatter: dateFormatter,
            shell: shell
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
        let config = SyncerConfigTest.syncConfig(execute: true, sshKeyPath: "/my keys/id_rsa")
        let expectQuotedSend = expectation(description: "send command quotes the spaced ssh key path")
        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ dryRun: Bool,
            _ estimatedOutputSize: Int?,
            _ estimatedErrorSize: Int?,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            if command.contains("zfs send") {
                XCTAssertTrue(command.contains("-i '/my keys/id_rsa'"), "send must quote spaced ssh key path: \(command)")
                expectQuotedSend.fulfill()
                return .success()
            } else if command.contains("ssh ") && command.contains("-t snapshot") {
                return .success(stdout: snapshotRecordOutput(["nas_12tb/nas/documents@20220805-000000"]))!
            } else if command.contains("-t snapshot") {
                return .success(stdout: snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                ]))!
            } else if command.contains("zfs list -o name -H") {
                return .success(stdout: "nas_12tb/nas/documents")!
            }
            XCTFail("unexpected command: \(command)")
            return .success()
        }
        let syncer = Syncer(config: config, dateFormatter: dateFormatter, shell: shell)
        try await syncer.sync()
        await fulfillment(of: [expectQuotedSend], timeout: 1, enforceOrder: false)
    }
}
