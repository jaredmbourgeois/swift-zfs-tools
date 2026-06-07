// Codable.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation

/// Decode a `T` from the JSON file at `path`, read through the injectable `fileSystem`. Throws
/// `ErrorType.fileNotFound` if the file is missing, `ErrorType.jsonDecodeFailed` if it won't decode.
public func decodeFromJSONAtPath<T: Decodable>(
    _ path: String,
    fileSystem: FileSystem,
    jsonDecoder: JSONDecoder
) throws -> T {
    guard let data = fileSystem.contents(path) else {
        throw ErrorType.fileNotFound(path: path)
    }
    let type: T
    do {
        type = try jsonDecoder.decode(T.self, from: data)
    } catch {
        throw ErrorType.jsonDecodeFailed(type: T.self, error: error, path: path)
    }
    return type
}

/// Encode `encodable` to pretty-printed JSON and write it through `fileSystem` (atomically, in the
/// `.live` implementation). Appends `.json` to `path` if missing. Throws `ErrorType.jsonEncodeFailed`
/// or `ErrorType.writeToURL` on failure.
public func encode<T: Encodable>(
    _ encodable: T,
    toJSONAtPath path: String,
    fileSystem: FileSystem,
    jsonEncoder: JSONEncoder
) throws {
    let path = path.lowercased().contains(".json") ? path : path + ".json"
    let currentFormatting = jsonEncoder.outputFormatting
    defer { jsonEncoder.outputFormatting = currentFormatting }
    jsonEncoder.outputFormatting = jsonEncoder.outputFormatting.union(.prettyPrinted)
    let data: Data
    do {
        data = try jsonEncoder.encode(encodable)
    } catch {
        throw ErrorType.jsonEncodeFailed(type: T.self, error: error, path: path)
    }
    do {
        try fileSystem.write(data, path)
    } catch {
        throw ErrorType.writeToURL(URL(fileURLWithPath: path), error: error)
    }
}
