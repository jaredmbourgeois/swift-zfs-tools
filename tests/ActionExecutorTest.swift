// ActionExecutorTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

// Confirms ActionExecutor decodes each action's config through the FileSystem witness and
// dispatches to the matching operation. Each operation is recognised by the mutation it issues
// on its own dataset (the listings are the same bare commands for all three; the dataset filter
// is applied in Swift).
final class ActionExecutorTest: XCTestCase {
    func testExecuteDispatchesEachAction() async throws {
        // The three configs are real files, in a directory this test owns.
        let directory = try TestRoot.makeTemporaryDirectory()
        defer { directory.remove() }
        let fileSystem = FileSystem.rooted(at: directory)
        let encoder = JSONEncoder()
        try fileSystem.write(
            try encoder.encode(
                Snapshotter.Config(
                    datasetGrep: "tank/snap",
                    dateSeparator: "@",
                    execute: true,
                    excludedDatasetGreps: [],
                    lineSeparator: "\n",
                    maxPoolUtilizationPercent: nil,
                    minFreeBytes: nil,
                    recursive: false,
                    stringEncodingRawValue: Defaults.stringEncoding.rawValue
                )
            ),
            "/snap.json"
        )
        try fileSystem.write(
            try encoder.encode(
                Consolidator.Config(
                    datasetGrep: "tank/cons",
                    dateSeparator: "@",
                    execute: true,
                    lineSeparator: "\n",
                    maxPoolUtilizationPercent: nil,
                    minFreeBytes: nil,
                    schedule: .init(periods: [], upperBound: nil),
                    snapshotsNotConsolidated: [],
                    stringEncoding: .utf8
                )
            ),
            "/cons.json"
        )
        try fileSystem.write(
            try encoder.encode(
                Syncer.Config(
                    datasetGrep: "tank/sync",
                    dateSeparator: "@",
                    execute: true,
                    lineSeparator: "\n",
                    sshPort: "22",
                    sshKeyPath: "/key",
                    sshUser: "u",
                    sshIP: "host",
                    stringEncoding: .utf8,
                    sendRateLimit: nil,
                    // The destination lists nothing here, so there is nothing a prune could take.
                    pruneRemoteSnapshots: false,
                    sentBookmarkName: nil,
                    remotePathStrip: nil,
                    remotePathRoot: nil
                )
            ),
            "/sync.json"
        )

        let expectSnapshot = expectation(description: "snapshot dispatched")
        expectSnapshot.assertForOverFulfill = false
        let expectConsolidate = expectation(description: "consolidate dispatched")
        expectConsolidate.assertForOverFulfill = false
        let expectSync = expectation(description: "sync dispatched")
        expectSync.assertForOverFulfill = false

        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            switch command {
            case "zfs list -o name -H":
                return .successWithUTF8Stdout("tank/snap\ntank/cons\ntank/sync")
            case "zfs list -o name -H -t snapshot":
                // Consolidate's listing: an empty schedule keeps nothing older than now, so both go.
                return .successWithUTF8Stdout("tank/cons@20220801-000000\ntank/cons@20220802-000000")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecord("guid-1", 1, "tank/sync@20220801-000000"))
            // The snapshot is named for the time on the clock the executor was handed.
            case "zfs snapshot tank/snap@\(testDateString)":
                expectSnapshot.fulfill()
                return .emptySuccess()
            default:
                if command.hasPrefix("zfs destroy tank/cons@") {
                    expectConsolidate.fulfill()
                } else if command.contains("zfs send -v tank/sync@") {
                    expectSync.fulfill()
                }
                return .emptySuccess()
            }
        }

        let executor = ActionExecutor(
            calendar: calendar,
            date: { testDate },
            dateFormatter: dateFormatter,
            diagnostics: unexpectedDiagnostics,
            fileSystem: fileSystem,
            jsonDecoder: JSONDecoder(),
            shell: shell,
            dryRunShell: .unusedDryRunShell()
        )
        try await executor.execute([
            .snapshot(configPath: "/snap.json"),
            .consolidate(configPath: "/cons.json"),
            .sync(configPath: "/sync.json"),
        ])
        await fulfillment(of: [expectSnapshot, expectConsolidate, expectSync], timeout: timeout)
    }
}
