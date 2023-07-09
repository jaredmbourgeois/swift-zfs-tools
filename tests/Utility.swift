import Foundation

func decodeResource<T: Decodable>(named fileName: String, fileManager: FileManager) -> T {
  let fileName = fileName.lowercased().contains(".json") ? fileName : "\(fileName).json"
  let thisFile = URL(string: #file)!
  let thisDirectory = thisFile.deletingLastPathComponent()
  let resourceURL = thisDirectory.appendingPathComponent("resource/\(fileName)")
  let contents = fileManager.contents(atPath: resourceURL.absoluteString)!
  return try! JSONDecoder().decode(T.self, from: contents)
}
