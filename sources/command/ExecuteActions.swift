import ArgumentParser
import Foundation
import Shell
import ZFSToolsModel

extension FileManager: @unchecked Sendable {}

struct ExecuteActions: AsyncParsableCommand {
  @OptionGroup()
  var arguments: Arguments.ExecuteActions

  func run() async throws {
    let fileManager = FileManager.default
    let jsonDecoder = JSONDecoder()
    let actions: [Action] = try decodeFromJsonAtPath(
      arguments.actionsPath,
      fileManager: fileManager,
      jsonDecoder: jsonDecoder
    )
    let calendar = Calendar.current
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.dateFormat = arguments.common.dateFormat ?? Defaults.dateFormat
    let executor = ActionExecutor(
      calendar: calendar,
      dateFormatter: dateFormatter,
      fileManager: fileManager,
      jsonDecoder: jsonDecoder,
      shell: Shell.Executor(arguments: arguments.common)
    )
    try await executor.execute(actions)
  }
}

struct ExecuteActionsConfigure: AsyncParsableCommand {
  @OptionGroup()
  var arguments: Arguments.ExecuteActionsConfigure

  func run() async throws {
    try encode(
      [
        Action.snapshot(configPath: "/path/to/snapshot/config.json"),
        Action.consolidate(configPath: "/path/to/consolidate/config.json"),
        Action.sync(configPath: "/path/to/sync/config.json"),
      ],
      toJsonAtPath: arguments.outputPath,
      fileManager: .default,
      jsonEncoder: .init()
    )
  }
}
