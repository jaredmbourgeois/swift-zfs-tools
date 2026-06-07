// PoolUtilizationTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

final class PoolUtilizationTest: XCTestCase {
    // MARK: - exceedsThreshold

    func testExceedsThresholdCapacity() {
        let utilization = PoolUtilization(capacityPercent: 85, usedBytes: 850_000_000_000, availableBytes: 150_000_000_000)
        XCTAssertTrue(utilization.exceedsThreshold(maxCapacityPercent: 80, minFreeBytes: nil))
        XCTAssertFalse(utilization.exceedsThreshold(maxCapacityPercent: 90, minFreeBytes: nil))
    }

    func testExceedsThresholdMinFreeBytes() {
        let utilization = PoolUtilization(capacityPercent: 50, usedBytes: 500_000_000_000, availableBytes: 500_000_000_000)
        XCTAssertTrue(utilization.exceedsThreshold(maxCapacityPercent: nil, minFreeBytes: 600_000_000_000))
        XCTAssertFalse(utilization.exceedsThreshold(maxCapacityPercent: nil, minFreeBytes: 400_000_000_000))
    }

    func testExceedsThresholdMinFreeBytesTakesPrecedence() {
        // minFreeBytes triggers even when capacity is within threshold
        let utilization = PoolUtilization(capacityPercent: 50, usedBytes: 500_000_000_000, availableBytes: 1_000_000_000)
        XCTAssertTrue(utilization.exceedsThreshold(maxCapacityPercent: 80, minFreeBytes: 5_000_000_000))
    }

    func testExceedsThresholdNoThresholds() {
        let utilization = PoolUtilization(capacityPercent: 99, usedBytes: 990_000_000_000, availableBytes: 10_000_000_000)
        XCTAssertFalse(utilization.exceedsThreshold(maxCapacityPercent: nil, minFreeBytes: nil))
    }

    // MARK: - poolName

    func testPoolNameFromDatasetPath() {
        XCTAssertEqual("tank", PoolUtilization.poolName(from: "tank/data/files"))
        XCTAssertEqual("nas_12tb", PoolUtilization.poolName(from: "nas_12tb/nas"))
        XCTAssertEqual("rpool", PoolUtilization.poolName(from: "rpool"))
    }

    func testPoolNameFromNil() {
        XCTAssertNil(PoolUtilization.poolName(from: nil))
        XCTAssertNil(PoolUtilization.poolName(from: ""))
    }

    // MARK: - query with mock shell

    func testQueryParsesOutput() async throws {
        let shell = ShellAtPath {
            @Sendable (
                _ command: ShellCommand,
                _ dryRun: Bool,
                _ estimatedOutputSize: Int?,
                _ estimatedErrorSize: Int?,
                _ statusesForResult: ShellTermination.StatusesForResult,
                _ stream: ShellStream?,
                _ timeout: TimeInterval?
            ) async -> ShellResult in
            if command.contains("zpool list") {
                return .success(stdout: "42")!
            } else if command.contains("zfs list") {
                return .success(stdout: "1234567890\t9876543210")!
            }
            XCTFail("unexpected command: \(command)")
            return .success()
        }
        let utilization = try await PoolUtilization.query(
            pool: "tank",
            shell: shell,
            dryRun: false,
            stringEncoding: .utf8,
            lineSeparator: "\n"
        )
        XCTAssertEqual(42, utilization.capacityPercent)
        XCTAssertEqual(1_234_567_890, utilization.usedBytes)
        XCTAssertEqual(9_876_543_210, utilization.availableBytes)
    }

    func testQueryReturnsZerosInDryRun() async throws {
        // In dry-run swift-shell echoes each command as stdout instead of running it, so the
        // "output" is the (non-numeric, unparseable) command text. The guard must stay a safe
        // no-op and return zeros — not throw. Regression guard for the H2 fail-loud change.
        let shell = ShellAtPath {
            @Sendable (
                _ command: ShellCommand,
                _ dryRun: Bool,
                _ estimatedOutputSize: Int?,
                _ estimatedErrorSize: Int?,
                _ statusesForResult: ShellTermination.StatusesForResult,
                _ stream: ShellStream?,
                _ timeout: TimeInterval?
            ) async -> ShellResult in
            // mimic swift-shell's dry-run: echo the command back as stdout
            .success(stdout: command)!
        }
        let utilization = try await PoolUtilization.query(
            pool: "tank",
            shell: shell,
            dryRun: true,
            stringEncoding: .utf8,
            lineSeparator: "\n"
        )
        XCTAssertEqual(PoolUtilization(capacityPercent: 0, usedBytes: 0, availableBytes: 0), utilization)
    }

    func testQueryThrowsOnUnparseableCapacity() async throws {
        // Command succeeded (exit 0) but emitted garbage — fail loud rather than silently reading 0%.
        let shell = ShellAtPath {
            @Sendable (
                _ command: ShellCommand,
                _ dryRun: Bool,
                _ estimatedOutputSize: Int?,
                _ estimatedErrorSize: Int?,
                _ statusesForResult: ShellTermination.StatusesForResult,
                _ stream: ShellStream?,
                _ timeout: TimeInterval?
            ) async -> ShellResult in
            if command.contains("zpool list") {
                return .success(stdout: "not-a-number")!
            }
            return .success(stdout: "1234567890\t9876543210")!
        }
        do {
            _ = try await PoolUtilization.query(pool: "tank", shell: shell, dryRun: false, stringEncoding: .utf8, lineSeparator: "\n")
            XCTFail("expected query to throw on unparseable capacity")
        } catch {
            // expected
        }
    }

    func testQueryThrowsOnUnparseableUsedAvailable() async throws {
        let shell = ShellAtPath {
            @Sendable (
                _ command: ShellCommand,
                _ dryRun: Bool,
                _ estimatedOutputSize: Int?,
                _ estimatedErrorSize: Int?,
                _ statusesForResult: ShellTermination.StatusesForResult,
                _ stream: ShellStream?,
                _ timeout: TimeInterval?
            ) async -> ShellResult in
            if command.contains("zpool list") {
                return .success(stdout: "42")!
            }
            return .success(stdout: "garbage-without-tab")!
        }
        do {
            _ = try await PoolUtilization.query(pool: "tank", shell: shell, dryRun: false, stringEncoding: .utf8, lineSeparator: "\n")
            XCTFail("expected query to throw on unparseable used/available")
        } catch {
            // expected
        }
    }

    // MARK: - Dry-run + threshold does not throw (regression)

    func testSnapshotDryRunWithThresholdDoesNotThrow() async throws {
        // dry-run (execute: false, the default) + a pool threshold must print the plan, not error.
        // swift-shell echoes commands in dry-run, which the fail-loud pool parser must tolerate.
        let shell = ShellAtPath {
            @Sendable (
                _ command: ShellCommand,
                _ dryRun: Bool,
                _ estimatedOutputSize: Int?,
                _ estimatedErrorSize: Int?,
                _ statusesForResult: ShellTermination.StatusesForResult,
                _ stream: ShellStream?,
                _ timeout: TimeInterval?
            ) async -> ShellResult in
            .success(stdout: command)!
        }
        let config = Snapshotter.Config(
            datasetGrep: "tank/data",
            dateSeparator: Defaults.dateSeparator,
            execute: false,
            lineSeparator: Defaults.lineSeparator,
            maxPoolUtilizationPercent: 80,
            recursive: false,
            stringEncodingRawValue: Defaults.stringEncoding.rawValue
        )
        let snapshotter = Snapshotter(
            config: config,
            date: { testDate },
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await snapshotter.snapshot()
    }

    // MARK: - Snapshot skips when over threshold

    func testSnapshotSkipsWhenOverThreshold() async throws {
        let snapshotShouldNotBeCalled = expectation(description: "snapshot should not be called")
        snapshotShouldNotBeCalled.isInverted = true
        let shell = ShellAtPath {
            @Sendable (
                _ command: ShellCommand,
                _ dryRun: Bool,
                _ estimatedOutputSize: Int?,
                _ estimatedErrorSize: Int?,
                _ statusesForResult: ShellTermination.StatusesForResult,
                _ stream: ShellStream?,
                _ timeout: TimeInterval?
            ) async -> ShellResult in
            if command.contains("zpool list") {
                return .success(stdout: "90")!
            } else if command.contains("zfs list -Hp -o used,available") {
                return .success(stdout: "900000000000\t100000000000")!
            } else if command.contains("zfs list") {
                return .success(stdout: "tank/data")!
            } else if command.contains("zfs snapshot") {
                snapshotShouldNotBeCalled.fulfill()
                return .success()
            }
            return .success()
        }
        let config = Snapshotter.Config(
            datasetGrep: "tank/data",
            dateSeparator: Defaults.dateSeparator,
            execute: true,
            lineSeparator: Defaults.lineSeparator,
            maxPoolUtilizationPercent: 80,
            recursive: false,
            stringEncodingRawValue: Defaults.stringEncoding.rawValue
        )
        let snapshotter = Snapshotter(
            config: config,
            date: { testDate },
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await snapshotter.snapshot()
        await fulfillment(of: [snapshotShouldNotBeCalled], timeout: 0.1)
    }

    func testSnapshotProceedsWhenUnderThreshold() async throws {
        let expectSnapshot = expectation(description: "snapshot command called")
        let shell = ShellAtPath {
            @Sendable (
                _ command: ShellCommand,
                _ dryRun: Bool,
                _ estimatedOutputSize: Int?,
                _ estimatedErrorSize: Int?,
                _ statusesForResult: ShellTermination.StatusesForResult,
                _ stream: ShellStream?,
                _ timeout: TimeInterval?
            ) async -> ShellResult in
            if command.contains("zpool list") {
                return .success(stdout: "50")!
            } else if command.contains("zfs list -Hp -o used,available") {
                return .success(stdout: "500000000000\t500000000000")!
            } else if command.contains("zfs list") {
                return .success(stdout: "tank/data")!
            } else if command.contains("zfs snapshot") {
                expectSnapshot.fulfill()
                return .success()
            }
            XCTFail("unexpected command: \(command)")
            return .success()
        }
        let config = Snapshotter.Config(
            datasetGrep: "tank/data",
            dateSeparator: Defaults.dateSeparator,
            execute: true,
            lineSeparator: Defaults.lineSeparator,
            maxPoolUtilizationPercent: 80,
            recursive: false,
            stringEncodingRawValue: Defaults.stringEncoding.rawValue
        )
        let snapshotter = Snapshotter(
            config: config,
            date: { testDate },
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await snapshotter.snapshot()
        await fulfillment(of: [expectSnapshot], timeout: timeout)
    }

    // MARK: - Config backward compatibility

    func testSnapshotConfigDecodesWithoutNewFields() throws {
        let json = """
        {
            "datasetGrep": "tank/data",
            "dateSeparator": "@",
            "execute": false,
            "lineSeparator": "\\n",
            "recursive": false,
            "stringEncodingRawValue": 4
        }
        """
        let config = try JSONDecoder().decode(Snapshotter.Config.self, from: json.data(using: .utf8)!)
        XCTAssertNil(config.maxPoolUtilizationPercent)
        XCTAssertNil(config.minFreeBytes)
    }

    func testConsolidatorConfigDecodesWithoutNewFields() throws {
        let json = """
        {
            "datasetGrep": "tank/data",
            "dateSeparator": "@",
            "execute": false,
            "lineSeparator": "\\n",
            "schedule": {
                "periods": [],
                "upperBound": null
            },
            "snapshotsNotConsolidated": [],
            "stringEncodingRawValue": 4
        }
        """
        let config = try JSONDecoder().decode(Consolidator.Config.self, from: json.data(using: .utf8)!)
        XCTAssertNil(config.maxPoolUtilizationPercent)
        XCTAssertNil(config.minFreeBytes)
    }

    func testSnapshotConfigEncodesNewFields() throws {
        let config = Snapshotter.Config(
            datasetGrep: "tank",
            dateSeparator: "@",
            execute: false,
            lineSeparator: "\n",
            maxPoolUtilizationPercent: 80,
            minFreeBytes: 5_368_709_120,
            recursive: false,
            stringEncodingRawValue: Defaults.stringEncoding.rawValue
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(Snapshotter.Config.self, from: data)
        XCTAssertEqual(config, decoded)
        XCTAssertEqual(80, decoded.maxPoolUtilizationPercent)
        XCTAssertEqual(5_368_709_120, decoded.minFreeBytes)
    }
}
