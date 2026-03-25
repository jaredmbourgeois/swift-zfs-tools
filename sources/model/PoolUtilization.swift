// PoolUtilization.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell

public struct PoolUtilization: Sendable, Equatable {
    public let capacityPercent: Float
    public let usedBytes: Int64
    public let availableBytes: Int64

    public init(
        capacityPercent: Float,
        usedBytes: Int64,
        availableBytes: Int64
    ) {
        self.capacityPercent = capacityPercent
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
    }

    public func exceedsThreshold(
        maxCapacityPercent: Float?,
        minFreeBytes: Int64?
    ) -> Bool {
        if let minFreeBytes, availableBytes < minFreeBytes {
            return true
        }
        if let maxCapacityPercent, capacityPercent > maxCapacityPercent {
            return true
        }
        return false
    }

    public static func query(
        pool: String,
        shell: ShellAtPath,
        dryRun: Bool,
        stringEncoding: String.Encoding,
        lineSeparator: String
    ) async throws -> PoolUtilization {
        async let capacityBinding: String = try await shell.execute(
            ZFS.poolCapacity(pool: pool),
            dryRun: dryRun
        )
        .get()
        .decodeStringLines(
            encoding: stringEncoding,
            lineSeparator: lineSeparator
        )
        .stdoutTyped
        .first ?? ""
        async let usedAvailableBinding: String = try await shell.execute(
            ZFS.listUsedAvailable(dataset: pool),
            dryRun: dryRun
        )
        .get()
        .decodeStringLines(
            encoding: stringEncoding,
            lineSeparator: lineSeparator
        )
        .stdoutTyped
        .first ?? ""
        let (capacityString, usedAvailableString) = try await (capacityBinding, usedAvailableBinding)

        let capacityPercent = Float(capacityString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let usedAvailableParts = usedAvailableString.split(separator: "\t")
        let usedBytes = usedAvailableParts.count > 0 ? Int64(usedAvailableParts[0]) ?? 0 : 0
        let availableBytes = usedAvailableParts.count > 1 ? Int64(usedAvailableParts[1]) ?? 0 : 0

        return PoolUtilization(
            capacityPercent: capacityPercent,
            usedBytes: usedBytes,
            availableBytes: availableBytes
        )
    }

    /// Extracts pool name from a dataset path (first path component) or datasetGrep pattern.
    public static func poolName(from datasetOrGrep: String?) -> String? {
        guard let datasetOrGrep, !datasetOrGrep.isEmpty else { return nil }
        return String(datasetOrGrep.split(separator: "/").first ?? Substring(datasetOrGrep))
    }
}
