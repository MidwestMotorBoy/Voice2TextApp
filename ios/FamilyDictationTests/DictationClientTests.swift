import XCTest
@testable import FamilyDictation

/// Answers every request with a canned response so no network is used.
final class StubProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var failure: URLError?
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class DictationClientTests: XCTestCase {
    private var client: DictationClient!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = DictationClient(session: URLSession(configuration: config))
        StubProtocol.status = 200
        StubProtocol.body = Data()
        StubProtocol.failure = nil
        StubProtocol.lastRequest = nil
    }

    private func send() async throws -> DictationResult {
        try await client.dictate(audio: Data([1, 2, 3]), seconds: 7, address: "worker.example.com", token: "test-token")
    }

    private func assertFails(with expected: DictationError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await send()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? DictationError, expected, file: file, line: line)
        }
    }

    func testSuccessReturnsTextAndSendsHeaders() async throws {
        StubProtocol.body = Data(#"{"text":"Clean text.","raw":"um clean text"}"#.utf8)

        let result = try await send()

        XCTAssertEqual(result, DictationResult(text: "Clean text.", raw: "um clean text"))
        let request = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://worker.example.com/dictate")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/mp4")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Duration-Seconds"), "7")
    }

    func testUnauthorized() async {
        StubProtocol.status = 401
        StubProtocol.body = Data(#"{"error":"unauthorized"}"#.utf8)
        await assertFails(with: .unauthorized)
        XCTAssertEqual(DictationError.unauthorized.message, "Token not accepted, check setup")
    }

    func testMonthlyLimit() async {
        StubProtocol.status = 429
        await assertFails(with: .limitReached)
        XCTAssertEqual(DictationError.limitReached.message, "Monthly limit reached")
    }

    func testTooLong() async {
        StubProtocol.status = 413
        await assertFails(with: .tooLong)
    }

    func testBadJSON() async {
        StubProtocol.body = Data("not json".utf8)
        await assertFails(with: .failed)
    }

    func testServerError() async {
        StubProtocol.status = 502
        await assertFails(with: .failed)
    }

    func testOffline() async {
        StubProtocol.failure = URLError(.notConnectedToInternet)
        await assertFails(with: .offline)
        XCTAssertEqual(DictationError.offline.message, "No internet")
    }

    func testEndpointAcceptsDifferentWaysOfTypingTheAddress() {
        let expected = "https://worker.example.com/dictate"
        XCTAssertEqual(DictationClient.endpoint(from: "worker.example.com")?.absoluteString, expected)
        XCTAssertEqual(DictationClient.endpoint(from: " https://worker.example.com/ ")?.absoluteString, expected)
        XCTAssertEqual(DictationClient.endpoint(from: "https://worker.example.com/dictate")?.absoluteString, expected)
        XCTAssertNil(DictationClient.endpoint(from: ""))
        XCTAssertNil(DictationClient.endpoint(from: "   "))
    }
}
