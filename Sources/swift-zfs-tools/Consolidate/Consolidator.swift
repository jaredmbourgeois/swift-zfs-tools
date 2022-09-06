import Algorithms
import Dispatch
import Foundation
import Shell

extension ZFSTools {
  public class Consolidator {
    public var isConsolidating: Bool { _isConsolidating.value }

    private let _isConsolidating: DispatchedValue<Bool>
    private let shell: ShellExecutor
    private let config: ZFSTools.Action.Config.Consolidate
    private let calendar: Calendar
    private let dateFormatter: DateFormatter

    public init(
      shell: ShellExecutor,
      config: ZFSTools.Action.Config.Consolidate,
      calendar: Calendar,
      dateFormatter: DateFormatter,
      consolidateNow: Bool
    ) {
      self.shell = shell
      self.config = config
      self.calendar = calendar
      self.dateFormatter = dateFormatter
      _isConsolidating = .init(consolidateNow)
      guard consolidateNow else { return }
      consolidate()
    }

    public func consolidate() {
      _isConsolidating.value = true
      Task(priority: .high) {
        async let _datasets = zfsDatasets()
        async let _allSnapshots = zfsSnapshots()
        let datasets = await _datasets
        var snapshotsToKeep = config.snapshotsNotConsolidated
        await withTaskGroup(of: [String].self) { taskGroup in
          for dataset in datasets {
            taskGroup.addTask {
              let datasetSnapshots = await self.zfsSnapshotsWithPattern(dataset)
              return self.consolidatedSnapshots(datasetSnapshots)
            }
          }
          for await snapshots in taskGroup {
            snapshotsToKeep.append(contentsOf: snapshots)
          }
        }
        let snapshotsToDelete = (await _allSnapshots).filter { !snapshotsToKeep.contains($0) }
        await deleteSnapshots(snapshotsToDelete)
        _isConsolidating.value = false
        await sudo("echo kept \(snapshotsToKeep.count), deleted \(snapshotsToDelete.count) snapshots")
      }
    }

    private func consolidatedSnapshots(_ snapshots: [String]) -> [String] {
      let snapshotsAndDates: [ConsolidatePeriod.SnapshotAndDate] = snapshots.compactMap { snapshot in
        guard let dateText = snapshot.splitXP(by: config.snapshotDateSeparator).last,
              let date = dateFormatter.date(from: dateText) else { return nil }
        return .init(snapshot: snapshot, date: date)
      }
      let snapshotPeriodRangeSnapshotAndDates = config.consolidatePeriod.snapshotPeriodRangeSnapshotAndDates(
        calendar,
        snapshotPeriodBias: config.consolidatePeriod.snapshotPeriodBias,
        snapshotAndDates: snapshotsAndDates
      )
      return snapshotPeriodRangeSnapshotAndDates.snapshots
    }
  }
}

// MARK: Helper
extension ZFSTools.Consolidator {
  private func zfsDatasets() async -> [String] {
    await shell.zfsDatasets(matching: config.datasetMatch, password: config.password)
  }

  private func zfsDestroy(_ subject: String) async {
    await shell.zfsDestroy(subject, password: config.password, dryRun: config.dryRun)
  }

  private func zfsSnapshots() async -> [String] {
    await shell.zfsSnapshots(matching: config.datasetMatch, password: config.password)
  }

  private func zfsSnapshotsWithPattern(_ pattern: String) async -> [String] {
    await shell.zfsSnapshots(matching: pattern, password: config.password)
  }

  private func deleteSnapshots(_ snapshots: [String]) async {
    for snapshot in snapshots {
      await zfsDestroy(snapshot)
    }
  }
}

// MARK: Command
extension ZFSTools.Consolidator {
  @discardableResult
  private func sudo(
    _ command: String,
    function: StaticString = #function
  ) async -> String {
    await shell.sudoOutput(command, password: config.password, dryRun: config.dryRun, function: function) ?? ""
  }

  @discardableResult
  private func sudoLines(
    _ command: String,
    function: StaticString = #function
  ) async -> [String] {
    await shell.sudoOutputLines(command, password: config.password, dryRun: config.dryRun, function: function)
  }
}
