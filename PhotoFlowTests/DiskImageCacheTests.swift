import Foundation
import Testing

@testable import PhotoFlow

struct DiskImageCacheTests {

    @Test
    func missingFileReturnsNil() async throws {
        let fileManager = FileManager.default

        let directoryURL = makeTemporaryDirectory(
            fileManager: fileManager
        )

        defer {
            try? fileManager.removeItem(
                at: directoryURL
            )
        }

        let cache = try DiskImageCache(
            fileManager: fileManager,
            directoryURL: directoryURL
        )

        guard let url = URL(
            string: "https://example.com/missing-image.jpg"
        ) else {
            Issue.record("Expected valid URL")
            return
        }

        let data = await readData(
            from: cache,
            for: url
        )

        #expect(data == nil)
    }

    @Test
    func insertedDataCanBeReadFromDisk() async throws {
        let fileManager = FileManager.default

        let directoryURL = makeTemporaryDirectory(
            fileManager: fileManager
        )

        defer {
            try? fileManager.removeItem(
                at: directoryURL
            )
        }

        let cache = try DiskImageCache(
            fileManager: fileManager,
            directoryURL: directoryURL
        )

        guard let url = URL(
            string: "https://example.com/image.jpg"
        ) else {
            Issue.record("Expected valid URL")
            return
        }

        let expectedData = Data(
            [1, 2, 3, 4]
        )

        cache.insert(
            expectedData,
            for: url
        )

        let receivedData = await readData(
            from: cache,
            for: url
        )

        #expect(receivedData == expectedData)
    }

    @Test
    func insertingNewDataForSameURLReplacesOldData() async throws {
        let fileManager = FileManager.default

        let directoryURL = makeTemporaryDirectory(
            fileManager: fileManager
        )

        defer {
            try? fileManager.removeItem(
                at: directoryURL
            )
        }

        let cache = try DiskImageCache(
            fileManager: fileManager,
            directoryURL: directoryURL
        )

        guard let url = URL(
            string: "https://example.com/image.jpg"
        ) else {
            Issue.record("Expected valid URL")
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

        let receivedData = await readData(
            from: cache,
            for: url
        )

        #expect(receivedData == newData)
    }

    private func readData(
        from cache: DiskImageCache,
        for url: URL
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            cache.data(
                for: url
            ) { data in
                continuation.resume(
                    returning: data
                )
            }
        }
    }

    private func makeTemporaryDirectory(
        fileManager: FileManager
    ) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
    }
}
