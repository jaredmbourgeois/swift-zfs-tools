import Foundation
import XCTest

@testable import ZFSToolsModel

class SyncerConfigTest: XCTestCase {
  func testConfigDecode() throws {
    let data = try XCTUnwrap(Self.defaultConfigEncode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(Syncer.Config.self, from: data))
    XCTAssertEqual(Self.defaultConfig, config)
  }

  func testConfigDecodeEncoded() throws {
    let data = try XCTUnwrap(Self.defaultConfigDecode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(Syncer.Config.self, from: data))
    XCTAssertEqual(Self.defaultConfig, config)
  }

  func testConfigCodable() throws {
    let data = try JSONEncoder().encode(Self.defaultConfig)
    let string = String(data: data, encoding: .utf8)
    XCTAssertEqual(Self.defaultConfigEncode, string)
  }

  func testConfigFromFile() throws {
    let config: Syncer.Config = decodeResource(named: "SyncerConfig", fileManager: .default)
    XCTAssertEqual(Self.defaultConfig, config)
  }
}

extension SyncerConfigTest {
  static let defaultConfig = syncConfig()
  static let dataset = "nas_12tb/nas"
  static let sshPort = "sshPort"
  static let sshKeyPath = "sshKeyPath"
  static let sshUser = "sshUser"
  static let sshIP = "sshIP"

  static func syncConfig(
    dataset: String = dataset,
    dateSeparator: String = Defaults.dateSeparator,
    sshPort: String = sshPort,
    sshKeyPath: String = sshKeyPath,
    sshUser: String = sshUser,
    sshIP: String = sshIP,
    execute: Bool = Defaults.execute
  ) -> Syncer.Config {
    .init(
      datasetGrep: dataset,
      dateSeparator: dateSeparator,
      sshPort: sshPort,
      sshKeyPath: sshKeyPath,
      sshUser: sshUser,
      sshIP: sshIP,
      execute: execute
    )
  }

  static let defaultConfigEncode = "{\"dateSeparator\":\"@\",\"sshUser\":\"sshUser\",\"sshPort\":\"sshPort\",\"execute\":false,\"sshIP\":\"sshIP\",\"sshKeyPath\":\"sshKeyPath\",\"datasetGrep\":\"nas_12tb\\/nas\"}"

  static let defaultConfigDecode = """
    {
      "execute": false,
      "dateSeparator": "@",
      "datasetGrep": "nas_12tb/nas",
      "sshPort": "sshPort",
      "sshKeyPath": "sshKeyPath",
      "sshUser": "sshUser",
      "sshIP": "sshIP"
    }
    """
}
