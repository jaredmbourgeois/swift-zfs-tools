// Syncer.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell

public struct Syncer: Sendable {
    private let config: Syncer.Config
    private let dateFormatter: DateFormatter
    private let shell: ShellAtPath
    private let sshLogin: String

    public init(
        config: Syncer.Config,
        dateFormatter: DateFormatter,
        shell: ShellAtPath
    ) {
        self.config = config
        self.dateFormatter = dateFormatter
        self.shell = shell
        sshLogin = "ssh -p \(config.sshPort) -i \(config.sshKeyPath) \(config.sshUser)@\(config.sshIP)"
    }

    public func sync() async throws {
        let datasets = try await datasets()
        // send and receive sequentially since ZFS receive locks dataset and its descendents
        // https://docs.oracle.com/cd/E18752_01/html/819-5461/gbchx.html
        var sendCommand: String
        for dataset in datasets {
            for snapshotToDelete in dataset.snapshotsRemoteToDelete {
                // snapshotToDelete.snapshot is stored in local form; transform to remote for destroy
                _ = try await shell.execute(
                    remote(ZFS.destroy(subject: forwardPath(snapshotToDelete.snapshot))),
                    dryRun: !config.execute
                ).get()
            }
            for snapshotToSend in dataset.snapshotsLocalToSend {
                sendCommand = "zfs send -v"
                if let previousSnapshot = snapshotToSend.previous {
                    sendCommand += " -i \(previousSnapshot.snapshot)"
                }
                sendCommand += " \(snapshotToSend.this.snapshot) | \(sshLogin) zfs recv -F \(forwardPath(snapshotToSend.this.snapshot))"
                _ = try await shell.execute(
                    sendCommand,
                    dryRun: !config.execute
                ).get()
            }
        }
    }

    private func datasets() async throws -> [DatasetSnapshotOperation] {
        async let datasetsLocalBinding: [String] = try await shell.execute(
                ZFS.listDatasets(grepping: config.datasetGrep),
                dryRun: !config.execute
            )
            .get()
            .decodeStringLines(
                encoding: config.stringEncoding,
                lineSeparator: config.lineSeparator
            )
            .stdoutTyped
        async let snapshotsLocalBinding: [String] = try await shell.execute(
                ZFS.listSnapshots(grepping: config.datasetGrep),
                dryRun: !config.execute
            )
            .get()
            .decodeStringLines(
                encoding: config.stringEncoding,
                lineSeparator: config.lineSeparator
            )
            .stdoutTyped
        // Remote datasets carry the path transform; grep with the transformed pattern so the
        // remote-side `zfs list ... | grep` actually matches.
        async let snapshotsRemoteRawBinding: [String] = try await shell.execute(
                remote(ZFS.listSnapshots(grepping: remoteDatasetGrep)),
                dryRun: !config.execute
            )
            .get()
            .decodeStringLines(
                encoding: config.stringEncoding,
                lineSeparator: config.lineSeparator
            )
            .stdoutTyped
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
}

extension Syncer {
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
