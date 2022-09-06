import Foundation
import Shell
import XCTest

@testable import swift_zfs_tools

class ConsolidatorTest: XCTestCase {
  func testDeletionWhenSnapshotsOutOfRange() {
    let config = TestUtilities.consolidateConfig(
      period: ZFSTools.Consolidator.ConsolidatePeriod.ConsolidatePeriodBuilder()
        .snapshotPeriod(snapshots: 1)
        .with(days: 2)
        .snapshotPeriodComplete()
        .build()
    )
    let expectation = expectation(description: "expectation-\(UUID().uuidString)")
    let setup = setup(
      commandHandlers: commandHandlers(
        config,
        zfsListOutput: TestUtilities.zfsDatasetsOutput,
        zfsListSnapshotOutput: TestUtilities.zfsSnapshotsOutput
      ),
      actionHandler: { action in
        guard action.command.contains("echo kept 0, deleted 36 snapshots") else { return }
        print("TEST \(action.command)")
        expectation.fulfill()
      },
      config: config
    )
    setup.consolidator.consolidate()
    wait(for: [expectation], timeout: TestUtilities.timeout)
    XCTAssertFalse(setup.consolidator.isConsolidating)
  }

  func testKeepSnapshotsNotConsolidated() {
    let keepSnapshots = [
      "nas_12tb/nas/documents@20210101-020423",
      "nas_12tb/nas/documents@20210823-033128",
      "nas_12tb/nas/documents@20220801-235247"
    ]
    let config = TestUtilities.consolidateConfig(
      snapshotsNotConsolidated: keepSnapshots,
      period: ZFSTools.Consolidator.ConsolidatePeriod.ConsolidatePeriodBuilder()
        .snapshotPeriod(snapshots: 1)
        .with(days: 2)
        .snapshotPeriodComplete()
        .build()
    )
    let expectation = expectation(description: "expectation-\(UUID().uuidString)")
    let setup = setup(
      commandHandlers: commandHandlers(
        config,
        zfsListOutput: TestUtilities.zfsDatasetsOutput,
        zfsListSnapshotOutput: TestUtilities.zfsSnapshotsOutput
      ),
      actionHandler: { action in
        keepSnapshots.forEach {
          XCTAssertNotEqual("zfs destroy \($0)", action.command)
        }
        guard action.command.contains("echo kept 3, deleted 33 snapshots") else { return }
        print("TEST \(action.command)")
        expectation.fulfill()
      },
      config: config
    )
    setup.consolidator.consolidate()
    wait(for: [expectation], timeout: TestUtilities.timeout)
    XCTAssertFalse(setup.consolidator.isConsolidating)
  }

  func testSnapshotsAreKept() {
    let config = TestUtilities.consolidateConfig(
      period: ZFSTools.Consolidator.ConsolidatePeriod.ConsolidatePeriodBuilder(upperBound: TestUtilities.upperBound)
      .snapshotPeriod(snapshots: 24)
      .with(months: 1)
      .snapshotPeriodComplete()
      .build()
    )
    let expectation = expectation(description: "expectation-\(UUID().uuidString)")
    let setup = setup(
      commandHandlers: commandHandlers(
        config,
        zfsListOutput: TestUtilities.zfsDatasetsOutput,
        zfsListSnapshotOutput: TestUtilities.zfsSnapshotsOutput
      ),
      actionHandler: { action in
        guard action.command.contains("echo kept 36, deleted 0 snapshots") else { return }
        print("TEST \(action.command)")
        expectation.fulfill()
      },
      config: config
    )
    setup.consolidator.consolidate()
    wait(for: [expectation], timeout: TestUtilities.timeout)
    XCTAssertFalse(setup.consolidator.isConsolidating)
  }
  
  func testThreeSnapshotsPerDayAreConsolidatedToSinglePerPeriod() throws {
    try testSnapshotConsolidation(
      upperBound: Date(),
      daysPerSnapshot: 3,
      snapshotPeriods: 64,
      snapshotsPerDay: 3
    )
  }

  func testTwoSnapshotsPerDayAreConsolidatedToSinglePerPeriod() throws {
    try testSnapshotConsolidation(
      upperBound: Date(),
      daysPerSnapshot: 3,
      snapshotPeriods: 64,
      snapshotsPerDay: 2
    )
  }

  func testOneSnapshotsPerDayAreConsolidatedToSinglePerPeriod() throws {
    try testSnapshotConsolidation(
      upperBound: Date(),
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
  ) throws {
    let config = TestUtilities.consolidateConfig(
      datasetMatch: TestUtilities.zfsDatasetsSingle[0],
      period: ZFSTools.Consolidator.ConsolidatePeriod.ConsolidatePeriodBuilder()
        .snapshotPeriod(snapshots: snapshotPeriods)
        .with(days: daysPerSnapshot)
        .snapshotPeriodComplete()
        .build()
    )
    let calendar = Calendar(identifier: .gregorian)
    let lowerBound = try XCTUnwrap(calendar.date(byAdding: .day, value: -Int(daysPerSnapshot * snapshotPeriods), to: upperBound))
    let dateRange = lowerBound..<upperBound
    let snapshotsOutput = TestUtilities.snapshotsPerDayForRange(
      snapshotsPerDay,
      forRange: dateRange,
      datasetName: TestUtilities.zfsDatasetsSingle[0],
      config: config
    )
    let snapshots = snapshotsOutput.splitXP(by: TestUtilities.line())
    let snapshotsKept = snapshots.count / (snapshotsPerDay * Int(daysPerSnapshot))
    let snapshotsDeleted = snapshots.count - snapshotsKept
    let expectation = expectation(description: "expectation-\(UUID().uuidString)")
    let setup = setup(
      commandHandlers: commandHandlers(
        config,
        zfsListOutput: TestUtilities.zfsDatasetsOutputSingle,
        zfsListSnapshotOutput: snapshotsOutput
      ),
      actionHandler: { action in
        guard action.command == "echo kept \(snapshotsKept), deleted \(snapshotsDeleted) snapshots" else { return }
        print("TEST \(action.command)")
        expectation.fulfill()
      },
      config: config
    )
    setup.consolidator.consolidate()
    wait(for: [expectation], timeout: TestUtilities.timeout)
    XCTAssertFalse(setup.consolidator.isConsolidating)
  }
}

extension ConsolidatorTest {
  private typealias Setup = (shell: MockShell, consolidator: ZFSTools.Consolidator)

  private func setup(
    commandHandlers: [MockShell.CommandHandler] = [],
    actionHandler: MockShell.ActionHandler? = nil,
    calendar: Calendar = .current,
    config: ZFSTools.Action.Config.Consolidate = TestUtilities.consolidateConfig(),
    snapshotDateFormat: String = ZFSTools.Constants.snapshotDateFormat
  ) -> Setup {
    let shell = MockShell(
      commandHandlers,
      actionHandler: actionHandler
    )
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.timeZone = calendar.timeZone
    dateFormatter.dateFormat = snapshotDateFormat
    let consolidator = ZFSTools.Consolidator(
      shell: shell,
      config: config,
      calendar: calendar,
      dateFormatter: dateFormatter,
      consolidateNow: false
    )
    return (shell, consolidator)
  }
}

extension ConsolidatorTest {
  private func commandHandlers(
    _ config: ZFSTools.Action.Config.Consolidate,
    zfsListOutput: String,
    zfsListSnapshotOutput: String
  ) -> [MockShell.CommandHandler] {
    [
      .sudo({ command, password in
        guard password == config.password,
              command == "zfs list -o name -H | grep \(config.datasetMatch)" else { return nil }
        return .output(zfsListOutput)
      }),
      .sudo({ command, password in
        guard password == config.password,
              command == "zfs list -t snapshot -o name -H" else { return nil }
        return .output(zfsListSnapshotOutput)
      }),
      .sudo({ command, password in
        let prefix = "zfs list -t snapshot -o name -H | grep "
        guard password == config.password,
              command.starts(with: prefix) else { return nil }
        let pattern = command.dropFirst(prefix.count)
        let output = zfsListSnapshotOutput.lines
          .filter { $0.contains(pattern) }
          .joined(separator: "\n")
        return .output(output)
      }),
      .sudo({ command, password in
        guard password == config.password,
              command.contains("zfs destroy ") else { return nil }
        return .output("")
      })
    ]
  }
}
