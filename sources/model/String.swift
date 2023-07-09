import Foundation

extension String {
  static let lineSeparator = "\n"

  var lines: [String] {
    split(separator: Self.lineSeparator).map { String($0) }
  }
}
