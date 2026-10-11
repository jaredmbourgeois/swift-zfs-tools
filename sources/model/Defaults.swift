// Defaults.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation

/// Compile-time defaults used when a flag or config field is omitted. Edit here and rebuild to change
/// the tool's out-of-the-box behavior.
public enum Defaults {
    /// The default GFS schedule: 7 daily, 3 weekly, 11 monthly, then 1 yearly indefinitely.
    public static func consolidationSchedule(upperBound: String?) -> Consolidator.SnapshotConsolidationSchedule {
        .Builder(upperBound: upperBound)
            .keepingSnapshots(1, every: 1, .days, repeatedBy: 7)
            .keepingSnapshots(1, every: 1, .weeks, repeatedBy: 3)
            .keepingSnapshots(1, every: 1, .months, repeatedBy: 11)
            .buildIndefinitelyKeepingSnapshots(1, every: 1, .years)
    }
    public static let dateFormat = "yyyyMMdd-HHmmss"
    public static let dateSeparator = "@"
    public static let execute = false
    public static let lineSeparator = "\n"
    /// `sync` leaves the destination's snapshots alone unless it is told to prune them: destroying
    /// is the effect, so an omitted `--prune-remote-snapshots` / `pruneRemoteSnapshots` is the safe
    /// side. This is the one declaration; the option and the config decoder both read it.
    public static let pruneRemoteSnapshots = false
    public static let recursive = false
    public static let shellPath = "/bin/bash"
    /// Seconds between SIGTERM and SIGKILL when a cancelled run tears a child process down: long
    /// enough for `zfs` or `ssh` to exit on the first signal, short enough to bound one that will not.
    public static let shellTerminationGracePeriod = TimeInterval(2)
    public static let stringEncoding = String.Encoding.utf8
}
