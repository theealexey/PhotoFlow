import Foundation
import Synchronization
import UIKit

protocol ImageLoading {

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

final class ImageLoadRequest: Sendable {

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

final class ImageLoader {

    private let dataLoader: ImageDataLoader
    private let imageProcessingQueue: DispatchQueue

    init(
        dataLoader: ImageDataLoader
    ) {
        self.dataLoader = dataLoader

        imageProcessingQueue = DispatchQueue(
            label: "com.alexeywestergaard.PhotoFlow.image-processing",
            qos: .userInitiated,
            attributes: .concurrent
        )
    }
}

extension ImageLoader: ImageLoading {

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

        let dataRequest = dataLoader.loadData(
            from: url
        ) { [dataLoader, imageProcessingQueue] result in
            guard !requestState.isCancelled else {
                return
            }

            switch result {
            case .success(let data):
                Self.processImageData(
                    data,
                    for: url,
                    dataLoader: dataLoader,
                    imageProcessingQueue: imageProcessingQueue,
                    requestState: requestState,
                    completion: completion
                )

            case .failure(let error):
                let imageLoadError = Self.mapError(
                    error
                )

                guard !requestState.isCancelled else {
                    return
                }

                completion(
                    .failure(imageLoadError)
                )
            }
        }
        
        requestState.register(
            dataRequest: dataRequest
        )

        return request
    }

    private static func processImageData(
        _ data: Data,
        for url: URL,
        dataLoader: ImageDataLoader,
        imageProcessingQueue: DispatchQueue,
        requestState: ImageLoadRequestState,
        completion: @escaping @Sendable (
            Result<UIImage, ImageLoadError>
        ) -> Void
    ) {
        imageProcessingQueue.async {
            guard !requestState.isCancelled else {
                return
            }

            guard let image = UIImage(
                data: data
            ) else {
                dataLoader.removeData(
                    for: url
                )

                guard !requestState.isCancelled else {
                    return
                }

                completion(
                    .failure(.imageCreationFailed)
                )

                return
            }

            guard !requestState.isCancelled else {
                return
            }

            completion(
                .success(image)
            )
        }
    }

    private static func mapError(
        _ error: ImageDataLoadError
    ) -> ImageLoadError {
        switch error {
        case .invalidResponse:
            return .invalidResponse

        case .missingData:
            return .missingData

        case .network:
            return .network
        }
    }
}

final class ImageLoadRequestState: Sendable {

    private struct State {
        var isCancelled = false
        var dataRequest: ImageDataLoadRequest?
    }

    private let state = Mutex(
        State()
    )

    func register(
        dataRequest: ImageDataLoadRequest
    ) {
        let shouldCancel = state.withLock { state in
            if state.isCancelled {
                return true
            }

            state.dataRequest = dataRequest

            return false
        }

        if shouldCancel {
            dataRequest.cancel()
        }
    }

    func cancel() {
        let dataRequest = state.withLock { state in
            state.isCancelled = true

            let dataRequest = state.dataRequest
            state.dataRequest = nil

            return dataRequest
        }

        dataRequest?.cancel()
    }

    var isCancelled: Bool {
        state.withLock { state in
            state.isCancelled
        }
    }
}
