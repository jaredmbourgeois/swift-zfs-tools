// CodableTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import XCTest

@testable import ZFSToolsModel

// Exercises the JSON read/write helpers through the injectable FileSystem witness, against the real
// file system inside a temporary directory each test creates and removes — and the witness's
// test-support double itself, so a double that drifts from a real file system fails here.
final class CodableTest: XCTestCase {
    private struct Sample: Codable, Equatable {
        let name: String
        let count: Int
    }

    func testDecodeReadsAndDecodes() throws {
        let directory = try TestRoot.makeTemporaryDirectory()
        defer { directory.remove() }
        let fileSystem = FileSystem.rooted(at: directory)
        let sample = Sample(name: "tank", count: 7)
        try fileSystem.write(try JSONEncoder().encode(sample), "/config.json")
        let decoded: Sample = try decodeFromJSONAtPath("/config.json", fileSystem: fileSystem, jsonDecoder: JSONDecoder())
        XCTAssertEqual(sample, decoded)
    }

    func testDecodeThrowsWhenMissing() throws {
        let directory = try TestRoot.makeTemporaryDirectory()
        defer { directory.remove() }
        do {
            let _: Sample = try decodeFromJSONAtPath("/missing.json", fileSystem: .rooted(at: directory), jsonDecoder: JSONDecoder())
            XCTFail("expected fileNotFound")
        } catch {
            // expected
        }
    }

    func testDecodeThrowsOnInvalidJSON() throws {
        let directory = try TestRoot.makeTemporaryDirectory()
        defer { directory.remove() }
        let fileSystem = FileSystem.rooted(at: directory)
        try fileSystem.write(Data("not json".utf8), "/bad.json")
        do {
            let _: Sample = try decodeFromJSONAtPath("/bad.json", fileSystem: fileSystem, jsonDecoder: JSONDecoder())
            XCTFail("expected jsonDecodeFailed")
        } catch {
            // expected
        }
    }

    func testEncodeWritesDecodableJSON() throws {
        let directory = try TestRoot.makeTemporaryDirectory()
        defer { directory.remove() }
        let fileSystem = FileSystem.rooted(at: directory)
        let sample = Sample(name: "tank", count: 7)
        try encode(sample, toJSONAtPath: "/out.json", fileSystem: fileSystem, jsonEncoder: JSONEncoder())
        let written = try XCTUnwrap(fileSystem.contents("/out.json"))
        XCTAssertEqual(sample, try JSONDecoder().decode(Sample.self, from: written))
    }

    func testEncodeAppendsJSONExtension() throws {
        let directory = try TestRoot.makeTemporaryDirectory()
        defer { directory.remove() }
        let fileSystem = FileSystem.rooted(at: directory)
        try encode(Sample(name: "x", count: 1), toJSONAtPath: "/out", fileSystem: fileSystem, jsonEncoder: JSONEncoder())
        XCTAssertNotNil(fileSystem.contents("/out.json"))
        XCTAssertEqual(["out.json"], try directory.entryNames())
    }

    func testEncodeThrowsOnWriteFailure() throws {
        struct WriteError: Error {}
        let directory = try TestRoot.makeTemporaryDirectory()
        defer { directory.remove() }
        let failing = FileSystem.rootedFailingEveryWrite(at: directory, with: WriteError())
        do {
            try encode(Sample(name: "x", count: 1), toJSONAtPath: "/out.json", fileSystem: failing, jsonEncoder: JSONEncoder())
            XCTFail("expected writeToURL error")
        } catch {
            // expected
        }
        XCTAssertEqual([], try directory.entryNames(), "a write that failed leaves nothing behind")
    }

    /// The same failure with no fault injected: the real file system refuses a write into a
    /// directory that does not exist, and `encode` reports it as the write error.
    func testEncodeThrowsWhenTheDirectoryDoesNotExist() throws {
        let directory = try TestRoot.makeTemporaryDirectory()
        defer { directory.remove() }
        do {
            try encode(Sample(name: "x", count: 1), toJSONAtPath: "/absent/out.json", fileSystem: .rooted(at: directory), jsonEncoder: JSONEncoder())
            XCTFail("expected writeToURL error")
        } catch ErrorType.writeToURL {
            // expected
        }
        XCTAssertEqual([], try directory.entryNames())
    }

    // MARK: - the rooted double is a real file system

    /// A write replaces the whole file, and what is read back is what was written last.
    func testRootedWriteReplacesTheFile() throws {
        let directory = try TestRoot.makeTemporaryDirectory()
        defer { directory.remove() }
        let fileSystem = FileSystem.rooted(at: directory)
        XCTAssertNil(fileSystem.contents("/config.json"))
        try fileSystem.write(Data("a longer first version".utf8), "/config.json")
        try fileSystem.write(Data("second".utf8), "/config.json")
        XCTAssertEqual(Data("second".utf8), fileSystem.contents("/config.json"))
        // A leading slash or none: the same file inside the directory.
        XCTAssertEqual(Data("second".utf8), fileSystem.contents("config.json"))
        XCTAssertEqual(["config.json"], try directory.entryNames())
    }

    /// A directory is not a file to read, and a file inside one is found by its path.
    func testRootedPathsReachIntoSubdirectories() throws {
        let directory = try TestRoot.makeTemporaryDirectory()
        defer { directory.remove() }
        let fileSystem = FileSystem.rooted(at: directory)
        try directory.makeDirectory(named: "configs")
        try fileSystem.write(Data("nested".utf8), "/configs/sync.json")
        XCTAssertEqual(Data("nested".utf8), fileSystem.contents("/configs/sync.json"))
        XCTAssertNil(fileSystem.contents("/configs"))
    }

    /// The executable probe reads the file's own permission bits.
    func testRootedExecutableProbe() throws {
        let directory = try TestRoot.makeTemporaryDirectory()
        defer { directory.remove() }
        let fileSystem = FileSystem.rooted(at: directory)
        XCTAssertFalse(fileSystem.isExecutableFile("/zfs"), "a missing file is not executable")
        try fileSystem.write(Data("#!/bin/sh\n".utf8), "/zfs")
        try directory.setExecutable(false, named: "zfs")
        XCTAssertFalse(fileSystem.isExecutableFile("/zfs"))
        try directory.setExecutable(true, named: "zfs")
        XCTAssertTrue(fileSystem.isExecutableFile("/zfs"))
    }
}
