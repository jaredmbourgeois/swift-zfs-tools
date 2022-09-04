import Foundation

extension ZFSTools.Consolidator {
  public struct ConsolidationPeriod: Codable, Hashable, Sendable {
    public let upperBound: Date
    public let snapshotPeriods: ZFSTools.Consolidator.SnapshotPeriods
    public let snapshotPeriodBias: ZFSTools.Consolidator.SnapshotPeriod.Bias

    fileprivate init(
      upperBound: Date,
      snapshotPeriods: ZFSTools.Consolidator.SnapshotPeriods,
      snapshotPeriodBias: ZFSTools.Consolidator.SnapshotPeriod.Bias
    ) {
      self.upperBound = upperBound
      self.snapshotPeriods = snapshotPeriods
      self.snapshotPeriodBias = snapshotPeriodBias
    }

    public func snapshotPeriodRangeSnapshotAndDates(
      _ calendar: Calendar,
      snapshotPeriodBias: ZFSTools.Consolidator.SnapshotPeriod.Bias,
      snapshotAndDates: [SnapshotAndDate]
    ) -> [SnapshotPeriodRangeSnapshotAndDates] {
      var upperBound = upperBound
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

extension Array where Element == ZFSTools.Consolidator.ConsolidationPeriod.SnapshotPeriodRangeSnapshotAndDates {
  public var snapshots: [String] {
    map { $0.snapshotAndDate.snapshot }
  }
}

extension ZFSTools.Consolidator.ConsolidationPeriod {
  public struct SnapshotPeriodRangeSnapshotAndDates: Codable, Hashable, Sendable {
    public let snapshotPeriod: ZFSTools.Consolidator.SnapshotPeriod
    public let range: Range<Date>
    public let snapshotAndDate: SnapshotAndDate
  }

  public struct SnapshotAndDate: Codable, Hashable, Sendable {
    public let snapshot: String
    public let date: Date
  }
}

extension ZFSTools.Consolidator.ConsolidationPeriod {
  public class ConsolidationPeriodBuilder {
    private let upperBound: Date
    private let snapshotPeriodBias: ZFSTools.Consolidator.SnapshotPeriod.Bias

    private var snapshotPeriods = ZFSTools.Consolidator.SnapshotPeriods()
    private var snapshotPeriod: ZFSTools.Consolidator.SnapshotPeriod?

    public init(
      upperBound: Date = Date(),
      snapshotPeriodBias: ZFSTools.Consolidator.SnapshotPeriod.Bias = .upperBound
    ) {
      self.upperBound = upperBound
      self.snapshotPeriodBias = snapshotPeriodBias
    }

    public func snapshotPeriod(snapshots: UInt16) -> SnapshotFrequencyBuilder {
      snapshotPeriod = .init(snapshots: snapshots, frequency: [])
      return .init(self)
    }

    public func build() -> ZFSTools.Consolidator.ConsolidationPeriod {
      let period = ZFSTools.Consolidator.ConsolidationPeriod(
        upperBound: upperBound,
        snapshotPeriods: snapshotPeriods,
        snapshotPeriodBias: snapshotPeriodBias
      )
      snapshotPeriods = []
      snapshotPeriod = nil
      return period
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
  }

  public class SnapshotFrequencyBuilder: ZFSTools.Consolidator.SnapshotPeriod.SnapshotFrequency.Builder {
    private let periodBuilder: ConsolidationPeriodBuilder

    public init(_ periodBuilder: ConsolidationPeriodBuilder) {
      self.periodBuilder = periodBuilder
    }

    public func snapshotPeriodComplete() -> ConsolidationPeriodBuilder {
      periodBuilder.snapshotPeriodComplete(build())
      return periodBuilder
    }

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
