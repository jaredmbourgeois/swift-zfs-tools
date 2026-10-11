// RemoteShapesGoldenTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

// The wire contract between a `sync` sender and a receiver's `receive-guard`, held across releases.
//
// `tests/resource/remote_shapes/<version>.txt` records every remote command a sender of that version
// sends over ssh for one fixed scenario (below): each line is an `SSH_ORIGINAL_COMMAND` exactly as a
// receiver's guard is handed it, in the order sent. `rejections.txt` holds commands every guard must
// refuse. In both, every line is a command — there is no comment syntax — and the datasets live in
// pool `nas_12tb`.
//
// A fleet upgrades one host at a time, so for a while a new sender pushes into an old guard and an
// old sender into a new one. These tests hold this version's half of that:
//   - the sender emits exactly this version's golden, so a change to a remote command (dropping
//     `-F`, say) fails here until the golden is rewritten on purpose — the moment to ask whether the
//     guards already installed accept the new line;
//   - this version's guard accepts every line of every golden, past versions' included, and refuses
//     every rejection.
// The other half — an OLD guard accepting this version's golden — is checked outside this package,
// by feeding these files to a guard built from the old tag.
//
// A release adds `<new version>.txt` (the failure of `testSenderEmitsThisVersionsGolden` prints the
// lines the sender emits) and never edits a released version's file.
final class RemoteShapesGoldenTest: XCTestCase {
    private static let directory = "remote_shapes"
    private static let rejectionsFileName = "rejections.txt"
    /// The first release to record its shapes. Its file must stay: hosts still run it.
    private static let oldestGoldenFileName = "2.2.0.txt"

    private let policy = ReceiveGuardPolicy(pool: "nas_12tb")

    /// The commands a resource file holds: its lines.
    private func commands(inResource fileName: String) throws -> [String] {
        let data = try TestRoot.resource(at: "\(Self.directory)/\(fileName)")
        let text = try XCTUnwrap(String(data: data, encoding: .utf8), "\(fileName) is not UTF-8")
        return text.split(separator: "\n").map { String($0) }
    }

    /// One file per version: every `.txt` in the directory except the rejections.
    private func goldenFileNames() throws -> [String] {
        try TestRoot.resourceNames(inDirectory: Self.directory)
            .filter { $0.hasSuffix(".txt") && $0 != Self.rejectionsFileName }
    }

    /// The remote commands of the golden scenario, in the order the sender issues them.
    ///
    /// The scenario is one executing sync that prunes, throttles and keeps a sent-bookmark, over
    /// four datasets chosen so that every shape appears bare and quoted:
    ///   - `documents` owes two snapshots after a common one, and the destination holds a stale
    ///     one: a destroy, then one `-I` stream received into the dataset;
    ///   - `media` owes one: a single-snapshot receive;
    ///   - `my data` (a name that needs quoting) shares nothing with the destination's stale
    ///     snapshot: a quoted destroy, then a full send received as a quoted snapshot;
    ///   - `my docs` is new to the destination and owes two: a full send, then an `-I` stream
    ///     received into the quoted dataset.
    private func remoteCommandsOfTheGoldenScenario() async throws -> [String] {
        let config = SyncerConfigTest.syncConfig(
            datasetGrep: SyncerConfigTest.datasetGrep,
            execute: true,
            sshKeyPath: SyncerConfigTest.sshKeyPath,
            sendRateLimit: "20M",
            pruneRemoteSnapshots: true,
            sentBookmarkName: "sent-serverMTB",
            remotePathStrip: nil,
            remotePathRoot: nil
        )
        let recorder = RecordingShell { command in
            switch command {
            case "zfs list -o name -H":
                // Not in name order: the sender sorts, so the golden's order is its own.
                return .successWithUTF8Stdout("nas_12tb/nas/my docs\nnas_12tb/nas/media\nnas_12tb/nas/my data\nnas_12tb/nas/documents")
            case "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220801-000000",
                    "nas_12tb/nas/documents@20220805-000000",
                    "nas_12tb/nas/documents@20220806-000000",
                    "nas_12tb/nas/media@20220805-000000",
                    "nas_12tb/nas/media@20220806-000000",
                    "nas_12tb/nas/my data@20220806-000000",
                    "nas_12tb/nas/my docs@20220805-000000",
                    "nas_12tb/nas/my docs@20220806-000000",
                ]))
            case "ssh -p sshPort -i sshKeyPath sshUser@sshIP 'zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg'":
                return .successWithUTF8Stdout(snapshotRecordOutput([
                    "nas_12tb/nas/documents@20220730-000000",
                    "nas_12tb/nas/documents@20220801-000000",
                    "nas_12tb/nas/media@20220805-000000",
                    "nas_12tb/nas/my data@20220730-000000",
                ]))
            case "zfs list -t bookmark -H -p -o guid,createtxg,name -s createtxg":
                return .successWithUTF8Stdout("")
            default:
                return nil
            }
        }
        try await Syncer(
            config: config,
            dateFormatter: dateFormatter,
            shell: recorder.shell,
            dryRunShell: recorder.dryRunShell
        ).sync()
        XCTAssertEqual([], recorder.dryRuns, "the scenario executes: nothing is held back")
        return recorder.executed.compactMap(remoteCommand(inLocalCommandLine:))
    }

    func testSenderEmitsThisVersionsGolden() async throws {
        let goldenFileName = "\(ToolVersion.current).txt"
        let golden = try commands(inResource: goldenFileName)
        let emitted = try await remoteCommandsOfTheGoldenScenario()
        XCTAssertEqual(
            golden,
            emitted,
            "the sender's remote commands are not \(Self.directory)/\(goldenFileName); it emits:\n" + emitted.joined(separator: "\n")
        )
    }

    func testGuardAcceptsEveryLineOfEveryGolden() throws {
        let goldenFileNames = try goldenFileNames()
        // A missing file would pass the loop below by not being in it.
        XCTAssertTrue(goldenFileNames.contains("\(ToolVersion.current).txt"), "no golden for \(ToolVersion.current) among \(goldenFileNames)")
        XCTAssertTrue(goldenFileNames.contains(Self.oldestGoldenFileName), "\(Self.oldestGoldenFileName) is gone from \(goldenFileNames)")
        for goldenFileName in goldenFileNames {
            let commands = try commands(inResource: goldenFileName)
            XCTAssertFalse(commands.isEmpty, "\(goldenFileName) holds no command")
            for command in commands {
                if case .failure(let rejection) = policy.validate(command) {
                    XCTFail("the guard rejects `\(command)` of \(goldenFileName): \(rejection)")
                }
            }
        }
    }

    func testGuardRejectsEveryRejection() throws {
        let rejections = try commands(inResource: Self.rejectionsFileName)
        XCTAssertFalse(rejections.isEmpty, "\(Self.rejectionsFileName) holds no command")
        for command in rejections {
            if case .success(let argv) = policy.validate(command) {
                XCTFail("the guard accepts `\(command)` and would run \(argv)")
            }
        }
    }
}
