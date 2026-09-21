//
//  KitoVideoCache.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/21/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation
import CryptoKit

/// On-disk cache for downloaded video files, one file per URL (unlike
/// `KitoDiskImageCache`, which stores raw `Data`) — `AVPlayer` needs a real
/// file on disk with the right extension, not bytes in memory. Same rule as
/// the image cache: the URL is the whole key, so a different link is
/// automatically a fresh download; nothing needs explicit invalidation.
public actor KitoVideoDiskCache {
    private let directory: URL
    private let maxBytes: Int

    public init(maxBytes: Int = 300 * 1024 * 1024, directoryName: String = "KitoImageLoaderVideos") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = caches.appendingPathComponent(directoryName, isDirectory: true)
        self.maxBytes = maxBytes
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Existing cached file for `key`, if any — touches its modification
    /// date so the LRU prune treats it as recently used.
    public func cachedFile(for key: String, sourceExtension: String) -> URL? {
        let url = fileURL(for: key, sourceExtension: sourceExtension)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    /// Moves a completed download from a temp location into the cache,
    /// pruning oldest entries afterward if that pushes the cache over budget.
    public func commit(tempFile: URL, for key: String, sourceExtension: String) -> URL {
        let destination = fileURL(for: key, sourceExtension: sourceExtension)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: tempFile, to: destination)
        pruneIfNeeded()
        return destination
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String, sourceExtension: String) -> URL {
        let ext = sourceExtension.isEmpty ? "mp4" : sourceExtension
        return directory.appendingPathComponent(Self.hash(key)).appendingPathExtension(ext)
    }

    private func pruneIfNeeded() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        let entries = urls.compactMap { url -> (url: URL, size: Int, modified: Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate else { return nil }
            return (url, size, modified)
        }

        let totalSize = entries.reduce(0) { $0 + $1.size }
        guard totalSize > maxBytes else { return }

        var overage = totalSize - maxBytes
        for entry in entries.sorted(by: { $0.modified < $1.modified }) {
            guard overage > 0 else { break }
            try? FileManager.default.removeItem(at: entry.url)
            overage -= entry.size
        }
    }

    private static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
