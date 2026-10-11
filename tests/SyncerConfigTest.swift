// SyncerConfigTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import ArgumentParser
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
        let config = Self.syncConfig(
            datasetGrep: Self.datasetGrep,
            execute: false,
            sshKeyPath: Self.sshKeyPath,
            sendRateLimit: "20M",
            pruneRemoteSnapshots: false,
            sentBookmarkName: nil,
            remotePathStrip: nil,
            remotePathRoot: nil
        )
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .sortedKeys
        let data = try jsonEncoder.encode(config)
        let decoded = try JSONDecoder().decode(Syncer.Config.self, from: data)

        XCTAssertEqual(config, decoded)
        XCTAssertTrue(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("\"sendRateLimit\":\"20M\""))
    }

    func testConfigFromFile() throws {
        let config: Syncer.Config = try decodeResourceJSON(named: "SyncerConfig", jsonDecoder: JSONDecoder())
        XCTAssertEqual(Self.defaultConfig, config)
    }

    // MARK: - pruneRemoteSnapshots: one default, on the safe side

    /// A saved config that never mentions pruning does not prune, and one that asks for it does:
    /// the destination's snapshots are destroyed only because the config said so.
    func testAConfigPrunesOnlyWhenItSaysSo() throws {
        let silent = try JSONDecoder().decode(Syncer.Config.self, from: Data(Self.defaultConfigDecode.utf8))
        XCTAssertFalse(silent.pruneRemoteSnapshots)
        XCTAssertFalse(Defaults.pruneRemoteSnapshots)

        let asking = Self.defaultConfigDecode.replacingOccurrences(of: "\"execute\": false,", with: "\"execute\": false, \"pruneRemoteSnapshots\": true,")
        XCTAssertTrue(try JSONDecoder().decode(Syncer.Config.self, from: Data(asking.utf8)).pruneRemoteSnapshots)
    }

    /// The command line is the same switch: no `--prune-remote-snapshots`, no prune.
    func testTheCommandLinePrunesOnlyWhenItSaysSo() throws {
        let destination = ["--ssh-user", "u", "--ssh-ip", "host", "--ssh-port", "22", "--ssh-key-path", "/key"]
        XCTAssertFalse(Syncer.Config(arguments: try Arguments.Sync.parse(destination)).pruneRemoteSnapshots)
        XCTAssertTrue(
            Syncer.Config(arguments: try Arguments.Sync.parse(destination + ["--prune-remote-snapshots", "true"])).pruneRemoteSnapshots
        )
        XCTAssertFalse(
            Syncer.Config(arguments: try Arguments.Sync.parse(destination + ["--prune-remote-snapshots", "false"])).pruneRemoteSnapshots
        )
    }
}

extension SyncerConfigTest {
    /// What a config holds when it sets nothing optional: a dry run that prunes nothing.
    static let defaultConfig = syncConfig(
        datasetGrep: datasetGrep,
        execute: false,
        sshKeyPath: sshKeyPath,
        sendRateLimit: nil,
        pruneRemoteSnapshots: false,
        sentBookmarkName: nil,
        remotePathStrip: nil,
        remotePathRoot: nil
    )
    static let datasetGrep = "nas_12tb/nas"
    static let sshPort = "sshPort"
    static let sshKeyPath = "sshKeyPath"
    static let sshUser = "sshUser"
    static let sshIP = "sshIP"

    /// A sync to the test destination: the fixed login `sshUser@sshIP` on port `sshPort`, and the
    /// tool's standard separators and encoding, none of which a sync test varies. The test states
    /// everything else.
    static func syncConfig(
        datasetGrep: String,
        execute: Bool,
        sshKeyPath: String,
        sendRateLimit: String?,
        pruneRemoteSnapshots: Bool,
        sentBookmarkName: String?,
        remotePathStrip: String?,
        remotePathRoot: String?
    ) -> Syncer.Config {
        .init(
            datasetGrep: datasetGrep,
            dateSeparator: Defaults.dateSeparator,
            execute: execute,
            lineSeparator: Defaults.lineSeparator,
            sshPort: sshPort,
            sshKeyPath: sshKeyPath,
            sshUser: sshUser,
            sshIP: sshIP,
            stringEncoding: Defaults.stringEncoding,
            sendRateLimit: sendRateLimit,
            pruneRemoteSnapshots: pruneRemoteSnapshots,
            sentBookmarkName: sentBookmarkName,
            remotePathStrip: remotePathStrip,
            remotePathRoot: remotePathRoot
        )
    }

    /// An executing sync of the default dataset to the test destination with nothing optional set:
    /// no rate limit, no sent-bookmark, no path remapping. The test says whether the destination
    /// is pruned — the one effect switch left.
    static func executingSync(pruneRemoteSnapshots: Bool) -> Syncer.Config {
        syncConfig(
            datasetGrep: datasetGrep,
            execute: true,
            sshKeyPath: sshKeyPath,
            sendRateLimit: nil,
            pruneRemoteSnapshots: pruneRemoteSnapshots,
            sentBookmarkName: nil,
            remotePathStrip: nil,
            remotePathRoot: nil
        )
    }

  // Optional fields hold nil; the synthesized Codable for Optional uses encodeIfPresent, so nil
  // values are omitted from the encoded JSON. Decode accepts both missing keys and explicit nulls.
  static let defaultConfigEncode = "{\"datasetGrep\":\"nas_12tb\\/nas\",\"dateSeparator\":\"@\",\"execute\":false,\"lineSeparator\":\"\\n\",\"pruneRemoteSnapshots\":false,\"sshIP\":\"sshIP\",\"sshKeyPath\":\"sshKeyPath\",\"sshPort\":\"sshPort\",\"sshUser\":\"sshUser\",\"stringEncodingRawValue\":4}"

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
