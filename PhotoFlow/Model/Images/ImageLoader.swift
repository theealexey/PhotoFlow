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

    private let networkTask: URLSessionDataTask?
    private let cancellationState: ImageLoadCancellationState

    init(
        networkTask: URLSessionDataTask?,
        cancellationState: ImageLoadCancellationState
    ) {
        self.networkTask = networkTask
        self.cancellationState = cancellationState
    }

    func cancel() {
        cancellationState.cancel()
        networkTask?.cancel()
    }

    deinit {
        cancel()
    }
}

final class ImageLoader: ImageLoading {

    private let session: URLSession
    private let memoryCache: ImageDataMemoryCache
    private let imageProcessingQueue: DispatchQueue

    init(
        session: URLSession = .shared,
        memoryCache: ImageDataMemoryCache = ImageDataMemoryCache()
    ) {
        self.session = session
        self.memoryCache = memoryCache

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
        let cancellationState = ImageLoadCancellationState()

        if let cachedData = memoryCache.data(for: url) {
            let request = ImageLoadRequest(
                networkTask: nil,
                cancellationState: cancellationState
            )

            let workItem = Self.makeImageProcessingWorkItem(
                data: cachedData,
                url: url,
                shouldCache: false,
                memoryCache: memoryCache,
                cancellationState: cancellationState,
                completion: completion
            )

            imageProcessingQueue.async(
                execute: workItem
            )

            return request
        }

        let networkTask = session.dataTask(
            with: url
        ) { [memoryCache, imageProcessingQueue] data, response, error in
            guard !cancellationState.isCancelled else {
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

            let workItem = Self.makeImageProcessingWorkItem(
                data: data,
                url: url,
                shouldCache: true,
                memoryCache: memoryCache,
                cancellationState: cancellationState,
                completion: completion
            )

            imageProcessingQueue.async(
                execute: workItem
            )
        }

        let request = ImageLoadRequest(
            networkTask: networkTask,
            cancellationState: cancellationState
        )

        networkTask.resume()

        return request
    }

    private static func makeImageProcessingWorkItem(
        data: Data,
        url: URL,
        shouldCache: Bool,
        memoryCache: ImageDataMemoryCache,
        cancellationState: ImageLoadCancellationState,
        completion: @escaping @Sendable (
            Result<UIImage, ImageLoadError>
        ) -> Void
    ) -> DispatchWorkItem {
        DispatchWorkItem {
            guard !cancellationState.isCancelled else {
                return
            }

            guard let image = UIImage(data: data) else {
                completion(
                    .failure(.imageCreationFailed)
                )

                return
            }

            guard !cancellationState.isCancelled else {
                return
            }

            if shouldCache {
                memoryCache.insert(
                    data,
                    for: url
                )
            }

            completion(
                .success(image)
            )
        }
    }
}

final class ImageLoadCancellationState: Sendable {

    private let cancelled = Mutex(false)

    func cancel() {
        cancelled.withLock { isCancelled in
            isCancelled = true
        }
    }

    var isCancelled: Bool {
        cancelled.withLock { isCancelled in
            isCancelled
        }
    }
}
