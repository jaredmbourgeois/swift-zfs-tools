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
        let snapshotNasCommand = "zfs snapshot -r \(datasets[0])\(Defaults.dateSeparator)\(dateFormatter.string(from: snapshotDate))"
        let snapshotNasDocumentsCommand = "zfs snapshot -r \(datasets[1])\(Defaults.dateSeparator)\(dateFormatter.string(from: snapshotDate))"
        let snapshotNasMediaCommand = "zfs snapshot -r \(datasets[2])\(Defaults.dateSeparator)\(dateFormatter.string(from: snapshotDate))"
        let expectSnapshotNas = expectation(description: "expect snapshot \(datasets[0])")
        let expectSnapshotNasDocuments = expectation(description: "expect snapshot \(datasets[1])")
        let expectSnapshotNasMedia = expectation(description: "expect snapshot \(datasets[2])")
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
            case "zfs list -o name -H | grep \(SnapshotterConfigTest.defaultDataset)":
                return .success(
                    stdout: datasets.joined(separator: Defaults.lineSeparator)
                )!
            case snapshotNasCommand:
                expectSnapshotNas.fulfill()
                return .success()
            case snapshotNasDocumentsCommand:
                expectSnapshotNasDocuments.fulfill()
                return .success()
            case snapshotNasMediaCommand:
                expectSnapshotNasMedia.fulfill()
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
                expectSnapshotNasDocuments,
                expectSnapshotNasMedia,
            ],
            timeout: timeout
        )
    }
}
