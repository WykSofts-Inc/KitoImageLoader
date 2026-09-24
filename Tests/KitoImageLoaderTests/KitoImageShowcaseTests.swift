//
//  KitoImageShowcaseTests.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
import UIKit
@testable import KitoImageLoader

private struct PixelFetcher: KitoImageDataFetching {
    func fetch(_ url: URL, onProgress: (@Sendable (Double) -> Void)?) async throws -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    }
}

private struct OfflineFetcher: KitoImageDataFetching {
    func fetch(_ url: URL, onProgress: (@Sendable (Double) -> Void)?) async throws -> Data {
        throw URLError(.notConnectedToInternet)
    }
}

final class KitoImageShowcaseTests: XCTestCase {
    private func freshDisk() -> KitoDiskImageCache {
        KitoDiskImageCache(directoryName: "KitoImageShowcaseTests-\(UUID().uuidString)")
    }

    // MARK: Stats

    func testStatsCountNetworkThenMemoryHits() async throws {
        let disk = freshDisk()
        let loader = KitoImageLoader(diskCache: disk, fetcher: PixelFetcher())
        let url = URL(string: "https://example.com/stats.png")!

        _ = try await loader.image(for: url)
        _ = try await loader.image(for: url)
        _ = try await loader.image(for: url)

        let stats = await loader.stats()
        XCTAssertEqual(stats.requests, 3)
        XCTAssertEqual(stats.networkFetches, 1)
        XCTAssertEqual(stats.memoryHits, 2)
        XCTAssertEqual(stats.hitRate, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertGreaterThan(stats.downloadedBytes, 0)
        await disk.removeAll()
    }

    func testStatsCountFailures() async {
        let disk = freshDisk()
        let loader = KitoImageLoader(diskCache: disk, fetcher: OfflineFetcher())
        _ = try? await loader.image(for: URL(string: "https://example.com/offline.png")!)
        let stats = await loader.stats()
        XCTAssertEqual(stats.failures, 1)
        XCTAssertEqual(stats.networkFetches, 0)
        await disk.removeAll()
    }

    func testResetStats() async throws {
        let disk = freshDisk()
        let loader = KitoImageLoader(diskCache: disk, fetcher: PixelFetcher())
        _ = try await loader.image(for: URL(string: "https://example.com/reset.png")!)
        await loader.resetStats()
        let stats = await loader.stats()
        XCTAssertEqual(stats.requests, 0)
        await disk.removeAll()
    }

    func testCachedImageIsSynchronousAfterLoad() async throws {
        let disk = freshDisk()
        let loader = KitoImageLoader(diskCache: disk, fetcher: PixelFetcher())
        let url = URL(string: "https://example.com/sync.png")!
        XCTAssertNil(loader.cachedImage(for: url))
        _ = try await loader.image(for: url)
        XCTAssertNotNil(loader.cachedImage(for: url))
        await disk.removeAll()
    }

    func testPrefetchAndWaitLoadsEveryURL() async {
        let disk = freshDisk()
        let loader = KitoImageLoader(diskCache: disk, fetcher: PixelFetcher())
        let urls = (0..<7).map { URL(string: "https://example.com/p\($0).png")! }
        let loaded = await loader.prefetchAndWait(urls, maxConcurrent: 3)
        XCTAssertEqual(loaded, 7)
        for url in urls { XCTAssertNotNil(loader.cachedImage(for: url)) }
        await disk.removeAll()
    }

    // MARK: Retry

    func testRetryBackoffDoubles() {
        let policy = KitoImageRetryPolicy(maxRetries: 3, baseDelay: 0.5)
        XCTAssertEqual(policy.delay(beforeRetry: 1), 0.5)
        XCTAssertEqual(policy.delay(beforeRetry: 2), 1.0)
        XCTAssertEqual(policy.delay(beforeRetry: 3), 2.0)
        XCTAssertEqual(KitoImageRetryPolicy(maxRetries: -2).maxRetries, 0)
    }

    // MARK: Avatars

    func testInitials() {
        XCTAssertEqual(KitoAvatarInitials.initials(for: "Wycliff Njenga"), "WN")
        XCTAssertEqual(KitoAvatarInitials.initials(for: "wycliff"), "W")
        XCTAssertEqual(KitoAvatarInitials.initials(for: "  amara  mwangi otieno "), "AO")
        XCTAssertEqual(KitoAvatarInitials.initials(for: ""), "?")
    }

    func testPaletteIndexIsStableAndInRange() {
        let first = KitoAvatarInitials.paletteIndex(for: "Wycliff N", count: 6)
        XCTAssertEqual(first, KitoAvatarInitials.paletteIndex(for: "wycliff n", count: 6))
        XCTAssertTrue((0..<6).contains(first))
        XCTAssertEqual(KitoAvatarInitials.paletteIndex(for: "anyone", count: 0), 0)
    }

    // MARK: Masonry

    func testMasonryFillsShortestColumn() {
        let assignments = KitoMasonry.columnAssignments(heights: [200, 100, 100, 100], columns: 2)
        XCTAssertEqual(assignments, [0, 1, 1, 0])
    }

    func testMasonryTotalHeightIncludesSpacing() {
        let height = KitoMasonry.totalHeight(heights: [100, 100, 100], columns: 2, spacing: 10)
        XCTAssertEqual(height, 210)
    }

    // MARK: Zoom

    func testZoomClamp() {
        XCTAssertEqual(KitoZoom.clamp(5, to: 1...4, rubberBand: false), 4)
        XCTAssertEqual(KitoZoom.clamp(0.5, to: 1...4, rubberBand: false), 1)
        XCTAssertGreaterThan(KitoZoom.clamp(5, to: 1...4), 4)
        XCTAssertLessThan(KitoZoom.clamp(5, to: 1...4), 5)
    }

    func testZoomOffsetStaysInsideBounds() {
        let size = CGSize(width: 100, height: 200)
        let clamped = KitoZoom.clampOffset(CGSize(width: 500, height: -500), size: size, scale: 2)
        XCTAssertEqual(clamped, CGSize(width: 50, height: -100))
        XCTAssertEqual(KitoZoom.clampOffset(CGSize(width: 30, height: 30), size: size, scale: 1), .zero)
    }
}
