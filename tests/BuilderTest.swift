// BuilderTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import ArgumentParser
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
            _ statusesForResult: ShellTermination.StatusesForResult,
            _ stream: ShellStream?,
            _ timeout: TimeInterval?
        ) async -> ShellResult in
            recorder.withLock { $0.append(command) }
            if command.contains("uname") {
                return .successWithUTF8Stdout(uname)
            }
            if command.contains("--show-bin-path") {
                return .successWithUTF8Stdout(binPath)
            }
            return .emptySuccess()
        }
    }

    func testLocalBuildCommandSequence() async throws {
        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "Darwin\narm64", binPath: "/repo/.build/release")
        let config = Builder.Config(
            remote: nil,
            remoteCommandPrefix: [],
            sourceDirectory: "/repo",
            tempDirectory: "/tmp/ztb",
            destination: nil,
            platformOverride: nil,
            swift: "swift",
            configuration: "release",
            keepTempDirectory: false,
            staticSwiftStdlib: false,
            workingDirectory: "/work"
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
        let shell = mockShell(recorder, uname: "Linux\nx86_64", binPath: "/tmp/zfs-tools-build/.build/release")
        let config = Builder.Config(
            remote: "serverJMB",
            remoteCommandPrefix: [],
            sourceDirectory: "/repo",
            tempDirectory: "/tmp/zfs-tools-build",
            destination: nil,
            platformOverride: nil,
            swift: "swift",
            configuration: "release",
            keepTempDirectory: false,
            staticSwiftStdlib: false,
            workingDirectory: "/work"
        )
        try await Builder(config: config, shell: shell).build()
        XCTAssertEqual(
            recorder.value,
            [
                "ssh 'serverJMB' 'uname -s && uname -m'",
                "rsync -az --exclude='.git' --exclude='.build' --exclude='build' --exclude='bin' '/repo/' 'serverJMB:/tmp/zfs-tools-build/'",
                "ssh 'serverJMB' 'cd '\\''/tmp/zfs-tools-build'\\'' && '\\''swift'\\'' build -c '\\''release'\\'''",
                "ssh 'serverJMB' 'cd '\\''/tmp/zfs-tools-build'\\'' && '\\''swift'\\'' build --show-bin-path -c '\\''release'\\'''",
                "mkdir -p '/repo/bin/linux-x86_64'",
                "scp 'serverJMB:/tmp/zfs-tools-build/.build/release/ZFSTools' '/repo/bin/linux-x86_64/zfs-tools'",
                "ssh 'serverJMB' 'rm -rf '\\''/tmp/zfs-tools-build'\\'''",
            ]
        )
    }

    // MARK: - --remote-command-prefix

    /// With a prefix, the two remote `swift` commands — the build — run through it, inside the
    /// `cd`; the probe, the rsync, the copy back and the cleanup are untouched. Without one the
    /// lines are `testRemoteBuildCommandSequence`'s.
    func testRemoteCommandPrefixWrapsTheRemoteSwiftCommands() async throws {
        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "Linux\nx86_64", binPath: "/tmp/zfs-tools-build/.build/release")
        let config = Builder.Config(
            remote: "serverJMB",
            remoteCommandPrefix: ["sudo", "-n", "fleet-ci-run"],
            sourceDirectory: "/repo",
            tempDirectory: "/tmp/zfs-tools-build",
            destination: nil,
            platformOverride: nil,
            swift: "/usr/share/swift/usr/bin/swift",
            configuration: "release",
            keepTempDirectory: false,
            staticSwiftStdlib: true,
            workingDirectory: "/work"
        )
        try await Builder(config: config, shell: shell).build()
        XCTAssertEqual(
            recorder.value,
            [
                "ssh 'serverJMB' 'uname -s && uname -m'",
                "rsync -az --exclude='.git' --exclude='.build' --exclude='build' --exclude='bin' '/repo/' 'serverJMB:/tmp/zfs-tools-build/'",
                "ssh 'serverJMB' 'cd '\\''/tmp/zfs-tools-build'\\'' && '\\''sudo'\\'' '\\''-n'\\'' '\\''fleet-ci-run'\\'' '\\''/usr/share/swift/usr/bin/swift'\\'' build -c '\\''release'\\'' --static-swift-stdlib'",
                "ssh 'serverJMB' 'cd '\\''/tmp/zfs-tools-build'\\'' && '\\''sudo'\\'' '\\''-n'\\'' '\\''fleet-ci-run'\\'' '\\''/usr/share/swift/usr/bin/swift'\\'' build --show-bin-path -c '\\''release'\\'''",
                "mkdir -p '/repo/bin/linux-x86_64'",
                "scp 'serverJMB:/tmp/zfs-tools-build/.build/release/ZFSTools' '/repo/bin/linux-x86_64/zfs-tools'",
                "ssh 'serverJMB' 'rm -rf '\\''/tmp/zfs-tools-build'\\'''",
            ]
        )
        // The same build line with each layer of quoting removed the way a shell removes it: the
        // local shell hands ssh one argument, and the remote shell reads that argument as these words.
        let remoteLine = try XCTUnwrap(ReceiveGuardPolicy.tokenize(recorder.value[2])?.last)
        XCTAssertEqual(
            "cd '/tmp/zfs-tools-build' && 'sudo' '-n' 'fleet-ci-run' '/usr/share/swift/usr/bin/swift' build -c 'release' --static-swift-stdlib",
            remoteLine
        )
        XCTAssertEqual(
            ["cd", "/tmp/zfs-tools-build", "&&", "sudo", "-n", "fleet-ci-run", "/usr/share/swift/usr/bin/swift", "build", "-c", "release", "--static-swift-stdlib"],
            ReceiveGuardPolicy.tokenize(remoteLine)
        )
    }

    /// The option takes every word after it, dash-prefixed ones included, and its absence is the
    /// parser's statement of "no prefix" — the config holds no default of its own.
    func testRemoteCommandPrefixIsParsedAsTheWordsAfterTheOption() throws {
        let prefixed = try Arguments.Build.parse([
            "--remote", "serverJMB", "--swift", "/usr/share/swift/usr/bin/swift",
            "--remote-command-prefix", "sudo", "-n", "fleet-ci-run",
        ])
        XCTAssertEqual(["sudo", "-n", "fleet-ci-run"], prefixed.remoteCommandPrefix)
        XCTAssertEqual("/usr/share/swift/usr/bin/swift", prefixed.swift)
        XCTAssertEqual(
            ["sudo", "-n", "fleet-ci-run"],
            Builder.Config(arguments: prefixed, workingDirectory: "/work").remoteCommandPrefix
        )

        let plain = try Arguments.Build.parse(["--remote", "serverJMB"])
        XCTAssertEqual([], plain.remoteCommandPrefix)
        XCTAssertEqual([], Builder.Config(arguments: plain, workingDirectory: "/work").remoteCommandPrefix)
    }

    /// A prefix with no remote build to run through it is refused by the parser, not ignored.
    func testRemoteCommandPrefixWithoutRemoteIsRejected() {
        XCTAssertThrowsError(try Arguments.Build.parse(["--remote-command-prefix", "sudo", "-n", "fleet-ci-run"]))
    }

    // MARK: - the working directory is handed in

    /// An omitted `--source-dir` is the working directory the composition root read, and a relative
    /// destination's parent is made inside that directory — neither is read from the process.
    func testSourceDirectoryAndARelativeDestinationAreReadAgainstTheWorkingDirectory() async throws {
        let arguments = try Arguments.Build.parse(["--destination", "out/zfs-tools", "--platform", "macos-arm64"])
        let config = Builder.Config(arguments: arguments, workingDirectory: "/work")
        XCTAssertEqual("/work", config.sourceDirectory)

        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "unused", binPath: "/work/.build/release")
        try await Builder(config: config, shell: shell).build()
        XCTAssertEqual(
            recorder.value,
            [
                "cd '/work' && 'swift' build -c 'release' --static-swift-stdlib",
                "cd '/work' && 'swift' build --show-bin-path -c 'release'",
                "mkdir -p '/work/out'",
                "cp '/work/.build/release/ZFSTools' 'out/zfs-tools'",
            ]
        )
    }

    func testPlatformOverrideSkipsUnameProbe() async throws {
        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "unused", binPath: "/repo/.build/release")
        let config = Builder.Config(
            remote: nil,
            remoteCommandPrefix: [],
            sourceDirectory: "/repo",
            tempDirectory: "/tmp/ztb",
            destination: nil,
            platformOverride: "linux-aarch64",
            swift: "swift",
            configuration: "release",
            keepTempDirectory: false,
            staticSwiftStdlib: false,
            workingDirectory: "/work"
        )
        try await Builder(config: config, shell: shell).build()
        XCTAssertFalse(recorder.value.contains { $0.contains("uname") }, "override must skip the uname probe")
        XCTAssertEqual("cp '/repo/.build/release/ZFSTools' '/repo/bin/linux-aarch64/zfs-tools'", recorder.value.last)
    }

    func testKeepTempDirectorySkipsCleanup() async throws {
        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "Linux\nx86_64", binPath: "/tmp/zfs-tools-build/.build/release")
        let config = Builder.Config(
            remote: "serverJMB",
            remoteCommandPrefix: [],
            sourceDirectory: "/repo",
            tempDirectory: "/tmp/zfs-tools-build",
            destination: nil,
            platformOverride: nil,
            swift: "swift",
            configuration: "release",
            keepTempDirectory: true,
            staticSwiftStdlib: false,
            workingDirectory: "/work"
        )
        try await Builder(config: config, shell: shell).build()
        XCTAssertFalse(recorder.value.contains { $0.contains("rm -rf") }, "keepTempDirectory must skip cleanup")
    }

    func testUnsafeRemoteTempDirectoryFailsBeforeShellExecution() async throws {
        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "Linux\nx86_64", binPath: "/tmp/ztb/.build/release")
        let config = Builder.Config(
            remote: "serverJMB",
            remoteCommandPrefix: [],
            sourceDirectory: "/repo",
            tempDirectory: "/",
            destination: nil,
            platformOverride: "linux-x86_64",
            swift: "swift",
            configuration: "release",
            keepTempDirectory: false,
            staticSwiftStdlib: false,
            workingDirectory: "/work"
        )
        do {
            try await Builder(config: config, shell: shell).build()
            XCTFail("unsafe tempDirectory should throw")
        } catch ErrorType.invalidArgument(let name, let value, _, _) {
            XCTAssertEqual(name, "tempDirectory")
            XCTAssertEqual(value, "/")
        }
        XCTAssertTrue(recorder.value.isEmpty, "unsafe tempDirectory must fail before rsync/build/cleanup")
    }

    func testBroadAbsoluteRemoteTempDirectoriesFailBeforeShellExecution() async throws {
        for tempDirectory in ["/home/jared", "/home/jared/.swiftly", "/var/tmp"] {
            let recorder = Locked<[String]>([])
            let shell = mockShell(recorder, uname: "Linux\nx86_64", binPath: "/tmp/zfs-tools-build/.build/release")
            let config = Builder.Config(
                remote: "serverJMB",
                remoteCommandPrefix: [],
                sourceDirectory: "/repo",
                tempDirectory: tempDirectory,
                destination: nil,
                platformOverride: "linux-x86_64",
                swift: "swift",
                configuration: "release",
                keepTempDirectory: false,
                staticSwiftStdlib: false,
                workingDirectory: "/work"
            )
            do {
                try await Builder(config: config, shell: shell).build()
                XCTFail("unsafe tempDirectory should throw: \(tempDirectory)")
            } catch ErrorType.invalidArgument(let name, let value, _, _) {
                XCTAssertEqual(name, "tempDirectory")
                XCTAssertEqual(value, tempDirectory)
            }
            XCTAssertTrue(recorder.value.isEmpty, "unsafe tempDirectory must fail before rsync/build/cleanup")
        }
    }

    /// A relative temp dir is the remote home's directory of that name, so it is held to the same
    /// basename rule as an absolute one: a plain user-visible name must never reach `rm -rf`.
    func testRelativeRemoteTempDirectoriesWithoutTheMarkerFailBeforeShellExecution() async throws {
        for tempDirectory in ["Documents", "./Documents", "~", "src/Documents", "Documents/..", "../zfs-tools-build", "zfs-tools-build/../Documents"] {
            let recorder = Locked<[String]>([])
            let shell = mockShell(recorder, uname: "Linux\nx86_64", binPath: "/home/jared/zfs-tools-build/.build/release")
            let config = Builder.Config(
                remote: "serverJMB",
                remoteCommandPrefix: [],
                sourceDirectory: "/repo",
                tempDirectory: tempDirectory,
                destination: nil,
                platformOverride: "linux-x86_64",
                swift: "swift",
                configuration: "release",
                keepTempDirectory: false,
                staticSwiftStdlib: false,
                workingDirectory: "/work"
            )
            do {
                try await Builder(config: config, shell: shell).build()
                XCTFail("unsafe tempDirectory should throw: \(tempDirectory)")
            } catch ErrorType.invalidArgument(let name, let value, _, _) {
                XCTAssertEqual(name, "tempDirectory")
                XCTAssertEqual(value, tempDirectory)
            }
            XCTAssertTrue(recorder.value.isEmpty, "unsafe tempDirectory must fail before rsync/build/cleanup: \(tempDirectory)")
        }
    }

    /// A relative temp dir whose basename carries the marker — the default among them — builds and
    /// is removed as that relative path, resolved by the remote shell against its login directory.
    func testRelativeRemoteTempDirectoriesWithTheMarkerPass() async throws {
        for tempDirectory in ["zfs-tools-build", "./zfs-tools-build", "build/zfs-tools-build-ci"] {
            let recorder = Locked<[String]>([])
            let shell = mockShell(recorder, uname: "Linux\nx86_64", binPath: "/home/jared/\(tempDirectory)/.build/release")
            let config = Builder.Config(
                remote: "serverJMB",
                remoteCommandPrefix: [],
                sourceDirectory: "/repo",
                tempDirectory: tempDirectory,
                destination: nil,
                platformOverride: "linux-x86_64",
                swift: "swift",
                configuration: "release",
                keepTempDirectory: false,
                staticSwiftStdlib: false,
                workingDirectory: "/work"
            )
            try await Builder(config: config, shell: shell).build()
            XCTAssertEqual(
                "rsync -az --exclude='.git' --exclude='.build' --exclude='build' --exclude='bin' '/repo/' 'serverJMB:\(tempDirectory)/'",
                recorder.value.first,
                tempDirectory
            )
            XCTAssertEqual("ssh 'serverJMB' 'rm -rf '\\''\(tempDirectory)'\\'''", recorder.value.last, tempDirectory)
        }
    }

    /// The parser's default temp dir satisfies the rule, so an omitted `--temp-dir` still builds.
    func testDefaultTempDirectoryPassesValidation() async throws {
        let arguments = try Arguments.Build.parse(["--remote", "serverJMB", "--platform", "linux-x86_64"])
        let config = Builder.Config(arguments: arguments, workingDirectory: "/work")
        XCTAssertEqual("zfs-tools-build", config.tempDirectory)

        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "unused", binPath: "/home/jared/zfs-tools-build/.build/release")
        try await Builder(config: config, shell: shell).build()
        XCTAssertEqual("ssh 'serverJMB' 'rm -rf '\\''zfs-tools-build'\\'''", recorder.value.last)
    }

    func testCustomDestinationIsHonored() async throws {
        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "Darwin\narm64", binPath: "/repo/.build/release")
        let config = Builder.Config(
            remote: nil,
            remoteCommandPrefix: [],
            sourceDirectory: "/repo",
            tempDirectory: "/tmp/ztb",
            destination: "/out/zfs-tools",
            platformOverride: nil,
            swift: "swift",
            configuration: "release",
            keepTempDirectory: false,
            staticSwiftStdlib: false,
            workingDirectory: "/work"
        )
        try await Builder(config: config, shell: shell).build()
        XCTAssertEqual("cp '/repo/.build/release/ZFSTools' '/out/zfs-tools'", recorder.value.last)
        XCTAssertTrue(recorder.value.contains("mkdir -p '/out'"))
    }

    func testStaticSwiftStdlibAddsBuildFlag() async throws {
        let recorder = Locked<[String]>([])
        let shell = mockShell(recorder, uname: "Darwin\narm64", binPath: "/repo/.build/release")
        let config = Builder.Config(
            remote: nil,
            remoteCommandPrefix: [],
            sourceDirectory: "/repo",
            tempDirectory: "/tmp/ztb",
            destination: nil,
            platformOverride: nil,
            swift: "swift",
            configuration: "release",
            keepTempDirectory: false,
            staticSwiftStdlib: true,
            workingDirectory: "/work"
        )
        try await Builder(config: config, shell: shell).build()
        XCTAssertTrue(
            recorder.value.contains("cd '/repo' && 'swift' build -c 'release' --static-swift-stdlib")
        )
    }
}
