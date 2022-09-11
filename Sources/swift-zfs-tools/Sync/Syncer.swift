import Foundation
import Shell

extension ZFSTools {
  public class Syncer {
    public var isSyncing: Bool { _isSyncing.value }

    private let _isSyncing: DispatchedValue<Bool>
    private let shell: ShellExecutor
    private let config: ZFSTools.Action.Config.Sync
    private let dateFormatter: DateFormatter

    private let sshLogin: String

    public init(
      shell: ShellExecutor,
      config: ZFSTools.Action.Config.Sync,
      dateFormatter: DateFormatter,
      syncNow: Bool
    ) {
      self.shell = shell
      self.config = config
      self.dateFormatter = dateFormatter
      sshLogin = "ssh -p \(config.sshPort) -i \(config.sshKeyPath) \(config.sshUser)@\(config.sshIP)"
      _isSyncing = .init(syncNow)
      guard syncNow else { return }
      sync()
    }

    public func sync() {
      _isSyncing.value = true
      Task(priority: .high) {
        let datasets = await datasets()
        await destroySnapshots(datasets)
        await sendSnapshots(datasets)
        _isSyncing.value = false
      }
    }

    private func destroySnapshots(_ datasets: [Dataset]) async {
      for dataset in datasets {
        for snapshotDeleted in dataset.snapshotsDeleted {
          await sudoOutput(zfsCommandDestroyRemote(snapshotDeleted.snapshot))
        }
      }
    }

    private func sendSnapshots(_ datasets: [Dataset]) async {
      for dataset in datasets {
        for send in sendsForDataset(dataset) {
          for destroy in send.destroy {
            await sudoOutput(zfsCommandDestroyRemote(destroy.snapshot))
          }
          await sudoOutput(zfsCommandSend(send))
        }
      }
    }

    private func snapshotsSortedByAscendingDate(_ snapshots: [Snapshot]) -> [Snapshot] {
      snapshots.sorted(by: { $0.date < $1.date })
    }

    private func sendsForDataset(_ dataset: Dataset) -> [Send] {
      guard !dataset.snapshotsCreated.isEmpty else { return [] }
      let commonSnapshots = (dataset.snapshotsLocal + dataset.snapshotsRemote)
        .uniqued()
        .sorted(by: { $0.date < $1.date })
      var destroy = [Snapshot]()
      var created = dataset.snapshotsCreated[0]
      var createdIndexInLocal: Int?
      var createdPrevious: Snapshot?
      return dataset.snapshotsCreated.mapIndex { index, snapshot in
        created = dataset.snapshotsCreated[index]
        createdIndexInLocal = dataset.snapshotsLocal.firstIndex(of: created)
        createdPrevious = nil
        if index > 0 {
          createdPrevious = dataset.snapshotsCreated[index - 1]
        } else if let createdIndexInLocal = createdIndexInLocal,
                  dataset.snapshotsLocal.indices.contains(createdIndexInLocal - 1) {
          let previousLocal = dataset.snapshotsLocal[createdIndexInLocal]
          createdPrevious = previousLocal
          if !commonSnapshots.contains(where: { $0 == previousLocal }) {
            let snapshotsBeforeLocal = commonSnapshots.filter({ $0.date > previousLocal.date })
            if let lastCommon = snapshotsBeforeLocal.last {
              createdPrevious = lastCommon
              // destroy snapshots after lastCommon since the last incremental is being set to an earlier snapshot
              destroy.append(
                contentsOf: dataset.snapshotsRemote.filter({ $0.date > lastCommon.date })
              )
            } else {
              // destroy all remote snapshots since they will be orphaned when we do a full send
              destroy.append(contentsOf: dataset.snapshotsRemote)
            }
          }
        }
        return .init(
          this: created,
          previous: createdPrevious,
          destroy: destroy
        )
      }
    }

    private func datasets() async -> [Dataset] {
      async let snapshotStringsRemote = sudoOutputLines(zfsCommandListSnapshotsRemote(matching: nil))
      async let snapshotStringsLocal = sudoOutputLines(zfsCommandListSnapshotsLocal(matching: nil))
      async let datasetsLocal = sudoOutputLines(zfsCommandListLocal(matching: nil))
      let snapshotsLocal: [Snapshot] = (await snapshotStringsLocal).compactMap {
        let split = $0.splitXP(by: config.snapshotDateSeparator)
        guard split.count == 2,
              let date = dateFormatter.date(from: split[1]) else { return nil }
        return Snapshot(snapshot: $0, dataset: split[0], date: date)
      }
      let snapshotsRemote: [Snapshot] = (await snapshotStringsRemote).compactMap {
        let split = $0.splitXP(by: config.snapshotDateSeparator)
        guard split.count == 2,
              let date = dateFormatter.date(from: split[1]) else { return nil }
        return Snapshot(snapshot: $0, dataset: split[0], date: date)
      }
      var datasets = [Dataset]()
      var datasetSnapshotsLocal: [Snapshot]
      var datasetSnapshotsRemote: [Snapshot]
      var datasetSnapshotsDeleted: [Snapshot]
      var datasetSnapshotsCreated: [Snapshot]
      var dataset: Dataset
      for datasetString in (await datasetsLocal) {
        datasetSnapshotsLocal = snapshotsSortedByAscendingDate(snapshotsLocal.filter({ $0.dataset == datasetString }))
        datasetSnapshotsRemote = snapshotsSortedByAscendingDate(snapshotsRemote.filter({ $0.dataset == datasetString }))
        datasetSnapshotsDeleted = snapshotsSortedByAscendingDate(datasetSnapshotsRemote.filter({ !datasetSnapshotsLocal.contains($0) }))
        datasetSnapshotsCreated = snapshotsSortedByAscendingDate(datasetSnapshotsLocal.filter({
          let notInRemote = !datasetSnapshotsRemote.contains($0)
          var inFuture = false
          if let lastRemote = datasetSnapshotsRemote.last {
            inFuture = $0.date > lastRemote.date
          } else if datasetSnapshotsRemote.isEmpty {
            inFuture = true
          }
          return notInRemote && inFuture
        }))
        dataset = .init(
          dataset: datasetString,
          snapshotsLocal: datasetSnapshotsLocal,
          snapshotsRemote: datasetSnapshotsRemote,
          snapshotsDeleted: datasetSnapshotsDeleted,
          snapshotsCreated: datasetSnapshotsCreated
        )
        datasets.append(dataset)
      }
      return datasets
    }
  }
}

extension ZFSTools.Syncer {
  @discardableResult
  private func sudoOutput(_ command: String) async -> String {
    await shell.sudoOutput(
      command,
      dryRun: config.dryRun
    ) ?? ""
  }

  @discardableResult
  private func sudoOutputLines(_ command: String) async -> [String] {
    await shell.sudoOutputLines(
      command,
      dryRun: config.dryRun
    )
  }
}

extension ZFSTools.Syncer {
  private func zfsCommandDestroyRemote(_ subject: String) -> String {
    "\(sshLogin) \(ZFSTools.ZFSCommand.destroy(subject))"
  }

  private func zfsCommandListLocal(matching: String?) -> String {
    var command = ZFSTools.ZFSCommand.list(matching: config.datasetMatch)
    if let matching = matching {
      command += " | grep \(matching)"
    }
    return command
  }

  private func zfsCommandListRemote(matching: String?) -> String {
    "\(sshLogin) \(zfsCommandListLocal(matching: matching))"
  }

  private func zfsCommandListSnapshotsLocal(matching: String?) -> String {
    var command = ZFSTools.ZFSCommand.listSnapshots(matching: config.datasetMatch)
    if let matching = matching {
      command += " | grep \(matching)"
    }
    return command
  }

  private func zfsCommandListSnapshotsRemote(matching: String?) -> String {
    "\(sshLogin) \(zfsCommandListSnapshotsLocal(matching: matching))"
  }

  private func zfsCommandSend(_ send: Send) -> String {
    var command = "zfs send"
    if let previousSnapshot = send.previous {
      command += " -i \(previousSnapshot.snapshot)"
    }
    command += " \(send.this.snapshot) | \(sshLogin) zfs recv -F \(send.this.snapshot)"
    return command
  }
}

extension ZFSTools.Syncer {
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
