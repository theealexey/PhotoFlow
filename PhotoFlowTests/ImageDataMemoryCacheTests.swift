import Foundation
import Testing

@testable import PhotoFlow

struct ImageDataMemoryCacheTests {

    @Test
    func emptyCacheReturnsNil() {
        let cache = ImageDataMemoryCache()

        let url = URL(
            string: "https://example.com/image.jpg"
        )

        #expect(url != nil)

        guard let url else {
            return
        }

        let data = cache.data(
            for: url
        )

        #expect(data == nil)
    }

    @Test
    func insertedDataCanBeRead() {
        let cache = ImageDataMemoryCache()

        let url = URL(
            string: "https://example.com/image.jpg"
        )

        #expect(url != nil)

        guard let url else {
            return
        }

        let expectedData = Data(
            [1, 2, 3]
        )

        cache.insert(
            expectedData,
            for: url
        )

        let receivedData = cache.data(
            for: url
        )

        #expect(receivedData == expectedData)
    }

    @Test
    func insertingNewDataForSameURLReplacesOldData() {
        let cache = ImageDataMemoryCache()

        let url = URL(
            string: "https://example.com/image.jpg"
        )

        #expect(url != nil)

        guard let url else {
            return
        }

        let oldData = Data(
            [1, 2, 3]
        )

        let newData = Data(
            [4, 5, 6]
        )

        cache.insert(
            oldData,
            for: url
        )

        cache.insert(
            newData,
            for: url
        )

        let receivedData = cache.data(
            for: url
        )

        #expect(receivedData == newData)
    }

    @Test
    func differentURLsKeepDifferentData() {
        let cache = ImageDataMemoryCache()

        let firstURL = URL(
            string: "https://example.com/first.jpg"
        )

        let secondURL = URL(
            string: "https://example.com/second.jpg"
        )

        #expect(firstURL != nil)
        #expect(secondURL != nil)

        guard
            let firstURL,
            let secondURL
        else {
            return
        }

        let firstData = Data(
            [1, 2, 3]
        )

        let secondData = Data(
            [4, 5, 6]
        )

        cache.insert(
            firstData,
            for: firstURL
        )

        cache.insert(
            secondData,
            for: secondURL
        )

        #expect(
            cache.data(for: firstURL) == firstData
        )

        #expect(
            cache.data(for: secondURL) == secondData
        )
    }
}
