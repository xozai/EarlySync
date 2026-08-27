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
    static var stubQueue: [Stub] = []
    /// Every request the client made, in order, for assertion.
    static var recordedRequests: [URLRequest] = []

    static func reset() {
        stubQueue = []
        recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.recordedRequests.append(request)

        guard !MockURLProtocol.stubQueue.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let stub = MockURLProtocol.stubQueue.removeFirst()

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
        MockURLProtocol.stubQueue = [.init(statusCode: 200, error: nil)]

        await client.setColor(.red)

        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1)
        let request = try XCTUnwrap(MockURLProtocol.recordedRequests.first)
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
        MockURLProtocol.stubQueue = [.init(statusCode: 200, error: nil)]

        await client.off()

        let request = try XCTUnwrap(MockURLProtocol.recordedRequests.first)
        let body = try XCTUnwrap(request.httpBodyOrStreamData())
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let actionFields = try XCTUnwrap(json["actionFields"] as? [String: Any])
        XCTAssertEqual(actionFields["color"] as? String, "custom")
        XCTAssertEqual(actionFields["custom_color"] as? String, "000000")
    }

    // MARK: - Retry on failure

    func testSetColor_retriesOnceOnFailure_thenSucceeds() async {
        MockURLProtocol.stubQueue = [
            .init(statusCode: 500, error: nil),
            .init(statusCode: 200, error: nil),
        ]

        await client.setColor(.blue)

        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 2)
    }

    func testSetColor_givesUpAfterOneRetry() async {
        MockURLProtocol.stubQueue = [
            .init(statusCode: 500, error: nil),
            .init(statusCode: 500, error: nil),
        ]

        await client.setColor(.green)

        // Initial attempt + exactly one retry, no more.
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 2)
    }

    // MARK: - Missing userId

    func testSetColor_missingUserId_doesNotSendRequest() async {
        KeychainService.shared.luxaforUserId = nil

        await client.setColor(.red)

        XCTAssertTrue(MockURLProtocol.recordedRequests.isEmpty)
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
