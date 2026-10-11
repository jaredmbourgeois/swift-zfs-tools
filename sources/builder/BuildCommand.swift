// BuildCommand.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import ArgumentParser
import Foundation
import Shell
import ZFSToolsModel

@main
struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "zfs-tools-build",
        abstract:
            "Build the zfs-tools binary into bin/<platform>/ — locally, or on a remote host over SSH.",
        discussion: """
            Builds locally when --remote is omitted, otherwise rsyncs the source to the remote, builds there,
            and copies the artifact back. The target platform (bin/<platform>) is derived from `uname` at the
            build site; override it with --platform. Builds statically link the Swift stdlib by default
            where supported so Linux artifacts run without a Swift toolchain; pass --no-static-swift-stdlib
            to opt into a dynamic Swift-runtime build. This does not make the Linux artifact fully static:
            it still depends on the platform C runtime/dynamic loader. Every command is printed as it runs.

            # Rebuild this host's binary in place
            zfs-tools-build

            # Build on a remote host over SSH and copy the binary back
            zfs-tools-build --remote user@buildhost

            # If Swift isn't on the remote's PATH, point at it
            zfs-tools-build --remote user@buildhost --swift /path/to/swift

            # Run the remote swift commands through a wrapper (the prefix is the last option)
            zfs-tools-build --remote buildhost --remote-command-prefix sudo -n my-wrapper
            """,
        version: ToolVersion.current
    )

    @OptionGroup
    var arguments: Arguments.Build

    // The builder's composition root, and the one place in this target that names a platform
    // accessor or a live value: it reads this process once and hands the values down.
    func run() async throws {
        let environment = ProcessInfo.processInfo.environment  // reach-ok: the builder's own environment, given to its ssh, rsync and swift children
        let workingDirectory = try validatedWorkingDirectory(
            FileManager.default.currentDirectoryPath  // reach-ok: the builder's own working directory: the children's, and the default source directory
        )
        let observer = ShellLogFormatter(
            toolName: "zfs-tools-build",
            lineSeparator: Defaults.lineSeparator,
            stringEncoding: Defaults.stringEncoding
        ).resultObserver(write: { entry in print(entry) })  // reach-ok: stdout, where every command is printed as it runs
        let shell = ShellAtPath.live(
            shellPath: Defaults.shellPath,
            environment: environment,
            workingDirectory: workingDirectory,
            terminationGracePeriod: Defaults.shellTerminationGracePeriod,
            shellObserver: observer,
            stringEncoding: Defaults.stringEncoding
        )
        try await Builder(config: .init(arguments: arguments, workingDirectory: workingDirectory), shell: shell).build()
    }
}
