// BuilderTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import XCTest

@testable import ZFSToolsModel

// Pins the exact command sequence the builder issues for local and remote builds — including the
// two-level shell quoting for SSH — with a mock shell, the way SyncerTest pins sync commands.
final class BuilderTest: XCTestCase {
    private func mockShell(
        _ recorder: Locked<[String]>,
        uname: String,
        binPath: String
    ) -> ShellAtPath {
        ShellAtPath { @Sendable (
            _ command: ShellCommand,
            _ dryRun: Bool,
            _ estimatedOutputSize: Int?,
            _ estimatedErrorSize: Int?,
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            recorder.withLock { $0.append(command) }
            if command.contains("uname") {
                return .success(stdout: uname)!
            }
            if command.contains("--show-bin-path") {
                return .success(stdout: binPath)!
            }
            return .success()
        }
    }

    func testLocalBuildCommandSequence() async throws {
        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "Darwin\narm64", binPath: "/repo/.build/release")
        let config = Builder.Config(
            remote: nil,
            sourceDirectory: "/repo",
            tempDirectory: "/tmp/ztb",
            destination: nil,
            platformOverride: nil,
            swift: "swift",
            configuration: "release",
            keepTempDirectory: false
        )
        try await Builder(config: config, shell: shell).build()
        XCTAssertEqual(
            recorder.value,
            [
                "uname -s && uname -m",
                "cd '/repo' && 'swift' build -c 'release'",
                "cd '/repo' && 'swift' build --show-bin-path -c 'release'",
                "mkdir -p '/repo/bin/macos-arm64'",
                "cp '/repo/.build/release/ZFSTools' '/repo/bin/macos-arm64/zfs-tools'",
            ]
        )
    }

    func testRemoteBuildCommandSequence() async throws {
        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "Linux\nx86_64", binPath: "/tmp/ztb/.build/release")
        let config = Builder.Config(
            remote: "serverJMB",
            sourceDirectory: "/repo",
            tempDirectory: "/tmp/ztb",
            destination: nil,
            platformOverride: nil,
            swift: "swift",
            configuration: "release",
            keepTempDirectory: false
        )
        try await Builder(config: config, shell: shell).build()
        XCTAssertEqual(
            recorder.value,
            [
                "ssh 'serverJMB' 'uname -s && uname -m'",
                "rsync -az --exclude='.git' --exclude='.build' --exclude='build' --exclude='bin' '/repo/' 'serverJMB:/tmp/ztb/'",
                "ssh 'serverJMB' 'cd '\\''/tmp/ztb'\\'' && '\\''swift'\\'' build -c '\\''release'\\'''",
                "ssh 'serverJMB' 'cd '\\''/tmp/ztb'\\'' && '\\''swift'\\'' build --show-bin-path -c '\\''release'\\'''",
                "mkdir -p '/repo/bin/linux-x86_64'",
                "scp 'serverJMB:/tmp/ztb/.build/release/ZFSTools' '/repo/bin/linux-x86_64/zfs-tools'",
                "ssh 'serverJMB' 'rm -rf '\\''/tmp/ztb'\\'''",
            ]
        )
    }

    func testPlatformOverrideSkipsUnameProbe() async throws {
        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "unused", binPath: "/repo/.build/release")
        let config = Builder.Config(
            remote: nil,
            sourceDirectory: "/repo",
            tempDirectory: "/tmp/ztb",
            destination: nil,
            platformOverride: "linux-aarch64",
            swift: "swift",
            configuration: "release",
            keepTempDirectory: false
        )
        try await Builder(config: config, shell: shell).build()
        XCTAssertFalse(recorder.value.contains { $0.contains("uname") }, "override must skip the uname probe")
        XCTAssertEqual("cp '/repo/.build/release/ZFSTools' '/repo/bin/linux-aarch64/zfs-tools'", recorder.value.last)
    }

    func testKeepTempDirectorySkipsCleanup() async throws {
        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "Linux\nx86_64", binPath: "/tmp/ztb/.build/release")
        let config = Builder.Config(
            remote: "serverJMB",
            sourceDirectory: "/repo",
            tempDirectory: "/tmp/ztb",
            destination: nil,
            platformOverride: nil,
            swift: "swift",
            configuration: "release",
            keepTempDirectory: true
        )
        try await Builder(config: config, shell: shell).build()
        XCTAssertFalse(recorder.value.contains { $0.contains("rm -rf") }, "keepTempDirectory must skip cleanup")
    }

    func testCustomDestinationIsHonored() async throws {
        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "Darwin\narm64", binPath: "/repo/.build/release")
        let config = Builder.Config(
            remote: nil,
            sourceDirectory: "/repo",
            tempDirectory: "/tmp/ztb",
            destination: "/out/zfs-tools",
            platformOverride: nil,
            swift: "swift",
            configuration: "release",
            keepTempDirectory: false
        )
        try await Builder(config: config, shell: shell).build()
        XCTAssertEqual("cp '/repo/.build/release/ZFSTools' '/out/zfs-tools'", recorder.value.last)
        XCTAssertTrue(recorder.value.contains("mkdir -p '/out'"))
    }
}
