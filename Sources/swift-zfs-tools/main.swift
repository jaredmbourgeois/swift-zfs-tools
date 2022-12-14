import Foundation
import Shell

extension ZFSTools {
  public typealias Model = Codable & Hashable & Sendable
}

public enum ZFSTools {
  public struct Config: ZFSTools.Model {
    public let actions: [Action]
    public let dateFormat: String
  }
}

private func run() {
  let fileManager = FileManager.default
  let shell = Shell.Executor()
  let configPath = CommandLine.arguments.optional(at: 1)
  guard let configPath = configPath,
        let config: ZFSTools.Config = fileManager.decodedJSON(atPath: configPath) else {
    _ = shell.sudoSynchronously("echo \"swift-zfs-tools ZFSTools.Config not found at configPath: \(configPath ?? "nil")\"")
    return
  }
  let calendar = Calendar.current
  let dateFormatter = DateFormatter()
  dateFormatter.calendar = calendar
  dateFormatter.timeZone = calendar.timeZone
  dateFormatter.dateFormat = config.dateFormat
  let actionPerformer = ZFSTools.ActionPerformer(
    actions: config.actions,
    fileManager: fileManager,
    shell:shell,
    calendar: calendar,
    dateFormatter: dateFormatter
  )
  actionPerformer.performActions()
}

run()
