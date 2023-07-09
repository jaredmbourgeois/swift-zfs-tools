import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

class ConsolidatorTest: XCTestCase {
  private let calendar = Calendar(identifier: .gregorian)

  let dateFormat = "yyyyMMdd-HHmmss"
  private lazy var dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.dateFormat = dateFormat
    return dateFormatter
  }()

  private let timeout = TimeInterval(120)

  private let upperBound = Date(timeIntervalSince1970: 1659416400) // August 2, 2022

  private func makeConfig(
    snapshotPeriods: UInt16,
    daysPerSnapshot: UInt16?
  ) -> Consolidator.Config {
    Consolidator.Config(
      datasetGrep: "nas_12/nas/",
      dateSeparator: "@",
      snapshotsNotConsolidated: [],
      consolidationPeriod: Consolidator.ConsolidationPeriod.ConsolidationPeriodBuilder(upperBound: upperBound)
        .snapshotPeriod(snapshots: snapshotPeriods)
        .with(days: daysPerSnapshot)
        .snapshotPeriodComplete()
        .build(),
      execute: true
    )
  }

  private func makeConfig(
    snapshotsNotConsolidated: [String] = [],
    consolidationPeriod: Consolidator.ConsolidationPeriod
  ) -> Consolidator.Config {
    Consolidator.Config(
      datasetGrep: "nas_12/nas/",
      dateSeparator: "@",
      snapshotsNotConsolidated: snapshotsNotConsolidated,
      consolidationPeriod: consolidationPeriod,
      execute: true
    )
  }

  func testDeletionWhenSnapshotsOutOfRange() async throws {
    let config = makeConfig(
      consolidationPeriod: Consolidator.ConsolidationPeriod.ConsolidationPeriodBuilder(upperBound: Date())
        .snapshotPeriod(snapshots: 1)
        .with(days: 2)
        .snapshotPeriodComplete()
        .build()
    )
    let documentsExpectation = expectation(description: "documentsExpectation-\(UUID().uuidString)")
    let familyExpectation = expectation(description: "familyExpectation-\(UUID().uuidString)")
    let mediaExpectation = expectation(description: "mediaExpectation-\(UUID().uuidString)")
    let mediaAudioBooksExpectation = expectation(description: "mediaAudioBooksxpectation-\(UUID().uuidString)")
    let mediaGamesExpectation = expectation(description: "mediaGamesxpectation-\(UUID().uuidString)")
    let mediaMoviesExpectation = expectation(description: "mediaMoviesxpectation-\(UUID().uuidString)")
    let mediaTVExpectation = expectation(description: "mediaTVxpectation-\(UUID().uuidString)")
    let softwareExpectation = expectation(description: "softwarexpectation-\(UUID().uuidString)")
    let sourceExpectation = expectation(description: "sourcexpectation-\(UUID().uuidString)")
    let setup = setup(
      commandHandlers: commandHandlers(
        config,
        zfsListOutput: Self.zfsDatasetsOutput,
        zfsListSnapshotOutput: Self.zfsSnapshotsOutput
      ),
      actionHandler: { action in
        switch action.command {
        case "echo nas_12tb/nas/documents total: 3, deleted: 3, kept: 0": documentsExpectation.fulfill()
        case "echo nas_12tb/nas/family total: 3, deleted: 3, kept: 0": familyExpectation.fulfill()
        case "echo nas_12tb/nas/media total: 3, deleted: 3, kept: 0": mediaExpectation.fulfill()
        case "echo nas_12tb/nas/media/audio_books total: 3, deleted: 3, kept: 0": mediaAudioBooksExpectation.fulfill()
        case "echo nas_12tb/nas/media/games total: 3, deleted: 3, kept: 0": mediaGamesExpectation.fulfill()
        case "echo nas_12tb/nas/media/movies total: 3, deleted: 3, kept: 0": mediaMoviesExpectation.fulfill()
        case "echo nas_12tb/nas/media/tv_comedy_documentaries total: 3, deleted: 3, kept: 0": mediaTVExpectation.fulfill()
        case "echo nas_12tb/nas/software total: 3, deleted: 3, kept: 0": softwareExpectation.fulfill()
        case "echo nas_12tb/nas/source total: 3, deleted: 3, kept: 0": sourceExpectation.fulfill()
        default: return
        }
        print("TEST \(action.command)")
      },
      config: config
    )
    try await setup.consolidator.consolidate()
    await fulfillment(
      of: [
        documentsExpectation,
        familyExpectation,
        mediaExpectation,
        mediaAudioBooksExpectation,
        mediaGamesExpectation,
        mediaMoviesExpectation,
        mediaTVExpectation,
        softwareExpectation,
        sourceExpectation,
      ],
      timeout: timeout
    )
  }

  func testKeepSnapshotsNotConsolidated() async throws {
    let keepSnapshots = [
      "nas_12tb/nas/documents@20210101-020423",
      "nas_12tb/nas/documents@20210823-033128",
      "nas_12tb/nas/documents@20220801-235247"
    ]
    let config = makeConfig(
      snapshotsNotConsolidated: keepSnapshots,
      consolidationPeriod: Consolidator.ConsolidationPeriod.ConsolidationPeriodBuilder(upperBound: Date())
        .snapshotPeriod(snapshots: 1)
        .with(days: 2)
        .snapshotPeriodComplete()
        .build()
    )
    let expectation = expectation(description: "expectation-\(UUID().uuidString)")
    let setup = setup(
      commandHandlers: commandHandlers(
        config,
        zfsListOutput: Self.zfsDatasetsOutput,
        zfsListSnapshotOutput: Self.zfsSnapshotsOutput
      ),
      actionHandler: { action in
        keepSnapshots.forEach {
          XCTAssertNotEqual("zfs destroy \($0)", action.command)
        }
        guard action.command.contains("nas_12tb/nas/documents total: 3, deleted: 0, kept: 3") else { return }
        print("TEST \(action.command)")
        expectation.fulfill()
      },
      config: config
    )
    try await setup.consolidator.consolidate()
    await fulfillment(of: [expectation], timeout: timeout)
  }

  func testSnapshotsAreKept() async throws {
    let config = makeConfig(
      consolidationPeriod: Consolidator.ConsolidationPeriod.ConsolidationPeriodBuilder(upperBound: upperBound)
        .snapshotPeriod(snapshots: 24)
        .with(months: 1)
        .snapshotPeriodComplete()
        .build()
    )
    let documentsExpectation = expectation(description: "documentsExpectation-\(UUID().uuidString)")
    let familyExpectation = expectation(description: "familyExpectation-\(UUID().uuidString)")
    let mediaExpectation = expectation(description: "mediaExpectation-\(UUID().uuidString)")
    let mediaAudioBooksExpectation = expectation(description: "mediaAudioBooksxpectation-\(UUID().uuidString)")
    let mediaGamesExpectation = expectation(description: "mediaGamesxpectation-\(UUID().uuidString)")
    let mediaMoviesExpectation = expectation(description: "mediaMoviesxpectation-\(UUID().uuidString)")
    let mediaTVExpectation = expectation(description: "mediaTVxpectation-\(UUID().uuidString)")
    let softwareExpectation = expectation(description: "softwarexpectation-\(UUID().uuidString)")
    let sourceExpectation = expectation(description: "sourcexpectation-\(UUID().uuidString)")
    let setup = setup(
      commandHandlers: commandHandlers(
        config,
        zfsListOutput: Self.zfsDatasetsOutput,
        zfsListSnapshotOutput: Self.zfsSnapshotsOutput
      ),
      actionHandler: { action in
        switch action.command {
        case "echo nas_12tb/nas/documents total: 3, deleted: 0, kept: 3": documentsExpectation.fulfill()
        case "echo nas_12tb/nas/family total: 3, deleted: 0, kept: 3": familyExpectation.fulfill()
        case "echo nas_12tb/nas/media total: 3, deleted: 0, kept: 3": mediaExpectation.fulfill()
        case "echo nas_12tb/nas/media/audio_books total: 3, deleted: 0, kept: 3": mediaAudioBooksExpectation.fulfill()
        case "echo nas_12tb/nas/media/games total: 3, deleted: 0, kept: 3": mediaGamesExpectation.fulfill()
        case "echo nas_12tb/nas/media/movies total: 3, deleted: 0, kept: 3": mediaMoviesExpectation.fulfill()
        case "echo nas_12tb/nas/media/tv_comedy_documentaries total: 3, deleted: 0, kept: 3": mediaTVExpectation.fulfill()
        case "echo nas_12tb/nas/software total: 3, deleted: 0, kept: 3": softwareExpectation.fulfill()
        case "echo nas_12tb/nas/source total: 3, deleted: 0, kept: 3": sourceExpectation.fulfill()
        default: return
        }
        print("TEST \(action.command)")
      },
      config: config
    )
    try await setup.consolidator.consolidate()
    await fulfillment(
      of: [
        documentsExpectation,
        familyExpectation,
        mediaExpectation,
        mediaAudioBooksExpectation,
        mediaGamesExpectation,
        mediaMoviesExpectation,
        mediaTVExpectation,
        softwareExpectation,
        sourceExpectation,
      ],
      timeout: timeout
    )
  }
  
  func testThreeSnapshotsPerDayAreConsolidatedToSinglePerPeriod() async throws {
    try await testSnapshotConsolidation(
      upperBound: upperBound,
      daysPerSnapshot: 3,
      snapshotPeriods: 64,
      snapshotsPerDay: 3
    )
  }

  func testTwoSnapshotsPerDayAreConsolidatedToSinglePerPeriod() async throws {
    try await testSnapshotConsolidation(
      upperBound: upperBound,
      daysPerSnapshot: 3,
      snapshotPeriods: 64,
      snapshotsPerDay: 2
    )
  }

  func testOneSnapshotsPerDayAreConsolidatedToSinglePerPeriod() async throws {
    try await testSnapshotConsolidation(
      upperBound: upperBound,
      daysPerSnapshot: 3,
      snapshotPeriods: 64,
      snapshotsPerDay: 1
    )
  }

  private func testSnapshotConsolidation(
    upperBound: Date,
    daysPerSnapshot: UInt16,
    snapshotPeriods: UInt16,
    snapshotsPerDay: Int
  ) async throws {
    let config = makeConfig(
      snapshotPeriods: snapshotPeriods,
      daysPerSnapshot: daysPerSnapshot
    )
    let calendar = Calendar(identifier: .gregorian)
    let lowerBound = try XCTUnwrap(calendar.date(byAdding: .day, value: -Int(daysPerSnapshot * snapshotPeriods), to: upperBound))
    let dateRange = lowerBound..<upperBound
    let datasetName = Self.zfsDatasetsSingle[0]
    let snapshotsOutput = snapshotsPerDayForRange(
      snapshotsPerDay,
      forRange: dateRange,
      datasetName: datasetName,
      dateSeparator: config.dateSeparator
    )
    let snapshots = snapshotsOutput.split(separator: line()).map { String($0) }
    let snapshotsKept = snapshots.count / (snapshotsPerDay * Int(daysPerSnapshot))
    let snapshotsDeleted = snapshots.count - snapshotsKept
    let expectation = self.expectation(description: "expectation-\(UUID().uuidString)")
    let setup = setup(
      commandHandlers: commandHandlers(
        config,
        zfsListOutput: Self.zfsDatasetsOutputSingle,
        zfsListSnapshotOutput: snapshotsOutput
      ),
      actionHandler: { action in
        guard action.command.contains("echo \(datasetName) total: \(snapshots.count), deleted: \(snapshotsDeleted), kept: \(snapshotsKept)") else { return }
        expectation.fulfill()
      },
      config: config
    )
    try await setup.consolidator.consolidate()
    await fulfillment(of: [expectation], timeout: timeout)
  }

  private func snapshotsPerDayForRange(
    _ snapshotsPerDay: Int,
    forRange range: Range<Date>,
    datasetName: String,
    dateSeparator: String
  ) -> String {
    let timeBetweenSnapshots = TimeInterval.secondsPerDay / TimeInterval(snapshotsPerDay + 1)
    var date = range.upperBound
    var snapshots = ""
    while date >= range.lowerBound {
      var dateInDate = date
      for snapshotIndex in 0..<snapshotsPerDay {
        dateInDate = date.addingTimeInterval(-TimeInterval(snapshotIndex)*timeBetweenSnapshots)
        snapshots.append(line("\(datasetName)\(dateSeparator)\(dateFormatter.string(from: dateInDate))"))
      }
      date = calendar.date(byAdding: .day, value: -1, to: date)!
    }
    return snapshots
  }
}

extension ConsolidatorTest {
  private typealias Setup = (shell: MockShell, consolidator: Consolidator)

  private func setup(
    commandHandlers: [MockShell.CommandHandler] = [],
    actionHandler: MockShell.ActionHandler? = nil,
    config: Consolidator.Config? = nil
  ) -> Setup {
    let shell = MockShell(
      commandHandlers,
      actionHandler: actionHandler
    )
    let consolidator = Consolidator(
      shell: shell,
      config: config ?? ConsolidatorConfigTest.config(
        dateFormatter: dateFormatter,
        fileManager: .default
      ),
      calendar: calendar,
      dateFormatter: dateFormatter
    )
    return (shell, consolidator)
  }
}

extension ConsolidatorTest {
  private func commandHandlers(
    _ config: Consolidator.Config,
    zfsListOutput: String,
    zfsListSnapshotOutput: String
  ) -> [MockShell.CommandHandler] {
    [
      .sudo({ command in
        guard command == "zfs list -o name -H | grep \(config.datasetGrep)" else { return nil }
        return .standardOutput(zfsListOutput)
      }),
      .sudo({ command in
        guard command == "zfs list -o name -H -t snapshot" else { return nil }
        return .standardOutput(zfsListSnapshotOutput)
      }),
      .sudo({ command in
        let prefix = "zfs list -o name -H -t snapshot | grep "
        guard command.starts(with: prefix) else { return nil }
        let pattern = command.dropFirst(prefix.count)
        let output = zfsListSnapshotOutput.lines
          .filter { $0.contains(pattern) }
          .joined(separator: "\n")
        return .standardOutput(output)
      }),
      .sudo({ command in
        guard command.contains("zfs destroy ") else { return nil }
        return .standardOutput("")
      })
    ]
  }

  private static let zfsDatasets: [String] = zfsDatasetsOutput.lines
  private static let zfsDatasetsOutput: String = """
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

  private static let zfsDatasetsSingle = zfsDatasetsOutputSingle.lines
  private static let zfsDatasetsOutputSingle: String = """
    nas_12tb/nas/documents
    """

  private static let zfsSnapshots = zfsSnapshotsOutput.lines
  private static let zfsSnapshotsOutput: String = """
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

extension ConsolidatorTest {
  private func line(_ string: String = "") -> String {
    "\(string)\n"
  }
}
