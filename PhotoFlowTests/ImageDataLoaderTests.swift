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
            didLoad: responseData
        )

        client?.urlProtocolDidFinishLoading(
            self
        )
    }

    override func stopLoading() {}
}
