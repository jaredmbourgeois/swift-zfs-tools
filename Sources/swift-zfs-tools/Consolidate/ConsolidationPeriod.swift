import Foundation

extension ZFSTools.Consolidator {
  public struct ConsolidatePeriod: ZFSTools.Model {
    public let upperBound: String?
    public let snapshotPeriods: ZFSTools.Consolidator.SnapshotPeriods
    public let snapshotPeriodBias: ZFSTools.Consolidator.SnapshotPeriod.Bias

    fileprivate init(
      upperBound: String?,
      snapshotPeriods: ZFSTools.Consolidator.SnapshotPeriods,
      snapshotPeriodBias: ZFSTools.Consolidator.SnapshotPeriod.Bias
    ) {
      self.upperBound = upperBound
      self.snapshotPeriods = snapshotPeriods
      self.snapshotPeriodBias = snapshotPeriodBias
    }

    public func snapshotPeriodRangeSnapshotAndDates(
      _ calendar: Calendar,
      dateFormatter: DateFormatter,
      snapshotPeriodBias: ZFSTools.Consolidator.SnapshotPeriod.Bias,
      snapshotAndDates: [SnapshotAndDate]
    ) -> [SnapshotPeriodRangeSnapshotAndDates] {
      var upperBound = Date()
      if let upperBoundInput = self.upperBound,
         let upperBoundInputDate = dateFormatter.date(from: upperBoundInput) {
        upperBound = upperBoundInputDate
      }
      return snapshotPeriods.flatMap { snapshotPeriod in
        (0..<snapshotPeriod.snapshots).compactMap { _ in
          let range = snapshotPeriod.range(upperBound: upperBound, calendar: calendar)
          upperBound = range.lowerBound
          guard let snapshotAndDate = snapshotAndDates
                                        .filter({ range.contains($0.date) })
                                        .sorted(by: {
                                          switch snapshotPeriodBias {
                                          case .upperBound: return $0.date > $1.date
                                          case .lowerBound: return $0.date < $1.date
                                          }
                                        })
                                        .first else { return nil }
          return .init(
            snapshotPeriod: snapshotPeriod,
            range: range,
            snapshotAndDate: snapshotAndDate
          )
        }
      }
    }
  }
}

extension Array where Element == ZFSTools.Consolidator.ConsolidatePeriod.SnapshotPeriodRangeSnapshotAndDates {
  public var snapshots: [String] {
    map { $0.snapshotAndDate.snapshot }
  }
}

extension ZFSTools.Consolidator.ConsolidatePeriod {
  public struct SnapshotPeriodRangeSnapshotAndDates: ZFSTools.Model {
    public let snapshotPeriod: ZFSTools.Consolidator.SnapshotPeriod
    public let range: Range<Date>
    public let snapshotAndDate: SnapshotAndDate
  }

  public struct SnapshotAndDate: ZFSTools.Model {
    public let snapshot: String
    public let date: Date
  }
}

extension ZFSTools.Consolidator.ConsolidatePeriod {
  public class ConsolidatePeriodBuilder {
    private let upperBound: String?
    private let snapshotPeriodBias: ZFSTools.Consolidator.SnapshotPeriod.Bias

    private var snapshotPeriods = ZFSTools.Consolidator.SnapshotPeriods()
    private var snapshotPeriod: ZFSTools.Consolidator.SnapshotPeriod?

    /// snapshotPeriodBias used when multiple snapshots are in a period to prioritize keeping snapshot that's closest to the upper or lower bound of that period range
    public init(
      upperBound: String? = nil,
      snapshotPeriodBias: ZFSTools.Consolidator.SnapshotPeriod.Bias = .upperBound
    ) {
      self.upperBound = upperBound
      self.snapshotPeriodBias = snapshotPeriodBias
    }

    /// starts a new snapshot period that will be repeated `snapshots` number of times
    public func snapshotPeriod(snapshots: UInt16) -> SnapshotFrequencyBuilder {
      snapshotPeriod = .init(snapshots: snapshots, frequency: [])
      return .init(self)
    }

    fileprivate func snapshotPeriodComplete(_ frequency: ZFSTools.Consolidator.SnapshotPeriod.SnapshotFrequency) {
      guard let snapshotPeriod = snapshotPeriod else { return }
      let snapshotPeriodWithFrequency = ZFSTools.Consolidator.SnapshotPeriod(
        snapshots: snapshotPeriod.snapshots,
        frequency: frequency
      )
      self.snapshotPeriod = snapshotPeriodWithFrequency
      snapshotPeriods.append(snapshotPeriodWithFrequency)
    }

    /// builds the `ConsolidatePeriod` and resets the builder
    public func build() -> ZFSTools.Consolidator.ConsolidatePeriod {
      let period = ZFSTools.Consolidator.ConsolidatePeriod(
        upperBound: upperBound,
        snapshotPeriods: snapshotPeriods,
        snapshotPeriodBias: snapshotPeriodBias
      )
      snapshotPeriods = []
      snapshotPeriod = nil
      return period
    }
  }

  public class SnapshotFrequencyBuilder: ZFSTools.Consolidator.SnapshotPeriod.SnapshotFrequency.Builder {
    private let periodBuilder: ConsolidatePeriodBuilder

    public init(_ periodBuilder: ConsolidatePeriodBuilder) {
      self.periodBuilder = periodBuilder
    }

    /// finishes the SnapshotPeriod in progress
    public func snapshotPeriodComplete() -> ConsolidatePeriodBuilder {
      periodBuilder.snapshotPeriodComplete(build())
      return periodBuilder
    }

    /// adds a number of the given calendar units to the frequency in progress
    public override func with(
      years: UInt16? = nil,
      months: UInt16? = nil,
      weeksOfMonth: UInt16? = nil,
      weeksOfYear: UInt16? = nil,
      days: UInt16? = nil,
      hours: UInt16? = nil,
      minutes: UInt16? = nil
    ) -> Self {
      _ = super.with(
        years: years,
        months: months,
        weeksOfMonth: weeksOfMonth,
        weeksOfYear: weeksOfYear,
        days: days,
        hours: hours,
        minutes: minutes
      )
      return self
    }
  }
}
