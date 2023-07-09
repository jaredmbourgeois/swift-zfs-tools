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
        let config: Snapshotter.Config = decodeResourceJSON(named: "SnapshotterConfig", fileManager: .default, jsonDecoder: JSONDecoder())
        XCTAssertEqual(Self.defaultConfig, config)
    }
}

extension SnapshotterConfigTest {
    static let defaultDataset = "nas_12tb/nas"
    static let defaultConfig = snapshotConfig(datasetGrep: defaultDataset)

    static func snapshotConfig(
        datasetGrep: String = defaultDataset,
        recursive: Bool = true,
        dateSeparator: String = Defaults.dateSeparator,
        lineSeparator: String = Defaults.lineSeparator,
        execute: Bool = Defaults.execute,
        stringEncodingRawValue: String.Encoding.RawValue = Defaults.stringEncoding.rawValue
    ) -> Snapshotter.Config {
        .init(
            datasetGrep: datasetGrep,
            dateSeparator: dateSeparator,
            execute: execute,
            lineSeparator: lineSeparator,
            recursive: recursive,
            stringEncodingRawValue: stringEncodingRawValue
        )
    }

    static let defaultConfigEncode = "{\"datasetGrep\":\"nas_12tb\\/nas\",\"dateSeparator\":\"@\",\"execute\":false,\"lineSeparator\":\"\\n\",\"recursive\":true,\"stringEncodingRawValue\":4}"

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
