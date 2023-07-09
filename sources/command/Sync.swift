import ArgumentParser
import Foundation
import Shell
import ZFSToolsModel

struct Sync: AsyncParsableCommand {
  @OptionGroup()
  var arguments: Arguments.Sync

  func run() async throws {
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = .current
    dateFormatter.dateFormat = arguments.common.dateFormat ?? Defaults.dateFormat
    let snapshotter = Syncer(
      shell: Shell.Executor(arguments: arguments.common),
      config: .init(arguments: arguments),
      dateFormatter: dateFormatter
    )
    try await snapshotter.sync()
  }
}

struct SyncConfigure: ParsableCommand {
  @OptionGroup()
  var arguments: Arguments.SyncConfigure

  func run() throws {
    try encode(
      Syncer.Config(arguments: arguments.sync),
      toJsonAtPath: arguments.outputPath,
      fileManager: .default,
      jsonEncoder: .init()
    )
  }
}

struct SyncConfigured: AsyncParsableCommand {
  @OptionGroup()
  var arguments: Arguments.SyncConfigured

  func run() async throws {
    let config: Syncer.Config = try decodeFromJsonAtPath(
      arguments.configPath,
      fileManager: .default,
      jsonDecoder: .init()
    )
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = .current
    dateFormatter.dateFormat = arguments.common.dateFormat ?? Defaults.dateFormat
    let snapshotter = Syncer(
      shell: Shell.Executor(arguments: arguments.common),
      config: config,
      dateFormatter: dateFormatter
    )
    try await snapshotter.sync()
  }
}
