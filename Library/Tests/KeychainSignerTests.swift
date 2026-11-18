// This file is licensed to you under the Apache License, Version 2.0
// (http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
// (http://opensource.org/licenses/MIT), at your option.
//
// Unless required by applicable law or agreed to in writing, this software is
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
// ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
// files for the specific language governing permissions and limitations under
// each license.
//
//  KeychainSignerTests.swift
//

import C2PA
import Foundation
import Security
import Testing

@Suite struct KeychainSignerTests {

    @Test func ed25519RejectedByKeychainSigner() throws {
        let certs = try Fixtures.certsPEM()
        let error = #expect(throws: C2PAError.self) {
            try Signer(algorithm: .ed25519, certificateChainPEM: certs, tsa: nil, keychainKeyTag: Fixtures.uniqueKeyTag("ed25519"))
        }
        guard case .ed25519NotSupported = error else {
            Issue.record("expected .ed25519NotSupported, got \(String(describing: error))")
            return
        }
    }

    /// The doc comment promises an init-time error for a missing key; today the
    /// lookup only happens when signing.
    @Test func nonExistentKeyFailure() throws {
        let tag = Fixtures.uniqueKeyTag("missing")
        let certs = try Fixtures.certsPEM()
        withKnownIssue("Keychain signer defers the key lookup to signing") {
            #expect(throws: C2PAError.self) {
                try Signer(algorithm: .es256, certificateChainPEM: certs, tsa: nil, keychainKeyTag: tag)
            }
        }
        let signer = try Signer(algorithm: .es256, certificateChainPEM: certs, tsa: nil, keychainKeyTag: tag)
        let builder = try Builder(manifestJSON: Fixtures.createdManifestJSON())
        #expect(throws: C2PAError.self, "signing with a missing key") {
            try Fixtures.signAndRead(builder, signer: signer)
        }
    }

    /// Suites that create persistent keys: serialized, and only where a
    /// permanent key can be created (always on a device).
    @Suite(.serialized, .requiresKeychain) struct WithKeychain {

        private let config = CertificateManager.CertificateConfig(
            commonName: "Keychain Test Signer",
            organization: "Keychain Test Org",
            organizationalUnit: "Testing",
            country: "US",
            state: "CA",
            locality: "SF")

        /// A keychain key with a self-signed chain for it; the caller deletes `tag`.
        private func keyWithChain(_ prefix: String) throws -> (tag: String, chain: String) {
            let tag = Fixtures.uniqueKeyTag(prefix)
            let key = try TestKeychain.createKey(tag: tag)
            let publicKey = try #require(SecKeyCopyPublicKey(key))
            return (tag, try CertificateManager.createSelfSignedCertificateChain(for: publicKey, config: config))
        }

        @Test func es256WithKeychainKey() throws {
            let (tag, chain) = try keyWithChain("es256")
            defer { TestKeychain.deleteKey(tag: tag) }
            let signer = try Signer(algorithm: .es256, certificateChainPEM: chain, tsa: nil, keychainKeyTag: tag)
            #expect(try signer.reserveSize() > 0)
            let signature = try Fixtures.signAndRead(Builder(manifestJSON: Fixtures.createdManifestJSON()), signer: signer).signatureInfo()
            #expect(signature["alg"] as? String == "Es256")
            #expect(signature["common_name"] as? String == config.commonName)
        }

        /// The whole flow: keychain key, self-signed chain, sign, read back Valid.
        @Test func keychainSigningWorkflow() throws {
            let (tag, chain) = try keyWithChain("workflow")
            defer { TestKeychain.deleteKey(tag: tag) }
            let signer = try Signer(algorithm: .es256, certificateChainPEM: chain, tsa: nil, keychainKeyTag: tag)
            let store = try Fixtures.signAndRead(
                Builder(manifestJSON: Fixtures.createdManifestJSON(claimGenerator: "keychain_test/1.0")), signer: signer)
            #expect(try store.assertionLabels().contains("c2pa.test"))
            #expect(store.validationState == "Valid", "validation status: \(store.validationCodes)")
        }

        /// A P-256 key cannot serve these algorithms. The doc comment promises an
        /// init-time error; today the key is only checked when signing, and the
        /// ES384/ES512 digests even pass that check, so signing must at least
        /// fail its own verification.
        @Test(arguments: [SigningAlgorithm.es384, .es512, .ps256, .ps384, .ps512])
        func algorithmMismatchDetection(algorithm: SigningAlgorithm) throws {
            let (tag, chain) = try keyWithChain("mismatch")
            defer { TestKeychain.deleteKey(tag: tag) }
            withKnownIssue("Keychain signer defers the algorithm check to signing") {
                #expect(throws: C2PAError.self) {
                    try Signer(algorithm: algorithm, certificateChainPEM: chain, tsa: nil, keychainKeyTag: tag)
                }
            }
            let signer = try Signer(algorithm: algorithm, certificateChainPEM: chain, tsa: nil, keychainKeyTag: tag)
            let settings = try C2PASettings(json: #"{"version": 1, "verify": {"verify_after_sign": true}}"#)
            let builder = try Builder(context: C2PAContext(settings: settings), manifestJSON: Fixtures.createdManifestJSON())
            #expect(throws: C2PAError.self, "a \(algorithm) signature from a P-256 key was accepted") {
                try Fixtures.signAndRead(builder, signer: signer)
            }
        }

        /// A key created under a unique tag is gone once its test's defer runs.
        @Test func keyTagsAreUnique() throws {
            let first = Fixtures.uniqueKeyTag("k")
            let second = Fixtures.uniqueKeyTag("k")
            #expect(first != second)
            do {
                defer { TestKeychain.deleteKey(tag: first) }
                try TestKeychain.createKey(tag: first)
                #expect(TestKeychain.keyExists(tag: first))
                #expect(!TestKeychain.keyExists(tag: second))
            }
            #expect(!TestKeychain.keyExists(tag: first))
        }
    }
}
