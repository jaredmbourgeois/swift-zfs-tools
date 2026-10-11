// SnapshotterConfigTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import XCTest

@testable import ZFSToolsModel

final class SnapshotterConfigTest: XCTestCase {
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
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .sortedKeys
        let data = try jsonEncoder.encode(Self.defaultConfig)
        let string = String(data: data, encoding: .utf8)
        XCTAssertEqual(Self.defaultConfigEncode, string)
    }

    func testConfigFromFile() throws {
        let config: Snapshotter.Config = try decodeResourceJSON(named: "SnapshotterConfig", jsonDecoder: JSONDecoder())
        XCTAssertEqual(Self.defaultConfig, config)
    }
}

extension SnapshotterConfigTest {
    static let defaultDataset = "nas_12tb/nas"
    static let defaultConfig = snapshotConfig(recursive: true, excludedDatasetGreps: [], execute: false)

    /// A snapshot config for `defaultDataset` with the tool's standard separators and encoding and
    /// no pool guard, none of which a test using it varies. The test states the rest.
    static func snapshotConfig(
        recursive: Bool,
        excludedDatasetGreps: [String],
        execute: Bool
    ) -> Snapshotter.Config {
        .init(
            datasetGrep: defaultDataset,
            dateSeparator: Defaults.dateSeparator,
            execute: execute,
            excludedDatasetGreps: excludedDatasetGreps,
            lineSeparator: Defaults.lineSeparator,
            maxPoolUtilizationPercent: nil,
            minFreeBytes: nil,
            recursive: recursive,
            stringEncodingRawValue: Defaults.stringEncoding.rawValue
        )
    }

    static let defaultConfigEncode = "{\"datasetGrep\":\"nas_12tb\\/nas\",\"dateSeparator\":\"@\",\"excludedDatasetGreps\":[],\"execute\":false,\"lineSeparator\":\"\\n\",\"recursive\":true,\"stringEncodingRawValue\":4}"

    static let defaultConfigDecode = """
    {
        "datasetGrep": "nas_12tb/nas",
        "dateSeparator": "@",
        "execute": false,
        "lineSeparator": "\\n",
        "recursive": true,
        "stringEncodingRawValue": 4
    }
    """
}
