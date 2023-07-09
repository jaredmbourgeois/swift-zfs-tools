// ConsolidationSnapshotPeriod.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation

extension Consolidator {
    public enum SnapshotConsolidationPeriodType: String, Codable, Hashable, Sendable {
        case years
        case months
        case weeks
        case days
        case hours
    }

    public struct SnapshotConsolidationPeriod: Codable, Equatable, Sendable {
        public let everyMultiple: UInt16
        public let everyPeriod: SnapshotConsolidationPeriodType
        public let snapshots: UInt16
        public let repetitions: UInt16?
    }

    public struct SnapshotConsolidationSchedule: Codable, Equatable, Sendable {
        public let periods: [SnapshotConsolidationPeriod]
        public let upperBound: String?
        public init(
            periods: [SnapshotConsolidationPeriod],
            upperBound: String?
        ) {
            self.periods = periods
            self.upperBound = upperBound
        }
    }
}

extension Consolidator.SnapshotConsolidationSchedule {
    public final class Builder {
        private var periods: [Consolidator.SnapshotConsolidationPeriod] = []
        private let upperBound: String?
        public init(upperBound: String? = nil) {
            self.upperBound = upperBound
        }

        public func build() -> Consolidator.SnapshotConsolidationSchedule {
            let periods = periods
            self.periods = []
            return .init(periods: periods, upperBound: upperBound)
        }

        public func buildIndefinitelyKeepingSnapshots(
            _ snapshots: UInt16,
            every everyMultiple: UInt16,
            _ everyPeriod: Consolidator.SnapshotConsolidationPeriodType
        ) -> Consolidator.SnapshotConsolidationSchedule {
            periods.append(
                .init(
                    everyMultiple: everyMultiple,
                    everyPeriod: everyPeriod,
                    snapshots: snapshots,
                    repetitions: nil
                )
            )
            return build()
        }

        @discardableResult
        public func keepingSnapshots(
            _ snapshots: UInt16,
            every everyMultiple: UInt16,
            _ everyPeriod: Consolidator.SnapshotConsolidationPeriodType,
            repeatedBy repetitions: UInt16 = 1
        ) -> Self {
            periods.append(
                .init(
                    everyMultiple: everyMultiple,
                    everyPeriod: everyPeriod,
                    snapshots: snapshots,
                    repetitions: repetitions
                )
            )
            return self
        }
    }
}
