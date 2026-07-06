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

// Pins the shell-command construction: every interpolated value is single-quoted so dataset
// names with spaces (legal in ZFS), grep patterns, and ssh args can't word-split or inject.
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

    // MARK: - shellQuoted

    func testShellQuotedWrapsPlainValue() {
        XCTAssertEqual("'abc'", "abc".shellQuoted)
    }

    func testShellQuotedWrapsValueWithSpace() {
        XCTAssertEqual("'a b'", "a b".shellQuoted)
    }

    func testShellQuotedEscapesEmbeddedSingleQuote() {
        // a'b -> 'a'\''b' (close quote, escaped quote, reopen quote)
        XCTAssertEqual("'a'\\''b'", "a'b".shellQuoted)
    }

    func testShellQuotedEmptyString() {
        XCTAssertEqual("''", "".shellQuoted)
    }

    // MARK: - destroy

    func testDestroyQuotesSubject() {
        XCTAssertEqual("zfs destroy 'tank/data@20220806-000000'", ZFS.destroy(subject: "tank/data@20220806-000000"))
    }

    func testDestroyQuotesSubjectWithSpace() {
        XCTAssertEqual("zfs destroy 'tank/my data@20220806-000000'", ZFS.destroy(subject: "tank/my data@20220806-000000"))
    }

    // MARK: - listDatasets / listSnapshots

    func testListDatasetsNoGrep() {
        XCTAssertEqual("zfs list -o name -H", ZFS.listDatasets())
    }

    func testListDatasetsQuotesGrep() {
        XCTAssertEqual("zfs list -o name -H | grep 'tank/data' || true", ZFS.listDatasets(grepping: "tank/data"))
    }

    func testListDatasetsQuotesEmptyGrep() {
        // empty pattern is preserved as grep '' (matches all) rather than a bare `grep`
        XCTAssertEqual("zfs list -o name -H | grep '' || true", ZFS.listDatasets(grepping: ""))
    }

    func testListSnapshotsNoGrep() {
        XCTAssertEqual("zfs list -o name -H -t snapshot", ZFS.listSnapshots())
    }

    func testListSnapshotsQuotesGrep() {
        XCTAssertEqual("zfs list -o name -H -t snapshot | grep 'tank/data' || true", ZFS.listSnapshots(grepping: "tank/data"))
    }

    func testListSnapshotRecordsNoGrep() {
        XCTAssertEqual(
            "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg",
            ZFS.listSnapshotRecords()
        )
    }

    func testListSnapshotRecordsQuotesGrep() {
        XCTAssertEqual(
            "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg | grep 'tank/data' || true",
            ZFS.listSnapshotRecords(grepping: "tank/data")
        )
    }

    func testListBookmarkRecordsQuotesGrep() {
        XCTAssertEqual(
            "zfs list -t bookmark -H -p -o guid,createtxg,name -s createtxg | grep '#sent-backup' || true",
            ZFS.listBookmarkRecords(grepping: "#sent-backup")
        )
    }

    func testBookmarkQuotesSnapshotAndBookmark() {
        XCTAssertEqual(
            "zfs bookmark 'tank/data@s1' 'tank/data#sent-backup'",
            ZFS.bookmark(snapshot: "tank/data@s1", bookmark: "tank/data#sent-backup")
        )
    }

    // MARK: - snapshot

    func testSnapshotQuotesName() {
        let command = ZFS.snapshot(dataset: "tank/data", date: testDate, dateFormatter: dateFormatter, dateSeparator: "@")
        XCTAssertEqual("zfs snapshot 'tank/data@20220806-000000'", command)
    }

    func testSnapshotRecursiveQuotesName() {
        let command = ZFS.snapshot(dataset: "tank/data", date: testDate, dateFormatter: dateFormatter, dateSeparator: "@", recursive: true)
        XCTAssertEqual("zfs snapshot -r 'tank/data@20220806-000000'", command)
    }

    func testSnapshotQuotesNameWithSpace() {
        let command = ZFS.snapshot(dataset: "tank/my data", date: testDate, dateFormatter: dateFormatter, dateSeparator: "@")
        XCTAssertEqual("zfs snapshot 'tank/my data@20220806-000000'", command)
    }

    // MARK: - pool queries

    func testPoolCapacityQuotesPool() {
        XCTAssertEqual("zpool list -Hp -o capacity 'tank'", ZFS.poolCapacity(pool: "tank"))
    }

    func testListUsedAvailableQuotesDataset() {
        XCTAssertEqual("zfs list -Hp -o used,available 'tank'", ZFS.listUsedAvailable(dataset: "tank"))
    }
}
