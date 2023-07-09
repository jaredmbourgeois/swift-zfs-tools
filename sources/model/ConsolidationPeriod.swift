import Foundation

extension Date: @unchecked Sendable { }

extension Consolidator {
  public struct ConsolidationPeriod: Codable, Hashable, Sendable {
    public let snapshotPeriods: SnapshotPeriods
    public let snapshotPeriodBias: Consolidator.SnapshotPeriod.Bias
    public let upperBound: Date

    public static func makeStandard(upperBound: Date) -> ConsolidationPeriod {
      Consolidator.ConsolidationPeriod.ConsolidationPeriodBuilder(upperBound: upperBound)
        .snapshotPeriod(snapshots: 7)
          .with(days: 1)
          .snapshotPeriodComplete()
        .snapshotPeriod(snapshots: 3)
          .with(weeksOfYear: 1)
          .snapshotPeriodComplete()
        .snapshotPeriod(snapshots: 11)
          .with(months: 1)
          .snapshotPeriodComplete()
        .snapshotPeriod(snapshots: 4)
          .with(months: 3)
          .snapshotPeriodComplete()
        .snapshotPeriod(snapshots: 97)
          .with(years: 1)
          .snapshotPeriodComplete()
        .build()
    }

    fileprivate init(
      upperBound: Date,
      snapshotPeriods: SnapshotPeriods,
      snapshotPeriodBias: Consolidator.SnapshotPeriod.Bias
    ) {
      self.upperBound = upperBound
      self.snapshotPeriods = snapshotPeriods
      self.snapshotPeriodBias = snapshotPeriodBias
    }
  }
}

extension Array where Element == Consolidator.ConsolidationPeriod.SnapshotPeriodRangeSnapshotAndDates {
  public var snapshots: [String] {
    flatMap { $0.snapshotAndDates.map { sD in sD.snapshot } }
  }
}

extension Consolidator.ConsolidationPeriod {
  public struct SnapshotPeriodRangeSnapshotAndDates: Codable, Hashable, Sendable {
    public let snapshotPeriod: Consolidator.SnapshotPeriod
    public let range: Range<Date>
    public let snapshotAndDates: [SnapshotAndDate]
  }

  public struct SnapshotAndDate: Codable, Hashable, Sendable {
    public let snapshot: String
    public let date: Date
  }
}

extension Consolidator.ConsolidationPeriod {
  public class ConsolidationPeriodBuilder {
    private let upperBound: Date
    private let snapshotPeriodBias: Consolidator.SnapshotPeriod.Bias

    private var snapshotPeriods = Consolidator.SnapshotPeriods()
    private var snapshotPeriod: Consolidator.SnapshotPeriod?

    public init(
      upperBound: Date,
      snapshotPeriodBias: Consolidator.SnapshotPeriod.Bias = .upperBound
    ) {
      self.upperBound = upperBound
      self.snapshotPeriodBias = snapshotPeriodBias
    }

    public func snapshotPeriod(snapshots: UInt16) -> SnapshotFrequencyBuilder {
      snapshotPeriod = .init(snapshots: snapshots, frequency: [])
      return .init(self)
    }

    public func build() -> Consolidator.ConsolidationPeriod {
      let period = Consolidator.ConsolidationPeriod(
        upperBound: upperBound,
        snapshotPeriods: snapshotPeriods,
        snapshotPeriodBias: snapshotPeriodBias
      )
      snapshotPeriods = []
      snapshotPeriod = nil
      return period
    }

    fileprivate func snapshotPeriodComplete(_ frequency: Consolidator.SnapshotPeriod.SnapshotFrequency) {
      guard let snapshotPeriod = snapshotPeriod else { return }
      let snapshotPeriodWithFrequency = Consolidator.SnapshotPeriod(
        snapshots: snapshotPeriod.snapshots,
        frequency: frequency
      )
      self.snapshotPeriod = snapshotPeriodWithFrequency
      snapshotPeriods.append(snapshotPeriodWithFrequency)
    }
  }

  public class SnapshotFrequencyBuilder: Consolidator.SnapshotPeriod.SnapshotFrequency.Builder {
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
