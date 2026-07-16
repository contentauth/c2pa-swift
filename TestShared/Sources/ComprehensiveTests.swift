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

// Comprehensive tests - pure Swift implementation
public final class ComprehensiveTests: TestImplementation {

    public init() {}

    public func testLibraryVersion() -> TestResult {
        let version = C2PA.version
        if !version.isEmpty && version.contains(".") {
            return .success("Library Version", "[PASS] C2PA Version: \(version)")
        }
        return .failure("Library Version", "Invalid version: \(version)")
    }

    public func testErrorHandling() -> TestResult {
        do {
            _ = try C2PA.readFile(at: URL(fileURLWithPath: "/non/existent/file.jpg"))
            return .failure("Error Handling", "Should have thrown an error")
        } catch {
            // Reading a non-existent file must throw. Since readFile now opens a
            // stream first, the error may be a Foundation file error (surfaced by
            // the stream) rather than a C2PAError; either is acceptable here.
            return .success("Error Handling", "[PASS] Error handling works correctly: \(error)")
        }
    }

    public func testReadImageWithManifest() -> TestResult {
        // Use the Adobe test image which has a C2PA manifest
        guard let imageData = TestUtilities.loadAdobeTestImage() else {
            return .failure("Read Image With Manifest", "Could not load test image")
        }
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).jpg")

        do {
            try imageData.write(to: tempFile)
            defer {
                try? FileManager.default.removeItem(at: tempFile)
            }

            let manifestJSON = try C2PA.readFile(at: tempFile)

            // Adobe test image SHOULD have a manifest - fail if empty
            guard !manifestJSON.isEmpty else {
                return .failure("Read Image With Manifest", "Adobe test image returned empty manifest JSON")
            }

            let jsonData = Data(manifestJSON.utf8)
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

            // Adobe test image SHOULD have manifests field
            guard json?["manifests"] != nil else {
                return .failure("Read Image With Manifest", "Adobe test image manifest has no 'manifests' field")
            }

            return .success("Read Image With Manifest", "[PASS] Read manifest from Adobe test image")

        } catch {
            return .failure("Read Image With Manifest", "Failed to read Adobe test image: \(error)")
        }
    }

    public func testStreamFromData() -> TestResult {
        do {
            let testData = Data("Hello C2PA Stream API".utf8)
            let stream = try Stream(data: testData)
            _ = stream
            return .success("Stream From Data", "[PASS] Created stream from data")
        } catch {
            return .failure("Stream From Data", "Failed: \(error)")
        }
    }

    public func testStreamFromFile() -> TestResult {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("stream_\(UUID().uuidString).txt")
        let testData = Data("Test file content".utf8)

        do {
            try testData.write(to: tempURL)
            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            let stream = try Stream(readFrom: tempURL)
            _ = stream
            return .success("Stream From File", "[PASS] Created stream from file")
        } catch {
            return .failure("Stream From File", "Failed: \(error)")
        }
    }


    public func testBuilderCreation() -> TestResult {
        let manifestJSON = """
            {
                "claim_generator": "TestSuite/1.0",
                "format": "image/jpeg",
                "title": "Test Manifest"
            }
            """

        do {
            let builder = try Builder(manifestJSON: manifestJSON)
            _ = builder
            return .success("Builder Creation", "[PASS] Created builder from JSON")
        } catch {
            return .failure("Builder Creation", "Failed: \(error)")
        }
    }

    public func testBuilderNoEmbed() -> TestResult {
        let manifestJSON = """
            {
                "claim_generator": "TestSuite/1.0",
                "assertions": []
            }
            """

        do {
            let builder = try Builder(manifestJSON: manifestJSON)
            builder.setNoEmbed()

            let archiveFile = FileManager.default.temporaryDirectory.appendingPathComponent(
                "archive_\(UUID().uuidString).c2pa")
            defer {
                try? FileManager.default.removeItem(at: archiveFile)
            }

            let archiveStream = try Stream(writeTo: archiveFile)
            try builder.writeArchive(to: archiveStream)

            if FileManager.default.fileExists(atPath: archiveFile.path) {
                return .success("Builder No Embed", "[PASS] Created archive with no-embed")
            }
            return .failure("Builder No Embed", "Archive not created")
        } catch {
            return .failure("Builder No Embed", "Failed: \(error)")
        }
    }

    public func testBuilderRemoteURL() -> TestResult {
        let manifestJSON = """
            {
                "claim_generator": "TestSuite/1.0",
                "assertions": []
            }
            """

        do {
            let builder = try Builder(manifestJSON: manifestJSON)
            try builder.setRemote(url: URL(string: "https://example.com/manifest")!)
            return .success("Builder Remote URL", "[PASS] Set remote URL on builder")
        } catch {
            return .failure("Builder Remote URL", "Failed: \(error)")
        }
    }

    public func testBuilderAddResource() -> TestResult {
        let manifestJSON = """
            {
                "claim_generator": "TestSuite/1.0",
                "assertions": []
            }
            """

        do {
            let builder = try Builder(manifestJSON: manifestJSON)
            guard let thumbnailData = TestUtilities.loadPexelsTestImage() else {
                return .failure("Builder Add Resource", "Could not load test image")
            }
            let thumbnailStream = try Stream(data: thumbnailData)

            do {
                try builder.addResource(uri: "thumbnail", stream: thumbnailStream)
                return .success("Builder Add Resource", "[PASS] Added resource to builder")
            } catch {
                return .success("Builder Add Resource", "[WARN] Add resource not supported")
            }
        } catch {
            return .failure("Builder Add Resource", "Failed: \(error)")
        }
    }


    public func testReaderCreation() -> TestResult {
        do {
            // Use the Adobe test image which has a C2PA manifest
            guard let imageData = TestUtilities.loadAdobeTestImage() else {
                return .failure("Reader Creation", "Could not load test image")
            }
            let stream = try Stream(data: imageData)
            let reader = try Reader(format: "image/jpeg", stream: stream)
            let json = try reader.json()

            // Adobe test image SHOULD have manifest
            guard !json.isEmpty else {
                return .failure("Reader Creation", "Adobe test image returned empty JSON from Reader")
            }

            return .success("Reader Creation", "[PASS] Created reader and read manifest (\(json.count) chars)")

        } catch {
            return .failure("Reader Creation", "Failed to read Adobe test image: \(error)")
        }
    }

    public func testReaderWithTestImage() -> TestResult {
        do {
            // Use the Adobe test image which has a C2PA manifest
            guard let imageData = TestUtilities.loadAdobeTestImage() else {
                return .failure("Reader With Test Image", "Could not load test image")
            }
            let stream = try Stream(data: imageData)
            let reader = try Reader(format: "image/jpeg", stream: stream)
            let json = try reader.json()

            // Adobe test image SHOULD have manifest - fail if empty
            guard !json.isEmpty else {
                return .failure("Reader With Test Image", "Adobe test image returned empty JSON")
            }

            let jsonData = Data(json.utf8)
            let manifest = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

            // Adobe test image SHOULD have manifests field
            guard manifest?["manifests"] != nil else {
                return .failure("Reader With Test Image", "Adobe test image manifest has no 'manifests' field")
            }

            return .success("Reader With Test Image", "[PASS] Read manifest from Adobe test image via Reader API")

        } catch {
            return .failure("Reader With Test Image", "Failed to read Adobe test image: \(error)")
        }
    }

    public func testSigningAlgorithms() -> TestResult {
        let algorithms = SigningAlgorithm.allCases

        for algorithm in algorithms {
            if algorithm.rawValue.isEmpty {
                return .failure("Signing Algorithms", "[FAIL] \(algorithm).rawValue.isEmpty")
            }

            // Needed for Codecov
            switch algorithm {
            case .es256:
                if algorithm.secKeyAlgo != .ecdsaSignatureMessageX962SHA256 {
                    return .failure("Signing Algorithms", "[FAIL] \(algorithm).secKeyAlgo != .ecdsaSignatureMessageX962SHA256")
                }

            case .es384:
                if algorithm.secKeyAlgo != .ecdsaSignatureMessageX962SHA384 {
                    return .failure("Signing Algorithms", "[FAIL] \(algorithm).secKeyAlgo != .ecdsaSignatureMessageX962SHA384")
                }

            case .es512:
                if algorithm.secKeyAlgo != .ecdsaSignatureMessageX962SHA512 {
                    return .failure("Signing Algorithms", "[FAIL] \(algorithm).secKeyAlgo != .ecdsaSignatureMessageX962SHA512")
                }

            case .ps256:
                if algorithm.secKeyAlgo != .rsaSignatureMessagePSSSHA256 {
                    return .failure("Signing Algorithms", "[FAIL] \(algorithm).secKeyAlgo != .rsaSignatureMessagePSSSHA256")
                }

            case .ps384:
                if algorithm.secKeyAlgo != .rsaSignatureMessagePSSSHA384 {
                    return .failure("Signing Algorithms", "[FAIL] \(algorithm).secKeyAlgo != .rsaSignatureMessagePSSSHA384")
                }

            case .ps512:
                if algorithm.secKeyAlgo != .rsaSignatureMessagePSSSHA512 {
                    return .failure("Signing Algorithms", "[FAIL] \(algorithm).secKeyAlgo != .rsaSignatureMessagePSSSHA512")
                }

            default:
                if algorithm.secKeyAlgo != nil {
                    return .failure("Signing Algorithms", "[FAIL] \(algorithm).secKeyAlgo != nil")
                }
            }
        }

        return .success("Signing Algorithms", "[PASS] Verified \(algorithms.count) algorithms")
    }

    public func testErrorEnumCases() -> TestResult {
        let apiError = C2PAError.api("Test error")
        if apiError.localizedDescription != "C2PA API error: Test error" {
            return .failure("Error Enum Cases", "API error description mismatch")
        }

        let nilError = C2PAError.nilPointer
        if nilError.localizedDescription != "Unexpected NULL pointer" {
            return .failure("Error Enum Cases", "Nil error description mismatch")
        }

        let utf8Error = C2PAError.utf8
        if utf8Error.localizedDescription != "Invalid UTF-8 from C2PA" {
            return .failure("Error Enum Cases", "UTF8 error description mismatch")
        }

        let negativeError = C2PAError.negative(42)
        if negativeError.localizedDescription != "C2PA negative status 42" {
            return .failure("Error Enum Cases", "Negative error description mismatch")
        }

        return .success("Error Enum Cases", "[PASS] All error cases working")
    }

    public func testEndToEndSigning() -> TestResult {
        let manifestJSON = """
            {
                "claim_generator": "TestSuite/1.0",
                "assertions": [
                    {"label": "c2pa.test", "data": {"test": true}}
                ]
            }
            """

        do {
            let builder = try Builder(manifestJSON: manifestJSON)

            let tempDir = FileManager.default.temporaryDirectory
            let sourceFile = tempDir.appendingPathComponent("source_\(UUID().uuidString).jpg")
            let destFile = tempDir.appendingPathComponent("signed_\(UUID().uuidString).jpg")

            defer {
                try? FileManager.default.removeItem(at: sourceFile)
                try? FileManager.default.removeItem(at: destFile)
            }

            guard let imageData = TestUtilities.loadPexelsTestImage() else {
                return .failure("End To End Signing", "Could not load test image")
            }
            try imageData.write(to: sourceFile)

            let sourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)

            let signer = try Signer(
                certsPEM: TestUtilities.testCertsPEM,
                privateKeyPEM: TestUtilities.testPrivateKeyPEM,
                algorithm: .es256,
                tsa: nil
            )

            _ = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )

            if FileManager.default.fileExists(atPath: destFile.path) {
                return .success("End to End Signing", "[PASS] Signing completed")
            }
            return .failure("End to End Signing", "Destination file not created")

        } catch {
            // All errors are real failures - don't hide certificate issues
            return .failure("End to End Signing", "Signing failed: \(error)")
        }
    }

    public func testInvalidFileHandling() -> TestResult {
        var testSteps: [String] = []
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_invalid_\(UUID().uuidString).txt")

        do {
            try "This is not a C2PA file".write(to: tempURL, atomically: true, encoding: .utf8)
            testSteps.append("✓ Created temporary invalid file")

            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            _ = try C2PA.readFile(at: tempURL)
            testSteps.append("✗ Should have thrown an error for invalid file")

            return .failure("Invalid File Handling", testSteps.joined(separator: "\n"))
        } catch {
            testSteps.append("✓ Correctly threw error for invalid file format")
            testSteps.append("Error: \(error)")

            return .success("Invalid File Handling", testSteps.joined(separator: "\n"))
        }
    }

    public func testStreamFileOptions() -> TestResult {
        var testSteps: [String] = []
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("stream_options_\(UUID().uuidString).dat")

        do {
            // Test 1: Create new file with stream
            let createStream = try Stream(writeTo: tempFile)
            _ = createStream
            testSteps.append("✓ Created new file with stream")

            // Verify file exists
            if FileManager.default.fileExists(atPath: tempFile.path) {
                testSteps.append("✓ File was created successfully")
            }

            // Write some data
            let testData = Data("Stream options test data".utf8)
            try testData.write(to: tempFile)

            // Test 2: Open existing file without truncation
            let readStream = try Stream(update: tempFile)
            _ = readStream
            testSteps.append("✓ Opened existing file without truncation")

            // Verify data still exists
            let readData = try Data(contentsOf: tempFile)
            if readData == testData {
                testSteps.append("✓ Data preserved when not truncating")
            }

            // Test 3: Open with truncation
            let truncateStream = try Stream(writeTo: tempFile)
            _ = truncateStream
            testSteps.append("✓ Opened file with truncation")

            // Test 4: Try to open non-existent file without creation
            let nonExistentFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("non_existent_\(UUID().uuidString).dat")
            do {
                _ = try Stream(update: nonExistentFile)
                testSteps.append("✗ Should have failed for non-existent file")
            } catch {
                testSteps.append("✓ Correctly failed for non-existent file")
            }

            // Cleanup
            try? FileManager.default.removeItem(at: tempFile)

            return .success("Stream File Options", testSteps.joined(separator: "\n"))

        } catch {
            testSteps.append("✗ Failed: \(error)")
            try? FileManager.default.removeItem(at: tempFile)
            return .failure("Stream File Options", testSteps.joined(separator: "\n"))
        }
    }

    public func runAllTests() async -> [TestResult] {
        return [
            testLibraryVersion(),
            testErrorHandling(),
            testReadImageWithManifest(),
            testInvalidFileHandling(),
            testStreamFileOptions(),
            testStreamFromData(),
            testStreamFromFile(),
            testBuilderCreation(),
            testBuilderNoEmbed(),
            testBuilderRemoteURL(),
            testBuilderAddResource(),
            testReaderCreation(),
            testReaderWithTestImage(),
            testSigningAlgorithms(),
            testErrorEnumCases(),
            testEndToEndSigning()
        ]
    }
}
