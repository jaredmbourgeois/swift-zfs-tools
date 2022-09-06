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

extension ZFSTools {
  public typealias Model = Codable & Hashable & Sendable
}

public enum ZFSTools {
  public struct Config: ZFSTools.Model {
    public let actions: [Action]
    public let dateFormat: String
  }
}
