//
//  KitoImageLoaderTests.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/21/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
import UIKit
@testable import KitoImageLoader

private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// Returns a real, tiny, decodable PNG every time — a fixed 1x1 red pixel —
/// and counts how many times `fetch` was actually called, so tests can
/// assert de-duplication and cache hits without touching the network.
private final class MockImageFetcher: KitoImageDataFetching {
    let counter = CallCounter()
    var delayNanoseconds: UInt64 = 0

    func fetch(_ url: URL, onProgress: (@Sendable (Double) -> Void)?) async throws -> Data {
        await counter.increment()
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        onProgress?(1)
        return Self.onePixelPNG
    }

    /// A minimal valid 1x1 PNG, decodable by `UIImage(data:)`.
    static let onePixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
}

final class KitoImageLoaderTests: XCTestCase {
    func testMemoryCacheStoresAndReturnsSameImage() async throws {
        let fetcher = MockImageFetcher()
        let loader = KitoImageLoader(fetcher: fetcher)
        let url = URL(string: "https://example.com/one.png")!

        _ = try await loader.image(for: url)
        _ = try await loader.image(for: url)

        let calls = await fetcher.counter.count
        XCTAssertEqual(calls, 1, "second request for the same URL should be served from memory, not refetched")
    }

    func testConcurrentRequestsForSameURLDeduplicate() async throws {
        let fetcher = MockImageFetcher()
        fetcher.delayNanoseconds = 50_000_000
        let loader = KitoImageLoader(fetcher: fetcher)
        let url = URL(string: "https://example.com/two.png")!

        async let first = loader.image(for: url)
        async let second = loader.image(for: url)
        async let third = loader.image(for: url)
        _ = try await (first, second, third)

        let calls = await fetcher.counter.count
        XCTAssertEqual(calls, 1, "three concurrent requests for the same URL should share one in-flight fetch")
    }

    func testDifferentURLsAreNotConflated() async throws {
        let fetcher = MockImageFetcher()
        let loader = KitoImageLoader(fetcher: fetcher)

        _ = try await loader.image(for: URL(string: "https://example.com/a.png")!)
        _ = try await loader.image(for: URL(string: "https://example.com/b.png")!)

        let calls = await fetcher.counter.count
        XCTAssertEqual(calls, 2, "a different link is a different cache key — both should fetch")
    }

    func testDiskCacheRoundTrips() async {
        let cache = KitoDiskImageCache(directoryName: "KitoImageLoaderTests-\(UUID().uuidString)")
        let payload = Data("not actually an image, just bytes".utf8)

        await cache.store(payload, for: "key-1")
        let loaded = await cache.data(for: "key-1")

        XCTAssertEqual(loaded, payload)
        await cache.removeAll()
    }

    func testDiskCachePrunesOldestEntriesWhenOverBudget() async {
        let cache = KitoDiskImageCache(maxBytes: 30, directoryName: "KitoImageLoaderTests-\(UUID().uuidString)")
        await cache.store(Data(repeating: 0, count: 20), for: "old")
        // Ensure a distinct modification timestamp before writing the next entry.
        try? await Task.sleep(nanoseconds: 20_000_000)
        await cache.store(Data(repeating: 0, count: 20), for: "new")

        let old = await cache.data(for: "old")
        let new = await cache.data(for: "new")
        XCTAssertNil(old, "oldest entry should have been pruned once the 30-byte budget was exceeded")
        XCTAssertNotNil(new)
        await cache.removeAll()
    }

    func testSecondLoaderInstanceHitsDiskCacheNotNetwork() async throws {
        // Simulates a fresh app launch: a new KitoImageLoader (empty memory
        // cache) pointed at a disk cache that already has this URL's bytes
        // from a previous session.
        let sharedDisk = KitoDiskImageCache(directoryName: "KitoImageLoaderTests-\(UUID().uuidString)")
        let url = URL(string: "https://example.com/cached.png")!
        await sharedDisk.store(MockImageFetcher.onePixelPNG, for: url.absoluteString)

        let fetcher = MockImageFetcher()
        let loader = KitoImageLoader(diskCache: sharedDisk, fetcher: fetcher)
        let image = try await loader.image(for: url)

        XCTAssertEqual(image.size, CGSize(width: 1, height: 1))
        let calls = await fetcher.counter.count
        XCTAssertEqual(calls, 0, "the URL was already on disk — no network fetch should have happened")
        await sharedDisk.removeAll()
    }
}

private final class MockVideoFetcher: KitoVideoDataFetching {
    let counter = CallCounter()
    var lastProgressReported: Double?

    func download(_ url: URL, to destination: URL, onProgress: (@Sendable (Double) -> Void)?) async throws {
        await counter.increment()
        try Data("fake video bytes".utf8).write(to: destination)
        onProgress?(1)
    }
}

final class KitoVideoLoaderTests: XCTestCase {
    func testDownloadsOnceThenServesFromDiskCache() async throws {
        let fetcher = MockVideoFetcher()
        let loader = KitoVideoLoader(cache: KitoVideoDiskCache(directoryName: "KitoVideoLoaderTests-\(UUID().uuidString)"), fetcher: fetcher)
        let url = URL(string: "https://example.com/clip.mp4")!

        let first = try await loader.localFile(for: url)
        let second = try await loader.localFile(for: url)

        XCTAssertEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        let calls = await fetcher.counter.count
        XCTAssertEqual(calls, 1, "the second request for the same URL should be served from the cached file, not re-downloaded")
    }

    func testDifferentURLProducesDifferentCachedFile() async throws {
        let fetcher = MockVideoFetcher()
        let loader = KitoVideoLoader(cache: KitoVideoDiskCache(directoryName: "KitoVideoLoaderTests-\(UUID().uuidString)"), fetcher: fetcher)

        let a = try await loader.localFile(for: URL(string: "https://example.com/a.mp4")!)
        let b = try await loader.localFile(for: URL(string: "https://example.com/b.mp4")!)

        XCTAssertNotEqual(a, b)
        let calls = await fetcher.counter.count
        XCTAssertEqual(calls, 2)
    }

    func testConcurrentRequestsForSameVideoDeduplicate() async throws {
        let fetcher = MockVideoFetcher()
        let loader = KitoVideoLoader(cache: KitoVideoDiskCache(directoryName: "KitoVideoLoaderTests-\(UUID().uuidString)"), fetcher: fetcher)
        let url = URL(string: "https://example.com/concurrent.mp4")!

        async let first = loader.localFile(for: url)
        async let second = loader.localFile(for: url)
        _ = try await (first, second)

        let calls = await fetcher.counter.count
        XCTAssertEqual(calls, 1)
    }

    func testCachedFilePreservesSourceExtension() async throws {
        let fetcher = MockVideoFetcher()
        let loader = KitoVideoLoader(cache: KitoVideoDiskCache(directoryName: "KitoVideoLoaderTests-\(UUID().uuidString)"), fetcher: fetcher)

        let local = try await loader.localFile(for: URL(string: "https://example.com/clip.mov")!)

        XCTAssertEqual(local.pathExtension, "mov")
    }
}
