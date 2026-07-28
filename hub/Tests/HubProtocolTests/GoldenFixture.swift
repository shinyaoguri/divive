import Foundation

enum GoldenFixture {
  static var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  static func packet() throws -> [UInt8] {
    try packet(atRepositoryPath: "protocol/golden/pose_v1.packet.hex")
  }

  static func packet(atRepositoryPath path: String) throws -> [UInt8] {
    try decodeHex(try hexText(atRepositoryPath: path))
  }

  static func hexText(atRepositoryPath path: String) throws -> String {
    try String(
      contentsOf: repositoryRoot.appendingPathComponent(path),
      encoding: .utf8
    )
  }

  static func decodeHex(_ text: String) throws -> [UInt8] {
    let hex = text.filter { !$0.isWhitespace }
    guard hex.count.isMultiple(of: 2) else {
      throw GoldenFixtureError.oddHexLength
    }

    return stride(from: 0, to: hex.count, by: 2).map { offset in
      let start = hex.index(hex.startIndex, offsetBy: offset)
      let end = hex.index(start, offsetBy: 2)
      return UInt8(hex[start..<end], radix: 16)!
    }
  }
}

enum GoldenFixtureError: Error {
  case oddHexLength
}
