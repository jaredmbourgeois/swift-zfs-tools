// ConsolidatorConfigTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import ArgumentParser
import Foundation
import XCTest

@testable import ZFSToolsModel

final class ConsolidatorConfigTest: XCTestCase {
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
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(defaultConfig)
        let string = String(data: data, encoding: .utf8)
        XCTAssertEqual(Self.defaultConfigEncode, string)
    }

    func testConfigFromJSON() {
        let decoder = JSONDecoder()
        XCTAssertEqual(defaultConfig, decodeResourceJSON(named: "ConsolidatorConfig", fileManager: fileManager, jsonDecoder: decoder))
        XCTAssertEqual(
            Self.config(
                date: nil,
                dateFormatter: dateFormatter,
                fileManager: fileManager
            ),
            decodeResourceJSON(named: "ConsolidatorConfigNoUpperBound", fileManager: fileManager, jsonDecoder: decoder)
        )
    }
}

extension ConsolidatorConfigTest {
    static func config(
        consolidationSchedule: Consolidator.SnapshotConsolidationSchedule? = nil,
        date: String? = testDateString,
        dateFormatter: DateFormatter,
        fileManager: FileManager
    ) -> Consolidator.Config {
        .init(
            datasetGrep: "nas_12tb/nas/",
            dateSeparator: "@",
            execute: true,
            lineSeparator: "\n",
            schedule: consolidationSchedule ?? Defaults.consolidationSchedule(upperBound: date),
            snapshotsNotConsolidated: [],
            stringEncoding: .utf8
        )
    }

    static func consolidationPeriodDays(
        upperBound: String = testDateString
    ) -> Consolidator.SnapshotConsolidationSchedule {
        Consolidator.SnapshotConsolidationSchedule.Builder(upperBound: upperBound)
            .keepingSnapshots(1, every: 1, .days, repeatedBy: 365)
            .build()
    }

    static func consolidationPeriodWeeks(
        upperBound: String = testDateString
    ) -> Consolidator.SnapshotConsolidationSchedule {
        Consolidator.SnapshotConsolidationSchedule.Builder(upperBound: upperBound)
            .keepingSnapshots(1, every: 1, .weeks, repeatedBy: 52)
            .build()
    }

    static let defaultConfigEncode = "{\"datasetGrep\":\"nas_12tb\\/nas\\/\",\"dateSeparator\":\"@\",\"execute\":true,\"lineSeparator\":\"\\n\",\"schedule\":{\"periods\":[{\"everyMultiple\":1,\"everyPeriod\":\"days\",\"repetitions\":7,\"snapshots\":1},{\"everyMultiple\":1,\"everyPeriod\":\"weeks\",\"repetitions\":3,\"snapshots\":1},{\"everyMultiple\":1,\"everyPeriod\":\"months\",\"repetitions\":11,\"snapshots\":1},{\"everyMultiple\":1,\"everyPeriod\":\"years\",\"snapshots\":1}],\"upperBound\":\"\(testDateString)\"},\"snapshotsNotConsolidated\":[],\"stringEncodingRawValue\":4}"

    static let defaultConfigDecode = """
    {
      "datasetGrep": "nas_12tb\\/nas\\/",
      "dateSeparator": "@",
      "execute": true,
      "lineSeparator": "\\n",
      "schedule": {
        "periods": [
          {
            "everyMultiple": 1,
            "everyPeriod": "days",
            "repetitions": 7,
            "snapshots": 1
          },
          {
            "everyMultiple": 1,
            "everyPeriod": "weeks",
            "repetitions": 3,
            "snapshots": 1
          },
          {
            "everyMultiple": 1,
            "everyPeriod": "months",
            "repetitions": 11,
            "snapshots": 1
          },
          {
            "everyMultiple": 1,
            "everyPeriod": "years",
            "snapshots": 1
          }
        ],
        "upperBound": "\(testDateString)"
      },
      "snapshotsNotConsolidated": [],
      "stringEncodingRawValue": 4
    }
    """
}
