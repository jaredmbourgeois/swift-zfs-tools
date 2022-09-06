import Foundation

extension ZFSTools {
  public enum Action: ZFSTools.Model {
    case snapshot(Config)
    case consolidate(Config)
    case sync(Config)
  }
}

extension ZFSTools.Action {
  public struct Config: ZFSTools.Model {
    public let path: String
  }
}
