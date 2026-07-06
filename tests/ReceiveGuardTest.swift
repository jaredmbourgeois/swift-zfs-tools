// ReceiveGuardTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import XCTest

@testable import ZFSToolsModel

// Pins the receive-guard allowlist to exactly the three remote commands `Syncer` emits, and proves
// everything else is rejected. If the sender's remote commands ever change, these break — which is
// the point: the guard and the sender stay in lockstep in one repo.
final class ReceiveGuardTest: XCTestCase {
    private let policy = ReceiveGuardPolicy(pool: "nas_12tb")

    // MARK: - tokenizer

    func testTokenizePlainWords() {
        XCTAssertEqual(
            ReceiveGuardPolicy.tokenize("zfs list -o name"), ["zfs", "list", "-o", "name"])
    }

    func testTokenizeSingleQuotedArgWithSlash() {
        XCTAssertEqual(
            ReceiveGuardPolicy.tokenize("zfs recv -F 'nas_12tb/nas'"),
            ["zfs", "recv", "-F", "nas_12tb/nas"])
    }

    func testTokenizeQuotedArgWithSpace() {
        // dataset names may contain spaces in ZFS; the sender single-quotes them
        XCTAssertEqual(
            ReceiveGuardPolicy.tokenize("zfs destroy 'nas_12tb/my data@x'"),
            ["zfs", "destroy", "nas_12tb/my data@x"])
    }

    func testTokenizeEmbeddedQuoteViaBackslashIdiom() {
        // String.shellQuoted renders  a'b  as  'a'\''b'  — must round-trip back to a'b
        XCTAssertEqual(ReceiveGuardPolicy.tokenize("'a'\\''b'"), ["a'b"])
    }

    func testTokenizeUnterminatedQuoteReturnsNil() {
        XCTAssertNil(ReceiveGuardPolicy.tokenize("zfs recv -F 'nas_12tb/nas"))
    }

    // MARK: - allowed shapes (exactly what Syncer emits)

    func testAllowsRecvIntoPoolChild() {
        XCTAssertEqual(
            try policy.validate("zfs recv -F 'nas_12tb/nas/documents@20260506-014625'").get(),
            ["zfs", "recv", "-F", "nas_12tb/nas/documents@20260506-014625"]
        )
    }

    func testAllowsRecvIntoPoolRoot() {
        XCTAssertEqual(
            try policy.validate("zfs recv -F 'nas_12tb'").get(), ["zfs", "recv", "-F", "nas_12tb"])
    }

    func testAllowsListSnapshotsExactShape() {
        XCTAssertEqual(
            try policy.validate("zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg").get(),
            ["zfs", "list", "-t", "snapshot", "-H", "-p", "-o", "guid,createtxg,name", "-s", "createtxg", "-r", "nas_12tb"]
        )
    }

    func testAllowsDestroySnapshotInPool() {
        XCTAssertEqual(
            try policy.validate("zfs destroy 'nas_12tb/nas@20260506-014625'").get(),
            ["zfs", "destroy", "nas_12tb/nas@20260506-014625"]
        )
    }

    // MARK: - rejections

    func testRejectsEmpty() {
        XCTAssertEqual(policy.validate(""), .failure(.emptyCommand))
    }

    func testRejectsInvalidPoolConfiguration() {
        let command = "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg"
        XCTAssertEqual(ReceiveGuardPolicy(pool: "").validate(command), .failure(.invalidPool("")))
        XCTAssertEqual(ReceiveGuardPolicy(pool: " ").validate(command), .failure(.invalidPool(" ")))
        XCTAssertEqual(ReceiveGuardPolicy(pool: "nas_12tb/nas").validate(command), .failure(.invalidPool("nas_12tb/nas")))
    }

    func testRejectsNonZfsBinary() {
        XCTAssertEqual(policy.validate("rm -rf /"), .failure(.notZfs("rm")))
    }

    func testRejectsDisallowedSubcommand() {
        XCTAssertEqual(
            policy.validate("zfs create nas_12tb/evil"), .failure(.disallowedSubcommand("create")))
    }

    func testRejectsRecvWithoutForceFlag() {
        XCTAssertEqual(
            policy.validate("zfs recv 'nas_12tb/nas'"),
            .failure(.wrongShape("zfs recv 'nas_12tb/nas'")))
    }

    func testRejectsRecvTargetInAnotherPool() {
        XCTAssertEqual(
            policy.validate("zfs recv -F 'rpool/secret'"),
            .failure(.targetOutsidePool("rpool/secret")))
    }

    func testRejectsPoolPrefixImpostor() {
        // "nas_12tb_evil" must NOT count as within pool "nas_12tb"
        XCTAssertEqual(
            policy.validate("zfs recv -F 'nas_12tb_evil/x'"),
            .failure(.targetOutsidePool("nas_12tb_evil/x"))
        )
    }

    func testRejectsDestroyOutsidePool() {
        XCTAssertEqual(
            policy.validate("zfs destroy 'rpool/x@s'"), .failure(.targetOutsidePool("rpool/x@s")))
    }

    func testRejectsDestroyPool() {
        XCTAssertEqual(
            policy.validate("zfs destroy 'nas_12tb'"), .failure(.destroyTargetIsNotSnapshot("nas_12tb")))
    }

    func testRejectsDestroyDataset() {
        XCTAssertEqual(
            policy.validate("zfs destroy 'nas_12tb/nas'"), .failure(.destroyTargetIsNotSnapshot("nas_12tb/nas")))
    }

    func testRejectsListWithExtraArgs() {
        // a broadened list (e.g. a different -o) is not what the sender emits → rejected
        let command = "zfs list -o name,used -H -t snapshot"
        XCTAssertEqual(policy.validate(command), .failure(.wrongShape(command)))
    }

    func testRejectsCallerSuppliedListScope() {
        let command = "zfs list -t snapshot -H -p -o guid,createtxg,name -s createtxg -r nas_12tb"
        XCTAssertEqual(policy.validate(command), .failure(.wrongShape(command)))
    }

    func testRejectsInjectionAttemptViaSecondCommand() {
        // no shell runs the approved argv, and a `;`-joined payload isn't the allowed shape anyway
        let command = "zfs list -o name -H -t snapshot ; rm -rf /"
        XCTAssertEqual(policy.validate(command), .failure(.wrongShape(command)))
    }
}
