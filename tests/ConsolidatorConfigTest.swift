import ArgumentParser
import Foundation
import XCTest

@testable import ZFSToolsModel

class ConsolidatorConfigTest: XCTestCase {
  private lazy var dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = Defaults.dateFormat
    return dateFormatter
  }()

  private lazy var defaultConfig: Consolidator.Config = {
    Self.config(dateFormatter: dateFormatter, fileManager: fileManager)
  }()

  private let fileManager = FileManager.default

  func testConfigDecode() throws {
    let data = try XCTUnwrap(Self.defaultConfigEncode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(Consolidator.Config.self, from: data))
    XCTAssertEqual(defaultConfig, config)
  }

  func testConfigDecodeEncoded() throws {
    let data = try XCTUnwrap(Self.defaultConfigDecode.data(using: .utf8))
    let config = try XCTUnwrap(JSONDecoder().decode(Consolidator.Config.self, from: data))
    XCTAssertEqual(defaultConfig, config)
  }

  func testConfigCodable() throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(defaultConfig)
    let string = String(data: data, encoding: .utf8)
    XCTAssertEqual(Self.defaultConfigEncode, string)
  }

  func testConfigFromJSON() {
    XCTAssertEqual(defaultConfig, decodeResource(named: "ConsolidatorConfig", fileManager: fileManager))
  }
}

extension ConsolidatorConfigTest {
  static func config(
    arguments: Arguments.Consolidate? = nil,
    consolidationPeriod: Consolidator.ConsolidationPeriod? = nil,
    dateFormatter: DateFormatter,
    fileManager: FileManager
  ) -> Consolidator.Config {
    let arguments = try! arguments ?? .parse([
      "--dataset-grep", "nas_12tb/nas/",
      "--execute", "true"
    ])
    return try! Consolidator.Config(
      arguments: arguments,
      fileManager: fileManager,
      jsonDecoder: JSONDecoder(),
      dateFormatter: dateFormatter,
      date: { defaultConfigDate }
    )
  }

  static func consolidationPeriodDays(
    _ days: UInt16 = 1,
    snapshots: UInt16 = 365,
    upperBound: Date = ConsolidatorConfigTest.defaultConfigDate
  ) -> Consolidator.ConsolidationPeriod {
    Consolidator.ConsolidationPeriod.ConsolidationPeriodBuilder(upperBound: upperBound)
      .snapshotPeriod(snapshots: snapshots)
        .with(days: days)
        .snapshotPeriodComplete()
      .build()
  }

  static func consolidationPeriodWeeks(
    _ weeksOfYear: UInt16 = 1,
    snapshots: UInt16 = 365,
    upperBound: Date = ConsolidatorConfigTest.defaultConfigDate
  ) -> Consolidator.ConsolidationPeriod {
    Consolidator.ConsolidationPeriod.ConsolidationPeriodBuilder(upperBound: upperBound)
      .snapshotPeriod(snapshots: snapshots)
        .with(weeksOfYear: weeksOfYear)
        .snapshotPeriodComplete()
      .build()
  }

  static let defaultConfigEncode = "{\"snapshotsNotConsolidated\":[],\"execute\":true,\"datasetGrep\":\"nas_12tb\\/nas\\/\",\"dateSeparator\":\"@\",\"consolidationPeriod\":{\"snapshotPeriodBias\":{\"upperBound\":{}},\"upperBound\":681109200,\"snapshotPeriods\":[{\"snapshots\":7,\"frequency\":[{\"day\":{\"_0\":1}}]},{\"snapshots\":3,\"frequency\":[{\"weekOfYear\":{\"_0\":1}}]},{\"snapshots\":11,\"frequency\":[{\"month\":{\"_0\":1}}]},{\"snapshots\":4,\"frequency\":[{\"month\":{\"_0\":3}}]},{\"snapshots\":97,\"frequency\":[{\"year\":{\"_0\":1}}]}]}}"

  static let defaultConfigDateEpoch = 1659416400.0
  static let defaultConfigDate = Date(timeIntervalSince1970: defaultConfigDateEpoch) // August 2, 2022

  static let defaultConfigDecode = """
  {
    "snapshotsNotConsolidated": [],
    "execute": true,
    "datasetGrep": "nas_12tb\\/nas\\/",
    "dateSeparator": "@",
    "consolidationPeriod": {
      "snapshotPeriodBias": {
        "upperBound": {}
      },
      "upperBound": 681109200,
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
          "snapshots": 4,
          "frequency": [
            {
              "month": {
                "_0": 3
              }
            }
          ]
        },
        {
          "snapshots": 97,
          "frequency": [
            {
              "year": {
                "_0": 1
              }
            }
          ]
        }
      ]
    }
  }
  """
}

