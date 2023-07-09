import Foundation
import Shell

public actor Snapshotter {
  private let shell: ShellExecutor
  private let config: Config
  private let dateFormatter: DateFormatter
  private let date: @Sendable () -> Date

  public init(
    shell: ShellExecutor,
    config: Config,
    dateFormatter: DateFormatter,
    date: @Sendable @escaping () -> Date
  ) {
    self.shell = shell
    self.config = config
    self.dateFormatter = dateFormatter
    self.date = date
  }

  public func snapshot() async throws {
    try await shell.sudo(snapshotCommand, execute: config.execute)
  }
}

extension Snapshotter {
  private var snapshotCommand: String {
    var command = "zfs snapshot"
    if config.recursive {
      command += " -r"
    }
    command += " \(config.dataset)\(config.dateSeparator)\(dateFormatter.string(from: date()))"
    return command
  }
}

extension Snapshotter {
  public struct Config: EquatableModel {
    public let dataset: String
    public let dateSeparator: String
    public let execute: Bool
    public let recursive: Bool

    public init(
      dataset: String,
      dateSeparator: String,
      execute: Bool,
      recursive: Bool
    ) {
      self.dataset = dataset
      self.dateSeparator = dateSeparator
      self.execute = execute
      self.recursive = recursive
    }

    public init(
      arguments: Arguments.Snapshot
    ) {
      dataset = arguments.dataset
      dateSeparator = arguments.common.dateSeparator ?? Defaults.dateSeparator
      execute = arguments.common.execute ?? Defaults.execute
      recursive = arguments.recursive ?? Defaults.recursive
    }
  }
}
