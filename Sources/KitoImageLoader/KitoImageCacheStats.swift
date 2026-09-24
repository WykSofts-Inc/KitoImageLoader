//
//  KitoImageCacheStats.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// A snapshot of how a `KitoImageLoader` has been serving requests — for a debug panel, a
/// settings "Storage" row, or a test.
public struct KitoImageCacheStats: Equatable, Sendable {
    /// Every call to `image(for:)`.
    public var requests: Int
    /// Served straight from decoded images in memory.
    public var memoryHits: Int
    /// Read back from disk (a previous session, or evicted from memory).
    public var diskHits: Int
    /// Downloaded.
    public var networkFetches: Int
    /// Joined a download already in flight for the same URL instead of starting another.
    public var sharedRequests: Int
    public var failures: Int
    /// Bytes pulled over the network.
    public var downloadedBytes: Int
    /// Bytes on disk right now.
    public var diskBytes: Int
    public var memoryLimitBytes: Int

    public init(
        requests: Int = 0,
        memoryHits: Int = 0,
        diskHits: Int = 0,
        networkFetches: Int = 0,
        sharedRequests: Int = 0,
        failures: Int = 0,
        downloadedBytes: Int = 0,
        diskBytes: Int = 0,
        memoryLimitBytes: Int = 0
    ) {
        self.requests = requests
        self.memoryHits = memoryHits
        self.diskHits = diskHits
        self.networkFetches = networkFetches
        self.sharedRequests = sharedRequests
        self.failures = failures
        self.downloadedBytes = downloadedBytes
        self.diskBytes = diskBytes
        self.memoryLimitBytes = memoryLimitBytes
    }

    /// Share of requests that never touched the network (memory, disk or a shared download),
    /// 0...1. Zero before the first request.
    public var hitRate: Double {
        guard requests > 0 else { return 0 }
        return Double(memoryHits + diskHits + sharedRequests) / Double(requests)
    }
}
