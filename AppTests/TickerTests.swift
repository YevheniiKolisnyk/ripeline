import Foundation
import Testing
@testable import Ripeline

/// Records how long the ticker asked to sleep each time, then behaves like the gate.
private final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Duration] = []
    func record(_ duration: Duration) { lock.lock(); values.append(duration); lock.unlock() }
    var durations: [Duration] { lock.lock(); defer { lock.unlock() }; return values }
}

/// Releases one "second" at a time, so a ticker test never waits for real time.
private struct BeatGate: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() { (stream, continuation) = AsyncStream<Void>.makeStream() }

    func release() { continuation.yield() }

    /// Stands in for `Task.sleep`: returns when the test releases a beat, throws when cancelled.
    func sleep(_ duration: Duration) async throws {
        for await _ in stream { return }
        throw CancellationError()
    }
}

@MainActor
struct TickerTests {
    private final class Counter { var value = 0 }

    /// Makes a ticker over a gate, with a handler that counts and signals each call.
    private func harness() -> (ticker: TaskTicker, gate: BeatGate, counter: Counter, handled: AsyncStream<Void>, handler: @MainActor () -> Void) {
        let gate = BeatGate()
        let counter = Counter()
        let (handled, signal) = AsyncStream<Void>.makeStream()
        let ticker = TaskTicker(interval: .seconds(1), sleep: { try await gate.sleep($0) })
        return (ticker, gate, counter, handled, { counter.value += 1; signal.yield() })
    }

    @Test func callsTheHandlerOncePerBeat() async {
        let h = harness()
        var handled = h.handled.makeAsyncIterator()
        h.ticker.start(h.handler)
        #expect(h.counter.value == 0)
        h.gate.release()
        await handled.next()
        #expect(h.counter.value == 1)
        h.gate.release()
        await handled.next()
        #expect(h.counter.value == 2)
        h.ticker.stop()
    }

    @Test func stoppingEndsTheLoop() async {
        let h = harness()
        var handled = h.handled.makeAsyncIterator()
        h.ticker.start(h.handler)
        #expect(h.ticker.isRunning)
        h.gate.release()
        await handled.next()
        h.ticker.stop()
        #expect(!h.ticker.isRunning)
        h.gate.release()
        for _ in 0..<50 { await Task.yield() }
        #expect(h.counter.value == 1)
    }

    @Test func startingTwiceKeepsASingleLoop() async {
        let h = harness()
        var handled = h.handled.makeAsyncIterator()
        h.ticker.start(h.handler)
        h.ticker.start(h.handler)
        h.gate.release()
        await handled.next()
        for _ in 0..<50 { await Task.yield() }
        #expect(h.counter.value == 1)
        h.ticker.stop()
    }

    @Test func canBeStartedAgainAfterStopping() async {
        let h = harness()
        var handled = h.handled.makeAsyncIterator()
        h.ticker.start(h.handler)
        h.ticker.stop()
        h.ticker.start(h.handler)
        #expect(h.ticker.isRunning)
        h.gate.release()
        await handled.next()
        #expect(h.counter.value == 1)
        h.ticker.stop()
    }

    /// Review finding: a ticker that is released while running must not keep waking up.
    @Test func releasingARunningTickerEndsItsLoop() async {
        let gate = BeatGate()
        let counter = Counter()
        let (handled, signal) = AsyncStream<Void>.makeStream()
        var ticker: TaskTicker? = TaskTicker(interval: .seconds(1), sleep: { try await gate.sleep($0) })
        var handledIterator = handled.makeAsyncIterator()
        ticker?.start { counter.value += 1; signal.yield() }
        gate.release()
        await handledIterator.next()
        #expect(counter.value == 1)

        ticker = nil
        gate.release()
        for _ in 0..<50 { await Task.yield() }
        #expect(counter.value == 1)
    }

    /// Review finding: sleeping a fixed second after each tick drifts; sleep to the next deadline instead.
    @Test func sleepsUntilTheNextDeadlineNotAFullIntervalEachTime() async {
        let gate = BeatGate()
        let log = SleepLog()
        let (handled, signal) = AsyncStream<Void>.makeStream()
        let ticker = TaskTicker(interval: .seconds(1), sleep: { duration in
            log.record(duration)
            try await gate.sleep(duration)
        })
        var iterator = handled.makeAsyncIterator()
        ticker.start { signal.yield() }
        for _ in 0..<3 { gate.release(); await iterator.next() }
        ticker.stop()
        let durations = log.durations
        #expect(durations.count >= 3)
        #expect(durations.allSatisfy { $0 > .zero })
        #expect(durations[0] <= .seconds(1))
    }
}
