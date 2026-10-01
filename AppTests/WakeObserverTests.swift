import AppKit
import Foundation
import Testing
@testable import Ripeline

/// Serialized: every observer hears every wake and clock notification, so tests that run side by
/// side would count each other's posts.
@MainActor @Suite(.serialized)
struct WakeObserverTests {
    private final class Counter { var value = 0 }

    /// An observer whose callback counts and signals each call.
    private func harness() -> (observer: WakeObserver, counter: Counter, signals: AsyncStream<Void>) {
        let counter = Counter()
        let (signals, signal) = AsyncStream<Void>.makeStream()
        let observer = WakeObserver { counter.value += 1; signal.yield() }
        return (observer, counter, signals)
    }

    private func postWake() {
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
    }

    private func postClockChange() {
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
    }

    @Test func wakingCallsBack() async {
        let h = harness()
        var signals = h.signals.makeAsyncIterator()
        postWake()
        await signals.next()
        #expect(h.counter.value == 1)
        for _ in 0..<20 { await Task.yield() }
        #expect(h.counter.value == 1)
        h.observer.invalidate()
    }

    @Test func aClockChangeCallsBack() async {
        let h = harness()
        var signals = h.signals.makeAsyncIterator()
        postClockChange()
        await signals.next()
        #expect(h.counter.value == 1)
        h.observer.invalidate()
    }

    @Test func invalidatingStopsTheCallbacks() async {
        let h = harness()
        h.observer.invalidate()
        postWake()
        postClockChange()
        for _ in 0..<50 { await Task.yield() }
        #expect(h.counter.value == 0)
    }

    @Test func releasingTheObserverStopsTheCallbacks() async {
        let counter = Counter()
        var observer: WakeObserver? = WakeObserver { counter.value += 1 }
        _ = observer
        observer = nil
        postWake()
        for _ in 0..<50 { await Task.yield() }
        #expect(counter.value == 0)
    }
}
