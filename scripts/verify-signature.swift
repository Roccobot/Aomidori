// Verifies a Sparkle EdDSA signature against the public key the app trusts.
//
//   swift scripts/verify-signature.swift <SUPublicEDKey> <edSignature> <file>
//
// Sparkle signs the archive's bytes with Ed25519; an installed copy accepts an update only if
// the signature verifies with its SUPublicEDKey. scripts/release.sh runs this after signing,
// whatever key signed (Keychain or ED_KEY_FILE), so a wrong key never reaches the appcast.
// Exits 0 if the signature is valid, 1 if not, 2 on bad input.
// Author: Rocco Casadei, a.k.a. Roccobot
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4,
      let publicKeyData = Data(base64Encoded: arguments[1]),
      let signature = Data(base64Encoded: arguments[2]),
      let file = FileManager.default.contents(atPath: arguments[3]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
    FileHandle.standardError.write(Data("usage: verify-signature.swift <SUPublicEDKey> <edSignature> <file>\n".utf8))
    exit(2)
}
exit(publicKey.isValidSignature(signature, for: file) ? 0 : 1)
