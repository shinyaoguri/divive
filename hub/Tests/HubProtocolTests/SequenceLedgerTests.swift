import HubProtocol
import XCTest

final class SequenceLedgerTests: XCTestCase {
  func test欠落重複順序逆転とsession変更を分類する() throws {
    let sessionA = try uuid(first: 0)
    let sessionB = try uuid(first: 32)
    let bridge = try uuid(first: 16)
    var ledger = SequenceLedger()

    XCTAssertEqual(
      ledger.observe(envelope(session: sessionA, bridge: bridge, sequence: 10)),
      .sessionStarted
    )
    XCTAssertEqual(
      ledger.observe(envelope(session: sessionA, bridge: bridge, sequence: 10)),
      .duplicate
    )
    XCTAssertEqual(
      ledger.observe(envelope(session: sessionA, bridge: bridge, sequence: 12)),
      .newFrame(missingFrames: 1, missingBatches: 0)
    )
    XCTAssertEqual(
      ledger.observe(envelope(session: sessionA, bridge: bridge, sequence: 11)),
      .outOfOrder
    )
    XCTAssertEqual(
      ledger.observe(envelope(session: sessionB, bridge: bridge, sequence: 1)),
      .sessionStarted
    )
  }

  func test複数batchの欠落とbatchCount不整合を分類する() throws {
    let session = try uuid(first: 0)
    let bridge = try uuid(first: 16)
    var ledger = SequenceLedger()

    XCTAssertEqual(
      ledger.observe(
        envelope(
          session: session,
          bridge: bridge,
          sequence: 1,
          batchIndex: 0,
          batchCount: 3
        )
      ),
      .sessionStarted
    )
    XCTAssertEqual(
      ledger.observe(
        envelope(
          session: session,
          bridge: bridge,
          sequence: 1,
          batchIndex: 1,
          batchCount: 3
        )
      ),
      .additionalBatch
    )
    XCTAssertEqual(
      ledger.observe(
        envelope(
          session: session,
          bridge: bridge,
          sequence: 1,
          batchIndex: 1,
          batchCount: 2
        )
      ),
      .inconsistentBatchCount
    )
    XCTAssertEqual(
      ledger.observe(envelope(session: session, bridge: bridge, sequence: 2)),
      .newFrame(missingFrames: 0, missingBatches: 1)
    )
  }

  private func uuid(first: UInt8) throws -> UUIDBytes {
    try UUIDBytes(bytes: (first..<(first + 16)).map { $0 })
  }

  private func envelope(
    session: UUIDBytes,
    bridge: UUIDBytes,
    sequence: UInt64,
    batchIndex: UInt16 = 0,
    batchCount: UInt16 = 1
  ) -> PacketEnvelope {
    PacketEnvelope(
      protocolMinor: 0,
      messageType: .poseBatch,
      flags: 0,
      sessionID: session,
      bridgeID: bridge,
      frameSequence: sequence,
      batchIndex: batchIndex,
      batchCount: batchCount
    )
  }
}
