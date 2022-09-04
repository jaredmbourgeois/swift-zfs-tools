// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
//    name: "swift-zfs-tools",
//    products: [
//        // Products define the executables and libraries a package produces, and make them visible to other packages.
//        .library(
//            name: "swift-zfs-tools",
//            targets: ["swift-zfs-tools"]),
//    ],
//    dependencies: [
//        // Dependencies declare other packages that this package depends on.
//        // .package(url: /* package url */, from: "1.0.0"),
//    ],
//    targets: [
//        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
//        // Targets can depend on other targets in this package, and on products in packages this package depends on.
//        .target(
//            name: "swift-zfs-tools",
//            dependencies: []),
//        .testTarget(
//            name: "swift-zfs-toolsTests",
//            dependencies: ["swift-zfs-tools"]),
//    ]
    name: "swift-zfs-tools",
    platforms: [
      .macOS(.v12),
      .custom("Ubuntu", versionString: "18.0.4")
    ],
    products: [
        .library(
            name: "swift-zfs-tools",
            targets: ["swift-zfs-tools"]
        ),
    ],
    dependencies: [
        .package(
          url: "https://github.com/jaredmbourgeois/swift-shell",
          from: "1.0.5"
        ),
        .package(
          url: "https://github.com/apple/swift-algorithms",
          from: "1.0.0"
        )
    ],
    targets: [
        .target(
            name: "swift-zfs-tools",
            dependencies: [
              .product(name: "Shell", package: "swift-shell"),
              .product(name: "Algorithms", package: "swift-algorithms")
            ]
        ),
        .testTarget(
            name: "swift-zfs-tools-tests",
            dependencies: ["swift-zfs-tools"]
        ),
    ]
)
