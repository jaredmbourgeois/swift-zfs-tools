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
    /// An executing consolidation of `nas_12tb/nas/` with the standard separators and encoding and
    /// no pool threshold, none of which these tests vary. The test states the schedule and the
    /// snapshots it protects.
    private func executingConfig(
        schedule: Consolidator.SnapshotConsolidationSchedule,
        snapshotsNotConsolidated: [String]
    ) -> Consolidator.Config {
        .init(
            datasetGrep: "nas_12tb/nas/",
            dateSeparator: "@",
            execute: true,
            lineSeparator: "\n",
            maxPoolUtilizationPercent: nil,
            minFreeBytes: nil,
            schedule: schedule,
            snapshotsNotConsolidated: snapshotsNotConsolidated,
            stringEncoding: .utf8
        )
    }

    func testSnapshotsAreConsolidatedInSinglePeriod() async throws {
        let expectDestroy20220729 = expectation(description: "expect destroy 20220729")
        let expectDestroy20220801 = expectation(description: "expect destroy 20220801")
        let expectDestroy20220805 = expectation(description: "expect destroy 20220805")
        let config = executingConfig(
            schedule: .Builder(upperBound: testDateString)
                .keepingSnapshots(1, every: 1, .weeks, repeatedBy: 1)
                .build(),
            snapshotsNotConsolidated: []
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
            case "zfs list -o name -H -t snapshot":
                return .successWithUTF8Stdout(
                    """
                    nas_12tb/nas/documents@20220805-000000
                    nas_12tb/nas/documents@20220803-000000
                    nas_12tb/nas/documents@20220801-000000
                    nas_12tb/nas/documents@20220729-000000
                    """
                )
            case "zfs destroy nas_12tb/nas/documents@20220729-000000":
                expectDestroy20220729.fulfill()
                return .emptySuccess()
            case "zfs destroy nas_12tb/nas/documents@20220801-000000":
                expectDestroy20220801.fulfill()
                return .emptySuccess()
            case "zfs destroy nas_12tb/nas/documents@20220805-000000":
                expectDestroy20220805.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            diagnostics: unexpectedDiagnostics,
            shell: shell,
            dryRunShell: .unusedDryRunShell()
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
        let config = executingConfig(
            schedule: .Builder(upperBound: testDateString)
                .buildIndefinitelyKeepingSnapshots(
                    1,
                    every: 1,
                    .weeks
                ),
            snapshotsNotConsolidated: []
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
            case "zfs list -o name -H -t snapshot":
                return .successWithUTF8Stdout(
                    """
                    nas_12tb/nas/documents@20220805-000000
                    nas_12tb/nas/documents@20220803-000000
                    nas_12tb/nas/documents@20220801-000000
                    nas_12tb/nas/documents@20220729-000000
                    """
                )
            case "zfs destroy nas_12tb/nas/documents@20220801-000000":
                expectDestroy20220801.fulfill()
                return .emptySuccess()
            case "zfs destroy nas_12tb/nas/documents@20220805-000000":
                expectDestroy20220805.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            diagnostics: unexpectedDiagnostics,
            shell: shell,
            dryRunShell: .unusedDryRunShell()
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
        let config = executingConfig(
            schedule: .Builder(upperBound: testDateString)
                .keepingSnapshots(1, every: 1, .days, repeatedBy: 7)
                .build(),
            snapshotsNotConsolidated: []
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
            case "zfs list -o name -H -t snapshot":
                return .successWithUTF8Stdout(
                    """
                    nas_12tb/nas/documents@20220805-000000
                    nas_12tb/nas/documents@20220803-000000
                    nas_12tb/nas/documents@20220801-000000
                    """
                )
            default:
                XCTFail("unexpected command: \(command)")
                expectNoDeletions.fulfill()
                return .emptySuccess()
            }
        }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            diagnostics: unexpectedDiagnostics,
            shell: shell,
            dryRunShell: .unusedDryRunShell()
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
        let config = executingConfig(
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
            case "zfs list -o name -H -t snapshot":
                return .successWithUTF8Stdout(
                    """
                    nas_12tb/nas/documents@20220805-000000
                    nas_12tb/nas/documents@20220803-000000
                    nas_12tb/nas/documents@20220801-000000
                    nas_12tb/nas/documents@20220729-000000
                    """
                )
            case "zfs destroy nas_12tb/nas/documents@20220729-000000":
                expectDestroy20220729.fulfill()
                return .emptySuccess()
            case "zfs destroy nas_12tb/nas/documents@20220801-000000":
                expectDestroy20220801.fulfill()
                return .emptySuccess()
            case "zfs destroy nas_12tb/nas/documents@20220805-000000":
                expectDestroy20220805.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            diagnostics: unexpectedDiagnostics,
            shell: shell,
            dryRunShell: .unusedDryRunShell()
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
        let config = executingConfig(
            schedule: .Builder(upperBound: testDateString)
                .keepingSnapshots(1, every: 1, .weeks, repeatedBy: 1)
                .build(),
            snapshotsNotConsolidated: []
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
            case "zfs list -o name -H -t snapshot":
                return .successWithUTF8Stdout(
                    """
                    nas_12tb/nas/documents@20220808-000000                  
                    nas_12tb/nas/documents@20220807-000000                  
                    nas_12tb/nas/documents@20220806-000000
                    """
                )
            case "zfs destroy nas_12tb/nas/documents@20220806-000000":
                expect20220806IsNotDestroyed.fulfill()
                return .emptySuccess()
            case "zfs destroy nas_12tb/nas/documents@20220807-000000":
                expect20220807IsNotDestroyed.fulfill()
                return .emptySuccess()
            case "zfs destroy nas_12tb/nas/documents@20220808-000000":
                expect20220808IsNotDestroyed.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            diagnostics: unexpectedDiagnostics,
            shell: shell,
            dryRunShell: .unusedDryRunShell()
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

    func testManualSnapshotNamesAreIgnoredInsteadOfFailingConsolidation() async throws {
        let expectDestroy20220801 = expectation(description: "expect destroy parseable snapshot")
        let expectDestroy20220805 = expectation(description: "expect destroy parseable snapshot")
        let expectManualIsNotDestroyed = expectation(description: "manual snapshot is not destroyed")
        expectManualIsNotDestroyed.isInverted = true
        let config = executingConfig(
            schedule: .Builder(upperBound: testDateString)
                .keepingSnapshots(1, every: 1, .weeks, repeatedBy: 1)
                .build(),
            snapshotsNotConsolidated: []
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
            case "zfs list -o name -H -t snapshot":
                return .successWithUTF8Stdout(
                    """
                    nas_12tb/nas/documents@manual-before-migration
                    nas_12tb/nas/documents@20220805-000000
                    nas_12tb/nas/documents@20220803-000000
                    nas_12tb/nas/documents@20220801-000000
                    """
                )
            case "zfs destroy nas_12tb/nas/documents@20220801-000000":
                expectDestroy20220801.fulfill()
                return .emptySuccess()
            case "zfs destroy nas_12tb/nas/documents@20220805-000000":
                expectDestroy20220805.fulfill()
                return .emptySuccess()
            case "zfs destroy nas_12tb/nas/documents@manual-before-migration":
                expectManualIsNotDestroyed.fulfill()
                return .emptySuccess()
            default:
                XCTFail("unexpected command: \(command)")
                return .emptySuccess()
            }
        }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            diagnostics: unexpectedDiagnostics,
            shell: shell,
            dryRunShell: .unusedDryRunShell()
        )
        try await consolidator.consolidate()
        await fulfillment(of: [expectDestroy20220801, expectDestroy20220805, expectManualIsNotDestroyed], timeout: timeout)
    }

    /// A dry run with a pool threshold reads the real pool after the (held) destroys and reports
    /// what it would do: the listings and both pool reads run, every destroy arrives as a dry run,
    /// and under threshold no aggressive prune follows.
    func testConsolidateDryRunWithThresholdReadsThePoolAndHoldsTheDestroys() async throws {
        let expectDestroy20220729 = expectation(description: "expect destroy 20220729")
        let expectDestroy20220801 = expectation(description: "expect destroy 20220801")
        let expectDestroy20220805 = expectation(description: "expect destroy 20220805")
        let expectPoolReads = expectation(description: "both pool reads run, for real")
        expectPoolReads.expectedFulfillmentCount = 2
        let config = Consolidator.Config(
            datasetGrep: "nas_12tb/nas/",
            dateSeparator: "@",
            execute: false,
            lineSeparator: "\n",
            maxPoolUtilizationPercent: 80,
            minFreeBytes: nil,
            schedule: .Builder(upperBound: testDateString)
                .keepingSnapshots(1, every: 1, .weeks, repeatedBy: 1)
                .build(),
            snapshotsNotConsolidated: [],
            stringEncoding: .utf8
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
            case "zfs list -o name -H -t snapshot":
                return .successWithUTF8Stdout(
                    """
                    nas_12tb/nas/documents@20220805-000000
                    nas_12tb/nas/documents@20220803-000000
                    nas_12tb/nas/documents@20220801-000000
                    nas_12tb/nas/documents@20220729-000000
                    """
                )
            case "zpool list -Hp -o capacity nas_12tb":
                expectPoolReads.fulfill()
                return .successWithUTF8Stdout("50")
            case "zfs list -Hp -o used,available nas_12tb":
                expectPoolReads.fulfill()
                return .successWithUTF8Stdout("500000000000\t500000000000")
            default:
                // The shell that runs sees the listings and the pool reads, and nothing else.
                XCTFail("a destroy is held on a dry run, and no other command is expected: \(command)")
                return .emptySuccess()
            }
        }
        // The dry-run shell sees every destroy, and nothing else: a pool read runs for real.
        let dryRunShell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs destroy nas_12tb/nas/documents@20220729-000000":
                expectDestroy20220729.fulfill()
            case "zfs destroy nas_12tb/nas/documents@20220801-000000":
                expectDestroy20220801.fulfill()
            case "zfs destroy nas_12tb/nas/documents@20220805-000000":
                expectDestroy20220805.fulfill()
            default:
                XCTFail("a pool read runs for real on a dry run, and no other command is held: \(command)")
            }
            return .dryRun(command: command, stringEncoding: .utf8)
        }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            diagnostics: unexpectedDiagnostics,
            shell: shell,
            dryRunShell: dryRunShell
        )
        try await consolidator.consolidate()
        await fulfillment(
            of: [
                expectDestroy20220729,
                expectDestroy20220801,
                expectDestroy20220805,
                expectPoolReads,
            ],
            timeout: timeout
        )
    }

    /// Over threshold on a dry run, the aggressive prune reads the pool once and issues every
    /// candidate oldest-first as a dry-run destroy — the newest snapshot of each dataset kept — so
    /// the report lists what a real run would take, without re-reading a pool nothing changed.
    func testConsolidateDryRunOverThresholdListsTheAggressivePruneCandidates() async throws {
        let config = Consolidator.Config(
            datasetGrep: "nas_12tb/nas/",
            dateSeparator: "@",
            execute: false,
            lineSeparator: "\n",
            maxPoolUtilizationPercent: 80,
            minFreeBytes: nil,
            schedule: .Builder(upperBound: testDateString)
                .keepingSnapshots(4, every: 1, .weeks, repeatedBy: 1)
                .build(),
            snapshotsNotConsolidated: [],
            stringEncoding: .utf8
        )
        let recorder = RecordingShell { command in
            switch command {
            case "zfs list -o name -H": return .successWithUTF8Stdout("nas_12tb/nas/documents")
            case "zfs list -o name -H -t snapshot":
                return .successWithUTF8Stdout("""
                    nas_12tb/nas/documents@20220805-000000
                    nas_12tb/nas/documents@20220803-000000
                    nas_12tb/nas/documents@20220801-000000
                    """)
            case "zpool list -Hp -o capacity nas_12tb": return .successWithUTF8Stdout("95")
            case "zfs list -Hp -o used,available nas_12tb": return .successWithUTF8Stdout("950000000000\t50000000000")
            default: return nil
            }
        }
        let diagnostics = Locked<[String]>([])
        try await Consolidator(
            calendar: calendar,
            config: config,
            date: { [testDate] in testDate },
            dateFormatter: dateFormatter,
            diagnostics: { line in diagnostics.withLock { $0.append(line) } },
            shell: recorder.shell,
            dryRunShell: recorder.dryRunShell
        ).consolidate()
        // The schedule keeps all three; the prune then offers the two oldest and keeps the newest.
        XCTAssertEqual(
            ["zfs destroy nas_12tb/nas/documents@20220801-000000", "zfs destroy nas_12tb/nas/documents@20220803-000000"],
            recorder.dryRuns
        )
        XCTAssertEqual(1, recorder.executed.filter { $0.hasPrefix("zpool list") }.count, "the pool is read once on a dry run")
        // The warning and the narration go to the diagnostics sink (a CLI's stderr), in order.
        XCTAssertEqual(
            [
                "zfs-tools consolidate: WARNING — pool nas_12tb utilization exceeds threshold after consolidation (capacity: 95.0%, available: 50000000000 bytes). dry-run — would prune oldest-first until within threshold; the candidates follow in order.",
                "zfs-tools consolidate: aggressive prune — dry-run — would destroy nas_12tb/nas/documents@20220801-000000 (capacity: 95.0%)",
                "zfs-tools consolidate: aggressive prune — dry-run — would destroy nas_12tb/nas/documents@20220803-000000 (capacity: 95.0%)",
            ],
            diagnostics.value
        )
    }
}
