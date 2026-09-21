//
//  KitoCachedVideoView.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/21/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import AVKit
import KitoCore
import KitoLoaders

/// A cache-backed looping video view — the video equivalent of
/// `KitoImageView`. Shows a placeholder while `url` downloads to disk (once,
/// in small chunks — see `KitoVideoLoader`), then plays the cached local
/// file. Re-fetches only when `url` itself changes.
public struct KitoCachedVideoView: View {
    @Environment(\.kitoTheme) private var theme

    let url: URL?
    let loader: KitoVideoLoader
    let placeholderStyle: KitoImagePlaceholderStyle
    let loop: Bool
    let muted: Bool

    @State private var state: LoadState = .loading(progress: nil)

    private enum LoadState {
        case loading(progress: Double?)
        case ready(URL)
        case failure
    }

    public init(
        url: URL?,
        loader: KitoVideoLoader = .shared,
        placeholderStyle: KitoImagePlaceholderStyle = .progressRing,
        loop: Bool = true,
        muted: Bool = true
    ) {
        self.url = url
        self.loader = loader
        self.placeholderStyle = placeholderStyle
        self.loop = loop
        self.muted = muted
    }

    public var body: some View {
        ZStack {
            switch state {
            case .loading(let progress):
                placeholder(progress: progress)
            case .ready(let localURL):
                KitoLoopingPlayerView(url: localURL, loop: loop, muted: muted)
            case .failure:
                Image(systemName: "video.slash")
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
            let localURL = try await loader.localFile(for: url) { fraction in
                Task { @MainActor in
                    if case .loading = state {
                        state = .loading(progress: fraction)
                    }
                }
            }
            state = .ready(localURL)
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

struct KitoLoopingPlayerView: UIViewControllerRepresentable {
    let url: URL
    let loop: Bool
    let muted: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        player.isMuted = muted
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        if loop {
            context.coordinator.observe(player: player)
        }
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private var token: NSObjectProtocol?
        private weak var player: AVPlayer?

        func observe(player: AVPlayer) {
            self.player = player
            token = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }

        func stop() {
            if let token {
                NotificationCenter.default.removeObserver(token)
            }
            player?.pause()
        }
    }
}
