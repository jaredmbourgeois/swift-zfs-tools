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
    private let dateFormatter: DateFormatter
    private let fileSystem: FileSystem
    private let jsonDecoder: JSONDecoder
    private let shell: ShellAtPath

    public init(
        calendar: Calendar,
        dateFormatter: DateFormatter,
        fileSystem: FileSystem,
        jsonDecoder: JSONDecoder,
        shell: ShellAtPath
    ) {
        self.calendar = calendar
        self.dateFormatter = dateFormatter
        self.fileSystem = fileSystem
        self.jsonDecoder = jsonDecoder
        self.shell = shell
    }

    /// Run each action in sequence; a failure stops the chain.
    public func execute(_ actions: [Action]) async throws {
        let date: @Sendable () -> Date = { .now }
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
                    shell: shell
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
                    shell: shell
                ).snapshot()

            case .sync(let configPath):
                try await Syncer(
                    config: try decodeFromJSONAtPath(
                        configPath,
                        fileSystem: fileSystem,
                        jsonDecoder: jsonDecoder
                    ),
                    dateFormatter: dateFormatter,
                    shell: shell
                ).sync()
            }
        }
    }
}
