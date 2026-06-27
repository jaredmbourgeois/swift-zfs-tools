// ErrorType.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation

/// The tool's error type. Each case captures a source `location` (file/function/line) via the
/// matching static factory and renders a diagnostic via `debugDescription`.
public enum ErrorType: Error, CustomDebugStringConvertible {
    /// A `Calendar` date computation (e.g. stepping a schedule period) returned no result.
    case dateFromCalendar(date: Date, location: String)
    public static func dateFromCalendar(date: Date, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .dateFromCalendar(date: date, location: location(file: file, function: function, line: line))
    }

    /// A string didn't parse as a date in the expected `format` (e.g. a snapshot suffix or upper bound).
    case dateFromString(string: String, format: String, location: String)
    public static func dateFromString(string: String, format: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .dateFromString(string: string, format: format, location: location(file: file, function: function, line: line))
    }

    /// No file (or no readable file) at `path`.
    case fileNotFound(path: String, location: String)
    public static func fileNotFound(path: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .fileNotFound(path: path, location: location(file: file, function: function, line: line))
    }

    /// JSON at `path` couldn't be decoded into the expected `type`.
    case jsonDecodeFailed(type: String, error: any Error, path: String, location: String)
    public static func jsonDecodeFailed<T>(type: T.Type, error: any Error, path: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .jsonDecodeFailed(type: String(reflecting: type), error: error, path: path, location: location(file: file, function: function, line: line))
    }

    /// A CLI/config argument was present but not in the format the tool accepts.
    case invalidArgument(name: String, value: String, reason: String, location: String)
    public static func invalidArgument(name: String, value: String, reason: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .invalidArgument(name: name, value: value, reason: reason, location: location(file: file, function: function, line: line))
    }

    /// A value of `type` couldn't be encoded to JSON for `path`.
    case jsonEncodeFailed(type: String, error: any Error, path: String, location: String)
    public static func jsonEncodeFailed<T>(type: T.Type, error: any Error, path: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .jsonEncodeFailed(type: String(reflecting: type), error: error, path: path, location: location(file: file, function: function, line: line))
    }

    /// A shell `command` ran but produced an error or unparseable output.
    case shellError(command: String, error: String, location: String)
    public static func shellError(command: String, error: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .shellError(command: command, error: error, location: location(file: file, function: function, line: line))
    }

    /// A shell `command` exited with a non-success status.
    case shellFailure(command: String, location: String)
    public static func shellFailure(command: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .shellFailure(command: command, location: location(file: file, function: function, line: line))
    }

    /// `path` couldn't be formed into a valid URL.
    case urlInvalid(path: String, location: String)

    /// Writing to `url` failed.
    case writeToURL(_ url: URL, error: any Error, location: String)
    public static func writeToURL(_ url: URL, error: any Error, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .writeToURL(url, error: error, location: location(file: file, function: function, line: line))
    }

    public var debugDescription: String {
    switch self {
    case .dateFromCalendar(let date, let location): "Date (\(date)) from calendar operation failed from \(location)."
    case .dateFromString(let string, let format, let location): "Date formatted as \(format) could not be parsed from \(string), from \(location)."
    case .fileNotFound(let path, let location): "File not found at \(path), from \(location)."
    case .invalidArgument(let name, let value, let reason, let location): "Invalid argument \(name)=\(value): \(reason), from \(location)."
    case .jsonDecodeFailed(let type, let error, let path, let location): "Could not DEcode \(type) at \(path), from \(location); \(String(reflecting: error))"
    case .jsonEncodeFailed(let type, let error, let path, let location): "Could not ENcode \(type) to \(path), from \(location); \(String(reflecting: error))"
    case .shellError(let command, let error, let location): "Shell command (\(command)), returned error (\(error)), from \(location)"
    case .shellFailure(let command, let location): "Shell command (\(command)), returned failure from \(location)."
    case .urlInvalid(let path, let location): "Invalid URL for \(path), from \(location)."
    case .writeToURL(let url, let error, let location): "Write to URL \(url), from \(location); \(String(reflecting: error))."
    }
    }

    private static func location(file: String, function: String, line: Int) -> String {
    var file = file
    let fileSplit = file.split(separator: "/")
    if let projectIndex = fileSplit.firstIndex(where: { String($0) == "swift-zfs-tools" }) {
    file = fileSplit[projectIndex..<fileSplit.count].joined(separator: "/")
    }
    return "\(file), function \(function), line \(line)"
    }
}
