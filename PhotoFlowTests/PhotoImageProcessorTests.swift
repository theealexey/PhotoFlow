import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import PhotoFlow

struct PhotoImageProcessorTests {

    @Test
    func processingResizesImageAndAppliesMonochromeFilter() async {
        guard let sourceImage = makeSolidRedImage(
            width: 1_600,
            height: 800
        ) else {
            Issue.record(
                "Expected test image"
            )

            return
        }

        let processor = PhotoImageProcessor()

        let output = await process(
            image: sourceImage,
            using: processor
        )

        switch output.result {
        case .success(let image):
            #expect(
                image.size.width <= 1_200
            )

            #expect(
                image.size.height <= 1_200
            )

            guard let pixel = firstPixel(
                from: image
            ) else {
                Issue.record(
                    "Expected readable output pixel"
                )

                return
            }

            let redGreenDifference = abs(
                Int(pixel.red) - Int(pixel.green)
            )

            let greenBlueDifference = abs(
                Int(pixel.green) - Int(pixel.blue)
            )

            #expect(
                redGreenDifference <= 1
            )

            #expect(
                greenBlueDifference <= 1
            )

        case .failure(let error):
            Issue.record(
                "Expected successful processing, received \(error)"
            )
        }
    }

    private func process(
        image: UIImage,
        using processor: PhotoImageProcessor
    ) async -> ProcessingOutput {
        var request: ImageProcessingRequest?

        let output = await withCheckedContinuation { continuation in
            request = processor.process(
                image: image
            ) { result in
                let output = ProcessingOutput(
                    result: result,
                    wasDeliveredOnMainThread: Thread.isMainThread
                )

                continuation.resume(
                    returning: output
                )
            }
        }

        withExtendedLifetime(request) {}

        return output
    }

    private func makeSolidRedImage(
        width: Int,
        height: Int
    ) -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let bytesPerRow = width * 4

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(
            red: 1,
            green: 0,
            blue: 0,
            alpha: 1
        )

        context.fill(
            CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        )

        guard let cgImage = context.makeImage() else {
            return nil
        }

        return UIImage(
            cgImage: cgImage
        )
    }

    private func firstPixel(
        from image: UIImage
    ) -> Pixel? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var bytes = [
            UInt8
        ](
            repeating: 0,
            count: 4
        )

        let didDraw = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }

            context.draw(
                cgImage,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: 1,
                    height: 1
                )
            )

            return true
        }

        guard didDraw else {
            return nil
        }

        return Pixel(
            red: bytes[0],
            green: bytes[1],
            blue: bytes[2]
        )
    }
}

private struct ProcessingOutput {
    let result: Result<UIImage, ImageProcessingError>
    let wasDeliveredOnMainThread: Bool
}

private struct Pixel {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}
