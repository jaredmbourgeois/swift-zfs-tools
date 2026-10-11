// Common.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell

public typealias Model = Sendable & Codable
public typealias EquatableModel = Model & Equatable
public typealias HashableModel = Model & Hashable

extension DateFormatter {
    func dateForSnapshot(
        _ snapshot: String,
        dateSeparator: String
    ) throws -> Date {
        guard let dateSubString = snapshot.split(separator: dateSeparator).last,
              let date = date(from: String(dateSubString)) else {
            throw ErrorType.dateFromString(string: snapshot, format: dateFormat)
        }
        return date
    }
}

/// The Gregorian calendar the retention schedule's period math runs on. `locale` and `timeZone`
/// are the operator's, read once at the composition root and handed down: where a day or a week
/// begins decides which window a snapshot falls in.
public func makeCalendar(locale: Locale, timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    calendar.timeZone = timeZone
    return calendar
}

/// The formatter that writes and parses a snapshot's timestamp suffix. The locale is fixed
/// (`en_US_POSIX`), so `dateFormat` reads the same on every host; `timeZone` is the operator's, read
/// once at the composition root and handed down, so a snapshot is named for its local wall time.
public func makeDateFormatter(_ dateFormat: String, timeZone: TimeZone) -> DateFormatter {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = dateFormat
    dateFormatter.locale = .init(identifier: "en_US_POSIX")
    dateFormatter.timeZone = timeZone
    return dateFormatter
}

/// `path` when it can be the working directory of the commands the tool spawns — an absolute path —
/// and otherwise an error naming what was read. A composition root passes what it read from its
/// process through here first: a deleted current directory reads as an empty path, and the shell
/// engine traps on a relative one rather than run a command somewhere nobody chose.
public func validatedWorkingDirectory(_ path: String) throws -> String {
    guard path.hasPrefix("/") else {
        throw ErrorType.invalidArgument(
            name: "working directory",
            value: path,
            reason: "expected an absolute path; run the command from a directory that still exists"
        )
    }
    return path
}

/// Renders a finished command as the tool's log entries, each prefixed with a distinct
/// `<tool> <event>:` label. Shared by the `zfs-tools` CLI and the `zfs-tools-build` builder.
public struct ShellLogFormatter: Sendable {
    public let toolName: String
    public let lineSeparator: String
    public let stringEncoding: String.Encoding

    public init(
        toolName: String,
        lineSeparator: String,
        stringEncoding: String.Encoding
    ) {
        self.toolName = toolName
        self.lineSeparator = lineSeparator
        self.stringEncoding = stringEncoding
    }

    public func command(_ command: ShellCommand) -> String {
        "\(toolName) command: \(command)"
    }

    public func result(_ result: ShellResult<ShellAtPathError>) -> String {
        if let error = result.error {
            return "\(toolName) result: error (\(result.termination.status)) \(error.userInfo[NSLocalizedDescriptionKey] ?? error.localizedDescription)"
        }
        return "\(toolName) result: success (\(result.termination.status))"
    }

    public func stdout(_ data: Data) -> String? {
        output(label: "stdout", data: data)
    }

    public func stderr(_ data: Data) -> String? {
        output(label: "stderr", data: data)
    }

    private func output(label: String, data: Data) -> String? {
        if let string = String(data: data, encoding: stringEncoding) {
            guard !string.isEmpty else { return nil }
            return "\(toolName) \(label):\(lineSeparator)\(string)"
        }
        return "\(toolName) \(label): (\(data.count) bytes) could not be decoded as \(String(reflecting: stringEncoding)) (\(stringEncoding.rawValue))"
    }
}

extension ShellLogFormatter {
    /// An observer that writes each finished command's log — the command line, its result, then any
    /// stdout and stderr — through `write`, one entry per call. A composition root supplies `write`
    /// (a CLI's stdout: the command log is what a run, or a dry run, is asked to show) and attaches
    /// the observer to the shells it builds, so the model itself never prints.
    public func resultObserver(
        write: @escaping @Sendable (_ entry: String) -> Void
    ) -> ShellObserver<ShellAtPathError> {
        .resultsOnly { command, result in
            write(self.command(command))
            write(self.result(result))
            if let stdout = self.stdout(result.processOutput.stdout) {
                write(stdout)
            }
            if let stderr = self.stderr(result.processOutput.stderr) {
                write(stderr)
            }
        }
    }
}

struct SnapshotAndDate: Equatable, Sendable {
    let snapshot: String
    let date: Date
}

struct SnapshotRecord: Equatable, Sendable {
    let guid: String
    let createtxg: UInt64
    let name: String

    var dataset: String {
        name.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? name
    }

    var bookmarkDataset: String {
        name.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? name
    }

    func withName(_ newName: String) -> SnapshotRecord {
        SnapshotRecord(guid: guid, createtxg: createtxg, name: newName)
    }

    static func parse(_ line: String, command: String) throws -> SnapshotRecord {
        let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3 else {
            throw ErrorType.shellError(
                command: command,
                error: "expected guid, createtxg, name fields for snapshot record: \(line)"
            )
        }
        guard let createtxg = UInt64(fields[1]) else {
            throw ErrorType.shellError(
                command: command,
                error: "expected integer createtxg for snapshot record: \(line)"
            )
        }
        return SnapshotRecord(guid: String(fields[0]), createtxg: createtxg, name: String(fields[2]))
    }
}

// `String.shellQuoted` — POSIX single-quoting for a value interpolated into a shell command line —
// is swift-shell's (`ShellQuoting.swift`), shared with `[String].shellCommandLine`.

/// One command the tool issues: WHAT runs (`form`) and whether it changes anything (`effect`).
/// `effect` is the one input to the dry-run decision (`ZFSRunner`): a read-only command always
/// runs, so a dry run plans against the real pool; a mutating command runs only when executing,
/// and is otherwise handed to the dry-run shell, which reports it.
struct ZFSCommand: Equatable, Sendable {
    enum Effect: Sendable {
        case readOnly
        case mutating
    }

    enum Form: Equatable, Sendable {
        /// A program and its arguments, spawned directly — no shell parses them, so a dataset name
        /// with a space or a `$` reaches `zfs` as written.
        case argv(executable: String, arguments: [String])
        /// A shell command line (`bash -c`), kept for the one genuine pipeline: the send stream.
        case shell(String)
    }

    let form: Form
    let effect: Effect

    /// The command as one line — what logs, observers, a dry run's output and a test mock see. An
    /// argv renders with each token quoted only when it needs quoting (`shellCommandLine`), so the
    /// line pastes back into a shell as the same argv.
    var commandLine: String {
        switch form {
        case .argv(let executable, let arguments): ([executable] + arguments).shellCommandLine
        case .shell(let line): line
        }
    }
}

/// The `zfs`/`zpool` commands the tool issues. Listings take no filter: the sender filters names in
/// Swift (`matching(_:)`), so a listing that fails fails, instead of `| grep … || true` reading an
/// error as "nothing matched" — and a receive-guard sees exactly the bare listing it whitelists.
enum ZFS {
    static func zfs(_ arguments: [String], _ effect: ZFSCommand.Effect) -> ZFSCommand {
        ZFSCommand(form: .argv(executable: "zfs", arguments: arguments), effect: effect)
    }

    static func destroy(subject: String) -> ZFSCommand {
        zfs(["destroy", subject], .mutating)
    }

    static func listDatasets() -> ZFSCommand {
        zfs(["list", "-o", "name", "-H"], .readOnly)
    }

    static func listSnapshots() -> ZFSCommand {
        zfs(["list", "-o", "name", "-H", "-t", "snapshot"], .readOnly)
    }

    /// The listing a receive-guard whitelists verbatim (`ReceiveGuardPolicy`): change it there too.
    static func listSnapshotRecords() -> ZFSCommand {
        zfs(["list", "-t", "snapshot", "-H", "-p", "-o", "guid,createtxg,name", "-s", "createtxg"], .readOnly)
    }

    static func listBookmarkRecords() -> ZFSCommand {
        zfs(["list", "-t", "bookmark", "-H", "-p", "-o", "guid,createtxg,name", "-s", "createtxg"], .readOnly)
    }

    static func bookmark(snapshot: String, bookmark: String) -> ZFSCommand {
        zfs(["bookmark", snapshot, bookmark], .mutating)
    }

    static func snapshot(dataset: String, date: Date, dateFormatter: DateFormatter, dateSeparator: String, recursive: Bool) -> ZFSCommand {
        var arguments = ["snapshot"]
        if recursive {
            arguments.append("-r")
        }
        arguments.append("\(dataset)\(dateSeparator)\(dateFormatter.string(from: date))")
        return zfs(arguments, .mutating)
    }

    /// `zfs recv -F <target>` — the receiving end of a send stream; a receive-guard accepts this
    /// shape for any target inside its pool.
    static func receive(target: String) -> ZFSCommand {
        zfs(["recv", "-F", target], .mutating)
    }

    /// Pool capacity as an integer percentage (0-100): one line, e.g. "42".
    static func poolCapacity(pool: String) -> ZFSCommand {
        ZFSCommand(form: .argv(executable: "zpool", arguments: ["list", "-Hp", "-o", "capacity", pool]), effect: .readOnly)
    }

    /// Used and available bytes for a dataset or pool: one tab-separated line, e.g. "1234\t5678".
    static func listUsedAvailable(dataset: String) -> ZFSCommand {
        zfs(["list", "-Hp", "-o", "used,available", dataset], .readOnly)
    }
}

/// Runs `ZFSCommand`s and owns the tool's ONE dry-run decision, made in `init`, where an operation
/// builds its runner from its config: a read-only command always goes to `shell`, so a dry run plans
/// against the real pool; a mutating command goes to `shell` when `execute` is true and otherwise
/// to `dryRunShell`, which reports the command and spawns nothing. No call site decides dry-run
/// for itself, and no command carries a dry-run flag.
struct ZFSRunner: Sendable {
    /// Runs every read-only command.
    let reads: ShellAtPath
    /// Runs every mutating command — or, on a dry run, only reports it.
    let mutations: ShellAtPath
    let stringEncoding: String.Encoding
    let lineSeparator: String

    init(
        shell: ShellAtPath,
        dryRunShell: ShellAtPath,
        execute: Bool,
        stringEncoding: String.Encoding,
        lineSeparator: String
    ) {
        reads = shell
        mutations = execute ? shell : dryRunShell
        self.stringEncoding = stringEncoding
        self.lineSeparator = lineSeparator
    }

    func run(_ command: ZFSCommand) async throws -> ShellProcessOutput {
        let shell = switch command.effect {
        case .readOnly: reads
        case .mutating: mutations
        }
        // Exit 0 is the one success `zfs`, `zpool` and `ssh` report. Nothing is written to a
        // command's stdin, and none is timed out: a send takes as long as its stream does.
        switch command.form {
        case .argv(let executable, let arguments):
            return try await shell.execute(
                executable: executable,
                arguments: arguments,
                statusesForResult: .exitZeroSucceedsSIGTERMCancels(),
                stream: nil,
                timeout: nil
            ).get()
        case .shell(let line):
            return try await shell.execute(
                line,
                statusesForResult: .exitZeroSucceedsSIGTERMCancels(),
                stream: nil,
                timeout: nil
            ).get()
        }
    }

    /// A read-only command's stdout as lines. A mutating command has no listing to read.
    func lines(_ command: ZFSCommand) async throws -> [String] {
        precondition(command.effect == .readOnly, "lines(_:) reads a listing; `\(command.commandLine)` mutates")
        return try await run(command)
            .decodeStringLines(encoding: stringEncoding, lineSeparator: lineSeparator)
            .stdoutTyped
    }
}

extension Array where Element == String {
    /// The names that contain `pattern` as a fixed substring — the sender-side filter that replaced
    /// `| grep <pattern> || true`. `nil` or an empty pattern keeps every name.
    func matching(_ pattern: String?) -> [String] {
        guard let pattern, !pattern.isEmpty else { return self }
        return filter { $0.contains(pattern) }
    }
}

extension ShellAtPath {
    /// Run a command LINE and return its stdout split into lines. `Builder` (a developer tool that
    /// never dry-runs) is its one caller; every ZFS listing goes through `ZFSRunner.lines(_:)`.
    func lines(
        _ command: ShellCommand,
        encoding: String.Encoding,
        lineSeparator: String
    ) async throws -> [String] {
        // Exit 0 is the one success; nothing is written to stdin; a build is not timed out.
        try await execute(
            command,
            statusesForResult: .exitZeroSucceedsSIGTERMCancels(),
            stream: nil,
            timeout: nil
        )
        .get()
        .decodeStringLines(encoding: encoding, lineSeparator: lineSeparator)
        .stdoutTyped
    }
}

extension TimeInterval {
    public static let secondsPerDay = TimeInterval(24 * 60 * 60)
}
