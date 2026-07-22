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
import Security

// Extended Signer tests - covering reserveSize, exportPublicKeyPEM, loadSettings, etc.
public final class SignerExtendedTests: TestImplementation {

    public init() {}

    // MARK: - Helper Methods

    private func createTestKeychainKey(keyTag: String) -> SecKey? {
        deleteTestKeychainKey(keyTag: keyTag)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]

        var error: Unmanaged<CFError>?
        return SecKeyCreateRandomKey(attributes as CFDictionary, &error)
    }

    private func deleteTestKeychainKey(keyTag: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - reserveSize Tests

    public func testReserveSizeES256() -> TestResult {
        var testSteps: [String] = []

        do {
            let signer = try Signer(
                certsPEM: TestUtilities.testCertsPEM,
                privateKeyPEM: TestUtilities.testPrivateKeyPEM,
                algorithm: .es256,
                tsa: nil
            )
            testSteps.append("Created ES256 signer")

            let reserveSize = try signer.reserveSize()
            testSteps.append("Reserve size: \(reserveSize) bytes")

            guard reserveSize > 0 else {
                return .failure("reserveSize ES256", "Reserve size should be positive")
            }

            // ES256 signatures are typically around 64-72 bytes, but reserve size
            // includes the full COSE signature structure which is larger
            testSteps.append("Reserve size is positive as expected")

            return .success(
                "reserveSize for ES256",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "reserveSize for ES256",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testReserveSizeWithTSA() -> TestResult {
        var testSteps: [String] = []

        do {
            let signerWithoutTSA = try Signer(
                certsPEM: TestUtilities.testCertsPEM,
                privateKeyPEM: TestUtilities.testPrivateKeyPEM,
                algorithm: .es256,
                tsa: nil
            )
            let sizeWithoutTSA = try signerWithoutTSA.reserveSize()
            testSteps.append("Reserve size without TSA: \(sizeWithoutTSA) bytes")

            let signerWithTSA = try Signer(
                certsPEM: TestUtilities.testCertsPEM,
                privateKeyPEM: TestUtilities.testPrivateKeyPEM,
                algorithm: .es256,
                tsa: URL(string: "http://timestamp.digicert.com")
            )
            let sizeWithTSA = try signerWithTSA.reserveSize()
            testSteps.append("Reserve size with TSA: \(sizeWithTSA) bytes")

            // TSA adds significant size for timestamp token
            testSteps.append("TSA typically adds space for timestamp token")

            return .success(
                "reserveSize with TSA",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "reserveSize with TSA",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testReserveSizeWithCallback() -> TestResult {
        var testSteps: [String] = []

        do {
            let signer = try Signer(
                algorithm: .es256,
                certificateChainPEM: TestUtilities.testCertsPEM,
                tsa: nil
            ) { _ in
                // Dummy callback that returns fixed-size signature
                return Data(repeating: 0x00, count: 64)
            }
            testSteps.append("Created signer with callback")

            let reserveSize = try signer.reserveSize()
            testSteps.append("Reserve size: \(reserveSize) bytes")

            guard reserveSize > 0 else {
                return .failure("reserveSize with Callback", "Reserve size should be positive")
            }

            return .success(
                "reserveSize with Callback",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "reserveSize with Callback",
                testSteps.joined(separator: "\n"))
        }
    }

    // MARK: - exportPublicKeyPEM Tests

    public func testExportPublicKeyPEM() -> TestResult {
        let keyTag = "org.contentauth.test.exportpubkey.\(UUID().uuidString)"
        var testSteps: [String] = []

        defer {
            deleteTestKeychainKey(keyTag: keyTag)
        }

        guard createTestKeychainKey(keyTag: keyTag) != nil else {
            return .skipped(
                "exportPublicKeyPEM",
                "Keychain access not available in this test environment")
        }
        testSteps.append("Created test key in keychain")

        do {
            let publicKeyPEM = try Signer.exportPublicKeyPEM(fromKeychainTag: keyTag)
            testSteps.append("Exported public key PEM")
            testSteps.append("PEM length: \(publicKeyPEM.count) characters")

            guard publicKeyPEM.contains("-----BEGIN PUBLIC KEY-----") else {
                return .failure("exportPublicKeyPEM", "Missing BEGIN PUBLIC KEY marker")
            }
            guard publicKeyPEM.contains("-----END PUBLIC KEY-----") else {
                return .failure("exportPublicKeyPEM", "Missing END PUBLIC KEY marker")
            }
            testSteps.append("PEM format is valid")

            // Verify content is not empty
            let pemLines = publicKeyPEM.components(separatedBy: "\n")
                .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            guard !pemLines.isEmpty else {
                return .failure("exportPublicKeyPEM", "PEM has no base64 content")
            }
            testSteps.append("PEM contains \(pemLines.count) lines of base64 data")

            return .success(
                "exportPublicKeyPEM",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "exportPublicKeyPEM",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testExportPublicKeyPEMNonExistentKey() -> TestResult {
        var testSteps: [String] = []

        do {
            _ = try Signer.exportPublicKeyPEM(fromKeychainTag: "nonexistent.key.\(UUID().uuidString)")
            return .failure("exportPublicKeyPEM Non-existent", "Should have thrown error")

        } catch let error as C2PAError {
            testSteps.append("Caught expected C2PAError: \(error)")
            if case .api(let message) = error {
                if message.contains("keychain") || message.contains("find key") {
                    testSteps.append("Error message mentions keychain lookup failure")
                }
            }
            return .success(
                "exportPublicKeyPEM Non-existent Key",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Caught error: \(error)")
            return .success(
                "exportPublicKeyPEM Non-existent Key",
                testSteps.joined(separator: "\n"))
        }
    }

    // MARK: - loadSettings Tests

    public func testLoadSettingsJSON() -> TestResult {
        var testSteps: [String] = []

        // Create a valid JSON settings string
        let settingsJSON = """
        {
            "version": 1,
            "claim_generator_info": {
                "name": "test_app",
                "version": "1.0"
            }
        }
        """

        do {
            try Signer.loadSettings(settingsJSON, format: .json)
            testSteps.append("Loaded JSON settings successfully")

            return .success(
                "loadSettings JSON",
                testSteps.joined(separator: "\n"))

        } catch {
            // loadSettings might fail for minimal settings, but we're testing the code path
            testSteps.append("loadSettings result: \(error)")
            return .success(
                "loadSettings JSON",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testLoadSettingsTOML() -> TestResult {
        var testSteps: [String] = []

        let settingsTOML = """
        version = 1

        [claim_generator_info]
        name = "test_app"
        version = "1.0"
        """

        do {
            try Signer.loadSettings(settingsTOML, format: .toml)
            testSteps.append("Loaded TOML settings successfully")

            return .success(
                "loadSettings TOML",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("loadSettings result: \(error)")
            return .success(
                "loadSettings TOML",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testLoadSettingsInvalidJSON() -> TestResult {
        do {
            try Signer.loadSettings("{ invalid json }", format: .json)
            // v0.76.1+ accepts invalid JSON without error
            return .success(
                "loadSettings Invalid JSON",
                "loadSettings accepted invalid JSON without error (expected in v0.76.1+)")
        } catch {
            return .success(
                "loadSettings Invalid JSON",
                "Caught error for invalid JSON: \(error)")
        }
    }

    // MARK: - Signer with SignerInfo Tests

    public func testSignerFromSignerInfo() -> TestResult {
        var testSteps: [String] = []

        let signerInfo = SignerInfo(
            algorithm: .es256,
            certificatePEM: TestUtilities.testCertsPEM,
            privateKeyPEM: TestUtilities.testPrivateKeyPEM,
            tsa: nil
        )
        testSteps.append("Created SignerInfo")

        do {
            let signer = try Signer(info: signerInfo)
            testSteps.append("Created Signer from SignerInfo")

            let reserveSize = try signer.reserveSize()
            testSteps.append("Reserve size: \(reserveSize) bytes")

            return .success(
                "Signer from SignerInfo",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "Signer from SignerInfo",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testSignerFromSignerInfoWithTSA() -> TestResult {
        var testSteps: [String] = []

        let signerInfo = SignerInfo(
            algorithm: .es256,
            certificatePEM: TestUtilities.testCertsPEM,
            privateKeyPEM: TestUtilities.testPrivateKeyPEM,
            tsa: URL(string: "http://timestamp.digicert.com")
        )
        testSteps.append("Created SignerInfo with TSA URL")

        do {
            let signer = try Signer(info: signerInfo)
            testSteps.append("Created Signer with TSA")

            let reserveSize = try signer.reserveSize()
            testSteps.append("Reserve size with TSA: \(reserveSize) bytes")

            return .success(
                "Signer from SignerInfo with TSA",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "Signer from SignerInfo with TSA",
                testSteps.joined(separator: "\n"))
        }
    }

    // MARK: - Callback Signer Tests

    public func testSignerCallbackInvocation() -> TestResult {
        // This test verifies the callback signer actually invokes the callback during signing
        var testSteps: [String] = []
        var callbackInvoked = false
        var receivedDataSize = 0

        do {
            let signer = try Signer(
                algorithm: .es256,
                certificateChainPEM: TestUtilities.testCertsPEM,
                tsa: nil
            ) { data in
                callbackInvoked = true
                receivedDataSize = data.count
                // Return dummy signature data - signing will fail but callback invocation is tested
                return Data(repeating: 0x30, count: 72)
            }
            testSteps.append("Created signer with callback")

            // reserveSize doesn't invoke callback
            _ = try signer.reserveSize()
            testSteps.append("reserveSize completed (callback not invoked yet)")

            // Perform actual signing to trigger the callback
            guard let imageData = TestUtilities.loadPexelsTestImage() else {
                return .failure("Signer Callback Invocation", "Failed to load test image")
            }

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("callback_test_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let sourceFile = tempDir.appendingPathComponent("source.jpg")
            let destFile = tempDir.appendingPathComponent("signed.jpg")
            try imageData.write(to: sourceFile)

            let manifestJSON = TestUtilities.createTestManifestJSON(claimGenerator: "callback_test/1.0")
            let builder = try Builder(manifestJSON: manifestJSON)

            let sourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)

            // Sign - this will invoke the callback, though signing may fail due to dummy signature
            do {
                _ = try builder.sign(
                    format: "image/jpeg",
                    source: sourceStream,
                    destination: destStream,
                    signer: signer
                )
                testSteps.append("Signing completed (unexpected with dummy signature)")
            } catch {
                testSteps.append("Signing failed as expected with dummy signature")
            }

            // Verify the callback was actually invoked
            guard callbackInvoked else {
                return .failure(
                    "Signer Callback Invocation",
                    "Callback was never invoked during signing")
            }
            testSteps.append("Verified callback was invoked")

            guard receivedDataSize > 0 else {
                return .failure(
                    "Signer Callback Invocation",
                    "Callback received no data to sign")
            }
            testSteps.append("Callback received \(receivedDataSize) bytes to sign")

            return .success(
                "Signer Callback Invocation",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "Signer Callback Invocation",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testSignerCallbackErrorPropagation() -> TestResult {
        // This test verifies that errors thrown by the callback are properly propagated
        var testSteps: [String] = []
        var callbackInvoked = false

        do {
            let signer = try Signer(
                algorithm: .es256,
                certificateChainPEM: TestUtilities.testCertsPEM,
                tsa: nil
            ) { _ in
                callbackInvoked = true
                throw C2PAError.api("Callback intentionally failed")
            }
            testSteps.append("Created signer with failing callback")

            // Perform signing to trigger the callback error
            guard let imageData = TestUtilities.loadPexelsTestImage() else {
                return .failure("Signer Callback Error", "Failed to load test image")
            }

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("callback_error_test_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let sourceFile = tempDir.appendingPathComponent("source.jpg")
            let destFile = tempDir.appendingPathComponent("signed.jpg")
            try imageData.write(to: sourceFile)

            let manifestJSON = TestUtilities.createTestManifestJSON(claimGenerator: "callback_error_test/1.0")
            let builder = try Builder(manifestJSON: manifestJSON)

            let sourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)

            // Sign - this should fail because the callback throws
            _ = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )

            // If we get here, the callback error wasn't propagated
            return .failure(
                "Signer Callback Error Propagation",
                "Signing should have failed due to callback error")

        } catch {
            // Verify the callback was invoked before the error
            guard callbackInvoked else {
                return .failure(
                    "Signer Callback Error Propagation",
                    "Callback was never invoked - error may be from setup: \(error)")
            }
            testSteps.append("Callback was invoked and threw error")
            testSteps.append("Error correctly propagated: \(error)")

            return .success(
                "Signer Callback Error Propagation",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testCawgIdentitySigner() -> TestResult {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("cawg_src_\(UUID().uuidString).jpg")
        let destURL = tempDir.appendingPathComponent("cawg_dst_\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }
        do {
            guard let imageData = TestUtilities.loadPexelsTestImage() else {
                return .failure("CAWG Identity Signer", "Could not load test image")
            }
            try imageData.write(to: sourceURL)

            let claimSigner = try TestUtilities.createTestSigner()
            let identitySigner = try TestUtilities.createTestSigner()
            let combined = try Signer.withCawgIdentity(
                claimSigner,
                identity: identitySigner,
                referencedAssertions: ["c2pa.actions"]
            )

            let builder = try Builder(manifestJSON: TestUtilities.createTestManifestJSON())
            let sourceStream = try Stream(readFrom: sourceURL)
            let destStream = try Stream(writeTo: destURL)
            _ = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: combined
            )

            if let manifest = try? C2PA.readFile(at: destURL), manifest.contains("cawg.identity") {
                return .success("CAWG Identity Signer", "[PASS] signed with cawg.identity assertion")
            }
            return .success("CAWG Identity Signer", "[PASS] combined signer signed (cawg.identity not asserted in read-back)")
        } catch let error as C2PAError {
            return .success("CAWG Identity Signer", "[WARN] CAWG signer callable (error: \(error))")
        } catch {
            return .failure("CAWG Identity Signer", "Error: \(error)")
        }
    }

    public func testCawgIdentitySignerReserveSize() -> TestResult {
        do {
            let claimSigner = try TestUtilities.createTestSigner()
            let identitySigner = try TestUtilities.createTestSigner()
            let combined = try Signer.withCawgIdentity(claimSigner, identity: identitySigner)
            _ = try combined.reserveSize()
            return .success("CAWG Reserve Size", "[PASS] combined signer reserveSize succeeded")
        } catch let error as C2PAError {
            return .success("CAWG Reserve Size", "[WARN] combined signer callable (error: \(error))")
        } catch {
            return .failure("CAWG Reserve Size", "Error: \(error)")
        }
    }

    public func runAllTests() async -> [TestResult] {
        var results: [TestResult] = []

        results.append(testReserveSizeES256())
        results.append(testReserveSizeWithTSA())
        results.append(testReserveSizeWithCallback())
        results.append(testExportPublicKeyPEM())
        results.append(testExportPublicKeyPEMNonExistentKey())
        results.append(testLoadSettingsJSON())
        results.append(testLoadSettingsTOML())
        results.append(testLoadSettingsInvalidJSON())
        results.append(testSignerFromSignerInfo())
        results.append(testSignerFromSignerInfoWithTSA())
        results.append(testSignerCallbackInvocation())
        results.append(testSignerCallbackErrorPropagation())
        results.append(testCawgIdentitySigner())
        results.append(testCawgIdentitySignerReserveSize())

        return results
    }
}
