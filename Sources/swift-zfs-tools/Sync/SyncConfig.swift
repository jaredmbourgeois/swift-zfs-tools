import Foundation

extension ZFSTools.Action.Config {
  public struct Sync: ZFSTools.Model {
    public let datasetMatch: String?
    public let snapshotDateSeparator: String
    public let sshPort: String
    public let sshKeyPath: String
    public let sshUser: String
    public let sshIP: String
    public let dryRun: Bool

    public init(
      datasetMatch: String?,
      snapshotDateSeparator: String,
      sshPort: String,
      sshKeyPath: String,
      sshUser: String,
      sshIP: String,
      dryRun: Bool
    ) {
      self.datasetMatch = datasetMatch
      self.snapshotDateSeparator = snapshotDateSeparator
      self.sshPort = sshPort
      self.sshKeyPath = sshKeyPath
      self.sshUser = sshUser
      self.sshIP = sshIP
      self.dryRun = dryRun
    }

    public init?(_ config: ZFSTools.Action.Config, fileManager: FileManager) {
      guard let decoded: Self = fileManager.decodedJSON(atPath: config.path) else { return nil }
      self = decoded
    }
  }
}
