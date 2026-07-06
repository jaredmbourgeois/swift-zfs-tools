// SyncerConfigTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import XCTest

@testable import ZFSToolsModel

final class SyncerConfigTest: XCTestCase {
    func testConfigDecode() throws {
        let data = try XCTUnwrap(Self.defaultConfigEncode.data(using: .utf8))
        let config = try XCTUnwrap(JSONDecoder().decode(Syncer.Config.self, from: data))
        XCTAssertEqual(Self.defaultConfig, config)
    }

    func testConfigDecodeEncoded() throws {
        let data = try XCTUnwrap(Self.defaultConfigDecode.data(using: .utf8))
        let config = try XCTUnwrap(JSONDecoder().decode(Syncer.Config.self, from: data))
        XCTAssertEqual(Self.defaultConfig, config)
    }

    func testConfigCodable() throws {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .sortedKeys
        let data = try jsonEncoder.encode(Self.defaultConfig)
        let string = String(data: data, encoding: .utf8)
        XCTAssertEqual(Self.defaultConfigEncode, string)
    }

    func testConfigCodableWithSendRateLimit() throws {
        let config = Self.syncConfig(sendRateLimit: "20M")
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .sortedKeys
        let data = try jsonEncoder.encode(config)
        let decoded = try JSONDecoder().decode(Syncer.Config.self, from: data)

        XCTAssertEqual(config, decoded)
        XCTAssertTrue(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("\"sendRateLimit\":\"20M\""))
    }

    func testConfigFromFile() throws {
        let config: Syncer.Config = try decodeResourceJSON(named: "SyncerConfig", fileManager: .default, jsonDecoder: JSONDecoder())
        XCTAssertEqual(Self.defaultConfig, config)
    }
}

extension SyncerConfigTest {
    static let defaultConfig = syncConfig()
    static let datasetGrep = "nas_12tb/nas"
    static let sshPort = "sshPort"
    static let sshKeyPath = "sshKeyPath"
    static let sshUser = "sshUser"
    static let sshIP = "sshIP"

    static func syncConfig(
        datasetGrep: String = datasetGrep,
        dateSeparator: String = Defaults.dateSeparator,
        execute: Bool = Defaults.execute,
        lineSeparator: String = Defaults.lineSeparator,
        sshPort: String = sshPort,
        sshKeyPath: String = sshKeyPath,
        sshUser: String = sshUser,
        sshIP: String = sshIP,
        stringEncoding: String.Encoding = Defaults.stringEncoding,
        sendRateLimit: String? = nil,
        pruneRemoteSnapshots: Bool = true,
        sentBookmarkName: String? = nil,
        remotePathStrip: String? = nil,
        remotePathRoot: String? = nil
    ) -> Syncer.Config {
        .init(
            datasetGrep: datasetGrep,
            dateSeparator: dateSeparator,
            execute: execute,
            lineSeparator: lineSeparator,
            sshPort: sshPort,
            sshKeyPath: sshKeyPath,
            sshUser: sshUser,
            sshIP: sshIP,
            stringEncoding: stringEncoding,
            sendRateLimit: sendRateLimit,
            pruneRemoteSnapshots: pruneRemoteSnapshots,
            sentBookmarkName: sentBookmarkName,
            remotePathStrip: remotePathStrip,
            remotePathRoot: remotePathRoot
        )
    }

  // Optional remotePath* fields default to nil; the synthesized Codable for Optional uses
  // encodeIfPresent so nil values are omitted from the encoded JSON. Decode accepts both
  // missing keys and explicit nulls.
  static let defaultConfigEncode = "{\"datasetGrep\":\"nas_12tb\\/nas\",\"dateSeparator\":\"@\",\"execute\":false,\"lineSeparator\":\"\\n\",\"pruneRemoteSnapshots\":true,\"sshIP\":\"sshIP\",\"sshKeyPath\":\"sshKeyPath\",\"sshPort\":\"sshPort\",\"sshUser\":\"sshUser\",\"stringEncodingRawValue\":4}"

  static let defaultConfigDecode = """
    {
        "execute": false,
        "dateSeparator": "@",
        "datasetGrep": "nas_12tb/nas",
        "lineSeparator": "\\n",
        "sshPort": "sshPort",
        "sshKeyPath": "sshKeyPath",
        "sshUser": "sshUser",
        "sshIP": "sshIP",
        "stringEncodingRawValue": 4
    }
    """
}
