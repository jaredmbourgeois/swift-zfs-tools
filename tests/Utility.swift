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
let snapshotRecordListCommand = "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg"

func snapshotRecord(_ guid: String, _ createtxg: UInt64, _ name: String) -> String {
    "\(guid)\t\(createtxg)\t\(name)"
}

func snapshotRecordOutput(_ names: [String]) -> String {
    names.map { name in
        snapshotRecord(snapshotGuid(name), snapshotCreatetxg(name), name)
    }
    .joined(separator: "\n")
}

func snapshotGuid(_ name: String) -> String {
    "guid-\(name)"
}

func snapshotCreatetxg(_ name: String) -> UInt64 {
    guard let suffix = name.split(separator: "@", maxSplits: 1).last else { return 0 }
    let digits = suffix.filter { $0 >= "0" && $0 <= "9" }
    return UInt64(String(digits)) ?? 0
}

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
