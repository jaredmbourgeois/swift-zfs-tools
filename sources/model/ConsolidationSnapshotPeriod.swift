// ConsolidationSnapshotPeriod.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation

extension Consolidator {
    /// The unit a consolidation period steps by.
    public enum SnapshotConsolidationPeriodType: String, Codable, Hashable, Sendable {
        case years
        case months
        case weeks
        case days
        case hours
    }

    /// One band of the retention schedule: keep `snapshots` snapshot(s) within each window of
    /// `everyMultiple` × `everyPeriod`, for `repetitions` windows back from the schedule's upper
    /// bound. `repetitions == nil` means repeat indefinitely (covers everything older).
    public struct SnapshotConsolidationPeriod: Codable, Equatable, Sendable {
        public let everyMultiple: UInt16
        public let everyPeriod: SnapshotConsolidationPeriodType
        public let snapshots: UInt16
        public let repetitions: UInt16?
    }

    /// An ordered list of periods (finest first) that decides which snapshots survive consolidation,
    /// evaluated back from `upperBound` (a timestamp in the configured date format, or `nil` = now).
    /// This is the `consolidation-period-path` / `schedule` JSON shape; build it with `Builder`.
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

extension Consolidator.SnapshotConsolidationPeriod {
    /// Rejects a zero `everyMultiple` or `snapshots` at decode time: the schedule math would
    /// otherwise spin forever (`everyMultiple: 0` never advances the window backward) or crash
    /// on a malformed range (`snapshots: 0` yields an invalid `1...0` interval).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let everyMultiple = try container.decode(UInt16.self, forKey: .everyMultiple)
        let everyPeriod = try container.decode(Consolidator.SnapshotConsolidationPeriodType.self, forKey: .everyPeriod)
        let snapshots = try container.decode(UInt16.self, forKey: .snapshots)
        let repetitions = try container.decodeIfPresent(UInt16.self, forKey: .repetitions)
        guard everyMultiple > 0 else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "everyMultiple must be at least 1"
                )
            )
        }
        guard snapshots > 0 else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "snapshots must be at least 1"
                )
            )
        }
        self.init(
            everyMultiple: everyMultiple,
            everyPeriod: everyPeriod,
            snapshots: snapshots,
            repetitions: repetitions
        )
    }
}

extension Consolidator.SnapshotConsolidationSchedule {
    /// Fluent builder for a schedule. Chain `keepingSnapshots(…)` for finite bands, then finish with
    /// `build()` or `buildIndefinitelyKeepingSnapshots(…)` for the open-ended tail (e.g. yearly forever).
    public final class Builder {
        private var periods: [Consolidator.SnapshotConsolidationPeriod] = []
        private let upperBound: String?
        public init(upperBound: String? = nil) {
            self.upperBound = upperBound
        }

        /// Finish the schedule with the periods accumulated so far.
        public func build() -> Consolidator.SnapshotConsolidationSchedule {
            let periods = periods
            self.periods = []
            return .init(periods: periods, upperBound: upperBound)
        }

        /// Append a final, indefinitely-repeating band (`repetitions == nil`) and `build()`.
        public func buildIndefinitelyKeepingSnapshots(
            _ snapshots: UInt16,
            every everyMultiple: UInt16,
            _ everyPeriod: Consolidator.SnapshotConsolidationPeriodType
        ) -> Consolidator.SnapshotConsolidationSchedule {
            // The same floor the decoder enforces: a zero never advances the window, or yields an
            // invalid `1...0` range. A builder is code, so a zero here is a programmer error.
            precondition(everyMultiple > 0 && snapshots > 0, "a consolidation band needs everyMultiple ≥ 1 and snapshots ≥ 1")
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

        /// Append a finite band: keep `snapshots` per `everyMultiple` × `everyPeriod` window,
        /// `repeatedBy` windows back. Returns `self` to keep chaining.
        @discardableResult
        public func keepingSnapshots(
            _ snapshots: UInt16,
            every everyMultiple: UInt16,
            _ everyPeriod: Consolidator.SnapshotConsolidationPeriodType,
            repeatedBy repetitions: UInt16 = 1
        ) -> Self {
            precondition(everyMultiple > 0 && snapshots > 0, "a consolidation band needs everyMultiple ≥ 1 and snapshots ≥ 1")
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
