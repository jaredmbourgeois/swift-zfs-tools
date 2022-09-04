import Foundation

extension ZFSTools {
  public enum Action: Codable, Sendable, Equatable {
    case snapshot(Config)
    case consolidate(Config)
    case sync(Config)
  }
}

extension ZFSTools.Action {
  public struct Config: Codable, Sendable, Equatable {
    public let path: String
  }
}
