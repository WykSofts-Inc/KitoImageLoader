//
//  KitoRemoteImage.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore
import KitoLoaders

/// What fills the frame while `KitoRemoteImage` loads.
public enum KitoImageLoadingStyle: Sendable {
    /// A soft band of light sweeping across a muted surface.
    case shimmer
    /// A tiny version of the image (a few KB) shown blurred, then sharpened by the full one.
    case blurUp(preview: URL)
    /// A flat colour — pass the image's dominant colour from your API for a calm load.
    case color(Color)
    /// A gradient, e.g. a brand gradient behind avatars.
    case gradient([Color])
    /// One of the `KitoLoaders` components, on a muted surface.
    case loader(KitoImagePlaceholderStyle)
}

/// How the image arrives once it's loaded. Reduce Motion always uses a plain fade.
public enum KitoImageAppearance: String, Sendable, CaseIterable {
    case none
    case fade
    /// Settles from slightly larger, like a photo dropping into place.
    case scaleIn
    /// Starts blurred and sharpens.
    case blurIn
    /// Rises a few points while fading in.
    case slideUp

    public var label: String {
        switch self {
        case .none: return "None"
        case .fade: return "Fade"
        case .scaleIn: return "Scale in"
        case .blurIn: return "Blur in"
        case .slideUp: return "Slide up"
        }
    }
}

/// What shows when every attempt has failed.
public enum KitoImageFailureStyle: Sendable, CaseIterable {
    /// Icon, message and a Retry button — scaled down to just an icon in small frames.
    case retry
    /// Just an icon.
    case icon
    /// Nothing but the placeholder surface.
    case hidden
}

/// How many times `KitoRemoteImage` quietly retries before showing its failure state, with
/// exponential backoff between attempts.
public struct KitoImageRetryPolicy: Sendable, Equatable {
    public var maxRetries: Int
    public var baseDelay: TimeInterval

    public init(maxRetries: Int = 2, baseDelay: TimeInterval = 0.8) {
        self.maxRetries = max(maxRetries, 0)
        self.baseDelay = max(baseDelay, 0)
    }

    /// Seconds to wait before retry number `retry` (1-based): base, 2×base, 4×base…
    public func delay(beforeRetry retry: Int) -> TimeInterval {
        baseDelay * pow(2, Double(max(retry - 1, 0)))
    }

    public static let none = KitoImageRetryPolicy(maxRetries: 0)
    public static let standard = KitoImageRetryPolicy()
    public static let persistent = KitoImageRetryPolicy(maxRetries: 5, baseDelay: 0.5)
}

/// A cache-backed remote image with the polish a showcase needs: shimmer or blur-up while
/// loading, an animated reveal, automatic retries with backoff and a tap-to-retry failure
/// state. Fills whatever frame you give it and clips to it — size and shape it from outside.
///
/// ```swift
/// KitoRemoteImage(url: listing.photoURL, loading: .blurUp(preview: listing.thumbURL), appearance: .scaleIn)
///     .frame(height: 240)
///     .clipShape(RoundedRectangle(cornerRadius: 24))
/// ```
public struct KitoRemoteImage: View {
    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let url: URL?
    let loader: KitoImageLoader
    let loading: KitoImageLoadingStyle
    let appearance: KitoImageAppearance
    let retry: KitoImageRetryPolicy
    let failure: KitoImageFailureStyle
    let contentMode: ContentMode
    let accessibilityLabel: String?

    @State private var image: UIImage?
    @State private var preview: UIImage?
    @State private var revealed = false
    @State private var failed = false
    @State private var progress: Double?
    @State private var retryToken = 0

    public init(
        url: URL?,
        loader: KitoImageLoader = .shared,
        loading: KitoImageLoadingStyle = .shimmer,
        appearance: KitoImageAppearance = .fade,
        retry: KitoImageRetryPolicy = .standard,
        failure: KitoImageFailureStyle = .retry,
        contentMode: ContentMode = .fill,
        accessibilityLabel: String? = nil
    ) {
        self.url = url
        self.loader = loader
        self.loading = loading
        self.appearance = appearance
        self.retry = retry
        self.failure = failure
        self.contentMode = contentMode
        self.accessibilityLabel = accessibilityLabel
    }

    private struct LoadKey: Equatable {
        let url: URL?
        let token: Int
    }

    public var body: some View {
        Color.clear
            .overlay { placeholder.opacity(revealed ? 0 : 1) }
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .modifier(KitoRevealModifier(appearance: reduceMotion && appearance != .none ? .fade : appearance, revealed: revealed))
                }
            }
            .overlay { if failed { failureView } }
            .clipped()
            .task(id: LoadKey(url: url, token: retryToken)) { await load() }
            .task(id: previewURL) { await loadPreview() }
            .accessibilityElement(children: failed ? .contain : .ignore)
            .accessibilityLabel(accessibilityLabel ?? "Image")
            .accessibilityAddTraits(.isImage)
    }

    // MARK: Loading

    private var previewURL: URL? {
        if case .blurUp(let preview) = loading { return preview }
        return nil
    }

    @MainActor
    private func load() async {
        guard let url else {
            failed = true
            return
        }
        if let cached = loader.cachedImage(for: url) {
            image = cached
            revealed = true
            failed = false
            return
        }
        image = nil
        revealed = false
        failed = false
        progress = nil

        var retries = 0
        while !Task.isCancelled {
            do {
                let loaded = try await loader.image(for: url) { fraction in
                    Task { @MainActor in progress = fraction }
                }
                image = loaded
                // Let the image render once hidden, then animate it in.
                await Task.yield()
                withAnimation(appearance == .none ? nil : .easeOut(duration: 0.5)) { revealed = true }
                return
            } catch {
                if Task.isCancelled { return }
                retries += 1
                guard retries <= retry.maxRetries else {
                    withAnimation(.easeOut(duration: 0.25)) { failed = true }
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(retry.delay(beforeRetry: retries) * 1_000_000_000))
            }
        }
    }

    @MainActor
    private func loadPreview() async {
        preview = nil
        guard let previewURL else { return }
        if let loaded = try? await loader.image(for: previewURL), image == nil || !revealed {
            withAnimation(.easeOut(duration: 0.25)) { preview = loaded }
        }
    }

    // MARK: Placeholder

    @ViewBuilder
    private var placeholder: some View {
        switch loading {
        case .shimmer:
            KitoShimmerPlaceholder()
        case .blurUp:
            ZStack {
                KitoShimmerPlaceholder()
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .blur(radius: 14, opaque: true)
                        .scaleEffect(1.08)
                        .transition(.opacity)
                }
            }
        case .color(let color):
            color
        case .gradient(let colors):
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        case .loader(let style):
            ZStack {
                theme.colors.surfaceMuted
                loaderView(style)
            }
        }
    }

    @ViewBuilder
    private func loaderView(_ style: KitoImagePlaceholderStyle) -> some View {
        switch style {
        case .none: EmptyView()
        case .spinner: KitoSpinner()
        case .dots: KitoDotsLoader()
        case .pulse: KitoPulseLoader()
        case .progressRing:
            if let progress { KitoProgressRing(fraction: progress) } else { KitoSpinner() }
        case .skeleton: KitoSkeleton(cornerRadius: 0)
        }
    }

    // MARK: Failure

    @ViewBuilder
    private var failureView: some View {
        switch failure {
        case .hidden:
            EmptyView()
        case .icon:
            failureIcon
        case .retry:
            ViewThatFits {
                VStack(spacing: 10) {
                    failureIcon
                    Text("Couldn't load image")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.colors.onBackground.opacity(0.7))
                    retryButton(compact: false)
                }
                .padding(12)
                retryButton(compact: true)
                failureIcon
            }
        }
    }

    private var failureIcon: some View {
        Image(systemName: "wifi.exclamationmark")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(theme.colors.onBackground.opacity(0.45))
            .accessibilityLabel("Image failed to load")
    }

    private func retryButton(compact: Bool) -> some View {
        Button {
            retryToken += 1
        } label: {
            Label("Retry", systemImage: "arrow.clockwise")
                .labelStyle(KitoRetryLabelStyle(compact: compact))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.colors.onPrimary)
                .padding(.horizontal, compact ? 8 : 14)
                .padding(.vertical, compact ? 8 : 7)
                .background(theme.colors.primary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry loading image")
    }
}

private struct KitoRetryLabelStyle: LabelStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        if compact {
            configuration.icon
        } else {
            HStack(spacing: 5) {
                configuration.icon
                configuration.title
            }
        }
    }
}

/// Hides the image until `revealed`, then animates it in the chosen way.
struct KitoRevealModifier: ViewModifier {
    let appearance: KitoImageAppearance
    let revealed: Bool

    func body(content: Content) -> some View {
        switch appearance {
        case .none:
            content.opacity(revealed ? 1 : 0)
        case .fade:
            content.opacity(revealed ? 1 : 0)
        case .scaleIn:
            content.opacity(revealed ? 1 : 0).scaleEffect(revealed ? 1 : 1.12)
        case .blurIn:
            content.opacity(revealed ? 1 : 0).blur(radius: revealed ? 0 : 18)
        case .slideUp:
            content.opacity(revealed ? 1 : 0).offset(y: revealed ? 0 : 14)
        }
    }
}
