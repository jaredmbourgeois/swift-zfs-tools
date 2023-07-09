import Foundation
import Shell

public enum Action: EquatableModel {
  case consolidate(configPath: String)
  case snapshot(configPath: String)
  case sync(configPath: String)
}

public actor ActionExecutor {
  private let calendar: Calendar
  private let dateFormatter: DateFormatter
  private let fileManager: FileManager
  private let jsonDecoder: JSONDecoder
  private let shell: ShellExecutor

  public init(
    calendar: Calendar,
    dateFormatter: DateFormatter,
    fileManager: FileManager,
    jsonDecoder: JSONDecoder,
    shell: ShellExecutor
  ) {
    self.calendar = calendar
    self.dateFormatter = dateFormatter
    self.fileManager = fileManager
    self.jsonDecoder = jsonDecoder
    self.shell = shell
  }

  public func execute(_ actions: [Action]) async throws {
    for action in actions {
      switch action {
      case .consolidate(let configPath):
        try await Consolidator(
          shell: shell,
          config: decodeFromJsonAtPath(
            configPath,
            fileManager: fileManager,
            jsonDecoder: jsonDecoder
          ),
          calendar: calendar,
          dateFormatter: dateFormatter
        ).consolidate()

      case .snapshot(let configPath):
        try await Snapshotter(
          shell: shell,
          config: try decodeFromJsonAtPath(
            configPath,
            fileManager: fileManager,
            jsonDecoder: jsonDecoder
          ),
          dateFormatter: dateFormatter,
          date: { .now }
        ).snapshot()

      case .sync(let configPath):
        try await Syncer(
          shell: shell,
          config: try decodeFromJsonAtPath(
            configPath,
            fileManager: fileManager,
            jsonDecoder: jsonDecoder
          ),
          dateFormatter: dateFormatter
        ).sync()
      }
    }
  }
}
