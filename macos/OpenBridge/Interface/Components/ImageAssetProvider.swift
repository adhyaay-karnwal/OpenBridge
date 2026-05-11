import AppKit
import Foundation

private actor InFlightTaskStore {
    private var tasks: [String: Task<NSImage, Error>] = [:]

    func task(for key: String) -> Task<NSImage, Error>? {
        tasks[key]
    }

    func getOrInsertTask(
        for key: String,
        createTask: () -> Task<NSImage, Error>
    ) -> Task<NSImage, Error> {
        if let existing = tasks[key] {
            return existing
        }
        let task = createTask()
        tasks[key] = task
        return task
    }

    func remove(for key: String) {
        tasks.removeValue(forKey: key)
    }
}

nonisolated enum ImageAssetProvider {
    nonisolated enum ImageAssetProviderError: Error {
        case failedToLoadImage
    }

    private nonisolated(unsafe) static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100 // Limit number of images
        // add a total cost limit for memory usage?
        return cache
    }()

    private static let taskStore = InFlightTaskStore()

    static func imageURL(for fileName: String?) -> URL? {
        guard let fileName, !fileName.isEmpty else { return nil }
        return Constant.imagesDirectoryURL.appendingPathComponent(fileName)
    }

    static func loadImage(for fileName: String?) throws -> NSImage {
        guard let fileName, !fileName.isEmpty else { throw ImageAssetProviderError.failedToLoadImage }

        if let cachedImage = imageCache.object(forKey: fileName as NSString) {
            return cachedImage
        }

        guard let url = imageURL(for: fileName),
              let image = NSImage(contentsOf: url)
        else {
            throw ImageAssetProviderError.failedToLoadImage
        }

        imageCache.setObject(image, forKey: fileName as NSString)
        return image
    }

    static func loadImageAsync(for fileName: String?) async throws -> NSImage {
        guard let fileName, !fileName.isEmpty else {
            throw ImageAssetProviderError.failedToLoadImage
        }

        if let cachedImage = imageCache.object(forKey: fileName as NSString) {
            return cachedImage
        }

        if let existingTask = await taskStore.task(for: fileName) {
            return try await existingTask.value
        }

        let task = await taskStore.getOrInsertTask(for: fileName) {
            Task.detached(priority: .userInitiated) {
                guard let url = imageURL(for: fileName),
                      let image = NSImage(contentsOf: url)
                else {
                    throw ImageAssetProviderError.failedToLoadImage
                }

                imageCache.setObject(image, forKey: fileName as NSString)
                return image
            }
        }
        do {
            let image = try await task.value
            await taskStore.remove(for: fileName)
            return image
        } catch {
            await taskStore.remove(for: fileName)
            throw error
        }
    }

    static func clearCache() {
        imageCache.removeAllObjects()
    }

    // MARK: - Remote URL Loading

    /// Loads an image from a remote URL with in-memory caching.
    /// Uses URL's absolute string as cache key. Supports task deduplication
    /// to prevent multiple concurrent requests for the same URL.
    static func loadImageAsync(from url: URL) async throws -> NSImage {
        let cacheKey = url.absoluteString

        if let cachedImage = imageCache.object(forKey: cacheKey as NSString) {
            return cachedImage
        }

        if let existingTask = await taskStore.task(for: cacheKey) {
            return try await existingTask.value
        }

        let task = await taskStore.getOrInsertTask(for: cacheKey) {
            Task.detached(priority: .userInitiated) {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = NSImage(data: data) else {
                    throw ImageAssetProviderError.failedToLoadImage
                }
                imageCache.setObject(image, forKey: cacheKey as NSString)
                return image
            }
        }

        do {
            let image = try await task.value
            await taskStore.remove(for: cacheKey)
            return image
        } catch {
            await taskStore.remove(for: cacheKey)
            throw error
        }
    }
}
