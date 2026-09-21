// swift-tools-version: 5.9
//
//  Package.swift
//  KitoImageLoader
//
//  Created by Wycliff on 9/21/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "KitoImageLoader",
    platforms: [.iOS(.v17)],
    products: [.library(name: "KitoImageLoader", targets: ["KitoImageLoader"])],
    dependencies: [
        .package(url: "https://github.com/WykSofts-Inc/KitoCore.git", from: "1.0.0"),
        .package(url: "https://github.com/WykSofts-Inc/KitoLoaders.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "KitoImageLoader",
            dependencies: [
                .product(name: "KitoCore", package: "KitoCore"),
                .product(name: "KitoLoaders", package: "KitoLoaders"),
            ]
        ),
        .testTarget(name: "KitoImageLoaderTests", dependencies: ["KitoImageLoader"]),
    ]
)
