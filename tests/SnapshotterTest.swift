import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

class SnapshotterTest: XCTestCase {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    return calendar
  }()

  private lazy var dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = Defaults.dateFormat
    dateFormatter.calendar = calendar
    return dateFormatter
  }()

  private let snapshotDate = ConsolidatorConfigTest.defaultConfigDate

  private let timeout = TimeInterval(60)

  func testSnapshot() async throws {
    let config = SnapshotterConfigTest.snapshotConfig(recursive: false, execute: true)
    let expectation = expectation(description: "expectation-\(UUID().uuidString)")
    let setup = setup(
      commandHandlers: commandHandlers(config),
      actionHandler: { action in
        guard action.command == "zfs snapshot \(SnapshotterConfigTest.defaultDataset)\(Defaults.dateSeparator)\(self.dateFormatter.string(from: self.snapshotDate))" else { return }
        print("TEST: \(action.command)")
        expectation.fulfill()
      },
      config: config
    )
    try await setup.snapshotter.snapshot()
    await fulfillment(of: [expectation], timeout: timeout)
  }

  func testSnapshotRecursive() async throws {
    let config = SnapshotterConfigTest.snapshotConfig(recursive: true, execute: true)
    let expectation = expectation(description: "expectation-\(UUID().uuidString)")
    let setup = setup(
      commandHandlers: commandHandlers(config),
      actionHandler: { action in
        guard action.command == "zfs snapshot -r \(SnapshotterConfigTest.defaultDataset)\(Defaults.dateSeparator)\(self.dateFormatter.string(from: self.snapshotDate))" else { return }
        print("TEST: \(action.command)")
        expectation.fulfill()
      },
      config: config
    )
    try await setup.snapshotter.snapshot()
    await fulfillment(of: [expectation], timeout: timeout)
  }
}

extension SnapshotterTest {
  private typealias Setup = (shell: MockShell, snapshotter: Snapshotter, dateFormatter: DateFormatter)

  private func setup(
    commandHandlers: [MockShell.CommandHandler]? = nil,
    actionHandler: MockShell.ActionHandler? = nil,
    config: Snapshotter.Config = SnapshotterConfigTest.defaultConfig
  ) -> Setup {
    let shell = MockShell(
      commandHandlers ?? self.commandHandlers(config),
      actionHandler: actionHandler
    )
    let snapshotter = Snapshotter(
      shell: shell,
      config: config,
      dateFormatter: dateFormatter,
      date: { self.snapshotDate }
    )

    return (shell, snapshotter, dateFormatter)
  }
}

extension SnapshotterTest {
  private func commandHandlers(_ config: Snapshotter.Config) -> [MockShell.CommandHandler] {
    [
      .sudo { command in
        guard command.contains("zfs snapshot ") else { return nil }
        return .standardOutput("")
      },
      .sudo { command in
        guard !command.contains("zfs snapshot ") else { return nil }
        return .standardError("")
      },
    ]
  }
}
