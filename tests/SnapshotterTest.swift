// SnapshotterTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

final class SnapshotterTest: XCTestCase {
    private let calendar = makeCalendar()

    private lazy var dateFormatter = makeDateFormatter(Defaults.dateFormat)

    private let snapshotDate = testDate

    private let timeout = TimeInterval(1)

    func testSnapshotsAreTaken() async throws {
        let config = SnapshotterConfigTest.snapshotConfig(recursive: true, execute: true)
        let datasets = [
            "nas_12tb/nas",
            "nas_12tb/nas/documents",
            "nas_12tb/nas/media",
        ]
        let snapshotNasCommand = "zfs snapshot -r '\(datasets[0])\(Defaults.dateSeparator)\(dateFormatter.string(from: snapshotDate))'"
        let expectSnapshotNas = expectation(description: "expect snapshot \(datasets[0])")
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
            switch command {
            case "zfs list -o name -H | grep '\(SnapshotterConfigTest.defaultDataset)' || true":
                return .success(
                    stdout: datasets.joined(separator: Defaults.lineSeparator)
                )!
            case snapshotNasCommand:
                expectSnapshotNas.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let snapshotter = Snapshotter(
            config: config,
            date: { [snapshotDate] in snapshotDate },
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await snapshotter.snapshot()
        await fulfillment(
            of: [
                expectSnapshotNas,
            ],
            timeout: timeout
        )
    }

    func testExcludedDatasetsAreNotSnapshotted() async throws {
        let config = SnapshotterConfigTest.snapshotConfig(
            recursive: true,
            excludedDatasetGreps: ["received"],
            execute: true
        )
        let includedDataset = "nas_12tb/nas/documents"
        let excludedDataset = "nas_12tb/nas/received/postgres"
        let snapshotIncludedCommand = "zfs snapshot '\(includedDataset)\(Defaults.dateSeparator)\(dateFormatter.string(from: snapshotDate))'"
        let expectSnapshotIncluded = expectation(description: "expect snapshot included dataset")
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
            switch command {
            case "zfs list -o name -H | grep '\(SnapshotterConfigTest.defaultDataset)' || true":
                return .success(stdout: [includedDataset, excludedDataset].joined(separator: Defaults.lineSeparator))!
            case snapshotIncludedCommand:
                expectSnapshotIncluded.fulfill()
                return .success()
            default:
                XCTFail("unexpected command: \(command)")
                return .success()
            }
        }
        let snapshotter = Snapshotter(
            config: config,
            date: { [snapshotDate] in snapshotDate },
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await snapshotter.snapshot()
        await fulfillment(of: [expectSnapshotIncluded], timeout: timeout)
    }

    func testRecursiveExclusionSnapshotsFilteredDatasetsNonrecursively() async throws {
        let config = SnapshotterConfigTest.snapshotConfig(
            recursive: true,
            excludedDatasetGreps: ["received"],
            execute: true
        )
        let includedParent = "nas_12tb/nas"
        let includedChild = "nas_12tb/nas/documents"
        let excludedChild = "nas_12tb/nas/received/postgres"
        let snapshotParentCommand = "zfs snapshot '\(includedParent)\(Defaults.dateSeparator)\(dateFormatter.string(from: snapshotDate))'"
        let snapshotChildCommand = "zfs snapshot '\(includedChild)\(Defaults.dateSeparator)\(dateFormatter.string(from: snapshotDate))'"
        let expectSnapshotParent = expectation(description: "expect snapshot parent without -r")
        let expectSnapshotChild = expectation(description: "expect snapshot child without -r")
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
            switch command {
            case "zfs list -o name -H | grep '\(SnapshotterConfigTest.defaultDataset)' || true":
                return .success(stdout: [includedParent, includedChild, excludedChild].joined(separator: Defaults.lineSeparator))!
            case snapshotParentCommand:
                expectSnapshotParent.fulfill()
                return .success()
            case snapshotChildCommand:
                expectSnapshotChild.fulfill()
                return .success()
            default:
                if command.contains(" -r ") || command.contains(excludedChild) {
                    XCTFail("exclusions must not use recursive snapshotting or snapshot excluded child: \(command)")
                } else {
                    XCTFail("unexpected command: \(command)")
                }
                return .success()
            }
        }
        let snapshotter = Snapshotter(
            config: config,
            date: { [snapshotDate] in snapshotDate },
            dateFormatter: dateFormatter,
            shell: shell
        )
        try await snapshotter.snapshot()
        await fulfillment(of: [expectSnapshotParent, expectSnapshotChild], timeout: timeout)
    }
}
