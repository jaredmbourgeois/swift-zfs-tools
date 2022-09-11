// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swift-zfs-tools",
  platforms: [
    .macOS(.v12),
    .custom("Ubuntu", versionString: "18.0.4")
  ],
  products: [
    .executable(
      name: "swift-zfs-tools",
      targets: ["swift-zfs-tools"]
    )
  ],
  dependencies: [
    .package(
      url: "https://github.com/jaredmbourgeois/swift-shell",
      from: "1.0.7"
    ),
    .package(
      url: "https://github.com/apple/swift-algorithms",
      from: "1.0.0"
    )
  ],
  targets: [
    .executableTarget(
      name: "swift-zfs-tools",
      dependencies: [
        .product(name: "Shell", package: "swift-shell"),
        .product(name: "Algorithms", package: "swift-algorithms")
      ]
    ),
    .testTarget(
        name: "swift-zfs-tools-tests",
        dependencies: ["swift-zfs-tools"]
    )
  ]
)
