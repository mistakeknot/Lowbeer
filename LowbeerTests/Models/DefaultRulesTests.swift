import XCTest
@testable import Lowbeer

final class DefaultRulesTests: XCTestCase {

    // MARK: - Rule Integrity

    func testAllDefaultsMarkedAsDefault() {
        for rule in DefaultRules.all {
            XCTAssertTrue(rule.isDefault, "\(rule.identity.displayName) should be marked isDefault")
        }
    }

    func testAllDefaultsEnabled() {
        for rule in DefaultRules.all {
            XCTAssertTrue(rule.enabled, "\(rule.identity.displayName) should be enabled")
        }
    }

    func testExpectedRuleCount() {
        // 6 terminals + 4 AI tools + 2 build tools + 2 local LLMs = 14
        XCTAssertEqual(DefaultRules.all.count, 14)
        XCTAssertEqual(DefaultRules.terminalRules.count, 6)
        XCTAssertEqual(DefaultRules.aiToolRules.count, 4)
        XCTAssertEqual(DefaultRules.buildToolRules.count, 2)
        XCTAssertEqual(DefaultRules.localLLMRules.count, 2)
    }

    func testEachRuleHasIdentity() {
        for rule in DefaultRules.all {
            let hasBundle = rule.identity.bundleIdentifier != nil && !rule.identity.bundleIdentifier!.isEmpty
            let hasPath = rule.identity.executablePath != nil && !rule.identity.executablePath!.isEmpty
            XCTAssertTrue(hasBundle || hasPath,
                "\(rule.identity.displayName) must have bundleIdentifier or executablePath")
        }
    }

    func testNoDuplicateIdentities() {
        let identities = DefaultRules.all.map { rule -> String in
            rule.identity.bundleIdentifier ?? rule.identity.executablePath ?? ""
        }
        let unique = Set(identities)
        XCTAssertEqual(identities.count, unique.count, "Duplicate identities found in defaults")
    }

    // MARK: - Category-Specific Rules

    func testTerminalRulesAreBackgroundOnly() {
        for rule in DefaultRules.terminalRules {
            XCTAssertTrue(rule.throttleInBackground,
                "\(rule.identity.displayName) terminal should be background-only")
        }
    }

    func testTerminalRulesUseDutyCycle() {
        for rule in DefaultRules.terminalRules {
            if case .throttleTo = rule.action {
                // OK
            } else {
                XCTFail("\(rule.identity.displayName) should use .throttleTo, not \(rule.action)")
            }
        }
    }

    func testLocalLLMRulesAreNotifyOnly() {
        for rule in DefaultRules.localLLMRules {
            XCTAssertEqual(rule.action, .notifyOnly,
                "\(rule.identity.displayName) LLM should be notifyOnly")
        }
    }

    func testBuildToolRulesUseDutyCycle() {
        for rule in DefaultRules.buildToolRules {
            if case .throttleTo = rule.action {
                // OK
            } else {
                XCTFail("\(rule.identity.displayName) should use .throttleTo, not \(rule.action)")
            }
        }
    }

    func testAIToolRulesAreBackgroundOnly() {
        for rule in DefaultRules.aiToolRules {
            XCTAssertTrue(rule.throttleInBackground,
                "\(rule.identity.displayName) AI tool should be background-only")
        }
    }

    // MARK: - Known Identities

    func testGhosttyIdentity() {
        let rule = DefaultRules.terminalRules.first { $0.identity.displayName == "Ghostty" }
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.identity.bundleIdentifier, "com.mitchellh.ghostty")
    }

    func testCursorIdentity() {
        let rule = DefaultRules.aiToolRules.first { $0.identity.displayName == "Cursor" }
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.identity.bundleIdentifier, "com.todesktop.cursor")
    }

    func testNodeIdentity() {
        let rule = DefaultRules.buildToolRules.first { $0.identity.displayName == "Node.js" }
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.identity.executablePath, "node")
    }

    func testOllamaIdentity() {
        let rule = DefaultRules.localLLMRules.first { $0.identity.displayName == "Ollama" }
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.identity.executablePath, "ollama")
    }
}
