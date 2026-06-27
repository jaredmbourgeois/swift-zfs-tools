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
        abstract: "Build the zfs-tools binary into bin/<platform>/ — locally, or on a remote host over SSH.",
        discussion: """
        Builds locally when --remote is omitted, otherwise rsyncs the source to the remote, builds there,
        and copies the artifact back. The target platform (bin/<platform>) is derived from `uname` at the
        build site; override it with --platform. Every command is printed as it runs.

        # Rebuild this host's binary in place
        zfs-tools-build

        # Build on a remote host over SSH and copy the binary back
        zfs-tools-build --remote user@buildhost

        # If Swift isn't on the remote's PATH, point at it
        zfs-tools-build --remote user@buildhost --swift /path/to/swift
        """,
        version: "2.0.1"
    )

    @OptionGroup
    var arguments: Arguments.Build

    func run() async throws {
        let shell = ShellAtPath.loggingToStdout(label: "zfs-tools-build command")
        try await Builder(config: .init(arguments: arguments), shell: shell).build()
    }
}
