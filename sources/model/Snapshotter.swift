// Snapshotter.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell

/// Creates timestamped ZFS snapshots for every dataset matching `config.datasetGrep`, one task per
/// dataset in parallel. Optionally guarded by a pool-utilization threshold. Honors dry-run via
/// `config.execute`.
public struct Snapshotter: Sendable {
    private let config: Config
    private let dateFormatter: DateFormatter
    private let date: @Sendable () -> Date
    private let shell: ShellAtPath

    /// `date`/`dateFormatter` build each snapshot's timestamp suffix; `shell` runs the commands
    /// (inject a mock to test).
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

    /// Snapshot every matching dataset (`zfs snapshot [-r] 'dataset@<timestamp>'`). If a pool
    /// threshold is set and exceeded, skips creation and returns without snapshotting.
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
        let datasets = try await shell.lines(
            ZFS.listDatasets(grepping: config.datasetGrep),
            dryRun: !config.execute,
            encoding: .init(rawValue: config.stringEncodingRawValue),
            lineSeparator: config.lineSeparator
        )
        // Per-dataset `zfs snapshot` calls in parallel. Each is independent at the
        // ZFS layer — distinct datasets share the pool's TXG batch but the kernel
        // serializes metadata commits transparently, so parallelism is safe and
        // saves wall time when N is large. Safe under swift-shell 2.0.0 — the
        // pre-1.4.1 pipe-drain race that lost stdout (empty-output on macOS / hard
        // libdispatch segfault on Swift 6.3.1 / Linux) under parallel use was fixed
        // in 1.4.1; 2.0.0 adds Linux support via dedicated reader threads.
        try await withThrowingDiscardingTaskGroup { taskGroup in
            for dataset in datasets {
                taskGroup.addTask {
                    _ = try await shell.execute(
                        ZFS.snapshot(
                            dataset: dataset,
                            date: date(),
                            dateFormatter: dateFormatter,
                            dateSeparator: config.dateSeparator,
                            recursive: config.recursive
                        ),
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
    /// A snapshot run as a `Codable` value — the `snapshot-configure` / `snapshot-configured` JSON
    /// schema. Build it from CLI `Arguments.Snapshot` or decode it from a saved config file.
    public struct Config: EquatableModel {
        /// Only snapshot datasets whose `zfs list` name matches this `grep` pattern; `nil` = all.
        public let datasetGrep: String?
        public let dateSeparator: String
        /// When `false` (the default), commands are printed but not run.
        public let execute: Bool
        public let lineSeparator: String
        /// Skip snapshotting if pool capacity exceeds this percent (0–100); `nil` disables the guard.
        public let maxPoolUtilizationPercent: Float?
        /// Skip snapshotting if pool free space is below this many bytes; `nil` disables the guard.
        public let minFreeBytes: Int64?
        /// Pass `-r` to snapshot child datasets recursively.
        public let recursive: Bool
        /// `String.Encoding.rawValue` for decoding command output; `4` is UTF-8.
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
