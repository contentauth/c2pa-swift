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
//  SignerExtendedTests.swift
//

import C2PA
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

@Suite struct SignerExtendedTests {

    private func plainSigner(tsa: URL? = nil) throws -> Signer {
        try Signer(certsPEM: Fixtures.certsPEM(), privateKeyPEM: Fixtures.privateKeyPEM(), algorithm: .es256, tsa: tsa)
    }

    // MARK: - Reserve size

    @Test func reserveSizeES256() throws {
        #expect(try plainSigner().reserveSize() > 0)
    }

    /// The doc only ties the size to the algorithm; a TSA must not shrink it.
    @Test func reserveSizeWithTSA() throws {
        let without = try plainSigner().reserveSize()
        let with = try plainSigner(tsa: URL(string: "http://timestamp.digicert.com")).reserveSize()
        #expect(with > 0)
        #expect(with >= without, "with TSA \(with), without \(without)")
    }

    @Test func reserveSizeWithCallback() throws {
        let signer = try Signer(algorithm: .es256, certificateChainPEM: Fixtures.certsPEM(), tsa: nil) { _ in Data(count: 64) }
        #expect(try signer.reserveSize() > 0)
    }

    // MARK: - SignerInfo

    @Test func signerFromSignerInfo() throws {
        let signer = try Signer(info: Fixtures.signerInfo())
        let store = try Fixtures.signAndRead(Builder(manifestJSON: Fixtures.createdManifestJSON()), signer: signer)
        #expect(try store.signatureInfo()["alg"] as? String == "Es256")
    }

    /// Needs network access to DigiCert.
    @Test func signerFromSignerInfoWithTSA() throws {
        let base = try Fixtures.signerInfo()
        let info = SignerInfo(
            algorithm: base.algorithm, certificatePEM: base.certificatePEM, privateKeyPEM: base.privateKeyPEM,
            tsa: URL(string: "http://timestamp.digicert.com"))
        let store = try Fixtures.signAndRead(Builder(manifestJSON: Fixtures.createdManifestJSON()), signer: Signer(info: info))
        #expect(try store.signatureInfo()["time"] != nil)
    }

    // MARK: - Callbacks

    /// A callback returning garbage must not yield a manifest: with
    /// verify-after-sign on, signing fails after the callback has run.
    @Test func signerCallbackInvocation() throws {
        let calls = CallRecorder()
        let signer = try Signer(algorithm: .es256, certificateChainPEM: Fixtures.certsPEM(), tsa: nil) { data in
            calls.record(data.count)
            return Data(repeating: 0x30, count: 64)
        }
        let settings = try C2PASettings(json: #"{"version": 1, "verify": {"verify_after_sign": true}}"#)
        let builder = try Builder(context: C2PAContext(settings: settings), manifestJSON: Fixtures.createdManifestJSON())
        #expect(throws: C2PAError.self) {
            try Fixtures.signAndRead(builder, signer: signer)
        }
        #expect(calls.recorded.count == 1)
        #expect(calls.recorded.first.map { $0 > 0 } == true, "the callback received no bytes to sign")
    }

    @Test func signerCallbackErrorPropagation() throws {
        let calls = CallRecorder()
        let signer = try Signer(algorithm: .es256, certificateChainPEM: Fixtures.certsPEM(), tsa: nil) { data in
            calls.record(data.count)
            throw C2PAError.api("Callback intentionally failed")
        }
        let builder = try Builder(manifestJSON: Fixtures.createdManifestJSON())
        #expect(throws: C2PAError.self) {
            try Fixtures.signAndRead(builder, signer: signer)
        }
        #expect(calls.recorded.count == 1, "the error must come from the callback, not from setup")
    }

    /// The C API rejects strings over 1 MiB, so creation fails after the
    /// callback has been retained for the signer; the failure must release it.
    @Test func failedSignerCreationReleasesCallback() {
        final class Captured: Sendable {}

        weak var weakCaptured: Captured?
        do {
            let captured = Captured()
            weakCaptured = captured
            let oversizedChain = String(repeating: "A", count: 1_048_577)
            #expect(throws: C2PAError.self, "created a signer over an oversized certificate chain") {
                try Signer(algorithm: .es256, certificateChainPEM: oversizedChain) { data in
                    withExtendedLifetime(captured) { data }
                }
            }
        }
        #expect(weakCaptured == nil, "the callback was retained after signer creation failed")
    }

    // MARK: - Keychain public keys

    @Test(.requiresKeychain) func exportPublicKeyPEM() throws {
        let tag = Fixtures.uniqueKeyTag("exportpubkey")
        defer { TestKeychain.deleteKey(tag: tag) }
        let key = try TestKeychain.createKey(tag: tag)

        let pem = try Signer.exportPublicKeyPEM(fromKeychainTag: tag)
        #expect(pem.hasPrefix("-----BEGIN PUBLIC KEY-----"))
        #expect(pem.hasSuffix("-----END PUBLIC KEY-----"))

        let expected = try #require(SecKeyCopyPublicKey(key).flatMap { SecKeyCopyExternalRepresentation($0, nil) as Data? })
        withKnownIssue("exportPublicKeyPEM labels a raw EC point as PUBLIC KEY instead of an SPKI") {
            let parsed = try P256.Signing.PublicKey(pemRepresentation: pem)
            #expect(parsed.x963Representation == expected)
        }
    }

    @Test func exportPublicKeyPEMNonExistentKey() {
        let tag = Fixtures.uniqueKeyTag("missing")
        let error = #expect(throws: C2PAError.self) { try Signer.exportPublicKeyPEM(fromKeychainTag: tag) }
        guard case .keySearchFailed(let searched, _, _) = error else {
            Issue.record("expected .keySearchFailed, got \(String(describing: error))")
            return
        }
        #expect(searched == tag)
    }

    // MARK: - CAWG identity

    @Test func cawgIdentitySigner() throws {
        let combined = try Signer.withCawgIdentity(
            Fixtures.signer(), identity: Fixtures.signer(), referencedAssertions: ["c2pa.actions"])
        let store = try Fixtures.signAndRead(Builder(manifestJSON: Fixtures.createdManifestJSON()), signer: combined)
        #expect(try store.assertionLabels().contains("cawg.identity"))
    }

    /// The combined signer reserves at least what its claim signer does.
    @Test func cawgIdentitySignerReserveSize() throws {
        let plain = try plainSigner().reserveSize()
        let combined = try Signer.withCawgIdentity(Fixtures.signer(), identity: Fixtures.signer())
        #expect(try combined.reserveSize() >= plain)
    }

    /// Both inputs are consumed by the combine; reusing either through an
    /// alias must throw rather than dereference a pointer the combined signer owns.
    @Test func consumedSignerIsGuarded() throws {
        let claim = try Fixtures.signer()
        let identity = try Fixtures.signer()
        let claimAlias = SignerAlias(claim)
        let identityAlias = SignerAlias(identity)
        _ = try Signer.withCawgIdentity(claim, identity: identity)

        #expect(throws: C2PAError.self, "reserveSize on a consumed signer") {
            try claimAlias.signer.reserveSize()
        }
        #expect(throws: C2PAError.self, "re-combining consumed signers") {
            try Signer.withCawgIdentity(claimAlias.signer, identity: identityAlias.signer)
        }
    }

    @Test func cawgSameInstanceRejected() throws {
        let alias = SignerAlias(try Fixtures.signer())
        let error = #expect(throws: C2PAError.self) {
            try Signer.withCawgIdentity(alias.signer, identity: alias.signer)
        }
        #expect(error?.localizedDescription.contains("distinct") == true, "error: \(String(describing: error))")
        #expect(try alias.signer.reserveSize() > 0, "the signer stays usable after a rejected combine")
    }
}
