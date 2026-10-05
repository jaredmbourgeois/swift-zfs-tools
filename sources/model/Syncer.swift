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
    private let runner: ZFSRunner
    /// `-p <port> -i <key> <user>@<host>` — ssh's arguments; `remote(_:)` appends the remote command
    /// line as one more argument.
    private let sshLogin: [String]

    /// Builds the `ssh` login from `config`; `shell` runs the commands (inject a mock to test).
    public init(
        config: Syncer.Config,
        dateFormatter: DateFormatter,
        shell: ShellAtPath
    ) {
        self.config = config
        runner = ZFSRunner(
            shell: shell,
            execute: config.execute,
            stringEncoding: config.stringEncoding,
            lineSeparator: config.lineSeparator
        )
        sshLogin = ["-p", config.sshPort, "-i", config.sshKeyPath, "\(config.sshUser)@\(config.sshIP)"]
    }

    /// Replicate every matching dataset: destroy remote-only snapshots, then send the dataset's new
    /// local snapshots as at most two streams (`sendSteps`). Datasets go in name order, so a parent
    /// is always received before its children; sends run sequentially — ZFS receive locks the
    /// dataset and its descendants.
    public func sync() async throws {
        let sendRateLimitPipe = try Self.sendRateLimitPipe(for: config.sendRateLimit)
        try Self.validateSentBookmarkName(config.sentBookmarkName)
        // The task group below finishes datasets in whatever order they complete; sorting makes the
        // run order (and every log of it) the same each night, parents first.
        let datasets = try await datasets().sorted { $0.dataset < $1.dataset }
        // https://docs.oracle.com/cd/E18752_01/html/819-5461/gbchx.html
        for dataset in datasets {
            if config.pruneRemoteSnapshots {
                for snapshotToDelete in dataset.snapshotsRemoteToDelete {
                    _ = try await runner.run(remote(ZFS.destroy(subject: snapshotToDelete.name)))
                }
            }
            guard let newest = dataset.snapshotsToSend.last else { continue }
            for step in Self.sendSteps(base: dataset.base, owed: dataset.snapshotsToSend) {
                _ = try await runner.run(sendCommand(for: step, sendRateLimitPipe: sendRateLimitPipe))
            }
            // Once per dataset, after every step landed. A step that fails throws before this, so
            // the bookmark never claims a snapshot the destination does not hold; the next run then
            // starts from whatever the destination does hold (its newest common snapshot).
            try await advanceBookmark(to: newest, existingBookmarks: dataset.bookmarkNames)
        }
    }

    /// One `zfs send … | zfs recv -F …` pipeline of a dataset's sync.
    struct SendStep: Equatable {
        enum Kind: Equatable {
            /// `zfs send <to>` — the destination has nothing to build on.
            case full
            /// `zfs send -i <from> <to>` — one snapshot's delta; `from` may be a bookmark.
            case incremental
            /// `zfs send -I <from> <to>` — every snapshot between the two, as ONE stream.
            /// ZFS requires `from` to be a snapshot here, never a bookmark.
            case intermediary
        }
        let kind: Kind
        /// The snapshot or bookmark the stream builds on; nil for a full send.
        let from: String?
        let to: SnapshotRecord
    }

    /// The streams that carry `owed` (a dataset's local snapshots newer than `base`, ascending by
    /// createtxg) to the destination — at most two, however many snapshots are owed.
    ///
    /// Why at most two: each send is a round trip of fixed cost (an `ssh`, a `zfs recv`, a pipe
    /// setup), and the NAS→serverMTB leg's forwarded subtree owes ~96 hourly snapshots a day. One
    /// send per snapshot at ~33 s each filled the leg's one-hour budget from 2026-09-28 until
    /// 2026-10-04 (bourgeois_concern `nas-backup-mtb-leg-completes`).
    ///
    /// - a snapshot base: one `-i` for a single owed snapshot, else one `-I base newest`;
    /// - a bookmark base: `-i bookmark first`, then `-I first newest` (`-I` cannot start at a
    ///   bookmark);
    /// - no base: a full send of the first, then `-I first newest`.
    ///
    /// `-I` sends every snapshot the source holds between its two ends, which equals `owed` only
    /// when `owed` is that whole run — which is how `datasets()` builds it. That is asserted rather
    /// than assumed (`isContiguous`); an owed list that is not provably the run falls back to one
    /// `-i` per snapshot, the pre-2.2.0 behaviour, which is correct for any list.
    static func sendSteps(base: SnapshotBase?, owed: [SnapshotRecord]) -> [SendStep] {
        guard let first = owed.first, let newest = owed.last else { return [] }
        guard isContiguous(owed, after: base) else {
            return perSnapshotSteps(base: base, owed: owed)
        }
        if let base, !base.isBookmark {
            return [
                SendStep(kind: owed.count == 1 ? .incremental : .intermediary, from: base.name, to: newest)
            ]
        }
        let firstStep = SendStep(kind: base == nil ? .full : .incremental, from: base?.name, to: first)
        guard owed.count > 1 else { return [firstStep] }
        return [firstStep, SendStep(kind: .intermediary, from: first.name, to: newest)]
    }

    /// One send per owed snapshot, each from the one before it — what every sync did before 2.2.0.
    static func perSnapshotSteps(base: SnapshotBase?, owed: [SnapshotRecord]) -> [SendStep] {
        var previous = base?.name
        return owed.map { snapshot in
            defer { previous = snapshot.name }
            return SendStep(kind: previous == nil ? .full : .incremental, from: previous, to: snapshot)
        }
    }

    /// Whether `owed` is one dataset's snapshots in strictly increasing createtxg, all newer than
    /// `base` — the precondition for `-I` sending exactly `owed`.
    static func isContiguous(_ owed: [SnapshotRecord], after base: SnapshotBase?) -> Bool {
        guard let dataset = owed.first?.dataset else { return true }
        var previousCreatetxg = base?.createtxg
        for snapshot in owed {
            guard snapshot.dataset == dataset else { return false }
            if let previousCreatetxg, snapshot.createtxg <= previousCreatetxg { return false }
            previousCreatetxg = snapshot.createtxg
        }
        if let base, base.dataset != dataset { return false }
        return true
    }

    /// Move the dataset's sent-bookmark to `snapshot` through a `.tmp` bookmark, so a crash between
    /// the steps leaves either the old bookmark or the new one, never none. `existingBookmarks` (the
    /// run's own listing) says which of the two already exist, so a destroy is issued only for a
    /// bookmark that is there — no `|| true` to swallow a real failure.
    private func advanceBookmark(to snapshot: SnapshotRecord, existingBookmarks: [String]) async throws {
        guard let sentBookmarkName = config.sentBookmarkName else { return }
        let bookmark = "\(snapshot.dataset)#\(sentBookmarkName)"
        let temporaryBookmark = "\(bookmark).tmp"
        if existingBookmarks.contains(temporaryBookmark) {
            _ = try await runner.run(ZFS.destroy(subject: temporaryBookmark))
        }
        _ = try await runner.run(ZFS.bookmark(snapshot: snapshot.name, bookmark: temporaryBookmark))
        if existingBookmarks.contains(bookmark) {
            _ = try await runner.run(ZFS.destroy(subject: bookmark))
        }
        _ = try await runner.run(ZFS.bookmark(snapshot: snapshot.name, bookmark: bookmark))
        _ = try await runner.run(ZFS.destroy(subject: temporaryBookmark))
    }

    /// The one shell pipeline the tool runs: `zfs send … | [pv …] | ssh … 'zfs recv -F <target>'`.
    /// Each stage is rendered from argv, so a name is quoted only when it needs quoting.
    private func sendCommand(for step: SendStep, sendRateLimitPipe: String?) -> ZFSCommand {
        var zfsSend = ["zfs", "send", "-v"]
        if let from = step.from {
            zfsSend += [step.kind == .intermediary ? "-I" : "-i", from]
        }
        zfsSend.append(step.to.name)

        // A single-snapshot stream lands as the named snapshot. A multi-snapshot (`-I`) stream must
        // name the DATASET: ZFS refuses a snapshot name for it ("cannot specify snapshot name for
        // multi-snapshot stream"), and each snapshot in it arrives under its own name.
        let receiveTarget = step.kind == .intermediary ? step.to.dataset : step.to.name
        var stages = [zfsSend.shellCommandLine]
        if let sendRateLimitPipe {
            stages.append(sendRateLimitPipe)
        }
        stages.append(remote(ZFS.receive(target: forwardPath(receiveTarget))).commandLine)
        return ZFSCommand(form: .shell("set -o pipefail; " + stages.joined(separator: " | ")), effect: .mutating)
    }

    private func datasets() async throws -> [DatasetSnapshotOperation] {
        // Three parallel listings (2 local + 1 remote SSH), all read-only at the ZFS layer; the
        // parallelism matters when the remote SSH round trip is slow. Each listing is the bare
        // command — the remote one is exactly the shape `ReceiveGuardPolicy` whitelists — and the
        // dataset filter is applied here, on parsed names.
        let listLocalCommand = ZFS.listSnapshotRecords()
        let listRemoteCommand = remote(ZFS.listSnapshotRecords())
        async let datasetsLocalBinding: [String] = try await runner.lines(ZFS.listDatasets()).matching(config.datasetGrep)
        async let snapshotsLocalBinding: [String] = try await runner.lines(listLocalCommand)
        async let snapshotsRemoteRawBinding: [String] = try await runner.lines(listRemoteCommand)
        let (
            datasetsLocal,
            snapshotsLocal,
            snapshotsRemoteRaw
        ) = try await (
            datasetsLocalBinding,
            snapshotsLocalBinding,
            snapshotsRemoteRawBinding
        )
        let snapshotsLocalRecords = try snapshotsLocal
            .map { try SnapshotRecord.parse($0, command: listLocalCommand.commandLine) }
            .filter { Self.matches($0.name, config.datasetGrep) }
        // Remote names carry the path transform, so they are filtered with the transformed pattern,
        // then reverse-transformed into local form so every comparison runs in one namespace. The
        // forward transform happens at the wire boundary in sync().
        let snapshotsRemoteRecords = try snapshotsRemoteRaw
            .map { try SnapshotRecord.parse($0, command: listRemoteCommand.commandLine) }
            .filter { Self.matches($0.name, remoteDatasetGrep) }
            .map { record in
                RemoteSnapshotRecord(local: record.withName(reversePath(record.name)), remote: record)
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
                    // Ascending createtxg (the sort above), every snapshot newer than the base: the
                    // whole run `sendSteps` may hand to one `-I`.
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
                    return DatasetSnapshotOperation(
                        dataset: dataset,
                        base: base,
                        snapshotsToSend: snapshotsLocalAfterLastCommonRemote,
                        snapshotsRemoteToDelete: snapshotsRemoteDeletedFromLocal,
                        bookmarkNames: bookmarksLocalRecords.filter { $0.bookmarkDataset == dataset }.map(\.name)
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

    /// The same command run on the remote host: `ssh <login> '<command line>'`, the remote command
    /// line as ONE ssh argument. The remote shell then receives exactly that line — a dataset name
    /// with a space (legal in ZFS) reaches `zfs` intact — and it is exactly the `SSH_ORIGINAL_COMMAND`
    /// a receive-guard validates (`ReceiveGuardPolicy`); the effect is the inner command's.
    private func remote(_ command: ZFSCommand) -> ZFSCommand {
        ZFSCommand(form: .argv(executable: "ssh", arguments: sshLogin + [command.commandLine]), effect: command.effect)
    }

    /// Whether a snapshot or dataset `name` holds `pattern` as a fixed substring (`nil`/empty: all).
    private static func matches(_ name: String, _ pattern: String?) -> Bool {
        guard let pattern, !pattern.isEmpty else { return true }
        return name.contains(pattern)
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

    /// The sent-bookmarks (`dataset#<sentBookmarkName>`, and any `.tmp` a crashed run left), from one
    /// bookmark listing filtered here.
    private func listBookmarkRecords() async throws -> [SnapshotRecord] {
        guard let sentBookmarkName = config.sentBookmarkName else { return [] }
        let command = ZFS.listBookmarkRecords()
        return try await runner.lines(command)
            .map { try SnapshotRecord.parse($0, command: command.commandLine) }
            .filter { $0.name.contains("#\(sentBookmarkName)") }
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
        return ["pv", "-q", "-L", sendRateLimit].shellCommandLine
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
        let dataset: String
        /// The newest snapshot or bookmark the destination already holds, if any.
        let base: SnapshotBase?
        /// Local snapshots newer than `base`, ascending by createtxg.
        let snapshotsToSend: [SnapshotRecord]
        let snapshotsRemoteToDelete: [SnapshotRecord]
        /// The dataset's sent-bookmarks that exist now (`dataset#name`, maybe `dataset#name.tmp`).
        let bookmarkNames: [String]
    }

    private struct RemoteSnapshotRecord {
        let local: SnapshotRecord
        let remote: SnapshotRecord
    }

    struct SnapshotBase: Equatable {
        let guid: String
        let createtxg: UInt64
        let name: String

        init(record: SnapshotRecord) {
            guid = record.guid
            createtxg = record.createtxg
            name = record.name
        }

        /// A bookmark is named `dataset#name`, a snapshot `dataset@name`.
        var isBookmark: Bool { name.contains("#") }

        /// The dataset the base belongs to — its name up to the `#` or `@`.
        var dataset: String {
            String(name.prefix { $0 != "#" && $0 != "@" })
        }
    }
}
