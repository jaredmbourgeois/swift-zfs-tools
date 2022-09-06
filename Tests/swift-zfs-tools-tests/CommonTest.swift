import Foundation
import XCTest

@testable import swift_zfs_tools

class CommonTest: XCTestCase {
  let idA = UUID().uuidString
  let idB = UUID().uuidString
  let idC = UUID().uuidString
  let separator = "@"
  let separatorLong = UUID().uuidString

  func testRangesXP() {
    let string = "@"
    let test = "\(string)123456789\(string)123456789\(string)"
    let ranges = test.rangesXP(of: string)
    let testStrings = ranges.map { String(test[$0]) }
    XCTAssertEqual(3, ranges.count)
    XCTAssertEqual([string, string, string], testStrings)
  }

  func testSplitXP() {
    let string = "\(idA)\(separator)\(idB)\(separator)\(idC)"
    let split = string.splitXP(by: separator)
    XCTAssertEqual(3, split.count)
    XCTAssertEqual(idA, split[0])
    XCTAssertEqual(idB, split[1])
    XCTAssertEqual(idC, split[2])
  }

  func testSplitXPLong() {
    let string = "\(idA)\(separatorLong)\(idB)\(separatorLong)\(idC)"
    let split = string.splitXP(by: separatorLong)
    XCTAssertEqual(3, split.count)
    XCTAssertEqual(idA, split[0])
    XCTAssertEqual(idB, split[1])
    XCTAssertEqual(idC, split[2])
  }

  func testSplitXPStartingWithSeparator() {
    let string = "\(separator)\(idA)\(separator)\(idB)\(separator)\(idC)"
    let split = string.splitXP(by: separator)
    XCTAssertEqual(3, split.count)
    XCTAssertEqual(idA, split[0])
    XCTAssertEqual(idB, split[1])
    XCTAssertEqual(idC, split[2])
  }

  func testSplitXPStartingWithSeparatorLong() {
    let string = "\(separatorLong)\(idA)\(separatorLong)\(idB)\(separatorLong)\(idC)"
    let split = string.splitXP(by: separatorLong)
    XCTAssertEqual(3, split.count)
    XCTAssertEqual(idA, split[0])
    XCTAssertEqual(idB, split[1])
    XCTAssertEqual(idC, split[2])
  }

  func testSplitXPEndingWithSeparator() {
    let string = "\(idA)\(separator)\(idB)\(separator)\(idC)\(separator)"
    let split = string.splitXP(by: separator)
    XCTAssertEqual(3, split.count)
    XCTAssertEqual(idA, split[0])
    XCTAssertEqual(idB, split[1])
    XCTAssertEqual(idC, split[2])
  }

  func testSplitXPEndingWithSeparatorLong() {
    let string = "\(idA)\(separatorLong)\(idB)\(separatorLong)\(idC)\(separatorLong)"
    let split = string.splitXP(by: separatorLong)
    XCTAssertEqual(3, split.count)
    XCTAssertEqual(idA, split[0])
    XCTAssertEqual(idB, split[1])
    XCTAssertEqual(idC, split[2])
  }

  func testSplitXPStartingAndEndingWithSeparator() {
    let string = "\(separator)\(idA)\(separator)\(idB)\(separator)\(idC)\(separator)"
    let split = string.splitXP(by: separator)
    XCTAssertEqual(3, split.count)
    XCTAssertEqual(idA, split[0])
    XCTAssertEqual(idB, split[1])
    XCTAssertEqual(idC, split[2])
  }

  func testSplitXPStartingAndEndingWithSeparatorLong() {
    let string = "\(separatorLong)\(idA)\(separatorLong)\(idB)\(separatorLong)\(idC)\(separatorLong)"
    let split = string.splitXP(by: separatorLong)
    XCTAssertEqual(3, split.count)
    XCTAssertEqual(idA, split[0])
    XCTAssertEqual(idB, split[1])
    XCTAssertEqual(idC, split[2])
  }

  func testSplitXPNoSeparator() {
    let string = "\(idA)\(idB)\(idC)"
    let split = string.splitXP(by: separator)
    XCTAssertEqual(1, split.count)
    XCTAssertEqual(string, split[0])
  }

  func testSplitXPOnlySeparator() {
    let string = "\(separator)\(separator)\(separator)"
    let split = string.splitXP(by: separator)
    XCTAssertTrue(split.isEmpty)
  }
}

