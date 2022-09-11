import Foundation
import Shell
import XCTest

@testable import swift_zfs_tools

class SyncerTest: XCTestCase {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    return calendar
  }()

  func testSync() {
    let config = TestUtilities.syncConfig()
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.timeZone = calendar.timeZone

    let expectationDelete = expectation(description: "expectationDelete-\(UUID().uuidString)")
    var snapshotsToDelete = Self.zfsSnapshotsDeleted
    var snapshotsDeleted = 0
    func handleDeleteSnapshotCommand(_ string: String) {
      if string.starts(with: "\(config.sshLoginTest) zfs destroy ") {
        snapshotsDeleted += 1
      }
      for snapshotToDelete in snapshotsToDelete {
        guard string == "\(config.sshLoginTest) zfs destroy \(snapshotToDelete)" else { continue }
        snapshotsToDelete.removeAll(where: { $0 == snapshotToDelete })
        guard snapshotsToDelete.isEmpty else { continue }
        expectationDelete.fulfill()
      }
    }
    if snapshotsToDelete.count == 0 {
      expectationDelete.fulfill()
    }

    let expectationSend = expectation(description: "expectationSend-\(UUID().uuidString)")
    var snapshotsToSend = Self.zfsSnapshotsSent
    var snapshotsSent = 0
    func handleSendSnapshotCommand(_ string: String) {
      if string.starts(with: "zfs send -i") {
        snapshotsSent += 1
      }
      for snapshotToSend in snapshotsToSend {
        guard string == "zfs send -i nas_12tb/nas/documents@20220805-000000 nas_12tb/nas/documents@20220806-000000 | \(config.sshLoginTest) zfs recv -F nas_12tb/nas/documents@20220806-000000" ||
              string == "zfs send -i nas_12tb/nas/documents@20220806-000000 nas_12tb/nas/documents@20220807-000000 | \(config.sshLoginTest) zfs recv -F nas_12tb/nas/documents@20220807-000000" else { continue }
        snapshotsToSend.removeAll(where: { $0 == snapshotToSend })
        guard snapshotsToSend.isEmpty else { continue }
        expectationSend.fulfill()
      }
    }

    let setup = setup(
      actionHandler: { action in
        print("TEST: \(action.command)")
        handleDeleteSnapshotCommand(action.command)
        handleSendSnapshotCommand(action.command)
      },
      dateFormatter: dateFormatter,
      config: config
    )
    setup.syncer.sync()
    wait(
      for: [
        expectationDelete,
        expectationSend
      ],
      timeout: TestUtilities.timeout
    )
    XCTAssertFalse(setup.syncer.isSyncing)
    XCTAssertEqual(Self.zfsSnapshotsDeleted.count, snapshotsDeleted)
    XCTAssertEqual(Self.zfsSnapshotsSent.count, snapshotsSent)
  }

  func testSyncOnlyFutureAreSent() {
    let config = TestUtilities.syncConfig()
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.timeZone = calendar.timeZone

    let expectationDelete = expectation(description: "expectationDelete-\(UUID().uuidString)")
    var snapshotsToDelete = Self.zfsSnapshotsOnlyFutureDeleted
    var snapshotsDeleted = 0
    func handleDeleteSnapshotCommand(_ string: String) {
      if string.starts(with: "\(config.sshLoginTest) zfs destroy ") {
        snapshotsDeleted += 1
      }
      for snapshotToDelete in snapshotsToDelete {
        guard string == "\(config.sshLoginTest) zfs destroy \(snapshotToDelete)" else { continue }
        snapshotsToDelete.removeAll(where: { $0 == snapshotToDelete })
        guard snapshotsToDelete.isEmpty else { continue }
        expectationDelete.fulfill()
      }
    }
    if snapshotsToDelete.count == 0 {
      expectationDelete.fulfill()
    }

    let expectationSend = expectation(description: "expectationSend-\(UUID().uuidString)")
    var snapshotsToSend = Self.zfsSnapshotsOnlyFutureSent
    var snapshotsSent = 0
    func handleSendSnapshotCommand(_ string: String) {
      if string.starts(with: "zfs send") {
        snapshotsSent += 1
      }
      for snapshotToSend in snapshotsToSend {
        guard string == "zfs send -i nas_12tb/nas/documents@20220805-000000 nas_12tb/nas/documents@20220806-000000 | \(config.sshLoginTest) zfs recv -F nas_12tb/nas/documents@20220806-000000" ||
              string == "zfs send -i nas_12tb/nas/documents@20220806-000000 nas_12tb/nas/documents@20220807-000000 | \(config.sshLoginTest) zfs recv -F nas_12tb/nas/documents@20220807-000000" else { continue }
        snapshotsToSend.removeAll(where: { $0 == snapshotToSend })
        guard snapshotsToSend.isEmpty else { continue }
        expectationSend.fulfill()
      }
    }

    let setup = setup(
      actionHandler: { action in
        print("TEST: \(action.command)")
        handleDeleteSnapshotCommand(action.command)
        handleSendSnapshotCommand(action.command)
      },
      dateFormatter: dateFormatter,
      config: config,
      snapshotsLocal: Self.zfsSnapshotsOnlyFutureLocal,
      snapshotsRemote: Self.zfsSnapshotsOnlyFutureRemote
    )
    setup.syncer.sync()
    wait(
      for: [
        expectationDelete,
        expectationSend
      ],
      timeout: TestUtilities.timeout
    )
    XCTAssertFalse(setup.syncer.isSyncing)
    XCTAssertEqual(Self.zfsSnapshotsOnlyFutureDeleted.count, snapshotsDeleted)
    XCTAssertEqual(Self.zfsSnapshotsOnlyFutureSent.count, snapshotsSent)
  }

  func testSyncResetsIncremental() {
    let config = TestUtilities.syncConfig()
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.timeZone = calendar.timeZone

    let expectationDelete = expectation(description: "expectationDelete-\(UUID().uuidString)")
    var snapshotsToDelete = Self.zfsSnapshotsResetsIncrementalDeleted
    var snapshotsDeleted = 0
    func handleDeleteSnapshotCommand(_ string: String) {
      if string.starts(with: "\(config.sshLoginTest) zfs destroy ") {
        snapshotsDeleted += 1
      }
      for snapshotToDelete in snapshotsToDelete {
        guard string == "\(config.sshLoginTest) zfs destroy \(snapshotToDelete)" else { continue }
        snapshotsToDelete.removeAll(where: { $0 == snapshotToDelete })
        guard snapshotsToDelete.isEmpty else { continue }
        expectationDelete.fulfill()
      }
    }
    if snapshotsToDelete.count == 0 {
      expectationDelete.fulfill()
    }

    let expectationSend = expectation(description: "expectationSend-\(UUID().uuidString)")
    var snapshotsToSend = Self.zfsSnapshotsResetsIncrementalSent
    var snapshotsSent = 0
    func handleSendSnapshotCommand(_ string: String) {
      if string.starts(with: "zfs send") {
        snapshotsSent += 1
      }
      for snapshotToSend in snapshotsToSend {
        guard string == "zfs send -i nas_12tb/nas/documents@20220803-000000 nas_12tb/nas/documents@20220806-000000 | \(config.sshLoginTest) zfs recv -F nas_12tb/nas/documents@20220806-000000" ||
              string == "zfs send -i nas_12tb/nas/documents@20220806-000000 nas_12tb/nas/documents@20220807-000000 | \(config.sshLoginTest) zfs recv -F nas_12tb/nas/documents@20220807-000000" else { continue }
        snapshotsToSend.removeAll(where: { $0 == snapshotToSend })
        guard snapshotsToSend.isEmpty else { continue }
        expectationSend.fulfill()
      }
    }

    let setup = setup(
      actionHandler: { action in
        print("TEST: \(action.command)")
        handleDeleteSnapshotCommand(action.command)
        handleSendSnapshotCommand(action.command)
      },
      dateFormatter: dateFormatter,
      config: config,
      snapshotsLocal: Self.zfsSnapshotsResetsIncrementalLocal,
      snapshotsRemote: Self.zfsSnapshotsResetsIncrementalRemote
    )
    setup.syncer.sync()
    wait(
      for: [
        expectationDelete,
        expectationSend
      ],
      timeout: TestUtilities.timeout
    )
    XCTAssertFalse(setup.syncer.isSyncing)
    XCTAssertEqual(Self.zfsSnapshotsResetsIncrementalDeleted.count, snapshotsDeleted)
    XCTAssertEqual(Self.zfsSnapshotsResetsIncrementalSent.count, snapshotsSent)
  }

  func testSyncTotalReset() {
    let config = TestUtilities.syncConfig()
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.timeZone = calendar.timeZone

    let expectationDelete = expectation(description: "expectationDelete-\(UUID().uuidString)")
    var snapshotsToDelete = Self.zfsSnapshotsTotalResetDeleted
    var snapshotsDeleted = 0
    func handleDeleteSnapshotCommand(_ string: String) {
      if string.starts(with: "\(config.sshLoginTest) zfs destroy ") {
        snapshotsDeleted += 1
      }
      for snapshotToDelete in snapshotsToDelete {
        guard string == "\(config.sshLoginTest) zfs destroy \(snapshotToDelete)" else { continue }
        snapshotsToDelete.removeAll(where: { $0 == snapshotToDelete })
        guard snapshotsToDelete.isEmpty else { continue }
        expectationDelete.fulfill()
      }
    }
    if snapshotsToDelete.count == 0 {
      expectationDelete.fulfill()
    }

    let expectationSend = expectation(description: "expectationSend-\(UUID().uuidString)")
    var snapshotsToSend = Self.zfsSnapshotsTotalResetSent
    var snapshotsSent = 0
    func handleSendSnapshotCommand(_ string: String) {
      if string.starts(with: "zfs send") {
        snapshotsSent += 1
      }
      for snapshotToSend in snapshotsToSend {
        guard string == "zfs send nas_12tb/nas/documents@20220806-000000 | \(config.sshLoginTest) zfs recv -F nas_12tb/nas/documents@20220806-000000" ||
              string == "zfs send -i nas_12tb/nas/documents@20220806-000000 nas_12tb/nas/documents@20220807-000000 | \(config.sshLoginTest) zfs recv -F nas_12tb/nas/documents@20220807-000000" else { continue }
        snapshotsToSend.removeAll(where: { $0 == snapshotToSend })
        guard snapshotsToSend.isEmpty else { continue }
        expectationSend.fulfill()
      }
    }

    let setup = setup(
      actionHandler: { action in
        print("TEST: \(action.command)")
        handleDeleteSnapshotCommand(action.command)
        handleSendSnapshotCommand(action.command)
      },
      dateFormatter: dateFormatter,
      config: config,
      snapshotsLocal: Self.zfsSnapshotsTotalResetLocal,
      snapshotsRemote: Self.zfsSnapshotsTotalResetRemote
    )
    setup.syncer.sync()
    wait(
      for: [
        expectationDelete,
        expectationSend
      ],
      timeout: TestUtilities.timeout
    )
    XCTAssertFalse(setup.syncer.isSyncing)
    XCTAssertEqual(Self.zfsSnapshotsTotalResetDeleted.count, snapshotsDeleted)
    XCTAssertEqual(Self.zfsSnapshotsTotalResetSent.count, snapshotsSent)
  }
}

private extension ZFSTools.Action.Config.Sync {
  var sshLoginTest: String {
    "ssh -p \(sshPort) -i \(sshKeyPath) \(sshUser)@\(sshIP)"
  }
}

extension SyncerTest {
  private typealias Setup = (shell: MockShell, syncer: ZFSTools.Syncer, dateFormatter: DateFormatter)

  private func setup(
    commandHandlers: [MockShell.CommandHandler]? = nil,
    actionHandler: MockShell.ActionHandler? = nil,
    dateFormatter: DateFormatter,
    config: ZFSTools.Action.Config.Sync = TestUtilities.syncConfig(),
    snapshotDateFormat: String = ZFSTools.Constants.snapshotDateFormat,
    listLocal: String = SyncerTest.zfsDatasets,
    listRemote: String = SyncerTest.zfsDatasets,
    snapshotsLocal: String = SyncerTest.zfsSnapshotsLocal,
    snapshotsRemote: String = SyncerTest.zfsSnapshotsRemote
  ) -> Setup {
    let shell = MockShell(
      commandHandlers ?? self.commandHandlers(
        config,
        listLocal: listLocal,
        listRemote: listRemote,
        snapshotsLocal: snapshotsLocal,
        snapshotsRemote: snapshotsRemote
      ),
      actionHandler: actionHandler
    )
    dateFormatter.dateFormat = snapshotDateFormat
    let syncer = ZFSTools.Syncer(
      shell: shell,
      config: config,
      dateFormatter: dateFormatter,
      syncNow: false
    )
    return (shell, syncer, dateFormatter)
  }
}

extension SyncerTest {
  private func commandHandlers(
    _ config: ZFSTools.Action.Config.Sync,
    listLocal: String,
    listRemote: String,
    snapshotsLocal: String,
    snapshotsRemote: String
  ) -> [MockShell.CommandHandler] {
    return [
      // zfsCommandDestroyRemote
      .sudo({ command in
        guard command.contains("\(config.sshLoginTest) \(ZFSTools.ZFSCommand.destroy(""))") else { return nil }
        return .output("")
      }),
      // zfsCommandListLocal
      .sudo({ command in
        guard command.contains(ZFSTools.ZFSCommand.list(matching: config.datasetMatch)) else { return nil }
        var output = listLocal.lines
        if let datasetMatch = config.datasetMatch {
          let split = command.splitXP(by: " | grep \(datasetMatch)")
          if split.count == 2 {
            let split2 = String(split[1]).splitXP(by: "| grep ")
            if split2.count == 2 {
              let filter = String(split2[1])
              output = output.filter { $0.contains(filter) }
            }
          }
        }
        return .output(output.joined(separator: TestUtilities.line()))
      }),
      // zfsCommandListRemote
      .sudo({ command in
        guard command.contains("\(config.sshLoginTest) \(ZFSTools.ZFSCommand.list(matching: config.datasetMatch))") else { return nil }
        var output = listRemote.lines
        if let datasetMatch = config.datasetMatch {
          let split = command.splitXP(by: " | grep \(datasetMatch)")
          if split.count == 2 {
            let split2 = String(split[1]).splitXP(by: "| grep ")
            if split2.count == 2 {
              let filter = String(split2[1])
              output = output.filter { $0.contains(filter) }
            }
          }
        }
        return .output(output.joined(separator: TestUtilities.line()))
      }),
      // zfsCommandListSnapshotsLocal
      .sudo({ command in
        guard command == ZFSTools.ZFSCommand.listSnapshots(matching: config.datasetMatch) else { return nil }
        var output = snapshotsLocal.lines
        if let datasetMatch = config.datasetMatch {
          let split = command.splitXP(by: " | grep \(datasetMatch)")
          if split.count == 2 {
            let split2 = String(split[1]).splitXP(by: "| grep ")
            if split2.count == 2 {
              let filter = String(split2[1])
              output = output.filter { $0.contains(filter) }
            }
          }
        }
        return .output(output.joined(separator: TestUtilities.line()))
      }),
      // zfsCommandListSnapshotsRemote
      .sudo({ command in
        guard command == "\(config.sshLoginTest) \(ZFSTools.ZFSCommand.listSnapshots(matching: config.datasetMatch))" else { return nil }
        var output = snapshotsRemote.lines
        if let datasetMatch = config.datasetMatch {
          let split = command.splitXP(by: " | grep \(datasetMatch)")
          if split.count == 2 {
            let split2 = String(split[1]).splitXP(by: "| grep ")
            if split2.count == 2 {
              let filter = String(split2[1])
              output = output.filter { $0.contains(filter) }
            }
          }
        }
        return .output(output.joined(separator: TestUtilities.line()))
      }),
      // zfsCommandSend
      .sudo({ command in
        guard command.contains("zfs send") else { return nil }
        return .output("")
      })
    ]
  }
}

extension SyncerTest {
  private static let zfsDatasets = """
    nas_12tb/nas/documents
    """
  private static let zfsSnapshotsLocal = """
    nas_12tb/nas/documents@20220807-000000
    nas_12tb/nas/documents@20220806-000000
    nas_12tb/nas/documents@20220805-000000
    nas_12tb/nas/documents@20220803-000000
    nas_12tb/nas/documents@20220801-000000
    """
  private static let zfsSnapshotsRemote = """
    nas_12tb/nas/documents@20220805-000000
    nas_12tb/nas/documents@20220804-000000
    nas_12tb/nas/documents@20220803-000000
    nas_12tb/nas/documents@20220802-000000
    nas_12tb/nas/documents@20220801-000000
    """
  private static let zfsSnapshotsDeleted = [
    "nas_12tb/nas/documents@20220804-000000",
    "nas_12tb/nas/documents@20220802-000000"
  ]

  private static let zfsSnapshotsSent = [
    "nas_12tb/nas/documents@20220807-000000",
    "nas_12tb/nas/documents@20220806-000000"
  ]
}

extension SyncerTest {
  private static let zfsSnapshotsOnlyFutureLocal = """
    nas_12tb/nas/documents@20220807-000000
    nas_12tb/nas/documents@20220806-000000
    nas_12tb/nas/documents@20220805-000000
    nas_12tb/nas/documents@20220803-000000
    nas_12tb/nas/documents@20220801-000000
    """
  private static let zfsSnapshotsOnlyFutureRemote = """
    nas_12tb/nas/documents@20220805-000000
    nas_12tb/nas/documents@20220801-000000
    """
  private static let zfsSnapshotsOnlyFutureDeleted = [String]()

  private static let zfsSnapshotsOnlyFutureSent = [
    "nas_12tb/nas/documents@20220807-000000",
    "nas_12tb/nas/documents@20220806-000000"
  ]
}

extension SyncerTest {
  private static let zfsSnapshotsResetsIncrementalLocal = """
    nas_12tb/nas/documents@20220807-000000
    nas_12tb/nas/documents@20220806-000000
    nas_12tb/nas/documents@20220803-000000
    nas_12tb/nas/documents@20220801-000000
    """
  private static let zfsSnapshotsResetsIncrementalRemote = """
    nas_12tb/nas/documents@20220805-000000
    nas_12tb/nas/documents@20220804-000000
    nas_12tb/nas/documents@20220803-000000
    nas_12tb/nas/documents@20220802-000000
    nas_12tb/nas/documents@20220801-000000
    """
  private static let zfsSnapshotsResetsIncrementalDeleted = [
    "nas_12tb/nas/documents@20220805-000000",
    "nas_12tb/nas/documents@20220804-000000",
    "nas_12tb/nas/documents@20220802-000000"
  ]

  private static let zfsSnapshotsResetsIncrementalSent = [
    "nas_12tb/nas/documents@20220807-000000",
    "nas_12tb/nas/documents@20220806-000000"
  ]
}

extension SyncerTest {
  private static let zfsSnapshotsTotalResetLocal = """
    nas_12tb/nas/documents@20220807-000000
    nas_12tb/nas/documents@20220806-000000
    """
  private static let zfsSnapshotsTotalResetRemote = """
    nas_12tb/nas/documents@20220805-000000
    nas_12tb/nas/documents@20220804-000000
    nas_12tb/nas/documents@20220803-000000
    nas_12tb/nas/documents@20220802-000000
    nas_12tb/nas/documents@20220801-000000
    """
  private static let zfsSnapshotsTotalResetDeleted = [
    "nas_12tb/nas/documents@20220805-000000",
    "nas_12tb/nas/documents@20220804-000000",
    "nas_12tb/nas/documents@20220803-000000",
    "nas_12tb/nas/documents@20220802-000000",
    "nas_12tb/nas/documents@20220801-000000"
  ]

  private static let zfsSnapshotsTotalResetSent = [
    "nas_12tb/nas/documents@20220807-000000",
    "nas_12tb/nas/documents@20220806-000000"
  ]
}
