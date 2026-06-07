// BuildPlatformTest.swift is part of the swift-zfs-tools open source project.
//
// Copyright © 2025 Jared Bourgeois
//
// Licensed under Apache License v2.0 with Runtime Library Exception
//

import XCTest

@testable import ZFSToolsModel

// Pins the uname → bin/<platform>/ directory mapping that lets the builder derive the target
// architecture at the build site rather than requiring it to be passed in.
final class BuildPlatformTest: XCTestCase {
    func testMacOSArm64() {
        XCTAssertEqual("macos-arm64", BuildPlatform.directoryName(unameS: "Darwin", unameM: "arm64"))
    }

    func testMacOSIntel() {
        XCTAssertEqual("macos-x86_64", BuildPlatform.directoryName(unameS: "Darwin", unameM: "x86_64"))
    }

    func testLinuxIntel() {
        XCTAssertEqual("linux-x86_64", BuildPlatform.directoryName(unameS: "Linux", unameM: "x86_64"))
    }

    func testLinuxArmNormalizesToAarch64() {
        XCTAssertEqual("linux-aarch64", BuildPlatform.directoryName(unameS: "Linux", unameM: "aarch64"))
        XCTAssertEqual("linux-aarch64", BuildPlatform.directoryName(unameS: "Linux", unameM: "arm64"))
    }

    func testLinuxAmd64NormalizesToX86_64() {
        XCTAssertEqual("linux-x86_64", BuildPlatform.directoryName(unameS: "Linux", unameM: "amd64"))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual("macos-arm64", BuildPlatform.directoryName(unameS: "Darwin\n", unameM: " arm64 "))
    }

    func testUnknownOSIsNil() {
        XCTAssertNil(BuildPlatform.directoryName(unameS: "MINGW64_NT", unameM: "x86_64"))
    }

    func testUnknownArchIsNil() {
        XCTAssertNil(BuildPlatform.directoryName(unameS: "Linux", unameM: "riscv64"))
    }
}
