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
                _ = try await shell.execute(
                    remote(ZFS.destroy(subject: snapshotToDelete.snapshot)),
                    dryRun: !config.execute
                ).get()
            }
            for snapshotToSend in dataset.snapshotsLocalToSend {
                sendCommand = "zfs send -v"
                if let previousSnapshot = snapshotToSend.previous {
                    sendCommand += " -i \(previousSnapshot.snapshot)"
                }
                sendCommand += " \(snapshotToSend.this.snapshot) | \(sshLogin) zfs recv -F \(snapshotToSend.this.snapshot)"
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
        async let snapshotsRemoteBinding: [String] = try await shell.execute(
                remote(ZFS.listSnapshots(grepping: config.datasetGrep)),
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
            snapshotsRemote
        ) = try await (
            datasetsLocalBinding,
            snapshotsLocalBinding,
            snapshotsRemoteBinding
        )
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
            stringEncoding: String.Encoding
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
