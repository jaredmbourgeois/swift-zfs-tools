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
            case "zfs list -o name -H | grep nas_12tb/nas":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents
                        nas_12tb/nas/documents-alt
                        """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220805-000000
                        nas_12tb/nas/documents@20220803-000000
                        nas_12tb/nas/documents@20220801-000000
                        nas_12tb/nas/documents-alt@20220805-000000
                        nas_12tb/nas/documents-alt@20220801-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep nas_12tb/nas":
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
            case "zfs list -o name -H | grep nas_12tb/nas":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents
                        """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220807-000000
                        nas_12tb/nas/documents@20220806-000000
                        nas_12tb/nas/documents@20220805-000000
                        nas_12tb/nas/documents@20220803-000000
                        nas_12tb/nas/documents@20220801-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep nas_12tb/nas":
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
            case "zfs list -o name -H | grep nas_12tb/nas":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents
                        """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220807-000000
                        nas_12tb/nas/documents@20220806-000000
                        nas_12tb/nas/documents@20220803-000000
                        nas_12tb/nas/documents@20220801-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep nas_12tb/nas":
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
            case "zfs list -o name -H | grep nas_12tb/nas":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents
                        """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas":
                return .success(
                    stdout: """
                        nas_12tb/nas/documents@20220807-000000
                        nas_12tb/nas/documents@20220806-000000
                        """
                )!
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP zfs list -o name -H -t snapshot | grep nas_12tb/nas":
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
