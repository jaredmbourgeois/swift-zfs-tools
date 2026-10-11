// FileSystem.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation

/// A `Sendable` witness over the file operations this tool needs, expressed as `@Sendable`
/// closures — the same dependency-injection idiom as `Shell`/`ShellExecute`. A composition root
/// hands down the live one (FileSystemLive.swift); a test hands down the same operations rooted in
/// a temporary directory it created, so the config read/write paths are tested against a real file
/// system without touching anything outside that directory.
public struct FileSystem: Sendable {
    /// The bytes of the file at `path`, or `nil` when no readable file is there.
    public let contents: @Sendable (_ path: String) -> Data?
    /// Replaces the file at `path` with `data`, or throws why it could not.
    public let write: @Sendable (_ data: Data, _ path: String) throws -> Void
    /// Whether `path` names a file this process may execute — how `receive-guard` finds `zfs`.
    public let isExecutableFile: @Sendable (_ path: String) -> Bool

    public init(
        contents: @escaping @Sendable (_ path: String) -> Data?,
        write: @escaping @Sendable (_ data: Data, _ path: String) throws -> Void,
        isExecutableFile: @escaping @Sendable (_ path: String) -> Bool
    ) {
        self.contents = contents
        self.write = write
        self.isExecutableFile = isExecutableFile
    }
}
