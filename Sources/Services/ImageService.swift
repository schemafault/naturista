import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageError: Error {
    case cannotCreateImageSource
    case cannotReadImage
    case cannotGetEXIF
    case cannotCreateDestination
    case writeFailed
    case invalidImageFormat
}

struct ImageMetadata {
    let capturedAt: Date?
}

actor ImageService {
    static let shared = ImageService()

    private init() {}

    func extractMetadata(from url: URL) throws -> ImageMetadata {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageError.cannotCreateImageSource
        }

        let capturedAt = extractCaptureDate(from: imageSource)
        return ImageMetadata(capturedAt: capturedAt)
    }

    private func extractCaptureDate(from imageSource: CGImageSource) -> Date? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
              let dateString = exifDict[kCGImagePropertyExifDateTimeOriginal as String] as? String else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }

    func createWorkingCopy(sourceURL: URL, maxPixels: Int = 4_000_000, jpegQuality: Double = 0.8) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw ImageError.cannotCreateImageSource
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ImageError.cannotReadImage
        }

        let resizedImage = resizeIfNeeded(cgImage, maxPixels: maxPixels)

        let outputURL = AppPaths.working.appendingPathComponent(UUID().uuidString + ".jpg")

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageError.cannotCreateDestination
        }

        let options: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: jpegQuality
        ]

        CGImageDestinationAddImage(destination, resizedImage, options as CFDictionary)

        if !CGImageDestinationFinalize(destination) {
            throw ImageError.writeFailed
        }

        return outputURL
    }

    private func resizeIfNeeded(_ image: CGImage, maxPixels: Int) -> CGImage {
        let width = image.width
        let height = image.height
        let totalPixels = width * height

        if totalPixels <= maxPixels {
            return image
        }

        let scale = sqrt(Double(maxPixels) / Double(totalPixels))
        let newWidth = Int(Double(width) * scale)
        let newHeight = Int(Double(height) * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = image.bitmapInfo

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        return context.makeImage() ?? image
    }
}