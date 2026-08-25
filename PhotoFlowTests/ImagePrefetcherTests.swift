import Foundation
import Synchronization
import Testing

@testable import PhotoFlow

@Suite(.serialized)
struct ImagePrefetcherTests {

    @Test
    func duplicatePrefetchForSameURLStartsOnlyOneRequest() async {
        guard let url = URL(
            string: "https://example.com/prefetch-image.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        let requestStarted = TestSignal()
        let requestStopped = TestSignal()

        ImagePrefetchURLProtocolStub.prepare(
            requestStarted: requestStarted,
            requestStopped: requestStopped
        )

        let session = makeStubbedSession()

        let dataLoader = ImageDataLoader(
            session: session
        )

        let prefetcher = ImagePrefetcher(
            dataLoader: dataLoader
        )

        prefetcher.prefetch(
            urls: [url]
        )

        prefetcher.prefetch(
            urls: [url]
        )

        await requestStarted.wait()

        #expect(
            ImagePrefetchURLProtocolStub.requestCount == 1
        )

        prefetcher.cancelPrefetching(
            urls: [url]
        )

        await requestStopped.wait()
    }

    @Test
    func cancellingPrefetchCancelsNetworkRequest() async {
        guard let url = URL(
            string: "https://example.com/cancel-prefetch-image.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        let requestStarted = TestSignal()
        let requestStopped = TestSignal()

        ImagePrefetchURLProtocolStub.prepare(
            requestStarted: requestStarted,
            requestStopped: requestStopped
        )

        let session = makeStubbedSession()

        let dataLoader = ImageDataLoader(
            session: session
        )

        let prefetcher = ImagePrefetcher(
            dataLoader: dataLoader
        )

        prefetcher.prefetch(
            urls: [url]
        )

        await requestStarted.wait()

        #expect(
            ImagePrefetchURLProtocolStub.requestCount == 1
        )

        prefetcher.cancelPrefetching(
            urls: [url]
        )

        await requestStopped.wait()

        #expect(
            ImagePrefetchURLProtocolStub.stopCount == 1
        )
    }

    private func makeStubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral

        configuration.protocolClasses = [
            ImagePrefetchURLProtocolStub.self
        ]

        return URLSession(
            configuration: configuration
        )
    }
}

private final class ImagePrefetchURLProtocolStub: URLProtocol {

    private struct State {
        var requestCount = 0
        var stopCount = 0
        var requestStarted: TestSignal?
        var requestStopped: TestSignal?
    }

    private static let state = Mutex(
        State()
    )

    static var requestCount: Int {
        state.withLock { state in
            state.requestCount
        }
    }

    static var stopCount: Int {
        state.withLock { state in
            state.stopCount
        }
    }

    static func prepare(
        requestStarted: TestSignal,
        requestStopped: TestSignal
    ) {
        state.withLock { state in
            state.requestCount = 0
            state.stopCount = 0
            state.requestStarted = requestStarted
            state.requestStopped = requestStopped
        }
    }

    override class func canInit(
        with request: URLRequest
    ) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        let requestStarted = Self.state.withLock { state in
            state.requestCount += 1

            return state.requestStarted
        }

        requestStarted?.signal()

    }

    override func stopLoading() {
        let requestStopped = Self.state.withLock { state in
            state.stopCount += 1

            return state.requestStopped
        }

        requestStopped?.signal()
    }
}

private final class TestSignal: Sendable {

    private struct State {
        var isSignalled = false
        var continuation: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(
        State()
    )

    func signal() {
        let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
            if let continuation = state.continuation {
                state.continuation = nil

                return continuation
            }

            state.isSignalled = true

            return nil
        }

        continuation?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = state.withLock { state in
                if state.isSignalled {
                    state.isSignalled = false

                    return true
                }

                state.continuation = continuation

                return false
            }

            if shouldResumeImmediately {
                continuation.resume()
            }
        }
    }
}
