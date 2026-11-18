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
//  Fixtures.swift
//

import C2PA
import class C2PA.Stream // swiftlint:disable:this duplicate_imports
import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// A fixture that is not in the test bundle, usually because a resource was not copied.
enum FixtureError: Error, Equatable {
    case missing(String)
}

/// Files and credentials shared by the suites. Everything resolves inside the
/// C2PATests bundle, where Library/Tests/Resources is copied.
enum Fixtures {
    /// Carries a C2PA manifest (see adobeActiveManifest).
    static let adobeJPEG = "adobe-20220124-CI.jpg"
    /// Carries no manifest.
    static let pexelsJPEG = "pexels-asadphoto-457882.jpg"
    /// Carries two manifests; the active one is titled "My Title".
    static let videoMP4 = "video1.mp4"

    static let adobeActiveManifest = "contentauth:urn:uuid:f37fff21-e50f-4777-9978-835f9fa18bac"
    static let adobeThumbnailURI =
        "self#jumbf=/c2pa/contentauth:urn:uuid:f37fff21-e50f-4777-9978-835f9fa18bac/c2pa.assertions/c2pa.thumbnail.claim.jpeg"

    static func url(_ name: String) throws(FixtureError) -> URL {
        let file = name as NSString
        guard let url = Bundle(for: BundleToken.self).url(
            forResource: file.deletingPathExtension, withExtension: file.pathExtension)
        else { throw .missing(name) }
        return url
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    static func text(_ name: String) throws -> String {
        try String(contentsOf: url(name), encoding: .utf8)
    }

    static func stream(_ name: String) throws -> Stream {
        try Stream(readFrom: url(name))
    }

    static func certsPEM() throws -> String { try text("es256_certs.pem") }

    static func privateKeyPEM() throws -> String { try text("es256_private.key") }

    /// An ES256 signer over the test certificate chain.
    static func signer() throws -> Signer {
        try Signer(info: signerInfo())
    }

    static func signerInfo() throws -> SignerInfo {
        SignerInfo(algorithm: .es256, certificatePEM: try certsPEM(), privateKeyPEM: try privateKeyPEM())
    }

    /// A callback signer that really signs with the test key, so what it signs
    /// validates. `onSign` receives the size of each payload before it is signed.
    static func callbackSigner(onSign: @escaping @Sendable (Int) -> Void = { _ in }) throws -> Signer {
        let key = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM())
        return try Signer(algorithm: .es256, certificateChainPEM: certsPEM()) { data in
            onSign(data.count)
            return try key.signature(for: data).rawRepresentation
        }
    }

    /// A settings section configuring a local ES256 signer over the test
    /// certificate chain. It serves as `signer` and as `cawg_x509_signer`.
    static func localSignerSection() throws -> [String: Any] {
        ["local": ["alg": "es256", "sign_cert": try certsPEM(), "private_key": try privateKeyPEM()]]
    }

    /// Settings whose signer is the test certificate, for signing with the
    /// signer on a context. `extra` adds further top-level sections.
    static func localSignerSettings(adding extra: [String: Any] = [:]) throws -> C2PASettings {
        var settings: [String: Any] = ["version": 1, "signer": try localSignerSection()]
        settings.merge(extra) { _, new in new }
        return try C2PASettings(json: JSONSerialization.data(withJSONObject: settings).utf8Text)
    }

    static let invalidCertsPEM = """
        -----BEGIN CERTIFICATE-----
        MIIBkTCB+wIJAKHO
        -----END CERTIFICATE-----
        """

    static let invalidPrivateKeyPEM = """
        -----BEGIN PRIVATE KEY-----
        MIGHAgEAMBMGByqG
        -----END PRIVATE KEY-----
        """

    /// A 1x1 PNG.
    static func tinyPNG() -> Data {
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(contentsOf: [0x00, 0x00, 0x00, 0x0D])
        png.append(Data("IHDR".utf8))
        png.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
        png.append(contentsOf: [0x08, 0x02, 0x00, 0x00, 0x00])
        png.append(contentsOf: [0x90, 0x77, 0x53, 0xDE])
        png.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])
        png.append(Data("IDAT".utf8))
        png.append(contentsOf: [0x08, 0x1D, 0x01, 0x01, 0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x02])
        png.append(contentsOf: [0x00, 0x01, 0xE2, 0x21])
        png.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        png.append(Data("IEND".utf8))
        png.append(contentsOf: [0xAE, 0x42, 0x60, 0x82])
        return png
    }

    /// A manifest for signing a new asset. The first action must be c2pa.created
    /// or c2pa.opened: c2pa-rs verifies what it just signed and rejects a manifest
    /// whose actions start any other way. c2pa.created also needs a digitalSourceType.
    static func createdManifestJSON(claimGenerator: String = "test_app/1.0") -> String {
        """
        {
            "claim_generator": "\(claimGenerator)",
            "assertions": [
                {
                    "label": "c2pa.actions",
                    "data": {
                        "actions": [
                            {
                                "action": "c2pa.created",
                                "digitalSourceType": "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"
                            }
                        ]
                    }
                },
                {"label": "c2pa.test", "data": {"test": true}}
            ]
        }
        """
    }

    /// A manifest for signing over an existing asset. It carries no inception
    /// action, so Builder.setIntent(.edit) can add the parent ingredient and the
    /// c2pa.opened action for it.
    static func editManifestJSON(claimGenerator: String = "test_app/1.0") -> String {
        """
        {
            "claim_generator": "\(claimGenerator)",
            "assertions": [
                {"label": "c2pa.test", "data": {"test": true}}
            ]
        }
        """
    }

    /// Signs a fixture with `builder` and reads the signed copy back.
    static func signAndRead(
        _ builder: Builder,
        source: String = pexelsJPEG,
        format: String = "image/jpeg",
        signer: Signer? = nil
    ) throws -> ManifestStore {
        let signer = try signer ?? self.signer()
        return try signAndRead(source: source, format: format) { source, destination in
            try builder.sign(format: format, source: source, destination: destination, signer: signer)
        }
    }

    /// Signs a fixture with the signer on `builder`'s context and reads the
    /// signed copy back.
    static func signAndReadWithContextSigner(
        _ builder: Builder,
        source: String = pexelsJPEG,
        format: String = "image/jpeg"
    ) throws -> ManifestStore {
        try signAndRead(source: source, format: format) { source, destination in
            try builder.sign(format: format, source: source, destination: destination)
        }
    }

    private static func signAndRead(
        source: String,
        format: String,
        sign: (_ source: Stream, _ destination: Stream) throws -> Data
    ) throws -> ManifestStore {
        let output = tempURL(extension: (source as NSString).pathExtension)
        defer { try? FileManager.default.removeItem(at: output) }
        _ = try sign(stream(source), Stream(writeTo: output))
        let reader = try Reader(format: format, stream: Stream(readFrom: output))
        return try ManifestStore(json: reader.json())
    }

    /// A path no other test uses, so parallel tests never share a file.
    static func tempURL(extension ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("c2pa-test-\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    /// A keychain tag no other test or earlier run uses.
    static func uniqueKeyTag(_ prefix: String) -> String {
        "org.contentauth.test.\(prefix).\(UUID().uuidString)"
    }
}

private final class BundleToken {}
