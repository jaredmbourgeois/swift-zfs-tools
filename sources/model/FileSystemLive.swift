// FileSystemLive.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation

// This file is the model's one live implementation: the only file in `sources/model/` that names a
// platform accessor, each on a line that says why. The source-rules test (tests/SourceRulesTest.swift)
// holds that — a reach anywhere else in the model, or in a test, fails `swift test`.

extension FileSystem {
    /// The live file system. Name it only at a composition root (a command's `run()`); everything
    /// below the root takes the `FileSystem` it is handed.
    public static let live = FileSystem(
        contents: { path in
            FileManager.default.contents(atPath: path)  // reach-ok: the live file read
        },
        // `.atomic` writes to a temp file and renames into place, so an interrupted write can't
        // leave a truncated / corrupt config behind.
        write: { data, path in
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)  // reach-ok: the live file write
        },
        isExecutableFile: { path in
            FileManager.default.isExecutableFile(atPath: path)  // reach-ok: the live executable probe
        }
    )
}
