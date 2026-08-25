import Foundation
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
