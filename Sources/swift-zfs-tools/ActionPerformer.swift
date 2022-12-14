import Foundation
import Shell

extension ZFSTools {
  public class ActionPerformer {
    private let actions: [Action]
    private let fileManager: FileManager
    private let shell: ShellExecutor
    private let calendar: Calendar
    private let dateFormatter: DateFormatter

    public init(
      actions: [Action],
      fileManager: FileManager,
      shell: ShellExecutor,
      calendar: Calendar,
      dateFormatter: DateFormatter
    ) {
      self.actions = actions
      self.fileManager = fileManager
      self.shell = shell
      self.calendar = calendar
      self.dateFormatter = dateFormatter
    }

    public func performActions() {
      for action in actions {
        performAction(action)
      }
    }

    private func performAction(_ action: ZFSTools.Action) {
      switch action {
      case .snapshot(let config): performSnapshot(config)
      case .consolidate(let config): performConsolidate(config)
      case .sync(let config): performSync(config)
      }
    }

    private func performSnapshot(_ config: ZFSTools.Action.Config) {
      guard let snapshotConfig: ZFSTools.Action.Config.Snapshot = fileManager.decodedJSON(atPath: config.path) else { return }
      let snapshotter = Snapshotter(
        shell: shell,
        config: snapshotConfig,
        dateFormatter: dateFormatter,
        snapshotNow: true
      )
      let poller = Poller { snapshotter.isSnapshotting }
      while poller.isBusy { }
    }

    private func performConsolidate(_ config: ZFSTools.Action.Config) {
      guard let consolidateConfig: ZFSTools.Action.Config.Consolidate = fileManager.decodedJSON(atPath: config.path) else { return }
      let consolidator = Consolidator(
        shell: shell,
        config: consolidateConfig,
        calendar: calendar,
        dateFormatter: dateFormatter,
        consolidateNow: true
      )
      let poller = Poller { consolidator.isConsolidating }
      while poller.isBusy { }
    }

    private func performSync(_ config: ZFSTools.Action.Config) {
      guard let syncConfig: ZFSTools.Action.Config.Sync = fileManager.decodedJSON(atPath: config.path) else { return }
      let snapshotter = Syncer(
        shell: shell,
        config: syncConfig,
        dateFormatter: dateFormatter,
        syncNow: true
      )
      let poller = Poller { snapshotter.isSyncing }
      while poller.isBusy { }
    }
  }
}
