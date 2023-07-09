import Foundation

extension Consolidator {
  public struct SnapshotPeriod: Codable, Hashable, Sendable {
    public let snapshots: UInt16
    public let frequency: SnapshotFrequency

    public func range(upperBound: Date, calendar: Calendar) -> Range<Date> {
      var lowerBound = upperBound
      for component in frequency {
        guard let date = calendar.date(
          byAdding: component.calendarComponent,
          value: component.value,
          to: lowerBound
        ) else { continue }
        lowerBound = date
      }
      guard lowerBound < upperBound else { return upperBound.addingTimeInterval(-1)..<upperBound }
      return lowerBound..<upperBound
    }
  }

  /// SnapshotPeriods are traversed first to last, going backward in time from start date.
  /// See `SnapshotPeriods.dateRanges(startingOn date: Date) -> [Range<Date>]`
  public typealias SnapshotPeriods = [SnapshotPeriod]
}

extension Consolidator.SnapshotPeriod {
  public enum Bias: Codable, Hashable, Sendable {
    case upperBound
    case lowerBound
  }
}

extension Consolidator.SnapshotPeriod {
  public typealias SnapshotFrequency = [SnapshotFrequencyComponent]

  public enum SnapshotFrequencyComponent: Codable, Hashable, Sendable {
    case year(UInt16)
    case month(UInt16)
    case weekOfMonth(UInt16)
    case weekOfYear(UInt16)
    case day(UInt16)
    case hour(UInt16)
    case minute(UInt16)

    public var calendarComponent: Calendar.Component {
      switch self {
      case .year: return .year
      case .month: return .month
      case .weekOfMonth: return .weekOfMonth
      case .weekOfYear: return .weekOfYear
      case .day: return .day
      case .hour: return .hour
      case .minute: return .minute
      }
    }

    public var value: Int {
      switch self {
      case .year(let value): return -Int(value)
      case .month(let value): return -Int(value)
      case .weekOfMonth(let value): return -Int(value)
      case .weekOfYear(let value): return -Int(value)
      case .day(let value): return -Int(value)
      case .hour(let value): return -Int(value)
      case .minute(let value): return -Int(value)
      }
    }
  }
}

extension Consolidator.SnapshotPeriod.SnapshotFrequency {
  public class Builder: @unchecked Sendable {
    private var frequency = Consolidator.SnapshotPeriod.SnapshotFrequency()

    public func build() -> Consolidator.SnapshotPeriod.SnapshotFrequency {
      let frequency = frequency
      self.frequency = []
      return frequency
    }

    public func with(
      years: UInt16? = nil,
      months: UInt16? = nil,
      weeksOfMonth: UInt16? = nil,
      weeksOfYear: UInt16? = nil,
      days: UInt16? = nil,
      hours: UInt16? = nil,
      minutes: UInt16? = nil
    ) -> Self {
      var snapshotComponents = [Consolidator.SnapshotPeriod.SnapshotFrequencyComponent]()
      if let years = years {
        snapshotComponents.append(.year(years))
      }
      if let months = months {
        snapshotComponents.append(.month(months))
      }
      if let weeksOfMonth = weeksOfMonth {
        snapshotComponents.append(.weekOfMonth(weeksOfMonth))
      }
      if let weeksOfYear = weeksOfYear {
        snapshotComponents.append(.weekOfYear(weeksOfYear))
      }
      if let days = days {
        snapshotComponents.append(.day(days))
      }
      if let hours = hours {
        snapshotComponents.append(.hour(hours))
      }
      if let minutes = minutes {
        snapshotComponents.append(.minute(minutes))
      }
      frequency.append(contentsOf: snapshotComponents)
      return self
    }
  }
}


extension Consolidator.SnapshotPeriod.SnapshotFrequencyComponent: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    switch lhs {
    case .minute(let lhsValue):
      switch rhs {
      case .minute(let rhsValue): return lhsValue == rhsValue
      default: return false
      }
    case .hour(let lhsValue):
      switch rhs {
      case .hour(let rhsValue): return lhsValue == rhsValue
      default: return false
      }
    case .day(let lhsValue):
      switch rhs {
      case .day(let rhsValue): return lhsValue == rhsValue
      default: return false
      }
    case .weekOfYear(let lhsValue):
      switch rhs {
      case .weekOfYear(let rhsValue): return lhsValue == rhsValue
      default: return false
      }
    case .weekOfMonth(let lhsValue):
      switch rhs {
      case .weekOfMonth(let rhsValue): return lhsValue == rhsValue
      default: return false
      }
    case .month(let lhsValue):
      switch rhs {
      case .month(let rhsValue): return lhsValue == rhsValue
      default: return false
      }
    case .year(let lhsValue):
      switch rhs {
      case .year(let rhsValue): return lhsValue == rhsValue
      default: return false
      }
    }
  }
}
