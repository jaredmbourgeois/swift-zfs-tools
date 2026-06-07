// Arguments.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import ArgumentParser
import Foundation

/// Namespace for the CLI's parsed argument groups — one `ParsableArguments` struct per command.
/// Each `Config` type builds from the matching group here. Per-flag help lives in the `@Option`
/// definitions below.
public enum Arguments {
    case consolidate(Consolidate)
    case consolidateConfigure(ConsolidateConfigure)
    case snapshot(Snapshot)
    case snapshotConfigure(SnapshotConfigure)
    case sync(Sync)
    case syncConfigure(SyncConfigure)
}

extension Arguments {
    /// Options shared by every command: dry-run, date format/separator, shell, output encoding.
    public struct Common: ParsableArguments, Sendable {
        public static let optionGroupTitle = "Swift ZFS Tools Common Options"

        @Option(help: "\(Self.dateFormatHelp)")
        public var dateFormat: String?
        public static let dateFormatHelp = "The ZFS snapshot date format. Defaults to \(Defaults.dateFormat)"

        @Option(help: "\(Self.dateSeparatorHelp)")
        public var dateSeparator: String?
        public static let dateSeparatorHelp = "The ZFS snapshot date separator. Defaults to \(Defaults.dateSeparator)."

        @Option(help: "\(Self.executeHelp)")
        public var execute: Bool?
        public static let executeHelp = "Whether or not the commands will be executed. Commands will only be printed if not. Defaults to \(Defaults.execute)."

        @Option(help: "\(Self.lineSeparatorHelp)")
        public var lineSeparator: String?
        public static let lineSeparatorHelp = "Line separator. Defaults to '\(Defaults.lineSeparator)'."

        @Option(help: "\(Self.shellPathHelp)")
        public var shellPath: String?
        public static let shellPathHelp = "Path to the shell used for execution. Defaults to \(Defaults.shellPath)."

        @Option(help: "\(Self.stringEncodingRawValueHelp)")
        public var stringEncodingRawValue: String.Encoding.RawValue?
        public static let stringEncodingRawValueHelp = "String encoding rawValue. Defaults to \(Defaults.stringEncoding.rawValue) (\(Defaults.stringEncoding))."

        public init() {}
    }
}

extension Arguments {
    /// Arguments for `execute-actions`: run a chain of saved configs from one actions file.
    public struct ExecuteActions: ParsableArguments, Sendable {
        @OptionGroup(title: Common.optionGroupTitle)
        public var common: Common

        @Option(help: "\(Self.actionsPathHelp)")
        public var actionsPath: String
        public static let actionsPathHelp = "The path for a JSON array of Actions."

        public init() {}
    }

    /// Arguments for `execute-actions-configure`: write an example actions file.
    public struct ExecuteActionsConfigure: ParsableArguments, Sendable {
        @Option(help: "\(Self.outputPathHelp)")
        public var outputPath: String
        public static let outputPathHelp = "The path for a JSON array of Actions. Creates an example with each type of action."

        public init() {}
    }
}

extension Arguments {
    /// Arguments for `consolidate`: apply a retention schedule, optionally pool-guarded.
    public struct Consolidate: ParsableArguments, Sendable {
        @OptionGroup(title: Common.optionGroupTitle)
        public var common: Common

        @Option(help: "\(Self.consolidationPeriodPathHelp)")
        public var consolidationPeriodPath: String?
        public static let consolidationPeriodPathHelp = "The path for a ConsolidationPeriod JSON file. Consolidate will fail if file is not found. Defaults to a standard schedule when not provided."

        @Option(help: "\(Self.consolidationPeriodUpperBoundHelp)")
        public var consolidationPeriodUpperBound: String?
        public static let consolidationPeriodUpperBoundHelp = "The upperBound for the ConsolidationPeriod. Date will be parsed using the run's date format. Consolidate will fail if date cannot be parsed. Defaults to the run time."

        @Option(help: "\(Self.datasetGrepHelp)")
        public var datasetGrep: String?
        public static let datasetGrepHelp = "Consolidate snapshots for datasets containing this pattern. All datasets are synced if no pattern is provided."

        @Option(help: "\(Self.doNotDeleteSnapshotsPathHelp)")
        public var doNotDeleteSnapshotsPath: String?
        public static let doNotDeleteSnapshotsPathHelp = "The path for a JSON array of ZFS snapshot names that will not be deleted, even if they would've been on consolidation."

        @Option(help: "\(Self.maxPoolUtilizationHelp)")
        public var maxPoolUtilization: Float?
        public static let maxPoolUtilizationHelp = "Maximum pool utilization percentage (0-100). Triggers aggressive pruning after consolidation if exceeded."

        @Option(help: "\(Self.minFreeBytesHelp)")
        public var minFreeBytes: Int64?
        public static let minFreeBytesHelp = "Minimum free bytes on pool. Triggers aggressive pruning after consolidation if below threshold."

        public init() {}
    }

    /// Arguments for `consolidate-configure`: save a `Consolidator.Config` to JSON.
    public struct ConsolidateConfigure: ParsableArguments, Sendable {
        @OptionGroup(title: Common.optionGroupTitle)
        public var consolidate: Consolidate

        @Option(help: "\(Self.outputPathHelp)")
        public var outputPath: String
        public static let outputPathHelp = "The output path for the Consolidator.Config JSON file."

        public init() {}
    }

    /// Arguments for `consolidate-configured`: run consolidation from a saved config.
    public struct ConsolidateConfigured: ParsableArguments, Sendable {
        @OptionGroup(title: Common.optionGroupTitle)
        public var common: Common

        @Option(help: "\(Self.configPathHelp)")
        public var configPath: String
        public static let configPathHelp = "Full path, including name, of a Consolidator.Config JSON; .json will be appended if not provided. eg /path/to/snapshot-config/nas_consolidate"

        public init() {}
    }
}

extension Arguments {
    /// Arguments for `snapshot`: create timestamped snapshots, optionally pool-guarded.
    public struct Snapshot: ParsableArguments, Sendable {
        @OptionGroup(title: Common.optionGroupTitle)
        public var common: Common

        @Option(help: "\(Self.datasetGrepHelp)")
        public var datasetGrep: String?
        public static let datasetGrepHelp = "Takes snapshots for datasets containing this pattern or all datasets if no pattern is provided."

        @Option(help: "\(Self.maxPoolUtilizationHelp)")
        public var maxPoolUtilization: Float?
        public static let maxPoolUtilizationHelp = "Maximum pool utilization percentage (0-100). Snapshots are skipped if exceeded."

        @Option(help: "\(Self.minFreeBytesHelp)")
        public var minFreeBytes: Int64?
        public static let minFreeBytesHelp = "Minimum free bytes on pool. Snapshots are skipped if below threshold."

        @Option(help: "\(Self.recursiveHelp)")
        public var recursive: Bool?
        public static let recursiveHelp = "Recursively takes snapshots of all child datasets, eg zfs snapshot -r dataset. Defaults to \(Defaults.recursive)."

        public init() {}
    }

    /// Arguments for `snapshot-configure`: save a `Snapshotter.Config` to JSON.
    public struct SnapshotConfigure: ParsableArguments, Sendable {
        @OptionGroup(title: "Snapshot options")
        public var snapshot: Snapshot

        @Option(help: "\(Self.outputPathHelp)")
        public var outputPath: String
        public static let outputPathHelp = "The output path for the Snapshotter.Config JSON; please include full path, .json extension will be appended if needed."

        public init() {}
    }

    /// Arguments for `snapshot-configured`: run snapshotting from a saved config.
    public struct SnapshotConfigured: ParsableArguments, Sendable {
        @OptionGroup(title: Common.optionGroupTitle)
        public var common: Common

        @Option(help: "\(Self.configPathHelp)")
        public var configPath: String
        public static let configPathHelp = "Full path, including name, of a Snapshotter.Config JSON; .json will be appended if not provided. eg /path/to/snapshot-config/nas_snapshot"

        public init() {}
    }
}

extension Arguments {
    /// Arguments for `sync`: replicate snapshots to a remote host, with optional path remapping.
    public struct Sync: ParsableArguments, Sendable {
        @OptionGroup(title: Common.optionGroupTitle)
        public var common: Common

        @Option(help: "\(Self.datasetGrepHelp)")
        public var datasetGrep: String?
        public static let datasetGrepHelp = "Sync snapshots for datasets containing this pattern. All datasets are synced if no pattern is provided."

        @Option(help: "\(Self.sshPortHelp)")
        public var sshPort: String
        public static let sshPortHelp = "SSH port for remote."

        @Option(help: "\(Self.sshKeyPathHelp)")
        public var sshKeyPath: String
        public static let sshKeyPathHelp = "SSH key path for remote."

        @Option(help: "\(Self.sshUserHelp)")
        public var sshUser: String
        public static let sshUserHelp = "SSH user for remote."

        @Option(help: "\(Self.sshIPHelp)")
        public var sshIP: String
        public static let sshIPHelp = "SSH IP for remote."

        @Option(help: "\(Self.remotePathStripHelp)")
        public var remotePathStrip: String?
        public static let remotePathStripHelp = "Strip this prefix from the local dataset path before computing the remote path. Use with --remote-path-root to redirect snapshots to a different location on the destination. Defaults to no strip."

        @Option(help: "\(Self.remotePathRootHelp)")
        public var remotePathRoot: String?
        public static let remotePathRootHelp = "Prepend this root to the (possibly stripped) dataset path on the destination. E.g. --remote-path-root pool_b/backups makes 'pool_a/data' arrive as 'pool_b/backups/pool_a/data' on the remote. Defaults to no prepend (recv path matches send path)."

        public init() {}
    }

    /// Arguments for `sync-configure`: save a `Syncer.Config` to JSON.
    public struct SyncConfigure: ParsableArguments, Sendable {
        @OptionGroup(title: "Sync options")
        public var sync: Sync

        @Option(help: "\(Self.outputPathHelp)")
        public var outputPath: String
        public static let outputPathHelp = "The output path for the Syncer.Config JSON file; please include full path, .json extension will be appended if needed."

        public init() {}
    }

    /// Arguments for `sync-configured`: run a sync from a saved config.
    public struct SyncConfigured: ParsableArguments, Sendable {
        @OptionGroup(title: Common.optionGroupTitle)
        public var common: Common

        @Option(help: "\(Self.configPathHelp)")
        public var configPath: String
        public static let configPathHelp = "Full path, including name, of a Syncer.Config JSON; .json will be appended if not provided. eg /path/to/snapshot-config/nas_sync"

        public init() {}
    }
}
