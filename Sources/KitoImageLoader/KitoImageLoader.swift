//
//  KitoImageLoader.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/21/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import UIKit

public enum KitoImageLoaderError: Error, LocalizedError, Sendable {
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .decodingFailed: return "The downloaded data could not be decoded as an image."
        }
    }
}

/// Memory → disk → network image loading with request de-duplication:
/// ten cells asking for the same URL at once still trigger exactly one
/// network fetch, and every caller shares its result.
///
/// The cache key is the URL itself, so "unless the link changes" falls out
/// for free — a different link is a different key, a cache miss, a fresh
/// fetch. There's no separate invalidation call to remember.
public actor KitoImageLoader {
    public static let shared = KitoImageLoader()

    private let memoryCache: KitoMemoryImageCache
    public let diskCache: KitoDiskImageCache
    private let fetcher: KitoImageDataFetching
    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    public init(
        memoryLimitBytes: Int = 50 * 1024 * 1024,
        diskCache: KitoDiskImageCache? = nil,
        diskLimitBytes: Int = 100 * 1024 * 1024,
        fetcher: KitoImageDataFetching = URLSessionImageFetcher()
    ) {
        self.memoryCache = KitoMemoryImageCache(costLimitBytes: memoryLimitBytes)
        self.diskCache = diskCache ?? KitoDiskImageCache(maxBytes: diskLimitBytes)
        self.fetcher = fetcher
    }

    /// Loads `url`, preferring memory → disk → network, in that order.
    /// Concurrent calls for the same URL share one in-flight request rather
    /// than issuing duplicates. `onProgress` reports a 0...1 fraction while
    /// actually downloading over the network — it's never called on a cache
    /// hit, and only the first caller of a shared in-flight request observes
    /// it (later callers just receive the final image, same tradeoff most
    /// image-loading libraries make rather than broadcasting to N observers).
    @discardableResult
    public func image(for url: URL, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> UIImage {
        if let cached = memoryCache.image(for: url) {
            return cached
        }
        if let task = inFlight[url] {
            return try await task.value
        }

        let memoryCache = self.memoryCache
        let diskCache = self.diskCache
        let fetcher = self.fetcher

        let task = Task<UIImage, Error> {
            if let data = await diskCache.data(for: url.absoluteString), let image = UIImage(data: data) {
                memoryCache.store(image, for: url)
                return image
            }
            let data = try await fetcher.fetch(url, onProgress: onProgress)
            guard let image = UIImage(data: data) else { throw KitoImageLoaderError.decodingFailed }
            memoryCache.store(image, for: url)
            await diskCache.store(data, for: url.absoluteString)
            return image
        }

        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }

    /// Warms the cache for `urls` without waiting on the result — fire this
    /// from a list's `onAppear`/`willDisplay` for cells just about to scroll
    /// into view.
    public func prefetch(_ urls: [URL]) {
        for url in urls {
            Task { _ = try? await image(for: url) }
        }
    }

    public func clearMemoryCache() {
        memoryCache.removeAll()
    }

    public func clearDiskCache() async {
        await diskCache.removeAll()
    }
}
