// Sync.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import ArgumentParser
import Foundation
import Shell
import ZFSToolsModel

struct Sync: AsyncParsableCommand {
    @OptionGroup()
    var arguments: Arguments.Sync

    func run() async throws {
        let dateFormatter = makeDateFormatter(arguments.common.dateFormat ?? Defaults.dateFormat)
        let syncer = Syncer(
            config: .init(arguments: arguments),
            dateFormatter: dateFormatter,
            shell: Shell(arguments: arguments.common)
        )
        try await syncer.sync()
    }
}

struct SyncConfigure: ParsableCommand {
    @OptionGroup()
    var arguments: Arguments.SyncConfigure

    func run() throws {
        try encode(
        Syncer.Config(arguments: arguments.sync),
            toJSONAtPath: arguments.outputPath,
            fileManager: .default,
            jsonEncoder: .init()
        )
    }
}

struct SyncConfigured: AsyncParsableCommand {
    @OptionGroup()
    var arguments: Arguments.SyncConfigured

    func run() async throws {
        let config: Syncer.Config = try decodeFromJSONAtPath(
            arguments.configPath,
            fileManager: .default,
            jsonDecoder: .init()
        )
        let dateFormatter = makeDateFormatter(arguments.common.dateFormat ?? Defaults.dateFormat)
        let syncer = Syncer(
            config: config,
            dateFormatter: dateFormatter,
            shell: Shell(arguments: arguments.common)
        )
        try await syncer.sync()
    }
}
