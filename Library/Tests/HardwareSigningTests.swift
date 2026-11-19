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
//  HardwareSigningTests.swift
//

import C2PA
import Foundation
import Security
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite(.serialized) struct HardwareSigningTests {

    private let message = Data("Test data for hardware signing".utf8)

    private func signAndVerify(_ privateKey: SecKey) throws {
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
        var error: Unmanaged<CFError>?
        let signature = try #require(
            SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, message as CFData, &error) as Data?,
            "signing failed: \(String(describing: error?.takeRetainedValue()))")
        #expect(SecKeyVerifySignature(publicKey, .ecdsaSignatureMessageX962SHA256, message as CFData, signature as CFData, nil))
    }

    @Test(.requiresKeychain) func keychainSignerCreation() throws {
        let tag = Fixtures.uniqueKeyTag("hw.keychain")
        defer { TestKeychain.deleteKey(tag: tag) }
        let key = try TestKeychain.createKey(tag: tag)
        try signAndVerify(key)

        let publicKey = try #require(SecKeyCopyPublicKey(key))
        let chain = try CertificateManager.createSelfSignedCertificateChain(
            for: publicKey,
            config: CertificateManager.CertificateConfig(
                commonName: "C2PA Keychain Test Signer", organization: "C2PA Test Organization",
                organizationalUnit: "Keychain Testing Unit", country: "US", state: "California", locality: "San Francisco",
                emailAddress: "keychain-test@example.com", validityDays: 365))
        let signer = try Signer(algorithm: .es256, certificateChainPEM: chain, tsa: nil, keychainKeyTag: tag)
        #expect(try signer.reserveSize() > 0)
    }

    @Test(.requiresSecureEnclave) func secureEnclaveSignerCreation() throws {
        let config = SecureEnclaveSignerConfig(keyTag: Fixtures.uniqueKeyTag("hw.se"), accessControl: [.privateKeyUsage])
        defer { _ = Signer.deleteSecureEnclaveKey(keyTag: config.keyTag) }
        let key = try Signer.createSecureEnclaveKey(config: config)
        let attributes = try #require(SecKeyCopyAttributes(key) as? [String: Any])
        #expect(attributes[kSecAttrTokenID as String] as? String == kSecAttrTokenIDSecureEnclave as String)
        try signAndVerify(key)

        // A chain that is not for this key: the Secure Enclave signs, but the
        // claim cannot verify against the certificate, so signing must fail.
        let signer = try Signer(algorithm: .es256, certificateChainPEM: Fixtures.certsPEM(), tsa: nil, secureEnclaveConfig: config)
        let settings = try C2PASettings(json: #"{"version": 1, "verify": {"verify_after_sign": true}}"#)
        let builder = try Builder(context: C2PAContext(settings: settings), manifestJSON: Fixtures.createdManifestJSON())
        #expect(throws: C2PAError.self, "a signature that does not match the certificate was accepted") {
            try Fixtures.signAndRead(builder, signer: signer)
        }
    }

    /// Enrolment end to end on a device: a Secure Enclave key, a CSR for it,
    /// a chain issued by the signing server, and a Valid manifest signed with
    /// that chain.
    @Test(.requiresSecureEnclave, .requiresSigningServer) func secureEnclaveCSRSigning() async throws {
        try await TestEnvironment.requireSigningServer()
        let config = SecureEnclaveSignerConfig(keyTag: Fixtures.uniqueKeyTag("hw.csr"), accessControl: [.privateKeyUsage])
        defer { _ = Signer.deleteSecureEnclaveKey(keyTag: config.keyTag) }
        let publicKey = try #require(SecKeyCopyPublicKey(Signer.createSecureEnclaveKey(config: config)))
        let csr = try CertificateManager.createCSR(
            for: publicKey,
            config: CertificateManager.CertificateConfig(
                commonName: "C2PA Test Signer", organization: "Test Organization", organizationalUnit: "iOS Testing",
                country: "US", state: "California", locality: "San Francisco", emailAddress: "test@example.com"))

        var request = URLRequest(url: TestEnvironment.signingServerURL.appendingPathComponent("api/v1/certificates/sign"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(TestEnvironment.signingServerToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "csr": csr,
            "metadata": ["device_id": "test-device", "app_version": "1.0.0"]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode
        try #require(status == 200, "CSR submission returned \(String(describing: status)): \(data.utf8Text)")

        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let chain = try #require(body["certificate_chain"] as? String, "response keys: \(body.keys.sorted())")
        #expect(PEM.certificates(in: chain).count >= 2, "the issued chain parses")

        let signer = try Signer(algorithm: .es256, certificateChainPEM: chain, tsa: nil, secureEnclaveConfig: config)
        let store = try Fixtures.signAndRead(Builder(manifestJSON: Fixtures.createdManifestJSON()), signer: signer)
        #expect(try store.signatureInfo()["common_name"] as? String == "C2PA Test Signer")
        #expect(store.validationState == "Valid", "validation status: \(store.validationCodes)")
    }
}
