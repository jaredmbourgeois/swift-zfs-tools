// TestRoot.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import ZFSToolsModel

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The test target's composition root: the only test code that names a live platform value, and
/// only for what the tests own — this package's own tree (the source-rules guard reads its Swift
/// files; the config and golden tests read `tests/resource/`) and temporary directories a test
/// creates and removes.
///
/// The source-rules guard honors a reach marker in this file and at the product's own reach sites
/// (`SourceRules.reachSites`) and refuses one anywhere else, so every other test file stays free of
/// the file system, the clock and the environment of whoever runs it.
enum TestRoot {
    /// The package root, found from this file's own location (`tests/TestRoot.swift`).
    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // tests
            .deletingLastPathComponent()  // the package root
    }

    /// Every `.swift` file under this package's `sources/` and `tests/`, each with its path relative
    /// to the package root.
    static func packageSwiftFiles() throws -> [SourceFile] {
        var files: [SourceFile] = []
        for directory in ["sources", "tests"] {
            let directoryURL = packageRoot.appendingPathComponent(directory)
            let subpaths = try FileManager.default.subpathsOfDirectory(atPath: directoryURL.path)  // reach-ok: the guard lists the package tree it belongs to
            for subpath in subpaths.sorted() where subpath.hasSuffix(".swift") {
                let text = try String(contentsOf: directoryURL.appendingPathComponent(subpath), encoding: .utf8)  // reach-ok: the guard reads the package tree it belongs to
                files.append(SourceFile(path: "\(directory)/\(subpath)", text: text))
            }
        }
        return files
    }

    /// The bytes of `tests/resource/<relativePath>`.
    static func resource(at relativePath: String) throws -> Data {
        let url = packageRoot.appendingPathComponent("tests/resource").appendingPathComponent(relativePath)
        return try Data(contentsOf: url)  // reach-ok: a test reads a resource of the package it belongs to
    }

    /// The names of the entries directly inside `tests/resource/<directory>`, sorted.
    static func resourceNames(inDirectory directory: String) throws -> [String] {
        let url = packageRoot.appendingPathComponent("tests/resource").appendingPathComponent(directory)
        return try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()  // reach-ok: a test lists the resources of the package it belongs to
    }

    /// A new, empty directory that the calling test owns and removes when it is done.
    static func makeTemporaryDirectory() throws -> TemporaryDirectory {
        let url = FileManager.default.temporaryDirectory  // reach-ok: where a test creates the directory it owns
            .appendingPathComponent("swift-zfs-tools-test-\(UUID().uuidString)")  // reach-ok: a directory name no other run uses
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)  // reach-ok: creating the directory the test owns
        return TemporaryDirectory(path: url.path)
    }

    /// The real file system inside `directory`: the three operations of the product's witness, with
    /// every path the product hands them read as a path inside the directory (`TemporaryDirectory.path(of:)`).
    /// `writeFault` is asked before each write; an error it returns is thrown and nothing is written.
    /// Tests reach this through `FileSystem.rooted(at:)` and its fault-injecting sibling.
    static func fileSystem(
        rootedAt directory: TemporaryDirectory,
        writeFault: @escaping @Sendable (_ path: String) -> (any Error)?
    ) -> FileSystem {
        FileSystem(
            contents: { path in
                FileManager.default.contents(atPath: directory.path(of: path))  // reach-ok: reading inside the directory the test owns
            },
            write: { data, path in
                if let fault = writeFault(path) {
                    throw fault
                }
                // `.atomic`, as the product's live write is: temp file, then rename into place.
                try data.write(to: URL(fileURLWithPath: directory.path(of: path)), options: .atomic)  // reach-ok: writing inside the directory the test owns
            },
            isExecutableFile: { path in
                FileManager.default.isExecutableFile(atPath: directory.path(of: path))  // reach-ok: probing inside the directory the test owns
            }
        )
    }
}

/// A directory a test created through `TestRoot.makeTemporaryDirectory()`.
struct TemporaryDirectory: Sendable {
    let path: String

    /// Where `path` lands inside the directory. A leading `/` is dropped, so the absolute path a
    /// test hands the product (`/config.json`) and the bare name (`config.json`) are the same file.
    func path(of path: String) -> String {
        "\(self.path)/\(path.drop(while: { $0 == "/" }))"
    }

    /// Creates the directory called `name` inside the directory.
    func makeDirectory(named name: String) throws {
        try FileManager.default.createDirectory(atPath: path(of: name), withIntermediateDirectories: false)  // reach-ok: creating inside the directory the test owns
    }

    /// Marks the file called `name` as executable, or not. `chmod` itself, rather than a
    /// file-attributes dictionary, so the mode is passed the same way on macOS and on Linux.
    func setExecutable(_ isExecutable: Bool, named name: String) throws {
        let path = path(of: name)
        guard chmod(path, isExecutable ? 0o755 : 0o644) == 0 else {
            throw PermissionChangeFailed(path: path, errorNumber: errno)
        }
    }

    struct PermissionChangeFailed: Error {
        let path: String
        let errorNumber: Int32
    }

    /// The names of the entries directly inside the directory, sorted.
    func entryNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path).sorted()  // reach-ok: listing the directory the test owns
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: path)  // reach-ok: removing the directory the test owns
    }
}
