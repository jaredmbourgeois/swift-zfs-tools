// swift-tools-version: 5.8

import PackageDescription

enum Dependency: String {
  case algorithms
  case argumentParser
  case shell

  var name: String {
    switch self {
    case .algorithms: return "Algorithms"
    case .argumentParser: return "ArgumentParser"
    case .shell: return "Shell"
    }
  }

  var package: String {
    switch self {
    case .algorithms: return "swift-algorithms"
    case .argumentParser: return "swift-argument-parser"
    case .shell: return "swift-shell"
    }
  }

  var packageDependency: Package.Dependency {
    .package(url: packageURL, exact: .init(stringLiteral: packageVersion))
  }

  var packageURL: String {
    switch self {
    case .algorithms: return "https://github.com/apple/\(package).git"
    case .argumentParser: return "https://github.com/apple/\(package).git"
    case .shell: return "https://github.com/jaredmbourgeois/\(package).git"
    }
  }

  var packageVersion: String {
    switch self {
    case .algorithms: return "1.0.0"
    case .argumentParser: return "1.2.2"
    case .shell: return "1.1.1"
    }
  }

  var targetDependency: Target.Dependency {
    switch self {
    case .algorithms: return .product(name: name, package: package)
    case .argumentParser: return .product(name: name, package: package)
    case .shell: return .product(name: name, package: package)
    }
  }
}

enum Product: String {
  case command
  case model
  case tests

  var name: String {
    switch self {
    case .command: return "ZFSTools"
    case .model: return "ZFSToolsModel"
    case .tests: return "ZFSToolsTests"
    }
  }

  var path: String {
    switch self {
    case .tests: return rawValue
    default: return "sources/\(rawValue)"
    }
  }

  var product: PackageDescription.Product {
    switch self {
    case .command: return .executable(
      name: name,
      targets: [name]
    )
    case .model: return .library(
      name: name,
      targets: [name]
    )
    case .tests: return .library(
      name: name,
      targets: [name]
    )
    }
  }

  var target: PackageDescription.Target {
    switch self {
    case .command: return .executableTarget(
      name: name,
      dependencies: [
        Dependency.argumentParser.targetDependency,
        Dependency.shell.targetDependency,
        .target(name: Product.model.name),
      ],
      path: path
    )
    case .model: return .target(
      name: name,
      dependencies: [
        Dependency.algorithms.targetDependency,
        Dependency.argumentParser.targetDependency,
        Dependency.shell.targetDependency,
      ],
      path: path
    )
    case .tests: return .testTarget(
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
      ]
    )
    }
  }
}

let package = Package(
    name: "swift-zfs-tools",
    platforms: [
      .macOS(.v13)
    ],
    products: [
      Product.command.product,
      Product.model.product,
    ],
    dependencies: [
      Dependency.algorithms.packageDependency,
      Dependency.argumentParser.packageDependency,
      Dependency.shell.packageDependency,
    ],
    targets: [
      Product.command.target,
      Product.model.target,
      Product.tests.target,
    ]
)
