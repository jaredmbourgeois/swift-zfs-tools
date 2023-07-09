// ConsolidatorTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

final class ConsolidatorTest: XCTestCase {
    private func makeConfig(
        datasetGrep: String? = "nas_12tb/nas/",
        dateSeparator: String = "@",
        execute: Bool = true,
        lineSeparator: String = "\n",
        schedule: Consolidator.SnapshotConsolidationSchedule,
        snapshotsNotConsolidated: [String] = [],
        stringEncoding: String.Encoding = .utf8
    ) -> Consolidator.Config {
        .init(
            datasetGrep: datasetGrep,
            dateSeparator: dateSeparator,
            execute: execute,
            lineSeparator: lineSeparator,
            schedule: schedule,
            snapshotsNotConsolidated: snapshotsNotConsolidated,
            stringEncoding: stringEncoding
        )
    }

    func testSnapshotsAreConsolidatedInSinglePeriod() async throws {
        let expectDestroy20220729 = expectation(description: "expect destroy 20220729")
        let expectDestroy20220801 = expectation(description: "expect destroy 20220801")
        let expectDestroy20220805 = expectation(description: "expect destroy 20220805")
        let config = makeConfig(
            schedule: .Builder(upperBound: testDateString)
                .keepingSnapshots(1, every: 1, .weeks, repeatedBy: 1)
                .build()
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
            case "zfs list -o name -H | grep nas_12tb/nas/":
                return .success(
                    stdout: """
                    nas_12tb/nas/documents
                    """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas/":
                return .success(
                    stdout: """
                    nas_12tb/nas/documents@20220805-000000
                    nas_12tb/nas/documents@20220803-000000
                    nas_12tb/nas/documents@20220801-000000
                    nas_12tb/nas/documents@20220729-000000
                    """
                )!
            case "zfs destroy nas_12tb/nas/documents@20220729-000000":
                expectDestroy20220729.fulfill()
                return .success()
            case "zfs destroy nas_12tb/nas/documents@20220801-000000":
                expectDestroy20220801.fulfill()
                return .success()
            case "zfs destroy nas_12tb/nas/documents@20220805-000000":
                expectDestroy20220805.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await consolidator.consolidate()
        await fulfillment(
            of: [
                expectDestroy20220729,
                expectDestroy20220801,
                expectDestroy20220805
            ],
            timeout: timeout
        )
    }

    func testSnapshotsAreConsolidatedIndefinitely() async throws {
        let expectDestroy20220801 = expectation(description: "expect destroy 20220801")
        let expectDestroy20220805 = expectation(description: "expect destroy 20220805")
        let config = makeConfig(
            schedule: .Builder(upperBound: testDateString)
                .buildIndefinitelyKeepingSnapshots(
                    1,
                    every: 1,
                    .weeks
                )
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
            case "zfs list -o name -H | grep nas_12tb/nas/":
                return .success(
                    stdout: """
                    nas_12tb/nas/documents
                    """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas/":
                return .success(
                    stdout: """
                    nas_12tb/nas/documents@20220805-000000
                    nas_12tb/nas/documents@20220803-000000
                    nas_12tb/nas/documents@20220801-000000
                    nas_12tb/nas/documents@20220729-000000
                    """
                )!
            case "zfs destroy nas_12tb/nas/documents@20220801-000000":
                expectDestroy20220801.fulfill()
                return .success()
            case "zfs destroy nas_12tb/nas/documents@20220805-000000":
                expectDestroy20220805.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await consolidator.consolidate()
        await fulfillment(
            of: [
                expectDestroy20220801,
                expectDestroy20220805
            ],
            timeout: timeout
        )
    }

    func testSnapshotsAreKept() async throws {
        let expectNoDeletions = expectation(description: "expect no deletions")
        expectNoDeletions.isInverted = true
        let config = makeConfig(
            schedule: .Builder(upperBound: testDateString)
                .keepingSnapshots(1, every: 1, .days, repeatedBy: 7)
                .build()
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
            case "zfs list -o name -H | grep nas_12tb/nas/":
                return .success(
                    stdout: """
                    nas_12tb/nas/documents
                    """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas/":
                return .success(
                    stdout: """
                    nas_12tb/nas/documents@20220805-000000
                    nas_12tb/nas/documents@20220803-000000
                    nas_12tb/nas/documents@20220801-000000
                    """
                )!
            default:
                XCTFail("unexpected command: \(command)")
                expectNoDeletions.fulfill()
                return .success()
            }
        }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await consolidator.consolidate()
        await fulfillment(of: [expectNoDeletions], timeout: timeout)
    }

    func testSnapshotsAreNotConsolidated() async throws {
        let expectDestroy20220729 = expectation(description: "expect destroy 20220729")
        expectDestroy20220729.isInverted = true
        let expectDestroy20220801 = expectation(description: "expect destroy 20220801")
        expectDestroy20220801.isInverted = true
        let expectDestroy20220805 = expectation(description: "expect destroy 20220805")
        let config = makeConfig(
            schedule: .Builder(upperBound: testDateString)
                .keepingSnapshots(1, every: 1, .weeks, repeatedBy: 1)
                .build(),
            snapshotsNotConsolidated: [
                "nas_12tb/nas/documents@20220729-000000",
                "nas_12tb/nas/documents@20220801-000000",
            ]
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
            case "zfs list -o name -H | grep nas_12tb/nas/":
                return .success(
                    stdout: """
                    nas_12tb/nas/documents
                    """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas/":
                return .success(
                    stdout: """
                    nas_12tb/nas/documents@20220805-000000
                    nas_12tb/nas/documents@20220803-000000
                    nas_12tb/nas/documents@20220801-000000
                    nas_12tb/nas/documents@20220729-000000
                    """
                )!
            case "zfs destroy nas_12tb/nas/documents@20220729-000000":
                expectDestroy20220729.fulfill()
                return .success()
            case "zfs destroy nas_12tb/nas/documents@20220801-000000":
                expectDestroy20220801.fulfill()
                return .success()
            case "zfs destroy nas_12tb/nas/documents@20220805-000000":
                expectDestroy20220805.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await consolidator.consolidate()
        await fulfillment(
            of: [
                expectDestroy20220729,
                expectDestroy20220801,
                expectDestroy20220805
            ],
            timeout: timeout
        )
    }

    func testSnapshotsAfterUpperBoundAreNotDeleted() async throws {
        let expect20220806IsNotDestroyed = expectation(description: "expect destroy 20220806")
        expect20220806IsNotDestroyed.isInverted = true
        let expect20220807IsNotDestroyed = expectation(description: "expect destroy 20220807")
        expect20220807IsNotDestroyed.isInverted = true
        let expect20220808IsNotDestroyed = expectation(description: "expect destroy 20220808")
        expect20220808IsNotDestroyed.isInverted = true
        let config = makeConfig(
            schedule: .Builder(upperBound: testDateString)
                .keepingSnapshots(1, every: 1, .weeks, repeatedBy: 1)
                .build(),
            snapshotsNotConsolidated: []
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
            case "zfs list -o name -H | grep nas_12tb/nas/":
                return .success(
                    stdout: """
                    nas_12tb/nas/documents
                    """
                )!
            case "zfs list -o name -H -t snapshot | grep nas_12tb/nas/":
                return .success(
                    stdout: """
                    nas_12tb/nas/documents@20220808-000000                  
                    nas_12tb/nas/documents@20220807-000000                  
                    nas_12tb/nas/documents@20220806-000000
                    """
                )!
            case "zfs destroy nas_12tb/nas/documents@20220806-000000":
                expect20220806IsNotDestroyed.fulfill()
                return .success()
            case "zfs destroy nas_12tb/nas/documents@20220807-000000":
                expect20220807IsNotDestroyed.fulfill()
                return .success()
            case "zfs destroy nas_12tb/nas/documents@20220808-000000":
                expect20220808IsNotDestroyed.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await consolidator.consolidate()
        await fulfillment(
            of: [
                expect20220806IsNotDestroyed,
                expect20220807IsNotDestroyed,
                expect20220808IsNotDestroyed,
            ],
            timeout: timeout
        )
    }
}
