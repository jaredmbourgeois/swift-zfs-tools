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
        if config.maxPoolUtilizationPercent != nil || config.minFreeBytes != nil,
           let pool = PoolUtilization.poolName(from: config.datasetGrep) {
            let utilization = try await PoolUtilization.query(
                pool: pool,
                shell: shell,
                dryRun: !config.execute,
                stringEncoding: .init(rawValue: config.stringEncodingRawValue),
                lineSeparator: config.lineSeparator
            )
            if utilization.exceedsThreshold(
                maxCapacityPercent: config.maxPoolUtilizationPercent,
                minFreeBytes: config.minFreeBytes
            ) {
                print("zfs-tools snapshot: WARNING — pool \(pool) utilization exceeds threshold (capacity: \(utilization.capacityPercent)%, available: \(utilization.availableBytes) bytes). Skipping snapshot creation.")
                return
            }
        }
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
        // Per-dataset `zfs snapshot` calls in parallel. Each is independent at the
        // ZFS layer — distinct datasets share the pool's TXG batch but the kernel
        // serializes metadata commits transparently, so parallelism is safe and
        // saves wall time when N is large. Requires swift-shell ≥1.4.1 — pre-1.4.1
        // had a pipe-drain race that lost stdout (empty-output on macOS / hard
        // libdispatch segfault on Swift 6.3.1 / Linux) under parallel use.
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
        public let maxPoolUtilizationPercent: Float?
        public let minFreeBytes: Int64?
        public let recursive: Bool
        public let stringEncodingRawValue: String.Encoding.RawValue

        public init(
            datasetGrep: String?,
            dateSeparator: String,
            execute: Bool,
            lineSeparator: String,
            maxPoolUtilizationPercent: Float? = nil,
            minFreeBytes: Int64? = nil,
            recursive: Bool,
            stringEncodingRawValue: String.Encoding.RawValue
        ) {
            self.datasetGrep = datasetGrep
            self.dateSeparator = dateSeparator
            self.execute = execute
            self.lineSeparator = lineSeparator
            self.maxPoolUtilizationPercent = maxPoolUtilizationPercent
            self.minFreeBytes = minFreeBytes
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
            maxPoolUtilizationPercent = arguments.maxPoolUtilization
            minFreeBytes = arguments.minFreeBytes
            recursive = arguments.recursive ?? Defaults.recursive
            stringEncodingRawValue = arguments.common.stringEncodingRawValue ?? Defaults.stringEncoding.rawValue
        }

        enum CodingKeys: String, CodingKey {
            case datasetGrep, dateSeparator, execute, lineSeparator
            case maxPoolUtilizationPercent, minFreeBytes
            case recursive, stringEncodingRawValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            datasetGrep = try container.decodeIfPresent(String.self, forKey: .datasetGrep)
            dateSeparator = try container.decode(String.self, forKey: .dateSeparator)
            execute = try container.decode(Bool.self, forKey: .execute)
            lineSeparator = try container.decode(String.self, forKey: .lineSeparator)
            maxPoolUtilizationPercent = try container.decodeIfPresent(Float.self, forKey: .maxPoolUtilizationPercent)
            minFreeBytes = try container.decodeIfPresent(Int64.self, forKey: .minFreeBytes)
            recursive = try container.decode(Bool.self, forKey: .recursive)
            stringEncodingRawValue = try container.decode(String.Encoding.RawValue.self, forKey: .stringEncodingRawValue)
        }
    }
}
