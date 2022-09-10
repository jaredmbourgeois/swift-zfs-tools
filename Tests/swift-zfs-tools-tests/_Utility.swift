import Foundation
import XCTest

@testable import swift_zfs_tools

class TestUtilities {
  private init() { }

  static let datasetMatch = "nas_12tb/nas"
  static let password = "1234567890"

  static let timeout = TimeInterval(120)

  /// August 2, 2022
  static let upperBound = Date(timeIntervalSince1970: TimeInterval(upperBoundSecondsSince1970))
  static let upperBoundSecondsSince1970 = 1659416400

  static let defaultConfig = ZFSTools.Config(
    actions: [
      .snapshot(.init(path: "snapshotConfig.json")),
      .consolidate(.init(path: "consolidateConfig.json")),
      .sync(.init(path: "syncConfig.json"))
    ],
    dateFormat: ZFSTools.Constants.snapshotDateFormat
  )

  static func decodedJSON<T: Decodable>(fileName: String, fileManager: FileManager = .default) -> T {
//    // TODO: Update this path for your machine
    let path = "/Users/jared/Projects/swift-zfs-tools/Tests/swift-zfs-tools-tests/_resources/\(fileName).json"
    let contents = fileManager.contents(atPath: path)!
    return try! JSONDecoder().decode(T.self, from: contents)
  }
}

// MARK: MockSnapshot
extension TestUtilities {
  static func snapshotsPerDayForRange(
    _ snapshotsPerDay: Int,
    snapshotDateFormat: String = ZFSTools.Constants.snapshotDateFormat,
    forRange range: Range<Date>,
    datasetName: String,
    calendar: Calendar = .current,
    config: ZFSTools.Action.Config.Consolidate
  ) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.dateFormat = snapshotDateFormat
    let timeBetweenSnapshots = TimeInterval.secondsPerDay / TimeInterval(snapshotsPerDay + 1)
    var date = range.upperBound
    var snapshots = ""
    while date >= range.lowerBound {
      var dateInDate = date
      for snapshotIndex in 0..<snapshotsPerDay {
        dateInDate = date.addingTimeInterval(-TimeInterval(snapshotIndex)*timeBetweenSnapshots)
        snapshots.append(line("\(datasetName)\(config.snapshotDateSeparator)\(dateFormatter.string(from: dateInDate))"))
      }
      date = calendar.date(byAdding: .day, value: -1, to: date)!
    }
    print("TEST \n\tconfig: \(config)\n\tsnapshots: \(snapshots)")
    return snapshots
  }

  static func line(_ string: String = "") -> String {
    "\(string)\n"
  }
}


// MARK: Consolidate
extension TestUtilities {
  static let consolidatePeriodDefault = ZFSTools.Consolidator.ConsolidatePeriod.ConsolidatePeriodBuilder(upperBound: upperBound)
    .snapshotPeriod(snapshots: 7)
      .with(days: 1)
      .snapshotPeriodComplete()
    .snapshotPeriod(snapshots: 3)
      .with(weeksOfYear: 1)
      .snapshotPeriodComplete()
    .snapshotPeriod(snapshots: 11)
      .with(months: 1)
      .snapshotPeriodComplete()
    .snapshotPeriod(snapshots: 16)
      .with(months: 3)
      .snapshotPeriodComplete()
    .snapshotPeriod(snapshots: 10)
      .with(months: 6)
      .snapshotPeriodComplete()
    .build()

  static func consolidateConfig(
    password: String = TestUtilities.password,
    datasetMatch: String = TestUtilities.datasetMatch,
    snapshotDateSeperator: String = ZFSTools.Constants.snapshotDateSeparator,
    snapshotsNotConsolidated: [String] = [],
    period: ZFSTools.Consolidator.ConsolidatePeriod = consolidatePeriodDefault,
    dryRun: Bool = false
  ) -> ZFSTools.Action.Config.Consolidate {
    ZFSTools.Action.Config.Consolidate(
      password: password,
      datasetMatch: datasetMatch,
      snapshotDateSeparator: snapshotDateSeperator,
      snapshotsNotConsolidated: snapshotsNotConsolidated,
      consolidatePeriod: period,
      dryRun: dryRun
    )
  }

  static func consolidatePeriodDays(
    _ days: UInt16 = 1,
    snapshots: UInt16 = 365,
    upperBound: Date = upperBound
  ) -> ZFSTools.Consolidator.ConsolidatePeriod {
    ZFSTools.Consolidator.ConsolidatePeriod.ConsolidatePeriodBuilder(upperBound: upperBound)
      .snapshotPeriod(snapshots: snapshots)
        .with(days: days)
        .snapshotPeriodComplete()
      .build()
  }

  static func consolidatePeriodWeeks(
    _ weeksOfYear: UInt16 = 1,
    snapshots: UInt16 = 365,
    upperBound: Date = upperBound
  ) -> ZFSTools.Consolidator.ConsolidatePeriod {
    ZFSTools.Consolidator.ConsolidatePeriod.ConsolidatePeriodBuilder(upperBound: upperBound)
      .snapshotPeriod(snapshots: snapshots)
        .with(weeksOfYear: weeksOfYear)
        .snapshotPeriodComplete()
      .build()
  }
}

// MARK: Snapshot
extension TestUtilities {
  static let snapshotDate = upperBound

  static func snapshotConfig(
    dataset: String = datasetMatch,
    recursive: Bool = true,
    dateSeparator: String = ZFSTools.Constants.snapshotDateSeparator,
    password: String = password,
    dryRun: Bool = false
  ) -> ZFSTools.Action.Config.Snapshot {
    .init(
      dataset: dataset,
      recursive: recursive,
      dateSeparator: dateSeparator,
      password: password,
      dryRun: dryRun
    )
  }
}

// MARK: Sync
extension TestUtilities {
  static let sshKeyPath = "sshKeyPath"
  static let sshIP = "sshIP"

  static func syncConfig(
    dataset: String = datasetMatch,
    dateSeparator: String = ZFSTools.Constants.snapshotDateSeparator,
    password: String = password,
    sshKeyPath: String = sshKeyPath,
    sshIP: String = sshIP,
    dryRun: Bool = false
  ) -> ZFSTools.Action.Config.Sync {
    .init(
      password: password,
      datasetMatch: dataset,
      snapshotDateSeparator: dateSeparator,
      sshKeyPath: sshKeyPath,
      sshIP: sshIP,
      dryRun: dryRun
    )
  }
}

// MARK: Output
extension TestUtilities {
  static let zfsDatasets: [String] = zfsDatasetsOutput.lines
  static let zfsDatasetsOutput: String = """
    nas_12tb/nas/documents
    nas_12tb/nas/family
    nas_12tb/nas/media
    nas_12tb/nas/media/audio_books
    nas_12tb/nas/media/games
    nas_12tb/nas/media/movies
    nas_12tb/nas/media/music
    nas_12tb/nas/media/tv_comedy_documentaries
    nas_12tb/nas/pictures
    nas_12tb/nas/projects
    nas_12tb/nas/software
    nas_12tb/nas/source
    """

  static let zfsDatasetsSingle = zfsDatasetsOutputSingle.lines
  static let zfsDatasetsOutputSingle: String = """
    nas_12tb/nas/documents
    """

  static let zfsSnapshots = zfsSnapshotsOutput.lines
  static let zfsSnapshotsOutput: String = """
    nas_12tb/nas/documents@20210101-020423
    nas_12tb/nas/documents@20210823-033128
    nas_12tb/nas/documents@20220801-235247
    nas_12tb/nas/family@20210101-020423
    nas_12tb/nas/family@20210823-033128
    nas_12tb/nas/family@20220801-235247
    nas_12tb/nas/media@20210101-020423
    nas_12tb/nas/media@20210823-033128
    nas_12tb/nas/media@20220801-235247
    nas_12tb/nas/media/audio_books@20210101-020423
    nas_12tb/nas/media/audio_books@20210823-033128
    nas_12tb/nas/media/audio_books@20220801-235247
    nas_12tb/nas/media/games@20210101-020423
    nas_12tb/nas/media/games@20210823-033128
    nas_12tb/nas/media/games@20220801-235247
    nas_12tb/nas/media/movies@20210101-020423
    nas_12tb/nas/media/movies@20210823-033128
    nas_12tb/nas/media/movies@20220801-235247
    nas_12tb/nas/media/music@20210101-020423
    nas_12tb/nas/media/music@20210823-033128
    nas_12tb/nas/media/music@20220801-235247
    nas_12tb/nas/media/tv_comedy_documentaries@20210101-020423
    nas_12tb/nas/media/tv_comedy_documentaries@20210823-033128
    nas_12tb/nas/media/tv_comedy_documentaries@20220801-235247
    nas_12tb/nas/pictures@20210101-020423
    nas_12tb/nas/pictures@20210823-033128
    nas_12tb/nas/pictures@20220801-235247
    nas_12tb/nas/projects@20210101-020423
    nas_12tb/nas/projects@20210823-033128
    nas_12tb/nas/projects@20220801-235247
    nas_12tb/nas/software@20210101-020423
    nas_12tb/nas/software@20210823-033128
    nas_12tb/nas/software@20220801-235247
    nas_12tb/nas/source@20210101-020423
    nas_12tb/nas/source@20210823-033128
    nas_12tb/nas/source@20220801-235247
    """
}
