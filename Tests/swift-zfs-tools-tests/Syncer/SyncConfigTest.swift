import Foundation
import XCTest

@testable import swift_zfs_tools

class SyncConfigTest: XCTestCase {
  func testConfigDecode() throws {
    let data = try XCTUnwrap(Self.defaultConfigEncode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(ZFSTools.Action.Config.Sync.self, from: data))
    XCTAssertEqual(Self.defaultConfig, config)
  }

  func testConfigDecodeEncoded() throws {
    let data = try XCTUnwrap(Self.defaultConfigDecode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(ZFSTools.Action.Config.Sync.self, from: data))
    XCTAssertEqual(Self.defaultConfig, config)
  }

  func testConfigCodable() throws {
    let data = try JSONEncoder().encode(Self.defaultConfig)
    let string = String(data: data, encoding: .utf8)
    XCTAssertEqual(Self.defaultConfigEncode, string)
  }

  func testConfigFromFile() throws {
    let config: ZFSTools.Action.Config.Sync = TestUtilities.decodedJSON(fileName: "SyncConfigTest_config")
    XCTAssertEqual(Self.defaultConfig, config)
  }
}

extension SyncConfigTest {
  static let defaultConfig = TestUtilities.syncConfig()

  static let defaultConfigEncode = "{\"dryRun\":false,\"sshUser\":\"sshUser\",\"sshPort\":\"sshPort\",\"datasetMatch\":\"nas_12tb\\/nas\",\"sshKeyPath\":\"sshKeyPath\",\"sshIP\":\"sshIP\",\"snapshotDateSeparator\":\"@\"}"

  static let defaultConfigDecode = """
    {
      "dryRun": false,
      "snapshotDateSeparator": "@",
      "datasetMatch": "nas_12tb\\/nas",
      "sshPort": "sshPort",
      "sshKeyPath": "sshKeyPath",
      "sshUser": "sshUser",
      "sshIP": "sshIP"
    }
    """
}
