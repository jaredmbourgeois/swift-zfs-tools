import Foundation

public func decodeFromJsonAtPath<T: Decodable>(
  _ path: String,
  fileManager: FileManager,
  jsonDecoder: JSONDecoder
) throws -> T {
  guard let data = fileManager.contents(atPath: path) else {
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

public func encode<T: Encodable>(
  _ encodable: T,
  toJsonAtPath path: String,
  fileManager: FileManager,
  jsonEncoder: JSONEncoder
) throws {
  let path = path.lowercased().contains(".json") ? path : path + ".json"
  let url = URL(fileURLWithPath: path)
  let currentFormatting = jsonEncoder.outputFormatting
  defer { jsonEncoder.outputFormatting = currentFormatting }
  jsonEncoder.outputFormatting = .prettyPrinted
  let data: Data
  do {
    data = try jsonEncoder.encode(encodable)
  } catch {
    throw ErrorType.jsonEndcodeFailed(type: T.self, error: error, path: path)
  }
  do {
    try data.write(to: url)
  } catch {
    throw ErrorType.writeToURL(url, error: error)
  }
}
