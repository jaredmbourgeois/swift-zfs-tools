import Algorithms
import Foundation
import Shell

public actor Syncer {
  private let shell: ShellExecutor
  private let config: Syncer.Config
  private let dateFormatter: DateFormatter

  private let sshLogin: String

  public init(
    shell: ShellExecutor,
    config: Syncer.Config,
    dateFormatter: DateFormatter
  ) {
    self.shell = shell
    self.config = config
    self.dateFormatter = dateFormatter
    sshLogin = "ssh -p \(config.sshPort) -i \(config.sshKeyPath) \(config.sshUser)@\(config.sshIP)"
  }

  public func sync() async throws {
    let datasets = try await datasets()
    try await destroySnapshots(datasets)
    try await sendSnapshots(datasets)
  }

  private func destroySnapshots(_ datasets: [Dataset]) async throws {
    try await withThrowingTaskGroup(of: Void.self) { taskGroup in
      for dataset in datasets {
        taskGroup.addTask {
          for snapshotDeleted in dataset.snapshotsDeleted {
            try await self.shell.sudo(
              self.remote(.destroy(subject: snapshotDeleted.snapshot)),
              execute: self.config.execute
            )
          }
        }
      }
      try await taskGroup.waitForAll()
    }
  }

  private func sendSnapshots(_ datasets: [Dataset]) async throws {
    try await withThrowingTaskGroup(of: Void.self) { taskGroup in
      for dataset in datasets {
        taskGroup.addTask {
          for send in await self.sendsForDataset(dataset) {
            for destroy in send.destroy {
              try await self.shell.sudo(
                self.remote(.destroy(subject: destroy.snapshot)),
                execute: self.config.execute
              )
            }
            try await self.shell.sudo(
              self.zfsSend(send),
              execute: self.config.execute
            )
          }
        }
      }
      try await taskGroup.waitForAll()
    }
  }

  private func snapshotsSortedByAscendingDate(_ snapshots: [Snapshot]) -> [Snapshot] {
    snapshots.sorted(by: { $0.date < $1.date })
  }

  private func sendsForDataset(_ dataset: Dataset) -> [Send] {
    guard !dataset.snapshotsCreated.isEmpty else { return [] }
    let uniqueSnapshots = (dataset.snapshotsLocal + dataset.snapshotsRemote).uniqued()
    var commonSnapshotsDescending = uniqueSnapshots.reduce(into: [Snapshot]()) { commonSnapshots, uniqueSnapshot in
      guard dataset.snapshotsLocal.contains(uniqueSnapshot) && dataset.snapshotsRemote.contains(uniqueSnapshot) else {
        return
      }
      commonSnapshots.append(uniqueSnapshot)
    }.sorted(by: { $0.date > $1.date })

    return dataset.snapshotsCreated.map { snapshotCreated in
      var mostRecentCommonAncestor: Snapshot?
      for commonSnapshot in commonSnapshotsDescending {
        guard commonSnapshot.date < snapshotCreated.date else { continue }
        mostRecentCommonAncestor = commonSnapshot
        break
      }

      let destroy: [Snapshot]
      if let mostRecentCommonAncestor {
        destroy = commonSnapshotsDescending.filter {
          $0.date < snapshotCreated.date && $0.date > mostRecentCommonAncestor.date
        }
      } else {
        destroy = []
      }

      commonSnapshotsDescending.append(snapshotCreated)
      commonSnapshotsDescending.sort(by: { $0.date > $1.date })

      return .init(
        this: snapshotCreated,
        previous: mostRecentCommonAncestor,
        destroy: destroy
      )
    }
  }

  private func datasets() async throws -> [Dataset] {
    let datasetsLocal = try await shell.sudoLines(
      ZFS.listDatasets(matching: config.datasetGrep).command,
      execute: config.execute
    )
    return try await withThrowingTaskGroup(of: Dataset.self) { taskGroup in
      datasetsLocal.forEach { dataset in
        taskGroup.addTask {
          async let snapshotStringsRemote = self.shell.sudoLines(
            self.remote(.listSnapshotsInDataset(dataset: dataset, dateSeparator: self.config.dateSeparator)),
            execute: self.config.execute
          )
          async let snapshotStringsLocal = self.shell.sudoLines(
            ZFS.listSnapshotsInDataset(dataset: dataset, dateSeparator: self.config.dateSeparator).command,
            execute: self.config.execute
          )
          let snapshotsLocal: [Snapshot] = await self.snapshotsSortedByAscendingDate(
            (try await snapshotStringsLocal).compactMap {
              let split = $0.split(separator: self.config.dateSeparator)
              guard split.count == 2,
                    let date = self.dateFormatter.date(from: String(split[1])) else { return nil }
              return Snapshot(snapshot: $0, dataset: String(split[0]), date: date)
            }
          )
          let snapshotsRemote: [Snapshot] = await self.snapshotsSortedByAscendingDate(
            (try await snapshotStringsRemote).compactMap {
              let split = $0.split(separator: self.config.dateSeparator)
              guard split.count == 2,
                    let date = self.dateFormatter.date(from: String(split[1])) else { return nil }
              return Snapshot(snapshot: $0, dataset: String(split[0]), date: date)
            }
          )
          let snapshotsDeleted = snapshotsRemote.filter { !snapshotsLocal.contains($0) }
          let snapshotsCreated = snapshotsLocal.filter {
            let notInRemote = !snapshotsRemote.contains($0)
            var inFuture = false
            if let lastRemote = snapshotsRemote.last {
              inFuture = $0.date > lastRemote.date
            } else if snapshotsRemote.isEmpty {
              inFuture = true
            }
            return notInRemote && inFuture
          }
          return Dataset(
            dataset: dataset,
            snapshotsLocal: snapshotsLocal,
            snapshotsRemote: snapshotsRemote,
            snapshotsDeleted: snapshotsDeleted,
            snapshotsCreated: snapshotsCreated
          )
        }
      }
      var datasets = [Dataset]()
      datasets.reserveCapacity(datasetsLocal.count)
      for try await dataset in taskGroup {
        datasets.append(dataset)
      }
      return datasets
    }
  }
}

extension Syncer {
  private func remote(_ command: ZFS) -> String {
    "\(sshLogin) \(command.command)"
  }

  private func zfsSend(_ send: Send) -> String {
    var command = "zfs send"
    if let previousSnapshot = send.previous {
      command += " -i \(previousSnapshot.snapshot)"
    }
    command += " \(send.this.snapshot) | \(sshLogin) zfs recv -F \(send.this.snapshot)"
    return command
  }
}

extension Syncer {
  private struct Dataset: Equatable {
    let dataset: String
    /// snapshotsLocal sorted by ascending Date
    let snapshotsLocal: [Snapshot]
    /// snapshotsRemote sorted by ascending Date
    let snapshotsRemote: [Snapshot]
    /// snapshotsDeleted sorted by ascending Date
    let snapshotsDeleted: [Snapshot]
    /// snapshotsCreated sorted by ascending Date
    let snapshotsCreated: [Snapshot]
  }

  private struct Snapshot: Hashable {
    let snapshot: String
    let dataset: String
    let date: Date
  }

  private struct Send {
    let this: Snapshot
    let previous: Snapshot?
    let destroy: [Snapshot]
  }
}

extension Syncer {
  public struct Config: Codable, Sendable, Equatable {
    let datasetGrep: String?
    let dateSeparator: String
    let sshPort: String
    let sshKeyPath: String
    let sshUser: String
    let sshIP: String
    let execute: Bool

    public init(
      datasetGrep: String?,
      dateSeparator: String,
      sshPort: String,
      sshKeyPath: String,
      sshUser: String,
      sshIP: String,
      execute: Bool
    ) {
      self.datasetGrep = datasetGrep
      self.dateSeparator = dateSeparator
      self.sshPort = sshPort
      self.sshKeyPath = sshKeyPath
      self.sshUser = sshUser
      self.sshIP = sshIP
      self.execute = execute
    }

    public init(
      arguments: Arguments.Sync
    ) {
      datasetGrep = arguments.datasetGrep
      dateSeparator = arguments.common.dateSeparator ?? Defaults.dateSeparator
      sshPort = arguments.sshPort
      sshKeyPath = arguments.sshKeyPath
      sshUser = arguments.sshUser
      sshIP = arguments.sshIP
      execute = arguments.common.execute ?? Defaults.execute
    }
  }
}
