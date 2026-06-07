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
        let lineSeparator = arguments.lineSeparator ?? Defaults.lineSeparator
        let stringEncoding = String.Encoding(rawValue: arguments.stringEncodingRawValue ?? Defaults.stringEncoding.rawValue)
        @Sendable func prefix(_ string: String) -> String {
            "zfs-tools command: \(string)"
        }
        self = .atPath(
            arguments.shellPath ?? Defaults.shellPath,
            shellObserver: .init(
                onResult: { command, result in
                    print(prefix(command))
                    if let error = result.error {
                        print(prefix("error (\(result.termination.status)) \(error.userInfo[NSLocalizedDescriptionKey] ?? error.localizedDescription)"))
                    } else {
                        print(prefix("success (\(result.termination.status))"))
                    }
                    if let stdoutString = String(data: result.processOutput.stdout, encoding: stringEncoding) {
                        if !stdoutString.isEmpty {
                            print(prefix("stdout\(lineSeparator)\(stdoutString)"))
                        }
                    } else {
                        print(prefix("stdout (\(result.processOutput.stdout.count) bytes) could not be decoded as \(String(reflecting: stringEncoding)) (\(stringEncoding.rawValue))"))
                    }
                    if let stderrString = String(data: result.processOutput.stderr, encoding: stringEncoding) {
                        if !stderrString.isEmpty {
                            print(prefix("stderr\(lineSeparator)\(stderrString)"))
                        }
                    } else {
                        print(prefix("stderr (\(result.processOutput.stderr.count) bytes) could not be decoded as \(String(reflecting: stringEncoding)) (\(stringEncoding.rawValue))"))
                    }
                }
            ),
            stringEncoding: stringEncoding
        )
    }
}

struct SnapshotAndDate: Equatable, Sendable {
    let snapshot: String
    let date: Date
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
