import CoreImage
import Foundation
import Synchronization
import UIKit

enum ImageProcessingError: Error, Equatable, Sendable {
    case resizeFailed
    case filterFailed
}

final class ImageProcessingRequest: Sendable {

    private let cancellationState: ImageProcessingCancellationState
    private let operations: [Operation]

    init(
        cancellationState: ImageProcessingCancellationState,
        operations: [Operation]
    ) {
        self.cancellationState = cancellationState
        self.operations = operations
    }

    func cancel() {
        cancellationState.cancel()

        for operation in operations {
            operation.cancel()
        }
    }

    deinit {
        cancel()
    }
}

final class PhotoImageProcessor: Sendable {

    private let operationQueue: OperationQueue

    init() {
        operationQueue = OperationQueue()
        operationQueue.name = "com.alexeywestergaard.PhotoFlow.image-processing-operations"
        operationQueue.qualityOfService = .userInitiated
        operationQueue.maxConcurrentOperationCount = 2
    }

    @discardableResult
    func process(
        image: UIImage,
        completion: @escaping @Sendable (
            Result<UIImage, ImageProcessingError>
        ) -> Void
    ) -> ImageProcessingRequest {
        let cancellationState = ImageProcessingCancellationState()

        let sourceImage = Mutex<UIImage?>(
            image
        )

        let resizedImage = Mutex<UIImage?>(
            nil
        )

        let processedImage = Mutex<UIImage?>(
            nil
        )

        let processingError = Mutex<ImageProcessingError?>(
            nil
        )

        let resizeOperation = BlockOperation {
            guard !cancellationState.isCancelled else {
                return
            }

            guard let image = sourceImage.withLock({ image in
                image
            }) else {
                processingError.withLock { error in
                    error = .resizeFailed
                }

                return
            }

            guard let resized = Self.resize(
                image: image,
                maximumDimension: 1_200
            ) else {
                processingError.withLock { error in
                    error = .resizeFailed
                }

                return
            }

            guard !cancellationState.isCancelled else {
                return
            }

            resizedImage.withLock { image in
                image = resized
            }
        }

        resizeOperation.name = "Resize Image"

        let monochromeOperation = BlockOperation {
            guard !cancellationState.isCancelled else {
                return
            }

            guard let image = resizedImage.withLock({ image in
                image
            }) else {
                return
            }

            guard let monochromeImage = Self.makeMonochrome(
                image: image
            ) else {
                processingError.withLock { error in
                    error = .filterFailed
                }

                return
            }

            guard !cancellationState.isCancelled else {
                return
            }

            processedImage.withLock { image in
                image = monochromeImage
            }
        }

        monochromeOperation.name = "Monochrome Image"

        monochromeOperation.addDependency(
            resizeOperation
        )

        let completionOperation = BlockOperation {
            guard !cancellationState.isCancelled else {
                return
            }

            if let error = processingError.withLock({ error in
                error
            }) {
                completion(
                    .failure(error)
                )

                return
            }

            guard let image = processedImage.withLock({ image in
                image
            }) else {
                completion(
                    .failure(.filterFailed)
                )

                return
            }

            completion(
                .success(image)
            )
        }

        completionOperation.name = "Publish Processed Image"

        completionOperation.addDependency(
            monochromeOperation
        )

        operationQueue.addOperations(
            [
                resizeOperation,
                monochromeOperation,
                completionOperation
            ],
            waitUntilFinished: false
        )

        return ImageProcessingRequest(
            cancellationState: cancellationState,
            operations: [
                resizeOperation,
                monochromeOperation,
                completionOperation
            ]
        )
    }

    private static func resize(
        image: UIImage,
        maximumDimension: CGFloat
    ) -> UIImage? {
        guard let inputImage = CIImage(
            image: image
        ) else {
            return nil
        }

        let originalWidth = inputImage.extent.width
        let originalHeight = inputImage.extent.height

        let longestDimension = max(
            originalWidth,
            originalHeight
        )

        guard longestDimension > 0 else {
            return nil
        }

        let scale = min(
            1,
            maximumDimension / longestDimension
        )

        let filter = CIFilter(
            name: "CILanczosScaleTransform"
        )

        filter?.setValue(
            inputImage,
            forKey: kCIInputImageKey
        )

        filter?.setValue(
            scale,
            forKey: kCIInputScaleKey
        )

        filter?.setValue(
            1,
            forKey: kCIInputAspectRatioKey
        )

        guard let outputImage = filter?.outputImage else {
            return nil
        }

        return makeUIImage(
            from: outputImage
        )
    }

    private static func makeMonochrome(
        image: UIImage
    ) -> UIImage? {
        guard let inputImage = CIImage(
            image: image
        ) else {
            return nil
        }

        let filter = CIFilter(
            name: "CIPhotoEffectMono"
        )

        filter?.setValue(
            inputImage,
            forKey: kCIInputImageKey
        )

        guard let outputImage = filter?.outputImage else {
            return nil
        }

        return makeUIImage(
            from: outputImage
        )
    }

    private static func makeUIImage(
        from image: CIImage
    ) -> UIImage? {
        let context = CIContext()

        guard let cgImage = context.createCGImage(
            image,
            from: image.extent
        ) else {
            return nil
        }

        return UIImage(
            cgImage: cgImage
        )
    }
}

final class ImageProcessingCancellationState: Sendable {

    private let cancelled = Mutex(
        false
    )

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
