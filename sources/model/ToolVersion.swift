// ToolVersion.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

/// The single source of truth for the version both `zfs-tools` (`Command.swift`) and `zfs-tools-build`
/// (`BuildCommand.swift`) report via `--version`. Before this existed, each `CommandConfiguration` carried
/// its own literal, bumped as two separate edits with nothing enforcing they moved together — that drift
/// is exactly how a 2.1.0 build once shipped self-reporting `2.0.3`, silently defeating
/// `install_zfs_tools.sh --expected-version`'s safety check. Bump this one constant when cutting a release;
/// both commands pick it up automatically.
public enum ToolVersion {
    public static let current = "2.1.0"
}
