import XCTest
@testable import FamilyDictation

final class HandoffTests: XCTestCase {
    private var directory: URL!
    private var store: HandoffStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = HandoffStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func state(_ phase: HandoffState.Phase, age: TimeInterval, text: String? = nil) -> HandoffState {
        HandoffState(phase: phase, text: text, message: nil, updatedAt: Date().addingTimeInterval(-age))
    }

    func testEmptyStoreIsIdle() {
        XCTAssertEqual(store.read().phase, .idle)
        XCTAssertFalse(store.consumeStopRequest())
    }

    func testResultRoundTripsAndClearRemovesIt() {
        store.write(state(.done, age: 0, text: "Clean text."))

        let read = store.read()
        XCTAssertEqual(read.phase, .done)
        XCTAssertEqual(read.text, "Clean text.")

        store.clear()
        XCTAssertEqual(store.read().phase, .idle)
        XCTAssertNil(store.read().text)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    func testStopRequestIsSeenExactlyOnce() {
        store.requestStop()
        XCTAssertTrue(store.consumeStopRequest())
        XCTAssertFalse(store.consumeStopRequest())
    }

    func testClearAlsoDropsAPendingStopRequest() {
        store.requestStop()
        store.clear()
        XCTAssertFalse(store.consumeStopRequest())
    }

    func testFreshStatesAreLeftAlone() {
        for phase in [HandoffState.Phase.listening, .cleaningUp, .done, .failed] {
            XCTAssertEqual(state(phase, age: 1).effective().phase, phase)
        }
    }

    func testListeningThatOutlivedTheRecordingLimitBecomesIdle() {
        XCTAssertEqual(state(.listening, age: HandoffState.maxListening + 1).effective().phase, .idle)
    }

    func testCleaningUpTimesOutWithAMessageInsteadOfSpinningForever() {
        let result = state(.cleaningUp, age: HandoffState.maxCleaning + 1).effective()
        XCTAssertEqual(result.phase, .failed)
        XCTAssertEqual(result.message, "Didn't work, try again")
    }

    func testOldResultIsDroppedRatherThanTypedSomewhereUnrelated() {
        let result = state(.done, age: HandoffState.maxResultAge + 1, text: "old words").effective()
        XCTAssertEqual(result.phase, .idle)
        XCTAssertNil(result.text)
    }

    // MARK: Background session

    private func session(heartbeatAge: TimeInterval, endsIn: TimeInterval) -> SessionInfo {
        SessionInfo(heartbeat: Date().addingTimeInterval(-heartbeatAge), endsAt: Date().addingTimeInterval(endsIn))
    }

    func testNoSessionFileMeansNoSession() {
        XCTAssertNil(store.session())
    }

    func testSessionRoundTripsAndSurvivesClearingAResult() {
        let info = session(heartbeatAge: 0, endsIn: 600)
        store.writeSession(info)
        store.write(state(.done, age: 0, text: "words"))

        store.clear()

        XCTAssertEqual(store.session()?.isAlive(), true)
        store.clearSession()
        XCTAssertNil(store.session())
    }

    func testSessionWithFreshHeartbeatIsAlive() {
        XCTAssertTrue(session(heartbeatAge: 1, endsIn: 300).isAlive())
    }

    func testSessionWithStaleHeartbeatIsDeadSoTheKeyboardOpensTheApp() {
        XCTAssertFalse(session(heartbeatAge: SessionInfo.heartbeatTimeout + 1, endsIn: 300).isAlive())
    }

    func testSessionPastItsEndIsDeadEvenWithAFreshHeartbeat() {
        XCTAssertFalse(session(heartbeatAge: 0, endsIn: -1).isAlive())
    }

    func testStartRequestIsSeenExactlyOnceAndClearedWithTheResult() {
        store.requestStart()
        XCTAssertTrue(store.consumeStartRequest())
        XCTAssertFalse(store.consumeStartRequest())

        store.requestStart()
        store.clear()
        XCTAssertFalse(store.consumeStartRequest())
    }
}
