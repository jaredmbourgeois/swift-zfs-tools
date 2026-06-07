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
// dispatches to the matching operation. Each operation is recognised by its distinctive
// datasetGrep, which appears in the first command it issues.
final class ActionExecutorTest: XCTestCase {
    func testExecuteDispatchesEachAction() async throws {
        let store = InMemoryFileStore()
        let encoder = JSONEncoder()
        store.setData(
            try encoder.encode(
                Snapshotter.Config(
                    datasetGrep: "tank/snap",
                    dateSeparator: "@",
                    execute: true,
                    lineSeparator: "\n",
                    recursive: false,
                    stringEncodingRawValue: Defaults.stringEncoding.rawValue
                )
            ),
            at: "/snap.json"
        )
        store.setData(
            try encoder.encode(
                Consolidator.Config(
                    datasetGrep: "tank/cons",
                    dateSeparator: "@",
                    execute: true,
                    lineSeparator: "\n",
                    schedule: .init(periods: [], upperBound: nil),
                    snapshotsNotConsolidated: [],
                    stringEncoding: .utf8
                )
            ),
            at: "/cons.json"
        )
        store.setData(
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
                    stringEncoding: .utf8
                )
            ),
            at: "/sync.json"
        )

        let expectSnapshot = expectation(description: "snapshot dispatched")
        expectSnapshot.assertForOverFulfill = false
        let expectConsolidate = expectation(description: "consolidate dispatched")
        expectConsolidate.assertForOverFulfill = false
        let expectSync = expectation(description: "sync dispatched")
        expectSync.assertForOverFulfill = false

        let shell = ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ dryRun: Bool,
            _ estimatedOutputSize: Int?,
            _ estimatedErrorSize: Int?,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            if command.contains("grep 'tank/snap'") {
                expectSnapshot.fulfill()
            } else if command.contains("grep 'tank/cons'") {
                expectConsolidate.fulfill()
            } else if command.contains("grep 'tank/sync'") {
                expectSync.fulfill()
            }
            return .success()
        }

        let executor = ActionExecutor(
            calendar: calendar,
            dateFormatter: dateFormatter,
            fileSystem: .inMemory(store),
            jsonDecoder: JSONDecoder(),
            shell: shell
        )
        try await executor.execute([
            .snapshot(configPath: "/snap.json"),
            .consolidate(configPath: "/cons.json"),
            .sync(configPath: "/sync.json"),
        ])
        await fulfillment(of: [expectSnapshot, expectConsolidate, expectSync], timeout: timeout)
    }
}
