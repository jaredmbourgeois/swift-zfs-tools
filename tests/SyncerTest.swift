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
            case "zfs list -o name -H | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents
                        nas_12tb/nas/documents-alt
                        """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220805-000000
                        nas_12tb/nas/documents@20220803-000000
                        nas_12tb/nas/documents@20220801-000000
                        nas_12tb/nas/documents-alt@20220805-000000
                        nas_12tb/nas/documents-alt@20220801-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220804-000000
                        nas_12tb/nas/documents@20220803-000000
                        nas_12tb/nas/documents@20220802-000000
                        nas_12tb/nas/documents@20220801-000000
                        nas_12tb/nas/documents-alt@20220803-000000
                        nas_12tb/nas/documents-alt@20220801-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs destroy nas_12tb/nas/documents@20220804-000000":
                expectDelete20220804.fulfill()
                return .success()
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs destroy nas_12tb/nas/documents@20220802-000000":
                expectDelete20220802.fulfill()
                return .success()
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs destroy nas_12tb/nas/documents-alt@20220803-000000":
                expectDeleteAlt20220803.fulfill()
                return .success()
            case "zfs send -v -i nas_12tb/nas/documents@20220803-000000 nas_12tb/nas/documents@20220805-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F nas_12tb/nas/documents@20220805-000000":
                expectSend20220805.fulfill()
                return .success()
            case "zfs send -v -i nas_12tb/nas/documents-alt@20220801-000000 nas_12tb/nas/documents-alt@20220805-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F nas_12tb/nas/documents-alt@20220805-000000":
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
            case "zfs list -o name -H | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents
                        """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220807-000000
                        nas_12tb/nas/documents@20220806-000000
                        nas_12tb/nas/documents@20220805-000000
                        nas_12tb/nas/documents@20220803-000000
                        nas_12tb/nas/documents@20220801-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220805-000000
                        nas_12tb/nas/documents@20220801-000000
                        """
                )!
            case "zfs send -v -i nas_12tb/nas/documents@20220805-000000 nas_12tb/nas/documents@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F nas_12tb/nas/documents@20220806-000000":
                expectSend20220806.fulfill()
                return .success()
            case "zfs send -v -i nas_12tb/nas/documents@20220806-000000 nas_12tb/nas/documents@20220807-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F nas_12tb/nas/documents@20220807-000000":
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
            case "zfs list -o name -H | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents
                        """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220807-000000
                        nas_12tb/nas/documents@20220806-000000
                        nas_12tb/nas/documents@20220803-000000
                        nas_12tb/nas/documents@20220801-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220804-000000
                        nas_12tb/nas/documents@20220803-000000
                        nas_12tb/nas/documents@20220802-000000
                        nas_12tb/nas/documents@20220801-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs destroy nas_12tb/nas/documents@20220804-000000":
                expectDelete20220804.fulfill()
                return .success()
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs destroy nas_12tb/nas/documents@20220802-000000":
                expectDelete20220802.fulfill()
                return .success()
            case "zfs send -v -i nas_12tb/nas/documents@20220803-000000 nas_12tb/nas/documents@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F nas_12tb/nas/documents@20220806-000000":
                expectSend20220806.fulfill()
                return .success()
            case "zfs send -v -i nas_12tb/nas/documents@20220806-000000 nas_12tb/nas/documents@20220807-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F nas_12tb/nas/documents@20220807-000000":
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
    /// byte-identical commands to 1.2.0. Mirror of testSyncOnlyFutureAreSent reduced to one send.
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
            case "zfs list -o name -H | grep nas_12tb/nas || true":
                return .success(stdout: "nas_12tb/nas/documents")!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220806-000000
                        nas_12tb/nas/documents@20220805-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(stdout: "nas_12tb/nas/documents@20220805-000000")!
            case "zfs send -v -i nas_12tb/nas/documents@20220805-000000 nas_12tb/nas/documents@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F nas_12tb/nas/documents@20220806-000000":
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
            case "zfs list -o name -H | grep nas_12tb/nas || true":
                return .success(stdout: "nas_12tb/nas/documents")!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220806-000000
                        nas_12tb/nas/documents@20220805-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep pool_b/backups/nas_12tb/nas || true":
                return .success(stdout: "pool_b/backups/nas_12tb/nas/documents@20220805-000000")!
            case "zfs send -v -i nas_12tb/nas/documents@20220805-000000 nas_12tb/nas/documents@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F pool_b/backups/nas_12tb/nas/documents@20220806-000000":
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
            case "zfs list -o name -H | grep pool_b/backups/nas_12tb/nas || true":
                return .success(stdout: "pool_b/backups/nas_12tb/nas/documents")!
            case "zfs list -o name -H -t snapshot | grep pool_b/backups/nas_12tb/nas || true":
                return .success(
                    stdout: """
                        pool_b/backups/nas_12tb/nas/documents@20220806-000000
                        pool_b/backups/nas_12tb/nas/documents@20220805-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(stdout: "nas_12tb/nas/documents@20220805-000000")!
            case "zfs send -v -i pool_b/backups/nas_12tb/nas/documents@20220805-000000 pool_b/backups/nas_12tb/nas/documents@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F nas_12tb/nas/documents@20220806-000000":
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
            case "zfs list -o name -H | grep nas_pool/archive/source-pool || true":
                return .success(stdout: "nas_pool/archive/source-pool/data")!
            case "zfs list -o name -H -t snapshot | grep nas_pool/archive/source-pool || true":
                return .success(
                    stdout: """
                        nas_pool/archive/source-pool/data@20220806-000000
                        nas_pool/archive/source-pool/data@20220805-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep backup_pool/source-pool || true":
                return .success(stdout: "backup_pool/source-pool/data@20220805-000000")!
            case "zfs send -v -i nas_pool/archive/source-pool/data@20220805-000000 nas_pool/archive/source-pool/data@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F backup_pool/source-pool/data@20220806-000000":
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
            case "zfs list -o name -H | grep nas_12tb/nas || true":
                return .success(stdout: "nas_12tb/nas/documents")!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220807-000000
                        nas_12tb/nas/documents@20220805-000000
                        nas_12tb/nas/documents@20220803-000000
                        nas_12tb/nas/documents@20220801-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep pool_b/backups/nas_12tb/nas || true":
                return .success(
                    stdout: """
                        pool_b/backups/nas_12tb/nas/documents@20220805-000000
                        pool_b/backups/nas_12tb/nas/documents@20220803-000000
                        """
                )!
            case "zfs send -v -i nas_12tb/nas/documents@20220805-000000 nas_12tb/nas/documents@20220807-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F pool_b/backups/nas_12tb/nas/documents@20220807-000000":
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
            case "zfs list -o name -H | grep nas_12tb/nas || true":
                return .success(stdout: "nas_12tb/nas/documents")!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(stdout: "nas_12tb/nas/documents@20220806-000000")!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep pool_b/backups/nas_12tb/nas || true":
                return .success(
                    stdout: """
                        pool_b/backups/nas_12tb/nas/documents@20220806-000000
                        pool_b/backups/nas_12tb/nas/documents@20220804-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs destroy pool_b/backups/nas_12tb/nas/documents@20220804-000000":
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
            case "zfs list -o name -H | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents
                        """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220807-000000
                        nas_12tb/nas/documents@20220806-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep nas_12tb/nas || true":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220805-000000
                        nas_12tb/nas/documents@20220801-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs destroy nas_12tb/nas/documents@20220801-000000":
                expectDelete20220801.fulfill()
                return .success()
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs destroy nas_12tb/nas/documents@20220805-000000":
                expectDelete20220805.fulfill()
                return .success()
            case "zfs send -v nas_12tb/nas/documents@20220806-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F nas_12tb/nas/documents@20220806-000000":
                expectSend20220806.fulfill()
                return .success()
            case "zfs send -v -i nas_12tb/nas/documents@20220806-000000 nas_12tb/nas/documents@20220807-000000 | ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs recv -F nas_12tb/nas/documents@20220807-000000":
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
}
