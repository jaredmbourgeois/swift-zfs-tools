import ArgumentParser
import Foundation
import Shell
import ZFSToolsModel

struct Consolidate: AsyncParsableCommand {
  @OptionGroup()
  var arguments: Arguments.Consolidate

  func run() async throws {
    let calendar = Calendar.current
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.dateFormat = arguments.common.dateFormat ?? Defaults.dateFormat
    let date: @Sendable () -> Date = { .now }
    let consolidator = Consolidator(
      shell: Shell.Executor(arguments: arguments.common),
      config: try Consolidator.Config(
        arguments: arguments,
        fileManager: .default,
        jsonDecoder: .init(),
        dateFormatter: dateFormatter
      ),
      calendar: calendar,
      dateFormatter: dateFormatter,
      date: date
    )
    try await consolidator.consolidate()
  }
}

struct ConsolidateConfigure: ParsableCommand {
  @OptionGroup()
  var arguments: Arguments.ConsolidateConfigure

  func run() throws {
    let fileManager = FileManager.default
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = .current
    dateFormatter.dateFormat = arguments.consolidate.common.dateFormat ?? Defaults.dateFormat
    try encode(
      try Consolidator.Config(
        arguments: arguments.consolidate,
        fileManager: fileManager,
        jsonDecoder: .init(),
        dateFormatter: dateFormatter
      ),
      toJsonAtPath: arguments.outputPath,
      fileManager: fileManager,
      jsonEncoder: .init()
    )
  }
}

struct ConsolidateConfigured: ParsableCommand {
  @OptionGroup()
  var arguments: Arguments.ConsolidateConfigured

  func run() async throws {
    let fileManager = FileManager.default
    let jsonDecoder = JSONDecoder()
    let config: Consolidator.Config = try decodeFromJsonAtPath(
      arguments.configPath,
      fileManager: fileManager,
      jsonDecoder: jsonDecoder
    )
    let calendar = Calendar.current
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.dateFormat = arguments.common.dateFormat ?? Defaults.dateFormat
    let date: @Sendable () -> Date = { .now }
    let consolidator = Consolidator(
      shell: Shell.Executor(arguments: arguments.common),
      config: config,
      calendar: calendar,
      dateFormatter: dateFormatter,
      date: date
    )
    try await consolidator.consolidate()
  }
}
