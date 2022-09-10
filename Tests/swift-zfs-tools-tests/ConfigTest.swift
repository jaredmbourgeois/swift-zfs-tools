import Foundation
import XCTest

@testable import swift_zfs_tools

class ConfigTest: XCTestCase {
  func testConfigDecode() throws {
    let data = try XCTUnwrap(Self.defaultConfigEncode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(ZFSTools.Config.self, from: data))
    XCTAssertEqual(Self.defaultConfig, config)
  }

  func testConfigDecodeEncoded() throws {
    let data = try XCTUnwrap(Self.defaultConfigDecode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(ZFSTools.Config.self, from: data))
    XCTAssertEqual(Self.defaultConfig, config)
  }

  func testConfigCodable() throws {
    let data = try JSONEncoder().encode(Self.defaultConfig)
    let string = String(data: data, encoding: .utf8)
    XCTAssertEqual(Self.defaultConfigEncode, string)
  }

  func testConfigFromFile() throws {
    let config: ZFSTools.Config = TestUtilities.decodedJSON(fileName: "ConfigTest_config")
    XCTAssertEqual(Self.defaultConfig, config)
  }
}

extension ConfigTest {
  static let defaultConfig = TestUtilities.defaultConfig

  static let defaultConfigEncode = "{\"actions\":[{\"snapshot\":{\"_0\":{\"path\":\"snapshotConfig.json\"}}},{\"consolidate\":{\"_0\":{\"path\":\"consolidateConfig.json\"}}},{\"sync\":{\"_0\":{\"path\":\"syncConfig.json\"}}}],\"dateFormat\":\"yyyyMMdd-HHmmss\"}"

  static let defaultConfigDecode = """
    {
      "actions": [
        {
          "snapshot": {
            "_0": {
              "path": "snapshotConfig.json"
            }
          }
        },
        {
          "consolidate": {
            "_0": {
              "path": "consolidateConfig.json"
            }
          }
        },
        {
          "sync": {
            "_0": {
              "path": "syncConfig.json"
            }
          }
        }
      ],
      "dateFormat": "yyyyMMdd-HHmmss"
    }
    """
}
