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
    private let diagnostics: @Sendable (_ line: String) -> Void
    private let shell: ShellAtPath
    private let dryRunShell: ShellAtPath

    /// `date`/`dateFormatter` resolve the schedule window and parse snapshot timestamps; `calendar`
    /// does the period math; `diagnostics` takes the pool-guard warning and the aggressive-prune
    /// narration (a CLI's stderr); `shell` runs the commands and `dryRunShell` reports the ones a
    /// dry run holds back (inject mocks to test).
    public init(
        calendar: Calendar,
        config: Config,
        date: @escaping @Sendable () -> Date,
        dateFormatter: DateFormatter,
        diagnostics: @escaping @Sendable (_ line: String) -> Void,
        shell: ShellAtPath,
        dryRunShell: ShellAtPath
    ) {
        self.calendar = calendar
        self.config = config
        self.date = date
        self.dateFormatter = dateFormatter
        self.diagnostics = diagnostics
        self.shell = shell
        self.dryRunShell = dryRunShell
    }

    /// Apply the retention schedule (`zfs destroy` for snapshots outside the windows), then, if a
    /// pool threshold is set and still exceeded, aggressively prune oldest-first. Listings and the
    /// pool read run on a dry run too; only the destroys are held back (reported, not run).
    public func consolidate() async throws {
        let runner = ZFSRunner(
            shell: shell,
            dryRunShell: dryRunShell,
            execute: config.execute,
            stringEncoding: config.stringEncoding,
            lineSeparator: config.lineSeparator
        )
        // Two parallel local listings — read-only at the ZFS layer, parallel-safe.
        async let datasetsLocalBinding: [String] = try await runner.lines(ZFS.listDatasets()).matching(config.datasetGrep)
        async let snapshotsLocalBinding: [String] = try await runner.lines(ZFS.listSnapshots()).matching(config.datasetGrep)
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
                    let snapshotAndDatesForDataset: [SnapshotAndDate] = snapshotsLocal
                        .compactMap {
                            guard $0.hasPrefix(snapshotsForDatasetPrefix) else {
                                return nil
                            }
                            guard let date = parseSnapshotDate($0) else { return nil }
                            return SnapshotAndDate(
                                snapshot: $0,
                                date: date
                            )
                        }
                        .sorted { $0.date > $1.date }
                    guard let snapshotDateEarliest = snapshotAndDatesForDataset.last?.date else {
                        return []
                    }

                    let (upperBound, dateRangeAndSnapshotCounts) = try dateRangeAndSnapshotCounts(snapshotDateEarliest: snapshotDateEarliest)

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
            _ = try await runner.run(ZFS.destroy(subject: snapshot))
        }
        if config.maxPoolUtilizationPercent != nil || config.minFreeBytes != nil,
           let pool = PoolUtilization.poolName(from: config.datasetGrep) {
            let utilization = try await PoolUtilization.query(pool: pool, runner: runner)
            if utilization.exceedsThreshold(
                maxCapacityPercent: config.maxPoolUtilizationPercent,
                minFreeBytes: config.minFreeBytes
            ) {
                let verdict = config.execute
                    ? "Running aggressive pruning."
                    : "dry-run — would prune oldest-first until within threshold; the candidates follow in order."
                diagnostics("zfs-tools consolidate: WARNING — pool \(pool) utilization exceeds threshold after consolidation (capacity: \(utilization.capacityPercent)%, available: \(utilization.availableBytes) bytes). \(verdict)")
                try await aggressivePrune(
                    pool: pool,
                    utilization: utilization,
                    runner: runner,
                    datasetsLocal: datasetsLocal,
                    snapshotsLocal: snapshotsLocal
                )
            }
        }
    }

    /// Destroy the oldest snapshots first until the pool is back within threshold, keeping the newest
    /// of every dataset. On a real run the pool is re-read after each destroy; on a dry run nothing
    /// is destroyed, so the pool is read once and every candidate is issued (as a dry-run command) in
    /// the order a real run would take them.
    private func aggressivePrune(
        pool: String,
        utilization initialUtilization: PoolUtilization,
        runner: ZFSRunner,
        datasetsLocal: [String],
        snapshotsLocal: [String]
    ) async throws {
        var allSnapshotAndDates: [SnapshotAndDate] = snapshotsLocal
            .compactMap { snapshot in
                guard datasetsLocal.contains(where: { snapshot.hasPrefix($0 + config.dateSeparator) }) else {
                    return nil
                }
                guard let date = parseSnapshotDate(snapshot) else { return nil }
                return SnapshotAndDate(
                    snapshot: snapshot,
                    date: date
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
        var utilization = initialUtilization
        for (index, snapshotAndDate) in allSnapshotAndDates.enumerated() {
            if index > 0, config.execute {
                utilization = try await PoolUtilization.query(pool: pool, runner: runner)
            }
            guard utilization.exceedsThreshold(
                maxCapacityPercent: config.maxPoolUtilizationPercent,
                minFreeBytes: config.minFreeBytes
            ) else {
                diagnostics("zfs-tools consolidate: pool \(pool) utilization now within threshold (capacity: \(utilization.capacityPercent)%). Aggressive pruning complete.")
                return
            }
            let verb = config.execute ? "destroying" : "dry-run — would destroy"
            diagnostics("zfs-tools consolidate: aggressive prune — \(verb) \(snapshotAndDate.snapshot) (capacity: \(utilization.capacityPercent)%)")
            _ = try await runner.run(ZFS.destroy(subject: snapshotAndDate.snapshot))
        }
    }

    private struct DateRangeAndSnapshotCount {
        let range: Range<Date>
        let snapshots: UInt16
    }

    private func parseSnapshotDate(_ snapshot: String) -> Date? {
        try? dateFormatter.dateForSnapshot(snapshot, dateSeparator: config.dateSeparator)
    }

    private func dateRangeAndSnapshotCounts(
        snapshotDateEarliest: Date
    ) throws -> (upperBound: Date, dateRangeAndSnapshotCounts: [DateRangeAndSnapshotCount]) {
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
            maxPoolUtilizationPercent: Float?,
            minFreeBytes: Int64?,
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
