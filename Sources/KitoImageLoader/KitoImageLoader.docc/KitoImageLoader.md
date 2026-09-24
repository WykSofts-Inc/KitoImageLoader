# ``KitoImageLoader``

A cache-backed image and video loader for SwiftUI with request de-duplication and configurable loading placeholders.

## Overview

`AsyncImage` fetches again every time its host view is recreated, so scrolling a
`List` downloads the same URL each time a cell comes back on screen.
KitoImageLoader caches by URL for the whole app lifetime, checking memory
first, then disk, then the network, and de-duplicates concurrent requests:
several cells asking for the same URL at once trigger exactly one fetch.

The URL is the cache key. A different link is automatically a cache miss and a
fresh fetch, so there is no separate invalidation call to remember.

```swift
import KitoImageLoader

KitoImageView(url: product.imageURL, placeholderStyle: .progressRing) { image in
    image.resizable().scaledToFill()
}
.frame(height: 220)
.clipShape(RoundedRectangle(cornerRadius: 16))
```

``KitoRemoteImage`` adds shimmer or blur-up loading, an animated reveal, quiet
retries with backoff, and a tap-to-retry failure state. The package also
includes avatars with initials fallbacks, a zoomable image and full-screen
viewer, and a masonry layout. For video, ``KitoVideoLoader`` streams a clip to
disk in small chunks and caches the file under its source URL, and
``KitoCachedVideoView`` plays it on a silent, looping player with no controls.

Warm the cache ahead of time with the `kitoPrefetchImages(_:loader:)` view
modifier, or call the loader directly.

## Topics

### Images

- ``KitoImageView``
- ``KitoRemoteImage``
- ``KitoImagePlaceholderStyle``
- ``KitoImageLoadingStyle``
- ``KitoImageAppearance``
- ``KitoImageFailureStyle``
- ``KitoImageRetryPolicy``
- ``KitoShimmerPlaceholder``

### Avatars

- ``KitoImageAvatar``
- ``KitoImageAvatarStack``
- ``KitoAvatarPerson``
- ``KitoAvatarRing``
- ``KitoAvatarStatus``
- ``KitoAvatarInitials``

### Zoom, Viewer, and Layout

- ``KitoZoomableImage``
- ``KitoImageViewer``
- ``KitoZoom``
- ``KitoMasonryLayout``
- ``KitoMasonry``

### Video

- ``KitoCachedVideoView``
- ``KitoVideoLoader``
- ``KitoVideoDiskCache``
- ``KitoVideoDataFetching``
- ``URLSessionVideoFetcher``

### Loading and Caching

- ``KitoImageLoader/KitoImageLoader``
- ``KitoDiskImageCache``
- ``KitoImageCacheStats``
- ``KitoImageDataFetching``
- ``URLSessionImageFetcher``
- ``KitoImageLoaderError``
