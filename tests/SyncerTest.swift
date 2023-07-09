import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

class SyncerTest: XCTestCase {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    return calendar
  }()

  private lazy var dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.timeZone = calendar.timeZone
    return dateFormatter
  }()

  private let timeout = TimeInterval(60)

  func testSync() async throws {
    let config = SyncerConfigTest.syncConfig(execute: true)

    let deleteHandler = DeleteSnapshotHandler(
      sshLogin: config.sshLoginTest,
      snapshotsToDelete: Self.zfsSnapshotsDeleted
    )

    let syncHandler = SendSnapshotHandler(
      sshLogin: config.sshLoginTest,
      expectedSends: [
        .incremental(date: "20220806-000000", incrementalDate: "20220805-000000"),
        .incremental(date: "20220807-000000", incrementalDate: "20220806-000000"),
      ]
    )

    let setup = setup(
      actionHandler: { action in
        print("TEST: \(action.command)")
        Task {
          await deleteHandler.handleDeleteSnapshotCommand(action.command)
          await syncHandler.handleSendSnapshotCommand(action.command)
        }
      },
      config: config
    )
    try await setup.syncer.sync()
    await fulfillment(
      of: [
        deleteHandler.expectation,
        syncHandler.expectation
      ],
      timeout: timeout
    )
  }

  func testSyncOnlyFutureAreSent() async throws {
    let config = SyncerConfigTest.syncConfig(execute: true)

    let deleteHandler = DeleteSnapshotHandler(
      sshLogin: config.sshLoginTest,
      snapshotsToDelete: Self.zfsSnapshotsOnlyFutureDeleted
    )

    let syncHandler = SendSnapshotHandler(
      sshLogin: config.sshLoginTest,
      expectedSends: [
        .incremental(date: "20220806-000000", incrementalDate: "20220805-000000"),
        .incremental(date: "20220807-000000", incrementalDate: "20220806-000000"),
      ]
    )

    let setup = setup(
      actionHandler: { action in
        print("TEST: \(action.command)")
        Task {
          await deleteHandler.handleDeleteSnapshotCommand(action.command)
          await syncHandler.handleSendSnapshotCommand(action.command)
        }
      },
      config: config,
      snapshotsLocal: Self.zfsSnapshotsOnlyFutureLocal,
      snapshotsRemote: Self.zfsSnapshotsOnlyFutureRemote
    )
    try await setup.syncer.sync()
    await fulfillment(
      of: [
        deleteHandler.expectation,
        syncHandler.expectation,
      ],
      timeout: timeout
    )
  }

  func testSyncResetsIncremental() async throws {
    let config = SyncerConfigTest.syncConfig(execute: true)

    let deleteHandler = DeleteSnapshotHandler(
      sshLogin: config.sshLoginTest,
      snapshotsToDelete: Self.zfsSnapshotsResetsIncrementalDeleted
    )

    let syncHandler = SendSnapshotHandler(
      sshLogin: config.sshLoginTest,
      expectedSends: [
        .incremental(date: "20220806-000000", incrementalDate: "20220803-000000"),
        .incremental(date: "20220807-000000", incrementalDate: "20220806-000000"),
      ]
    )

    let setup = setup(
      actionHandler: { action in
        print("TEST: \(action.command)")
        Task {
          await deleteHandler.handleDeleteSnapshotCommand(action.command)
          await syncHandler.handleSendSnapshotCommand(action.command)
        }
      },
      config: config,
      snapshotsLocal: Self.zfsSnapshotsResetsIncrementalLocal,
      snapshotsRemote: Self.zfsSnapshotsResetsIncrementalRemote
    )
    try await setup.syncer.sync()
    await fulfillment(
      of: [
        deleteHandler.expectation,
        syncHandler.expectation,
      ],
      timeout: timeout
    )
  }

  func testSyncTotalReset() async throws {
    let config = SyncerConfigTest.syncConfig(execute: true)

    let deleteHandler = DeleteSnapshotHandler(
      sshLogin: config.sshLoginTest,
      snapshotsToDelete: Self.zfsSnapshotsTotalResetDeleted
    )

    let syncHandler = SendSnapshotHandler(
      sshLogin: config.sshLoginTest,
      expectedSends: [
        .full(date: "20220806-000000"),
        .incremental(date: "20220807-000000", incrementalDate: "20220806-000000"),
      ]
    )

    let setup = setup(
      actionHandler: { action in
        print("TEST: \(action.command)")
        Task {
          await deleteHandler.handleDeleteSnapshotCommand(action.command)
          await syncHandler.handleSendSnapshotCommand(action.command)
        }
      },
      config: config,
      snapshotsLocal: Self.zfsSnapshotsTotalResetLocal,
      snapshotsRemote: Self.zfsSnapshotsTotalResetRemote
    )
    try await setup.syncer.sync()
    await fulfillment(
      of: [
        deleteHandler.expectation,
        syncHandler.expectation,
      ],
      timeout: timeout
    )
  }
}

private extension Syncer.Config {
  var sshLoginTest: String {
    "ssh -p \(sshPort) -i \(sshKeyPath) \(sshUser)@\(sshIP)"
  }
}

extension SyncerTest {
  private typealias Setup = (shell: MockShell, syncer: Syncer, dateFormatter: DateFormatter)

  private func setup(
    commandHandlers: [MockShell.CommandHandler]? = nil,
    actionHandler: MockShell.ActionHandler? = nil,
    config: Syncer.Config = SyncerConfigTest.defaultConfig,
    dateFormat: String = Defaults.dateFormat,
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
    dateFormatter.dateFormat = dateFormat
    let syncer = Syncer(
      shell: shell,
      config: config,
      dateFormatter: dateFormatter
    )
    return (shell, syncer, dateFormatter)
  }
}

extension SyncerTest {
  private func commandHandlers(
    _ config: Syncer.Config,
    listLocal: String,
    listRemote: String,
    snapshotsLocal: String,
    snapshotsRemote: String
  ) -> [MockShell.CommandHandler] {
    return [
      // zfsCommandDestroyRemote
      .sudo({ command in
        guard command.contains("\(config.sshLoginTest) \(ZFS.destroy(subject: "").command)") else { return nil }
        return .standardOutput("")
      }),
      // zfsCommandListLocal
      .sudo({ command in
        guard command.contains(ZFS.listDatasets(matching: config.datasetGrep).command) else { return nil }
        var output = listLocal.lines
        if let datasetGrep = config.datasetGrep {
          let split = command.split(separator: " | grep \(datasetGrep)")
          if split.count == 2 {
            let split2 = String(split[1]).split(separator: "| grep ")
            if split2.count == 2 {
              let filter = String(split2[1])
              output = output.filter { $0.contains(filter) }
            }
          }
        }
        return .standardOutput(output.joined(separator: String.lineSeparator))
      }),
      // zfsCommandListRemote
      .sudo({ command in
        guard command.contains("\(config.sshLoginTest) \(ZFS.listDatasets(matching: config.datasetGrep).command)") else { return nil }
        var output = listRemote.lines
        if let datasetGrep = config.datasetGrep {
          let split = command.split(separator: " | grep \(datasetGrep)")
          if split.count == 2 {
            let split2 = String(split[1]).split(separator: "| grep ")
            if split2.count == 2 {
              let filter = String(split2[1])
              output = output.filter { $0.contains(filter) }
            }
          }
        }
        return .standardOutput(output.joined(separator: String.lineSeparator))
      }),
      // zfsCommandListSnapshotsLocal
      .sudo({ command in
        guard command == ZFS.listSnapshotsInDataset(dataset: Self.documentsDataset, dateSeparator: Defaults.dateSeparator).command else { return nil }
        var output = snapshotsLocal.lines
        if let datasetGrep = config.datasetGrep {
          let split = command.split(separator: " | grep \(datasetGrep)")
          if split.count == 2 {
            let split2 = String(split[1]).split(separator: "| grep ")
            if split2.count == 2 {
              let filter = String(split2[1])
              output = output.filter { $0.contains(filter) }
            }
          }
        }
        return .standardOutput(output.joined(separator: String.lineSeparator))
      }),
      // zfsCommandListSnapshotsRemote
      .sudo({ command in
        guard command == "\(config.sshLoginTest) \(ZFS.listSnapshotsInDataset(dataset: Self.documentsDataset, dateSeparator: Defaults.dateSeparator).command)" else { return nil }
        var output = snapshotsRemote.lines
        if let datasetGrep = config.datasetGrep {
          let split = command.split(separator: " | grep \(datasetGrep)")
          if split.count == 2 {
            let split2 = String(split[1]).split(separator: "| grep ")
            if split2.count == 2 {
              let filter = String(split2[1])
              output = output.filter { $0.contains(filter) }
            }
          }
        }
        return .standardOutput(output.joined(separator: String.lineSeparator))
      }),
      // zfsCommandSend
      .sudo({ command in
        guard command.contains("zfs send") else { return nil }
        return .standardOutput("")
      })
    ]
  }
}

extension SyncerTest {
  private static let documentsDataset = "nas_12tb/nas/documents"

  private static let zfsDatasets = """
    \(documentsDataset)
    """
  private static let zfsSnapshotsLocal = """
    \(documentsDataset)@20220807-000000
    \(documentsDataset)@20220806-000000
    \(documentsDataset)@20220805-000000
    \(documentsDataset)@20220803-000000
    \(documentsDataset)@20220801-000000
    """
  private static let zfsSnapshotsRemote = """
    \(documentsDataset)@20220805-000000
    \(documentsDataset)@20220804-000000
    \(documentsDataset)@20220803-000000
    \(documentsDataset)@20220802-000000
    \(documentsDataset)@20220801-000000
    """
  private static let zfsSnapshotsDeleted = [
    "\(documentsDataset)@20220804-000000",
    "\(documentsDataset)@20220802-000000"
  ]
}

extension SyncerTest {
  private static let zfsSnapshotsOnlyFutureLocal = """
    \(documentsDataset)@20220807-000000
    \(documentsDataset)@20220806-000000
    \(documentsDataset)@20220805-000000
    \(documentsDataset)@20220803-000000
    \(documentsDataset)@20220801-000000
    """
  private static let zfsSnapshotsOnlyFutureRemote = """
    \(documentsDataset)@20220805-000000
    \(documentsDataset)@20220801-000000
    """
  private static let zfsSnapshotsOnlyFutureDeleted = [String]()
}

extension SyncerTest {
  private static let zfsSnapshotsResetsIncrementalLocal = """
    \(documentsDataset)@20220807-000000
    \(documentsDataset)@20220806-000000
    \(documentsDataset)@20220803-000000
    \(documentsDataset)@20220801-000000
    """
  private static let zfsSnapshotsResetsIncrementalRemote = """
    \(documentsDataset)@20220805-000000
    \(documentsDataset)@20220804-000000
    \(documentsDataset)@20220803-000000
    \(documentsDataset)@20220802-000000
    \(documentsDataset)@20220801-000000
    """
  private static let zfsSnapshotsResetsIncrementalDeleted = [
    "\(documentsDataset)@20220805-000000",
    "\(documentsDataset)@20220804-000000",
    "\(documentsDataset)@20220802-000000"
  ]

  private static let zfsSnapshotsResetsIncrementalSent = [
    "\(documentsDataset)@20220807-000000",
    "\(documentsDataset)@20220806-000000"
  ]
}

extension SyncerTest {
  private static let zfsSnapshotsTotalResetLocal = """
    \(documentsDataset)@20220807-000000
    \(documentsDataset)@20220806-000000
    """
  private static let zfsSnapshotsTotalResetRemote = """
    \(documentsDataset)@20220805-000000
    \(documentsDataset)@20220804-000000
    \(documentsDataset)@20220803-000000
    \(documentsDataset)@20220802-000000
    \(documentsDataset)@20220801-000000
    """
  private static let zfsSnapshotsTotalResetDeleted = [
    "\(documentsDataset)@20220805-000000",
    "\(documentsDataset)@20220804-000000",
    "\(documentsDataset)@20220803-000000",
    "\(documentsDataset)@20220802-000000",
    "\(documentsDataset)@20220801-000000"
  ]

  private static let zfsSnapshotsTotalResetSent = [
    "\(documentsDataset)@20220807-000000",
    "\(documentsDataset)@20220806-000000"
  ]
}

extension SyncerTest {
  private actor DeleteSnapshotHandler {
    let expectation: XCTestExpectation
    private let sshLogin: String
    private(set) var snapshotsToDelete: [String]

    public init(
      expectation: XCTestExpectation = XCTestExpectation(description: "\(String(describing: DeleteSnapshotHandler.self))-\(UUID().uuidString)"),
      sshLogin: String,
      snapshotsToDelete: [String]
    ) {
      self.expectation = expectation
      self.sshLogin = sshLogin
      self.snapshotsToDelete = snapshotsToDelete
      guard snapshotsToDelete.isEmpty else { return }
      expectation.fulfill()
    }

    func handleDeleteSnapshotCommand(_ string: String) {
      for snapshotToDelete in snapshotsToDelete {
        guard string == "\(sshLogin) zfs destroy \(snapshotToDelete)" else { continue }
        snapshotsToDelete.removeAll(where: { $0 == snapshotToDelete })
        guard snapshotsToDelete.isEmpty else { continue }
        expectation.fulfill()
      }
    }
  }
}

extension SyncerTest {
  private actor SendSnapshotHandler {
    let expectation: XCTestExpectation

    private var expectedStrings: [String]

    public init(
      expectation: XCTestExpectation = XCTestExpectation(description: "\(String(describing: SendSnapshotHandler.self))-\(UUID().uuidString)"),
      sshLogin: String,
      expectedSends: [Send]
    ) {
      self.expectation = expectation
      var expected = [String]()
      for send in expectedSends {
        switch send {
        case .full(let snapshot):
          expected.append("zfs send \(snapshot) | \(sshLogin) zfs recv -F \(snapshot)")
        case .incremental(let snapshot, let incremental):
          expected.append("zfs send -i \(incremental) \(snapshot) | \(sshLogin) zfs recv -F \(snapshot)")
        }
      }
      expectedStrings = expected
      guard expectedStrings.isEmpty else { return }
      expectation.fulfill()
    }

    func handleSendSnapshotCommand(
      _ string: String
    ) {
      for expectedString in expectedStrings {
        guard string == expectedString else { continue }
        expectedStrings.removeAll(where: { $0 == string })
        guard expectedStrings.isEmpty else { continue }
        expectation.fulfill()
      }
    }
  }

  private enum Send {
    case full(snapshot: String)
    static func full(date: String) -> Self {
      .full(snapshot: "\(SyncerTest.documentsDataset)@\(date)")
    }

    case incremental(snapshot: String, incremental: String)
    static func incremental(date: String, incrementalDate: String) -> Self {
      .incremental(snapshot: "\(SyncerTest.documentsDataset)@\(date)", incremental: "\(SyncerTest.documentsDataset)@\(incrementalDate)")
    }
  }
}
