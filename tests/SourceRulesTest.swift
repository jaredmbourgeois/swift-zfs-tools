// SourceRulesTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import Foundation
import XCTest

// The package's two house rules, held by a scan of its own `sources/` and `tests/` that runs under
// `swift test`:
//
//  1. No default arguments. No `func`, `init`, `subscript` or `macro` parameter and no enum associated
//     value carries `= value`, except a caller-context capture (`#line` and its family), where the
//     default is the mechanism. (An `@Option`'s or `@Flag`'s initial value is not a parameter default:
//     it is the command line's own default, declared once in the parser.)
//  2. Inject, never reach. A platform accessor (the reach vocabulary below) is named only at the
//     package's reach sites — the two composition-root files, the file-system witness's live factory
//     and the test target's root — on a line marked with why; and no file outside those names a live
//     value at all — `tests/` never does.
//
// The match is lexical: comments and string literals are blanked first, then declarations and tokens
// are matched as text. It therefore cannot see a default respelled as a forwarding overload or as an
// in-body `??` fallback, a reach through an API the vocabulary does not list (`URL(fileURLWithPath:)`
// reading a relative path against the working directory, say), a regex literal (read as code), or a
// declaration whose name and `(` are on different lines. Those stay a reviewer's job.
//
// `SourceRulesTest` runs the scan over the tree, and proves the scan can fail by feeding it planted
// violations (and their near misses) as in-memory sources.
//
// The scanner (`SourceFile`, `SourceViews`, `SourceRules`' three scans) is swift-shell's, whose
// `Tests/ShellTest/SourceRulesTest.swift` this file follows; the reach sites and the vocabulary's
// second half are this package's own.

/// One Swift file handed to the rules: its path relative to the package root, and its text.
struct SourceFile {
    let path: String
    let text: String
}

/// A source text split into the two views the rules read. Each has the text's length and line breaks,
/// so a line number in a view is a line number in the file.
struct SourceViews {
    /// The text with every comment and the literal characters of every string blanked to spaces. Code
    /// inside a string interpolation is code and stays.
    let code: String
    /// The text with everything except comments blanked to spaces.
    let comments: String

    var codeLines: [String] { code.components(separatedBy: "\n") }
    var commentLines: [String] { comments.components(separatedBy: "\n") }

    private enum LexicalContext {
        /// Code: the file's top level, or the inside of a string interpolation, where
        /// `unclosedParentheses` counts the `(` opened since the interpolation began.
        case code(isInterpolation: Bool, unclosedParentheses: Int)
        /// The characters of a string literal that closes with `"` (three of them when `isMultiline`)
        /// followed by `poundCount` `#` characters.
        case string(isMultiline: Bool, poundCount: Int)
        /// A `/* … */` comment. They nest; `depth` counts how deep.
        case blockComment(depth: Int)
    }

    init(text: String) {
        let bytes = Array(text.utf8)
        var code = bytes
        var comments = bytes.map { $0 == ASCII.newline ? ASCII.newline : ASCII.space }

        func blank(_ range: Range<Int>, in view: inout [UInt8]) {
            for index in range where view[index] != ASCII.newline {
                view[index] = ASCII.space
            }
        }
        func moveToComments(_ range: Range<Int>) {
            for index in range {
                comments[index] = bytes[index]
            }
            blank(range, in: &code)
        }
        func bytesMatch(_ expected: [UInt8], at index: Int) -> Bool {
            index + expected.count <= bytes.count && Array(bytes[index..<(index + expected.count)]) == expected
        }
        // The length of a string literal's closing (or opening) delimiter at `index`, or nil when there
        // is none there: one or three `"`, then exactly the literal's `#` characters.
        func delimiterLength(at index: Int, isMultiline: Bool, poundCount: Int) -> Int? {
            let quotes = [UInt8](repeating: ASCII.quote, count: isMultiline ? 3 : 1)
            let pounds = [UInt8](repeating: ASCII.pound, count: poundCount)
            return bytesMatch(quotes + pounds, at: index) ? quotes.count + pounds.count : nil
        }

        var contexts: [LexicalContext] = [.code(isInterpolation: false, unclosedParentheses: 0)]
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            switch contexts[contexts.count - 1] {
            case .code(let isInterpolation, let unclosedParentheses):
                if bytesMatch([ASCII.slash, ASCII.slash], at: index) {
                    var lineEnd = index
                    while lineEnd < bytes.count, bytes[lineEnd] != ASCII.newline {
                        lineEnd += 1
                    }
                    moveToComments(index..<lineEnd)
                    index = lineEnd
                } else if bytesMatch([ASCII.slash, ASCII.asterisk], at: index) {
                    moveToComments(index..<(index + 2))
                    contexts.append(.blockComment(depth: 1))
                    index += 2
                } else if byte == ASCII.quote || byte == ASCII.pound {
                    // A string opens with `"` or `"""`, after any number of `#` (a raw string). A `#`
                    // that leads to no quote is code: `#if`, `#line`.
                    var poundCount = 0
                    while index + poundCount < bytes.count, bytes[index + poundCount] == ASCII.pound {
                        poundCount += 1
                    }
                    let quoteIndex = index + poundCount
                    if quoteIndex < bytes.count, bytes[quoteIndex] == ASCII.quote {
                        let isMultiline = bytesMatch([ASCII.quote, ASCII.quote, ASCII.quote], at: quoteIndex)
                        contexts.append(.string(isMultiline: isMultiline, poundCount: poundCount))
                        index = quoteIndex + (isMultiline ? 3 : 1)
                    } else {
                        index += 1
                    }
                } else if isInterpolation, byte == ASCII.openParenthesis {
                    contexts[contexts.count - 1] = .code(isInterpolation: true, unclosedParentheses: unclosedParentheses + 1)
                    index += 1
                } else if isInterpolation, byte == ASCII.closeParenthesis {
                    if unclosedParentheses == 0 {
                        contexts.removeLast()  // the `)` that ends the interpolation: back in the string
                    } else {
                        contexts[contexts.count - 1] = .code(isInterpolation: true, unclosedParentheses: unclosedParentheses - 1)
                    }
                    index += 1
                } else {
                    index += 1
                }

            case .string(let isMultiline, let poundCount):
                if let closingLength = delimiterLength(at: index, isMultiline: isMultiline, poundCount: poundCount) {
                    contexts.removeLast()
                    index += closingLength
                } else if byte == ASCII.backslash,
                          bytesMatch([UInt8](repeating: ASCII.pound, count: poundCount), at: index + 1) {
                    // A backslash (plus the literal's `#` characters) starts an interpolation when a `(`
                    // follows, and otherwise escapes the next character — which may be a quote that
                    // must not be read as the closing one.
                    let escapedIndex = index + 1 + poundCount
                    let endOfEscape = min(escapedIndex + 1, bytes.count)
                    blank(index..<endOfEscape, in: &code)
                    if escapedIndex < bytes.count, bytes[escapedIndex] == ASCII.openParenthesis {
                        contexts.append(.code(isInterpolation: true, unclosedParentheses: 0))
                    }
                    index = endOfEscape
                } else {
                    blank(index..<(index + 1), in: &code)
                    index += 1
                }

            case .blockComment(let depth):
                if bytesMatch([ASCII.slash, ASCII.asterisk], at: index) {
                    moveToComments(index..<(index + 2))
                    contexts[contexts.count - 1] = .blockComment(depth: depth + 1)
                    index += 2
                } else if bytesMatch([ASCII.asterisk, ASCII.slash], at: index) {
                    moveToComments(index..<(index + 2))
                    if depth == 1 {
                        contexts.removeLast()
                    } else {
                        contexts[contexts.count - 1] = .blockComment(depth: depth - 1)
                    }
                    index += 2
                } else {
                    moveToComments(index..<(index + 1))
                    index += 1
                }
            }
        }
        self.code = String(decoding: code, as: UTF8.self)
        self.comments = String(decoding: comments, as: UTF8.self)
    }
}

/// The ASCII bytes the scan names.
private enum ASCII {
    static let newline = UInt8(ascii: "\n")
    static let space = UInt8(ascii: " ")
    static let slash = UInt8(ascii: "/")
    static let asterisk = UInt8(ascii: "*")
    static let quote = UInt8(ascii: "\"")
    static let pound = UInt8(ascii: "#")
    static let backslash = UInt8(ascii: "\\")
    static let period = UInt8(ascii: ".")
    static let comma = UInt8(ascii: ",")
    static let colon = UInt8(ascii: ":")
    static let semicolon = UInt8(ascii: ";")
    static let equals = UInt8(ascii: "=")
    static let exclamationMark = UInt8(ascii: "!")
    static let lessThan = UInt8(ascii: "<")
    static let underscore = UInt8(ascii: "_")
    static let openParenthesis = UInt8(ascii: "(")
    static let closeParenthesis = UInt8(ascii: ")")
    static let openBracket = UInt8(ascii: "[")
    static let closeBracket = UInt8(ascii: "]")
    static let openBrace = UInt8(ascii: "{")
    static let closeBrace = UInt8(ascii: "}")

    static let openers: Set<UInt8> = [openParenthesis, openBracket, openBrace]
    static let closers: Set<UInt8> = [closeParenthesis, closeBracket, closeBrace]

    /// A byte that can be part of an identifier or keyword. Bytes above 127 belong to a non-ASCII
    /// character, which Swift allows in identifiers.
    static func isIdentifierByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"), underscore:
            true
        default:
            byte > 127
        }
    }
}

enum SourceRules {
    /// The files where a reach is legal and a marker is honored — a closed list, one file per site:
    ///   - the builder's composition root (`zfs-tools-build`'s `run()`);
    ///   - the command target's composition root: every `zfs-tools` command's `run()` gets its live
    ///     values from this one file, so the command files themselves name none;
    ///   - the file-system witness's live factory, the model's one live implementation;
    ///   - the test target's root.
    /// A new reach belongs in one of these, or it is a finding.
    static let reachSites: Set<String> = [
        "sources/builder/BuildCommand.swift",
        "sources/command/CommandRoot.swift",
        "sources/model/FileSystemLive.swift",
        "tests/TestRoot.swift",
    ]

    // MARK: - No default arguments

    /// The defaults that are the mechanism, not a value a caller forgot: each captures where the call
    /// was written.
    static let callerContextCaptures: Set<String> = [
        "#file", "#fileID", "#filePath", "#function", "#line", "#column", "#dsohandle", "#isolation",
        "#_sourceLocation",
    ]

    /// One finding per parameter or associated value that declares a default other than a
    /// caller-context capture.
    static func defaultArgumentFindings(in files: [SourceFile]) -> [String] {
        var findings: [String] = []
        for file in files {
            let code = Array(SourceViews(text: file.text).code.utf8)
            for clause in parameterClauses(in: code) {
                for parameter in topLevelParts(of: clause, in: code) {
                    guard let equalsIndex = defaultValueEquals(in: parameter, of: code) else { continue }
                    let defaultValue = String(decoding: code[(equalsIndex + 1)..<parameter.upperBound], as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if callerContextCaptures.contains(defaultValue) { continue }
                    let line = code[..<equalsIndex].filter { $0 == ASCII.newline }.count + 1
                    let parameterText = String(decoding: code[parameter], as: UTF8.self)
                        .split(whereSeparator: \.isWhitespace)
                        .joined(separator: " ")
                    findings.append("\(file.path):\(line): default argument: \(parameterText)")
                }
            }
        }
        return findings
    }

    /// The parameter clauses of every declaration in `code` that could carry a default: the text
    /// between the parentheses of each `func`, `init`, `subscript` and `macro`, and of each `case`
    /// payload.
    private static func parameterClauses(in code: [UInt8]) -> [Range<Int>] {
        var clauses: [Range<Int>] = []
        var index = 0
        while index < code.count {
            guard ASCII.isIdentifierByte(code[index]) else {
                index += 1
                continue
            }
            let wordStart = index
            while index < code.count, ASCII.isIdentifierByte(code[index]) {
                index += 1
            }
            // `.init(…)` is a call, and a call's arguments are not declarations.
            let isMemberAccess = wordStart > 0 && code[wordStart - 1] == ASCII.period
            if isMemberAccess { continue }
            switch String(decoding: code[wordStart..<index], as: UTF8.self) {
            case "func", "init", "subscript", "macro":
                if let clause = declarationClause(after: index, in: code) {
                    clauses.append(clause)
                }
            case "case":
                clauses.append(contentsOf: payloadClauses(after: index, in: code))
            default:
                break
            }
        }
        return clauses
    }

    /// The clause opened by the first `(` after a declaration keyword, when only the declaration's name
    /// and generic parameters stand between them. A `{`, `}`, `;`, `)` or line break first means the
    /// keyword did not introduce a parameter list.
    private static func declarationClause(after keywordEnd: Int, in code: [UInt8]) -> Range<Int>? {
        var cursor = keywordEnd
        while cursor < code.count {
            switch code[cursor] {
            case ASCII.openParenthesis:
                guard let close = matchingCloser(ofOpenerAt: cursor, in: code) else { return nil }
                return (cursor + 1)..<close
            case ASCII.openBrace, ASCII.closeBrace, ASCII.semicolon, ASCII.closeParenthesis, ASCII.newline:
                return nil
            default:
                cursor += 1
            }
        }
        return nil
    }

    /// The parenthesised groups after a `case` keyword on its line, up to a `:` outside any group: an
    /// enum case's associated values (`case failed(code: Int)`) or — harmlessly, since a pattern holds
    /// no `=` — a `switch` case's pattern.
    private static func payloadClauses(after keywordEnd: Int, in code: [UInt8]) -> [Range<Int>] {
        var clauses: [Range<Int>] = []
        var cursor = keywordEnd
        while cursor < code.count {
            switch code[cursor] {
            case ASCII.newline, ASCII.colon:
                return clauses
            case ASCII.openParenthesis:
                guard let close = matchingCloser(ofOpenerAt: cursor, in: code) else { return clauses }
                clauses.append((cursor + 1)..<close)
                cursor = close + 1
            default:
                cursor += 1
            }
        }
        return clauses
    }

    /// The index of the `)`, `]` or `}` that closes the opener at `openerIndex`.
    private static func matchingCloser(ofOpenerAt openerIndex: Int, in code: [UInt8]) -> Int? {
        var depth = 0
        for cursor in openerIndex..<code.count {
            if ASCII.openers.contains(code[cursor]) {
                depth += 1
            } else if ASCII.closers.contains(code[cursor]) {
                depth -= 1
                if depth == 0 { return cursor }
            }
        }
        return nil
    }

    /// `clause` split at the commas that are not inside a nested `()`, `[]` or `{}`: one range per
    /// parameter. (A comma between generic arguments also splits; a piece of a parameter still holds
    /// that parameter's `=`, so nothing is missed.)
    private static func topLevelParts(of clause: Range<Int>, in code: [UInt8]) -> [Range<Int>] {
        var parts: [Range<Int>] = []
        var partStart = clause.lowerBound
        var depth = 0
        for cursor in clause {
            if ASCII.openers.contains(code[cursor]) {
                depth += 1
            } else if ASCII.closers.contains(code[cursor]) {
                depth -= 1
            } else if code[cursor] == ASCII.comma, depth == 0 {
                parts.append(partStart..<cursor)
                partStart = cursor + 1
            }
        }
        parts.append(partStart..<clause.upperBound)
        return parts
    }

    /// The index of the `=` that introduces `parameter`'s default value, or nil when it has none: the
    /// first `=` outside any nested `()`, `[]` or `{}` that is not half of `==`, `!=` or `<=`.
    private static func defaultValueEquals(in parameter: Range<Int>, of code: [UInt8]) -> Int? {
        var depth = 0
        for cursor in parameter {
            if ASCII.openers.contains(code[cursor]) {
                depth += 1
            } else if ASCII.closers.contains(code[cursor]) {
                depth -= 1
            } else if code[cursor] == ASCII.equals, depth == 0 {
                let previous = cursor > parameter.lowerBound ? code[cursor - 1] : ASCII.space
                let next = cursor + 1 < parameter.upperBound ? code[cursor + 1] : ASCII.space
                let isHalfOfAnOperator = [ASCII.equals, ASCII.exclamationMark, ASCII.lessThan].contains(previous)
                    || next == ASCII.equals
                if !isHalfOfAnOperator { return cursor }
            }
        }
        return nil
    }

    // MARK: - Inject, never reach

    /// The platform accessors a function must be handed instead of naming. Each pattern is matched
    /// against one line of the code view.
    static let reachVocabulary: [(name: String, pattern: String)] = [
        ("FileManager.default", #"\bFileManager\s*\.\s*default\b"#),
        ("FileManager()", #"\bFileManager\s*(\.\s*init\s*)?\(\s*\)"#),
        ("ProcessInfo.processInfo", #"\bProcessInfo\s*\.\s*processInfo\b"#),
        ("Date()", #"\bDate\s*(\.\s*init\s*)?\(\s*\)"#),
        ("Date.now", #"\bDate\s*\.\s*now\b"#),
        ("UUID()", #"\bUUID\s*(\.\s*init\s*)?\(\s*\)"#),
        ("URLSession.shared", #"\bURLSession\s*\.\s*shared\b"#),
        ("UserDefaults.standard", #"\bUserDefaults\s*\.\s*standard\b"#),
        ("Locale.current", #"\bLocale\s*\.\s*current\b"#),
        ("TimeZone.current", #"\bTimeZone\s*\.\s*current\b"#),
        ("Calendar.current", #"\bCalendar\s*\.\s*current\b"#),
        ("Bundle.main", #"\bBundle\s*\.\s*main\b"#),
        ("NotificationCenter.default", #"\bNotificationCenter\s*\.\s*default\b"#),
        ("DispatchQueue.main", #"\bDispatchQueue\s*\.\s*main\b"#),
        // What a command-line tool reaches beyond those: its standard streams, a process it spawns
        // itself, a file it opens by path, the environment, its arguments, a sleep.
        ("print or debugPrint", #"\b(print|debugPrint)\s*\("#),
        ("FileHandle.standardOutput, .standardError or .standardInput", #"\bFileHandle\s*\.\s*standard(Output|Error|Input)\b"#),
        ("Process()", #"\bProcess\s*(\.\s*init\s*)?\(\s*\)"#),
        ("Data(contentsOf:) or String(contentsOf:)", #"\b(Data|String)\s*(\.\s*init\s*)?\(\s*contentsOf\s*:"#),
        (".write(to:)", #"\.\s*write\s*\(\s*to\s*:"#),
        ("getenv", #"\bgetenv\s*\("#),
        ("CommandLine.arguments", #"\bCommandLine\s*\.\s*arguments\b"#),
        ("NSTemporaryDirectory()", #"\bNSTemporaryDirectory\s*\("#),
        ("Task.sleep or Thread.sleep", #"\b(Task|Thread)\s*\.\s*sleep\b"#),
        // The same accessors with the type left to inference (`date: .now`, `session: .shared`): a
        // member that follows no value. An unrelated member that happens to share one of these names
        // is fixed by spelling its type, never by a marker.
        ("an implicit .now, .current, .shared, .standard, .default or .main", #"(^|[^\w)\]?!>])\.(now|current|shared|standard|default|main)\b"#),
    ]

    /// A regex matched against one line of a view. `\b` is made the plain identifier boundary: Swift's
    /// default word boundary treats `a.b` as a single word, so `\bdefault\b` would not match the
    /// `default` in `FileManager.default.fileExists` — the reach would hide behind its own member access.
    private static func sourcePattern(_ pattern: String) throws -> Regex<AnyRegexOutput> {
        try Regex(pattern).wordBoundaryKind(.simple)
    }

    /// One finding per reach outside a reach site, per unmarked reach inside one, and per marker that
    /// is outside a reach site or gives no reason.
    static func reachFindings(in files: [SourceFile], reachSites: Set<String>) throws -> [String] {
        let vocabulary = try reachVocabulary.map { entry in (name: entry.name, regex: try sourcePattern(entry.pattern)) }
        // A marker is a comment that begins with the word, so prose that merely mentions it is not one.
        let markerOpening = try sourcePattern(#"//\s*reach-ok:"#)
        var findings: [String] = []
        for file in files {
            let views = SourceViews(text: file.text)
            let commentLines = views.commentLines
            let isReachSite = reachSites.contains(file.path)
            for (lineIndex, codeLine) in views.codeLines.enumerated() {
                let location = "\(file.path):\(lineIndex + 1)"
                var lineIsExempt = false
                if let marker = commentLines[lineIndex].firstMatch(of: markerOpening) {
                    let reason = commentLines[lineIndex][marker.range.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !isReachSite {
                        findings.append("\(location): a reach-ok marker is honored only in a live implementation or a composition root")
                    } else if reason.isEmpty {
                        findings.append("\(location): a reach-ok marker needs a reason")
                    } else {
                        lineIsExempt = true
                    }
                }
                if lineIsExempt { continue }
                for entry in vocabulary where codeLine.contains(entry.regex) {
                    if isReachSite {
                        findings.append("\(location): \(entry.name) needs a reach-ok marker with a reason on its line")
                    } else {
                        findings.append("\(location): \(entry.name) is a reach: only a live implementation or a composition root may name it")
                    }
                }
            }
        }
        return findings
    }

    /// One finding per line that names a live value (`.live`) where it may not be named: anywhere
    /// under `tests/` — a test builds its doubles through test-support factories — and in any source
    /// file that is not a reach site.
    static func liveValueFindings(in files: [SourceFile], reachSites: Set<String>) throws -> [String] {
        let liveMember = try sourcePattern(#"\.live\b"#)
        var findings: [String] = []
        for file in files {
            let isTestFile = file.path.hasPrefix("tests/")
            if !isTestFile, reachSites.contains(file.path) { continue }
            for (lineIndex, codeLine) in SourceViews(text: file.text).codeLines.enumerated() where codeLine.contains(liveMember) {
                let who = isTestFile ? "a test" : "logic"
                findings.append("\(file.path):\(lineIndex + 1): \(who) names the live implementation (.live)")
            }
        }
        return findings
    }
}

final class SourceRulesTest: XCTestCase {
    // MARK: - The tree

    func testTreeDeclaresNoDefaultArguments() throws {
        let findings = SourceRules.defaultArgumentFindings(in: try TestRoot.packageSwiftFiles())
        XCTAssertEqual([], findings, "\n" + findings.joined(separator: "\n"))
    }

    func testTreeHoldsNoReachOutsideItsReachSites() throws {
        let findings = try SourceRules.reachFindings(in: try TestRoot.packageSwiftFiles(), reachSites: SourceRules.reachSites)
        XCTAssertEqual([], findings, "\n" + findings.joined(separator: "\n"))
    }

    func testTreeNamesTheLiveFactoryNowhereItMayNot() throws {
        let findings = try SourceRules.liveValueFindings(in: try TestRoot.packageSwiftFiles(), reachSites: SourceRules.reachSites)
        XCTAssertEqual([], findings, "\n" + findings.joined(separator: "\n"))
    }

    /// An empty scan passes every rule, so a moved `sources/` must fail here instead: the scan saw
    /// files, and among them the ones the rules single out.
    func testScanSawTheTree() throws {
        let paths = Set(try TestRoot.packageSwiftFiles().map(\.path))
        XCTAssertTrue(paths.contains { $0.hasPrefix("sources/builder/") })
        XCTAssertTrue(paths.contains { $0.hasPrefix("sources/command/") })
        XCTAssertTrue(paths.contains { $0.hasPrefix("sources/model/") })
        XCTAssertTrue(paths.contains { $0.hasPrefix("tests/") })
        XCTAssertTrue(paths.contains("sources/model/Syncer.swift"))
        XCTAssertTrue(paths.contains("tests/SourceRulesTest.swift"))
        for reachSite in SourceRules.reachSites {
            XCTAssertTrue(paths.contains(reachSite), "\(reachSite) is a reach site the scan did not find")
        }
        for file in try TestRoot.packageSwiftFiles() {
            XCTAssertFalse(file.text.isEmpty, "\(file.path) was read as empty")
        }
    }

    // MARK: - The scan can fail: default arguments

    private func logicFile(_ text: String) -> [SourceFile] {
        [SourceFile(path: "sources/model/Logic.swift", text: text)]
    }

    private func testFile(_ text: String) -> [SourceFile] {
        [SourceFile(path: "tests/LogicTest.swift", text: text)]
    }

    private func liveFile(_ text: String) -> [SourceFile] {
        [SourceFile(path: "sources/model/FileSystemLive.swift", text: text)]
    }

    /// Every kind of declaration that can carry a default is caught when it does.
    func testScanFlagsAPlantedDefaultArgument() {
        let plants: [(kind: String, source: String)] = [
            ("func", #"func run(timeout: Double = 3) {}"#),
            ("func, unlabelled", #"static func makeDateFormatter(_ dateFormat: String = "yyyyMMdd-HHmmss") -> DateFormatter { fatalError() }"#),
            ("func, nil", #"func sync(sendRateLimit: String? = nil) {}"#),
            ("func, generic type", #"func run(environment: Dictionary<String, String> = [:]) {}"#),
            ("func, no spaces", #"func run(limit: Optional<Int>=nil) {}"#),
            ("generic func", #"func decode<Output: Decodable>(decoder: JSONDecoder = JSONDecoder()) throws -> Output { fatalError() }"#),
            ("init", #"init(pruneRemoteSnapshots: Bool = true) {}"#),
            ("failable init", #"init?(rawValue: String, isLenient: Bool = true) { nil }"#),
            ("subscript", #"subscript(index: Int = 0) -> Int { 0 }"#),
            ("enum case", #"enum Failure { case failed(code: Int = 1) }"#),
            ("second enum case on a line", #"enum Failure { case stopped(Int), failed(code: Int = 1) }"#),
            ("macro", #"macro stringify(value: Int = 1) -> String = #externalMacro(module: "M", type: "T")"#),
            ("closure default over several lines", #"""
                func makeSnapshotter(
                    date: @escaping @Sendable () -> Date = {
                        Date()
                    },
                    encoding: String.Encoding
                ) {}
                """#),
        ]
        for plant in plants {
            let findings = SourceRules.defaultArgumentFindings(in: logicFile(plant.source))
            XCTAssertEqual(1, findings.count, "\(plant.kind): \(findings)")
        }
        // The rule covers test code as well as sources, and names the line.
        let inATest = SourceRules.defaultArgumentFindings(in: testFile("import XCTest\n\nfunc makeScript(directory: String = \"/tmp\") {}\n"))
        XCTAssertEqual(1, inATest.count)
        XCTAssertEqual(true, inATest.first?.hasPrefix("tests/LogicTest.swift:3:"), "\(inATest)")
    }

    /// A caller-context capture is the one default that passes: `#line` and each of its family.
    func testScanPassesACallerContextCapture() {
        let assertion = #"func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {}"#
        XCTAssertEqual([], SourceRules.defaultArgumentFindings(in: testFile(assertion)))
        for capture in SourceRules.callerContextCaptures {
            let findings = SourceRules.defaultArgumentFindings(in: logicFile("func record(location: Any = \(capture)) {}"))
            XCTAssertEqual([], findings, capture)
        }
        // Only the capture itself passes: a default that merely starts with one does not.
        let dressedUp = SourceRules.defaultArgumentFindings(in: logicFile(#"func record(line: UInt = #line + 1) {}"#))
        XCTAssertEqual(1, dressedUp.count)
    }

    /// An `=` that is not a parameter default is no finding: assignments, comparisons, calls, patterns,
    /// and anything in a comment or a string.
    func testScanPassesDefaultArgumentNearMisses() {
        let source = #"""
            // func run(timeout: Double = 3) {}
            /* init(name: String = "x") {} */
            struct Logic: Equatable {
                let limit = 3
                let handler: (Int) -> Void = { _ in }
                let text = "func run(timeout: Double = 3) {}"
                init(limit: Int) { self.limit = limit }
                func run(timeout: Double, compare: (Int, Int) -> Bool) -> Bool {
                    let doubled = timeout == 3 ? 6 : timeout
                    let shell = Shell.init(execute: { command in command })
                    let result: Result = .init(reason: .exit, status: doubled >= 6 ? 0 : 1)
                    return compare(1, 2)
                }
                static func == (lhs: Logic, rhs: Logic) -> Bool { lhs.limit == rhs.limit }
                static func <= (lhs: Logic, rhs: Logic) -> Bool { lhs.limit <= rhs.limit }
            }
            enum Failure { case failed(code: Int), stopped }
            func describe(_ failure: Failure) -> String {
                if case .failed(let code) = failure, code != 0 { return "failed" }
                switch failure {
                case .failed(let code) where code == 1: return "one"
                case .failed, .stopped: return "other"
                }
            }
            """#
        XCTAssertEqual([], SourceRules.defaultArgumentFindings(in: logicFile(source)))
    }

    // MARK: - The scan can fail: reaches and markers

    /// Every entry of the reach vocabulary is caught, in a source file and in a test file alike.
    func testScanFlagsEachPlantedReach() throws {
        let plants = [
            #"let manager = FileManager.default"#,
            #"let exists = FileManager.default.fileExists(atPath: path)"#,
            #"let manager = FileManager()"#,
            #"let manager = FileManager.init()"#,
            #"let environment = ProcessInfo.processInfo.environment"#,
            #"let now = Date()"#,
            #"let seconds = Date().timeIntervalSince1970"#,
            #"let now = Date.now"#,
            #"let later = Date.now.addingTimeInterval(60)"#,
            #"let now: Date = .now"#,
            #"let clock = Clock(date: { .now })"#,
            #"let identifier = UUID()"#,
            #"let identifier = UUID().uuidString"#,
            #"let name = "run-\(UUID())""#,
            #"let session = URLSession.shared"#,
            #"let client = Client(session: .shared)"#,
            #"let defaults = UserDefaults.standard"#,
            #"let store: UserDefaults = .standard"#,
            #"let locale = Locale.current"#,
            #"calendar.locale = .current"#,
            #"let timeZone = TimeZone.current"#,
            #"let calendar = Calendar.current"#,
            #"let bundle = Bundle.main"#,
            #"let center = NotificationCenter.default"#,
            #"observe(center: .default)"#,
            #"let queue = DispatchQueue.main"#,
            #"run(on: .main)"#,
            #"print("zfs-tools snapshot: WARNING")"#,
            #"debugPrint(utilization)"#,
            #"FileHandle.standardError.write(Data(line.utf8))"#,
            #"let output = FileHandle.standardOutput"#,
            #"let input = FileHandle.standardInput.availableData"#,
            #"let process = Process()"#,
            #"let data = try Data(contentsOf: url)"#,
            #"let text = try String(contentsOf: url, encoding: .utf8)"#,
            #"try data.write(to: url, options: .atomic)"#,
            #"let searchPath = getenv("PATH")"#,
            #"let arguments = CommandLine.arguments"#,
            #"let directory = NSTemporaryDirectory()"#,
            #"try await Task.sleep(nanoseconds: 1_000_000)"#,
            #"Thread.sleep(forTimeInterval: 1)"#,
        ]
        for plant in plants {
            let inLogic = try SourceRules.reachFindings(in: logicFile(plant), reachSites: SourceRules.reachSites)
            XCTAssertEqual(1, inLogic.count, "\(plant): \(inLogic)")
            let inATest = try SourceRules.reachFindings(in: testFile(plant), reachSites: SourceRules.reachSites)
            XCTAssertEqual(1, inATest.count, "\(plant): \(inATest)")
        }
    }

    /// Names that only look like the vocabulary, a value built from fixed inputs, and anything in a
    /// comment or a string literal are no finding.
    func testScanPassesReachNearMisses() throws {
        let source = #"""
            // FileManager.default would be a reach here; so would Date().
            /* UUID() */
            let text = "FileManager.default and Date() and .now"
            let epoch = Date(timeIntervalSince1970: 0)
            let fixed = UUID(uuidString: "00000000-0000-0000-0000-000000000000")
            let update = lastUpdate()
            let mine = MyDate()
            let instant = clock.now
            let value = settings.current
            let status: Status = .defaultSuccessStatus
            let other = registry.shared.standard.main
            let blueprint = fingerprint(of: snapshot)
            let reason = Process.TerminationReason.exit
            try fileSystem.write(data, path)
            let bytes = Data(line.utf8)
            let decoded = String(data: bytes, encoding: .utf8)
            let dryRunShell = ShellAtPath.dryRun(shellObserver: nil, stringEncoding: .utf8)
            """#
        XCTAssertEqual([], try SourceRules.reachFindings(in: logicFile(source), reachSites: SourceRules.reachSites))
    }

    /// In the live implementation a reach passes when its line says why — and only then.
    func testScanPassesAMarkedReachInTheLiveFileOnly() throws {
        let marked = #"isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }  // reach-ok: the live executable probe"#
        XCTAssertEqual([], try SourceRules.reachFindings(in: liveFile(marked), reachSites: SourceRules.reachSites))

        let unmarked = #"isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }"#
        XCTAssertEqual(1, try SourceRules.reachFindings(in: liveFile(unmarked), reachSites: SourceRules.reachSites).count)

        let noReason = #"isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }  // reach-ok:"#
        // Two findings: the marker has no reason, so it exempts nothing and the reach stands too.
        XCTAssertEqual(2, try SourceRules.reachFindings(in: liveFile(noReason), reachSites: SourceRules.reachSites).count)

        // The marker covers its own line, not the next one.
        let markerOnAnotherLine = "// reach-ok: the live clock\nlet now = Date()\n"
        XCTAssertEqual(1, try SourceRules.reachFindings(in: liveFile(markerOnAnotherLine), reachSites: SourceRules.reachSites).count)
    }

    /// A marker anywhere but a reach site exempts nothing and is itself a finding: adding one to make a
    /// reach pass is the violation.
    func testScanRefusesAMarkerOutsideAReachSite() throws {
        let marked = #"let now = Date()  // reach-ok: just this once"#
        // Two findings each: the refused marker, and the reach it did not exempt.
        XCTAssertEqual(2, try SourceRules.reachFindings(in: logicFile(marked), reachSites: SourceRules.reachSites).count)
        XCTAssertEqual(2, try SourceRules.reachFindings(in: testFile(marked), reachSites: SourceRules.reachSites).count)

        let markerAlone = #"let limit = 3  // reach-ok: nothing to exempt"#
        XCTAssertEqual(1, try SourceRules.reachFindings(in: testFile(markerAlone), reachSites: SourceRules.reachSites).count)

        // The word in a string, or mentioned in the middle of a comment, is not a marker.
        let mentions = #"""
            let note = "// reach-ok: not a comment"
            // A line that names the live file system carries a reach-ok marker with its reason.
            """#
        XCTAssertEqual([], try SourceRules.reachFindings(in: testFile(mentions), reachSites: SourceRules.reachSites))
    }

    // MARK: - The scan can fail: naming the live factory

    /// A test may not name a live value, however it spells the reference — not even the test
    /// target's root, where a marker would be honored. Nor may logic, nor a command file: the
    /// command target names its live values in its one root file.
    func testScanFlagsALiveValueNamedInATest() throws {
        let plants = [
            #"let shell = ShellAtPath.live(shellPath: "/bin/bash", environment: [:], workingDirectory: "/", terminationGracePeriod: 2, shellObserver: nil, stringEncoding: .utf8)"#,
            #"let shell: ShellAtPath = .live(shellPath: "/bin/bash", environment: [:], workingDirectory: "/", terminationGracePeriod: 2, shellObserver: nil, stringEncoding: .utf8)"#,
            #"let makeShell = ShellAtPath.live"#,
            #"let fileSystem = FileSystem.live"#,
            #"let contents = try FileSystem.live.contents(path)"#,
        ]
        for plant in plants {
            XCTAssertEqual(1, try SourceRules.liveValueFindings(in: testFile(plant), reachSites: SourceRules.reachSites).count, plant)
            let inTheTestRoot = [SourceFile(path: "tests/TestRoot.swift", text: plant)]
            XCTAssertEqual(1, try SourceRules.liveValueFindings(in: inTheTestRoot, reachSites: SourceRules.reachSites).count, plant)
            XCTAssertEqual(1, try SourceRules.liveValueFindings(in: logicFile(plant), reachSites: SourceRules.reachSites).count, plant)
            let inACommandFile = [SourceFile(path: "sources/command/Sync.swift", text: plant)]
            XCTAssertEqual(1, try SourceRules.liveValueFindings(in: inACommandFile, reachSites: SourceRules.reachSites).count, plant)
            // The composition root is where a live value is named.
            let inTheCommandRoot = [SourceFile(path: "sources/command/CommandRoot.swift", text: plant)]
            XCTAssertEqual([], try SourceRules.liveValueFindings(in: inTheCommandRoot, reachSites: SourceRules.reachSites), plant)
        }
    }

    /// Declaring the live value in the live file, and names that merely contain the word, pass.
    func testScanPassesLiveValueNearMisses() throws {
        let declaration = #"extension FileSystem { public static let live = FileSystem(contents: readFile, write: writeFile, isExecutableFile: probe) }"#
        XCTAssertEqual([], try SourceRules.liveValueFindings(in: liveFile(declaration), reachSites: SourceRules.reachSites))
        let lookalikes = #"""
            // ShellAtPath.live is the live wiring.
            let text = "ShellAtPath.live"
            let isLive = probe.liveness > 0
            let delivered = queue.delivered
            """#
        XCTAssertEqual([], try SourceRules.liveValueFindings(in: testFile(lookalikes), reachSites: SourceRules.reachSites))
    }

    // MARK: - The two views

    /// Comments and string text are blanked from the code view, line for line; code inside a string
    /// interpolation stays; and the comment view holds the comments alone.
    func testViewsSeparateCodeFromCommentsAndStrings() {
        let source = #"""
            let a = 1 // trailing Date()
            let b = "Date() \(UUID()) \"quoted\" // not a comment"
            /* block /* nested */ still */ let c = 2
            let d = #"raw \(Date()) "inner" text"# + """
                multi-line Date()
                """
            """#
        let views = SourceViews(text: source)
        let codeLines = views.codeLines
        let commentLines = views.commentLines
        XCTAssertEqual(source.components(separatedBy: "\n").count, codeLines.count)
        XCTAssertEqual(codeLines.count, commentLines.count)

        XCTAssertTrue(codeLines[0].hasPrefix("let a = 1"))
        XCTAssertFalse(codeLines[0].contains("Date"))
        XCTAssertTrue(commentLines[0].contains("// trailing Date()"))

        XCTAssertTrue(codeLines[1].contains("UUID()"), "interpolated code is code: \(codeLines[1])")
        XCTAssertFalse(codeLines[1].contains("Date"))
        XCTAssertFalse(codeLines[1].contains("quoted"))
        XCTAssertFalse(commentLines[1].contains("not a comment"), "a `//` inside a string opens no comment")

        XCTAssertTrue(codeLines[2].contains("let c = 2"))
        XCTAssertFalse(codeLines[2].contains("nested"))
        XCTAssertTrue(commentLines[2].contains("still"))

        XCTAssertFalse(codeLines[3].contains("Date"), "a raw string's `\\(` is text, not an interpolation: \(codeLines[3])")
        XCTAssertFalse(codeLines[3].contains("inner"))
        XCTAssertFalse(codeLines[4].contains("Date"))
    }
}
