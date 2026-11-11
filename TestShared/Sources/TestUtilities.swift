// This file is licensed to you under the Apache License, Version 2.0 
// (http://www.apache.org/licenses/LICENSE-2.0) or the MIT license 
// (http://opensource.org/licenses/MIT), at your option.
//
// Unless required by applicable law or agreed to in writing, this software is 
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF 
// ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE 
// files for the specific language governing permissions and limitations under
// each license.

import C2PA
import CryptoKit
import Foundation

// Helper class for bundle resolution
private class TestUtilitiesClassReference {}

/// Collects values delivered from native callbacks.
///
/// Callbacks fire synchronously on the thread running the operation, but a plain array
/// would still be shared mutable state as far as the compiler is concerned.
final class CallbackRecorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []

    func record(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
    }

    var recorded: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

/// Test-only escape hatch: a second reference to a signer that the compiler's region
/// analysis cannot see, so the runtime consumption guards stay exercisable once the signer
/// itself has been passed as `sending`.
///
/// Unchecked because `Signer` is not `Sendable`. A test keeps its alias on the thread that
/// created it.
final class SignerAlias: @unchecked Sendable {
    let signer: Signer

    init(_ signer: Signer) {
        self.signer = signer
    }
}

/// A broken test setup, such as a missing fixture.
///
/// Deliberately not a ``C2PAError``, so a test that expects the library to throw one
/// cannot mistake a setup failure for the error it is looking for.
struct TestSetupError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    /// Runs a setup step, turning whatever it throws into a ``TestSetupError``.
    static func wrapping<T>(_ failure: String, _ step: () throws -> T) throws -> T {
        do {
            return try step()
        } catch {
            throw TestSetupError("\(failure): \(error)")
        }
    }
}

// Shared test utilities and helper methods
public enum TestUtilities {

    // Loads a test resource from the bundle
    public static func loadTestResource(name: String, ext: String = "jpg", in bundle: Bundle? = nil)
        -> Data?
    {
        let targetBundle = bundle ?? Bundle(for: TestUtilitiesClassReference.self)
        guard let url = targetBundle.url(forResource: name, withExtension: ext) else {
            print("Error: Could not find resource \(name).\(ext) in bundle \(targetBundle)")
            return nil
        }
        return try? Data(contentsOf: url)
    }

    // Loads the Adobe test image with C2PA manifest
    public static func loadAdobeTestImage() -> Data? {
        return loadTestResource(name: "adobe-20220124-CI", ext: "jpg")
    }

    // Loads the Pexels test image without C2PA manifest
    public static func loadPexelsTestImage() -> Data? {
        return loadTestResource(name: "pexels-asadphoto-457882", ext: "jpg")
    }

    public static func loadVideoTestData() -> Data? {
        return loadTestResource(name: "video1", ext: "mp4")
    }

    // Test certificate PEM for testing (valid cert for actual signing)
    public static var testCertsPEM: String {
        let bundle = Bundle(for: TestUtilitiesClassReference.self)
        guard let url = bundle.url(forResource: "es256_certs", withExtension: "pem"),
            let certsPEM = try? String(contentsOf: url, encoding: .utf8)
        else {
            fatalError("Could not load es256_certs.pem from TestShared bundle")
        }
        return certsPEM
    }

    // Test private key PEM for testing (valid key for actual signing)
    public static var testPrivateKeyPEM: String {
        let bundle = Bundle(for: TestUtilitiesClassReference.self)
        guard let url = bundle.url(forResource: "es256_private", withExtension: "key"),
            let privateKeyPEM = try? String(contentsOf: url, encoding: .utf8)
        else {
            fatalError("Could not load es256_private.key from TestShared bundle")
        }
        return privateKeyPEM
    }

    // Invalid certificate PEM for testing expected failures
    public static var invalidCertsPEM: String {
        """
        -----BEGIN CERTIFICATE-----
        MIIBkTCB+wIJAKHO
        -----END CERTIFICATE-----
        """
    }

    // Invalid private key PEM for testing expected failures
    public static var invalidPrivateKeyPEM: String {
        """
        -----BEGIN PRIVATE KEY-----
        MIGHAgEAMBMGByqG
        -----END PRIVATE KEY-----
        """
    }

    // A settings signer section: a local ES256 signer on the test credentials
    public static var localSignerSection: [String: Any] {
        ["local": ["alg": "es256", "sign_cert": testCertsPEM, "private_key": testPrivateKeyPEM]]
    }

    // Settings JSON that configures a local signer on the test credentials. Entries in
    // `sections` are added as further top-level sections.
    public static func localSignerSettingsJSON(merging sections: [String: Any] = [:]) throws -> String {
        var settings: [String: Any] = ["version": 1, "signer": localSignerSection]
        settings.merge(sections) { _, added in added }
        let data = try JSONSerialization.data(withJSONObject: settings)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TestSetupError("Could not encode the settings as UTF-8")
        }
        return json
    }

    // Creates a test signer with valid credentials for actual signing
    public static func createTestSigner() throws -> Signer {
        return try Signer(
            certsPEM: testCertsPEM,
            privateKeyPEM: testPrivateKeyPEM,
            algorithm: .es256,
            tsa: nil
        )
    }

    // Creates a callback signer that produces valid ES256 signatures with the test key,
    // calling onSign with the bytes to be signed first
    public static func createTestCallbackSigner(
        onSign: @escaping @Sendable (Data) -> Void = { _ in }
    ) throws -> Signer {
        let key = try P256.Signing.PrivateKey(pemRepresentation: testPrivateKeyPEM)
        return try Signer(algorithm: .es256, certificateChainPEM: testCertsPEM) { data in
            onSign(data)
            return try key.signature(for: data).derRepresentation
        }
    }

    // Creates a test signer with invalid credentials for testing failures
    public static func createInvalidTestSigner() throws -> Signer {
        return try Signer(
            certsPEM: invalidCertsPEM,
            privateKeyPEM: invalidPrivateKeyPEM,
            algorithm: .es256,
            tsa: nil
        )
    }

    // Creates a minimal valid PNG data for testing
    public static func createTestPNGData() -> Data {
        var pngData = Data()
        // PNG signature
        pngData.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        // IHDR chunk
        pngData.append(contentsOf: [0x00, 0x00, 0x00, 0x0D])  // Length
        pngData.append("IHDR".data(using: .ascii)!)
        pngData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])  // Width: 1
        pngData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])  // Height: 1
        pngData.append(contentsOf: [0x08, 0x02, 0x00, 0x00, 0x00])  // Bit depth, color type, etc.
        pngData.append(contentsOf: [0x90, 0x77, 0x53, 0xDE])  // CRC
        // IDAT chunk
        pngData.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])  // Length
        pngData.append("IDAT".data(using: .ascii)!)
        pngData.append(contentsOf: [
            0x08, 0x1D, 0x01, 0x01, 0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x02
        ])
        pngData.append(contentsOf: [0x00, 0x01, 0xE2, 0x21])  // CRC
        // IEND chunk
        pngData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // Length
        pngData.append("IEND".data(using: .ascii)!)
        pngData.append(contentsOf: [0xAE, 0x42, 0x60, 0x82])  // CRC
        return pngData
    }

    // Sample manifest JSON for signing a new asset.
    //
    // The first action must be c2pa.created or c2pa.opened: c2pa-rs verifies the
    // manifest it just signed and rejects one whose actions do not start that way.
    // c2pa.created also needs a digitalSourceType.
    public static func createTestManifestJSON(claimGenerator: String = "test_app/1.0") -> String {
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

    // Sample manifest JSON for signing over an existing asset.
    //
    // Carries no inception action so that Builder.setIntent(.edit) can add the
    // parent ingredient from the source stream and the c2pa.opened action for it.
    public static func createTestEditManifestJSON(claimGenerator: String = "test_app/1.0") -> String {
        """
        {
            "claim_generator": "\(claimGenerator)",
            "assertions": [
                {"label": "c2pa.test", "data": {"test": true}}
            ]
        }
        """
    }

    // Reads a signed JPEG back and returns the assertion labels of its active manifest
    public static func activeManifestAssertionLabels(inJPEG asset: Data) throws -> [String] {
        let json = try Reader(format: "image/jpeg", stream: try Stream(data: asset)).json()
        guard let store = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let active = store["active_manifest"] as? String,
              let manifests = store["manifests"] as? [String: Any],
              let manifest = manifests[active] as? [String: Any],
              let assertions = manifest["assertions"] as? [[String: Any]]
        else {
            throw TestSetupError("No assertions in the active manifest: \(json.prefix(300))")
        }
        return assertions.compactMap { $0["label"] as? String }
    }

    // Whether assertion labels include a CAWG identity assertion. A manifest's second one
    // is labelled cawg.identity__1, and so on.
    public static func containsCawgIdentity(_ labels: [String]) -> Bool {
        labels.contains { $0 == "cawg.identity" || $0.hasPrefix("cawg.identity__") }
    }
}
