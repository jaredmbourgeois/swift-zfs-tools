import Foundation

public enum Defaults {
  public static func consolidationPeriod(upperBound: Date?) -> Consolidator.ConsolidationPeriod {
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
  public static let dateFormat = "yyyyMMdd-HHmmss"
  public static let dateSeparator = "@"
  public static let execute = false
  public static let recursive = false
  public static let shellPath = "/bin/bash"
  public static let shellPrintsStandardOutput = true
  public static let shellPrintsFailure = true
}
