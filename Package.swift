// Package.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-zfs-tools",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        Product.builder.product,
        Product.command.product,
        Product.model.product,
    ],
    dependencies: [
        Dependency.argumentParser.packageDependency,
        Dependency.shell.packageDependency,
    ],
    targets: [
        Product.builder.target,
        Product.command.target,
        Product.model.target,
        Product.tests.target,
    ]
)

enum Dependency: String {
    case argumentParser
    case shell

    var name: String {
        switch self {
        case .argumentParser: "ArgumentParser"
        case .shell: "Shell"
        }
    }

    var package: String {
        switch self {
        case .argumentParser: "swift-argument-parser"
        case .shell: "swift-shell"
        }
    }

    var packageDependency: Package.Dependency {
        .package(url: packageURL, exact: .init(stringLiteral: packageVersion))
    }

    var packageURL: String {
        switch self {
        case .argumentParser: "https://github.com/apple/\(package).git"
        case .shell: "https://github.com/jaredmbourgeois/\(package).git"
        }
    }

    var packageVersion: String {
        switch self {
        case .argumentParser: "1.5.0"
        case .shell: "2.0.0"
        }
    }

    var targetDependency: Target.Dependency {
        switch self {
        case .argumentParser: .product(name: name, package: package)
        case .shell: .product(name: name, package: package)
        }
    }
}

enum Product: String {
    case builder
    case command
    case model
    case tests

    var name: String {
        switch self {
        case .builder: "ZFSToolsBuilder"
        case .command: "ZFSTools"
        case .model: "ZFSToolsModel"
        case .tests: "ZFSToolsTests"
        }
    }

    var path: String {
        switch self {
        case .tests: rawValue
        default: "sources/\(rawValue)"
        }
    }

    var product: PackageDescription.Product {
        switch self {
        case .builder: .executable(name: name, targets: [name])
        case .command: .executable(name: name, targets: [name])
        case .model: .library(name: name, targets: [name])
        case .tests: .library(name: name, targets: [name])
        }
    }

    static let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

    var target: PackageDescription.Target {
        switch self {
        case .builder, .command:
            .executableTarget(
                name: name,
                dependencies: [
                    Dependency.argumentParser.targetDependency,
                    Dependency.shell.targetDependency,
                    .target(name: Product.model.name),
                ],
                path: path,
                swiftSettings: Self.swiftSettings
            )
        case .model:
            .target(
                name: name,
                dependencies: [
                    Dependency.argumentParser.targetDependency,
                    Dependency.shell.targetDependency,
                ],
                path: path,
                swiftSettings: Self.swiftSettings
            )
        case .tests:
            .testTarget(
                name: name,
                dependencies: [
                    .product(name: Dependency.argumentParser.name, package: Dependency.argumentParser.package),
                    .product(name: Dependency.shell.name, package: Dependency.shell.package),
                    .target(name: Product.command.name),
                    .target(name: Product.model.name),
                ],
                path: path,
                resources: [
                    .copy("resource")
                ],
                swiftSettings: Self.swiftSettings
            )
        }
    }
}
