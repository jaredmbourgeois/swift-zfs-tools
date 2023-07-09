// ErrorType.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation

public enum ErrorType: Error, CustomDebugStringConvertible {
    case dateFromCalendar(date: Date, location: String)
    public static func dateFromCalendar(date: Date, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .dateFromCalendar(date: date, location: location(file: file, function: function, line: line))
    }

    case dateFromString(string: String, format: String, location: String)
    public static func dateFromString(string: String, format: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .dateFromString(string: string, format: format, location: location(file: file, function: function, line: line))
    }

    case fileNotFound(path: String, location: String)
    public static func fileNotFound(path: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .fileNotFound(path: path, location: location(file: file, function: function, line: line))
    }

    case jsonDecodeFailed(type: String, error: any Error, path: String, location: String)
    public static func jsonDecodeFailed<T>(type: T.Type, error: any Error, path: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .jsonDecodeFailed(type: String(reflecting: type), error: error, path: path, location: location(file: file, function: function, line: line))
    }

    case jsonEncodeFailed(type: String, error: any Error, path: String, location: String)
    public static func jsonEndcodeFailed<T>(type: T.Type, error: any Error, path: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .jsonEncodeFailed(type: String(reflecting: type), error: error, path: path, location: location(file: file, function: function, line: line))
    }

    case shellError(command: String, error: String, location: String)
    public static func shellError(command: String, error: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .shellError(command: command, error: error, location: location(file: file, function: function, line: line))
    }

    case shellFailure(command: String, location: String)
    public static func shellFailure(command: String, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .shellFailure(command: command, location: location(file: file, function: function, line: line))
    }

    case urlInvalid(path: String, location: String)

    case writeToURL(_ url: URL, error: any Error, location: String)
    public static func writeToURL(_ url: URL, error: any Error, file: String = #file, function: String = #function, line: Int = #line) -> Self {
        .writeToURL(url, error: error, location: location(file: file, function: function, line: line))
    }

    public var debugDescription: String {
    switch self {
    case .dateFromCalendar(let date, let location): "Date (\(date)) from calendar operation failed from \(location)."
    case .dateFromString(let string, let format, let location): "Date formatted as \(format) could not be parsed from \(string), from \(location)."
    case .fileNotFound(let path, let location): "File not found at \(path), from \(location)."
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
