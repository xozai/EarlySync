import XCTest
@testable import EarlySync

// MARK: - MockURLProtocol

/// Intercepts URLSession requests so tests can assert on outgoing calls
/// and script responses/failures without touching the network.
final class MockURLProtocol: URLProtocol {

    struct Stub {
        let statusCode: Int?
        let error: Error?
    }

    /// FIFO queue of responses to hand out, one per request.
    private static var stubQueue: [Stub] = []
    /// Every request the client made, in order, for assertion.
    private static var recordedRequests: [URLRequest] = []
    /// URLProtocol callbacks can land on different threads for concurrent requests.
    private static let stateLock = NSLock()

    static func reset() {
        stateLock.lock()
        stubQueue = []
        recordedRequests = []
        stateLock.unlock()
    }

    static func setStubQueue(_ stubs: [Stub]) {
        stateLock.lock()
        stubQueue = stubs
        stateLock.unlock()
    }

    static func allRecordedRequests() -> [URLRequest] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recordedRequests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.stateLock.lock()
        MockURLProtocol.recordedRequests.append(request)
        let stub = MockURLProtocol.stubQueue.isEmpty ? nil : MockURLProtocol.stubQueue.removeFirst()
        MockURLProtocol.stateLock.unlock()

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode ?? 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - LuxaforWebhookClientTests

final class LuxaforWebhookClientTests: XCTestCase {

    private var session: URLSession!
    private var client: LuxaforWebhookClient!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        client = LuxaforWebhookClient(session: session)
        KeychainService.shared.luxaforUserId = "test-user-id"
    }

    override func tearDown() {
        KeychainService.shared.luxaforUserId = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Success

    func testSetColor_success_sendsExpectedPayload() async throws {
        MockURLProtocol.setStubQueue([.init(statusCode: 200, error: nil)])

        await client.setColor(.red)

        XCTAssertEqual(MockURLProtocol.allRecordedRequests().count, 1)
        let request = try XCTUnwrap(MockURLProtocol.allRecordedRequests().first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.luxafor.co.uk/webhook/v1/actions/solid_color")
        XCTAssertEqual(request.httpMethod, "POST")

        let body = try XCTUnwrap(request.httpBodyOrStreamData())
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["userId"] as? String, "test-user-id")
        let actionFields = try XCTUnwrap(json["actionFields"] as? [String: Any])
        XCTAssertEqual(actionFields["color"] as? String, "red")
        XCTAssertNil(actionFields["custom_color"])
    }

    func testOff_sendsCustomColorPayload() async throws {
        MockURLProtocol.setStubQueue([.init(statusCode: 200, error: nil)])

        await client.off()

        let request = try XCTUnwrap(MockURLProtocol.allRecordedRequests().first)
        let body = try XCTUnwrap(request.httpBodyOrStreamData())
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let actionFields = try XCTUnwrap(json["actionFields"] as? [String: Any])
        XCTAssertEqual(actionFields["color"] as? String, "custom")
        XCTAssertEqual(actionFields["custom_color"] as? String, "000000")
    }

    // MARK: - Retry on failure

    func testSetColor_retriesOnceOnFailure_thenSucceeds() async {
        MockURLProtocol.setStubQueue([
            .init(statusCode: 500, error: nil),
            .init(statusCode: 200, error: nil),
        ])

        await client.setColor(.blue)

        XCTAssertEqual(MockURLProtocol.allRecordedRequests().count, 2)
    }

    func testSetColor_givesUpAfterOneRetry() async {
        MockURLProtocol.setStubQueue([
            .init(statusCode: 500, error: nil),
            .init(statusCode: 500, error: nil),
        ])

        await client.setColor(.green)

        // Initial attempt + exactly one retry, no more.
        XCTAssertEqual(MockURLProtocol.allRecordedRequests().count, 2)
    }

    // MARK: - Missing userId

    func testSetColor_missingUserId_doesNotSendRequest() async {
        KeychainService.shared.luxaforUserId = nil

        await client.setColor(.red)

        XCTAssertTrue(MockURLProtocol.allRecordedRequests().isEmpty)
    }

    // MARK: - Concurrency

    /// Actor isolation should serialize concurrent calls safely: every call gets its
    /// own request/response round trip, none are dropped or corrupted by the others.
    func testSetColor_concurrentCalls_allRequestsRecordedSafely() async {
        let colors: [LuxaforColor] = [.red, .green, .blue, .yellow]
        MockURLProtocol.setStubQueue(colors.map { _ in .init(statusCode: 200, error: nil) })

        await withTaskGroup(of: Void.self) { group in
            for color in colors {
                group.addTask { await self.client.setColor(color) }
            }
        }

        XCTAssertEqual(MockURLProtocol.allRecordedRequests().count, colors.count)
    }
}

// MARK: - URLRequest helper

private extension URLRequest {
    /// `httpBody` is nil for requests replayed through URLProtocol in some URLSession
    /// versions; fall back to reading the body stream if needed.
    func httpBodyOrStreamData() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
