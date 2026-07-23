import Foundation

enum GoldenFixture {
  static func packet() throws -> [UInt8] {
    let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repositoryRoot =
      testDirectory
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fixtureURL =
      repositoryRoot
      .appendingPathComponent("protocol/golden/pose_v1.packet.hex")
    let hex = try String(contentsOf: fixtureURL, encoding: .utf8)
      .filter { !$0.isWhitespace }

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
