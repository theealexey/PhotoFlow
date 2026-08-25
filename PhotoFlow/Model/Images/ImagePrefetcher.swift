import Foundation
import Synchronization

final class ImagePrefetcher: Sendable {

    private struct ActivePrefetch: Sendable {
        let id: UUID
        var request: ImageDataLoadRequest?
    }

    private let dataLoader: ImageDataLoader

    private let activePrefetches = Mutex<[URL: ActivePrefetch]>(
        [:]
    )

    init(
        dataLoader: ImageDataLoader
    ) {
        self.dataLoader = dataLoader
    }

    func prefetch(
        urls: [URL]
    ) {
        for url in urls {
            startPrefetch(
                for: url
            )
        }
    }

    func cancelPrefetching(
        urls: [URL]
    ) {
        let requests = activePrefetches.withLock { activePrefetches in
            urls.compactMap { url in
                activePrefetches
                    .removeValue(forKey: url)?
                    .request
            }
        }

        for request in requests {
            request.cancel()
        }
    }

    private func startPrefetch(
        for url: URL
    ) {
        let requestID = UUID()

        let shouldStart = activePrefetches.withLock { activePrefetches in
            guard activePrefetches[url] == nil else {
                return false
            }

            activePrefetches[url] = ActivePrefetch(
                id: requestID,
                request: nil
            )

            return true
        }

        guard shouldStart else {
            return
        }

        let request = dataLoader.loadData(
            from: url
        ) { [weak self] _ in
            guard let self else {
                return
            }

            activePrefetches.withLock { activePrefetches in
                guard activePrefetches[url]?.id == requestID else {
                    return
                }

                activePrefetches[url] = nil
            }
        }

        let shouldCancel = activePrefetches.withLock { activePrefetches in
            guard activePrefetches[url]?.id == requestID else {
                return true
            }

            activePrefetches[url]?.request = request

            return false
        }

        if shouldCancel {
            request.cancel()
        }
    }
}
