// ConsolidatorConfigTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import XCTest

@testable import ZFSToolsModel

final class ConsolidatorConfigTest: XCTestCase {
    private let defaultConfig = ConsolidatorConfigTest.defaultScheduleConfig(upperBound: testDateString)

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

    /// The two fixtures in `tests/resource/`: one names the schedule's upper bound, one leaves it out.
    func testConfigFromJSON() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(defaultConfig, try decodeResourceJSON(named: "ConsolidatorConfig", jsonDecoder: decoder))
        XCTAssertEqual(
            Self.defaultScheduleConfig(upperBound: nil),
            try decodeResourceJSON(named: "ConsolidatorConfigNoUpperBound", jsonDecoder: decoder)
        )
    }

    // MARK: - Period decode validation

    func testPeriodDecodeRejectsZeroEveryMultiple() throws {
        let json = #"{"everyMultiple":0,"everyPeriod":"days","repetitions":7,"snapshots":1}"#
        XCTAssertThrowsError(
            try JSONDecoder().decode(Consolidator.SnapshotConsolidationPeriod.self, from: json.data(using: .utf8)!)
        ) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("expected DecodingError.dataCorrupted, got \(error)")
            }
        }
    }

    func testPeriodDecodeRejectsZeroSnapshots() throws {
        let json = #"{"everyMultiple":1,"everyPeriod":"days","repetitions":7,"snapshots":0}"#
        XCTAssertThrowsError(
            try JSONDecoder().decode(Consolidator.SnapshotConsolidationPeriod.self, from: json.data(using: .utf8)!)
        ) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("expected DecodingError.dataCorrupted, got \(error)")
            }
        }
    }

    func testPeriodDecodeAcceptsValidValuesWithoutRepetitions() throws {
        let json = #"{"everyMultiple":2,"everyPeriod":"weeks","snapshots":3}"#
        let period = try JSONDecoder().decode(Consolidator.SnapshotConsolidationPeriod.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(2, period.everyMultiple)
        XCTAssertEqual(.weeks, period.everyPeriod)
        XCTAssertEqual(3, period.snapshots)
        XCTAssertNil(period.repetitions)
    }
}

extension ConsolidatorConfigTest {
    /// An executing consolidation of `nas_12tb/nas/` on the tool's default retention schedule, with
    /// no pool threshold and nothing protected: the config the JSON fixtures hold. `upperBound` is
    /// the schedule's reference time (`nil`: the time the run starts).
    static func defaultScheduleConfig(upperBound: String?) -> Consolidator.Config {
        .init(
            datasetGrep: "nas_12tb/nas/",
            dateSeparator: "@",
            execute: true,
            lineSeparator: "\n",
            maxPoolUtilizationPercent: nil,
            minFreeBytes: nil,
            schedule: Defaults.consolidationSchedule(upperBound: upperBound),
            snapshotsNotConsolidated: [],
            stringEncoding: .utf8
        )
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
