import Foundation
import Shell

extension Array {
  public func mapIndex<T>(_ map: (Int, Element) -> T) -> [T] {
    var index = 0
    return self.map {
      let value = map(index, $0)
      index += 1
      return value
    }
  }

  public func optional(at index: Self.Index) -> Element? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}

extension Date: @unchecked Sendable { }

extension FileManager {
  public func decodedJSON<Contents: Decodable>(atPath path: String) -> Contents? {
    let decoder = JSONDecoder()
    guard let data = contents(atPath: path),
          let contents = try? decoder.decode(Contents.self, from: data) else { return nil }
    return contents
  }
}

extension String {
  public static let lineSeparator = "\n"
  
  public var lines: [String] {
    splitXP(by: .lineSeparator)
  }

  public func rangesExcluded(from excludedRanges: [Range<Index>]) -> [Range<Index>] {
    guard let firstIndex = indices.first,
          let lastIndex = indices.last else { return [] }
    guard !excludedRanges.isEmpty else { return [ firstIndex..<index(lastIndex, offsetBy: 1) ] }

    let sortedExcludedRanges = excludedRanges.sorted(by: { $0.lowerBound < $1.lowerBound })
    var rangesToKeep = [Range<Index>]()
    var thisRangeLower: Index?
    var thisRangeUpper: Index?

    for index in indices {
      let keepIndex = !sortedExcludedRanges.contains(where: { $0.contains(index) })
      guard keepIndex else {
        if let lower = thisRangeLower {
          rangesToKeep.append(lower..<index)
          thisRangeLower = nil
          thisRangeUpper = nil
        }
        continue
      }
      if thisRangeLower == nil {
        thisRangeLower = index
      } else {
        thisRangeUpper = index
      }
    }
    if let thisRangeLower = thisRangeLower {
      rangesToKeep.append(thisRangeLower..<self.index(thisRangeUpper ?? lastIndex, offsetBy: 1))
    }
    return rangesToKeep
  }

  public func rangesExcluded(from string: String) -> [Range<Index>] {
    guard !self.isEmpty else { return [] }
    return rangesExcluded(from: rangesXP(of: string))
  }

  public func rangesXP(of string: String) -> [Range<Index>] {
    var ranges = [Range<Index>]()
    var thisLengthStart: Index
    var thisLengthEnd: Index
    var thisLengthRange: Range<Index>
    var thisLengthString: String
    var indexInt = 0
    for index in indices {
      thisLengthStart = index
      guard indexInt + string.count <= indices.count else {
        indexInt += 1
        continue
      }
      thisLengthEnd = self.index(index, offsetBy: string.count)
      thisLengthRange = thisLengthStart..<thisLengthEnd
      thisLengthString = String(self[thisLengthRange])
      if thisLengthString == string {
        ranges.append(thisLengthRange)
      }
      indexInt += 1
    }
    return ranges
  }

  public func splitXP(by separator: String) -> [String] {
    rangesExcluded(from: rangesXP(of: separator)).map { String(self[$0]) }
  }
}

extension TimeInterval {
  public static let secondsPerDay = TimeInterval(24 * secondsPerHour)
  public static let secondsPerHour = TimeInterval(60 * secondsPerMinute)
  public static let secondsPerMinute = TimeInterval(60)
}
