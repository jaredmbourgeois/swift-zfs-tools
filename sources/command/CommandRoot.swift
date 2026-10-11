// CommandRoot.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import Shell
import ZFSToolsModel

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// The `zfs-tools` composition root: the one file in this target that names a platform accessor or a
// live value, each accessor on a line that says why. The source-rules test
// (tests/SourceRulesTest.swift) honors a `reach-ok` marker here and refuses one in the command
// files, so a command's `run()` gets everything live from this file: it reads the process ONCE with
// `CommandRoot.readingThisProcess()` and hands the values down. Nothing below `run()` reads the
// environment, the clock, the file system or a standard stream for itself.

/// What a command's `run()` hands down: this process's facts, read once, and the live values built
/// from them.
struct CommandRoot: Sendable {
    /// This process's environment, whole. Every `zfs`, `zpool` and `ssh` child is given exactly
    /// this, and a bare `zfs` is looked up on its `PATH`.
    let environment: [String: String]
    /// This process's working directory, an absolute path: the children's.
    let workingDirectory: String
    /// The operator's locale and time zone: the retention calendar's, and the zone a snapshot's
    /// timestamp is written and read in.
    let locale: Locale
    let timeZone: TimeZone

    /// Reads this process, once. The first statement of every `run()`.
    static func readingThisProcess() throws -> CommandRoot {
        CommandRoot(
            environment: ProcessInfo.processInfo.environment,  // reach-ok: this process's environment, read once per run
            workingDirectory: try validatedWorkingDirectory(
                FileManager.default.currentDirectoryPath  // reach-ok: this process's working directory, read once per run
            ),
            locale: Locale.current,  // reach-ok: the operator's locale, read once per run
            timeZone: TimeZone.current  // reach-ok: the operator's time zone, read once per run
        )
    }

    /// The live file system.
    var fileSystem: FileSystem {
        .live
    }

    /// The live clock. A closure rather than one instant: `execute-actions` chains operations that
    /// can run for hours, and each reads the time it starts.
    var date: @Sendable () -> Date {
        { Date() }  // reach-ok: the live clock
    }

    /// Writes one entry of the command log to stdout. The log — each command, its result and its
    /// output — is what a run, and above all a dry run, is asked to show: it is the payload.
    var standardOutput: @Sendable (_ entry: String) -> Void {
        { entry in print(entry) }  // reach-ok: stdout, the payload channel
    }

    /// Writes one line of diagnostics — a warning, a rejection — to stderr.
    var diagnostics: @Sendable (_ line: String) -> Void {
        { line in
            // stdout is buffered when it is not a terminal and stderr never is. Flushing stdout
            // first keeps a log that captures both streams in the order the lines were written.
            fflush(nil)
            // A closed stderr leaves nowhere to say so; the line is dropped rather than ending the run.
            try? FileHandle.standardError.write(contentsOf: Data((line + "\n").utf8))  // reach-ok: stderr, the diagnostics channel
        }
    }

    /// The two shells every operation takes, built from a command's common options: `shell` runs a
    /// command, and `dryRunShell` reports one without running it. Both log through one observer, so
    /// a dry run prints a held command exactly as a real run prints one that ran.
    func shells(_ common: Arguments.Common) -> (shell: ShellAtPath, dryRunShell: ShellAtPath) {
        let stringEncoding = String.Encoding(rawValue: common.stringEncodingRawValue ?? Defaults.stringEncoding.rawValue)
        let observer = ShellLogFormatter(
            toolName: "zfs-tools",
            lineSeparator: common.lineSeparator ?? Defaults.lineSeparator,
            stringEncoding: stringEncoding
        ).resultObserver(write: standardOutput)
        return (
            shell: .live(
                shellPath: common.shellPath ?? Defaults.shellPath,
                environment: environment,
                workingDirectory: workingDirectory,
                terminationGracePeriod: Defaults.shellTerminationGracePeriod,
                shellObserver: observer,
                stringEncoding: stringEncoding
            ),
            dryRunShell: .dryRun(shellObserver: observer, stringEncoding: stringEncoding)
        )
    }

    /// The calendar the retention schedule's period math runs on.
    func calendar() -> Calendar {
        makeCalendar(locale: locale, timeZone: timeZone)
    }

    /// The snapshot-timestamp formatter for a command's `--date-format`.
    func dateFormatter(_ common: Arguments.Common) -> DateFormatter {
        makeDateFormatter(common.dateFormat ?? Defaults.dateFormat, timeZone: timeZone)
    }

    /// Runs the program at `executablePath` on this process's own stdin, stdout and stderr, waits
    /// for it, and returns its exit status. `receive-guard` runs an approved `zfs` this way — with
    /// no shell and no pipe of ours in between — so a `zfs recv` reads the SSH channel's byte stream
    /// directly. The child is given the environment and working directory this root read.
    func runOnOwnStandardStreams(executablePath: String, arguments: [String]) throws -> Int32 {
        let process = Process()  // reach-ok: the one direct spawn, so the child owns this process's standard streams
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
