import Foundation
import Shell

extension ZFSTools {
  public class Snapshotter {
    public var isSnapshotting: Bool { _isSnapshotting.value }
    private let _isSnapshotting: DispatchedValue<Bool>
    private let shell: ShellExecutor
    private let config: ZFSTools.Action.Config.Snapshot
    private let date: () -> Date
    private let dateFormatter: DateFormatter

    public init(
      shell: ShellExecutor,
      config: ZFSTools.Action.Config.Snapshot,
      date: @escaping () -> Date = { .now },
      dateFormatter: DateFormatter,
      snapshotNow: Bool
    ) {
      _isSnapshotting = .init(snapshotNow)
      self.shell = shell
      self.config = config
      self.date = date
      self.dateFormatter = dateFormatter
      guard snapshotNow else { return }
      snapshot()
    }

    public func snapshot() {
      _isSnapshotting.value = true
      Task(priority: .high) {
        await shell.sudoOutput(snapshotCommand, password: config.password, dryRun: config.dryRun)
        _isSnapshotting.value = false
      }
    }
  }
}

extension ZFSTools.Snapshotter {
  private var snapshotCommand: String {
    var command = "zfs snapshot"
    if config.recursive {
      command += " -r"
    }
    command += " \(config.dataset)\(config.dateSeparator)\(dateFormatter.string(from: date()))"
    return command
  }
}
