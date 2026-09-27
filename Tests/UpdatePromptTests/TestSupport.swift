import Foundation
import Testing
@testable import UpdatePrompt

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "Missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }
}

extension HTTPTransport {
    /// Answers every request with `data` and `status`, and records the requested URLs.
    static func stub(_ data: Data, status: Int = 200, recorder: RequestRecorder? = nil) -> HTTPTransport {
        HTTPTransport { request in
            recorder?.record(request)
            let url = request.url ?? URL(string: "https://example.com")!
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }

    static func failing(_ error: URLError.Code) -> HTTPTransport {
        HTTPTransport { _ in throw URLError(error) }
    }
}

final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { storage } }

    func record(_ request: URLRequest) {
        lock.withLock { storage.append(request) }
    }
}

/// A clock the test moves forward by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.date = date
    }

    var now: Date { lock.withLock { date } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(seconds) }
    }
}

/// An in-memory source whose answer can change between checks.
final class StubUpdateSource: UpdateSource, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<UpdateInfo, UpdateSourceError>
    private var count = 0

    init(_ update: UpdateInfo) {
        result = .success(update)
    }

    init(error: UpdateSourceError) {
        result = .failure(error)
    }

    var callCount: Int { lock.withLock { count } }

    func set(_ update: UpdateInfo) {
        lock.withLock { result = .success(update) }
    }

    func latestUpdate() async throws -> UpdateInfo {
        let result = lock.withLock {
            count += 1
            return self.result
        }
        return try result.get()
    }
}
