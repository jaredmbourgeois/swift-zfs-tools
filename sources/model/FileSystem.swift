// FileSystem.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation

/// A `Sendable` witness over the file operations this tool needs, expressed as `@Sendable`
/// closures — the same dependency-injection idiom as `Shell`/`ShellExecute`. Production code
/// uses `.live` (backed by `FileManager` / `Data`); tests inject an in-memory implementation
/// so config read/write paths are unit-testable without touching the disk.
public struct FileSystem: Sendable {
    public var contents: @Sendable (_ path: String) -> Data?
    public var write: @Sendable (_ data: Data, _ path: String) throws -> Void

    public init(
        contents: @escaping @Sendable (_ path: String) -> Data?,
        write: @escaping @Sendable (_ data: Data, _ path: String) throws -> Void
    ) {
        self.contents = contents
        self.write = write
    }

    public static let live = FileSystem(
        contents: { FileManager.default.contents(atPath: $0) },
        // `.atomic` writes to a temp file and renames into place, so an interrupted write can't
        // leave a truncated / corrupt config behind.
        write: { data, path in try data.write(to: URL(fileURLWithPath: path), options: .atomic) }
    )
}
