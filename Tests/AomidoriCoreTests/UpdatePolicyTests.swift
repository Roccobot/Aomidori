import Foundation
import Testing
@testable import AomidoriCore

@Suite("Updates")
struct UpdatePolicyTests {
    private let key = Data(repeating: 7, count: 32).base64EncodedString()

    @Test func startsWithAnHTTPSFeedAndAKey() {
        #expect(UpdatePolicy.reasonNotToStart(feedURL: UpdatePolicy.feedURL, publicEDKey: key, smokeTestActive: false) == nil)
    }

    @Test func staysOffInSmokeTestsAndWithoutFeedOrKey() {
        #expect(UpdatePolicy.reasonNotToStart(feedURL: UpdatePolicy.feedURL, publicEDKey: key, smokeTestActive: true) == "smoke test")
        #expect(UpdatePolicy.reasonNotToStart(feedURL: nil, publicEDKey: key, smokeTestActive: false) != nil)
        #expect(UpdatePolicy.reasonNotToStart(feedURL: "http://roccobot.github.io/Aomidori/appcast.xml", publicEDKey: key, smokeTestActive: false) != nil)
        #expect(UpdatePolicy.reasonNotToStart(feedURL: UpdatePolicy.feedURL, publicEDKey: nil, smokeTestActive: false) != nil)
        #expect(UpdatePolicy.reasonNotToStart(feedURL: UpdatePolicy.feedURL, publicEDKey: "REPLACE_WITH_GENERATE_KEYS_OUTPUT", smokeTestActive: false) != nil)
    }

    @Test func publicKeysAre32BytesOfBase64() {
        #expect(UpdatePolicy.isEd25519PublicKey(key))
        #expect(!UpdatePolicy.isEd25519PublicKey(Data(repeating: 7, count: 31).base64EncodedString()))
        #expect(!UpdatePolicy.isEd25519PublicKey("not base64"))
    }

    /// Info.plist and the appcast agree with the code on where updates come from.
    @Test func infoPlistAndAppcastNameTheSameFeed() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["SUFeedURL"] as? String == UpdatePolicy.feedURL)
        #expect(plist["SUPublicEDKey"] is String)
        #expect(plist["SUEnableAutomaticChecks"] == nil, "set, it would skip Sparkle's permission prompt")
        #expect(plist["SUScheduledCheckInterval"] as? Int == 86_400)
        let appcast = try String(contentsOf: root.appendingPathComponent("publish/appcast.xml"), encoding: .utf8)
        #expect(appcast.contains("<link>https://roccobot.github.io/Aomidori/</link>"))
    }
}
