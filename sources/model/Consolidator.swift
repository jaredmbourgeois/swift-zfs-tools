// Consolidator.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell

/// Prunes snapshots to a Grandfather-Father-Son schedule: within each period it keeps the snapshot
/// closest to each ideal evenly-spaced date and destroys the rest, per dataset. Snapshots newer than
/// the schedule's upper bound, and any in `config.snapshotsNotConsolidated`, are always kept. With a
/// pool threshold set, it follows up with an aggressive oldest-first prune until utilization drops.
public struct Consolidator: Sendable {
    private let calendar: Calendar
    private let config: Config
    private let date: @Sendable () -> Date
    private let dateFormatter: DateFormatter
    private let shell: ShellAtPath

    /// `date`/`dateFormatter` resolve the schedule window and parse snapshot timestamps; `calendar`
    /// does the period math; `shell` runs the commands (inject a mock to test).
    public init(
        calendar: Calendar,
        config: Config,
        date: @escaping @Sendable () -> Date,
        dateFormatter: DateFormatter,
        shell: ShellAtPath
    ) {
        self.calendar = calendar
        self.config = config
        self.date = date
        self.dateFormatter = dateFormatter
        self.shell = shell
    }

    /// Apply the retention schedule (`zfs destroy` for snapshots outside the windows), then, if a
    /// pool threshold is set and still exceeded, aggressively prune oldest-first.
    public func consolidate() async throws {
        // Two parallel local listings — read-only at the ZFS layer, parallel-safe.
        // Safe under swift-shell 2.0.0 (parallel pipe-drain race fixed in 1.4.1).
        async let datasetsLocalBinding: [String] = try await shell.lines(
            ZFS.listDatasets(grepping: config.datasetGrep),
            dryRun: !config.execute,
            encoding: config.stringEncoding,
            lineSeparator: config.lineSeparator
        )
        async let snapshotsLocalBinding: [String] = try await shell.lines(
            ZFS.listSnapshots(grepping: config.datasetGrep),
            dryRun: !config.execute,
            encoding: config.stringEncoding,
            lineSeparator: config.lineSeparator
        )
        let (
            datasetsLocal,
            snapshotsLocal
        ) = try await (
            datasetsLocalBinding,
            snapshotsLocalBinding
        )
        guard !snapshotsLocal.isEmpty else { return }
        let snapshotsToDestroy: [String] = try await withThrowingTaskGroup(
            of: [String].self,
            returning: [String].self
        ) { taskGroup in
            for dataset in datasetsLocal {
                taskGroup.addTask {
                    let snapshotsForDatasetPrefix = dataset + config.dateSeparator
                    let snapshotAndDatesForDataset: [SnapshotAndDate] = try snapshotsLocal
                        .compactMap {
                            guard $0.hasPrefix(snapshotsForDatasetPrefix) else {
                                return nil
                            }
                            return SnapshotAndDate(
                                snapshot: $0,
                                date: try dateFormatter.dateForSnapshot($0, dateSeparator: config.dateSeparator)
                            )
                        }
                        .sorted { $0.date > $1.date }
                    guard let snapshotDateEarliest = snapshotAndDatesForDataset.last?.date else {
                        return []
                    }

                    let (upperBound, dateRangeAndSnapshotCounts) = try dateRangeAndShapshotCounts(snapshotDateEarliest: snapshotDateEarliest)

                    var snapshotAndDatesToKeepBySnapshot = [String: SnapshotAndDate]()
                    for snapshotAndDate in snapshotAndDatesForDataset {
                        guard snapshotAndDate.date > upperBound || config.snapshotsNotConsolidated.contains(where: { $0 == snapshotAndDate.snapshot }) else {
                            continue
                        }
                        snapshotAndDatesToKeepBySnapshot[snapshotAndDate.snapshot] = snapshotAndDate
                    }

                    var closestSnapshotAndDateInRange: SnapshotAndDate?
                    var dateRangeSeconds: TimeInterval
                    var idealInterval: TimeInterval
                    var idealDates: [Date]
                    var snapshotAndDatesInRange: [SnapshotAndDate]
                    for dateRangeAndSnapshotCount in dateRangeAndSnapshotCounts {
                        snapshotAndDatesInRange = snapshotAndDatesForDataset.filter {
                            $0.date > dateRangeAndSnapshotCount.range.lowerBound && $0.date <= dateRangeAndSnapshotCount.range.upperBound
                        }
                        dateRangeSeconds = dateRangeAndSnapshotCount.range.upperBound.timeIntervalSince(dateRangeAndSnapshotCount.range.lowerBound)
                        idealInterval = dateRangeSeconds / TimeInterval(dateRangeAndSnapshotCount.snapshots + 1)
                        idealDates = (1 ... dateRangeAndSnapshotCount.snapshots).map { dateRangeAndSnapshotCount.range.upperBound.addingTimeInterval(-TimeInterval($0) * idealInterval) }
                        for idealDate in idealDates {
                            closestSnapshotAndDateInRange = nil
                            for snapshotAndDateInRange in snapshotAndDatesInRange {
                                if closestSnapshotAndDateInRange != nil {
                                    if abs(snapshotAndDateInRange.date.timeIntervalSince(idealDate)) < abs(closestSnapshotAndDateInRange!.date.timeIntervalSince(idealDate)) {
                                        closestSnapshotAndDateInRange = snapshotAndDateInRange
                                    }
                                } else {
                                    closestSnapshotAndDateInRange = snapshotAndDateInRange
                                }
                            }
                            if let closestSnapshotAndDateInRange {
                                snapshotAndDatesToKeepBySnapshot[closestSnapshotAndDateInRange.snapshot] = closestSnapshotAndDateInRange
                                snapshotAndDatesInRange.removeAll { $0 == closestSnapshotAndDateInRange }
                            }
                        }
                    }

                    return snapshotAndDatesForDataset.compactMap {
                        guard snapshotAndDatesToKeepBySnapshot[$0.snapshot] == nil else {
                            return nil
                        }
                        return $0.snapshot
                    }
                }
            }
            var snapshots = [String]()
            for try await snapshotsForDataset in taskGroup {
                snapshots.append(contentsOf: snapshotsForDataset)
            }
            snapshots.sort(by: { $0 < $1 })
            return snapshots
        }
        for snapshot in snapshotsToDestroy {
            _ = try await shell.execute(
                ZFS.destroy(subject: snapshot),
                dryRun: !config.execute
            ).get()
        }
        if config.maxPoolUtilizationPercent != nil || config.minFreeBytes != nil,
           let pool = PoolUtilization.poolName(from: config.datasetGrep) {
            let utilization = try await PoolUtilization.query(
                pool: pool,
                shell: shell,
                dryRun: !config.execute,
                stringEncoding: config.stringEncoding,
                lineSeparator: config.lineSeparator
            )
            if utilization.exceedsThreshold(
                maxCapacityPercent: config.maxPoolUtilizationPercent,
                minFreeBytes: config.minFreeBytes
            ) {
                print("zfs-tools consolidate: WARNING — pool \(pool) utilization exceeds threshold after consolidation (capacity: \(utilization.capacityPercent)%, available: \(utilization.availableBytes) bytes). Running aggressive pruning.")
                try await aggressivePrune(
                    pool: pool,
                    datasetsLocal: datasetsLocal,
                    snapshotsLocal: snapshotsLocal
                )
            }
        }
    }

    private func aggressivePrune(
        pool: String,
        datasetsLocal: [String],
        snapshotsLocal: [String]
    ) async throws {
        var allSnapshotAndDates: [SnapshotAndDate] = try snapshotsLocal
            .compactMap { snapshot in
                guard datasetsLocal.contains(where: { snapshot.hasPrefix($0 + config.dateSeparator) }) else {
                    return nil
                }
                return SnapshotAndDate(
                    snapshot: snapshot,
                    date: try dateFormatter.dateForSnapshot(snapshot, dateSeparator: config.dateSeparator)
                )
            }
            .sorted { $0.date < $1.date }
        // Keep at least one snapshot per dataset
        var newestByDataset = [String: SnapshotAndDate]()
        for snapshotAndDate in allSnapshotAndDates {
            let dataset = String(snapshotAndDate.snapshot.split(separator: config.dateSeparator).first ?? "")
            newestByDataset[dataset] = snapshotAndDate
        }
        let protectedSnapshots = Set(newestByDataset.values.map(\.snapshot))
        allSnapshotAndDates.removeAll { protectedSnapshots.contains($0.snapshot) || config.snapshotsNotConsolidated.contains($0.snapshot) }
        for snapshotAndDate in allSnapshotAndDates {
            let utilization = try await PoolUtilization.query(
                pool: pool,
                shell: shell,
                dryRun: !config.execute,
                stringEncoding: config.stringEncoding,
                lineSeparator: config.lineSeparator
            )
            guard utilization.exceedsThreshold(
                maxCapacityPercent: config.maxPoolUtilizationPercent,
                minFreeBytes: config.minFreeBytes
            ) else {
                print("zfs-tools consolidate: pool \(pool) utilization now within threshold (capacity: \(utilization.capacityPercent)%). Aggressive pruning complete.")
                return
            }
            print("zfs-tools consolidate: aggressive prune — destroying \(snapshotAndDate.snapshot) (capacity: \(utilization.capacityPercent)%)")
            _ = try await shell.execute(
                ZFS.destroy(subject: snapshotAndDate.snapshot),
                dryRun: !config.execute
            ).get()
        }
    }

    private struct DateRangeAndSnapshotCount {
        let range: Range<Date>
        let snapshots: UInt16
    }

    private func dateRangeAndShapshotCounts(
        snapshotDateEarliest: Date
    ) throws -> (upperBound: Date, dateRangeAndShapshotCounts: [DateRangeAndSnapshotCount]) {
        let upperBound: Date = try {
            if let upperBound = config.schedule.upperBound {
                guard let date = dateFormatter.date(from: upperBound) else {
                    throw ErrorType.dateFromString(string: upperBound, format: dateFormatter.dateFormat)
                }
                return date
            } else {
                return date()
            }
        }()
        var dateLatest = upperBound
        var dateEarliest: Date
        var dateRangeAndSnapshotCounts: [DateRangeAndSnapshotCount] = []
        for consolidationPeriod in config.schedule.periods {
            if consolidationPeriod.repetitions == nil {
                while dateLatest > snapshotDateEarliest {
                    dateEarliest = if let date = calendar.date(
                        byAdding: {
                            switch consolidationPeriod.everyPeriod {
                            case .years: .year
                            case .months: .month
                            case .weeks: .weekOfYear
                            case .days: .day
                            case .hours: .hour
                            }
                        }(),
                        value: -.init(consolidationPeriod.everyMultiple),
                        to: dateLatest
                    ) { date }
                    else {
                        throw ErrorType.dateFromCalendar(date: dateLatest)
                    }
                    dateRangeAndSnapshotCounts.append(
                        .init(
                            range: dateEarliest ..< dateLatest,
                            snapshots: consolidationPeriod.snapshots
                        )
                    )
                    dateLatest = dateEarliest
                }
            } else if consolidationPeriod.repetitions! > 0 {
                for _ in 0 ..< consolidationPeriod.repetitions! {
                    dateEarliest = if let date = calendar.date(
                        byAdding: {
                            switch consolidationPeriod.everyPeriod {
                            case .years: .year
                            case .months: .month
                            case .weeks: .weekOfYear
                            case .days: .day
                            case .hours: .hour
                            }
                        }(),
                        value: -.init(consolidationPeriod.everyMultiple),
                        to: dateLatest
                    ) {
                        date
                    } else {
                        throw ErrorType.dateFromCalendar(date: dateLatest)
                    }
                    dateRangeAndSnapshotCounts.append(
                        .init(
                            range: dateEarliest ..< dateLatest,
                            snapshots: consolidationPeriod.snapshots
                        )
                    )
                    dateLatest = dateEarliest
                }
            }
        }
        return (upperBound, dateRangeAndSnapshotCounts)
    }
}

extension Consolidator {
    /// A consolidation run as a `Codable` value — the `consolidate-configure` / `consolidate-configured`
    /// JSON schema. Build it from CLI `Arguments.Consolidate` or decode it from a saved config file.
    public struct Config: Codable, Sendable, Equatable {
        /// Only consolidate datasets whose `zfs list` name matches this `grep` pattern; `nil` = all.
        public let datasetGrep: String?
        public let dateSeparator: String
        /// When `false` (the default), `zfs destroy` commands are printed but not run.
        public let execute: Bool
        public let lineSeparator: String
        /// After the schedule runs, aggressively prune if capacity still exceeds this percent; `nil` disables.
        public let maxPoolUtilizationPercent: Float?
        /// After the schedule runs, aggressively prune if free space is still below this many bytes; `nil` disables.
        public let minFreeBytes: Int64?
        /// The retention schedule — the periods and counts that decide which snapshots survive.
        public let schedule: SnapshotConsolidationSchedule
        /// Snapshot names that are never destroyed, even when the schedule would prune them.
        public let snapshotsNotConsolidated: [String]
        /// `String.Encoding.rawValue` for decoding command output; `4` is UTF-8.
        public let stringEncodingRawValue: UInt
        public var stringEncoding: String.Encoding { .init(rawValue: stringEncodingRawValue) }

        public init(
            datasetGrep: String?,
            dateSeparator: String,
            execute: Bool,
            lineSeparator: String,
            maxPoolUtilizationPercent: Float? = nil,
            minFreeBytes: Int64? = nil,
            schedule: SnapshotConsolidationSchedule,
            snapshotsNotConsolidated: [String],
            stringEncoding: String.Encoding
        ) {
            self.datasetGrep = datasetGrep
            self.dateSeparator = dateSeparator
            self.execute = execute
            self.lineSeparator = lineSeparator
            self.maxPoolUtilizationPercent = maxPoolUtilizationPercent
            self.minFreeBytes = minFreeBytes
            self.schedule = schedule
            self.snapshotsNotConsolidated = snapshotsNotConsolidated
            self.stringEncodingRawValue = stringEncoding.rawValue
        }

        public init(
            arguments: Arguments.Consolidate,
            dateFormatter: DateFormatter,
            fileSystem: FileSystem,
            jsonDecoder: JSONDecoder
        ) throws {
            datasetGrep = arguments.datasetGrep
            dateSeparator = arguments.common.dateSeparator ?? Defaults.dateSeparator
            execute = arguments.common.execute ?? Defaults.execute
            lineSeparator = arguments.common.lineSeparator ?? Defaults.lineSeparator
            maxPoolUtilizationPercent = arguments.maxPoolUtilization
            minFreeBytes = arguments.minFreeBytes
            schedule = if let consolidationPeriodPath = arguments.consolidationPeriodPath {
                try decodeFromJSONAtPath(
                    consolidationPeriodPath,
                    fileSystem: fileSystem,
                    jsonDecoder: jsonDecoder
                )
            } else {
                Defaults.consolidationSchedule(
                    upperBound: try {
                        if let arg = arguments.consolidationPeriodUpperBound {
                            guard let date = dateFormatter.date(from: arg) else {
                                throw ErrorType.dateFromString(string: arg, format: dateFormatter.dateFormat)
                            }
                            return dateFormatter.string(from: date)
                        } else {
                            return nil
                        }
                    }()
                )
            }
            snapshotsNotConsolidated = if let doNotDeleteSnapshotsPath = arguments.doNotDeleteSnapshotsPath {
                try decodeFromJSONAtPath(
                    doNotDeleteSnapshotsPath,
                    fileSystem: fileSystem,
                    jsonDecoder: jsonDecoder
                )
            } else {
                []
            }
            stringEncodingRawValue = arguments.common.stringEncodingRawValue ?? Defaults.stringEncoding.rawValue
        }

        enum CodingKeys: String, CodingKey {
            case datasetGrep, dateSeparator, execute, lineSeparator
            case maxPoolUtilizationPercent, minFreeBytes
            case schedule, snapshotsNotConsolidated, stringEncodingRawValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            datasetGrep = try container.decodeIfPresent(String.self, forKey: .datasetGrep)
            dateSeparator = try container.decode(String.self, forKey: .dateSeparator)
            execute = try container.decode(Bool.self, forKey: .execute)
            lineSeparator = try container.decode(String.self, forKey: .lineSeparator)
            maxPoolUtilizationPercent = try container.decodeIfPresent(Float.self, forKey: .maxPoolUtilizationPercent)
            minFreeBytes = try container.decodeIfPresent(Int64.self, forKey: .minFreeBytes)
            schedule = try container.decode(SnapshotConsolidationSchedule.self, forKey: .schedule)
            snapshotsNotConsolidated = try container.decode([String].self, forKey: .snapshotsNotConsolidated)
            stringEncodingRawValue = try container.decode(UInt.self, forKey: .stringEncodingRawValue)
        }
    }
}
