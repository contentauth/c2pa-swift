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
//  SigningTests.swift
//

import C2PA
import class C2PA.Stream // swiftlint:disable:this duplicate_imports
import Foundation
import Security
import Testing

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

private final class CallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var sizes: [Int] = []

    func record(_ size: Int) {
        lock.lock()
        defer { lock.unlock() }
        sizes.append(size)
    }

    var recorded: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return sizes
    }
}

@Suite struct SigningTests {

    /// A manifest the CAWG x509 signer from the settings fixtures can reference:
    /// those settings name cawg.training-mining as the identity's referenced assertion.
    private func cawgManifestJSON() throws -> String {
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(Fixtures.createdManifestJSON().utf8)) as? [String: Any])
        var assertions = try #require(object["assertions"] as? [[String: Any]])
        assertions.append(["label": "cawg.training-mining", "data": ["entries": ["cawg.ai_inference": ["use": "notAllowed"]]]])
        object["assertions"] = assertions
        return try JSONSerialization.data(withJSONObject: object).utf8Text
    }

    private func signAndRead(_ signer: Signer, manifestJSON: String = Fixtures.createdManifestJSON()) throws -> ManifestStore {
        try Fixtures.signAndRead(Builder(manifestJSON: manifestJSON), signer: signer)
    }

    // MARK: - PEM signers

    @Test func signerCreation() throws {
        let signer = try Signer(certsPEM: Fixtures.certsPEM(), privateKeyPEM: Fixtures.privateKeyPEM(), algorithm: .es256, tsa: nil)
        #expect(try signer.reserveSize() > 0)
        #expect(try signAndRead(signer).signatureInfo()["issuer"] as? String == "C2PA Test Signing Cert")
    }

    /// The test key is P-256, so every other algorithm is incompatible, which
    /// the initializer documents as an error.
    @Test(arguments: [SigningAlgorithm.es384, .es512, .ps256, .ps384, .ps512, .ed25519])
    func mismatchedAlgorithmRejected(algorithm: SigningAlgorithm) throws {
        let certs = try Fixtures.certsPEM()
        let key = try Fixtures.privateKeyPEM()
        #expect(throws: C2PAError.self) {
            try Signer(certsPEM: certs, privateKeyPEM: key, algorithm: algorithm, tsa: nil)
        }
    }

    @Test(arguments: [
        "-----BEGIN CERTIFICATE-----",
        "-----BEGIN CERTIFICATE-----\nnotbase64!!!\n-----END CERTIFICATE-----",
        "-----BEGIN CERTIFICATE-----\nTUlJQ2\n-----END CERTIFICATE-----"
    ])
    func invalidCertificateChain(certsPEM: String) throws {
        let key = try Fixtures.privateKeyPEM()
        #expect(throws: C2PAError.self) {
            try Signer(certsPEM: certsPEM, privateKeyPEM: key, algorithm: .es256, tsa: nil)
        }
    }

    /// A chain with no PEM block at all. The doc promises an init-time error;
    /// today the signer is created and only signing fails.
    @Test(arguments: ["", "this is definitely not a certificate"])
    func invalidCertificateChainWithoutPEM(certsPEM: String) throws {
        let key = try Fixtures.privateKeyPEM()
        withKnownIssue("Signer accepts a certificate chain with no PEM blocks until signing") {
            #expect(throws: C2PAError.self) {
                try Signer(certsPEM: certsPEM, privateKeyPEM: key, algorithm: .es256, tsa: nil)
            }
        }
        let signer = try Signer(certsPEM: certsPEM, privateKeyPEM: key, algorithm: .es256, tsa: nil)
        let builder = try Builder(manifestJSON: Fixtures.createdManifestJSON())
        #expect(throws: C2PAError.self, "signing without a certificate") {
            try Fixtures.signAndRead(builder, signer: signer)
        }
    }

    @Test(arguments: [
        "",
        "this is definitely not a private key",
        "-----BEGIN PRIVATE KEY-----",
        "-----BEGIN RSA PRIVATE KEY-----\nTUlJQ2\n-----END RSA PRIVATE KEY-----"
    ])
    func invalidPrivateKey(privateKeyPEM: String) throws {
        let certs = try Fixtures.certsPEM()
        #expect(throws: C2PAError.self) {
            try Signer(certsPEM: certs, privateKeyPEM: privateKeyPEM, algorithm: .es256, tsa: nil)
        }
    }

    /// A timestamp authority countersigns the claim, which the read-back
    /// reports as the signature's time. Needs network access to DigiCert.
    @Test func signerWithTimestampAuthority() throws {
        let signer = try Signer(
            certsPEM: Fixtures.certsPEM(), privateKeyPEM: Fixtures.privateKeyPEM(), algorithm: .es256,
            tsa: URL(string: "http://timestamp.digicert.com"))
        #expect(try signAndRead(signer).signatureInfo()["time"] != nil)
    }

    // MARK: - Callback signers

    /// A callback signer that really signs with the test key produces a Valid
    /// manifest.
    @Test func signerWithCallback() throws {
        let key = try P256.Signing.PrivateKey(pemRepresentation: Fixtures.privateKeyPEM())
        let calls = CallRecorder()
        let signer = try Signer(algorithm: .es256, certificateChainPEM: Fixtures.certsPEM(), tsa: nil) { data in
            calls.record(data.count)
            return try key.signature(for: data).rawRepresentation
        }
        let store = try signAndRead(signer)
        #expect(calls.recorded.count == 1)
        #expect(calls.recorded.first.map { $0 > 0 } == true)
        #expect(store.validationState == "Valid")
        #expect(try store.signatureInfo()["issuer"] as? String == "C2PA Test Signing Cert")
    }

    // MARK: - Settings signers

    /// The CAWG settings fixtures configure a signer and a CAWG X.509 signer on
    /// top of it, so a context built from them signs and adds the identity
    /// assertion.
    @Test(arguments: ["toml", "json"])
    func settingsSignerSignsThroughContext(format: String) throws {
        let text = try Fixtures.text("test_settings_with_cawg_signing.\(format)")
        let settings = try format == "toml" ? C2PASettings(toml: text) : C2PASettings(json: text)
        let builder = try Builder(context: C2PAContext(settings: settings), manifestJSON: cawgManifestJSON())
        let labels = try Fixtures.signAndReadWithContextSigner(builder).assertionLabels()
        #expect(labels.contains("cawg.identity"), "labels: \(labels)")
    }

    // MARK: - Assets

    /// Signing over an asset that already has a manifest keeps it as the parent.
    @Test func doubleSigningImage() throws {
        let builder = try Builder(manifestJSON: Fixtures.editManifestJSON(claimGenerator: "double_sign_test/1.0"))
        try builder.setIntent(.edit)
        let store = try Fixtures.signAndRead(builder, source: Fixtures.adobeJPEG)
        #expect(store.manifestCount == 2)
        let parent = try #require(try store.ingredients().first)
        #expect(parent["relationship"] as? String == "parentOf")
        #expect(parent["active_manifest"] as? String == Fixtures.adobeActiveManifest)
    }

    @Test func zeroByteFile() throws {
        let source = Fixtures.tempURL(extension: "jpg")
        let destination = Fixtures.tempURL(extension: "jpg")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        try Data().write(to: source)
        let builder = try Builder(manifestJSON: Fixtures.createdManifestJSON())
        let signer = try Fixtures.signer()
        let error = try #require(throws: C2PAError.self) {
            try builder.sign(format: "image/jpeg", source: Stream(readFrom: source), destination: Stream(writeTo: destination), signer: signer)
        }
        guard case .api = error else {
            Issue.record("expected .api, got \(error)")
            return
        }
    }

    // MARK: - Algorithms

    @Test(arguments: SigningAlgorithm.allCases)
    func signingAlgorithms(algorithm: SigningAlgorithm) {
        #expect(!algorithm.rawValue.isEmpty)
        let expected: SecKeyAlgorithm? =
            switch algorithm {
            case .es256: .ecdsaSignatureMessageX962SHA256
            case .es384: .ecdsaSignatureMessageX962SHA384
            case .es512: .ecdsaSignatureMessageX962SHA512
            case .ps256: .rsaSignatureMessagePSSSHA256
            case .ps384: .rsaSignatureMessagePSSSHA384
            case .ps512: .rsaSignatureMessagePSSSHA512
            default: nil
            }
        #expect(algorithm.secKeyAlgo == expected)
    }
}
