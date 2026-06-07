// Utility.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import ZFSToolsModel

func decodeResourceJSON<T: Decodable>(
    named fileName: String,
    fileManager: FileManager,
    jsonDecoder: JSONDecoder
) throws -> T {
    let fileName = fileName.lowercased().contains(".json") ? fileName : "\(fileName).json"
    // URL(fileURLWithPath:) + .path is the correct file-path round-trip; URL(string:) +
    // .absoluteString only worked by accident for paths without spaces/special characters.
    let thisDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let resourceURL = thisDirectory.appendingPathComponent("resource/\(fileName)")
    guard let contents = fileManager.contents(atPath: resourceURL.path) else {
        throw ErrorType.fileNotFound(path: resourceURL.path)
    }
    return try jsonDecoder.decode(T.self, from: contents)
}

let calendar = makeCalendar()
let dateFormat = "yyyyMMdd-HHmmss"
let dateFormatter = makeDateFormatter(dateFormat)
let testDate = dateFormatter.date(from: testDateString)!
let testDateString = "20220806-000000"
let timeout = TimeInterval(1)

/// Dictionary-backed store behind a test `FileSystem` — exercises the Codable / ActionExecutor
/// read+write paths without touching disk. Backed by swift-shell's `Locked`, so it's `Sendable` for
/// the `@Sendable` closure boundary without a hand-rolled lock.
final class InMemoryFileStore: Sendable {
    private let files: Locked<[String: Data]>

    init(_ files: [String: Data] = [:]) {
        self.files = Locked(files)
    }

    func data(at path: String) -> Data? {
        files.withLock { $0[path] }
    }

    func setData(_ data: Data, at path: String) {
        files.withLock { $0[path] = data }
    }
}

extension FileSystem {
    static func inMemory(_ store: InMemoryFileStore) -> FileSystem {
        FileSystem(
            contents: { store.data(at: $0) },
            write: { data, path in store.setData(data, at: path) }
        )
    }
}
