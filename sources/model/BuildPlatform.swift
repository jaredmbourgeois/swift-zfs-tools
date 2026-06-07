// BuildPlatform.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation

/// Maps a build host's `uname` output to the `bin/<platform>/` directory name used for prebuilt
/// binaries. Pure and deterministic, so the builder can derive the target architecture at the build
/// site — local or over SSH — instead of requiring it as a flag. Returns `nil` for an unrecognized
/// OS/arch, in which case the caller falls back to an explicit `--platform` override. (Windows has no
/// `uname`; supporting it later means extending this mapping.)
public enum BuildPlatform {
    /// `("Darwin", "arm64") → "macos-arm64"`, `("Linux", "x86_64") → "linux-x86_64"`,
    /// `("Linux", "aarch64") → "linux-aarch64"`. `nil` if either component is unrecognized.
    public static func directoryName(unameS: String, unameM: String) -> String? {
        let os: String
        switch unameS.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Darwin": os = "macos"
        case "Linux": os = "linux"
        default: return nil
        }
        let arch: String
        switch unameM.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "x86_64", "amd64": arch = "x86_64"
        // macOS reports Apple Silicon as `arm64`; Linux reports it as `aarch64`. Normalize each to
        // the name that platform's toolchain and our bin/ layout use.
        case "arm64", "aarch64": arch = (os == "macos") ? "arm64" : "aarch64"
        default: return nil
        }
        return "\(os)-\(arch)"
    }
}
