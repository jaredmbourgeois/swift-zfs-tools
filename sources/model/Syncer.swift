// Syncer.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell

/// Replicates local snapshots to a remote host over SSH (`zfs send | ssh zfs recv`). Sends
/// incrementally from the most recent common snapshot when one exists, full otherwise; destroys
/// remote snapshots that no longer exist locally. Optional path remapping redirects where datasets
/// land on the destination.
public struct Syncer: Sendable {
    private let config: Syncer.Config
    private let dateFormatter: DateFormatter
    private let shell: ShellAtPath
    private let sshLogin: String

    /// Builds the `ssh` login from `config` (shell-quoted); `shell` runs the commands (inject a mock
    /// to test).
    public init(
        config: Syncer.Config,
        dateFormatter: DateFormatter,
        shell: ShellAtPath
    ) {
        self.config = config
        self.dateFormatter = dateFormatter
        self.shell = shell
        sshLogin = "ssh -p \(config.sshPort.shellQuoted) -i \(config.sshKeyPath.shellQuoted) \(config.sshUser.shellQuoted)@\(config.sshIP.shellQuoted)"
    }

    /// Replicate every matching dataset: destroy remote-only snapshots, then send each new local
    /// snapshot (incremental where possible). Sends run sequentially — ZFS receive locks the dataset.
    public func sync() async throws {
        let sendRateLimitPipe = try Self.sendRateLimitPipe(for: config.sendRateLimit)
        let datasets = try await datasets()
        // send and receive sequentially since ZFS receive locks dataset and its descendents
        // https://docs.oracle.com/cd/E18752_01/html/819-5461/gbchx.html
        for dataset in datasets {
            for snapshotToDelete in dataset.snapshotsRemoteToDelete {
                // snapshotToDelete.snapshot is stored in local form; transform to remote for destroy
                _ = try await shell.execute(
                    remote(ZFS.destroy(subject: forwardPath(snapshotToDelete.snapshot))),
                    dryRun: !config.execute
                ).get()
            }
            for snapshotToSend in dataset.snapshotsLocalToSend {
                _ = try await shell.execute(
                    sendCommand(for: snapshotToSend, sendRateLimitPipe: sendRateLimitPipe),
                    dryRun: !config.execute
                ).get()
            }
        }
    }

    private func sendCommand(for snapshotToSend: SendSnapshot, sendRateLimitPipe: String?) -> String {
        var zfsSend = "zfs send -v"
        if let previousSnapshot = snapshotToSend.previous {
            zfsSend += " -i \(previousSnapshot.snapshot.shellQuoted)"
        }
        zfsSend += " \(snapshotToSend.this.snapshot.shellQuoted)"

        var command = "set -o pipefail; \(zfsSend)"
        if let sendRateLimitPipe {
            command += " | \(sendRateLimitPipe)"
        }
        command += " | \(sshLogin) zfs recv -F \(forwardPath(snapshotToSend.this.snapshot).shellQuoted)"
        return command
    }

    private func datasets() async throws -> [DatasetSnapshotOperation] {
        // Three parallel listings (2 local + 1 remote SSH). All read-only at the
        // ZFS layer; the parallelism is meaningful when the remote SSH RTT is
        // high. Safe under swift-shell 2.0.0; 1.2.3 c21a673 serialized this as a
        // workaround for the pre-1.4.1 swift-shell pipe-drain race that lost
        // stdout under parallel use, fixed in swift-shell 1.4.1.
        async let datasetsLocalBinding: [String] = try await shell.lines(
            ZFS.listDatasets(grepping: config.datasetGrep),
            dryRun: !config.execute,
            encoding: config.stringEncoding,
            lineSeparator: config.lineSeparator
        )
        async let snapshotsLocalBinding: [String] = try await shell.lines(
            ZFS.listSnapshots(grepping: config.datasetGrep),
            dryRun: !config.execute,
            encoding: config.stringEncoding,
            lineSeparator: config.lineSeparator
        )
        // Remote datasets carry the path transform; grep with the transformed pattern so the
        // remote-side `zfs list ... | grep` actually matches.
        async let snapshotsRemoteRawBinding: [String] = try await shell.lines(
            remote(ZFS.listSnapshots(grepping: remoteDatasetGrep)),
            dryRun: !config.execute,
            encoding: config.stringEncoding,
            lineSeparator: config.lineSeparator
        )
        let (
            datasetsLocal,
            snapshotsLocal,
            snapshotsRemoteRaw
        ) = try await (
            datasetsLocalBinding,
            snapshotsLocalBinding,
            snapshotsRemoteRawBinding
        )
        // Reverse-transform remote snapshot names into local form so all internal comparisons
        // run in a single namespace. Forward-transform happens at the wire boundary in sync().
        let snapshotsRemote = snapshotsRemoteRaw.map { reversePath($0) }
        return try await withThrowingTaskGroup(of: DatasetSnapshotOperation.self) { [dateFormatter] taskGroup in
            for dataset in datasetsLocal {
                taskGroup.addTask {
                    let snapshotsLocalForDataset: [SnapshotAndDate] = try snapshotsLocal
                        .compactMap { snapshot in
                            guard snapshot.hasPrefix("\(dataset)\(config.dateSeparator)") else { return nil }
                            let date = try dateFormatter.dateForSnapshot(snapshot, dateSeparator: config.dateSeparator)
                            return SnapshotAndDate(snapshot: snapshot, date: date)
                        }
                        .sorted { $0.date > $1.date }
                    let snapshotsLocalForDatasetBySnapshot = snapshotsLocalForDataset.reduce(into: [String: SnapshotAndDate]()) { $0[$1.snapshot] = $1 }
                    let snapshotsRemoteForDataset: [SnapshotAndDate] = try snapshotsRemote
                        .compactMap { snapshot in
                            guard snapshot.hasPrefix("\(dataset)\(config.dateSeparator)") else { return nil }
                            let date = try dateFormatter.dateForSnapshot(snapshot, dateSeparator: config.dateSeparator)
                            return SnapshotAndDate(snapshot: snapshot, date: date)
                        }
                        .sorted { $0.date > $1.date }
                    let snapshotsRemoteForDatasetBySnapshot = snapshotsRemoteForDataset.reduce(into: [String: SnapshotAndDate]()) { $0[$1.snapshot] = $1 }

                    let snapshotsRemoteDeletedFromLocal: [SnapshotAndDate] = snapshotsRemoteForDataset.filter { snapshotsLocalForDatasetBySnapshot[$0.snapshot] == nil }
                    let snapshotsCommon = snapshotsLocalForDataset.filter { snapshotsRemoteForDatasetBySnapshot[$0.snapshot] != nil }
                    let snapshotsLocalAfterLastCommonRemote = snapshotsLocalForDataset.filter {
                        guard let mostRecentCommonSnapshot = snapshotsCommon.first else {
                            return true
                        }
                        return $0.date > mostRecentCommonSnapshot.date
                    }
                    .sorted { $0.date < $1.date }
                    var snapshotsLocalAfterLastCommonRemoteIndex = 0
                    return DatasetSnapshotOperation(
                        snapshotsLocalToSend: snapshotsLocalAfterLastCommonRemote.map { thisSnapshot in
                            let send = SendSnapshot(
                                this: thisSnapshot,
                                previous: snapshotsLocalAfterLastCommonRemoteIndex == .zero ?
                                    // snapshotsCommon sorted descending date
                                    snapshotsCommon.first :
                                    // snapshotsLocalAfterLastCommonRemote sorted ascending date
                                    snapshotsLocalAfterLastCommonRemote[snapshotsLocalAfterLastCommonRemoteIndex - 1]
                            )
                            snapshotsLocalAfterLastCommonRemoteIndex += 1
                            return send
                        },
                        snapshotsRemoteToDelete: snapshotsRemoteDeletedFromLocal
                    )
                }
            }
            var datasets = [DatasetSnapshotOperation]()
            datasets.reserveCapacity(datasetsLocal.count)
            for try await dataset in taskGroup {
                datasets.append(dataset)
            }
            return datasets
        }
    }

    /// Prefixes `command` with the ssh login so it runs on the remote host.
    ///
    /// Two deliberate properties:
    /// - **Quoting depth.** Interpolated values are single-quoted for the *local* shell. `ssh` then
    ///   re-parses the command on the *remote* shell, so a value containing spaces/metacharacters
    ///   would be re-split remotely (single-level quoting only). This is safe because ZFS
    ///   dataset/snapshot names can't contain such characters (OpenZFS naming rules); we don't
    ///   double-quote.
    /// - **Local pipe.** When `command` contains `… | grep … || true` (the list builders), the pipe
    ///   is interpreted by the *local* shell — the remote `zfs list` streams to a local `grep`. That
    ///   is intentional; wrapping the whole remote command in quotes would move the grep remote-side.
    private func remote(_ command: String) -> String {
        "\(sshLogin) \(command)"
    }

    /// Forward-transform a local-form path/snapshot to its remote-form equivalent.
    ///
    /// Order of operations: strip `remotePathStrip` from the front (if present), then prepend
    /// `remotePathRoot` (if set). When both are nil the input is returned unchanged, preserving
    /// 1.2.0 behavior.
    private func forwardPath(_ localPath: String) -> String {
        Self.applyPathTransform(localPath, strip: config.remotePathStrip, add: config.remotePathRoot)
    }

    /// Reverse-transform a remote-form path/snapshot back to its local-form equivalent.
    ///
    /// The inverse of `forwardPath`: strip `remotePathRoot` then prepend `remotePathStrip`.
    private func reversePath(_ remotePath: String) -> String {
        Self.applyPathTransform(remotePath, strip: config.remotePathRoot, add: config.remotePathStrip)
    }

    /// Remote-side grep pattern for `zfs list`, derived from `datasetGrep` via `forwardPath`.
    /// Returns `nil` when no grep is configured.
    private var remoteDatasetGrep: String? {
        guard let grep = config.datasetGrep else { return nil }
        return forwardPath(grep)
    }

    private static func applyPathTransform(_ input: String, strip: String?, add: String?) -> String {
        var path = input
        if let strip, !strip.isEmpty, path.hasPrefix(strip) {
            path = String(path.dropFirst(strip.count))
            if path.hasPrefix("/") { path = String(path.dropFirst()) }
        }
        if let add, !add.isEmpty {
            path = "\(add)/\(path)"
        }
        return path
    }

    private static func sendRateLimitPipe(for sendRateLimit: String?) throws -> String? {
        guard let sendRateLimit, !sendRateLimit.isEmpty else { return nil }
        guard isValidSendRateLimit(sendRateLimit) else {
            throw ErrorType.invalidArgument(
                name: "sendRateLimit",
                value: sendRateLimit,
                reason: "expected a positive byte count with an optional K/M/G/T/P/E/Z/Y suffix, e.g. 20M"
            )
        }
        return "pv -q -L \(sendRateLimit.shellQuoted)"
    }

    private static func isValidSendRateLimit(_ sendRateLimit: String) -> Bool {
        guard let firstCharacter = sendRateLimit.first, firstCharacter != "0" else { return false }
        let suffixes = Set("kKmMgGtTpPeEzZyY")
        let lastCharacter = sendRateLimit.last
        let digitString: Substring
        if let lastCharacter, suffixes.contains(lastCharacter) {
            digitString = sendRateLimit.dropLast()
        } else {
            digitString = sendRateLimit[...]
        }
        guard !digitString.isEmpty else { return false }
        return digitString.utf8.allSatisfy { scalar in
            scalar >= 48 && scalar <= 57
        }
    }
}

extension Syncer {
    /// A sync run as a `Codable` value — the `sync-configure` / `sync-configured` JSON schema. Build
    /// it from CLI `Arguments.Sync` or decode it from a saved config file. `remotePathStrip` /
    /// `remotePathRoot` are optional; with both unset the receive path matches the send path.
    public struct Config: Codable, Sendable, Equatable {
        let datasetGrep: String?
        let dateSeparator: String
        let execute: Bool
        let lineSeparator: String
        let sshPort: String
        let sshKeyPath: String
        let sshUser: String
        let sshIP: String
        let stringEncodingRawValue: UInt
        /// Optional `pv -q -L` rate passed into the local send pipeline, e.g. "20M".
        let sendRateLimit: String?
        /// Strip this prefix from local dataset paths before computing the remote path.
        /// Combine with `remotePathRoot` to redirect snapshots to a different location on the
        /// destination. Both nil = behavior identical to 1.2.0 (recv path matches send path).
        let remotePathStrip: String?
        /// Prepend this root to the (possibly stripped) dataset path on the destination.
        let remotePathRoot: String?
        var stringEncoding: String.Encoding { .init(rawValue: stringEncodingRawValue) }

        public init(
            datasetGrep: String?,
            dateSeparator: String,
            execute: Bool,
            lineSeparator: String,
            sshPort: String,
            sshKeyPath: String,
            sshUser: String,
            sshIP: String,
            stringEncoding: String.Encoding,
            sendRateLimit: String? = nil,
            remotePathStrip: String? = nil,
            remotePathRoot: String? = nil
        ) {
            self.datasetGrep = datasetGrep
            self.dateSeparator = dateSeparator
            self.execute = execute
            self.lineSeparator = lineSeparator
            self.sshPort = sshPort
            self.sshKeyPath = sshKeyPath
            self.sshUser = sshUser
            self.sshIP = sshIP
            self.stringEncodingRawValue = stringEncoding.rawValue
            self.sendRateLimit = sendRateLimit
            self.remotePathStrip = remotePathStrip
            self.remotePathRoot = remotePathRoot
        }

        public init(
            arguments: Arguments.Sync
        ) {
            datasetGrep = arguments.datasetGrep
            dateSeparator = arguments.common.dateSeparator ?? Defaults.dateSeparator
            execute = arguments.common.execute ?? Defaults.execute
            lineSeparator = arguments.common.lineSeparator ?? Defaults.lineSeparator
            sshPort = arguments.sshPort
            sshKeyPath = arguments.sshKeyPath
            sshUser = arguments.sshUser
            sshIP = arguments.sshIP
            stringEncodingRawValue = arguments.common.stringEncodingRawValue ?? Defaults.stringEncoding.rawValue
            sendRateLimit = arguments.sendRateLimit
            remotePathStrip = arguments.remotePathStrip
            remotePathRoot = arguments.remotePathRoot
        }
    }

    private struct DatasetSnapshotOperation {
        /// `snapshotsLocalToSend` sorted by descending `Date`
        let snapshotsLocalToSend: [SendSnapshot]
        /// `snapshotsRemoteToDelete` sorted by descending `Date`
        let snapshotsRemoteToDelete: [SnapshotAndDate]
    }

    private struct SendSnapshot {
        let this: SnapshotAndDate
        let previous: SnapshotAndDate?
    }
}
