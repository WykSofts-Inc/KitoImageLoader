//
//  KitoImageDataFetching.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/21/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// The network seam `KitoImageLoader` downloads through. Swapping this in
/// tests (instead of hitting `URLSession.shared` for real) is what makes
/// request-count/dedup behavior actually testable.
public protocol KitoImageDataFetching: Sendable {
    func fetch(_ url: URL, onProgress: (@Sendable (Double) -> Void)?) async throws -> Data
}

/// The real implementation — streams the response via `URLSession.bytes(from:)`
/// so `onProgress` can report a live 0...1 fraction as bytes arrive, instead
/// of only learning the size after the whole download completes.
public struct URLSessionImageFetcher: KitoImageDataFetching {
    public init() {}

    public func fetch(_ url: URL, onProgress: (@Sendable (Double) -> Void)?) async throws -> Data {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let expected = response.expectedContentLength
        var data = Data()
        if expected > 0 { data.reserveCapacity(Int(expected)) }
        var received: Int64 = 0

        for try await byte in bytes {
            data.append(byte)
            received += 1
            if expected > 0 {
                onProgress?(Double(received) / Double(expected))
            }
        }
        onProgress?(1)
        return data
    }
}
