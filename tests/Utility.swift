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
) -> T {
    let fileName = fileName.lowercased().contains(".json") ? fileName : "\(fileName).json"
    let thisFile = URL(string: #filePath)!
    let thisDirectory = thisFile.deletingLastPathComponent()
    let resourceURL = thisDirectory.appendingPathComponent("resource/\(fileName)")
    let contents = fileManager.contents(atPath: resourceURL.absoluteString)!
    return try! jsonDecoder.decode(T.self, from: contents)
}

let calendar = makeCalendar()
let dateFormat = "yyyyMMdd-HHmmss"
let dateFormatter = makeDateFormatter(dateFormat)
let testDate = dateFormatter.date(from: testDateString)!
let testDateString = "20220806-000000"
let timeout = TimeInterval(1)

