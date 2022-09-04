import Foundation

extension ZFSTools.Action.Config {
  public struct Consolidate: Codable {
    public let password: String
    public let datasetMatch: String
    public let snapshotDateSeparator: String
    public let snapshotsNotConsolidated: [String]
    public let consolidatePeriod: ZFSTools.Consolidator.ConsolidatePeriod
    public let dryRun: Bool

    public init(
      password: String,
      datasetMatch: String,
      snapshotDateSeparator: String,
      snapshotsNotConsolidated: [String],
      consolidatePeriod: ZFSTools.Consolidator.ConsolidatePeriod,
      dryRun: Bool
    ) {
      self.password = password
      self.datasetMatch = datasetMatch
      self.snapshotDateSeparator = snapshotDateSeparator
      self.snapshotsNotConsolidated = snapshotsNotConsolidated
      self.consolidatePeriod = consolidatePeriod
      self.dryRun = dryRun
    }

    public init?(_ config: ZFSTools.Action.Config, fileManager: FileManager) {
      guard let decoded: Self = fileManager.decodedJSON(atPath: config.path) else { return nil }
      self = decoded
    }
  }
}
