# swift-zfs-tools

## Tools to take, consolidate, and sync ZFS snapshots.

### Written in Swift with credit to [swift-argument-parser](https://github.com/apple/swift-argument-parser) for the CLI!

## Installation

1. Install [Swift](https://www.swift.org/download/) > 5.8
  - tl;dr MacOS install [Xcode](https://developer.apple.com/xcode/)
  - tl;dr [Unbuntu instructions](https://gist.github.com/Jswizzy/408af5829970f9eb18f9b45f891910bb) (note this links to Swift 5.3, so update the links as needed)
2. `cd` to desired directory and `git clone https://github.com/jaredmbourgeois/swift-zfs-tools.git`
 - **Optional**: modify values in `swift-zfs-tools/sources/model/Defaults.swift` to change default values before compiling.
3. `cd` to `swift-zfs-tools` and `swift build -c release --build-path /path/to/build/directory`
  - executable will be located in `/path/to/build/directory/build-platform/release/ZFSTools`
4. **Optional**: move executable wherever desired and add it to your path

## Run

The core subcommands are `snapshot`, `consolidate`, and `sync`; the `execute-actions` subcommand runs a list of these core subcommands.

Each subcommand has an associated `x-configure` subcommand that takes parameters and writes a json to the `output-path`.
