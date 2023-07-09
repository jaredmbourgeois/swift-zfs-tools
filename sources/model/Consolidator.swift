// Consolidator.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell

public struct Consolidator: Sendable {
    private let calendar: Calendar
    private let config: Config
    private let date: @Sendable () -> Date
    private let dateFormatter: DateFormatter
    private let shell: ShellAtPath

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

    public func consolidate() async throws {
        async let datasetsLocalBinding: [String] = try await shell.execute(
            ZFS.listDatasets(grepping: config.datasetGrep),
            dryRun: !config.execute
        )
        .get()
        .decodeStringLines(
            encoding: config.stringEncoding,
            lineSeparator: config.lineSeparator
        )
        .stdoutTyped
        async let snapshotsLocalBinding: [String] = try await shell.execute(
            ZFS.listSnapshots(grepping: config.datasetGrep),
            dryRun: !config.execute
        )
        .get()
        .decodeStringLines(
            encoding: config.stringEncoding,
            lineSeparator: config.lineSeparator
        )
        .stdoutTyped
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
    public struct Config: Codable, Sendable, Equatable {
        public let datasetGrep: String?
        public let dateSeparator: String
        public let execute: Bool
        public let lineSeparator: String
        public let schedule: SnapshotConsolidationSchedule
        public let snapshotsNotConsolidated: [String]
        public let stringEncodingRawValue: UInt
        public var stringEncoding: String.Encoding { .init(rawValue: stringEncodingRawValue) }

        public init(
            datasetGrep: String?,
            dateSeparator: String,
            execute: Bool,
            lineSeparator: String,
            schedule: SnapshotConsolidationSchedule,
            snapshotsNotConsolidated: [String],
            stringEncoding: String.Encoding
        ) {
            self.datasetGrep = datasetGrep
            self.dateSeparator = dateSeparator
            self.execute = execute
            self.lineSeparator = lineSeparator
            self.schedule = schedule
            self.snapshotsNotConsolidated = snapshotsNotConsolidated
            self.stringEncodingRawValue = stringEncoding.rawValue
        }

        public init(
            arguments: Arguments.Consolidate,
            dateFormatter: DateFormatter,
            fileManager: FileManager,
            jsonDecoder: JSONDecoder
        ) throws {
            datasetGrep = arguments.datasetGrep
            dateSeparator = arguments.common.dateSeparator ?? Defaults.dateSeparator
            execute = arguments.common.execute ?? Defaults.execute
            lineSeparator = arguments.common.lineSeparator ?? Defaults.lineSeparator
            schedule = if let consolidationPeriodPath = arguments.consolidationPeriodPath {
                try decodeFromJSONAtPath(
                    consolidationPeriodPath,
                    fileManager: fileManager,
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
                    fileManager: fileManager,
                    jsonDecoder: jsonDecoder
                )
            } else {
                []
            }
            stringEncodingRawValue = arguments.common.stringEncodingRawValue ?? Defaults.stringEncoding.rawValue
        }
    }
}
