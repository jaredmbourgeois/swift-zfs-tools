// Snapshot.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import ArgumentParser
import Foundation
import Shell
import ZFSToolsModel

struct Snapshot: AsyncParsableCommand {
    @OptionGroup()
    var arguments: Arguments.Snapshot

    func run() async throws {
        let root = try CommandRoot.readingThisProcess()
        let shells = root.shells(arguments.common)
        let snapshotter = Snapshotter(
            config: .init(arguments: arguments),
            date: root.date,
            dateFormatter: root.dateFormatter(arguments.common),
            diagnostics: root.diagnostics,
            shell: shells.shell,
            dryRunShell: shells.dryRunShell
        )
        try await snapshotter.snapshot()
    }
}

struct SnapshotConfigure: ParsableCommand {
    @OptionGroup()
    var arguments: Arguments.SnapshotConfigure

    func run() throws {
        let root = try CommandRoot.readingThisProcess()
        try encode(
            Snapshotter.Config(arguments: arguments.snapshot),
            toJSONAtPath: arguments.outputPath,
            fileSystem: root.fileSystem,
            jsonEncoder: .init()
        )
    }
}

struct SnapshotConfigured: AsyncParsableCommand {
    @OptionGroup()
    var arguments: Arguments.SnapshotConfigured

    func run() async throws {
        let root = try CommandRoot.readingThisProcess()
        let config: Snapshotter.Config = try decodeFromJSONAtPath(
            arguments.configPath,
            fileSystem: root.fileSystem,
            jsonDecoder: .init()
        )
        let shells = root.shells(arguments.common)
        let snapshotter = Snapshotter(
            config: config,
            date: root.date,
            dateFormatter: root.dateFormatter(arguments.common),
            diagnostics: root.diagnostics,
            shell: shells.shell,
            dryRunShell: shells.dryRunShell
        )
        try await snapshotter.snapshot()
    }
}
