// Defaults.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation

public enum Defaults {
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
    public static let recursive = false
    public static let shellPath = "/bin/bash"
    public static let shellPrintsStandardOutput = true
    public static let shellPrintsFailure = true
    public static let stringEncoding = String.Encoding.utf8
}
