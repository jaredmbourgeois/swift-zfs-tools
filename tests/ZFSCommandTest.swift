// ZFSCommandTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

// Pins the command construction: every command is argv (no shell parses a dataset name), each
// builder declares whether it mutates — the one input to the dry-run decision — and the rendered
// line quotes a token only when it needs quoting.
final class ZFSCommandTest: XCTestCase {
    // MARK: - shell logging

    func testShellLogFormatterLabelsCommandResultStdoutAndStderrSeparately() {
        let formatter = ShellLogFormatter(toolName: "zfs-tools", lineSeparator: "\n", stringEncoding: .utf8)
        let result = ShellResult<ShellAtPathError>.success(stderr: "warning\n", stdout: "dataset\n")!

        XCTAssertEqual("zfs-tools command: zfs list -o name -H", formatter.command("zfs list -o name -H"))
        XCTAssertEqual("zfs-tools result: success (0)", formatter.result(result))
        XCTAssertEqual("zfs-tools stdout:\ndataset\n", formatter.stdout(result.processOutput.stdout))
        XCTAssertEqual("zfs-tools stderr:\nwarning\n", formatter.stderr(result.processOutput.stderr))
    }

    // MARK: - effect: the dry-run decision's one input

    func testListingsAndPoolReadsAreReadOnly() {
        for command in [
            ZFS.listDatasets(),
            ZFS.listSnapshots(),
            ZFS.listSnapshotRecords(),
            ZFS.listBookmarkRecords(),
            ZFS.poolCapacity(pool: "tank"),
            ZFS.listUsedAvailable(dataset: "tank"),
        ] {
            XCTAssertEqual(.readOnly, command.effect, command.commandLine)
        }
    }

    func testEverythingElseMutates() {
        for command in [
            ZFS.destroy(subject: "tank/data@s1"),
            ZFS.bookmark(snapshot: "tank/data@s1", bookmark: "tank/data#sent"),
            ZFS.snapshot(dataset: "tank/data", date: testDate, dateFormatter: dateFormatter, dateSeparator: "@"),
            ZFS.receive(target: "tank/data"),
        ] {
            XCTAssertEqual(.mutating, command.effect, command.commandLine)
        }
    }

    // MARK: - argv and its rendering

    func testDestroyIsArgvAndRendersBare() {
        let command = ZFS.destroy(subject: "tank/data@20220806-000000")
        XCTAssertEqual(.argv(executable: "zfs", arguments: ["destroy", "tank/data@20220806-000000"]), command.form)
        XCTAssertEqual("zfs destroy tank/data@20220806-000000", command.commandLine)
    }

    func testDestroyRendersASpacedNameQuoted() {
        XCTAssertEqual("zfs destroy 'tank/my data@20220806-000000'", ZFS.destroy(subject: "tank/my data@20220806-000000").commandLine)
    }

    func testListingsTakeNoFilter() {
        XCTAssertEqual("zfs list -o name -H", ZFS.listDatasets().commandLine)
        XCTAssertEqual("zfs list -o name -H -t snapshot", ZFS.listSnapshots().commandLine)
        XCTAssertEqual("zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg", ZFS.listSnapshotRecords().commandLine)
        XCTAssertEqual("zfs list -t bookmark -H -p -o guid,createtxg,name -s createtxg", ZFS.listBookmarkRecords().commandLine)
    }

    func testBookmarkQuotesOnlyTheHashNames() {
        // `#` is outside the safe set, so a bookmark name is quoted and a snapshot name is not.
        XCTAssertEqual(
            "zfs bookmark tank/data@s1 'tank/data#sent-backup'",
            ZFS.bookmark(snapshot: "tank/data@s1", bookmark: "tank/data#sent-backup").commandLine
        )
    }

    func testSnapshotName() {
        let command = ZFS.snapshot(dataset: "tank/data", date: testDate, dateFormatter: dateFormatter, dateSeparator: "@")
        XCTAssertEqual("zfs snapshot tank/data@20220806-000000", command.commandLine)
    }

    func testSnapshotRecursive() {
        let command = ZFS.snapshot(dataset: "tank/data", date: testDate, dateFormatter: dateFormatter, dateSeparator: "@", recursive: true)
        XCTAssertEqual("zfs snapshot -r tank/data@20220806-000000", command.commandLine)
    }

    func testSnapshotSpacedNameIsOneArgument() {
        let command = ZFS.snapshot(dataset: "tank/my data", date: testDate, dateFormatter: dateFormatter, dateSeparator: "@")
        XCTAssertEqual(.argv(executable: "zfs", arguments: ["snapshot", "tank/my data@20220806-000000"]), command.form)
        XCTAssertEqual("zfs snapshot 'tank/my data@20220806-000000'", command.commandLine)
    }

    func testReceiveTarget() {
        XCTAssertEqual("zfs recv -F tank/data@s1", ZFS.receive(target: "tank/data@s1").commandLine)
    }

    // MARK: - pool queries

    func testPoolCapacityIsZpool() {
        let command = ZFS.poolCapacity(pool: "tank")
        XCTAssertEqual(.argv(executable: "zpool", arguments: ["list", "-Hp", "-o", "capacity", "tank"]), command.form)
        XCTAssertEqual("zpool list -Hp -o capacity tank", command.commandLine)
    }

    func testListUsedAvailable() {
        XCTAssertEqual("zfs list -Hp -o used,available tank", ZFS.listUsedAvailable(dataset: "tank").commandLine)
    }

    // MARK: - the Swift-side filter that replaced `| grep … || true`

    func testMatchingIsAFixedSubstringFilter() {
        let names = ["tank/data", "tank/data/docs", "tankish/data", "other"]
        XCTAssertEqual(["tank/data", "tank/data/docs"], names.matching("tank/data"))
        XCTAssertEqual(names, names.matching(nil))
        XCTAssertEqual(names, names.matching(""))
        XCTAssertEqual([], names.matching("tank/data."))  // a `.` is a literal, not a regex wildcard
    }

    // MARK: - ZFSRunner: read-only always runs, mutations honor execute

    func testRunnerRunsReadOnlyCommandsOnADryRunAndHoldsMutations() async throws {
        let recorder = RecordingShell { command in
            command == "zfs list -o name -H" ? .success(stdout: "tank/data")! : nil
        }
        let runner = ZFSRunner(shell: recorder.shell, execute: false, stringEncoding: .utf8, lineSeparator: "\n")
        let listed = try await runner.lines(ZFS.listDatasets())
        XCTAssertEqual(["tank/data"], listed)
        let destroyed = try await runner.run(ZFS.destroy(subject: "tank/data@s1"))
        XCTAssertEqual("zfs destroy tank/data@s1\n", try destroyed.decodeString().stdoutTyped)
        XCTAssertEqual(["zfs list -o name -H"], recorder.executed)
        XCTAssertEqual(["zfs destroy tank/data@s1"], recorder.dryRuns)
    }

    func testRunnerExecutesMutationsWhenExecuting() async throws {
        let recorder = RecordingShell { _ in nil }
        let runner = ZFSRunner(shell: recorder.shell, execute: true, stringEncoding: .utf8, lineSeparator: "\n")
        _ = try await runner.run(ZFS.destroy(subject: "tank/data@s1"))
        XCTAssertEqual(["zfs destroy tank/data@s1"], recorder.executed)
        XCTAssertEqual([], recorder.dryRuns)
    }
}
