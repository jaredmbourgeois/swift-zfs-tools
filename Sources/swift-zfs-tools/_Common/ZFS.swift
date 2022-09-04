import Foundation
import Shell

extension ShellExecutor {
  @discardableResult
  func sudoOutput(
    _ command: String,
    password: String,
    dryRun: Bool,
    function: StaticString = #function
  ) async -> String? {
    print("DEBUG: Consolidator.\(function) command: \(command)")
    let command = !dryRun ? command : "echo \(command)"
    let result = await sudo(command, password: password)
    switch result {
    case .output(let output):
      print("DEBUG: Consolidator.\(function) result: .output(\(output))")
      return output
    case .error(let error):
      print("DEBUG: Consolidator.\(function) result: .error(\(error))")
      return nil
    case .failure:
      print("DEBUG: Consolidator.\(function) result: .failure")
      return nil
    }
  }

  @discardableResult
  func sudoOutputLines(
    _ command: String,
    password: String,
    dryRun: Bool,
    function: StaticString = #function
  ) async -> [String] {
    (await sudoOutput(command, password: password, dryRun: dryRun, function: function))?.lines ?? []
  }
}

extension ShellExecutor {
  func zfsDatasets(
    matching: String? = nil,
    password: String,
    function: StaticString = #function
  ) async -> [String] {
    await sudoOutputLines(
      ZFSTools.ZFSCommand.list(matching: matching),
      password: password,
      dryRun: false,
      function: function
    )
  }

  func zfsDeleteSnapshots(
    _ snapshots: [String],
    password: String,
    dryRun: Bool,
    function: StaticString = #function
  ) async {
    for snapshot in snapshots {
      await zfsDestroy(snapshot, password: password, dryRun: dryRun, function: function)
    }
  }

  func zfsDestroy(
    _ subject: String,
    password: String,
    dryRun: Bool,
    function: StaticString = #function
  ) async {
    await sudoOutputLines(
      ZFSTools.ZFSCommand.destroy(subject),
      password: password,
      dryRun: dryRun,
      function: function
    )
  }

  func zfsSnapshots(
    matching: String? = nil,
    password: String,
    function: StaticString = #function
  ) async -> [String] {
    await sudoOutputLines(
      ZFSTools.ZFSCommand.listSnapshots(matching: matching),
      password: password,
      dryRun: false,
      function: function
    )
  }
}

extension ZFSTools {
  public enum ZFSCommand {
    public static func list(matching: String? = nil) -> String {
      var command = "zfs list -o name -H"
      if let matching = matching {
        command += " | grep \(matching)"
      }
      return command
    }

    public static func listSnapshots(matching: String? = nil) -> String {
      var command = "zfs list -t snapshot -o name -H"
      if let matching = matching {
        command += " | grep \(matching)"
      }
      return command
    }

    public static func destroy(_ subject: String) -> String {
      "zfs destroy \(subject)"
    }
  }
}
