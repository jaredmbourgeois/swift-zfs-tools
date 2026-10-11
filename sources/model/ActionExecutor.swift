// ActionExecutor.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell

/// One step in an actions file: which operation to run and the path to its saved JSON config.
/// `Codable`, so a `[Action]` array round-trips to the `execute-actions` JSON.
public enum Action: EquatableModel {
    case consolidate(configPath: String)
    case snapshot(configPath: String)
    case sync(configPath: String)
}

/// Runs a list of `Action`s in order, loading each operation's `Config` from its `configPath` and
/// dispatching to `Snapshotter` / `Consolidator` / `Syncer`. The basis of the `execute-actions`
/// command — one cron entry that chains snapshot → consolidate → sync.
public struct ActionExecutor: Sendable {
    private let calendar: Calendar
    private let date: @Sendable () -> Date
    private let dateFormatter: DateFormatter
    private let diagnostics: @Sendable (_ line: String) -> Void
    private let fileSystem: FileSystem
    private let jsonDecoder: JSONDecoder
    private let shell: ShellAtPath
    private let dryRunShell: ShellAtPath

    /// Everything the three operations take, handed down from the composition root. `date` is a
    /// clock, not one instant: a chain can run for hours, and each action reads the time it starts.
    public init(
        calendar: Calendar,
        date: @escaping @Sendable () -> Date,
        dateFormatter: DateFormatter,
        diagnostics: @escaping @Sendable (_ line: String) -> Void,
        fileSystem: FileSystem,
        jsonDecoder: JSONDecoder,
        shell: ShellAtPath,
        dryRunShell: ShellAtPath
    ) {
        self.calendar = calendar
        self.date = date
        self.dateFormatter = dateFormatter
        self.diagnostics = diagnostics
        self.fileSystem = fileSystem
        self.jsonDecoder = jsonDecoder
        self.shell = shell
        self.dryRunShell = dryRunShell
    }

    /// Run each action in sequence; a failure stops the chain.
    public func execute(_ actions: [Action]) async throws {
        for action in actions {
            switch action {
            case .consolidate(let configPath):
                try await Consolidator(
                    calendar: calendar,
                    config: decodeFromJSONAtPath(
                        configPath,
                        fileSystem: fileSystem,
                        jsonDecoder: jsonDecoder
                    ),
                    date: date,
                    dateFormatter: dateFormatter,
                    diagnostics: diagnostics,
                    shell: shell,
                    dryRunShell: dryRunShell
                ).consolidate()

            case .snapshot(let configPath):
                try await Snapshotter(
                    config: try decodeFromJSONAtPath(
                        configPath,
                        fileSystem: fileSystem,
                        jsonDecoder: jsonDecoder
                    ),
                    date: date,
                    dateFormatter: dateFormatter,
                    diagnostics: diagnostics,
                    shell: shell,
                    dryRunShell: dryRunShell
                ).snapshot()

            case .sync(let configPath):
                try await Syncer(
                    config: try decodeFromJSONAtPath(
                        configPath,
                        fileSystem: fileSystem,
                        jsonDecoder: jsonDecoder
                    ),
                    dateFormatter: dateFormatter,
                    shell: shell,
                    dryRunShell: dryRunShell
                ).sync()
            }
        }
    }
}
