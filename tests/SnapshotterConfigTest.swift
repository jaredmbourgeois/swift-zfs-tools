import Foundation
import XCTest

@testable import ZFSToolsModel

class SnapshotterConfigTest: XCTestCase {
  func testConfigDecode() throws {
    let data = try XCTUnwrap(Self.defaultConfigEncode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(Snapshotter.Config.self, from: data))
    XCTAssertEqual(Self.defaultConfig, config)
  }

  func testConfigDecodeEncoded() throws {
    let data = try XCTUnwrap(Self.defaultConfigDecode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(Snapshotter.Config.self, from: data))
    XCTAssertEqual(Self.defaultConfig, config)
  }

  func testConfigCodable() throws {
    let data = try JSONEncoder().encode(Self.defaultConfig)
    let string = String(data: data, encoding: .utf8)
    XCTAssertEqual(Self.defaultConfigEncode, string)
  }

  func testConfigFromFile() throws {
    let config: Snapshotter.Config = decodeResource(named: "SnapshotterConfig", fileManager: .default)
    XCTAssertEqual(Self.defaultConfig, config)
  }
}

extension SnapshotterConfigTest {
  static let defaultDataset = "nas_12tb/nas"
  static let defaultConfig = snapshotConfig(dataset: defaultDataset)

  static func snapshotConfig(
    dataset: String = defaultDataset,
    recursive: Bool = true,
    dateSeparator: String = Defaults.dateSeparator,
    execute: Bool = Defaults.execute
  ) -> Snapshotter.Config {
    .init(
      dataset: dataset,
      dateSeparator: dateSeparator,
      execute: execute,
      recursive: recursive
    )
  }

  static let defaultConfigEncode = "{\"execute\":false,\"dateSeparator\":\"@\",\"dataset\":\"nas_12tb\\/nas\",\"recursive\":true}"

  static let defaultConfigDecode = """
    {
      "execute": false,
      "dateSeparator": "@",
      "dataset": "nas_12tb/nas",
      "recursive": true
    }
    """
}
