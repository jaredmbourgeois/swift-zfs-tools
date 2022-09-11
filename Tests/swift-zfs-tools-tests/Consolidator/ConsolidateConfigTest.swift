import Foundation
import XCTest

@testable import swift_zfs_tools

class ConsolidateConfigTest: XCTestCase {
  func testConfigDecode() throws {
    let data = try XCTUnwrap(Self.defaultConfigEncode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(ZFSTools.Action.Config.Consolidate.self, from: data))
    XCTAssertEqual(TestUtilities.consolidateConfig(), config)
  }

  func testConfigDecodeEncoded() throws {
    let data = try XCTUnwrap(Self.defaultConfigDecode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(ZFSTools.Action.Config.Consolidate.self, from: data))
    XCTAssertEqual(TestUtilities.consolidateConfig(), config)
  }

  func testConfigCodable() throws {
    let data = try JSONEncoder().encode(Self.defaultConfig)
    let string = String(data: data, encoding: .utf8)
    XCTAssertEqual(Self.defaultConfigEncode, string)
  }

  func testConfigFromFile() throws {
    let config: ZFSTools.Action.Config.Consolidate = TestUtilities.decodedJSON(fileName: "ConsolidatorConfigTest_config")
    XCTAssertEqual(TestUtilities.consolidateConfig(), config)
  }

  func testConfigNoUpperBound() throws {
    let data = try XCTUnwrap(Self.noUpperBoundConfigDecode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(ZFSTools.Action.Config.Consolidate.self, from: data))
    let expected = TestUtilities.consolidateConfig(period: ZFSTools.Consolidator.ConsolidatePeriod.ConsolidatePeriodBuilder()
      .snapshotPeriod(snapshots: 7)
        .with(days: 1)
        .snapshotPeriodComplete()
      .snapshotPeriod(snapshots: 3)
        .with(weeksOfYear: 1)
        .snapshotPeriodComplete()
      .snapshotPeriod(snapshots: 11)
        .with(months: 1)
        .snapshotPeriodComplete()
      .snapshotPeriod(snapshots: 16)
        .with(months: 3)
        .snapshotPeriodComplete()
      .snapshotPeriod(snapshots: 10)
        .with(months: 6)
        .snapshotPeriodComplete()
      .build())
    XCTAssertEqual(expected, config)
  }
}

extension ConsolidateConfigTest {
  static let defaultConfig = TestUtilities.consolidateConfig(
    period: TestUtilities.consolidatePeriodDefault
  )

  static let defaultConfigEncode = "{\"snapshotsNotConsolidated\":[],\"consolidatePeriod\":{\"upperBound\":\"\(TestUtilities.upperBound)\",\"snapshotPeriodBias\":{\"upperBound\":{}},\"snapshotPeriods\":[{\"snapshots\":7,\"frequency\":[{\"day\":{\"_0\":1}}]},{\"snapshots\":3,\"frequency\":[{\"weekOfYear\":{\"_0\":1}}]},{\"snapshots\":11,\"frequency\":[{\"month\":{\"_0\":1}}]},{\"snapshots\":16,\"frequency\":[{\"month\":{\"_0\":3}}]},{\"snapshots\":10,\"frequency\":[{\"month\":{\"_0\":6}}]}]},\"snapshotDateSeparator\":\"@\",\"datasetMatch\":\"nas_12tb\\/nas\",\"dryRun\":false}"

  static let defaultConfigDecode = """
    {
      "snapshotsNotConsolidated": [],
      "consolidatePeriod": {
        "upperBound": \"\(TestUtilities.upperBound)\",
        "snapshotPeriodBias": {
          "upperBound": {}
        },
        "snapshotPeriods": [
          {
            "snapshots": 7,
            "frequency": [
              {
                "day": {
                  "_0": 1
                }
              }
            ]
          },
          {
            "snapshots": 3,
            "frequency": [
              {
                "weekOfYear": {
                  "_0": 1
                }
              }
            ]
          },
          {
            "snapshots": 11,
            "frequency": [
              {
                "month": {
                  "_0": 1
                }
              }
            ]
          },
          {
            "snapshots": 16,
            "frequency": [
              {
                "month": {
                  "_0": 3
                }
              }
            ]
          },
          {
            "snapshots": 10,
            "frequency": [
              {
                "month": {
                  "_0": 6
                }
              }
            ]
          }
        ]
      },
      "snapshotDateSeparator": "@",
      "datasetMatch": "nas_12tb\\/nas",
      "dryRun": false
    }
    """

  static let noUpperBoundConfigDecode = """
    {
      "snapshotsNotConsolidated": [],
      "consolidatePeriod": {
        "snapshotPeriodBias": {
          "upperBound": {}
        },
        "snapshotPeriods": [
          {
            "snapshots": 7,
            "frequency": [
              {
                "day": {
                  "_0": 1
                }
              }
            ]
          },
          {
            "snapshots": 3,
            "frequency": [
              {
                "weekOfYear": {
                  "_0": 1
                }
              }
            ]
          },
          {
            "snapshots": 11,
            "frequency": [
              {
                "month": {
                  "_0": 1
                }
              }
            ]
          },
          {
            "snapshots": 16,
            "frequency": [
              {
                "month": {
                  "_0": 3
                }
              }
            ]
          },
          {
            "snapshots": 10,
            "frequency": [
              {
                "month": {
                  "_0": 6
                }
              }
            ]
          }
        ]
      },
      "snapshotDateSeparator": "@",
      "datasetMatch": "nas_12tb\\/nas",
      "dryRun": false
    }
    """
}
