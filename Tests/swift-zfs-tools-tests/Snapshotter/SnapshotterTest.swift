import Foundation
import Shell
import XCTest

@testable import swift_zfs_tools

class SnapshotterTest: XCTestCase {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    return calendar
  }()

  func testSnapshot() {
    let config = TestUtilities.snapshotConfig(recursive: false)
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.timeZone = calendar.timeZone
    let expectation = expectation(description: "expectation-\(UUID().uuidString)")
    let setup = setup(
      commandHandlers: commandHandlers(config),
      actionHandler: { action in
        guard action.command == "zfs snapshot \(TestUtilities.datasetMatch)\(ZFSTools.Constants.snapshotDateSeparator)\(dateFormatter.string(from: TestUtilities.snapshotDate))" else { return }
        print("TEST \(action.command)")
        expectation.fulfill()
      },
      dateFormatter: dateFormatter,
      config: config
    )
    setup.snapshotter.snapshot()
    wait(for: [expectation], timeout: TestUtilities.timeout)
    XCTAssertFalse(setup.snapshotter.isSnapshotting)
  }

  func testSnapshotRecursive() {
    let config = TestUtilities.snapshotConfig(recursive: true)
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.timeZone = calendar.timeZone
    let expectation = expectation(description: "expectation-\(UUID().uuidString)")
    let setup = setup(
      commandHandlers: commandHandlers(config),
      actionHandler: { action in
        guard action.command == "zfs snapshot -r \(TestUtilities.datasetMatch)\(ZFSTools.Constants.snapshotDateSeparator)\(dateFormatter.string(from: TestUtilities.snapshotDate))" else { return }
        print("TEST \(action.command)")
        expectation.fulfill()
      },
      dateFormatter: dateFormatter,
      config: config
    )
    setup.snapshotter.snapshot()
    wait(for: [expectation], timeout: TestUtilities.timeout)
    XCTAssertFalse(setup.snapshotter.isSnapshotting)
  }
}

extension SnapshotterTest {
  private typealias Setup = (shell: MockShell, snapshotter: ZFSTools.Snapshotter, dateFormatter: DateFormatter)

  private func setup(
    commandHandlers: [MockShell.CommandHandler]? = nil,
    actionHandler: MockShell.ActionHandler? = nil,
    dateFormatter: DateFormatter,
    config: ZFSTools.Action.Config.Snapshot = TestUtilities.snapshotConfig(),
    snapshotDateFormat: String = ZFSTools.Constants.snapshotDateFormat
  ) -> Setup {
    let shell = MockShell(
      commandHandlers ?? self.commandHandlers(config),
      actionHandler: actionHandler
    )
    dateFormatter.dateFormat = snapshotDateFormat
    let snapshotter = ZFSTools.Snapshotter(
      shell: shell,
      config: config,
      date: { TestUtilities.snapshotDate },
      dateFormatter: dateFormatter,
      snapshotNow: false
    )
    return (shell, snapshotter, dateFormatter)
  }
}

extension SnapshotterTest {
  private func commandHandlers(_ config: ZFSTools.Action.Config.Snapshot) -> [MockShell.CommandHandler] {
    [
      .sudo({ command, password in
        guard password == config.password,
              command.contains("zfs snapshot ") else { return nil }
        return .output("")
      }),
      .sudo({ command, password in
        guard password == config.password,
              !command.contains("zfs snapshot ") else { return nil }
        return .error("")
      })
    ]
  }
}
