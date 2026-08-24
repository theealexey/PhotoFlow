import Foundation
import Synchronization
import UIKit

protocol ImageLoading {

    @discardableResult
    func loadImage(
        from url: URL,
        completion: @escaping @Sendable (
            Result<UIImage, ImageLoadError>
        ) -> Void
    ) -> ImageLoadRequest
}

enum ImageLoadError: Error, Equatable, Sendable {
    case invalidResponse
    case missingData
    case imageCreationFailed
    case network
}

final class ImageLoadRequest {

    private let state: ImageLoadRequestState

    init(
        state: ImageLoadRequestState
    ) {
        self.state = state
    }

    func cancel() {
        state.cancel()
    }

    deinit {
        cancel()
    }
}

final class ImageLoader: ImageLoading {

    private let session: URLSession
    private let memoryCache: ImageDataMemoryCache
    private let diskCache: DiskImageCache?
    private let imageProcessingQueue: DispatchQueue

    init(
        session: URLSession = .shared,
        memoryCache: ImageDataMemoryCache = ImageDataMemoryCache(),
        diskCache: DiskImageCache? = nil
    ) {
        self.session = session
        self.memoryCache = memoryCache
        self.diskCache = diskCache

        imageProcessingQueue = DispatchQueue(
            label: "com.alexeywestergaard.PhotoFlow.image-processing",
            qos: .userInitiated,
            attributes: .concurrent
        )
    }

    @discardableResult
    func loadImage(
        from url: URL,
        completion: @escaping @Sendable (
            Result<UIImage, ImageLoadError>
        ) -> Void
    ) -> ImageLoadRequest {
        let requestState = ImageLoadRequestState()

        let request = ImageLoadRequest(
            state: requestState
        )

        if let cachedData = memoryCache.data(
            for: url
        ) {
            Self.processImageData(
                cachedData,
                from: .memoryCache,
                for: url,
                memoryCache: memoryCache,
                diskCache: diskCache,
                imageProcessingQueue: imageProcessingQueue,
                requestState: requestState,
                completion: completion
            )

            return request
        }

        guard let diskCache else {
            Self.startNetworkLoad(
                from: url,
                session: session,
                memoryCache: memoryCache,
                diskCache: nil,
                imageProcessingQueue: imageProcessingQueue,
                requestState: requestState,
                completion: completion
            )

            return request
        }

        diskCache.data(
            for: url
        ) { [session, memoryCache, imageProcessingQueue] data in
            guard !requestState.isCancelled else {
                return
            }

            if let data {
                Self.processImageData(
                    data,
                    from: .diskCache,
                    for: url,
                    memoryCache: memoryCache,
                    diskCache: diskCache,
                    imageProcessingQueue: imageProcessingQueue,
                    requestState: requestState,
                    completion: completion
                )

                return
            }

            Self.startNetworkLoad(
                from: url,
                session: session,
                memoryCache: memoryCache,
                diskCache: diskCache,
                imageProcessingQueue: imageProcessingQueue,
                requestState: requestState,
                completion: completion
            )
        }

        return request
    }

    private static func startNetworkLoad(
        from url: URL,
        session: URLSession,
        memoryCache: ImageDataMemoryCache,
        diskCache: DiskImageCache?,
        imageProcessingQueue: DispatchQueue,
        requestState: ImageLoadRequestState,
        completion: @escaping @Sendable (
            Result<UIImage, ImageLoadError>
        ) -> Void
    ) {
        guard !requestState.isCancelled else {
            return
        }

        let networkTask = session.dataTask(
            with: url
        ) { data, response, error in
            guard !requestState.isCancelled else {
                return
            }

            if let urlError = error as? URLError {
                guard urlError.code != .cancelled else {
                    return
                }

                completion(
                    .failure(.network)
                )

                return
            }

            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                completion(
                    .failure(.invalidResponse)
                )

                return
            }

            guard let data else {
                completion(
                    .failure(.missingData)
                )

                return
            }

            processImageData(
                data,
                from: .network,
                for: url,
                memoryCache: memoryCache,
                diskCache: diskCache,
                imageProcessingQueue: imageProcessingQueue,
                requestState: requestState,
                completion: completion
            )
        }

        requestState.register(
            networkTask: networkTask
        )

        networkTask.resume()
    }

    private static func processImageData(
        _ data: Data,
        from source: ImageDataSource,
        for url: URL,
        memoryCache: ImageDataMemoryCache,
        diskCache: DiskImageCache?,
        imageProcessingQueue: DispatchQueue,
        requestState: ImageLoadRequestState,
        completion: @escaping @Sendable (
            Result<UIImage, ImageLoadError>
        ) -> Void
    ) {
        let workItem = DispatchWorkItem {
            guard !requestState.isCancelled else {
                return
            }

            guard let image = UIImage(
                data: data
            ) else {
                completion(
                    .failure(.imageCreationFailed)
                )

                return
            }

            guard !requestState.isCancelled else {
                return
            }

            switch source {
            case .memoryCache:
                break

            case .diskCache:
                memoryCache.insert(
                    data,
                    for: url
                )

            case .network:
                memoryCache.insert(
                    data,
                    for: url
                )

                diskCache?.insert(
                    data,
                    for: url
                )
            }

            completion(
                .success(image)
            )
        }

        imageProcessingQueue.async(
            execute: workItem
        )
    }
}

private enum ImageDataSource {
    case memoryCache
    case diskCache
    case network
}

final class ImageLoadRequestState: Sendable {

    private struct State {
        var isCancelled = false
        var networkTask: URLSessionDataTask?
    }

    private let state = Mutex(
        State()
    )

    func register(
        networkTask: URLSessionDataTask
    ) {
        let shouldCancel = state.withLock { state in
            if state.isCancelled {
                return true
            }

            state.networkTask = networkTask

            return false
        }

        if shouldCancel {
            networkTask.cancel()
        }
    }

    func cancel() {
        let networkTask = state.withLock { state in
            state.isCancelled = true

            let networkTask = state.networkTask

            state.networkTask = nil

            return networkTask
        }

        networkTask?.cancel()
    }

    var isCancelled: Bool {
        state.withLock { state in
            state.isCancelled
        }
    }
}
