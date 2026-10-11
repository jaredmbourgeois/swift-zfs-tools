// Utility.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import XCTest
import ZFSToolsModel

// Test support: fixed values and the doubles the tests hand the product in place of anything live.
// Nothing here reads the machine it runs on; the one file that does is TestRoot.swift.

func decodeResourceJSON<T: Decodable>(
    named fileName: String,
    jsonDecoder: JSONDecoder
) throws -> T {
    let fileName = fileName.lowercased().contains(".json") ? fileName : "\(fileName).json"
    return try jsonDecoder.decode(T.self, from: TestRoot.resource(at: fileName))
}

/// Every test runs in one fixed locale and time zone, whatever the machine's are: the product is
/// handed both (`makeCalendar`, `makeDateFormatter`), so a test hands it these.
let testLocale = Locale(identifier: "en_US_POSIX")
let testTimeZone = TimeZone(secondsFromGMT: 0)!

let calendar = makeCalendar(locale: testLocale, timeZone: testTimeZone)
let dateFormat = "yyyyMMdd-HHmmss"
let dateFormatter = makeDateFormatter(dateFormat, timeZone: testTimeZone)
let testDate = dateFormatter.date(from: testDateString)!
let testDateString = "20220806-000000"
let timeout = TimeInterval(1)
let snapshotRecordListCommand = "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg"

func snapshotRecord(_ guid: String, _ createtxg: UInt64, _ name: String) -> String {
    "\(guid)\t\(createtxg)\t\(name)"
}

func snapshotRecordOutput(_ names: [String]) -> String {
    names.map { name in
        snapshotRecord(snapshotGuid(name), snapshotCreatetxg(name), name)
    }
    .joined(separator: "\n")
}

func snapshotGuid(_ name: String) -> String {
    "guid-\(name)"
}

func snapshotCreatetxg(_ name: String) -> UInt64 {
    guard let suffix = name.split(separator: "@", maxSplits: 1).last else { return 0 }
    let digits = suffix.filter { $0 >= "0" && $0 <= "9" }
    return UInt64(String(digits)) ?? 0
}

/// The ssh argument of a rendered local command line — `ssh … '<remote command>'`, or a send
/// pipeline that ends in that stage. It is exactly what sshd hands a receiver's forced command as
/// `SSH_ORIGINAL_COMMAND`; nil for a command that does not go over ssh.
func remoteCommand(inLocalCommandLine line: String) -> String? {
    // A send pipeline ends in the ssh stage; a bare ssh line is the stage itself.
    let sshStage = line.components(separatedBy: " | ssh ").last.map { line.contains(" | ssh ") ? "ssh " + $0 : $0 } ?? line
    guard sshStage.hasPrefix("ssh ") else { return nil }
    return ReceiveGuardPolicy.tokenize(sshStage)?.last
}

/// A value guarded by a lock, so a `@Sendable` mock-shell closure can record into it from whichever
/// task calls it. (swift-shell's own `Locked` is internal to that package since 3.0.0.)
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        _value = value
    }

    var value: Value {
        withLock { $0 }
    }

    @discardableResult
    func withLock<T>(_ operation: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation(&_value)
    }
}

/// The two shells an operation takes, recording every command with which of them it reached:
/// `shell` stands in for the one that runs — `answers` gives the canned result for a command line,
/// or nil for a plain success — and `dryRunShell` is swift-shell's own dry-run shell, which reports
/// the command and spawns nothing. Argv calls reach both as their rendered line
/// (`shellCommandLine`), the same string the real engine reports.
final class RecordingShell: Sendable {
    struct Invocation: Equatable, Sendable {
        let command: String
        let dryRun: Bool
    }

    private let invocations = Locked<[Invocation]>([])
    let shell: ShellAtPath
    let dryRunShell: ShellAtPath

    init(answers: @escaping @Sendable (String) -> ShellResult<ShellAtPathError>?) {
        let invocations = self.invocations
        shell = ShellAtPath { command, _, _, _ in
            invocations.withLock { $0.append(Invocation(command: command, dryRun: false)) }
            return answers(command) ?? .emptySuccess()
        }
        dryRunShell = .dryRun(
            shellObserver: .resultsOnly { command, _ in
                invocations.withLock { $0.append(Invocation(command: command, dryRun: true)) }
            },
            stringEncoding: .utf8
        )
    }

    var all: [Invocation] { invocations.withLock { $0 } }
    /// The command lines that ran, in order.
    var executed: [String] { all.filter { !$0.dryRun }.map(\.command) }
    /// The command lines a dry run held back, in order.
    var dryRuns: [String] { all.filter(\.dryRun).map(\.command) }
}

extension ShellAtPath {
    /// The dry-run shell of a test whose config executes. An executing run holds nothing back, so
    /// a command that reaches this shell fails the test.
    static func unusedDryRunShell() -> ShellAtPath {
        ShellAtPath { command, _, _, _ in
            XCTFail("an executing run sent a command to the dry-run shell: \(command)")
            return .dryRun(command: command, stringEncoding: .utf8)
        }
    }
}

/// The diagnostics sink of a test whose run has nothing to warn about: a line that reaches it
/// fails the test.
let unexpectedDiagnostics: @Sendable (_ line: String) -> Void = { line in
    XCTFail("unexpected diagnostic: \(line)")
}

extension FileSystem {
    /// The real file system inside `directory`, which the test created and removes. A path the
    /// product is handed is read as a path inside it: `/config.json` is `<directory>/config.json`.
    static func rooted(at directory: TemporaryDirectory) -> FileSystem {
        TestRoot.fileSystem(rootedAt: directory, writeFault: { _ in nil })
    }

    /// The same file system, except that every write throws `error` and writes nothing.
    static func rootedFailingEveryWrite(at directory: TemporaryDirectory, with error: any Error) -> FileSystem {
        TestRoot.fileSystem(rootedAt: directory, writeFault: { _ in error })
    }
}
