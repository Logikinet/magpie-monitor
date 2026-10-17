import XCTest
import Foundation
@testable import MagpieKit

private actor ScriptedTrace: TraceSource {
    var calls: [Int] = []
    var results: [Result<TraceEnvelope, MagpieError>]
    init(_ results: [Result<TraceEnvelope, MagpieError>]) { self.results = results }
    func trace(after: Int, wait: Bool) throws -> TraceEnvelope {
        calls.append(after)
        guard wait, !results.isEmpty else { throw CancellationError() }
        return try results.removeFirst().get()
    }
}

private actor PollRecording {
    var statuses: [PollStatus] = []
    var sleeps: [TimeInterval] = []
    var sequences: [Int] = []
    func event(_ event: TraceEvent) {
        switch event {
        case .status(let status): statuses.append(status)
        case .envelope(let envelope): sequences.append(envelope.seq?.value ?? -1)
        }
    }
    func sleep(_ seconds: TimeInterval) { sleeps.append(seconds) }
}

final class TracePollerTests: XCTestCase {
    private func envelope(_ seq: Int) throws -> TraceEnvelope {
        try MagpieJSON.decoder.decode(TraceEnvelope.self, from: Data("{\"seq\":\(seq),\"routes\":[]}".utf8))
    }

    func testBackoffCapJitterAndReset() {
        var backoff = Backoff(random: { 1 })
        XCTAssertEqual((0..<9).map { _ in backoff.next() }, [0.5, 1, 2, 4, 8, 16, 30, 30, 30])
        backoff.reset()
        XCTAssertEqual(backoff.next(), 0.5)
        var half = Backoff(random: { 0.5 })
        XCTAssertEqual(half.next(), 0.25)
        var zero = Backoff(random: { 0 })
        XCTAssertEqual(zero.next(), 0)
    }

    func testSequencesAndServerRestart() async throws {
        let source = ScriptedTrace(try [5, 8, 2, 4].map { .success(try envelope($0)) })
        let recording = PollRecording()
        let poller = TracePoller(source: source, sleeper: { await recording.sleep($0) })
        await poller.run { await recording.event($0) }
        let calls = await source.calls
        let last = await poller.lastSeq
        let sequences = await recording.sequences
        let statuses = await recording.statuses
        XCTAssertEqual(calls, [0, 5, 8, 0, 4])
        XCTAssertEqual(last, 4)
        XCTAssertEqual(sequences, [5, 8, 2, 4])
        XCTAssertEqual(statuses.first, .connecting)
        XCTAssertEqual(statuses.last, .stopped)
    }

    func testErrorsTimeoutAndReset() async throws {
        let source = ScriptedTrace([
            .failure(.network("模拟错误")), .failure(.timeout), .failure(.network("模拟错误")),
            .success(try envelope(1)), .failure(.unauthorized), .failure(.network("模拟错误"))
        ])
        let recording = PollRecording()
        let poller = TracePoller(source: source, backoff: Backoff(random: { 1 }),
                                 sleeper: { await recording.sleep($0) })
        await poller.run { await recording.event($0) }
        let sleeps = await recording.sleeps
        let statuses = await recording.statuses
        XCTAssertEqual(sleeps, [0.5, 0.1, 1, 0.1, 0.5, 1])
        XCTAssertTrue(statuses.contains(.unauthorized))
        XCTAssertEqual(statuses.filter { if case .backingOff = $0 { return true }; return false },
                       [.backingOff(0.5), .backingOff(1), .backingOff(0.5), .backingOff(1)])
    }

    func testCancellationDuringSleepFinishes() async {
        let sleeping = expectation(description: "进入休眠")
        let source = ScriptedTrace([.failure(.network("模拟错误"))])
        let recording = PollRecording()
        let poller = TracePoller(source: source, sleeper: { _ in
            sleeping.fulfill()
            try await Task.sleep(for: .seconds(3600))
        })
        let task = Task { await poller.run { await recording.event($0) } }
        await fulfillment(of: [sleeping], timeout: 2)
        task.cancel()
        await task.value
        let statuses = await recording.statuses
        let calls = await source.calls
        XCTAssertEqual(statuses.last, .stopped)
        XCTAssertEqual(calls, [0])
    }
}
