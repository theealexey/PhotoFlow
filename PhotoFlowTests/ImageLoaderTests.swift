import Foundation
import Synchronization
import Testing
import UIKit

@testable import PhotoFlow

@Suite(.serialized)
struct ImageLoaderTests {

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
            string: "https://example.com/network-disk-image.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        guard let imageData = makeValidImageData() else {
            Issue.record("Expected valid image data")
            return
        }

        #expect(
            memoryCache.data(for: url) == nil
        )

        let initialDiskData = await readDiskData(
            from: diskCache,
            for: url
        )

        #expect(
            initialDiskData == nil
        )

        URLProtocolStub.prepare(
            responseData: imageData
        )

        let session = makeStubbedSession()

        let imageLoader = makeImageLoader(
            session: session,
            memoryCache: memoryCache,
            diskCache: diskCache
        )

        let result = await loadImage(
            using: imageLoader,
            from: url
        )

        switch result {
        case .success:
            break

        case .failure(let error):
            Issue.record(
                "Expected successful image load, received \(error)"
            )
        }

        #expect(
            URLProtocolStub.requestCount == 1
        )

        #expect(
            memoryCache.data(for: url) == imageData
        )

        let storedDiskData = await readDiskData(
            from: diskCache,
            for: url
        )

        #expect(
            storedDiskData == imageData
        )
    }

    @Test
    func diskCacheHitDoesNotStartNetworkRequestAndPromotesDataToMemory() throws {
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
            string: "https://example.com/disk-image.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        guard let imageData = makeValidImageData() else {
            Issue.record("Expected valid image data")
            return
        }

        diskCache.insert(
            imageData,
            for: url
        )

        #expect(
            memoryCache.data(for: url) == nil
        )

        URLProtocolStub.prepare(
            responseData: imageData
        )

        let session = makeStubbedSession()

        let imageLoader = makeImageLoader(
            session: session,
            memoryCache: memoryCache,
            diskCache: diskCache
        )

        let completionResult = Mutex<Bool?>(
            nil
        )

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

            #expect(
                waitResult == .success
            )
        }

        let didSucceed = completionResult.withLock { value in
            value
        }

        #expect(
            didSucceed == true
        )

        #expect(
            URLProtocolStub.requestCount == 0
        )

        #expect(
            memoryCache.data(for: url) == imageData
        )
    }

    @Test
    func cacheHitDoesNotStartNetworkRequest() {
        let memoryCache = ImageDataMemoryCache()

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

        memoryCache.insert(
            imageData,
            for: url
        )

        URLProtocolStub.prepare(
            responseData: imageData
        )

        let session = makeStubbedSession()

        let imageLoader = makeImageLoader(
            session: session,
            memoryCache: memoryCache
        )

        let completionResult = Mutex<Bool?>(
            nil
        )

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

            #expect(
                waitResult == .success
            )
        }

        let didSucceed = completionResult.withLock { value in
            value
        }

        #expect(
            didSucceed == true
        )

        #expect(
            URLProtocolStub.requestCount == 0
        )
    }

    @Test
    func cacheMissLoadsFromNetworkAndCachesData() {
        let memoryCache = ImageDataMemoryCache()

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

        let imageLoader = makeImageLoader(
            session: session,
            memoryCache: memoryCache
        )

        #expect(
            memoryCache.data(for: url) == nil
        )

        let firstCompletionResult = Mutex<Bool?>(
            nil
        )

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

            #expect(
                waitResult == .success
            )
        }

        let firstDidSucceed = firstCompletionResult.withLock { value in
            value
        }

        #expect(
            firstDidSucceed == true
        )

        #expect(
            URLProtocolStub.requestCount == 1
        )

        let cachedData = memoryCache.data(
            for: url
        )

        #expect(
            cachedData == imageData
        )

        let secondCompletionResult = Mutex<Bool?>(
            nil
        )

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

            #expect(
                waitResult == .success
            )
        }

        let secondDidSucceed = secondCompletionResult.withLock { value in
            value
        }

        #expect(
            secondDidSucceed == true
        )

        #expect(
            URLProtocolStub.requestCount == 1
        )
    }
    
    @Test
    func invalidDiskCachedDataIsEvictedAndNextLoadUsesNetwork() async throws {
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
            string: "https://example.com/poisoned-image.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        let invalidImageData = Data(
            "not-an-image".utf8
        )

        guard let validImageData = makeValidImageData() else {
            Issue.record("Expected valid image data")
            return
        }

        diskCache.insert(
            invalidImageData,
            for: url
        )

        URLProtocolStub.prepare(
            responseData: validImageData
        )

        let session = makeStubbedSession()

        let imageLoader = makeImageLoader(
            session: session,
            memoryCache: memoryCache,
            diskCache: diskCache
        )

        let firstResult = await loadImage(
            using: imageLoader,
            from: url
        )

        switch firstResult {
        case .success:
            Issue.record(
                "Expected imageCreationFailed for invalid cached data"
            )

        case .failure(let error):
            #expect(
                error == .imageCreationFailed
            )
        }

        #expect(
            URLProtocolStub.requestCount == 0
        )

        #expect(
            memoryCache.data(for: url) == nil
        )

        let secondResult = await loadImage(
            using: imageLoader,
            from: url
        )

        switch secondResult {
        case .success:
            break

        case .failure(let error):
            Issue.record(
                "Expected successful recovery load, received \(error)"
            )
        }

        #expect(
            URLProtocolStub.requestCount == 1
        )

        #expect(
            memoryCache.data(for: url) == validImageData
        )

        let diskData = await readDiskData(
            from: diskCache,
            for: url
        )

        #expect(
            diskData == validImageData
        )
    }
    
    private func makeImageLoader(
        session: URLSession,
        memoryCache: ImageDataMemoryCache,
        diskCache: DiskImageCache? = nil
    ) -> ImageLoader {
        let dataLoader = ImageDataLoader(
            session: session,
            memoryCache: memoryCache,
            diskCache: diskCache
        )

        return ImageLoader(
            dataLoader: dataLoader
        )
    }

    private func loadImage(
        using imageLoader: ImageLoader,
        from url: URL
    ) async -> Result<UIImage, ImageLoadError> {
        var request: ImageLoadRequest?

        let result = await withCheckedContinuation { continuation in
            request = imageLoader.loadImage(
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

