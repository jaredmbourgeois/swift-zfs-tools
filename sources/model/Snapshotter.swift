// Snapshotter.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell

public struct Snapshotter: Sendable {
    private let config: Config
    private let dateFormatter: DateFormatter
    private let date: @Sendable () -> Date
    private let shell: ShellAtPath

    public init(
        config: Config,
        date: @Sendable @escaping () -> Date,
        dateFormatter: DateFormatter,
        shell: ShellAtPath
    ) {
        self.config = config
        self.date = date
        self.dateFormatter = dateFormatter
        self.shell = shell
    }

    public func snapshot() async throws {
        let datasets = try await shell.execute(
            ZFS.listDatasets(grepping: config.datasetGrep),
            dryRun: !config.execute
        )
        .get()
        .decodeStringLines(
            encoding: .init(rawValue: config.stringEncodingRawValue),
            lineSeparator: config.lineSeparator
        )
        .stdoutTyped
        try await withThrowingDiscardingTaskGroup { taskGroup in
            for dataset in datasets {
                taskGroup.addTask {
                    _ = try await shell.execute(
                        {
                            var command = "zfs snapshot"
                            if config.recursive {
                              command += " -r"
                            }
                            command += " \(dataset)\(config.dateSeparator)\(dateFormatter.string(from: date()))"
                            return command
                        }(),
                        dryRun: !config.execute
                    )
                    .get()
                    return
                }
            }
        }
    }
}

extension Snapshotter {
    public struct Config: EquatableModel {
        public let datasetGrep: String?
        public let dateSeparator: String
        public let execute: Bool
        public let lineSeparator: String
        public let recursive: Bool
        public let stringEncodingRawValue: String.Encoding.RawValue

        public init(
            datasetGrep: String?,
            dateSeparator: String,
            execute: Bool,
            lineSeparator: String,
            recursive: Bool,
            stringEncodingRawValue: String.Encoding.RawValue
        ) {
            self.datasetGrep = datasetGrep
            self.dateSeparator = dateSeparator
            self.execute = execute
            self.lineSeparator = lineSeparator
            self.recursive = recursive
            self.stringEncodingRawValue = stringEncodingRawValue
        }

        public init(
            arguments: Arguments.Snapshot
        ) {
            datasetGrep = arguments.datasetGrep
            dateSeparator = arguments.common.dateSeparator ?? Defaults.dateSeparator
            execute = arguments.common.execute ?? Defaults.execute
            lineSeparator = arguments.common.lineSeparator ?? Defaults.lineSeparator
            recursive = arguments.recursive ?? Defaults.recursive
            stringEncodingRawValue = arguments.common.stringEncodingRawValue ?? Defaults.stringEncoding.rawValue
        }
    }
}
