//
//  KitoImageCache.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/21/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import UIKit
import CryptoKit

/// In-memory tier — an `NSCache` (thread-safe by design, hence the
/// `@unchecked Sendable`) keyed by URL, cost-weighted by decoded byte size
/// so a handful of large images don't starve the cache the way a
/// count-based limit would.
final class KitoMemoryImageCache: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()

    init(costLimitBytes: Int) {
        cache.totalCostLimit = costLimitBytes
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4 * image.scale * image.scale)
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: max(cost, 1))
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// On-disk tier under `Caches/KitoImageLoader`, keyed by a SHA-256 hash of
/// the URL string (so cache keys never collide with the filesystem's own
/// path rules) and pruned oldest-accessed-first once `maxBytes` is exceeded.
/// The URL itself is the whole cache key — a different link is automatically
/// a miss; there's no separate "invalidate" step to remember to call.
public actor KitoDiskImageCache {
    private let directory: URL
    private let maxBytes: Int

    public init(maxBytes: Int = 100 * 1024 * 1024, directoryName: String = "KitoImageLoader") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = caches.appendingPathComponent(directoryName, isDirectory: true)
        self.maxBytes = maxBytes
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func data(for key: String) -> Data? {
        let fileURL = self.fileURL(for: key)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return data
    }

    public func store(_ data: Data, for key: String) {
        let fileURL = self.fileURL(for: key)
        try? data.write(to: fileURL, options: .atomic)
        pruneIfNeeded()
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Total bytes currently on disk — mostly useful for tests/diagnostics.
    public func currentSizeBytes() -> Int {
        entries().reduce(0) { $0 + $1.size }
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(Self.hash(key))
    }

    private func pruneIfNeeded() {
        let all = entries()
        let totalSize = all.reduce(0) { $0 + $1.size }
        guard totalSize > maxBytes else { return }

        var overage = totalSize - maxBytes
        for entry in all.sorted(by: { $0.modified < $1.modified }) {
            guard overage > 0 else { break }
            try? FileManager.default.removeItem(at: entry.url)
            overage -= entry.size
        }
    }

    private func entries() -> [(url: URL, size: Int, modified: Date)] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return [] }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate else { return nil }
            return (url, size, modified)
        }
    }

    private static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
