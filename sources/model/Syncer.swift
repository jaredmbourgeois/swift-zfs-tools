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
        self.shell = shell
        sshLogin =
            "ssh -p \(config.sshPort.shellQuoted) -i \(config.sshKeyPath.shellQuoted) \(config.sshUser.shellQuoted)@\(config.sshIP.shellQuoted)"
    }

    /// Replicate every matching dataset: destroy remote-only snapshots, then send each new local
    /// snapshot (incremental where possible). Sends run sequentially — ZFS receive locks the dataset.
    public func sync() async throws {
        let sendRateLimitPipe = try Self.sendRateLimitPipe(for: config.sendRateLimit)
        try Self.validateSentBookmarkName(config.sentBookmarkName)
        let datasets = try await datasets()
        // send and receive sequentially since ZFS receive locks dataset and its descendents
        // https://docs.oracle.com/cd/E18752_01/html/819-5461/gbchx.html
        for dataset in datasets {
            if config.pruneRemoteSnapshots {
                for snapshotToDelete in dataset.snapshotsRemoteToDelete {
                    _ = try await shell.execute(
                        remote(ZFS.destroy(subject: snapshotToDelete.name)),
                        dryRun: !config.execute
                    ).get()
                }
            }
            for snapshotToSend in dataset.snapshotsLocalToSend {
                _ = try await shell.execute(
                    sendCommand(for: snapshotToSend, sendRateLimitPipe: sendRateLimitPipe),
                    dryRun: !config.execute
                ).get()
                try await advanceBookmark(to: snapshotToSend.this)
            }
        }
    }

    private func advanceBookmark(to snapshot: SnapshotRecord) async throws {
        guard let sentBookmarkName = config.sentBookmarkName else { return }
        let bookmark = "\(snapshot.dataset)#\(sentBookmarkName)"
        let temporaryBookmark = "\(bookmark).tmp"
        _ = try await shell.execute(
            "\(ZFS.destroy(subject: temporaryBookmark)) || true",
            dryRun: !config.execute
        ).get()
        _ = try await shell.execute(
            ZFS.bookmark(snapshot: snapshot.name, bookmark: temporaryBookmark),
            dryRun: !config.execute
        ).get()
        _ = try await shell.execute(
            "\(ZFS.destroy(subject: bookmark)) || true",
            dryRun: !config.execute
        ).get()
        _ = try await shell.execute(
            ZFS.bookmark(snapshot: snapshot.name, bookmark: bookmark),
            dryRun: !config.execute
        ).get()
        _ = try await shell.execute(
            "\(ZFS.destroy(subject: temporaryBookmark)) || true",
            dryRun: !config.execute
        ).get()
    }

    private func sendCommand(for snapshotToSend: SendSnapshot, sendRateLimitPipe: String?) -> String
    {
        var zfsSend = "zfs send -v"
        if let previousSnapshot = snapshotToSend.previous {
            zfsSend += " -i \(previousSnapshot.name.shellQuoted)"
        }
        zfsSend += " \(snapshotToSend.this.name.shellQuoted)"

        var command = "set -o pipefail; \(zfsSend)"
        if let sendRateLimitPipe {
            command += " | \(sendRateLimitPipe)"
        }
        command +=
            " | \(sshLogin) zfs recv -F \(forwardPath(snapshotToSend.this.name).shellQuoted)"
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
            ZFS.listSnapshotRecords(grepping: config.datasetGrep),
            dryRun: !config.execute,
            encoding: config.stringEncoding,
            lineSeparator: config.lineSeparator
        )
        // Remote datasets carry the path transform; grep with the transformed pattern so the
        // remote-side `zfs list ... | grep` actually matches.
        async let snapshotsRemoteRawBinding: [String] = try await shell.lines(
            remote(ZFS.listSnapshotRecords(grepping: remoteDatasetGrep)),
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
        let listLocalCommand = ZFS.listSnapshotRecords(grepping: config.datasetGrep)
        let listRemoteCommand = remote(ZFS.listSnapshotRecords(grepping: remoteDatasetGrep))
        let snapshotsLocalRecords = try snapshotsLocal.map {
            try SnapshotRecord.parse($0, command: listLocalCommand)
        }
        // Reverse-transform remote snapshot names into local form so all internal comparisons
        // run in a single namespace. Forward-transform happens at the wire boundary in sync().
        let snapshotsRemoteRecords = try snapshotsRemoteRaw.map { line in
            let record = try SnapshotRecord.parse(line, command: listRemoteCommand)
            return RemoteSnapshotRecord(local: record.withName(reversePath(record.name)), remote: record)
        }
        let bookmarksLocalRecords = try await listBookmarkRecords()
        return try await withThrowingTaskGroup(of: DatasetSnapshotOperation.self) {
            taskGroup in
            for dataset in datasetsLocal {
                taskGroup.addTask {
                    let snapshotsLocalForDataset = snapshotsLocalRecords
                        .filter { $0.dataset == dataset }
                        .sorted { $0.createtxg < $1.createtxg }
                    let snapshotsRemoteForDataset = snapshotsRemoteRecords
                        .filter { $0.local.dataset == dataset }
                        .sorted { $0.local.createtxg < $1.local.createtxg }
                    let snapshotsRemoteForDatasetByGuid = snapshotsRemoteForDataset.reduce(
                        into: [String: RemoteSnapshotRecord]()
                    ) { $0[$1.local.guid] = $1 }

                    let snapshotsLocalForDatasetGuids = Set(snapshotsLocalForDataset.map(\.guid))
                    let snapshotsCommon = snapshotsLocalForDataset.filter {
                        snapshotsRemoteForDatasetByGuid[$0.guid] != nil
                    }
                    let mostRecentCommonSnapshot = snapshotsCommon.last.map(SnapshotBase.init(record:))
                    let bookmarkBase = bookmarksLocalRecords
                        .filter { $0.bookmarkDataset == dataset && snapshotsRemoteForDatasetByGuid[$0.guid] != nil }
                        .max { $0.createtxg < $1.createtxg }
                        .map(SnapshotBase.init(record:))
                    let base = [mostRecentCommonSnapshot, bookmarkBase]
                        .compactMap { $0 }
                        .max { $0.createtxg < $1.createtxg }
                    let snapshotsLocalAfterLastCommonRemote = snapshotsLocalForDataset.filter {
                        guard let base else { return true }
                        return $0.createtxg > base.createtxg
                    }
                    let snapshotsRemoteDeletedFromLocal: [SnapshotRecord] = snapshotsRemoteForDataset.compactMap {
                        guard !snapshotsLocalForDatasetGuids.contains($0.local.guid), $0.local.guid != base?.guid else {
                            return nil
                        }
                        return $0.remote
                    }
                    var snapshotsLocalAfterLastCommonRemoteIndex = 0
                    return DatasetSnapshotOperation(
                        snapshotsLocalToSend: snapshotsLocalAfterLastCommonRemote.map {
                            thisSnapshot in
                            let send = SendSnapshot(
                                this: thisSnapshot,
                                previous: snapshotsLocalAfterLastCommonRemoteIndex == .zero
                                    ? base
                                    : // snapshotsLocalAfterLastCommonRemote sorted ascending createtxg
                                    SnapshotBase(
                                        record: snapshotsLocalAfterLastCommonRemote[
                                            snapshotsLocalAfterLastCommonRemoteIndex - 1])
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
    ///   `ReceiveGuardPolicy` depends on this: it exact-matches the bare `zfs list -t snapshot ...`
    ///   a receiver sees. Pushing the grep remote-side would make SSH_ORIGINAL_COMMAND
    ///   `zfs list … | grep …`, which the guard rejects — silently breaking every guarded sync.
    private func remote(_ command: String) -> String {
        "\(sshLogin) \(command)"
    }

    /// Forward-transform a local-form path/snapshot to its remote-form equivalent.
    ///
    /// Order of operations: strip `remotePathStrip` from the front (if present), then prepend
    /// `remotePathRoot` (if set). When both are nil the input is returned unchanged, preserving
    /// 1.2.0 behavior.
    private func forwardPath(_ localPath: String) -> String {
        Self.applyPathTransform(
            localPath, strip: config.remotePathStrip, add: config.remotePathRoot)
    }

    /// Reverse-transform a remote-form path/snapshot back to its local-form equivalent.
    ///
    /// The inverse of `forwardPath`: strip `remotePathRoot` then prepend `remotePathStrip`.
    private func reversePath(_ remotePath: String) -> String {
        Self.applyPathTransform(
            remotePath, strip: config.remotePathRoot, add: config.remotePathStrip)
    }

    /// Remote-side grep pattern for `zfs list`, derived from `datasetGrep` via `forwardPath`.
    /// Returns `nil` when no grep is configured.
    private var remoteDatasetGrep: String? {
        guard let grep = config.datasetGrep else { return nil }
        return forwardPath(grep)
    }

    private func listBookmarkRecords() async throws -> [SnapshotRecord] {
        guard let sentBookmarkName = config.sentBookmarkName else { return [] }
        let command = ZFS.listBookmarkRecords(grepping: "#\(sentBookmarkName)")
        return try await shell.lines(
            command,
            dryRun: !config.execute,
            encoding: config.stringEncoding,
            lineSeparator: config.lineSeparator
        )
        .map { try SnapshotRecord.parse($0, command: command) }
    }

    private static func applyPathTransform(_ input: String, strip: String?, add: String?) -> String
    {
        var path = input
        if let strip = normalizedPathComponent(strip), path == strip || path.hasPrefix(strip + "/") {
            path = String(path.dropFirst(strip.count))
            if path.hasPrefix("/") { path = String(path.dropFirst()) }
        }
        if let add = normalizedPathComponent(add) {
            path = path.isEmpty ? add : "\(add)/\(path)"
        }
        return path
    }

    private static func normalizedPathComponent(_ component: String?) -> String? {
        guard var component, !component.isEmpty else { return nil }
        while component.hasSuffix("/") { component.removeLast() }
        return component.isEmpty ? nil : component
    }

    private static func sendRateLimitPipe(for sendRateLimit: String?) throws -> String? {
        guard let sendRateLimit, !sendRateLimit.isEmpty else { return nil }
        guard isValidSendRateLimit(sendRateLimit) else {
            throw ErrorType.invalidArgument(
                name: "sendRateLimit",
                value: sendRateLimit,
                reason:
                    "expected a positive byte count with an optional K/M/G/T/P/E/Z/Y suffix, e.g. 20M"
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

    private static func validateSentBookmarkName(_ sentBookmarkName: String?) throws {
        guard let sentBookmarkName else { return }
        guard isValidBookmarkComponent(sentBookmarkName) else {
            throw ErrorType.invalidArgument(
                name: "sentBookmarkName",
                value: sentBookmarkName,
                reason: "expected a non-empty ZFS bookmark component using only letters, digits, '.', '_', '-', or ':'"
            )
        }
    }

    private static func isValidBookmarkComponent(_ component: String) -> Bool {
        guard !component.isEmpty else { return false }
        return component.utf8.allSatisfy { scalar in
            (scalar >= 48 && scalar <= 57)
                || (scalar >= 65 && scalar <= 90)
                || (scalar >= 97 && scalar <= 122)
                || scalar == 45
                || scalar == 46
                || scalar == 58
                || scalar == 95
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
        /// Preserve existing behavior by default: prune remote snapshots absent from local.
        let pruneRemoteSnapshots: Bool
        /// Optional local bookmark component (`dataset#name`) advanced after each successful send.
        let sentBookmarkName: String?
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
            pruneRemoteSnapshots: Bool = true,
            sentBookmarkName: String? = nil,
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
            self.pruneRemoteSnapshots = pruneRemoteSnapshots
            self.sentBookmarkName = sentBookmarkName
            self.remotePathStrip = remotePathStrip
            self.remotePathRoot = remotePathRoot
        }

        enum CodingKeys: String, CodingKey {
            case datasetGrep, dateSeparator, execute, lineSeparator
            case pruneRemoteSnapshots, remotePathRoot, remotePathStrip, sendRateLimit, sentBookmarkName
            case sshIP, sshKeyPath, sshPort, sshUser, stringEncodingRawValue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            datasetGrep = try container.decodeIfPresent(String.self, forKey: .datasetGrep)
            dateSeparator = try container.decode(String.self, forKey: .dateSeparator)
            execute = try container.decode(Bool.self, forKey: .execute)
            lineSeparator = try container.decode(String.self, forKey: .lineSeparator)
            sshPort = try container.decode(String.self, forKey: .sshPort)
            sshKeyPath = try container.decode(String.self, forKey: .sshKeyPath)
            sshUser = try container.decode(String.self, forKey: .sshUser)
            sshIP = try container.decode(String.self, forKey: .sshIP)
            stringEncodingRawValue = try container.decode(UInt.self, forKey: .stringEncodingRawValue)
            sendRateLimit = try container.decodeIfPresent(String.self, forKey: .sendRateLimit)
            pruneRemoteSnapshots = try container.decodeIfPresent(Bool.self, forKey: .pruneRemoteSnapshots) ?? true
            sentBookmarkName = try container.decodeIfPresent(String.self, forKey: .sentBookmarkName)
            remotePathStrip = try container.decodeIfPresent(String.self, forKey: .remotePathStrip)
            remotePathRoot = try container.decodeIfPresent(String.self, forKey: .remotePathRoot)
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
            stringEncodingRawValue =
                arguments.common.stringEncodingRawValue ?? Defaults.stringEncoding.rawValue
            sendRateLimit = arguments.sendRateLimit
            pruneRemoteSnapshots = arguments.pruneRemoteSnapshots ?? true
            sentBookmarkName = arguments.sentBookmarkName
            remotePathStrip = arguments.remotePathStrip
            remotePathRoot = arguments.remotePathRoot
        }
    }

    private struct DatasetSnapshotOperation {
        let snapshotsLocalToSend: [SendSnapshot]
        let snapshotsRemoteToDelete: [SnapshotRecord]
    }

    private struct RemoteSnapshotRecord {
        let local: SnapshotRecord
        let remote: SnapshotRecord
    }

    private struct SendSnapshot {
        let this: SnapshotRecord
        let previous: SnapshotBase?
    }

    private struct SnapshotBase {
        let guid: String
        let createtxg: UInt64
        let name: String

        init(record: SnapshotRecord) {
            guid = record.guid
            createtxg = record.createtxg
            name = record.name
        }
    }
}
