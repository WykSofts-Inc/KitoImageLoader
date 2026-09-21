//
//  KitoImagePlaceholderStyle.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/21/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

/// What `KitoImageView` shows while an image is loading — every case maps
/// onto an existing `KitoLoaders` component, so the "what does loading look
/// like" choice is the same one already used everywhere else in the app.
public enum KitoImagePlaceholderStyle: Sendable, CaseIterable {
    case none
    case spinner
    case dots
    case pulse
    /// A determinate ring — only shows a real percentage when the server
    /// sends a `Content-Length` header; falls back to an indeterminate ring
    /// otherwise.
    case progressRing
    case skeleton

    public var label: String {
        switch self {
        case .none: return "None"
        case .spinner: return "Spinner"
        case .dots: return "Dots"
        case .pulse: return "Pulse"
        case .progressRing: return "Progress ring"
        case .skeleton: return "Skeleton"
        }
    }
}
