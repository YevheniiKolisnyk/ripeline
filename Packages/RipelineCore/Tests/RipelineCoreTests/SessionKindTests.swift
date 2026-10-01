import Foundation
import Testing
@testable import RipelineCore

struct SessionKindTests {
    private func engine(kind: SessionKind = .day, _ plan: [PlannedSegment]? = nil) throws -> (SessionEngine, ManualClock) {
        let clock = ManualClock(t(9))
        var engine = SessionEngine(clock: clock)
        try engine.startDay(plan: plan ?? makePlan([(.work, 25), (.shortBreak, 5)]), settings: SessionSettings(), kind: kind)
        return (engine, clock)
    }

    // MARK: the kind

    @Test func aDayIsTheDefault() throws {
        let (engine, _) = try engine()
        #expect(engine.snapshot.kind == .day)
        #expect(SessionSnapshot.empty.kind == .day)

        var plain = SessionEngine(clock: ManualClock(t(9)))
        try plain.startDay(plan: makePlan([(.work, 25)]), settings: SessionSettings())   // no kind given
        #expect(plain.snapshot.kind == .day)
    }

    @Test func aQuickSessionKeepsItsKindThroughItsLife() throws {
        var (engine, clock) = try engine(kind: .quick)
        #expect(engine.snapshot.kind == .quick)
        try engine.start()
        clock.set(t(9, 10)); try engine.pause()
        #expect(engine.snapshot.kind == .quick)
        clock.set(t(9, 12)); try engine.resume()
        clock.set(t(9, 20)); try engine.endDay()
        #expect(engine.snapshot.kind == .quick)
    }

    // MARK: Codable and old files (Review Focus 1)

    private func roundTrip(_ snapshot: SessionSnapshot) throws -> SessionSnapshot {
        try JSONDecoder().decode(SessionSnapshot.self, from: JSONEncoder().encode(snapshot))
    }

    /// The JSON as an earlier version wrote it: the same object without a `kind`.
    private func withoutKind(_ snapshot: SessionSnapshot) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        object.removeValue(forKey: "kind")
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func aSnapshotWithoutAKindIsADayInEveryState() throws {
        var (engine, clock) = try engine()
        var snapshots = [engine.snapshot]                                     // idle
        try engine.start(); snapshots.append(engine.snapshot)                 // running
        clock.set(t(9, 10)); try engine.pause(); snapshots.append(engine.snapshot)
        clock.set(t(9, 12)); try engine.resume()
        clock.set(t(9, 40)); engine.tick(); snapshots.append(engine.snapshot) // overtime
        try engine.endDay(); snapshots.append(engine.snapshot)                // finished
        for snapshot in snapshots {
            let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: try withoutKind(snapshot))
            #expect(decoded == snapshot, "\(snapshot.state)")
            #expect(decoded.kind == .day)
        }
    }

    @Test func aQuickSessionRoundTripsAndRestores() throws {
        var (engine, _) = try engine(kind: .quick)
        try engine.start()
        let data = try JSONEncoder().encode(engine.snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["kind"] as? String == "quick")
        let decoded = try roundTrip(engine.snapshot)
        #expect(decoded == engine.snapshot && decoded.kind == .quick)
        _ = try SessionEngine(restoring: decoded, clock: ManualClock(t(9, 5)))
    }

    /// A snapshot exactly as the previous version wrote it, kept as a fixture.
    @Test func aFileWrittenBeforeTheKindExistedStillLoads() throws {
        let old = #"{"actuals":[{"intervals":[],"status":"active"}],"openInterval":{"kind":"work","start":790160400},"plan":[{"end":790161900,"id":"7089BD4A-583C-4CE2-B2C8-164EC8872EA3","index":0,"kind":"work","start":790160400}],"settings":{"autoAdvanceBreakToWork":false,"autoAdvanceWorkToBreak":false,"pausesCountAsRest":true},"state":{"running":{"endsAt":790161900,"segmentIndex":0}}}"#
        let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: Data(old.utf8))
        #expect(snapshot.kind == .day)
        #expect(snapshot.plan.count == 1)
        #expect(snapshot.state == .running(segmentIndex: 0, endsAt: Date(timeIntervalSinceReferenceDate: 790161900)))
        let restored = try SessionEngine(restoring: snapshot, clock: ManualClock(Date(timeIntervalSinceReferenceDate: 790160700)))
        #expect(restored.remainingTime() == 1200)
    }
}
