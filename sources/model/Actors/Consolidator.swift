import Algorithms
import Foundation
import Shell

public actor Consolidator {
  private let shell: ShellExecutor
  private let config: Config
  private let calendar: Calendar
  private let dateFormatter: DateFormatter

  public init(
    shell: ShellExecutor,
    config: Config,
    calendar: Calendar,
    dateFormatter: DateFormatter
  ) {
    self.shell = shell
    self.config = config
    self.calendar = calendar
    self.dateFormatter = dateFormatter
  }

  public func consolidate() async throws {
    let datasets = try await shell.zfsListDatasets(matching: config.datasetGrep, execute: config.execute)
    let datasetSnapshots = try await withThrowingTaskGroup(of: DatasetSnapshots.self) { taskGroup in
      datasets.forEach { dataset in
        taskGroup.addTask {
          let datasetSnapshots = try await self.shell.zfsListSnapshotsInDataset(
            dataset: dataset,
            dateSeparator: self.config.dateSeparator,
            execute: self.config.execute
          )
          let datasetSnapshotsToDelete = await self.snapshotsToDelete(datasetSnapshots)
          return DatasetSnapshots(
            dataset: dataset,
            all: datasetSnapshots,
            toDelete: datasetSnapshotsToDelete
          )
        }
      }
      return try await taskGroup.reduce(into: [DatasetSnapshots]()) { accumulated, datasetSnapshots in
        accumulated.append(datasetSnapshots)
      }
    }

    try await shell.zfsDeleteSnapshots(datasetSnapshots.flatMap { $0.toDelete }, execute: config.execute)

    await withThrowingTaskGroup(of: Void.self) { taskGroup in
      for datasetSnapshots in datasetSnapshots {
        taskGroup.addTask {
          try await self.shell.sudo(
            "echo \(datasetSnapshots.dataset) total: \(datasetSnapshots.all.count), deleted: \(datasetSnapshots.toDelete.count), kept: \(datasetSnapshots.all.count - datasetSnapshots.toDelete.count)",
            execute: true
          )
          try await self.shell.sudo(
            "echo \(datasetSnapshots.dataset) snapshots deleted: [\n\t\(datasetSnapshots.toDelete.joined(by: "\n\t"))\n]",
            execute: true
          )
        }
      }
    }
  }

  private struct DatasetSnapshots {
    let dataset: String
    let all: [String]
    let toDelete: [String]
  }

  private func biasedSortByDate<T>(_ array: [T], date: (T) -> Date) -> [T] {
    switch config.consolidationPeriod.snapshotPeriodBias {
    case .lowerBound: return array.sorted { date($0) < date($1) }
    case .upperBound: return array.sorted { date($0) > date($1) }
    }
  }

  private var biasWeightFromLowerBound: TimeInterval {
    switch config.consolidationPeriod.snapshotPeriodBias {
    case .lowerBound: return 0.333
    case .upperBound: return 0.667
    }
  }

  private func snapshotAndDatesSortedByMostRecent(from snapshots: [String]) -> [ConsolidationPeriod.SnapshotAndDate] {
    snapshots
      .compactMap { snapshot in
        guard let dateSplit = snapshot.split(separator: config.dateSeparator).last,
              let date = dateFormatter.date(from: String(dateSplit)) else { return nil }
        return .init(snapshot: snapshot, date: date)
      }
      .sorted { $0.date > $1.date }
  }

  private func snapshotAndDateClosestToTargetInRange(_ range: Range<Date>, snapshotAndDates: [ConsolidationPeriod.SnapshotAndDate]) -> ConsolidationPeriod.SnapshotAndDate? {
    let targetDate = range.lowerBound + biasWeightFromLowerBound * (range.upperBound.timeIntervalSince(range.lowerBound))
    return snapshotAndDates
      .filter { range.contains($0.date) }
      .sorted(by: { abs(targetDate.timeIntervalSince($0.date)) < abs(targetDate.timeIntervalSince($1.date)) })
      .first
  }

  private struct SnapshotPeriodRanges {
    let snapshotPeriod: SnapshotPeriod
    let upperBound: Date
    let snapshotRanges: [Range<Date>]
  }

  private func snapshotPeriodRanges(_ snapshotPeriod: SnapshotPeriod, upperBound: inout Date) -> SnapshotPeriodRanges {
    .init(
      snapshotPeriod: snapshotPeriod,
      upperBound: upperBound,
      snapshotRanges: (0 ..< snapshotPeriod.snapshots).map { snapshotIndex in
        let snapshotRange = snapshotPeriod.range(upperBound: upperBound, calendar: calendar)
        upperBound = snapshotRange.lowerBound
        return snapshotRange
      }
    )
  }

  private func snapshotsToDelete(_ snapshots: [String]) async -> [String] {
    let snapshotAndDatesSortedByMostRecent = snapshotAndDatesSortedByMostRecent(from: snapshots)
    var upperBound = config.consolidationPeriod.upperBound
    let snapshotPeriodRanges = config.consolidationPeriod.snapshotPeriods.map { snapshotPeriod in
      self.snapshotPeriodRanges(snapshotPeriod, upperBound: &upperBound)
    }
    let snapshotRanges = snapshotPeriodRanges.flatMap { $0.snapshotRanges }
    let snapshotAndDatesToKeep: [ConsolidationPeriod.SnapshotAndDate] = await withTaskGroup(of: ConsolidationPeriod.SnapshotAndDate?.self) { taskGroup in
      snapshotRanges.forEach { snapshotRange in
        taskGroup.addTask {
          await self.snapshotAndDateClosestToTargetInRange(snapshotRange, snapshotAndDates: snapshotAndDatesSortedByMostRecent)
        }
      }
      return await taskGroup.reduce(into: [ConsolidationPeriod.SnapshotAndDate]()) { accumulated, snapshotAndDate in
        guard let snapshotAndDate else { return }
        accumulated.append(snapshotAndDate)
      }
    }
    let snapshotsToKeep = (snapshotAndDatesToKeep.map { $0.snapshot } + config.snapshotsNotConsolidated).uniqued()
    return snapshots.filter { !snapshotsToKeep.contains($0) }
  }
}

extension Consolidator {
  public struct Config: Codable, Sendable, Equatable {
    public let datasetGrep: String
    public let dateSeparator: String
    public let snapshotsNotConsolidated: [String]
    public let consolidationPeriod: ConsolidationPeriod
    public let execute: Bool

    public init(
      datasetGrep: String,
      dateSeparator: String,
      snapshotsNotConsolidated: [String],
      consolidationPeriod: ConsolidationPeriod,
      execute: Bool
    ) {
      self.datasetGrep = datasetGrep
      self.dateSeparator = dateSeparator
      self.snapshotsNotConsolidated = snapshotsNotConsolidated
      self.consolidationPeriod = consolidationPeriod
      self.execute = execute
    }

    public init(
      arguments: Arguments.Consolidate,
      fileManager: FileManager,
      jsonDecoder: JSONDecoder,
      dateFormatter: DateFormatter,
      date: () -> Date
    ) throws {
      if let configPath = arguments.configPath {
        self = try decodeFromJsonAtPath(
          configPath,
          fileManager: fileManager,
          jsonDecoder: jsonDecoder
        )
        return
      }

      let snapshotsNotConsolidated: [String]
      if let doNotDeleteSnapshotsPath = arguments.doNotDeleteSnapshotsPath {
        snapshotsNotConsolidated = try decodeFromJsonAtPath(
          doNotDeleteSnapshotsPath,
          fileManager: fileManager,
          jsonDecoder: jsonDecoder
        )
      } else {
        snapshotsNotConsolidated = []
      }

      let period: Consolidator.ConsolidationPeriod
      if let consolidationPeriodPath = arguments.consolidationPeriodPath {
        period = try decodeFromJsonAtPath(
          consolidationPeriodPath,
          fileManager: fileManager,
          jsonDecoder: jsonDecoder
        )
      } else {
        let upperBound: Date
        if let arg = arguments.consolidationPeriodUpperBound {
          guard let date = dateFormatter.date(from: arg) else {
            throw ErrorType.dateFormat(string: arg, format: dateFormatter.dateFormat)
          }
          upperBound = date
        } else {
          upperBound = date()
        }
        period = .makeStandard(upperBound: upperBound)
      }
      datasetGrep = arguments.datasetGrep
      dateSeparator = arguments.common.dateSeparator ?? Defaults.dateSeparator
      self.snapshotsNotConsolidated = snapshotsNotConsolidated
      consolidationPeriod = period
      execute = arguments.common.execute ?? Defaults.execute
    }
  }
}
