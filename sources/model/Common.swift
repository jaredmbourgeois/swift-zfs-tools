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

extension String {
    /// POSIX-safe single-quoting for shell arguments: wrap in single quotes and escape any
    /// embedded single quote as the standard `'\''` (close-quote, literal quote, reopen-quote).
    /// Keeps dataset names with spaces (legal in ZFS), grep patterns, and ssh args from
    /// word-splitting, glob-expanding, or injecting when interpolated into a shell command.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum ZFS {
    static func destroy(subject: String) -> String {
        "zfs destroy \(subject.shellQuoted)"
    }

    private static func list() -> String {
        "zfs list -o name -H"
    }

    static func listDatasets(grepping: String? = nil) -> String {
        var command = Self.list()
        if let grepping {
            // `|| true` so an empty grep result (no datasets matching) is reported as zero
            // datasets, not a failure. grep exits 1 on no-match which the shell wrapper
            // would otherwise propagate as a hard error — meaningful for first-time runs.
            command += " | grep \(grepping.shellQuoted) || true"
        }
        return command
    }

    static func listSnapshots(grepping: String? = nil) -> String {
        var command = "\(Self.list()) -t snapshot"
        if let grepping {
            // See note on listDatasets — same rationale (e.g. fresh remote with no snapshots yet).
            command += " | grep \(grepping.shellQuoted) || true"
        }
        return command
    }

    static func listSnapshotRecords(grepping: String? = nil) -> String {
        var command = "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg"
        if let grepping {
            // See note on listDatasets — same rationale (e.g. fresh remote with no snapshots yet).
            command += " | grep \(grepping.shellQuoted) || true"
        }
        return command
    }

    static func listBookmarkRecords(grepping: String? = nil) -> String {
        var command = "zfs list -t bookmark -H -p -o guid,createtxg,name -s createtxg"
        if let grepping {
            command += " | grep \(grepping.shellQuoted) || true"
        }
        return command
    }

    static func bookmark(snapshot: String, bookmark: String) -> String {
        "zfs bookmark \(snapshot.shellQuoted) \(bookmark.shellQuoted)"
    }

    static func snapshot(dataset: String, date: Date, dateFormatter: DateFormatter, dateSeparator: String, recursive: Bool = false) -> String {
        var command = "zfs snapshot"
        if recursive {
          command += " -r"
        }
        let snapshotName = "\(dataset)\(dateSeparator)\(dateFormatter.string(from: date))"
        command += " \(snapshotName.shellQuoted)"
        return command
    }

    /// Returns pool capacity as integer percentage (0-100).
    /// Output: single integer, e.g. "42"
    static func poolCapacity(pool: String) -> String {
        "zpool list -Hp -o capacity \(pool.shellQuoted)"
    }

    /// Returns used and available bytes for a dataset/pool.
    /// Output: tab-separated "used\tavailable", e.g. "1234567890\t9876543210"
    static func listUsedAvailable(dataset: String) -> String {
        "zfs list -Hp -o used,available \(dataset.shellQuoted)"
    }
}

extension ShellAtPath {
    /// Run `command` and return its stdout split into lines — the shared
    /// `execute → get → decodeStringLines → stdoutTyped` chain used across every ZFS listing
    /// and query call site.
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
