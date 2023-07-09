import ArgumentParser
import Foundation
import Shell
import ZFSToolsModel

struct Snapshot: AsyncParsableCommand {
  @OptionGroup()
  var arguments: Arguments.Snapshot

  func run() async throws {
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = .current
    dateFormatter.dateFormat = arguments.common.dateFormat ?? Defaults.dateFormat
    let snapshotter = Snapshotter(
      shell: Shell.Executor(arguments: arguments.common),
      config: .init(arguments: arguments),
      dateFormatter: dateFormatter,
      date: { .now }
    )
    try await snapshotter.snapshot()
  }
}

struct SnapshotConfigure: ParsableCommand {
  @OptionGroup()
  var arguments: Arguments.SnapshotConfigure

  func run() throws {
    try encode(
      Snapshotter.Config(arguments: arguments.snapshot),
      toJsonAtPath: arguments.outputPath,
      fileManager: .default,
      jsonEncoder: .init()
    )
  }
}
