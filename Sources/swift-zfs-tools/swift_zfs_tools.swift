import Foundation
import Shell

public func main() {
  let fileManager = FileManager.default
  guard let configPath = CommandLine.arguments.optional(at: 0),
        let config: ZFSTools.Config = fileManager.decodedJSON(atPath: configPath) else { return }
  let calendar = Calendar.current
  let dateFormatter = DateFormatter()
  dateFormatter.calendar = calendar
  dateFormatter.timeZone = calendar.timeZone
  dateFormatter.dateFormat = config.dateFormat
  let actionPerformer = ZFSTools.ActionPerformer(
    actions: config.actions,
    fileManager: fileManager,
    shell: Shell.Executor(),
    calendar: calendar,
    dateFormatter: dateFormatter
  )
  actionPerformer.performActions()
}


public enum ZFSTools {
  public struct Config: Codable, Sendable, Equatable {
    public let actions: [Action]
    public let dateFormat: String
  }
}

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
      case .consolidation(let config): performConsolidation(config)
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

    private func performConsolidation(_ config: ZFSTools.Action.Config) {
      guard let consolidationConfig: ZFSTools.Action.Config.Consolidation = fileManager.decodedJSON(atPath: config.path) else { return }
      let consolidator = Consolidator(
        shell: shell,
        config: consolidationConfig,
        calendar: calendar,
        dateFormatter: dateFormatter,
        consolidateNow: true
      )
      let poller = Poller { consolidator.isConsolidating }
      while poller.isBusy { }
    }

    private func performSync(_ config: ZFSTools.Action.Config) {

    }
  }
}
