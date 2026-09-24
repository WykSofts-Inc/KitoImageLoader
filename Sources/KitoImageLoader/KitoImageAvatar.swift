//
//  KitoImageAvatar.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// Initials and a stable colour for a person with no photo (or whose photo won't load).
public enum KitoAvatarInitials {
    /// "WN" for "Wycliff Njenga", "W" for "Wycliff", "AM" for "amara  mwangi otieno" — first
    /// letters of the first and last words, uppercased.
    public static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).filter { $0.first?.isLetter == true }
        guard let first = words.first?.first else { return "?" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }

    /// An index into a palette of `count` colours that stays the same for the same name across
    /// launches (unlike `hashValue`, which is randomised per process).
    public static func paletteIndex(for name: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let hash = name.lowercased().unicodeScalars.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ $1.value }
        return Int(hash % UInt32(count))
    }

    /// The gradients avatars fall back to.
    public static let palettes: [[Color]] = [
        [Color(red: 1.0, green: 0.55, blue: 0.3), Color(red: 0.93, green: 0.27, blue: 0.4)],
        [Color(red: 0.36, green: 0.55, blue: 1.0), Color(red: 0.5, green: 0.3, blue: 0.95)],
        [Color(red: 0.2, green: 0.78, blue: 0.6), Color(red: 0.1, green: 0.52, blue: 0.62)],
        [Color(red: 1.0, green: 0.76, blue: 0.25), Color(red: 0.98, green: 0.45, blue: 0.2)],
        [Color(red: 0.93, green: 0.4, blue: 0.75), Color(red: 0.6, green: 0.3, blue: 0.9)],
        [Color(red: 0.3, green: 0.75, blue: 0.95), Color(red: 0.2, green: 0.45, blue: 0.85)],
    ]
}

/// The ring drawn around an avatar.
public enum KitoAvatarRing: Sendable, Equatable {
    case none
    /// The warm gradient ring of an unseen story. `animates` spins it while loading.
    case story(animates: Bool)
    /// A grey ring for a story already watched.
    case seen
    case solid(Color)
}

/// A presence dot in the corner.
public enum KitoAvatarStatus: String, Sendable, CaseIterable {
    case none
    case online
    case away
    case busy
}

/// A circular, cache-backed profile photo that falls back to initials on a stable gradient —
/// while loading, with no URL, or when the photo fails. Optional story ring and presence dot.
///
/// ```swift
/// KitoImageAvatar(url: user.photoURL, name: "Wycliff N", size: 56, ring: .story(animates: false), status: .online)
/// ```
public struct KitoImageAvatar: View {
    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let url: URL?
    let name: String
    let size: CGFloat
    let ring: KitoAvatarRing
    let status: KitoAvatarStatus
    let loader: KitoImageLoader

    @State private var spin = false

    public init(
        url: URL?,
        name: String,
        size: CGFloat = 48,
        ring: KitoAvatarRing = .none,
        status: KitoAvatarStatus = .none,
        loader: KitoImageLoader = .shared
    ) {
        self.url = url
        self.name = name
        self.size = size
        self.ring = ring
        self.status = status
        self.loader = loader
    }

    private var hasRing: Bool { ring != .none }
    private var ringWidth: CGFloat { max(2, size * 0.05) }
    private var inset: CGFloat { hasRing ? ringWidth * 2.2 : 0 }

    public var body: some View {
        ZStack {
            ringView
            photo
                .frame(width: size - inset * 2, height: size - inset * 2)
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) { statusDot }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status == .none ? name : "\(name), \(status.rawValue)")
        .accessibilityAddTraits(.isImage)
    }

    private var photo: some View {
        let palette = KitoAvatarInitials.palettes[KitoAvatarInitials.paletteIndex(for: name, count: KitoAvatarInitials.palettes.count)]
        return ZStack {
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(KitoAvatarInitials.initials(for: name))
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
            if url != nil {
                KitoRemoteImage(url: url, loader: loader, loading: .color(.clear), appearance: .fade, retry: .standard, failure: .hidden)
            }
        }
    }

    @ViewBuilder
    private var ringView: some View {
        switch ring {
        case .none:
            EmptyView()
        case .story(let animates):
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [.yellow, .orange, .pink, .purple, .orange, .yellow],
                        center: .center
                    ),
                    lineWidth: ringWidth
                )
                .rotationEffect(.degrees(spin ? 360 : 0))
                .onAppear {
                    guard animates, !reduceMotion else { return }
                    withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { spin = true }
                }
        case .seen:
            Circle().strokeBorder(theme.colors.onBackground.opacity(0.2), lineWidth: ringWidth * 0.7)
        case .solid(let color):
            Circle().strokeBorder(color, lineWidth: ringWidth)
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        if status != .none {
            let dot = max(10, size * 0.26)
            Circle()
                .fill(statusColor)
                .frame(width: dot, height: dot)
                .overlay(Circle().stroke(theme.colors.background, lineWidth: max(2, dot * 0.18)))
                .offset(x: hasRing ? -inset * 0.2 : 0, y: hasRing ? -inset * 0.2 : 0)
        }
    }

    private var statusColor: Color {
        switch status {
        case .none: return .clear
        case .online: return theme.colors.success
        case .away: return theme.colors.warning
        case .busy: return theme.colors.danger
        }
    }
}

/// One person in a `KitoImageAvatarStack`.
public struct KitoAvatarPerson: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var photoURL: URL?

    public init(id: String? = nil, name: String, photoURL: URL? = nil) {
        self.id = id ?? name
        self.name = name
        self.photoURL = photoURL
    }
}

/// Overlapping avatars with a "+3" bubble for the rest — who's going, who's in the group.
public struct KitoImageAvatarStack: View {
    @Environment(\.kitoTheme) private var theme
    let people: [KitoAvatarPerson]
    let size: CGFloat
    let maxVisible: Int
    let overlap: CGFloat

    public init(_ people: [KitoAvatarPerson], size: CGFloat = 36, maxVisible: Int = 4, overlap: CGFloat = 0.32) {
        self.people = people
        self.size = size
        self.maxVisible = max(maxVisible, 1)
        self.overlap = overlap
    }

    public var body: some View {
        let visible = Array(people.prefix(maxVisible))
        let extra = people.count - visible.count
        HStack(spacing: -size * overlap) {
            ForEach(visible) { person in
                KitoImageAvatar(url: person.photoURL, name: person.name, size: size)
                    .overlay(Circle().stroke(theme.colors.background, lineWidth: 2.5))
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.colors.onBackground)
                    .frame(width: size, height: size)
                    .background(theme.colors.surfaceMuted, in: Circle())
                    .overlay(Circle().stroke(theme.colors.background, lineWidth: 2.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let names = people.prefix(maxVisible).map(\.name).joined(separator: ", ")
        let extra = people.count - min(people.count, maxVisible)
        return extra > 0 ? "\(names) and \(extra) more" : names
    }
}
