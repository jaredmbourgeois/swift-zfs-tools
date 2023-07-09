// Consolidate.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import ArgumentParser
import Foundation
import Shell
import ZFSToolsModel

struct Consolidate: AsyncParsableCommand {
    @OptionGroup()
    var arguments: Arguments.Consolidate

    func run() async throws {
        let calendar = makeCalendar()
        let dateFormatter = makeDateFormatter(arguments.common.dateFormat ?? Defaults.dateFormat)
        let date: @Sendable () -> Date = { .now }
        let consolidator = Consolidator(
            calendar: calendar,
            config: try Consolidator.Config(
                arguments: arguments,
                dateFormatter: dateFormatter,
                fileManager: .default,
                jsonDecoder: .init()
            ),
            date: date,
            dateFormatter: dateFormatter,
            shell: Shell(arguments: arguments.common)
        )
        try await consolidator.consolidate()
    }
}

struct ConsolidateConfigure: ParsableCommand {
    @OptionGroup()
    var arguments: Arguments.ConsolidateConfigure

    func run() throws {
        let fileManager = FileManager.default
        let dateFormatter = makeDateFormatter(arguments.consolidate.common.dateFormat ?? Defaults.dateFormat)
        try encode(
            try Consolidator.Config(
                arguments: arguments.consolidate,
                dateFormatter: dateFormatter,
                fileManager: fileManager,
                jsonDecoder: .init()
            ),
            toJSONAtPath: arguments.outputPath,
            fileManager: fileManager,
            jsonEncoder: .init()
        )
    }
}

struct ConsolidateConfigured: AsyncParsableCommand {
    @OptionGroup()
    var arguments: Arguments.ConsolidateConfigured

    func run() async throws {
        let fileManager = FileManager.default
        let jsonDecoder = JSONDecoder()
        let config: Consolidator.Config = try decodeFromJSONAtPath(
            arguments.configPath,
            fileManager: fileManager,
            jsonDecoder: jsonDecoder
        )
        let calendar = makeCalendar()
        let dateFormatter = makeDateFormatter(arguments.common.dateFormat ?? Defaults.dateFormat)
        let date: @Sendable () -> Date = { .now }
        let consolidator = Consolidator(
            calendar: calendar,
            config: config,
            date: date,
            dateFormatter: dateFormatter,
            shell: Shell(arguments: arguments.common)
        )
        try await consolidator.consolidate()
    }
}
