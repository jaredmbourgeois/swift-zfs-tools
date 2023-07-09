// ActionExecutor.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell

public enum Action: EquatableModel {
    case consolidate(configPath: String)
    case snapshot(configPath: String)
    case sync(configPath: String)
}

public struct ActionExecutor: Sendable {
    private let calendar: Calendar
    private let dateFormatter: DateFormatter
    private let fileManager: @Sendable () -> FileManager
    private let jsonDecoder: JSONDecoder
    private let shell: ShellAtPath

    public init(
        calendar: Calendar,
        dateFormatter: DateFormatter,
        fileManager: @escaping @Sendable () -> FileManager,
        jsonDecoder: JSONDecoder,
        shell: ShellAtPath
    ) {
        self.calendar = calendar
        self.dateFormatter = dateFormatter
        self.fileManager = fileManager
        self.jsonDecoder = jsonDecoder
        self.shell = shell
    }

    public func execute(_ actions: [Action]) async throws {
        let date: @Sendable () -> Date = { .now }
        let fileManager = fileManager()
        for action in actions {
            switch action {
            case .consolidate(let configPath):
                try await Consolidator(
                    calendar: calendar,
                    config: decodeFromJSONAtPath(
                        configPath,
                        fileManager: fileManager,
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
                        fileManager: fileManager,
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
                        fileManager: fileManager,
                        jsonDecoder: jsonDecoder
                    ),
                    dateFormatter: dateFormatter,
                    shell: shell
                ).sync()
            }
        }
    }
}
