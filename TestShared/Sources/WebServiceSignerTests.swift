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

// WebServiceSigner tests - testing web service-based signing
// Tests focus on initialization, error handling, and code paths that don't require a server
public final class WebServiceSignerTests: TestImplementation {

    public init() {}

    // MARK: - Initialization Tests

    public func testWebServiceSignerCreation() -> TestResult {
        var testSteps: [String] = []

        let signer1 = WebServiceSigner(
            configurationEndpoint: URL(string: "https://example.com/config")!
        )
        testSteps.append("Created WebServiceSigner with minimal parameters")

        let signer2 = WebServiceSigner(
            configurationEndpoint: URL(string: "https://example.com/config")!,
            bearerToken: "test-token"
        )
        testSteps.append("Created WebServiceSigner with bearer token")

        let signer3 = WebServiceSigner(
            configurationEndpoint: URL(string: "https://example.com/config")!,
            bearerToken: "test-token",
            headers: ["X-Custom-Header": "test-value", "X-Another": "value2"]
        )
        testSteps.append("Created WebServiceSigner with custom headers")

        // Verify all signers are distinct instances
        guard ObjectIdentifier(signer1) != ObjectIdentifier(signer2) else {
            return .failure("WebServiceSigner Creation", "signer1 and signer2 should be distinct instances")
        }
        guard ObjectIdentifier(signer2) != ObjectIdentifier(signer3) else {
            return .failure("WebServiceSigner Creation", "signer2 and signer3 should be distinct instances")
        }
        testSteps.append("Verified all signers are distinct instances")

        return .success(
            "WebServiceSigner Creation",
            testSteps.joined(separator: "\n"))
    }

    // MARK: - Connection Failure Tests

    public func testCreateSignerInvalidURL() async -> TestResult {
        var testSteps: [String] = []

        // Test with clearly invalid URL
        let signer = WebServiceSigner(
            configurationEndpoint: URL(string: "not-a-valid-url")!
        )

        do {
            _ = try await signer.createSigner()
            return .failure("createSigner Invalid URL", "Should have thrown error for invalid URL")

        } catch let error as SignerError {
            testSteps.append("Caught SignerError: \(error)")
            if case .invalidURL = error {
                testSteps.append("Error is correctly .invalidURL")
            }
            return .success(
                "createSigner Invalid URL",
                testSteps.joined(separator: "\n"))

        } catch let error as URLError {
            // URLError is acceptable - invalid URL format detected by URL loading system
            testSteps.append("Caught URLError: \(error.localizedDescription)")
            return .success(
                "createSigner Invalid URL",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Caught unexpected error type: \(type(of: error)) - \(error)")
            return .failure(
                "createSigner Invalid URL",
                "Expected SignerError.invalidURL or URLError, but got: \(type(of: error))")
        }
    }

    public func testCreateSignerConnectionFailure() async -> TestResult {
        var testSteps: [String] = []

        // Test with a URL that won't respond
        let signer = WebServiceSigner(
            configurationEndpoint: URL(string: "http://localhost:59999/nonexistent")!
        )

        do {
            _ = try await signer.createSigner()
            return .failure("createSigner Connection Failure", "Should have thrown error")

        } catch {
            testSteps.append("Caught expected error: \(error)")
            return .success(
                "createSigner Connection Failure",
                testSteps.joined(separator: "\n"))
        }
    }

    // MARK: - Async Signer Extension Tests

    public func testAsyncSignerCreation() async -> TestResult {
        var testSteps: [String] = []
        // Written by the signer closure, which the signing bridge runs to completion before
        // `sign` returns, so every read below comes after the write.
        nonisolated(unsafe) var asyncClosureInvoked = false
        nonisolated(unsafe) var dataReceived: Data?

        do {
            let signer = try Signer(
                algorithm: .es256,
                certificateChainPEM: TestUtilities.testCertsPEM,
                tsa: nil,
                asyncSigner: { data in
                    // Track that closure was invoked and capture input
                    asyncClosureInvoked = true
                    dataReceived = data
                    // Return dummy data - signing will fail but we can verify the callback was invoked
                    return Data(repeating: 0x30, count: 72)
                }
            )
            testSteps.append("Created Signer with asyncSigner closure")

            let reserveSize = try signer.reserveSize()
            testSteps.append("Reserve size: \(reserveSize) bytes")

            // Try to use the signer to verify the async closure is invoked
            // The signing will fail because we return invalid signature data,
            // but that's expected - we're testing the callback invocation
            guard let imageData = TestUtilities.loadPexelsTestImage() else {
                return .failure("Async Signer Creation", "Failed to load test image")
            }

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("async_signer_test_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let sourceFile = tempDir.appendingPathComponent("source.jpg")
            let destFile = tempDir.appendingPathComponent("signed.jpg")
            try imageData.write(to: sourceFile)

            let manifestJSON = TestUtilities.createTestManifestJSON(claimGenerator: "async_signer_test/1.0")
            let builder = try Builder(manifestJSON: manifestJSON)

            let sourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)

            // Sign - this will fail because our callback returns invalid signature data
            do {
                _ = try builder.sign(
                    format: "image/jpeg",
                    source: sourceStream,
                    destination: destStream,
                    signer: signer
                )
                testSteps.append("Signing unexpectedly succeeded with dummy signature")
            } catch {
                testSteps.append("Signing failed as expected (invalid signature): \(error)")
            }

            // Verify the async closure was actually invoked
            guard asyncClosureInvoked else {
                return .failure("Async Signer Creation", "Async closure was never invoked during signing attempt")
            }
            testSteps.append("Verified async closure was invoked")

            guard let receivedData = dataReceived, !receivedData.isEmpty else {
                return .failure("Async Signer Creation", "Async closure received no data to sign")
            }
            testSteps.append("Async closure received \(receivedData.count) bytes to sign")

            return .success(
                "Async Signer Creation",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error creating signer: \(error)")
            return .failure(
                "Async Signer Creation",
                testSteps.joined(separator: "\n"))
        }
    }

    public func testAsyncSignerWithTSA() -> TestResult {
        var testSteps: [String] = []

        do {
            let signer = try Signer(
                algorithm: .es256,
                certificateChainPEM: TestUtilities.testCertsPEM,
                tsa: URL(string: "http://timestamp.digicert.com"),
                asyncSigner: { _ in
                    return Data(repeating: 0x30, count: 72)
                }
            )
            testSteps.append("Created async Signer with TSA URL")

            let reserveSize = try signer.reserveSize()
            testSteps.append("Reserve size with TSA: \(reserveSize) bytes")

            return .success(
                "Async Signer with TSA",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "Async Signer with TSA",
                testSteps.joined(separator: "\n"))
        }
    }

    // MARK: - Integration with Local Server (when available)

    public func testWebServiceSignerWithLocalServer() async -> TestResult {
        var testSteps: [String] = []

        // Check if the local signing server is running
        guard let healthURL = URL(string: "http://127.0.0.1:8080/health") else {
            return .skipped(
                "WebServiceSigner Local Server",
                "Could not create health check URL")
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: healthURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return .skipped(
                    "WebServiceSigner Local Server",
                    "Signing server not running (run 'make signing-server-start')")
            }
            testSteps.append("Signing server is available")

        } catch {
            return .skipped(
                "WebServiceSigner Local Server",
                "Signing server not available: \(error)")
        }

        // Server is available, test the full flow
        let configurationURL = ProcessInfo.processInfo.environment["SIGNING_SERVER_URL"] ?? "http://127.0.0.1:8080"
        let bearerToken = ProcessInfo.processInfo.environment["SIGNING_SERVER_TOKEN"] ?? "test-bearer-token-12345"
        let signer = WebServiceSigner(
            configurationEndpoint: URL(string: "\(configurationURL)/api/v1/c2pa/configuration")!,
            bearerToken: bearerToken
        )

        do {
            let realSigner = try await signer.createSigner()
            testSteps.append("Created signer from web service")

            let reserveSize = try realSigner.reserveSize()
            testSteps.append("Reserve size: \(reserveSize) bytes")

            // Try signing an actual file
            guard let imageData = TestUtilities.loadPexelsTestImage() else {
                return .failure(
                    "WebServiceSigner Local Server",
                    "Failed to load test image")
            }
            testSteps.append("Loaded test image")

            let manifestJSON = TestUtilities.createTestManifestJSON(claimGenerator: "webservice_test/1.0")
            let builder = try Builder(manifestJSON: manifestJSON)

            // Use temp files for signing
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("webservice_test_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let sourceFile = tempDir.appendingPathComponent("source.jpg")
            let destFile = tempDir.appendingPathComponent("signed.jpg")
            try imageData.write(to: sourceFile)

            let sourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)

            _ = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: realSigner
            )
            testSteps.append("Signed image using web service signer")
            let outputData = try Data(contentsOf: destFile)
            testSteps.append("Output size: \(outputData.count) bytes")

            return .success(
                "WebServiceSigner Local Server",
                testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("Error: \(error)")
            return .failure(
                "WebServiceSigner Local Server",
                testSteps.joined(separator: "\n"))
        }
    }

    public func runAllTests() async -> [TestResult] {
        var results: [TestResult] = []

        results.append(testWebServiceSignerCreation())
        results.append(await testCreateSignerInvalidURL())
        results.append(await testCreateSignerConnectionFailure())
        results.append(await testAsyncSignerCreation())
        results.append(testAsyncSignerWithTSA())
        results.append(await testWebServiceSignerWithLocalServer())

        return results
    }
}
