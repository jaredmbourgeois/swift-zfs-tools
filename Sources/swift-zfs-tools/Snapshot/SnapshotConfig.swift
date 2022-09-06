import Foundation

extension ZFSTools.Action.Config {
  public struct Snapshot: ZFSTools.Model {
    public let dataset: String
    public let recursive: Bool
    public let dateSeparator: String
    public let password: String
    public let dryRun: Bool

    public init(
      dataset: String,
      recursive: Bool,
      dateSeparator: String,
      password: String,
      dryRun: Bool
    ) {
      self.dataset = dataset
      self.recursive = recursive
      self.dateSeparator = dateSeparator
      self.password = password
      self.dryRun = dryRun
    }
    
    public init?(_ config: ZFSTools.Action.Config, fileManager: FileManager) {
      guard let decoded: Self = fileManager.decodedJSON(atPath: config.path) else { return nil }
      self = decoded
    }
  }
}
