//
//  KitoImageView.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/21/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore
import KitoLoaders

/// A cache-backed replacement for `AsyncImage` — the same URL loads once and
/// stays cached (memory, then disk) across every view that asks for it,
/// instead of `AsyncImage` re-fetching every time its host view is
/// recreated. Cancels its load automatically when `url` changes or the view
/// disappears (plain structured-concurrency `.task(id:)`).
public struct KitoImageView<Content: View>: View {
    @Environment(\.kitoTheme) private var theme

    let url: URL?
    let loader: KitoImageLoader
    let placeholderStyle: KitoImagePlaceholderStyle
    let content: (Image) -> Content

    @State private var state: LoadState = .loading(progress: nil)

    private enum LoadState {
        case loading(progress: Double?)
        case success(UIImage)
        case failure
    }

    public init(
        url: URL?,
        loader: KitoImageLoader = .shared,
        placeholderStyle: KitoImagePlaceholderStyle = .spinner,
        @ViewBuilder content: @escaping (Image) -> Content = { $0.resizable() }
    ) {
        self.url = url
        self.loader = loader
        self.placeholderStyle = placeholderStyle
        self.content = content
    }

    public var body: some View {
        ZStack {
            switch state {
            case .loading(let progress):
                placeholder(progress: progress)
            case .success(let image):
                content(Image(uiImage: image))
            case .failure:
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.colors.onBackground.opacity(0.3))
            }
        }
        .task(id: url) { await load() }
    }

    @MainActor
    private func load() async {
        guard let url else {
            state = .failure
            return
        }
        state = .loading(progress: nil)
        do {
            let image = try await loader.image(for: url) { fraction in
                Task { @MainActor in
                    if case .loading = state {
                        state = .loading(progress: fraction)
                    }
                }
            }
            state = .success(image)
        } catch {
            state = .failure
        }
    }

    @ViewBuilder
    private func placeholder(progress: Double?) -> some View {
        switch placeholderStyle {
        case .none:
            Color.clear
        case .spinner:
            KitoSpinner()
        case .dots:
            KitoDotsLoader()
        case .pulse:
            KitoPulseLoader()
        case .progressRing:
            if let progress {
                KitoProgressRing(fraction: progress)
            } else {
                KitoSpinner()
            }
        case .skeleton:
            KitoSkeleton()
        }
    }
}
