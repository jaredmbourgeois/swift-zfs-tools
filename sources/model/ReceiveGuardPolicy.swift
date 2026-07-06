// ReceiveGuardPolicy.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation

// The receive side of a `sync`. Installed as an SSH forced command
// (`command="zfs-tools receive-guard --pool <pool>"`) on a backup RECEIVER, it constrains a push
// key to exactly the remote commands `Syncer` emits — nothing else, no shell, no other pool.
//
// `Syncer` (the SENDER) issues these remote commands (see Syncer.swift), which are the allowlist:
//   • `zfs recv -F <target>`                                            (the incoming send stream)
//   • `zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg`   (enumerate snapshots)
//   • `zfs destroy <snapshot>`                                          (prune a snapshot)
// Dataset/snapshot args are `.shellQuoted` by the sender, so this parser understands single-quoting
// and backslash escapes. Validation is by exact argv shape; the approved command is then exec'd
// DIRECTLY (no shell), so metacharacters in a rejected command are never interpreted.

public enum ReceiveGuardRejection: Error, Equatable, Sendable {
    case emptyCommand
    case unterminatedQuote
    case notZfs(String)  // argv[0] wasn't `zfs`
    case disallowedSubcommand(String)  // not recv / list / destroy
    case wrongShape(String)  // right subcommand, unexpected argv
    case targetOutsidePool(String)  // recv/destroy target not within --pool
    case destroyTargetIsNotSnapshot(String)
    case invalidPool(String)
}

public struct ReceiveGuardPolicy: Sendable {
    public let pool: String

    public init(pool: String) {
        self.pool = pool
    }

    /// Validate a raw `$SSH_ORIGINAL_COMMAND`. On success returns the approved argv to exec (argv[0]
    /// == "zfs"); on failure returns why. Pure + total — no I/O, no exec — so it is unit-tested
    /// exhaustively and can't drift from what the sender emits.
    public func validate(_ originalCommand: String) -> Result<[String], ReceiveGuardRejection> {
        guard Self.isValidPoolName(pool) else { return .failure(.invalidPool(pool)) }
        guard let argv = Self.tokenize(originalCommand) else {
            // tokenize returns nil only for an unterminated single quote
            return .failure(.unterminatedQuote)
        }
        guard let verb = argv.first else { return .failure(.emptyCommand) }
        guard verb == "zfs" else { return .failure(.notZfs(verb)) }
        guard argv.count >= 2 else { return .failure(.wrongShape(originalCommand)) }

        switch argv[1] {
        case "recv", "receive":
            // zfs recv -F <target>
            guard argv.count == 4, argv[2] == "-F" else {
                return .failure(.wrongShape(originalCommand))
            }
            guard withinPool(argv[3]) else { return .failure(.targetOutsidePool(argv[3])) }
            return .success(argv)

        case "list":
            // The sender sends no pool filter because its grep runs sender-side. Accept only that
            // fixed input shape, but execute a scoped argv so a forced key cannot enumerate every
            // visible snapshot on the receiver.
            guard argv == [
                "zfs", "list", "-t", "snapshot", "-H", "-p", "-o", "guid,createtxg,name", "-s",
                "createtxg",
            ] else {
                return .failure(.wrongShape(originalCommand))
            }
            return .success(argv + ["-r", pool])

        case "destroy":
            // zfs destroy <snapshot>
            guard argv.count == 3 else { return .failure(.wrongShape(originalCommand)) }
            guard withinPool(argv[2]) else { return .failure(.targetOutsidePool(argv[2])) }
            guard argv[2].contains("@") else { return .failure(.destroyTargetIsNotSnapshot(argv[2])) }
            return .success(argv)

        default:
            return .failure(.disallowedSubcommand(argv[1]))
        }
    }

    /// A dataset/snapshot arg is in scope iff it is the pool itself or a child (`pool/…`) or a
    /// snapshot of the pool root (`pool@…`). Prevents a push key from touching any other pool.
    private func withinPool(_ target: String) -> Bool {
        target == pool || target.hasPrefix(pool + "/") || target.hasPrefix(pool + "@")
    }

    private static func isValidPoolName(_ pool: String) -> Bool {
        guard !pool.isEmpty, pool.trimmingCharacters(in: .whitespacesAndNewlines) == pool else {
            return false
        }
        return !pool.contains("/") && !pool.contains("@") && !pool.contains("#")
    }

    /// POSIX-ish word tokenizer covering exactly what `String.shellQuoted` can produce: whitespace
    /// separates words; a single-quoted run is literal until its closing quote; a backslash escapes
    /// the next character (so the `'\''` idiom for an embedded quote round-trips). Adjacent runs with
    /// no whitespace between them join into one word. Returns nil only on an unterminated quote.
    public static func tokenize(_ command: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var haveWord = false
        var index = command.startIndex

        func endWord() {
            if haveWord {
                words.append(current)
                current = ""
                haveWord = false
            }
        }

        while index < command.endIndex {
            let character = command[index]
            switch character {
            case " ", "\t", "\n", "\r":
                endWord()
                index = command.index(after: index)
            case "'":
                haveWord = true
                index = command.index(after: index)
                while index < command.endIndex, command[index] != "'" {
                    current.append(command[index])
                    index = command.index(after: index)
                }
                guard index < command.endIndex else { return nil }  // unterminated quote
                index = command.index(after: index)  // consume closing quote
            case "\\":
                haveWord = true
                index = command.index(after: index)
                if index < command.endIndex {
                    current.append(command[index])
                    index = command.index(after: index)
                }
            default:
                haveWord = true
                current.append(character)
                index = command.index(after: index)
            }
        }
        endWord()
        return words
    }
}
