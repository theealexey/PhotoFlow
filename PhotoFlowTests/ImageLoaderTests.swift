import Foundation
import Synchronization
import Testing
import UIKit

@testable import PhotoFlow

struct ImageLoaderTests {

    @Test
    func validCachedDataIsDecodedIntoImage() async {
        let memoryCache = ImageDataMemoryCache()

        guard let url = URL(
            string: "https://example.com/valid-image.png"
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

        let dataLoader = ImageDataLoader(
            memoryCache: memoryCache
        )

        let imageLoader = ImageLoader(
            dataLoader: dataLoader
        )

        let result = await loadImage(
            using: imageLoader,
            from: url
        )

        switch result {
        case .success(let image):
            #expect(
                image.size.width > 0
            )

            #expect(
                image.size.height > 0
            )

        case .failure(let error):
            Issue.record(
                "Expected successfully decoded image, received \(error)"
            )
        }
    }

    @Test
    func invalidCachedDataReturnsImageCreationFailedAndEvictsData() async {
        let memoryCache = ImageDataMemoryCache()

        guard let url = URL(
            string: "https://example.com/invalid-image.png"
        ) else {
            Issue.record("Expected valid test URL")
            return
        }

        let invalidImageData = Data(
            "not-an-image".utf8
        )

        memoryCache.insert(
            invalidImageData,
            for: url
        )

        let dataLoader = ImageDataLoader(
            memoryCache: memoryCache
        )

        let imageLoader = ImageLoader(
            dataLoader: dataLoader
        )

        let result = await loadImage(
            using: imageLoader,
            from: url
        )

        switch result {
        case .success:
            Issue.record(
                "Expected image creation to fail"
            )

        case .failure(let error):
            #expect(
                error == .imageCreationFailed
            )
        }

        #expect(
            memoryCache.data(for: url) == nil
        )
    }

    @Test
    func cancellingBeforeQueuedDecodeSuppressesCompletion() async {
        let memoryCache = ImageDataMemoryCache()

        guard let url = URL(
            string: "https://example.com/cancelled-image.png"
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

        let dataLoader = ImageDataLoader(
            memoryCache: memoryCache
        )
        let imageProcessingQueue = DispatchQueue(
            label: "com.alexeywestergaard.PhotoFlowTests.image-loader"
        )
        let imageLoader = ImageLoader(
            dataLoader: dataLoader,
            imageProcessingQueue: imageProcessingQueue
        )
        let completionCount = Mutex(0)
        let markerReached = ImageLoaderTestSignal()

        imageProcessingQueue.suspend()

        let request = imageLoader.loadImage(
            from: url
        ) { _ in
            completionCount.withLock { count in
                count += 1
            }
        }

        request.cancel()

        imageProcessingQueue.async {
            markerReached.signal()
        }

        imageProcessingQueue.resume()

        await markerReached.wait()

        #expect(
            completionCount.withLock { count in
                count
            } == 0
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

    private func makeValidImageData() -> Data? {
        Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
    }
}

private final class ImageLoaderTestSignal: Sendable {

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
