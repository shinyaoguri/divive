import Foundation

public enum CalibrationStoreError: Error, Equatable, Sendable {
  case profileNotFound(path: String)
  case unsupportedFormatVersion(Int)
  case malformedProfile(path: String, reason: String)
  case writeFailed(path: String, reason: String)
}

/// calibration profileをJSONファイルへ永続化する。
///
/// 読み込みに失敗した場合はidentity transformへfallbackせずthrowする。
/// 壊れたprofileを黙って無視すると、未較正の座標が較正済みとしてcontentへ流れる。
public struct CalibrationStore: Sendable {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  public static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  public func exists() -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  public func load() throws -> CalibrationProfile {
    guard exists() else {
      throw CalibrationStoreError.profileNotFound(path: url.path)
    }

    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw CalibrationStoreError.malformedProfile(
        path: url.path,
        reason: String(describing: error)
      )
    }

    do {
      return try Self.makeDecoder().decode(CalibrationProfile.self, from: data)
    } catch let error as CalibrationProfileError {
      if case let .unsupportedFormatVersion(version) = error {
        throw CalibrationStoreError.unsupportedFormatVersion(version)
      }
      throw CalibrationStoreError.malformedProfile(
        path: url.path,
        reason: String(describing: error)
      )
    } catch {
      throw CalibrationStoreError.malformedProfile(
        path: url.path,
        reason: String(describing: error)
      )
    }
  }

  /// 中断しても既存profileが半端な内容にならないようatomicに書き出す。
  public func save(_ profile: CalibrationProfile) throws {
    let data: Data
    do {
      data = try Self.makeEncoder().encode(profile)
    } catch {
      throw CalibrationStoreError.writeFailed(
        path: url.path,
        reason: String(describing: error)
      )
    }

    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: url, options: [.atomic])
    } catch {
      throw CalibrationStoreError.writeFailed(
        path: url.path,
        reason: String(describing: error)
      )
    }
  }
}
