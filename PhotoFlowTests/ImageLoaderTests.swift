import Foundation
import Synchronization
import Testing

@testable import PhotoFlow

@Suite(.serialized)
struct ImageLoaderTests {

    @Test
    func cacheHitDoesNotStartNetworkRequest() {
        let cache = ImageDataMemoryCache()

        guard let url = URL(
            string: "https://example.com/cached-image.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        guard let imageData = makeValidImageData() else {
            Issue.record("Expected valid image data")
            return
        }

        cache.insert(
            imageData,
            for: url
        )

        URLProtocolStub.prepare(
            responseData: imageData
        )

        let session = makeStubbedSession()

        let imageLoader = ImageLoader(
            session: session,
            memoryCache: cache
        )

        let completionResult = Mutex<Bool?>(nil)

        let completionSemaphore = DispatchSemaphore(
            value: 0
        )

        let request = imageLoader.loadImage(
            from: url
        ) { result in
            completionResult.withLock { value in
                switch result {
                case .success:
                    value = true

                case .failure:
                    value = false
                }
            }

            completionSemaphore.signal()
        }

        withExtendedLifetime(request) {
            let waitResult = completionSemaphore.wait(
                timeout: .now() + 1
            )

            #expect(waitResult == .success)
        }

        let didSucceed = completionResult.withLock { value in
            value
        }

        #expect(didSucceed == true)
        #expect(URLProtocolStub.requestCount == 0)
    }

    @Test
    func cacheMissLoadsFromNetworkAndCachesData() {
        let cache = ImageDataMemoryCache()

        guard let url = URL(
            string: "https://example.com/network-image.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        guard let imageData = makeValidImageData() else {
            Issue.record("Expected valid image data")
            return
        }

        URLProtocolStub.prepare(
            responseData: imageData
        )

        let session = makeStubbedSession()

        let imageLoader = ImageLoader(
            session: session,
            memoryCache: cache
        )

        #expect(
            cache.data(for: url) == nil
        )

        let firstCompletionResult = Mutex<Bool?>(nil)

        let firstCompletionSemaphore = DispatchSemaphore(
            value: 0
        )

        let firstRequest = imageLoader.loadImage(
            from: url
        ) { result in
            firstCompletionResult.withLock { value in
                switch result {
                case .success:
                    value = true

                case .failure:
                    value = false
                }
            }

            firstCompletionSemaphore.signal()
        }

        withExtendedLifetime(firstRequest) {
            let waitResult = firstCompletionSemaphore.wait(
                timeout: .now() + 1
            )

            #expect(waitResult == .success)
        }

        let firstDidSucceed = firstCompletionResult.withLock { value in
            value
        }

        #expect(firstDidSucceed == true)
        #expect(URLProtocolStub.requestCount == 1)

        let cachedData = cache.data(
            for: url
        )

        #expect(cachedData == imageData)

        let secondCompletionResult = Mutex<Bool?>(nil)

        let secondCompletionSemaphore = DispatchSemaphore(
            value: 0
        )

        let secondRequest = imageLoader.loadImage(
            from: url
        ) { result in
            secondCompletionResult.withLock { value in
                switch result {
                case .success:
                    value = true

                case .failure:
                    value = false
                }
            }

            secondCompletionSemaphore.signal()
        }

        withExtendedLifetime(secondRequest) {
            let waitResult = secondCompletionSemaphore.wait(
                timeout: .now() + 1
            )

            #expect(waitResult == .success)
        }

        let secondDidSucceed = secondCompletionResult.withLock { value in
            value
        }

        #expect(secondDidSucceed == true)

        #expect(
            URLProtocolStub.requestCount == 1
        )
    }

    private func makeStubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral

        configuration.protocolClasses = [
            URLProtocolStub.self
        ]

        return URLSession(
            configuration: configuration
        )
    }

    private func makeValidImageData() -> Data? {
        Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
    }
}

private final class URLProtocolStub: URLProtocol {

    private struct State {
        var requestCount = 0
        var responseData = Data()
    }

    private static let state = Mutex(
        State()
    )

    static var requestCount: Int {
        state.withLock { state in
            state.requestCount
        }
    }

    static func prepare(
        responseData: Data
    ) {
        state.withLock { state in
            state.requestCount = 0
            state.responseData = responseData
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
        let responseData = Self.state.withLock { state in
            state.requestCount += 1

            return state.responseData
        }

        guard let url = request.url else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badURL)
            )

            return
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "image/png"
            ]
        ) else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )

            return
        }

        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )

        client?.urlProtocol(
            self,
            didLoad: responseData
        )

        client?.urlProtocolDidFinishLoading(
            self
        )
    }

    override func stopLoading() {}
}
