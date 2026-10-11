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
        let root = try CommandRoot.readingThisProcess()
        let dateFormatter = root.dateFormatter(arguments.common)
        let shells = root.shells(arguments.common)
        let consolidator = Consolidator(
            calendar: root.calendar(),
            config: try Consolidator.Config(
                arguments: arguments,
                dateFormatter: dateFormatter,
                fileSystem: root.fileSystem,
                jsonDecoder: .init()
            ),
            date: root.date,
            dateFormatter: dateFormatter,
            diagnostics: root.diagnostics,
            shell: shells.shell,
            dryRunShell: shells.dryRunShell
        )
        try await consolidator.consolidate()
    }
}

struct ConsolidateConfigure: ParsableCommand {
    @OptionGroup()
    var arguments: Arguments.ConsolidateConfigure

    func run() throws {
        let root = try CommandRoot.readingThisProcess()
        try encode(
            try Consolidator.Config(
                arguments: arguments.consolidate,
                dateFormatter: root.dateFormatter(arguments.consolidate.common),
                fileSystem: root.fileSystem,
                jsonDecoder: .init()
            ),
            toJSONAtPath: arguments.outputPath,
            fileSystem: root.fileSystem,
            jsonEncoder: .init()
        )
    }
}

struct ConsolidateConfigured: AsyncParsableCommand {
    @OptionGroup()
    var arguments: Arguments.ConsolidateConfigured

    func run() async throws {
        let root = try CommandRoot.readingThisProcess()
        let config: Consolidator.Config = try decodeFromJSONAtPath(
            arguments.configPath,
            fileSystem: root.fileSystem,
            jsonDecoder: .init()
        )
        let shells = root.shells(arguments.common)
        let consolidator = Consolidator(
            calendar: root.calendar(),
            config: config,
            date: root.date,
            dateFormatter: root.dateFormatter(arguments.common),
            diagnostics: root.diagnostics,
            shell: shells.shell,
            dryRunShell: shells.dryRunShell
        )
        try await consolidator.consolidate()
    }
}
