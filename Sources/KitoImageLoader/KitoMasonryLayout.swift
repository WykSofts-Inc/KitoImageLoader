//
//  KitoMasonryLayout.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI

/// The placement rule behind `KitoMasonryLayout`, kept pure so it's testable: each item goes
/// into whichever column is currently shortest, so columns stay close to even.
public enum KitoMasonry {
    /// For items of the given `heights`, the column each one lands in.
    public static func columnAssignments(heights: [CGFloat], columns: Int, spacing: CGFloat = 0) -> [Int] {
        let count = max(columns, 1)
        var columnHeights = Array(repeating: CGFloat(0), count: count)
        return heights.map { height in
            let column = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] } ?? 0
            columnHeights[column] += height + (columnHeights[column] > 0 ? spacing : 0)
            return column
        }
    }

    /// The tallest column's height once every item is placed.
    public static func totalHeight(heights: [CGFloat], columns: Int, spacing: CGFloat = 0) -> CGFloat {
        let count = max(columns, 1)
        var columnHeights = Array(repeating: CGFloat(0), count: count)
        for (index, column) in columnAssignments(heights: heights, columns: count, spacing: spacing).enumerated() {
            columnHeights[column] += heights[index] + (columnHeights[column] > 0 ? spacing : 0)
        }
        return columnHeights.max() ?? 0
    }
}

/// A Pinterest-style masonry `Layout`: children keep their own heights (give each an
/// `.aspectRatio`) and flow into the shortest column.
///
/// ```swift
/// ScrollView {
///     KitoMasonryLayout(columns: 2, spacing: 10) {
///         ForEach(photos) { photo in
///             KitoRemoteImage(url: photo.url).aspectRatio(photo.aspect, contentMode: .fit)
///         }
///     }
/// }
/// ```
public struct KitoMasonryLayout: Layout {
    public var columns: Int
    public var spacing: CGFloat

    public init(columns: Int = 2, spacing: CGFloat = 10) {
        self.columns = max(columns, 1)
        self.spacing = spacing
    }

    private func columnWidth(for width: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func heights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let itemHeights = heights(subviews, width: columnWidth(for: width))
        return CGSize(width: width, height: KitoMasonry.totalHeight(heights: itemHeights, columns: columns, spacing: spacing))
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = columnWidth(for: bounds.width)
        let itemHeights = heights(subviews, width: width)
        let assignments = KitoMasonry.columnAssignments(heights: itemHeights, columns: columns, spacing: spacing)
        var columnHeights = Array(repeating: CGFloat(0), count: columns)
        for (index, subview) in subviews.enumerated() {
            let column = assignments[index]
            let x = bounds.minX + CGFloat(column) * (width + spacing)
            let y = bounds.minY + columnHeights[column] + (columnHeights[column] > 0 ? spacing : 0)
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: itemHeights[index]))
            columnHeights[column] = y - bounds.minY + itemHeights[index]
        }
    }
}

public extension View {
    /// Warms the image cache for `urls` when this view appears — the next screen's photos, the
    /// rest of a carousel.
    func kitoPrefetchImages(_ urls: [URL], loader: KitoImageLoader = .shared) -> some View {
        task(id: urls) { await loader.prefetch(urls) }
    }
}
