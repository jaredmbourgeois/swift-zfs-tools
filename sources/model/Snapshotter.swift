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

    /// Snapshot every matching dataset (`zfs snapshot [-r] dataset@<timestamp>`). If a pool
    /// threshold is set and exceeded, skips creation and returns without snapshotting. The pool is
    /// read on a dry run too, so the report says what a real run would do; only the snapshots are
    /// held back.
    public func snapshot() async throws {
        let runner = ZFSRunner(
            shell: shell,
            execute: config.execute,
            stringEncoding: .init(rawValue: config.stringEncodingRawValue),
            lineSeparator: config.lineSeparator
        )
        if config.maxPoolUtilizationPercent != nil || config.minFreeBytes != nil,
           let pool = PoolUtilization.poolName(from: config.datasetGrep) {
            let utilization = try await PoolUtilization.query(pool: pool, runner: runner)
            if utilization.exceedsThreshold(
                maxCapacityPercent: config.maxPoolUtilizationPercent,
                minFreeBytes: config.minFreeBytes
            ) {
                let verdict = config.execute ? "Skipping snapshot creation." : "dry-run — would skip snapshot creation."
                print("zfs-tools snapshot: WARNING — pool \(pool) utilization exceeds threshold (capacity: \(utilization.capacityPercent)%, available: \(utilization.availableBytes) bytes). \(verdict)")
                return
            }
        }
        // One timestamp per run: every dataset's snapshot carries the same name suffix, so a run is
        // one point in time however long its snapshots take.
        let snapshotDate = date()
        let datasetsListed = try await runner.lines(ZFS.listDatasets())
            .matching(config.datasetGrep)
            .filter { dataset in
                !config.excludedDatasetGreps.contains { excluded in
                    !excluded.isEmpty && dataset.contains(excluded)
                }
            }
        let datasets = Self.snapshotDatasets(from: datasetsListed, recursive: config.recursive, hasExclusions: !config.excludedDatasetGreps.isEmpty)
        // Per-dataset `zfs snapshot` calls in parallel. Each is independent at the ZFS layer —
        // distinct datasets share the pool's TXG batch but the kernel serializes metadata commits
        // transparently, so parallelism is safe and saves wall time when N is large.
        try await withThrowingDiscardingTaskGroup { taskGroup in
            for dataset in datasets {
                taskGroup.addTask {
                    _ = try await runner.run(
                        ZFS.snapshot(
                            dataset: dataset,
                            date: snapshotDate,
                            dateFormatter: dateFormatter,
                            dateSeparator: config.dateSeparator,
                            recursive: config.recursive && config.excludedDatasetGreps.isEmpty
                        )
                    )
                }
            }
        }
    }

    private static func snapshotDatasets(from datasets: [String], recursive: Bool, hasExclusions: Bool) -> [String] {
        guard recursive, !hasExclusions else { return datasets }
        return datasets.filter { dataset in
            !datasets.contains { possibleParent in
                possibleParent != dataset && dataset.hasPrefix(possibleParent + "/")
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
        /// Skip matching datasets after the broad listing. Used to avoid local snapshots on received
        /// trees that are only being forwarded onward.
        public let excludedDatasetGreps: [String]
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
            excludedDatasetGreps: [String] = [],
            lineSeparator: String,
            maxPoolUtilizationPercent: Float? = nil,
            minFreeBytes: Int64? = nil,
            recursive: Bool,
            stringEncodingRawValue: String.Encoding.RawValue
        ) {
            self.datasetGrep = datasetGrep
            self.dateSeparator = dateSeparator
            self.execute = execute
            self.excludedDatasetGreps = excludedDatasetGreps
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
            excludedDatasetGreps = arguments.excludedDatasetGreps
            lineSeparator = arguments.common.lineSeparator ?? Defaults.lineSeparator
            maxPoolUtilizationPercent = arguments.maxPoolUtilization
            minFreeBytes = arguments.minFreeBytes
            recursive = arguments.recursive ?? Defaults.recursive
            stringEncodingRawValue = arguments.common.stringEncodingRawValue ?? Defaults.stringEncoding.rawValue
        }

        enum CodingKeys: String, CodingKey {
            case datasetGrep, dateSeparator, execute, excludedDatasetGreps, lineSeparator
            case maxPoolUtilizationPercent, minFreeBytes
            case recursive, stringEncodingRawValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            datasetGrep = try container.decodeIfPresent(String.self, forKey: .datasetGrep)
            dateSeparator = try container.decode(String.self, forKey: .dateSeparator)
            execute = try container.decode(Bool.self, forKey: .execute)
            excludedDatasetGreps = try container.decodeIfPresent([String].self, forKey: .excludedDatasetGreps) ?? []
            lineSeparator = try container.decode(String.self, forKey: .lineSeparator)
            maxPoolUtilizationPercent = try container.decodeIfPresent(Float.self, forKey: .maxPoolUtilizationPercent)
            minFreeBytes = try container.decodeIfPresent(Int64.self, forKey: .minFreeBytes)
            recursive = try container.decode(Bool.self, forKey: .recursive)
            stringEncodingRawValue = try container.decode(String.Encoding.RawValue.self, forKey: .stringEncodingRawValue)
        }
    }
}
