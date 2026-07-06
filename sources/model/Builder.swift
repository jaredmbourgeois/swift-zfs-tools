// Builder.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell

/// Pure shell-command builders for the binary-build flow — the build-tooling analogue of the `ZFS`
/// enum. Every interpolated value is `shellQuoted` so paths/hosts with spaces can't word-split.
enum Build {
    /// Prints the build host's OS then machine on two lines — fed to `BuildPlatform.directoryName`.
    static func uname() -> String {
        "uname -s && uname -m"
    }

    /// Wrap `command` so it runs in `directory`. The `&&` and `cd` are for the shell that ultimately
    /// runs it (the local shell, or — once passed through `remote(ssh:command:)` — the remote shell).
    static func inDirectory(_ directory: String, run command: String) -> String {
        "cd \(directory.shellQuoted) && \(command)"
    }

    static func swiftBuild(swift: String, configuration: String, staticSwiftStdlib: Bool) -> String
    {
        var command = "\(swift.shellQuoted) build -c \(configuration.shellQuoted)"
        if staticSwiftStdlib {
            // Statically links the Swift stdlib so the artifact runs on a host with no Swift
            // toolchain (the recv-guard receivers). Only the build needs it; --show-bin-path is
            // unaffected (same release dir).
            command += " --static-swift-stdlib"
        }
        return command
    }

    /// `swift build --show-bin-path` prints the directory holding the built products — used to locate
    /// the artifact without hardcoding a target triple, so any arch works.
    static func swiftBinPath(swift: String, configuration: String) -> String {
        "\(swift.shellQuoted) build --show-bin-path -c \(configuration.shellQuoted)"
    }

    static func rsync(source: String, destination: String, excludes: [String]) -> String {
        var command = "rsync -az"
        for exclude in excludes {
            command += " --exclude=\(exclude.shellQuoted)"
        }
        command += " \(source.shellQuoted) \(destination.shellQuoted)"
        return command
    }

    /// Run `command` on `ssh` (an ssh destination or config alias). The *whole* command is quoted so
    /// it survives the remote shell's re-parse intact — the opposite of `Syncer.remote`, which keeps a
    /// pipe on the local side.
    static func remote(ssh: String, command: String) -> String {
        "ssh \(ssh.shellQuoted) \(command.shellQuoted)"
    }

    static func scp(from: String, to: String) -> String {
        "scp \(from.shellQuoted) \(to.shellQuoted)"
    }

    static func copy(from: String, to: String) -> String {
        "cp \(from.shellQuoted) \(to.shellQuoted)"
    }

    static func makeDirectory(_ path: String) -> String {
        "mkdir -p \(path.shellQuoted)"
    }

    static func removeDirectory(_ path: String) -> String {
        "rm -rf \(path.shellQuoted)"
    }
}

/// Builds the `zfs-tools` executable and drops the binary into `bin/<platform>/` — locally, or on a
/// remote host over SSH (rsync up → `swift build` → copy the artifact back → clean up). The target
/// platform is derived at the build site via `uname` (overridable). Injectable `shell` makes the whole
/// orchestration unit-testable, mirroring `Syncer`.
public struct Builder: Sendable {
    private let config: Config
    private let shell: ShellAtPath

    /// Source-tree entries never needed for a build — skipped on rsync to keep transfers small and
    /// avoid shipping build products (`bin` holds the prebuilt binaries; `.build`/`build` are local
    /// build dirs) to the build host.
    private static let rsyncExcludes = [".git", ".build", "build", "bin"]

    /// The product name `swift build` emits; the artifact is `<bin-path>/ZFSTools`.
    private static let productName = "ZFSTools"

    public init(config: Config, shell: ShellAtPath) {
        self.config = config
        self.shell = shell
    }

    public func build() async throws {
        let platform = try await resolvePlatform()
        let destination =
            config.destination ?? "\(config.sourceDirectory)/bin/\(platform)/zfs-tools"
        if let remote = config.remote {
            try await buildRemote(remote: remote, destination: destination)
        } else {
            try await buildLocal(destination: destination)
        }
    }

    /// Derive the `bin/<platform>/` directory name from `uname` at the build site, unless the caller
    /// pinned it with `platformOverride`. Fails loud if `uname` output is unrecognized.
    private func resolvePlatform() async throws -> String {
        if let override = config.platformOverride {
            return override
        }
        let unameCommand =
            config.remote.map { Build.remote(ssh: $0, command: Build.uname()) } ?? Build.uname()
        let lines = try await shell.lines(
            unameCommand, dryRun: false, encoding: .utf8, lineSeparator: "\n")
        guard lines.count >= 2,
            let platform = BuildPlatform.directoryName(unameS: lines[0], unameM: lines[1])
        else {
            throw ErrorType.shellError(
                command: unameCommand,
                error: "could not derive platform from uname output: \(lines)")
        }
        return platform
    }

    private func buildLocal(destination: String) async throws {
        let buildCommand = Build.inDirectory(
            config.sourceDirectory,
            run: Build.swiftBuild(
                swift: config.swift, configuration: config.configuration,
                staticSwiftStdlib: config.staticSwiftStdlib))
        try await run(buildCommand)
        let binPath = try await lastLine(
            Build.inDirectory(
                config.sourceDirectory,
                run: Build.swiftBinPath(swift: config.swift, configuration: config.configuration)))
        try await run(Build.makeDirectory(parentDirectory(of: destination)))
        try await run(Build.copy(from: "\(binPath)/\(Self.productName)", to: destination))
    }

    private func buildRemote(remote: String, destination: String) async throws {
        let temp = config.tempDirectory
        try Self.validateTempDirectory(temp)
        try await run(
            Build.rsync(
                source: "\(config.sourceDirectory)/",
                destination: "\(remote):\(temp)/",
                excludes: Self.rsyncExcludes
            )
        )
        try await run(
            Build.remote(
                ssh: remote,
                command: Build.inDirectory(
                    temp,
                    run: Build.swiftBuild(
                        swift: config.swift, configuration: config.configuration,
                        staticSwiftStdlib: config.staticSwiftStdlib))
            ))
        let binPath = try await lastLine(
            Build.remote(
                ssh: remote,
                command: Build.inDirectory(
                    temp,
                    run: Build.swiftBinPath(
                        swift: config.swift, configuration: config.configuration))))
        try await run(Build.makeDirectory(parentDirectory(of: destination)))
        try await run(Build.scp(from: "\(remote):\(binPath)/\(Self.productName)", to: destination))
        if !config.keepTempDirectory {
            try await run(Build.remote(ssh: remote, command: Build.removeDirectory(temp)))
        }
    }

    private func run(_ command: String) async throws {
        _ = try await shell.execute(command, dryRun: false).get()
    }

    /// Run `command` and return its last non-empty stdout line (the `--show-bin-path` path).
    private func lastLine(_ command: String) async throws -> String {
        let lines = try await shell.lines(
            command, dryRun: false, encoding: .utf8, lineSeparator: "\n")
        guard
            let line = lines.last(where: {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else {
            throw ErrorType.shellError(command: command, error: "no output")
        }
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parentDirectory(of path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    private static func validateTempDirectory(_ path: String) throws {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let unsafePaths = ["", "/", ".", ".."]
        let pathComponents = trimmed.split(separator: "/").map(String.init)
        let basename = pathComponents.last ?? ""
        let isAbsolute = trimmed.hasPrefix("/")
        guard !unsafePaths.contains(trimmed), !trimmed.hasPrefix("../"), !trimmed.hasSuffix("/.."), !trimmed.contains("/../"), !trimmed.hasPrefix("~/") else {
            throw ErrorType.invalidArgument(
                name: "tempDirectory",
                value: path,
                reason: "expected a non-root build directory without parent-directory components"
            )
        }
        guard !isAbsolute || basename.contains("zfs-tools-build") else {
            throw ErrorType.invalidArgument(
                name: "tempDirectory",
                value: path,
                reason: "expected an absolute build directory basename containing zfs-tools-build"
            )
        }
    }
}

extension Builder {
    /// Inputs for a build run. `destination` defaults to `<sourceDirectory>/bin/<platform>/zfs-tools`;
    /// `platformOverride` bypasses `uname` derivation; `remote` nil means build on this host.
    public struct Config: Sendable {
        public let remote: String?
        public let sourceDirectory: String
        public let tempDirectory: String
        public let destination: String?
        public let platformOverride: String?
        public let swift: String
        public let configuration: String
        public let keepTempDirectory: Bool
        public let staticSwiftStdlib: Bool

        public init(
            remote: String?,
            sourceDirectory: String,
            tempDirectory: String,
            destination: String?,
            platformOverride: String?,
            swift: String,
            configuration: String,
            keepTempDirectory: Bool,
            staticSwiftStdlib: Bool
        ) {
            self.remote = remote
            self.sourceDirectory = sourceDirectory
            self.tempDirectory = tempDirectory
            self.destination = destination
            self.platformOverride = platformOverride
            self.swift = swift
            self.configuration = configuration
            self.keepTempDirectory = keepTempDirectory
            self.staticSwiftStdlib = staticSwiftStdlib
        }

        public init(arguments: Arguments.Build) {
            remote = arguments.remote
            sourceDirectory = arguments.sourceDir ?? FileManager.default.currentDirectoryPath
            // Relative path: resolved against the remote home directory (ssh's default cwd). A
            // leading `~` can't be used here — it's single-quoted into the command and wouldn't
            // expand. Pass an absolute `--temp-dir` to put it elsewhere.
            tempDirectory = arguments.tempDir ?? "zfs-tools-build"
            destination = arguments.destination
            platformOverride = arguments.platform
            swift = arguments.swift ?? "swift"
            configuration = arguments.configuration ?? "release"
            keepTempDirectory = arguments.keepTemp
            staticSwiftStdlib = arguments.staticSwiftStdlib
        }
    }
}
