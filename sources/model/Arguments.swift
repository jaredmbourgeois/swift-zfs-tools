import ArgumentParser
import Foundation

public enum Arguments {
  case consolidate(Consolidate)
  case consolidateConfigure(ConsolidateConfigure)
  case snapshot(Snapshot)
  case snapshotConfigure(SnapshotConfigure)
  case sync(Sync)
  case syncConfigure(SyncConfigure)
}

extension Arguments {
  public struct Common: ParsableArguments {
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

    @Option(help: "\(Self.shellPathHelp)")
    public var shellPath: String?
    public static let shellPathHelp = "Path to the shell used for execution. Defaults to \(Defaults.shellPath)."

    @Option(help: "\(Self.shellPrintsFailureHelp)")
    public var shellPrintsFailure: Bool?
    public static let shellPrintsFailureHelp = "Shell prints process failure results. Defaults to \(Defaults.shellPath)."

    @Option(help: "\(Self.shellPrintsStandardOutputHelp)")
    public var shellPrintsStandardOutput: Bool?
    public static let shellPrintsStandardOutputHelp = "Shell prints standard output and error results. Defaults to \(Defaults.shellPath)."

    public init() {}
  }
}

extension Arguments {
  public struct ExecuteActions: ParsableArguments {
    @OptionGroup(title: Common.optionGroupTitle)
    public var common: Common

    @Option(help: "The path for a JSON array of Actions.")
    public var actionsPath: String

    public init() {}
  }

  public struct ExecuteActionsConfigure: ParsableArguments {
    @Option(help: "The path for a JSON array of Actions. Creates an example with each type of action.")
    public var outputPath: String

    public init() {}
  }
}

extension Arguments {
  public struct Consolidate: ParsableArguments {
    @OptionGroup(title: Common.optionGroupTitle)
    public var common: Common

    @Option(help: "The path for a Consolidator.Config JSON file. Overrides all other options. Consolidate will fail if file is not found.")
    public var configPath: String?

    @Option(help: "The path for a ConsolidationPeriod JSON file. Consolidate will fail if file is not found.")
    public var consolidationPeriodPath: String?

    @Option(help: "The upperBound for the ConsolidationPeriod. Date will be parsed using the run's date format. Consolidate will fail if date cannot be parsed. Defaults to the run time.")
    public var consolidationPeriodUpperBound: String?

    @Option(help: "ZFS snapshot dataset root to consolidate, eg nas/documents")
    public var datasetGrep: String

    @Option(help: "The path for a JSON array of ZFS snapshot names that will not be deleted, even if they would've been on consolidation.")
    public var doNotDeleteSnapshotsPath: String?

    public init() {}
  }

  public struct ConsolidateConfigure: ParsableArguments {
    @OptionGroup(title: Common.optionGroupTitle)
    public var consolidate: Consolidate

    @Option(help: "The output path for the Consolidator.Config JSON file.")
    public var outputPath: String

    public init() {}
  }
}

extension Arguments {
  public struct Snapshot: ParsableArguments {
    @OptionGroup(title: Common.optionGroupTitle)
    public var common: Common

    @Option(help: "The dataset to snapshot, eg zfs snapshot dataset.")
    public var dataset: String

    @Option(help: "Recursively takes snapshots of all child datasets, eg zfs snapshot -r dataset.")
    public var recursive: Bool?

    public init() {}
  }

  public struct SnapshotConfigure: ParsableArguments {
    @OptionGroup(title: "Snapshot options")
    public var snapshot: Snapshot

    @Option(help: "The output path for the Snapshotter.Config JSON; please include full path, .json extension will be appeneded if needed.")
    public var outputPath: String

    public init() {}
  }
}

extension Arguments {
  public struct Sync: ParsableArguments {
    @OptionGroup(title: Common.optionGroupTitle)
    public var common: Common

    @Option(help: "Datasets to sync containing this pattern. All datasets are synced if no pattern is provided.")
    public var datasetGrep: String?

    @Option(help: "SSH port for remote.")
    public var sshPort: String

    @Option(help: "SSH key path for remote.")
    public var sshKeyPath: String

    @Option(help: "SSH user for remote.")
    public var sshUser: String

    @Option(help: "SSH IP for remote.")
    public var sshIP: String

    public init() {}
  }

  public struct SyncConfigure: ParsableArguments {
    @OptionGroup(title: "Sync options")
    public var sync: Sync

    @Option(help: "The output path for the Syncer.Config JSON file; please include full path, .json extension will be appeneded if needed.")
    public var outputPath: String

    public init() {}
  }
}
