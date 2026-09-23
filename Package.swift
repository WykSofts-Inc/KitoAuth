// swift-tools-version: 5.9
//
//  Package.swift
//  KitoAuth
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "KitoAuth",
    platforms: [.iOS(.v17)],
    products: [.library(name: "KitoAuth", targets: ["KitoAuth"])],
    dependencies: [
        .package(url: "https://github.com/WykSofts-Inc/KitoCore.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "KitoAuth", dependencies: [.product(name: "KitoCore", package: "KitoCore")]),
        .testTarget(name: "KitoAuthTests", dependencies: ["KitoAuth"]),
    ]
)
