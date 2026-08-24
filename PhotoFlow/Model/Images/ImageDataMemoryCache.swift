import Foundation

final class ImageDataMemoryCache {

    private var storage: [URL: Data] = [:]

    private let synchronizationQueue = DispatchQueue(
        label: "com.alexeywestergaard.PhotoFlow.image-data-cache",
        qos: .utility,
        attributes: .concurrent
    )

    func data(for url: URL) -> Data? {
        synchronizationQueue.sync {
            storage[url]
        }
    }

    func insert(
        _ data: Data,
        for url: URL
    ) {
        synchronizationQueue.sync(
            flags: .barrier
        ) {
            storage[url] = data
        }
    }
}
