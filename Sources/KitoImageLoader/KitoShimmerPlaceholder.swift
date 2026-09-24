//
//  KitoShimmerPlaceholder.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// A muted surface with a diagonal band of light sweeping across it — the loading state for
/// images and cards. Reduce Motion keeps the surface still.
public struct KitoShimmerPlaceholder: View {
    @Environment(\.kitoTheme) private var theme
    let tint: Color?

    public init(tint: Color? = nil) {
        self.tint = tint
    }

    public var body: some View {
        (tint ?? theme.colors.surfaceMuted)
            .kitoImageShimmer()
            .accessibilityLabel("Loading")
    }
}

public extension View {
    /// Sweeps a soft highlight across this view while `isActive` — for skeleton cards and
    /// placeholders. Reduce Motion turns the sweep off.
    func kitoImageShimmer(isActive: Bool = true, duration: Double = 1.4) -> some View {
        modifier(KitoImageShimmerModifier(isActive: isActive, duration: duration))
    }
}

private struct KitoImageShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let isActive: Bool
    let duration: Double

    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive && !reduceMotion {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        LinearGradient(
                            colors: [.clear, .white.opacity(colorScheme == .dark ? 0.12 : 0.45), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(width * 0.7, 60))
                        .rotationEffect(.degrees(18))
                        .offset(x: phase * (width + max(width * 0.7, 60)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .offset(x: -max(width * 0.35, 30))
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .onAppear {
                        phase = -1
                        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) { phase = 1 }
                    }
                }
            }
    }
}
