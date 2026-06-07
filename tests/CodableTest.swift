// CodableTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import XCTest

@testable import ZFSToolsModel

// Exercises the JSON read/write helpers through the injectable FileSystem witness — no disk.
final class CodableTest: XCTestCase {
    private struct Sample: Codable, Equatable {
        let name: String
        let count: Int
    }

    func testDecodeReadsAndDecodes() throws {
        let sample = Sample(name: "tank", count: 7)
        let store = InMemoryFileStore(["/config.json": try JSONEncoder().encode(sample)])
        let decoded: Sample = try decodeFromJSONAtPath("/config.json", fileSystem: .inMemory(store), jsonDecoder: JSONDecoder())
        XCTAssertEqual(sample, decoded)
    }

    func testDecodeThrowsWhenMissing() {
        let store = InMemoryFileStore()
        do {
            let _: Sample = try decodeFromJSONAtPath("/missing.json", fileSystem: .inMemory(store), jsonDecoder: JSONDecoder())
            XCTFail("expected fileNotFound")
        } catch {
            // expected
        }
    }

    func testDecodeThrowsOnInvalidJSON() {
        let store = InMemoryFileStore(["/bad.json": Data("not json".utf8)])
        do {
            let _: Sample = try decodeFromJSONAtPath("/bad.json", fileSystem: .inMemory(store), jsonDecoder: JSONDecoder())
            XCTFail("expected jsonDecodeFailed")
        } catch {
            // expected
        }
    }

    func testEncodeWritesDecodableJSON() throws {
        let store = InMemoryFileStore()
        let sample = Sample(name: "tank", count: 7)
        try encode(sample, toJSONAtPath: "/out.json", fileSystem: .inMemory(store), jsonEncoder: JSONEncoder())
        let written = try XCTUnwrap(store.data(at: "/out.json"))
        XCTAssertEqual(sample, try JSONDecoder().decode(Sample.self, from: written))
    }

    func testEncodeAppendsJSONExtension() throws {
        let store = InMemoryFileStore()
        try encode(Sample(name: "x", count: 1), toJSONAtPath: "/out", fileSystem: .inMemory(store), jsonEncoder: JSONEncoder())
        XCTAssertNotNil(store.data(at: "/out.json"))
    }

    func testEncodeThrowsOnWriteFailure() {
        struct WriteError: Error {}
        let failing = FileSystem(contents: { _ in nil }, write: { _, _ in throw WriteError() })
        do {
            try encode(Sample(name: "x", count: 1), toJSONAtPath: "/out.json", fileSystem: failing, jsonEncoder: JSONEncoder())
            XCTFail("expected writeToURL error")
        } catch {
            // expected
        }
    }
}
