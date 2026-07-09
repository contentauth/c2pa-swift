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
import Foundation

// Helper class for bundle resolution
private class TestUtilitiesClassReference {}

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

    // Creates a test signer with valid credentials for actual signing
    public static func createTestSigner() throws -> Signer {
        return try Signer(
            certsPEM: testCertsPEM,
            privateKeyPEM: testPrivateKeyPEM,
            algorithm: .es256,
            tsa: nil
        )
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

    // Sample manifest JSON for testing
    public static func createTestManifestJSON(claimGenerator: String = "test_app/1.0") -> String {
        """
        {
            "claim_generator": "\(claimGenerator)",
            "assertions": [
                {"label": "c2pa.test", "data": {"test": true}}
            ]
        }
        """
    }
}
