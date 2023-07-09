// ExecuteActions.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import ArgumentParser
import Foundation
import Shell
import ZFSToolsModel

struct ExecuteActions: AsyncParsableCommand {
    @OptionGroup()
    var arguments: Arguments.ExecuteActions

    func run() async throws {
        let jsonDecoder = JSONDecoder()
        let actions: [Action] = try decodeFromJSONAtPath(
            arguments.actionsPath,
            fileManager: .default,
            jsonDecoder: jsonDecoder
        )
        let calendar = makeCalendar()
        let dateFormatter = makeDateFormatter(arguments.common.dateFormat ?? Defaults.dateFormat)
        let executor = ActionExecutor(
            calendar: calendar,
            dateFormatter: dateFormatter,
            fileManager: { .default },
            jsonDecoder: jsonDecoder,
            shell: Shell(arguments: arguments.common)
        )
        try await executor.execute(actions)
    }
}

struct ExecuteActionsConfigure: ParsableCommand {
    @OptionGroup()
    var arguments: Arguments.ExecuteActionsConfigure

    func run() throws {
        try encode(
            [
                Action.snapshot(configPath: "/path/to/snapshot/config.json"),
                Action.consolidate(configPath: "/path/to/consolidate/config.json"),
                Action.sync(configPath: "/path/to/sync/config.json"),
            ],
            toJSONAtPath: arguments.outputPath,
            fileManager: .default,
            jsonEncoder: .init()
        )
    }
}
