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

public func makeCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = .current
    calendar.timeZone = .current
    return calendar
}

public func makeDateFormatter(_ dateFormat: String) -> DateFormatter {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = dateFormat
    dateFormatter.locale = .init(identifier: "en_US_POSIX")
    dateFormatter.timeZone = .current
    return dateFormatter
}

extension ShellAtPath {
    public init(
        arguments: Arguments.Common
    ) {
        self = .loggingToStdout(
            shellPath: arguments.shellPath ?? Defaults.shellPath,
            lineSeparator: arguments.lineSeparator ?? Defaults.lineSeparator,
            stringEncoding: .init(rawValue: arguments.stringEncodingRawValue ?? Defaults.stringEncoding.rawValue)
        )
    }

    /// A `ShellAtPath` whose observer prints each command, its exit status, and decoded
    /// stdout/stderr (prefixed with distinct `<tool> <event>:` labels). Shared by the `zfs-tools` CLI and the `zfs-tools-build`
    /// builder. Take plain values — never read `@Option`s off a hand-constructed `ParsableArguments`,
    /// which traps.
    public static func loggingToStdout(
        toolName: String = "zfs-tools",
        shellPath: String = Defaults.shellPath,
        lineSeparator: String = Defaults.lineSeparator,
        stringEncoding: String.Encoding = Defaults.stringEncoding
    ) -> ShellAtPath {
        let formatter = ShellLogFormatter(
            toolName: toolName,
            lineSeparator: lineSeparator,
            stringEncoding: stringEncoding
        )
        return .atPath(
            shellPath,
            shellObserver: .init(
                onResult: { command, result in
                    print(formatter.command(command))
                    print(formatter.result(result))
                    if let stdout = formatter.stdout(result.processOutput.stdout) {
                        print(stdout)
                    }
                    if let stderr = formatter.stderr(result.processOutput.stderr) {
                        print(stderr)
                    }
                }
            ),
            stringEncoding: stringEncoding
        )
    }
}

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
/// runs, so a dry run plans against the real pool; a mutating command runs only when executing.
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

    static func snapshot(dataset: String, date: Date, dateFormatter: DateFormatter, dateSeparator: String, recursive: Bool = false) -> ZFSCommand {
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

/// Runs `ZFSCommand`s through the shell and owns the tool's ONE dry-run decision: a read-only
/// command always runs, a mutating command runs only when `execute` is true and is otherwise
/// reported by the shell (`ShellResult.dryRun`, nothing spawned). Every operation builds one from
/// its config, so no call site decides dry-run for itself.
struct ZFSRunner: Sendable {
    let shell: ShellAtPath
    let execute: Bool
    let stringEncoding: String.Encoding
    let lineSeparator: String

    func run(_ command: ZFSCommand) async throws -> ShellProcessOutput {
        let dryRun = command.effect == .mutating && !execute
        switch command.form {
        case .argv(let executable, let arguments):
            return try await shell.execute(executable: executable, arguments: arguments, dryRun: dryRun).get()
        case .shell(let line):
            return try await shell.execute(line, dryRun: dryRun).get()
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
        dryRun: Bool,
        encoding: String.Encoding,
        lineSeparator: String
    ) async throws -> [String] {
        try await execute(command, dryRun: dryRun)
            .get()
            .decodeStringLines(encoding: encoding, lineSeparator: lineSeparator)
            .stdoutTyped
    }
}

extension TimeInterval {
    public static let secondsPerDay = TimeInterval(24 * 60 * 60)
}
