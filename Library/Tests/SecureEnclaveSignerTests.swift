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
//  SecureEnclaveSignerTests.swift
//

import C2PA
import Foundation
import Security
import Testing

@Suite struct SecureEnclaveSignerTests {

    @Test func secureEnclaveSignerConfigCreation() {
        let defaults = SecureEnclaveSignerConfig(keyTag: "test.key.tag")
        #expect(defaults.keyTag == "test.key.tag")
        #expect(defaults.accessControl == [.privateKeyUsage])

        let custom = SecureEnclaveSignerConfig(keyTag: "another.key.tag", accessControl: [.privateKeyUsage, .biometryCurrentSet])
        #expect(custom.keyTag == "another.key.tag")
        #expect(custom.accessControl == [.privateKeyUsage, .biometryCurrentSet])
    }

    /// The Secure Enclave only holds P-256 keys, so the initializer refuses
    /// everything but ES256 before touching the hardware.
    @Test(arguments: [SigningAlgorithm.es384, .es512, .ps256, .ps384, .ps512, .ed25519])
    func nonES256RejectedBySecureEnclave(algorithm: SigningAlgorithm) throws {
        let certs = try Fixtures.certsPEM()
        let config = SecureEnclaveSignerConfig(keyTag: Fixtures.uniqueKeyTag("se.rejected"))
        let error = #expect(throws: C2PAError.self) {
            try Signer(algorithm: algorithm, certificateChainPEM: certs, tsa: nil, secureEnclaveConfig: config)
        }
        guard case .unsupportedAlgorithm(let rejected, let isSecureEnclave) = error else {
            Issue.record("expected .unsupportedAlgorithm, got \(String(describing: error))")
            return
        }
        #expect(rejected == algorithm)
        #expect(isSecureEnclave)
    }

    @Suite(.serialized, .requiresSecureEnclave) struct Hardware {

        @Test func deleteNonExistentKey() {
            #expect(Signer.deleteSecureEnclaveKey(keyTag: Fixtures.uniqueKeyTag("se.missing")))
        }

        @Test func deleteKeyIdempotent() throws {
            let config = SecureEnclaveSignerConfig(keyTag: Fixtures.uniqueKeyTag("se.delete"))
            try Signer.createSecureEnclaveKey(config: config)
            #expect(Signer.deleteSecureEnclaveKey(keyTag: config.keyTag), "first delete")
            #expect(Signer.deleteSecureEnclaveKey(keyTag: config.keyTag), "second delete")
            #expect(!TestKeychain.keyExists(tag: config.keyTag))
        }

        @Test func secureEnclaveAvailabilityCheck() throws {
            let config = SecureEnclaveSignerConfig(keyTag: Fixtures.uniqueKeyTag("se.availability"))
            defer { _ = Signer.deleteSecureEnclaveKey(keyTag: config.keyTag) }
            let key = try Signer.createSecureEnclaveKey(config: config)
            let attributes = try #require(SecKeyCopyAttributes(key) as? [String: Any])
            #expect(attributes[kSecAttrTokenID as String] as? String == kSecAttrTokenIDSecureEnclave as String)
            let publicKey = try #require(SecKeyCopyPublicKey(key))
            #expect((SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)?.count == 65, "an uncompressed P-256 point")
        }

        @Test(arguments: ["privateKeyUsage", "userPresence"])
        func createKeyAccessControlValidation(name: String) throws {
            let flags: SecAccessControlCreateFlags = name == "userPresence" ? [.privateKeyUsage, .userPresence] : [.privateKeyUsage]
            let config = SecureEnclaveSignerConfig(keyTag: Fixtures.uniqueKeyTag("se.ac.\(name)"), accessControl: flags)
            defer { _ = Signer.deleteSecureEnclaveKey(keyTag: config.keyTag) }
            try Signer.createSecureEnclaveKey(config: config)
            #expect(TestKeychain.keyExists(tag: config.keyTag))
        }

        /// A Secure Enclave key with a chain issued for it signs a Valid manifest.
        @Test func es256AcceptedBySecureEnclave() throws {
            let config = SecureEnclaveSignerConfig(keyTag: Fixtures.uniqueKeyTag("se.es256"))
            defer { _ = Signer.deleteSecureEnclaveKey(keyTag: config.keyTag) }
            let publicKey = try #require(SecKeyCopyPublicKey(Signer.createSecureEnclaveKey(config: config)))
            let chain = try CertificateManager.createSelfSignedCertificateChain(
                for: publicKey,
                config: CertificateManager.CertificateConfig(
                    commonName: "Secure Enclave Test Signer", organization: "Test Org", organizationalUnit: "Testing",
                    country: "US", state: "CA", locality: "SF"))

            let signer = try Signer(algorithm: .es256, certificateChainPEM: chain, tsa: nil, secureEnclaveConfig: config)
            #expect(try signer.reserveSize() > 0)
            let store = try Fixtures.signAndRead(Builder(manifestJSON: Fixtures.createdManifestJSON()), signer: signer)
            #expect(try store.signatureInfo()["common_name"] as? String == "Secure Enclave Test Signer")
            #expect(store.validationState == "Valid", "validation status: \(store.validationCodes)")
        }
    }
}
