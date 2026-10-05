// PoolUtilization.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell

/// A point-in-time read of a pool's capacity percent and used/available bytes, with the
/// threshold check that the snapshot and consolidate guards use.
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

    /// `true` if either threshold is crossed: free space below `minFreeBytes`, or capacity above
    /// `maxCapacityPercent`. A `nil` threshold is ignored; both `nil` is always `false`.
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

    /// Read a pool's utilization via `zpool list` / `zfs list` (run in parallel). Both are read-only,
    /// so they run on a dry run too: the guard reads the real pool and reports what it would do.
    /// Unparseable output throws rather than silently reading 0%, which would let a full pool slip
    /// past the guard.
    static func query(
        pool: String,
        runner: ZFSRunner
    ) async throws -> PoolUtilization {
        // Two parallel local listings — read-only at the ZFS layer, parallel-safe.
        async let capacityBinding: String = try await runner.lines(ZFS.poolCapacity(pool: pool)).first ?? ""
        async let usedAvailableBinding: String = try await runner.lines(ZFS.listUsedAvailable(dataset: pool)).first ?? ""
        let (capacityString, usedAvailableString) = try await (capacityBinding, usedAvailableBinding)

        let capacityTrimmed = capacityString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let capacityPercent = Float(capacityTrimmed) else {
            throw ErrorType.shellError(command: ZFS.poolCapacity(pool: pool).commandLine, error: "unparseable pool capacity: \(capacityTrimmed)")
        }
        let usedAvailableTrimmed = usedAvailableString.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = usedAvailableTrimmed.split(separator: "\t")
        guard parts.count >= 2, let usedBytes = Int64(parts[0]), let availableBytes = Int64(parts[1]) else {
            throw ErrorType.shellError(command: ZFS.listUsedAvailable(dataset: pool).commandLine, error: "unparseable used/available: \(usedAvailableTrimmed)")
        }

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
