import Foundation
import XCTest

@testable import swift_zfs_tools

class SnapshotConfigTest: XCTestCase {
  func testConfigDecode() throws {
    let data = try XCTUnwrap(Self.defaultConfigEncode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(ZFSTools.Action.Config.Snapshot.self, from: data))
    XCTAssertEqual(Self.defaultConfig, config)
  }

  func testConfigDecodeEncoded() throws {
    let data = try XCTUnwrap(Self.defaultConfigDecode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(ZFSTools.Action.Config.Snapshot.self, from: data))
    XCTAssertEqual(Self.defaultConfig, config)
  }

  func testConfigCodable() throws {
    let data = try JSONEncoder().encode(Self.defaultConfig)
    let string = String(data: data, encoding: .utf8)
    XCTAssertEqual(Self.defaultConfigEncode, string)
  }

  func testConfigFromFile() throws {
    let config: ZFSTools.Action.Config.Snapshot = TestUtilities.decodedJSON(fileName: "SnapshotConfigTest_config")
    XCTAssertEqual(Self.defaultConfig, config)
  }
}

extension SnapshotConfigTest {
  static let defaultConfig = TestUtilities.snapshotConfig()

  static let defaultConfigEncode = "{\"dryRun\":false,\"dateSeparator\":\"@\",\"dataset\":\"nas_12tb\\/nas\",\"recursive\":true}"

  static let defaultConfigDecode = """
    {
       "dryRun":false,
       "dateSeparator":"@",
       "dataset":"nas_12tb\\/nas",
       "recursive":true
    }
    """
}
