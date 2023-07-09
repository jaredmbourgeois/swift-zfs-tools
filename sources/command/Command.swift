import ArgumentParser
import Foundation
import Shell
import ZFSToolsModel

@main
struct Command: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "swift-zfs-tools",
    abstract: """

    Tools to take, consolidate, and sync ZFS snapshots.
    The core subcommands are snapshot, consolidate, and sync; the execute-actions subcommand runs a list of these core subcommands.
    Each subcommand has an associated X-configure subcommand that takes parameters and writes the associated config.json to the output-path.

    Written in Swift with credit to swift-argument-parser for the CLI!

    """,
    usage: "./ZFSTools conslidate-configure --dataset-root nas/documents --output-path ~/Desktop/nas_documents_consolidate.json",
    discussion: """
    \(Arguments.Common.optionGroupTitle) (configure commands do not depend on a shell)
      --date-format > \(Arguments.Common.dateFormatHelp)
      --date-separator > \(Arguments.Common.dateSeparatorHelp)
      --execute true > \(Arguments.Common.executeHelp)
      --shell-path > \(Arguments.Common.shellPathHelp)
      --shell-prints-failure true > \(Arguments.Common.shellPrintsFailureHelp)
      --shell-prints-standard-output true > \(Arguments.Common.shellPrintsStandardOutputHelp)
    """,
    version: "1.0.0",
    shouldDisplay: true,
    subcommands: [
      ExecuteActions.self,
      ExecuteActionsConfigure.self,
      Snapshot.self,
      SnapshotConfigure.self,
      Consolidate.self,
      ConsolidateConfigure.self,
      Sync.self,
      SyncConfigure.self
    ],
    defaultSubcommand: ExecuteActionsConfigure.self,
    helpNames: nil
  )
}
