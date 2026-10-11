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
        let root = try CommandRoot.readingThisProcess()
        let shells = root.shells(arguments.common)
        let syncer = Syncer(
            config: .init(arguments: arguments),
            dateFormatter: root.dateFormatter(arguments.common),
            shell: shells.shell,
            dryRunShell: shells.dryRunShell
        )
        try await syncer.sync()
    }
}

struct SyncConfigure: ParsableCommand {
    @OptionGroup()
    var arguments: Arguments.SyncConfigure

    func run() throws {
        let root = try CommandRoot.readingThisProcess()
        try encode(
            Syncer.Config(arguments: arguments.sync),
            toJSONAtPath: arguments.outputPath,
            fileSystem: root.fileSystem,
            jsonEncoder: .init()
        )
    }
}

struct SyncConfigured: AsyncParsableCommand {
    @OptionGroup()
    var arguments: Arguments.SyncConfigured

    func run() async throws {
        let root = try CommandRoot.readingThisProcess()
        let config: Syncer.Config = try decodeFromJSONAtPath(
            arguments.configPath,
            fileSystem: root.fileSystem,
            jsonDecoder: .init()
        )
        let shells = root.shells(arguments.common)
        let syncer = Syncer(
            config: config,
            dateFormatter: root.dateFormatter(arguments.common),
            shell: shells.shell,
            dryRunShell: shells.dryRunShell
        )
        try await syncer.sync()
    }
}
