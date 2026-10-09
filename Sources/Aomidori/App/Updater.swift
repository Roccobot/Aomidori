import AppKit
import AomidoriCore
import Sparkle

/// Automatic updates with Sparkle 2, from the appcast named by `SUFeedURL` in Info.plist.
///
/// Sparkle's standard behaviour is kept: on the second launch it asks once whether to check
/// automatically (`SUEnableAutomaticChecks` is deliberately absent, so the question is asked),
/// then checks once a day (`SUScheduledCheckInterval`). An update is accepted only if its ZIP
/// carries a valid EdDSA signature for `SUPublicEDKey`; Aomidori is signed ad hoc, so that
/// signature is what proves an update comes from Rocco (see Rules.md, "Releases and updates").
///
/// The updater stays off when `UpdatePolicy` says so: in the scripted smoke sessions (they must
/// not talk to the feed or write Sparkle's settings in Rocco's defaults) and in a build with no
/// feed or no valid public key, such as `swift run` outside the bundle.
@MainActor
final class Updater {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?

    /// Why the updater did not start, or `nil` once it runs. Reported by the launch smoke test.
    private(set) var reasonNotStarted: String? = "not started yet"

    private init() {}

    /// Called once, when launching is over.
    func start() {
        guard controller == nil else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        // Every scripted session (scripts/smoke*.sh) starts with one of these launch arguments.
        let smokeKeys = [LaunchSmokeTest.defaultsKey, ReaderSmokeTest.defaultsKey,
                         PlaygroundSmokeTest.defaultsKey, ReaderViewController.snapshotDefaultsKey]
        let smokeTestActive = smokeKeys.contains { UserDefaults.standard.string(forKey: $0) != nil }
        reasonNotStarted = UpdatePolicy.reasonNotToStart(
            feedURL: info["SUFeedURL"] as? String,
            publicEDKey: info["SUPublicEDKey"] as? String,
            smokeTestActive: smokeTestActive
        )
        guard reasonNotStarted == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// False while a check or an update is under way, and when the updater does not run.
    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// "Check for Updates…": Sparkle's own window shows the outcome, even "you're up to date".
    func checkForUpdates(_ sender: Any?) { controller?.checkForUpdates(sender) }
}
