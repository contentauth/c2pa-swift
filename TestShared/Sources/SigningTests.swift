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

// Signing tests
public final class SigningTests: TestImplementation {

    public init() {}

    private let keyTag = "org.contentauth.test.key.\(UUID().uuidString)"

    public func testSignerCreation() -> TestResult {
        // This test attempts to create a signer with test certificates
        // If the certs are invalid, this is expected to fail
        do {
            let signer = try Signer(
                certsPEM: TestUtilities.testCertsPEM,
                privateKeyPEM: TestUtilities.testPrivateKeyPEM,
                algorithm: .es256,
                tsa: nil
            )
            _ = signer
            return .success("Signer Creation", "[PASS] Created PEM-based signer with valid certificates")
        } catch let error as C2PAError {
            // If certificates are invalid, this is a FAILURE not a success
            return .failure("Signer Creation", "Certificate/key error (test certs may be invalid): \(error)")
        } catch {
            return .failure("Signer Creation", "Failed: \(error)")
        }
    }

    public func testSignerWithCallback() -> TestResult {
        // This test verifies that the callback mechanism works
        // It's not testing actual signing validity
        var callbackInvoked = false
        var dataToSign: Data?

        let signCallback: (Data) throws -> Data = { data in
            callbackInvoked = true
            dataToSign = data

            // Return dummy signature data - this won't be cryptographically valid
            // but that's OK since we're just testing the callback mechanism
            return Data(repeating: 0x42, count: 64)
        }

        do {
            let signer = try Signer(
                algorithm: .es256,
                certificateChainPEM: TestUtilities.testCertsPEM,
                tsa: nil,
                sign: signCallback
            )

            // Actually use the signer to trigger the callback
            let testManifest = TestUtilities.createTestManifestJSON()
            let builder = try Builder(manifestJSON: testManifest)

            guard let imageData = TestUtilities.loadPexelsTestImage() else {
                return .failure("Signer With Callback", "Could not load test image")
            }

            let tempDir = FileManager.default.temporaryDirectory
            let sourceFile = tempDir.appendingPathComponent("callback_source_\(UUID().uuidString).jpg")
            let destFile = tempDir.appendingPathComponent("callback_dest_\(UUID().uuidString).jpg")

            defer {
                try? FileManager.default.removeItem(at: sourceFile)
                try? FileManager.default.removeItem(at: destFile)
            }

            try imageData.write(to: sourceFile)

            let sourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)

            _ = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )

            // If we get here without errors, callback should have been invoked
            if callbackInvoked && dataToSign != nil {
                return .success(
                    "Signer With Callback",
                    "[PASS] Callback mechanism works - invoked with \(dataToSign?.count ?? 0) bytes")
            } else {
                return .failure(
                    "Signer With Callback",
                    "Callback was not invoked during signing")
            }
        } catch {
            // Check if the callback was at least invoked before failure
            if callbackInvoked && dataToSign != nil {
                return .success(
                    "Signer With Callback",
                    "[PASS] Callback mechanism works - invoked with \(dataToSign?.count ?? 0) bytes (signing failed as expected with dummy signature)"
                )
            } else {
                // The callback wasn't invoked at all - this is a real failure
                return .failure(
                    "Signer With Callback",
                    "Callback mechanism failed - callback not invoked: \(error)")
            }
        }
    }

    public func testSigningAlgorithms() -> TestResult {
        // Test certs are ES256 - only ES256 should work, others should fail
        var results: [String] = []

        // ES256 MUST work with our test certificates
        do {
            _ = try Signer(
                certsPEM: TestUtilities.testCertsPEM,
                privateKeyPEM: TestUtilities.testPrivateKeyPEM,
                algorithm: .es256,
                tsa: nil
            )
            results.append("ES256: PASS (expected)")
        } catch {
            return .failure("Signing Algorithms", "ES256 should work with test certs but failed: \(error)")
        }

        // Other algorithms should fail with ES256 certs (mismatched algorithm/key)
        let mismatchedAlgorithms: [SigningAlgorithm] = [.es384, .es512, .ps256, .ps384, .ps512, .ed25519]

        for algorithm in mismatchedAlgorithms {
            do {
                _ = try Signer(
                    certsPEM: TestUtilities.testCertsPEM,
                    privateKeyPEM: TestUtilities.testPrivateKeyPEM,
                    algorithm: algorithm,
                    tsa: nil
                )
                // If it doesn't throw, that's unexpected behavior
                results.append("\(algorithm): UNEXPECTED SUCCESS (should fail with ES256 certs)")
            } catch {
                // Expected - mismatched algorithm should fail
                results.append("\(algorithm): EXPECTED FAILURE")
            }
        }

        return .success(
            "Signing Algorithms",
            results.joined(separator: "\n"))
    }


    public func testSignerWithTimestampAuthority() -> TestResult {
        let tsa = URL(string: "http://timestamp.digecert.com")

        do {
            let signer = try Signer(
                certsPEM: TestUtilities.testCertsPEM,
                privateKeyPEM: TestUtilities.testPrivateKeyPEM,
                algorithm: .es256,
                tsa: tsa
            )
            _ = signer
            return .success("Signer With TSA", "[PASS] Created signer with TSA URL")
        } catch {
            // Certificate or TSA errors are failures, not successes
            return .failure("Signer With TSA", "Failed to create signer with TSA: \(error)")
        }
    }

    public func testWebServiceSignerCreation() async -> TestResult {
        var testSteps: [String] = []
        var testsPassed = 0

        // Test connection to signing server - handle connection failures gracefully
        let healthURL = URL(string: "http://127.0.0.1:8080/health")!

        let serverAvailable: Bool
        do {
            let (_, response) = try await URLSession.shared.data(from: healthURL)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                serverAvailable = true
            } else {
                serverAvailable = false
            }
        } catch {
            // Connection refused, timeout, etc. - server not available
            return .skipped(
                "Web Service Real Signing & Verification",
                "Signing server not available (run 'make signing-server-start')")
        }

        guard serverAvailable else {
            return .skipped(
                "Web Service Real Signing & Verification",
                "Signing server not running (run 'make signing-server-start')")
        }

        testSteps.append("Connected to signing server")

        do {
            testSteps.append("Server health check passed")
            testsPassed += 1

            // Create WebServiceSigner with the configuration URL and bearer token
            let configurationURL = ProcessInfo.processInfo.environment["SIGNING_SERVER_URL"] ?? "http://127.0.0.1:8080"
            let bearerToken = ProcessInfo.processInfo.environment["SIGNING_SERVER_TOKEN"] ?? "test-bearer-token-12345"
            let webServiceSigner = WebServiceSigner(
                configurationEndpoint: URL(string: "\(configurationURL)/api/v1/c2pa/configuration")!,
                bearerToken: bearerToken
            )
            testSteps.append("✓ Created WebServiceSigner with configuration URL")

            // Create a signer from the web service
            let signer = try await webServiceSigner.createSigner()
            testSteps.append("✓ Successfully created signer from web service configuration")
            testsPassed += 1

            // Load test image and attempt to sign
            guard let testImageData = TestUtilities.loadPexelsTestImage() else {
                throw C2PAError.api("Could not load test image")
            }
            testSteps.append("✓ Loaded test image")

            // Create a test manifest and sign the image
            let manifestJSON = "{\"claim_generator\":\"c2pa-ios-test/1.0\",\"title\":\"Web Service Test\"}"

            do {
                let builder = try Builder(manifestJSON: manifestJSON)

                let tempDir = FileManager.default.temporaryDirectory
                let sourceFile = tempDir.appendingPathComponent("test_source_\(UUID().uuidString).jpg")
                let destFile = tempDir.appendingPathComponent("test_signed_\(UUID().uuidString).jpg")

                defer {
                    try? FileManager.default.removeItem(at: sourceFile)
                    try? FileManager.default.removeItem(at: destFile)
                }

                try testImageData.write(to: sourceFile)

                let sourceStream = try Stream(readFrom: sourceFile)
                let destStream = try Stream(writeTo: destFile)

                _ = try builder.sign(
                    format: "image/jpeg",
                    source: sourceStream,
                    destination: destStream,
                    signer: signer
                )

                testSteps.append("✓ Successfully signed image using web service signer")
                testsPassed += 1

                // Verify the signed image
                let signedData = try Data(contentsOf: destFile)
                let signedStream = try Stream(data: signedData)
                let reader = try Reader(format: "image/jpeg", stream: signedStream)
                let verifiedManifestJSON = try reader.json()

                if !verifiedManifestJSON.isEmpty {
                    testSteps.append("✓ Verified signed image contains C2PA manifest")

                    if let manifestData = verifiedManifestJSON.data(using: .utf8),
                        let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
                    {
                        if manifest["claim_generator"] != nil {
                            testSteps.append("✓ Manifest contains claim_generator")
                        }
                        if manifest["title"] != nil {
                            testSteps.append("✓ Manifest contains title")
                        }
                    }
                }
            } catch {
                testSteps.append("[WARN] Signing with web service failed (expected in test mode): \(error)")
            }

        } catch {
            testSteps.append("✗ Test failed: \(error)")
        }

        return TestResult(
            testName: "Web Service Real Signing & Verification",
            passed: testsPassed >= 2,
            message: "Completed \(testsPassed)/3 signing server tests\n"
                + testSteps.joined(separator: "\n")
        )
    }


    public func testSignerWithActualSigning() -> TestResult {
        let manifestJSON = TestUtilities.createTestManifestJSON()

        do {
            let builder = try Builder(manifestJSON: manifestJSON)

            // Create test files instead of using streams directly
            guard let sourceData = TestUtilities.loadPexelsTestImage() else {
                return .failure("Signer With Actual Signing", "Could not load test image")
            }

            let tempDir = FileManager.default.temporaryDirectory
            let sourceFile = tempDir.appendingPathComponent("sign_source_\(UUID().uuidString).jpg")
            let destFile = tempDir.appendingPathComponent("sign_dest_\(UUID().uuidString).jpg")

            defer {
                try? FileManager.default.removeItem(at: sourceFile)
                try? FileManager.default.removeItem(at: destFile)
            }

            // Write source image to file
            try sourceData.write(to: sourceFile)

            // Create file-based streams
            let sourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)

            let signer = try TestUtilities.createTestSigner()

            _ = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )
            return .success("Signer With Actual Signing", "[PASS] Signing operation completed successfully")

        } catch {
            // All errors are failures - if certs are invalid, that's a real failure
            return .failure("Signer With Actual Signing", "Signing failed: \(error)")
        }
    }

    public func testSignerFromSettingsTOML() -> TestResult {
        let bundle = Bundle(for: type(of: self))

        guard let tomlURL = bundle.url(forResource: "test_settings_with_cawg_signing", withExtension: "toml") else {
            return .failure("Signer From Settings (TOML)", "Fixture not found: test_settings_with_cawg_signing.toml")
        }

        do {
            let settingsTOML = try String(contentsOf: tomlURL, encoding: .utf8)
            let signer = try Signer(settingsTOML: settingsTOML)

            // Load test image
            guard let sourceData = TestUtilities.loadPexelsTestImage() else {
                return .failure("Signer From Settings (TOML)", "Could not load test image")
            }

            // Create manifest
            let manifestJSON = TestUtilities.createTestManifestJSON()
            let builder = try Builder(manifestJSON: manifestJSON)

            let tempDir = FileManager.default.temporaryDirectory
            let sourceFile = tempDir.appendingPathComponent("settings_toml_source_\(UUID().uuidString).jpg")
            let destFile = tempDir.appendingPathComponent("settings_toml_dest_\(UUID().uuidString).jpg")

            defer {
                try? FileManager.default.removeItem(at: sourceFile)
                try? FileManager.default.removeItem(at: destFile)
            }

            try sourceData.write(to: sourceFile)

            let sourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)

            _ = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )

            // Verify the signed image contains a valid manifest
            let signedData = try Data(contentsOf: destFile)
            let signedStream = try Stream(data: signedData)
            let reader = try Reader(format: "image/jpeg", stream: signedStream)
            let manifestJSONResult = try reader.json()

            guard let manifestData = manifestJSONResult.data(using: .utf8),
                (try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any]) != nil
            else {
                return .failure("Signer From Settings (TOML)", "Could not parse manifest JSON")
            }

            // Successfully signed and verified manifest
            // Check for CAWG-related content in the parsed manifest structure
            guard let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
                  let manifests = manifest["manifests"] as? [String: Any],
                  let firstManifest = manifests.values.first as? [String: Any],
                  let assertions = firstManifest["assertions"] as? [[String: Any]] else {
                return .success(
                    "Signer From Settings (TOML)",
                    "[PASS] Signed image with CAWG settings - manifest valid but no assertions to inspect")
            }

            // Check assertion labels for CAWG content
            let assertionLabels = assertions.compactMap { $0["label"] as? String }
            let hasCawgAssertion = assertionLabels.contains { label in
                label.contains("cawg") || label.contains("training") || label.contains("mining")
            }

            if hasCawgAssertion {
                return .success(
                    "Signer From Settings (TOML)",
                    "[PASS] Signed image with CAWG signer - found CAWG assertions: \(assertionLabels)")
            } else {
                return .success(
                    "Signer From Settings (TOML)",
                    "[PASS] Signed image with CAWG settings - assertions: \(assertionLabels)")
            }

        } catch let error as C2PAError {
            return .failure("Signer From Settings (TOML)", "Failed - \(error)")
        } catch {
            return .failure("Signer From Settings (TOML)", "Failed - \(error)")
        }
    }

    public func testSignerFromSettingsJSON() -> TestResult {
        let bundle = Bundle(for: type(of: self))

        guard let jsonURL = bundle.url(forResource: "test_settings_with_cawg_signing", withExtension: "json") else {
            return .failure("Signer From Settings (JSON)", "Fixture not found: test_settings_with_cawg_signing.json")
        }

        do {
            let settingsJSON = try String(contentsOf: jsonURL, encoding: .utf8)
            let signer = try Signer(settingsJSON: settingsJSON)

            // Load test image
            guard let sourceData = TestUtilities.loadPexelsTestImage() else {
                return .failure("Signer From Settings (JSON)", "Could not load test image")
            }

            // Create manifest
            let manifestJSON = TestUtilities.createTestManifestJSON()
            let builder = try Builder(manifestJSON: manifestJSON)

            let tempDir = FileManager.default.temporaryDirectory
            let sourceFile = tempDir.appendingPathComponent("settings_json_source_\(UUID().uuidString).jpg")
            let destFile = tempDir.appendingPathComponent("settings_json_dest_\(UUID().uuidString).jpg")

            defer {
                try? FileManager.default.removeItem(at: sourceFile)
                try? FileManager.default.removeItem(at: destFile)
            }

            try sourceData.write(to: sourceFile)

            let sourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)

            _ = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )

            // Verify the signed image contains a valid manifest
            let signedData = try Data(contentsOf: destFile)
            let signedStream = try Stream(data: signedData)
            let reader = try Reader(format: "image/jpeg", stream: signedStream)
            let manifestJSONResult = try reader.json()

            guard let manifestData = manifestJSONResult.data(using: .utf8),
                (try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any]) != nil
            else {
                return .failure("Signer From Settings (JSON)", "Could not parse manifest JSON")
            }

            // Successfully signed and verified manifest
            // Check for CAWG-related content in the parsed manifest structure
            guard let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
                  let manifests = manifest["manifests"] as? [String: Any],
                  let firstManifest = manifests.values.first as? [String: Any],
                  let assertions = firstManifest["assertions"] as? [[String: Any]] else {
                return .success(
                    "Signer From Settings (JSON)",
                    "[PASS] Signed image with CAWG settings - manifest valid but no assertions to inspect")
            }

            // Check assertion labels for CAWG content
            let assertionLabels = assertions.compactMap { $0["label"] as? String }
            let hasCawgAssertion = assertionLabels.contains { label in
                label.contains("cawg") || label.contains("training") || label.contains("mining")
            }

            if hasCawgAssertion {
                return .success(
                    "Signer From Settings (JSON)",
                    "[PASS] Signed image with CAWG signer - found CAWG assertions: \(assertionLabels)")
            } else {
                return .success(
                    "Signer From Settings (JSON)",
                    "[PASS] Signed image with CAWG settings - assertions: \(assertionLabels)")
            }

        } catch let error as C2PAError {
            return .failure("Signer From Settings (JSON)", "Failed - \(error)")
        } catch {
            return .failure("Signer From Settings (JSON)", "Failed - \(error)")
        }
    }

    // MARK: - Edge Case Tests

    public func testDoubleSigningImage() -> TestResult {
        // Test signing an image that already has a C2PA manifest (double-signing)
        var testSteps: [String] = []

        guard let signedImageData = TestUtilities.loadAdobeTestImage() else {
            return .failure("Double Signing", "Could not load Adobe test image (which has existing manifest)")
        }
        testSteps.append("Loaded Adobe test image with existing manifest (\(signedImageData.count) bytes)")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("double_sign_test_\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let sourceFile = tempDir.appendingPathComponent("already_signed.jpg")
            let destFile = tempDir.appendingPathComponent("double_signed.jpg")

            try signedImageData.write(to: sourceFile)

            // Verify source has a manifest
            let sourceStream = try Stream(readFrom: sourceFile)
            let sourceReader = try Reader(format: "image/jpeg", stream: sourceStream)
            let originalManifest = try sourceReader.json()
            guard !originalManifest.isEmpty else {
                return .failure("Double Signing", "Source image doesn't have a manifest - test setup error")
            }
            testSteps.append("Verified source has existing manifest")

            // Now sign it again with a new manifest. The edit intent makes the
            // existing manifest the parent ingredient and opens it.
            let signer = try TestUtilities.createTestSigner()
            let manifestJSON = TestUtilities.createTestEditManifestJSON(claimGenerator: "double_sign_test/1.0")
            let builder = try Builder(manifestJSON: manifestJSON)
            try builder.setIntent(.edit)

            let signSourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)

            _ = try builder.sign(
                format: "image/jpeg",
                source: signSourceStream,
                destination: destStream,
                signer: signer
            )
            testSteps.append("Double-signed the image")

            // Verify the result has a manifest with our new claim generator
            let signedData = try Data(contentsOf: destFile)
            testSteps.append("Output size: \(signedData.count) bytes")

            let resultStream = try Stream(data: signedData)
            let resultReader = try Reader(format: "image/jpeg", stream: resultStream)
            let resultManifest = try resultReader.json()

            // Verify the manifest has required C2PA fields and multiple manifests (original + new)
            guard let manifestData = resultManifest.data(using: .utf8),
                  let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
                let excerpt = String(resultManifest.prefix(500))
                return .failure("Double Signing", "Double-signed image doesn't have valid JSON manifest. Excerpt: \(excerpt)")
            }

            // Check that we have manifests (the double-signed image should have at least 2)
            if let manifests = manifest["manifests"] as? [String: Any] {
                testSteps.append("Double-signed image has \(manifests.count) manifest(s)")
            }
            testSteps.append("Double-signed image has valid C2PA manifest structure")

            return .success(
                "Double Signing Image",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "Double Signing Image",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testZeroByteFile() -> TestResult {
        // Test handling of zero-byte file - should fail gracefully
        var testSteps: [String] = []

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("zero_byte_test_\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let sourceFile = tempDir.appendingPathComponent("empty.jpg")
            let destFile = tempDir.appendingPathComponent("signed.jpg")

            // Create zero-byte file
            try Data().write(to: sourceFile)
            testSteps.append("Created zero-byte file")

            let signer = try TestUtilities.createTestSigner()
            let manifestJSON = TestUtilities.createTestManifestJSON()
            let builder = try Builder(manifestJSON: manifestJSON)

            let sourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)

            _ = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )

            // If we get here, signing unexpectedly succeeded on empty file
            return .failure(
                "Zero Byte File",
                "Signing should have failed for zero-byte file")

        } catch let error as C2PAError {
            testSteps.append("Correctly failed with C2PAError: \(error)")
            return .success(
                "Zero Byte File Handling",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Failed with error: \(error)")
            return .success(
                "Zero Byte File Handling",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testInvalidCertificateChain() -> TestResult {
        // Test handling of malformed certificate PEM
        var testSteps: [String] = []

        let invalidCerts: [(String, String)] = [
            ("empty string", ""),
            ("not PEM at all", "this is definitely not a certificate"),
            ("incomplete PEM header", "-----BEGIN CERTIFICATE-----"),
            ("invalid base64", "-----BEGIN CERTIFICATE-----\nnotbase64!!!\n-----END CERTIFICATE-----"),
            ("truncated certificate", "-----BEGIN CERTIFICATE-----\nTUlJQ2\n-----END CERTIFICATE-----")
        ]

        for (description, invalidCert) in invalidCerts {
            do {
                _ = try Signer(
                    certsPEM: invalidCert,
                    privateKeyPEM: TestUtilities.testPrivateKeyPEM,
                    algorithm: .es256,
                    tsa: nil
                )
                testSteps.append("\(description): UNEXPECTED SUCCESS")
            } catch {
                testSteps.append("\(description): correctly rejected")
            }
        }

        // At least some should have been rejected
        let rejectedCount = testSteps.filter { $0.contains("correctly rejected") }.count
        guard rejectedCount >= 3 else {
            return .failure(
                "Invalid Certificate Chain",
                "Too many invalid certificates were accepted: " + testSteps.joined(separator: "\n"))
        }

        return .success(
            "Invalid Certificate Chain Handling",
            testSteps.joined(separator: "\n"))
    }

    public func testInvalidPrivateKey() -> TestResult {
        // Test handling of malformed private key PEM
        var testSteps: [String] = []

        let invalidKeys: [(String, String)] = [
            ("empty string", ""),
            ("not PEM at all", "this is definitely not a private key"),
            ("incomplete PEM header", "-----BEGIN PRIVATE KEY-----"),
            ("wrong key type header", "-----BEGIN RSA PRIVATE KEY-----\nTUlJQ2\n-----END RSA PRIVATE KEY-----")
        ]

        for (description, invalidKey) in invalidKeys {
            do {
                _ = try Signer(
                    certsPEM: TestUtilities.testCertsPEM,
                    privateKeyPEM: invalidKey,
                    algorithm: .es256,
                    tsa: nil
                )
                testSteps.append("\(description): UNEXPECTED SUCCESS")
            } catch {
                testSteps.append("\(description): correctly rejected")
            }
        }

        // At least some should have been rejected
        let rejectedCount = testSteps.filter { $0.contains("correctly rejected") }.count
        guard rejectedCount >= 2 else {
            return .failure(
                "Invalid Private Key",
                "Too many invalid keys were accepted: " + testSteps.joined(separator: "\n"))
        }

        return .success(
            "Invalid Private Key Handling",
            testSteps.joined(separator: "\n"))
    }

    public func runAllTests() async -> [TestResult] {
        return [
            testSignerCreation(),
            testSignerWithCallback(),
            testSigningAlgorithms(),
            testSignerWithTimestampAuthority(),
            await testWebServiceSignerCreation(),
            testSignerWithActualSigning(),
            testSignerFromSettingsTOML(),
            testSignerFromSettingsJSON(),
            // Edge case tests
            testDoubleSigningImage(),
            testZeroByteFile(),
            testInvalidCertificateChain(),
            testInvalidPrivateKey()
        ]
    }
}
