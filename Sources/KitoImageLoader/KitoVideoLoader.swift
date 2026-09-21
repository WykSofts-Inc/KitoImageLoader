//
//  KitoVideoLoader.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/21/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// The download seam `KitoVideoLoader` writes through — swappable in tests
/// the same way `KitoImageDataFetching` is for images.
public protocol KitoVideoDataFetching: Sendable {
    /// Streams `url` straight to `destination` in small chunks (never
    /// buffering the whole clip in memory) and reports 0...1 progress as
    /// bytes land, when the server sends a `Content-Length`.
    func download(_ url: URL, to destination: URL, onProgress: (@Sendable (Double) -> Void)?) async throws
}

public struct URLSessionVideoFetcher: KitoVideoDataFetching {
    /// Bytes buffered before each disk write — small enough that memory use
    /// stays flat regardless of the clip's total size.
    let chunkSize: Int

    public init(chunkSize: Int = 64 * 1024) {
        self.chunkSize = chunkSize
    }

    public func download(_ url: URL, to destination: URL, onProgress: (@Sendable (Double) -> Void)?) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let expected = response.expectedContentLength

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(chunkSize)
        var received: Int64 = 0

        for try await byte in bytes {
            buffer.append(byte)
            received += 1
            if buffer.count >= chunkSize {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 { onProgress?(Double(received) / Double(expected)) }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        onProgress?(1)
    }
}

/// Downloads video straight to disk in small chunks and caches the result
/// under the source URL — request de-duplication and the "different link =
/// fresh download" rule both work exactly like `KitoImageLoader`. Playback
/// reads the cached file directly; nothing is ever fully buffered in memory.
public actor KitoVideoLoader {
    public static let shared = KitoVideoLoader()

    public let cache: KitoVideoDiskCache
    private let fetcher: KitoVideoDataFetching
    private var inFlight: [URL: Task<URL, Error>] = [:]

    public init(cache: KitoVideoDiskCache = KitoVideoDiskCache(), fetcher: KitoVideoDataFetching = URLSessionVideoFetcher()) {
        self.cache = cache
        self.fetcher = fetcher
    }

    /// A local file URL playable by `AVPlayer` — from cache if this exact
    /// URL was already downloaded, otherwise streamed to disk now.
    public func localFile(for url: URL, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        let key = url.absoluteString
        let ext = url.pathExtension

        if let cached = await cache.cachedFile(for: key, sourceExtension: ext) {
            return cached
        }
        if let task = inFlight[url] {
            return try await task.value
        }

        let cache = self.cache
        let fetcher = self.fetcher
        let task = Task<URL, Error> {
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try await fetcher.download(url, to: tempFile, onProgress: onProgress)
            return await cache.commit(tempFile: tempFile, for: key, sourceExtension: ext)
        }

        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }
}
