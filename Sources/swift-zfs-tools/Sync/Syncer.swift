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
      sshLogin = "ssh -i \(config.sshKeyPath) \(config.sshIP)"
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
          await sudoOutput(zfsCommandSend(send))
        }
      }
    }

    private func sendsForDataset(_ dataset: Dataset) -> [Send] {
      guard !dataset.snapshotsCreated.isEmpty else { return [] }
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
          createdPrevious = dataset.snapshotsLocal[createdIndexInLocal]
        }
        return .init(this: created, previous: createdPrevious)
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
      func sortedByDate(_ snapshots: [Snapshot]) -> [Snapshot] {
        snapshots.sorted(by: { $0.date < $1.date })
      }
      var datasets = [Dataset]()
      var datasetSnapshotsLocal: [Snapshot]
      var datasetSnapshotsRemote: [Snapshot]
      var datasetSnapshotsDeleted: [Snapshot]
      var datasetSnapshotsCreated: [Snapshot]
      var dataset: Dataset
      for datasetString in (await datasetsLocal) {
        datasetSnapshotsLocal = snapshotsLocal.filter { $0.dataset == datasetString }
        datasetSnapshotsRemote = snapshotsRemote.filter { $0.dataset == datasetString }
        datasetSnapshotsDeleted = datasetSnapshotsRemote.filter { !datasetSnapshotsLocal.contains($0) }
        datasetSnapshotsCreated = datasetSnapshotsLocal.filter { !datasetSnapshotsRemote.contains($0) }
        dataset = .init(
          dataset: datasetString,
          snapshotsLocal: sortedByDate(datasetSnapshotsLocal),
          snapshotsRemote: sortedByDate(datasetSnapshotsRemote),
          snapshotsDeleted: sortedByDate(datasetSnapshotsDeleted),
          snapshotsCreated: sortedByDate(datasetSnapshotsCreated)
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
    let snapshotsLocal: [Snapshot]
    let snapshotsRemote: [Snapshot]
    let snapshotsDeleted: [Snapshot]
    let snapshotsCreated: [Snapshot]
  }

  private struct Snapshot: Equatable {
    let snapshot: String
    let dataset: String
    let date: Date
  }

  private struct Send {
    let this: Snapshot
    let previous: Snapshot?
  }
}
