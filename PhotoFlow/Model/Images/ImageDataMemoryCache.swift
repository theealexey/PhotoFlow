import Foundation
import Synchronization

final class ImageDataMemoryCache: Sendable {

    private let storage = Mutex<[URL: Data]>(
        [:]
    )

    func data(for url: URL) -> Data? {
        storage.withLock { storage in
            storage[url]
        }
    }

    func insert(
        _ data: Data,
        for url: URL
    ) {
        storage.withLock { storage in
            storage[url] = data
        }
    }
}
