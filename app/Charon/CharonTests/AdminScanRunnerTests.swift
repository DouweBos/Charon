// AdminScanRunnerTests.swift
// CharonTests

import Testing
@testable import Charon

struct AdminScanRunnerTests {
    @Test func quotingSurvivesHostilePaths() {
        #expect(AdminScanRunner.shellQuoted("/Users/me/it's here") == "'/Users/me/it'\\''s here'")
        #expect(AdminScanRunner.appleScriptEscaped("a \"b\" \\c") == "a \\\"b\\\" \\\\c")
    }
}
