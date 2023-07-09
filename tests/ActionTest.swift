// ActionTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import XCTest

@testable import ZFSToolsModel

final class ActionTest: XCTestCase {
  func testEncode() throws {
    let data = try JSONEncoder().encode(Self.actions)
    let string = String(data: data, encoding: .utf8)
    XCTAssertEqual(Self.actionsEncode, string)
  }

  func testDecode() throws {
    let data = try XCTUnwrap(Self.actionsDecode.data(using: .utf8))
    let actions = try XCTUnwrap(JSONDecoder().decode([Action].self, from: data))
    XCTAssertEqual(Self.actions, actions)
  }

  func testFromJSON() throws {
      let actions: [Action] = decodeResourceJSON(named: "Actions", fileManager: .default, jsonDecoder: JSONDecoder())
    XCTAssertEqual(Self.actions, actions)
  }
}

extension ActionTest {
  static let snapshotConfigPathA = "/snapshots/dataset-a-snapshot.json"

  static let actions: [Action] = [
    // dataset A
    .snapshot(configPath: "/snapshots/dataset-a-snapshot.json"),
    .consolidate(configPath: "/snapshots/dataset-a-consolidate.json"),
    .sync(configPath: "/snapshots/dataset-a-sync.json"),
    // dataset B
    .snapshot(configPath: "/snapshots/dataset-b-snapshot.json"),
    .consolidate(configPath: "/snapshots/dataset-b-consolidate.json"),
    .sync(configPath: "/snapshots/dataset-b-sync.json")
  ]

  static let actionsEncode = "[{\"snapshot\":{\"configPath\":\"\\/snapshots\\/dataset-a-snapshot.json\"}},{\"consolidate\":{\"configPath\":\"\\/snapshots\\/dataset-a-consolidate.json\"}},{\"sync\":{\"configPath\":\"\\/snapshots\\/dataset-a-sync.json\"}},{\"snapshot\":{\"configPath\":\"\\/snapshots\\/dataset-b-snapshot.json\"}},{\"consolidate\":{\"configPath\":\"\\/snapshots\\/dataset-b-consolidate.json\"}},{\"sync\":{\"configPath\":\"\\/snapshots\\/dataset-b-sync.json\"}}]"

  static let actionsDecode = """
  [
    {
      "snapshot": {
        "configPath":"/snapshots/dataset-a-snapshot.json"
      }
    },
    {
      "consolidate": {
        "configPath":"/snapshots/dataset-a-consolidate.json"
      }
    },
    {
      "sync": {
        "configPath":"/snapshots/dataset-a-sync.json"
      }
    },
    {
      "snapshot": {
        "configPath":"/snapshots/dataset-b-snapshot.json"
      }
    },
    {
      "consolidate": {
        "configPath":"/snapshots/dataset-b-consolidate.json"
      }
    },
    {
      "sync": {
        "configPath":"/snapshots/dataset-b-sync.json"
      }
    }
  ]
  """
}
