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
    private var inFlight: [URL: Task<LoadedImage, Error>] = [:]
    private let memoryLimitBytes: Int

    private var requests = 0
    private var memoryHits = 0
    private var diskHits = 0
    private var networkFetches = 0
    private var sharedRequests = 0
    private var failures = 0
    private var downloadedBytes = 0

    private struct LoadedImage: @unchecked Sendable {
        enum Source { case disk, network }
        let image: UIImage
        let source: Source
        let bytes: Int
    }

    public init(
        memoryLimitBytes: Int = 50 * 1024 * 1024,
        diskCache: KitoDiskImageCache? = nil,
        diskLimitBytes: Int = 100 * 1024 * 1024,
        fetcher: KitoImageDataFetching = URLSessionImageFetcher()
    ) {
        self.memoryCache = KitoMemoryImageCache(costLimitBytes: memoryLimitBytes)
        self.memoryLimitBytes = memoryLimitBytes
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
        requests += 1
        if let cached = memoryCache.image(for: url) {
            memoryHits += 1
            return cached
        }
        if let task = inFlight[url] {
            sharedRequests += 1
            return try await task.value.image
        }

        let memoryCache = self.memoryCache
        let diskCache = self.diskCache
        let fetcher = self.fetcher

        let task = Task<LoadedImage, Error> {
            if let data = await diskCache.data(for: url.absoluteString), let image = UIImage(data: data) {
                memoryCache.store(image, for: url)
                return LoadedImage(image: image, source: .disk, bytes: data.count)
            }
            let data = try await fetcher.fetch(url, onProgress: onProgress)
            guard let image = UIImage(data: data) else { throw KitoImageLoaderError.decodingFailed }
            memoryCache.store(image, for: url)
            await diskCache.store(data, for: url.absoluteString)
            return LoadedImage(image: image, source: .network, bytes: data.count)
        }

        inFlight[url] = task
        defer { inFlight[url] = nil }
        do {
            let loaded = try await task.value
            switch loaded.source {
            case .disk: diskHits += 1
            case .network:
                networkFetches += 1
                downloadedBytes += loaded.bytes
            }
            return loaded.image
        } catch {
            failures += 1
            throw error
        }
    }

    /// The image for `url` if it's already decoded in memory — synchronous, so a view can show
    /// a cached image on its first frame instead of flashing a placeholder.
    public nonisolated func cachedImage(for url: URL) -> UIImage? {
        memoryCache.image(for: url)
    }

    /// Loads every URL (up to `maxConcurrent` at a time) and returns once they're all cached —
    /// warm a gallery before showing it. Returns how many loaded successfully.
    @discardableResult
    public func prefetchAndWait(_ urls: [URL], maxConcurrent: Int = 4) async -> Int {
        await withTaskGroup(of: Bool.self) { group in
            var loaded = 0
            var iterator = urls.makeIterator()
            for _ in 0..<max(maxConcurrent, 1) {
                guard let url = iterator.next() else { break }
                group.addTask { (try? await self.image(for: url)) != nil }
            }
            for await success in group {
                if success { loaded += 1 }
                if let url = iterator.next() {
                    group.addTask { (try? await self.image(for: url)) != nil }
                }
            }
            return loaded
        }
    }

    /// Hit rates, fetch counts and disk usage since this loader was created (or since
    /// `resetStats()`).
    public func stats() async -> KitoImageCacheStats {
        KitoImageCacheStats(
            requests: requests,
            memoryHits: memoryHits,
            diskHits: diskHits,
            networkFetches: networkFetches,
            sharedRequests: sharedRequests,
            failures: failures,
            downloadedBytes: downloadedBytes,
            diskBytes: await diskCache.currentSizeBytes(),
            memoryLimitBytes: memoryLimitBytes
        )
    }

    public func resetStats() {
        requests = 0
        memoryHits = 0
        diskHits = 0
        networkFetches = 0
        sharedRequests = 0
        failures = 0
        downloadedBytes = 0
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

    /// Clears memory and disk.
    public func clearAll() async {
        memoryCache.removeAll()
        await diskCache.removeAll()
    }
}
