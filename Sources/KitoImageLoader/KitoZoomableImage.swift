//
//  KitoZoomableImage.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// Zoom maths shared by the zoomable views, kept pure so it's testable.
public enum KitoZoom {
    /// Clamps a pinch scale into `range`, with a little rubber-band give past either end.
    public static func clamp(_ scale: CGFloat, to range: ClosedRange<CGFloat>, rubberBand: Bool = true) -> CGFloat {
        guard rubberBand else { return min(max(scale, range.lowerBound), range.upperBound) }
        if scale < range.lowerBound { return range.lowerBound - (range.lowerBound - scale) * 0.3 }
        if scale > range.upperBound { return range.upperBound + (scale - range.upperBound) * 0.3 }
        return scale
    }

    /// The furthest an image of `size` scaled by `scale` can pan before its edge leaves the frame.
    public static func maxOffset(for size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(0, (size.width * scale - size.width) / 2), height: max(0, (size.height * scale - size.height) / 2))
    }

    /// Keeps `offset` inside `maxOffset(for:scale:)`.
    public static func clampOffset(_ offset: CGSize, size: CGSize, scale: CGFloat) -> CGSize {
        let limit = maxOffset(for: size, scale: scale)
        return CGSize(width: min(max(offset.width, -limit.width), limit.width), height: min(max(offset.height, -limit.height), limit.height))
    }
}

/// A remote image you can pinch to zoom, pan when zoomed, and double-tap to zoom in or back out.
/// Springs back inside its bounds when released.
public struct KitoZoomableImage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let url: URL?
    let loader: KitoImageLoader
    let maxScale: CGFloat
    let onZoomChange: ((Bool) -> Void)?

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    public init(url: URL?, loader: KitoImageLoader = .shared, maxScale: CGFloat = 4, onZoomChange: ((Bool) -> Void)? = nil) {
        self.url = url
        self.loader = loader
        self.maxScale = maxScale
        self.onZoomChange = onZoomChange
    }

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82) }

    public var body: some View {
        GeometryReader { proxy in
            KitoRemoteImage(url: url, loader: loader, loading: .shimmer, appearance: .fade, contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(magnify(in: proxy.size).simultaneously(with: pan(in: proxy.size)))
                .onTapGesture(count: 2) { location in toggleZoom(at: location, in: proxy.size) }
        }
        .onChange(of: scale > 1.01) { _, zoomed in onZoomChange?(zoomed) }
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityAction(named: scale > 1 ? "Zoom out" : "Zoom in") {
            withAnimation(spring) {
                scale = scale > 1 ? 1 : 2.5
                baseScale = scale
                offset = .zero
                baseOffset = .zero
            }
        }
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = KitoZoom.clamp(baseScale * value.magnification, to: 1...maxScale)
            }
            .onEnded { _ in
                withAnimation(spring) {
                    scale = KitoZoom.clamp(scale, to: 1...maxScale, rubberBand: false)
                    offset = KitoZoom.clampOffset(offset, size: size, scale: scale)
                }
                baseScale = scale
                baseOffset = offset
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: scale > 1 ? 0 : 10_000)
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: baseOffset.width + value.translation.width, height: baseOffset.height + value.translation.height)
            }
            .onEnded { _ in
                withAnimation(spring) { offset = KitoZoom.clampOffset(offset, size: size, scale: scale) }
                baseOffset = offset
            }
    }

    private func toggleZoom(at location: CGPoint, in size: CGSize) {
        withAnimation(spring) {
            if scale > 1 {
                scale = 1
                offset = .zero
            } else {
                scale = min(2.5, maxScale)
                let target = CGSize(width: (size.width / 2 - location.x) * (scale - 1), height: (size.height / 2 - location.y) * (scale - 1))
                offset = KitoZoom.clampOffset(target, size: size, scale: scale)
            }
        }
        baseScale = scale
        baseOffset = offset
    }
}

/// A full-screen photo viewer: swipe between images, pinch or double-tap to zoom, drag down to
/// dismiss (the backdrop fades as you drag). Present it with `.fullScreenCover` or overlay it.
///
/// ```swift
/// .fullScreenCover(item: $openedIndex) { index in
///     KitoImageViewer(urls: photos, startIndex: index.value) { openedIndex = nil }
/// }
/// ```
public struct KitoImageViewer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let urls: [URL]
    let captions: [String]
    let loader: KitoImageLoader
    let onDismiss: () -> Void

    @State private var index: Int
    @State private var dragOffset: CGFloat = 0
    @State private var isZoomed = false
    @State private var showsChrome = true

    public init(urls: [URL], startIndex: Int = 0, captions: [String] = [], loader: KitoImageLoader = .shared, onDismiss: @escaping () -> Void) {
        self.urls = urls
        self.captions = captions
        self.loader = loader
        self.onDismiss = onDismiss
        _index = State(initialValue: min(max(startIndex, 0), max(urls.count - 1, 0)))
    }

    private var dismissProgress: CGFloat { min(abs(dragOffset) / 300, 1) }

    public var body: some View {
        ZStack {
            Color.black.opacity(1 - dismissProgress * 0.8).ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { position, url in
                    KitoZoomableImage(url: url, loader: loader) { zoomed in isZoomed = zoomed }
                        .tag(position)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset)
            .scaleEffect(1 - dismissProgress * 0.15)
            .simultaneousGesture(dismissDrag)
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showsChrome.toggle() } }

            if showsChrome { chrome.transition(.opacity) }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(!showsChrome)
        .onAppear { loader.prefetch(urls) }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !isZoomed, abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard !isZoomed else { return }
                if abs(value.translation.height) > 140 || abs(value.predictedEndTranslation.height) > 400 {
                    onDismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { dragOffset = 0 }
                }
            }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Text("\(index + 1) of \(urls.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 12) {
                if captions.indices.contains(index) {
                    Text(captions[index])
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                if urls.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(urls.indices, id: \.self) { dot in
                            Capsule()
                                .fill(.white.opacity(dot == index ? 1 : 0.35))
                                .frame(width: dot == index ? 18 : 6, height: 6)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
                    .accessibilityHidden(true)
                }
            }
            .padding(.bottom, 24)
        }
        .opacity(1 - dismissProgress)
    }
}
