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
//  CertificateManagerTests.swift
//

import C2PA
import Foundation
import Security
import Testing

@Suite struct CertificateManagerTests {

    private static func config(_ commonName: String) -> CertificateManager.CertificateConfig {
        CertificateManager.CertificateConfig(
            commonName: commonName,
            organization: "Test Organization",
            organizationalUnit: "Certificate Tests",
            country: "US",
            state: "California",
            locality: "San Francisco",
            emailAddress: "test@example.com",
            validityDays: 365)
    }

    private static func ephemeralPublicKey() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false
        ]
        var error: Unmanaged<CFError>?
        let key = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
        return try #require(SecKeyCopyPublicKey(key))
    }

    /// Three certificates (leaf, intermediate, root), each parseable, the leaf
    /// naming the configured subject.
    private static func expectChain(_ chain: String, leafCommonName: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let certificates = PEM.certificates(in: chain)
        #expect(PEM.blocks("CERTIFICATE", in: chain).count == 3, sourceLocation: sourceLocation)
        #expect(certificates.count == 3, "every certificate in the chain parses", sourceLocation: sourceLocation)
        #expect(
            certificates.first.flatMap { SecCertificateCopySubjectSummary($0) as String? } == leafCommonName,
            sourceLocation: sourceLocation)
    }

    /// One DER CertificationRequest whose subject carries the common name.
    private static func expectCSR(_ csr: String, commonName: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let blocks = PEM.blocks("CERTIFICATE REQUEST", in: csr)
        #expect(blocks.count == 1, sourceLocation: sourceLocation)
        #expect(blocks.first?.first == 0x30, "a DER SEQUENCE", sourceLocation: sourceLocation)
        #expect(blocks.first?.range(of: Data(commonName.utf8)) != nil, "the subject names \(commonName)", sourceLocation: sourceLocation)
    }

    // MARK: - No keychain needed

    @Test func selfSignedChainDirectCall() throws {
        let chain = try CertificateManager.createSelfSignedCertificateChain(
            for: Self.ephemeralPublicKey(), config: Self.config("Direct Chain Test"))
        Self.expectChain(chain, leafCommonName: "Direct Chain Test")
    }

    /// A CSR is signed with the private key, which must be in the keychain.
    @Test func csrCreationRejectsEphemeralKeys() throws {
        let publicKey = try Self.ephemeralPublicKey()
        let error = #expect(throws: CertificateManager.CertificateError.self) {
            try CertificateManager.createCSR(for: publicKey, config: Self.config("CSR Direct Test"))
        }
        guard case .invalidKeyData = error else {
            Issue.record("expected .invalidKeyData, got \(String(describing: error))")
            return
        }
    }

    @Test func csrCreationWithInvalidKeyTag() {
        let error = #expect(throws: CertificateManager.CertificateError.self) {
            try CertificateManager.createCSR(keyTag: Fixtures.uniqueKeyTag("missing"), config: Self.config("Invalid Key Test"))
        }
        guard case .invalidKeyData = error else {
            Issue.record("expected .invalidKeyData, got \(String(describing: error))")
            return
        }
    }

    // MARK: - Keychain

    @Suite(.serialized, .requiresKeychain) struct WithKeychain {

        @Test func selfSignedCertificateChainCreation() throws {
            let tag = Fixtures.uniqueKeyTag("selfcert")
            defer { TestKeychain.deleteKey(tag: tag) }
            let publicKey = try #require(SecKeyCopyPublicKey(TestKeychain.createKey(tag: tag)))
            let chain = try CertificateManager.createSelfSignedCertificateChain(for: publicKey, config: config("Test Signer"))
            expectChain(chain, leafCommonName: "Test Signer")
            let signer = try Signer(algorithm: .es256, certificateChainPEM: chain, tsa: nil, keychainKeyTag: tag)
            #expect(try signer.reserveSize() > 0)
        }

        @Test func selfSignedChainWithPersistentKey() throws {
            let tag = Fixtures.uniqueKeyTag("chain")
            defer { TestKeychain.deleteKey(tag: tag) }
            let publicKey = try #require(SecKeyCopyPublicKey(TestKeychain.createKey(tag: tag)))
            let chain = try CertificateManager.createSelfSignedCertificateChain(for: publicKey, config: config("Persistent Chain Test"))
            expectChain(chain, leafCommonName: "Persistent Chain Test")
            let signer = try Signer(algorithm: .es256, certificateChainPEM: chain, tsa: nil, keychainKeyTag: tag)
            let store = try Fixtures.signAndRead(Builder(manifestJSON: Fixtures.createdManifestJSON()), signer: signer)
            #expect(try store.signatureInfo()["common_name"] as? String == "Persistent Chain Test")
        }

        @Test func csrCreationWithPublicKey() throws {
            let tag = Fixtures.uniqueKeyTag("csr")
            defer { TestKeychain.deleteKey(tag: tag) }
            let publicKey = try #require(SecKeyCopyPublicKey(TestKeychain.createKey(tag: tag)))
            expectCSR(try CertificateManager.createCSR(for: publicKey, config: config("CSR Test Subject")), commonName: "CSR Test Subject")
        }

        @Test func csrCreationWithKeyTag() throws {
            let tag = Fixtures.uniqueKeyTag("csrkeytag")
            defer { TestKeychain.deleteKey(tag: tag) }
            try TestKeychain.createKey(tag: tag)
            expectCSR(try CertificateManager.createCSR(keyTag: tag, config: config("KeyTag CSR Test")), commonName: "KeyTag CSR Test")
        }

        @Test func persistentKeychainKey() throws {
            let tag = Fixtures.uniqueKeyTag("persistent")
            defer { TestKeychain.deleteKey(tag: tag) }
            try TestKeychain.createKey(tag: tag)
            #expect(TestKeychain.keyExists(tag: tag), "the key is retrievable by its tag")
            expectCSR(try CertificateManager.createCSR(keyTag: tag, config: config("Persistent Key Test")), commonName: "Persistent Key Test")
        }
    }
}
