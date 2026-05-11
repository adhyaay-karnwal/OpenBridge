//
//  ImageProcessor.swift
//  OpenBridge
//
//  Created by OpenBridge on 2025/01/27.
//

import AppKit
import CryptoKit
import Foundation
import Vision

private nonisolated let logger = Logger.app

nonisolated struct OptimizedImage: Sendable {
    let image: NSImage
    let data: Data
    let mimeType: String
    let pixelSize: CGSize

    var base64String: String {
        data.base64EncodedString()
    }
}

final nonisolated class ImageProcessor: @unchecked Sendable {
    static let shared = ImageProcessor()

    private init() {
        // Trigger directory initialization
        _ = Constant.imagesDirectoryURL
    }

    /// Get the full path to an image file
    func imageURL(for fileName: String) -> URL {
        Constant.imagesDirectoryURL.appendingPathComponent(fileName)
    }

    /// Get the full path to a thumbnail file
    func thumbnailURL(for fileName: String) -> URL {
        Constant.imagesDirectoryURL.appendingPathComponent(fileName)
    }

    // MARK: - Private Methods

    func performOCR(on cgImage: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                let result = recognizedStrings.joined(separator: " ")
                continuation.resume(returning: result.isEmpty ? nil : result)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    /// Generate a description or summary of an image using AI (GPT-5-nano model).
    /// - Parameters:
    ///   - cgImage: The image to analyze
    ///   - prompt: Instructions for the model. Defaults to describing the image.
    /// - Returns: AI-generated description of the image, or nil if analysis fails
    func performSummarization(
        on cgImage: CGImage,
        prompt _: String = "Describe this image in detail."
    ) async -> String? {
        let image = NSImage(cgImage: cgImage, size: .zero)
        guard image.optimized(maxDimension: 1024, quality: 0.8) != nil
        else {
            logger.error("Failed to optimize image for summarization")
            return nil
        }

        logger.info("Image summarization is unavailable in the local app")
        return nil
    }
}

// MARK: - LLM Image Normalization

/// Result of normalizing an image for LLM input.
struct NormalizedImage: Sendable {
    let data: Data
    let contentType: String
    let filename: String
}

private nonisolated let chatImageTargetBytes = 300 * 1024

/// Supported image formats by the LLM vision API.
private nonisolated let llmSupportedImageTypes: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/webp"]

/// Maximum image data size before compression (2MB).
private nonisolated let llmMaxImageDataSize = 2 * 1024 * 1024

/// Maximum pixel count for compressed images (1 million pixels).
private nonisolated let llmMaxPixelCount = 1_000_000

/// Normalize image data for LLM input: convert unsupported formats to PNG, and compress large images.
/// This ensures the image is compatible with the LLM vision API.
/// - Parameters:
///   - data: Original image data
///   - contentType: MIME type of the image (must be an image type)
///   - filename: Original filename
/// - Returns: Normalized image with potentially converted format and reduced size, or nil if conversion fails
nonisolated func normalizeImageForLLMInput(
    data: Data,
    contentType: String,
    filename: String
) -> NormalizedImage? {
    let needsFormatConversion = !llmSupportedImageTypes.contains(contentType)
    let needsSizeCompression = data.count > llmMaxImageDataSize

    if needsFormatConversion || needsSizeCompression {
        guard let pngData = convertImageToPNG(data: data, maxPixels: needsSizeCompression ? llmMaxPixelCount : nil) else {
            return nil
        }
        let newFilename = (filename as NSString).deletingPathExtension + ".png"
        return NormalizedImage(data: pngData, contentType: "image/png", filename: newFilename)
    }

    return NormalizedImage(data: data, contentType: contentType, filename: filename)
}

/// Normalize an image for local chat usage.
/// Produces a reasonably small JPEG so message history can reference a stable local file
/// without carrying around the original, potentially large, image payload.
nonisolated func normalizeImageForChatInput(
    data: Data,
    filename: String,
    targetBytes: Int = chatImageTargetBytes
) -> NormalizedImage? {
    guard let sourceImage = NSImage(data: data) else {
        return nil
    }

    let baseName = (filename as NSString).deletingPathExtension
    let outputFilename = baseName.isEmpty ? "image.jpg" : "\(baseName).jpg"
    let maxDimensions: [CGFloat] = [1600, 1400, 1200, 1024, 896, 768, 640]
    let qualities: [CGFloat] = [0.82, 0.72, 0.62, 0.52, 0.42, 0.34]

    var bestData: Data?

    for maxDimension in maxDimensions {
        let resized = sourceImage.resized(toFit: maxDimension) ?? sourceImage
        let flattened = resized.flattenedForJPEG()

        for quality in qualities {
            guard let jpegData = flattened.jpegData(compressionQuality: quality) else {
                continue
            }

            if jpegData.count <= targetBytes {
                return NormalizedImage(
                    data: jpegData,
                    contentType: "image/jpeg",
                    filename: outputFilename
                )
            }

            if bestData == nil || jpegData.count < (bestData?.count ?? Int.max) {
                bestData = jpegData
            }
        }
    }

    guard let bestData else {
        return nil
    }

    return NormalizedImage(
        data: bestData,
        contentType: "image/jpeg",
        filename: outputFilename
    )
}

/// Convert image data to PNG format, optionally resizing to fit within maxPixels.
private nonisolated func convertImageToPNG(data: Data, maxPixels: Int? = nil) -> Data? {
    guard let image = NSImage(data: data) else {
        return nil
    }

    var targetSize = image.size

    // Resize if exceeds max pixel count
    if let maxPixels {
        let currentPixels = Int(targetSize.width * targetSize.height)
        if currentPixels > maxPixels {
            let scale = sqrt(Double(maxPixels) / Double(currentPixels))
            targetSize = NSSize(
                width: floor(targetSize.width * scale),
                height: floor(targetSize.height * scale)
            )
        }
    }

    // Create a new image with the target size
    let resizedImage = NSImage(size: targetSize, flipped: false) { rect in
        image.draw(
            in: rect,
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        return true
    }

    guard let tiffData = resizedImage.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:])
    else {
        return nil
    }
    return pngData
}

nonisolated extension Data {
    var sha256Hash: String {
        let digest = SHA256.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated extension CGImage {
    func pngData() -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: self)
        return bitmapRep.representation(using: .png, properties: [:])
    }
}

nonisolated extension NSImage {
    func optimized(
        maxDimension: CGFloat = 1024,
        quality: CGFloat = 0.8
    ) -> OptimizedImage? {
        let targetImage: NSImage = if maxDimension > 0 {
            resized(toFit: maxDimension) ?? self
        } else {
            self
        }

        let pixelSize = targetImage.pixelSize

        let clampedQuality = max(0.05, min(0.95, quality))
        if let jpegData = targetImage.jpegData(compressionQuality: clampedQuality) {
            return OptimizedImage(
                image: targetImage,
                data: jpegData,
                mimeType: "image/jpeg",
                pixelSize: pixelSize
            )
        }

        if let pngData = targetImage.pngData() {
            return OptimizedImage(
                image: targetImage,
                data: pngData,
                mimeType: "image/png",
                pixelSize: pixelSize
            )
        }

        return nil
    }

    var pixelSize: CGSize {
        if let rep = representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return size
    }

    func resized(toFit maxDimension: CGFloat) -> NSImage? {
        guard maxDimension > 0 else { return self }
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let image = NSImage(size: newSize)
        image.lockFocus()
        defer { image.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1.0)
        return image
    }

    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }
        let factor = max(0.0, min(1.0, compressionQuality))
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: factor]
        )
    }

    func flattenedForJPEG(backgroundColor: NSColor = .white) -> NSImage {
        let canvasSize = size
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return self
        }

        let flattened = NSImage(size: canvasSize)
        flattened.lockFocus()
        defer { flattened.unlockFocus() }

        backgroundColor.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()
        draw(
            in: NSRect(origin: .zero, size: canvasSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        return flattened
    }
}
