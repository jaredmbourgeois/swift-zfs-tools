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
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = .current
        dateFormatter.dateFormat = arguments.common.dateFormat ?? Defaults.dateFormat
        let snapshotter = Snapshotter(
            config: .init(arguments: arguments),
            date: { .now },
            dateFormatter: dateFormatter,
            shell: Shell(arguments: arguments.common)
        )
        try await snapshotter.snapshot()
    }
}

struct SnapshotConfigure: ParsableCommand {
    @OptionGroup()
    var arguments: Arguments.SnapshotConfigure

    func run() throws {
        try encode(
            Snapshotter.Config(arguments: arguments.snapshot),
            toJSONAtPath: arguments.outputPath,
            fileManager: .default,
            jsonEncoder: .init()
        )
    }
}

struct SnapshotConfigured: AsyncParsableCommand {
    @OptionGroup()
    var arguments: Arguments.SnapshotConfigured

    func run() async throws {
        let config: Snapshotter.Config = try decodeFromJSONAtPath(
            arguments.configPath,
            fileManager: .default,
            jsonDecoder: .init()
        )
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = .current
        dateFormatter.dateFormat = arguments.common.dateFormat ?? Defaults.dateFormat
        let snapshotter = Snapshotter(
            config: config,
            date: { .now },
            dateFormatter: dateFormatter,
            shell: Shell(arguments: arguments.common)
        )
        try await snapshotter.snapshot()
    }
}
