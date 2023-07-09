import Foundation
import Shell

public typealias Model = Sendable & Codable
public typealias EquatableModel = Model & Equatable
public typealias HashableModel = Model & Hashable

extension Shell.Executor {
  public init(arguments: Arguments.Common) {
    self.init(
      shellPath: arguments.shellPath ?? Defaults.shellPath,
      printsOutput: arguments.shellPrintsStandardOutput ?? Defaults.shellPrintsStandardOutput,
      printsFailure: arguments.shellPrintsFailure ?? Defaults.shellPrintsFailure
    )
  }
}

extension ShellExecutor {
  @discardableResult
  func sudo(
    _ command: String,
    execute: Bool,
    file: String = #file,
    function: String = #function,
    line: Int = #line
  ) async throws -> String {
    let command = execute ? command : "echo \(command)"
    let result = await sudo(command)
    switch result {
    case .standardOutput(let output):
      return output
    case .standardError(let error):
      throw ErrorType.shellError(command: command, error: error, file: file, function: function, line: line)
    case .failure:
      throw ErrorType.shellFailure(command: command, file: file, function: function, line: line)
    }
  }

  func sudoLines(
    _ command: String,
    execute: Bool,
    file: String = #file,
    function: String = #function,
    line: Int = #line
  ) async throws -> [String] {
    (try await sudo(command, execute: execute, file: file, function: function, line: line)).lines
  }

  func zfsDestroy(subject: String, execute: Bool) async throws {
    try await sudo(
      ZFS.destroy(subject: subject).command,
      execute: execute
    )
  }

  func zfsDeleteSnapshots(_ snapshots: [String], execute: Bool) async throws {
    for snapshot in snapshots {
      try await zfsDestroy(
        subject: snapshot,
        execute: execute
      )
    }
  }

  func zfsListDatasets(matching: String?, execute: Bool) async throws -> [String] {
    try await sudoLines(
      ZFS.listDatasets(matching: matching).command,
      execute: execute
    )
  }

  func zfsListSnapshots(matching: String?, execute: Bool) async throws -> [String] {
    try await sudoLines(
      ZFS.listSnapshots(matching: matching).command,
      execute: execute
    )
  }

  func zfsListSnapshotsInDataset(dataset: String, dateSeparator: String, execute: Bool) async throws -> [String] {
    try await sudoLines(
      ZFS.listSnapshotsInDataset(dataset: dataset, dateSeparator: dateSeparator).command,
      execute: execute
    )
  }
}

enum ZFS {
  case destroy(subject: String)
  case listDatasets(matching: String?)
  case listSnapshots(matching: String?)
  case listSnapshotsInDataset(dataset: String, dateSeparator: String)

  var command: String {
    switch self {
    case .destroy(let subject):
      return "zfs destroy \(subject)"

    case .listDatasets(let matching):
      let list = Self.list()
      guard let matching else {
        return list
      }
      return list.matching(matching)

    case .listSnapshots(let matching):
      let list = "\(Self.list()) -t snapshot"
      guard let matching else {
        return list
      }
      return list.matching(matching)

    case .listSnapshotsInDataset(let dataset, let dateSeparator):
      return "\(Self.list()) -t snapshot".matching("\(dataset)\(dateSeparator)")

    }
  }

  private static func list() -> String {
    "zfs list -o name -H"
  }
}

fileprivate extension String {
  func matching(_ matching: String) -> String {
    guard !matching.isEmpty else {
      return self
    }
    return "\(self) | grep \(matching)"
  }
}

extension TimeInterval {
  public static let secondsPerDay = TimeInterval(24 * 60 * 60)
}
