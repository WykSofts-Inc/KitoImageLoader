# KitoImageLoader

A cache-backed image and video loader for SwiftUI — memory → disk → network,
request de-duplication, and configurable loading placeholders drawn from
[KitoLoaders](https://github.com/WykSofts-Inc/KitoLoaders). Part of the
[Kito](https://github.com/WykSofts-Inc/KitoDevKit) ecosystem.

## Why not just `AsyncImage`?

`AsyncImage` re-fetches every time its host view is recreated — scroll a
`List` and the same URL downloads again each time the cell comes back on
screen. `KitoImageLoader` caches by URL across the whole app lifetime
(memory first, then disk), and de-duplicates concurrent requests: ten cells
asking for the same URL at once trigger exactly one network fetch.

Cache invalidation is intentionally simple: **the URL is the cache key.**
A different link is automatically a cache miss and a fresh fetch — there's
no separate "invalidate" call to remember, and no chance of serving stale
bytes for a URL that changed.

## Images

```swift
import KitoImageLoader

KitoImageView(url: product.imageURL, placeholderStyle: .progressRing) { image in
    image.resizable().scaledToFill()
}
.frame(height: 220)
.clipShape(RoundedRectangle(cornerRadius: 16))
```

`placeholderStyle` is any `KitoImagePlaceholderStyle` — `.spinner`, `.dots`,
`.pulse`, `.progressRing` (shows a real percentage when the server sends a
`Content-Length` header), `.skeleton`, or `.none`.

Call the loader directly when you don't need a view — prefetch a list's
next screen of thumbnails, for example:

```swift
KitoImageLoader.shared.prefetch(nextPageImageURLs)
```

## Video

The same model, extended to video: `KitoVideoLoader` streams a clip to disk
in small chunks (never buffering the whole file in memory) and caches the
resulting file under its source URL, exactly like the image loader.
`KitoCachedVideoView` plays the cached file on a silent, looping `AVPlayer`
with no controls — it reads as an illustration, not a video player.

```swift
KitoCachedVideoView(url: heroClipURL, placeholderStyle: .progressRing)
    .frame(height: 260)
```

## Architecture

- `KitoImageLoader` / `KitoVideoLoader` — actors owning an in-memory
  `NSCache` (images only), a disk cache, and in-flight request
  de-duplication.
- `KitoImageDataFetching` / `KitoVideoDataFetching` — the network seam both
  loaders download through, injectable in tests instead of hitting
  `URLSession.shared` for real.
- `KitoDiskImageCache` / `KitoVideoDiskCache` — SHA-256-keyed on-disk
  storage under `Caches/`, pruned oldest-accessed-first once a byte budget
  is exceeded.

## Installation

```swift
.package(url: "https://github.com/WykSofts-Inc/KitoImageLoader.git", from: "1.0.0")
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — open an issue, then a pull request
against `main`. All contributions are reviewed before merge.

## License

MIT — see [LICENSE](LICENSE).
