import Foundation

extension ZFSTools.Action.Config {
  public struct Sync: Codable {
    public let password: String
    public let datasetMatch: String?
    public let snapshotDateSeparator: String
    public let sshKeyPath: String
    public let sshIP: String
    public let dryRun: Bool

    public init(
      password: String,
      datasetMatch: String?,
      snapshotDateSeparator: String,
      sshKeyPath: String,
      sshIP: String,
      dryRun: Bool
    ) {
      self.password = password
      self.datasetMatch = datasetMatch
      self.snapshotDateSeparator = snapshotDateSeparator
      self.sshKeyPath = sshKeyPath
      self.sshIP = sshIP
      self.dryRun = dryRun
    }

    public init?(_ config: ZFSTools.Action.Config, fileManager: FileManager) {
      guard let decoded: Self = fileManager.decodedJSON(atPath: config.path) else { return nil }
      self = decoded
    }
  }
}
