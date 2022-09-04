import Foundation

extension ZFSTools.Action.Config {
  public struct Consolidation: Codable {
    public let password: String
    public let datasetMatch: String
    public let snapshotDateSeparator: String
    public let snapshotsNotConsolidated: [String]
    public let consolidationPeriod: ZFSTools.Consolidator.ConsolidationPeriod
    public let dryRun: Bool

    public init(
      password: String,
      datasetMatch: String,
      snapshotDateSeparator: String,
      snapshotsNotConsolidated: [String],
      consolidationPeriod: ZFSTools.Consolidator.ConsolidationPeriod,
      dryRun: Bool
    ) {
      self.password = password
      self.datasetMatch = datasetMatch
      self.snapshotDateSeparator = snapshotDateSeparator
      self.snapshotsNotConsolidated = snapshotsNotConsolidated
      self.consolidationPeriod = consolidationPeriod
      self.dryRun = dryRun
    }

    public init?(_ config: ZFSTools.Action.Config, fileManager: FileManager) {
      guard let decoded: Self = fileManager.decodedJSON(atPath: config.path) else { return nil }
      self = decoded
    }
  }
}
