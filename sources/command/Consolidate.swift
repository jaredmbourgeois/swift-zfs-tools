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
    let consolidator = Consolidator(
      shell: Shell.Executor(arguments: arguments.common),
      config: try Consolidator.Config(
        arguments: arguments,
        fileManager: .default,
        jsonDecoder: .init(),
        dateFormatter: dateFormatter,
        date: { .now }
      ),
      calendar: calendar,
      dateFormatter: dateFormatter
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
        dateFormatter: dateFormatter,
        date: { .now }
      ),
      toJsonAtPath: arguments.outputPath,
      fileManager: fileManager,
      jsonEncoder: .init()
    )
  }
}
