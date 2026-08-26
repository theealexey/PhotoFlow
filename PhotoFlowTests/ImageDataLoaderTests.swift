import Foundation
import Synchronization
import Testing

@testable import PhotoFlow

@Suite(.serialized)
struct ImageDataLoaderTests {

    @Test
    func memoryCacheHitReturnsDataWithoutStartingNetworkRequest() async {
        let memoryCache = ImageDataMemoryCache()

        guard let url = URL(
            string: "https://example.com/cached-image.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        let expectedData = Data(
            "cached-image-data".utf8
        )

        memoryCache.insert(
            expectedData,
            for: url
        )

        ImageDataURLProtocolStub.prepare(
            responseData: Data()
        )

        let session = makeStubbedSession()

        let dataLoader = ImageDataLoader(
            session: session,
            memoryCache: memoryCache
        )

        let result = await loadData(
            using: dataLoader,
            from: url
        )

        switch result {
        case .success(let data):
            #expect(
                data == expectedData
            )

        case .failure(let error):
            Issue.record(
                "Expected cached data, received \(error)"
            )
        }

        #expect(
            ImageDataURLProtocolStub.requestCount == 0
        )
    }

    @Test
    func diskCacheHitReturnsDataAndPromotesItToMemoryWithoutNetwork() async throws {
        let fileManager = FileManager.default

        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )

        defer {
            try? fileManager.removeItem(
                at: directoryURL
            )
        }

        let memoryCache = ImageDataMemoryCache()

        let diskCache = try DiskImageCache(
            fileManager: fileManager,
            directoryURL: directoryURL
        )

        guard let url = URL(
            string: "https://example.com/disk-data.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        let expectedData = Data(
            "disk-image-data".utf8
        )

        diskCache.insert(
            expectedData,
            for: url
        )

        #expect(
            memoryCache.data(for: url) == nil
        )

        ImageDataURLProtocolStub.prepare(
            responseData: Data()
        )

        let session = makeStubbedSession()

        let dataLoader = ImageDataLoader(
            session: session,
            memoryCache: memoryCache,
            diskCache: diskCache
        )

        let result = await loadData(
            using: dataLoader,
            from: url
        )

        switch result {
        case .success(let data):
            #expect(
                data == expectedData
            )

        case .failure(let error):
            Issue.record(
                "Expected disk cached data, received \(error)"
            )
        }

        #expect(
            ImageDataURLProtocolStub.requestCount == 0
        )

        #expect(
            memoryCache.data(for: url) == expectedData
        )
    }

    @Test
    func cacheMissLoadsFromNetworkAndStoresDataInMemoryAndDisk() async throws {
        let fileManager = FileManager.default

        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )

        defer {
            try? fileManager.removeItem(
                at: directoryURL
            )
        }

        let memoryCache = ImageDataMemoryCache()

        let diskCache = try DiskImageCache(
            fileManager: fileManager,
            directoryURL: directoryURL
        )

        guard let url = URL(
            string: "https://example.com/network-data.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        let expectedData = Data(
            "network-image-data".utf8
        )

        #expect(
            memoryCache.data(for: url) == nil
        )

        ImageDataURLProtocolStub.prepare(
            responseData: expectedData
        )

        let session = makeStubbedSession()

        let dataLoader = ImageDataLoader(
            session: session,
            memoryCache: memoryCache,
            diskCache: diskCache
        )

        let result = await loadData(
            using: dataLoader,
            from: url
        )

        switch result {
        case .success(let data):
            #expect(
                data == expectedData
            )

        case .failure(let error):
            Issue.record(
                "Expected network data, received \(error)"
            )
        }

        #expect(
            ImageDataURLProtocolStub.requestCount == 1
        )

        #expect(
            memoryCache.data(for: url) == expectedData
        )

        let diskData = await readDiskData(
            from: diskCache,
            for: url
        )

        #expect(
            diskData == expectedData
        )
    }

    @Test
    func removeDataDeletesDataFromMemoryAndDisk() async throws {
        let fileManager = FileManager.default

        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )

        defer {
            try? fileManager.removeItem(
                at: directoryURL
            )
        }

        let memoryCache = ImageDataMemoryCache()

        let diskCache = try DiskImageCache(
            fileManager: fileManager,
            directoryURL: directoryURL
        )

        guard let url = URL(
            string: "https://example.com/image-to-remove.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        let imageData = Data(
            "cached-image-data".utf8
        )

        memoryCache.insert(
            imageData,
            for: url
        )

        diskCache.insert(
            imageData,
            for: url
        )

        #expect(
            memoryCache.data(for: url) == imageData
        )

        let initialDiskData = await readDiskData(
            from: diskCache,
            for: url
        )

        #expect(
            initialDiskData == imageData
        )

        let dataLoader = ImageDataLoader(
            memoryCache: memoryCache,
            diskCache: diskCache
        )

        dataLoader.removeData(
            for: url
        )

        #expect(
            memoryCache.data(for: url) == nil
        )

        let removedDiskData = await readDiskData(
            from: diskCache,
            for: url
        )

        #expect(
            removedDiskData == nil
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func explicitCancellationCancelsNetworkRequest() async {
        guard let url = URL(
            string: "https://example.com/explicit-cancellation.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        let requestStarted = ImageDataLoaderTestSignal()
        let requestStopped = ImageDataLoaderTestSignal()
        let completionCount = Mutex(0)

        ImageDataURLProtocolStub.prepareSuspended(
            requestStarted: requestStarted,
            requestStopped: requestStopped
        )

        let dataLoader = ImageDataLoader(
            session: makeStubbedSession()
        )

        let request = dataLoader.loadData(
            from: url
        ) { _ in
            completionCount.withLock { count in
                count += 1
            }
        }

        await requestStarted.wait()

        #expect(
            ImageDataURLProtocolStub.requestCount == 1
        )

        request.cancel()

        await requestStopped.wait()

        #expect(
            ImageDataURLProtocolStub.stopCount == 1
        )

        #expect(
            completionCount.withLock { count in
                count
            } == 0
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func releasingRequestCancelsNetworkRequest() async {
        guard let url = URL(
            string: "https://example.com/release-cancellation.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        let requestStarted = ImageDataLoaderTestSignal()
        let requestStopped = ImageDataLoaderTestSignal()
        let completionCount = Mutex(0)

        ImageDataURLProtocolStub.prepareSuspended(
            requestStarted: requestStarted,
            requestStopped: requestStopped
        )

        let dataLoader = ImageDataLoader(
            session: makeStubbedSession()
        )

        var request: ImageDataLoadRequest? = dataLoader.loadData(
            from: url
        ) { _ in
            completionCount.withLock { count in
                count += 1
            }
        }

        await requestStarted.wait()

        #expect(
            request != nil
        )

        request = nil

        await requestStopped.wait()

        #expect(
            ImageDataURLProtocolStub.requestCount == 1
        )

        #expect(
            ImageDataURLProtocolStub.stopCount == 1
        )

        #expect(
            completionCount.withLock { count in
                count
            } == 0
        )
    }
    
    private func loadData(
        using dataLoader: ImageDataLoader,
        from url: URL
    ) async -> Result<Data, ImageDataLoadError> {
        var request: ImageDataLoadRequest?

        let result = await withCheckedContinuation { continuation in
            request = dataLoader.loadData(
                from: url
            ) { result in
                continuation.resume(
                    returning: result
                )
            }
        }

        withExtendedLifetime(request) {}

        return result
    }

    private func readDiskData(
        from diskCache: DiskImageCache,
        for url: URL
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            diskCache.data(
                for: url
            ) { data in
                continuation.resume(
                    returning: data
                )
            }
        }
    }

    private func makeStubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral

        configuration.protocolClasses = [
            ImageDataURLProtocolStub.self
        ]

        return URLSession(
            configuration: configuration
        )
    }
}

private final class ImageDataURLProtocolStub: URLProtocol {

    private enum LoadingMode {
        case immediate
        case suspended
    }

    private struct State {
        var requestCount = 0
        var stopCount = 0
        var responseData = Data()
        var loadingMode = LoadingMode.immediate
        var requestStarted: ImageDataLoaderTestSignal?
        var requestStopped: ImageDataLoaderTestSignal?
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
        responseData: Data
    ) {
        state.withLock { state in
            state.requestCount = 0
            state.stopCount = 0
            state.responseData = responseData
            state.loadingMode = .immediate
            state.requestStarted = nil
            state.requestStopped = nil
        }
    }

    static func prepareSuspended(
        requestStarted: ImageDataLoaderTestSignal,
        requestStopped: ImageDataLoaderTestSignal
    ) {
        state.withLock { state in
            state.requestCount = 0
            state.stopCount = 0
            state.responseData = Data()
            state.loadingMode = .suspended
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
        let configuration = Self.state.withLock { state in
            state.requestCount += 1

            return (
                loadingMode: state.loadingMode,
                responseData: state.responseData,
                requestStarted: state.requestStarted
            )
        }

        configuration.requestStarted?.signal()

        guard configuration.loadingMode == .immediate else {
            return
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
            headerFields: nil
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
            didLoad: configuration.responseData
        )

        client?.urlProtocolDidFinishLoading(
            self
        )
    }

    override func stopLoading() {
        let requestStopped = Self.state.withLock { state in
            state.stopCount += 1

            return state.requestStopped
        }

        requestStopped?.signal()
    }
}

private final class ImageDataLoaderTestSignal: Sendable {

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
