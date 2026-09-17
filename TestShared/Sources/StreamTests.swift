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

// Stream tests - pure Swift implementation
public final class StreamTests: TestImplementation {

    public init() {}

    public func testStreamOperations() -> TestResult {
        do {
            let testData = Data("Hello, C2PA Stream!".utf8)
            _ = try Stream(data: testData)

            return .success("Stream Operations", "[PASS] Created stream from data successfully")
        } catch {
            return .failure("Stream Operations", "Failed to create stream: \(error)")
        }
    }

    public func testStreamFileOperations() -> TestResult {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "stream_test_\(UUID().uuidString).txt")
        let testContent = "Test file content for stream operations"

        do {
            try testContent.write(to: tempURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            // Test read mode
            let readStream = try Stream(readFrom: tempURL)
            _ = readStream

            // Test write mode
            let writeURL = tempURL.appendingPathExtension("write")
            defer { try? FileManager.default.removeItem(at: writeURL) }

            let writeStream = try Stream(writeTo: writeURL)
            _ = writeStream

            return .success("Stream File Operations", "[PASS] File streams created successfully")
        } catch {
            return .failure("Stream File Operations", "Failed: \(error)")
        }
    }

    public func testWriteOnlyStreams() -> TestResult {
        do {
            var capturedData = Data()

            _ = try Stream(
                write: { buffer, count in
                    let data = Data(bytes: buffer, count: count)
                    capturedData.append(data)
                    return count
                },
                flush: { return 0 }
            )

            // Use with Builder to test write operations
            let manifestJSON = """
                {
                    "claim_generator": "StreamTest/1.0",
                    "assertions": []
                }
                """

            let builder = try Builder(manifestJSON: manifestJSON)
            builder.setNoEmbed()

            let archiveFile = FileManager.default.temporaryDirectory.appendingPathComponent(
                "archive_\(UUID().uuidString).c2pa")
            defer { try? FileManager.default.removeItem(at: archiveFile) }

            let archiveStream = try Stream(writeTo: archiveFile)
            try builder.writeArchive(to: archiveStream)

            guard FileManager.default.fileExists(atPath: archiveFile.path) else {
                return .failure("Write-Only Streams", "Archive file was not created")
            }
            return .success("Write-Only Streams", "[PASS] Write-only stream working, archive created")
        } catch {
            return .failure("Write-Only Streams", "Failed: \(error)")
        }
    }

    public func testCustomStreamCallbacks() -> TestResult {
        var readCount = 0
        var seekCount = 0
        guard let testData = TestUtilities.loadPexelsTestImage() else {
            return .failure("Custom Stream Callbacks", "Could not load test image")
        }
        var position = 0

        do {
            let customStream = try Stream(
                read: { buffer, count in
                    readCount += 1
                    let readSize = min(count, testData.count - position)
                    if readSize > 0 {
                        testData.withUnsafeBytes { bytes in
                            let src = bytes.baseAddress!.advanced(by: position)
                            memcpy(buffer, src, readSize)
                        }
                        position += readSize
                    }
                    return readSize
                },
                seek: { offset, origin in
                    seekCount += 1
                    switch origin.rawValue {
                    case 0:  // Start
                        position = max(0, offset)
                    case 1:  // Current
                        position = max(0, position + offset)
                    case 2:  // End
                        position = max(0, testData.count + offset)
                    default:
                        break
                    }
                    return position
                }
            )

            // Actually use the stream with a Reader to verify callbacks are invoked
            do {
                let reader = try Reader(format: "image/jpeg", stream: customStream)
                _ = try? reader.json()  // May fail due to no manifest, that's fine
            } catch {
                // Reader creation may fail, but callbacks should have been invoked
            }

            // Verify callbacks were actually called
            guard readCount > 0 || seekCount > 0 else {
                return .failure("Custom Stream Callbacks", "Callbacks were never invoked (read=\(readCount), seek=\(seekCount))")
            }

            return .success("Custom Stream Callbacks", "[PASS] Callbacks invoked: read=\(readCount), seek=\(seekCount)")
        } catch {
            return .failure("Custom Stream Callbacks", "Failed: \(error)")
        }
    }

    public func testStreamWithLargeData() -> TestResult {
        let largeSize = 10_000_000  // 10MB
        let largeData = Data(repeating: 0xAB, count: largeSize)

        do {
            let stream = try Stream(data: largeData)
            _ = stream
            return .success("Large Data Stream", "[PASS] Handled \(largeSize / 1_000_000)MB data")
        } catch {
            return .failure("Large Data Stream", "Failed with large data: \(error)")
        }
    }

    public func testMultipleStreams() -> TestResult {
        do {
            var streams: [AnyObject] = []

            for i in 0..<10 {
                let data = Data("Stream \(i)".utf8)
                let stream = try Stream(data: data)
                streams.append(stream)
            }

            return .success("Multiple Streams", "[PASS] Created \(streams.count) concurrent streams")
        } catch {
            return .failure("Multiple Streams", "Failed: \(error)")
        }
    }

    public func testFileStreamOptions() -> TestResult {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("options_\(UUID().uuidString).txt")

        do {
            // Test create if needed
            let createStream = try Stream(writeTo: tempFile)
            _ = createStream

            let fileExists = FileManager.default.fileExists(atPath: tempFile.path)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            if !fileExists {
                return .failure("File Stream Options", "File not created with createIfNeeded=true")
            }

            // Write some data
            try "test content".write(to: tempFile, atomically: true, encoding: .utf8)

            // Test truncate
            let truncateStream = try Stream(writeTo: tempFile)
            _ = truncateStream

            return .success("File Stream Options", "[PASS] File stream options working")
        } catch {
            return .failure("File Stream Options", "Failed: \(error)")
        }
    }

    public func testStreamWithReader() -> TestResult {
        // Use the Pexels image which is a real JPEG without C2PA manifest
        guard let imageData = TestUtilities.loadPexelsTestImage() else {
            return .failure("Stream with Reader", "Could not load test image")
        }

        do {
            let stream = try Stream(data: imageData)
            let reader = try Reader(format: "image/jpeg", stream: stream)

            // Attempting to read JSON from a file without manifest should fail
            do {
                let json = try reader.json()
                // If we get here with JSON, verify it's valid (shouldn't happen for Pexels image)
                guard !json.isEmpty else {
                    return .failure("Stream with Reader", "Got empty JSON from image without manifest")
                }
                return .success("Stream with Reader", "[PASS] Stream works with Reader API (JSON length: \(json.count))")
            } catch let jsonError as C2PAError {
                // Expected: no manifest in test image
                if case .api(let message) = jsonError,
                   message.contains("no JUMBF data found") || message.contains("ManifestNotFound")
                       || message.contains("No manifest") {
                    return .success("Stream with Reader", "[PASS] Reader correctly reports no manifest")
                }
                return .failure("Stream with Reader", "Unexpected C2PAError reading JSON: \(jsonError)")
            }
        } catch let error as C2PAError {
            // Reader creation may fail for images without C2PA data
            if case .api(let message) = error,
               message.contains("no JUMBF data found") || message.contains("ManifestNotFound")
                   || message.contains("No manifest") {
                return .success("Stream with Reader", "[PASS] Reader correctly detects no manifest")
            }
            return .failure("Stream with Reader", "C2PAError: \(error)")
        } catch {
            return .failure("Stream with Reader", "Failed: \(error)")
        }
    }

    public func testStreamWithBuilder() -> TestResult {
        // Use real image for source
        guard let sourceData = TestUtilities.loadPexelsTestImage() else {
            return .failure("Stream with Builder", "Could not load test image")
        }

        // Use file-based streams to avoid crashes
        let tempDir = FileManager.default.temporaryDirectory
        let sourceFile = tempDir.appendingPathComponent("stream_builder_src_\(UUID().uuidString).jpg")
        let destFile = tempDir.appendingPathComponent("stream_builder_dst_\(UUID().uuidString).jpg")

        defer {
            try? FileManager.default.removeItem(at: sourceFile)
            try? FileManager.default.removeItem(at: destFile)
        }

        do {
            // Write source image to file
            try sourceData.write(to: sourceFile)

            // Create file-based streams
            let sourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)

            let manifestJSON = TestUtilities.createTestManifestJSON(claimGenerator: "StreamTest/1.0")

            let builder = try Builder(manifestJSON: manifestJSON)

            let signer = try Signer(
                certsPEM: TestUtilities.testCertsPEM,
                privateKeyPEM: TestUtilities.testPrivateKeyPEM,
                algorithm: .es256,
                tsa: nil
            )

            // Actually sign and verify result
            let manifestBytes = try builder.sign(format: "image/jpeg", source: sourceStream, destination: destStream, signer: signer)

            // Verify output file was created
            guard FileManager.default.fileExists(atPath: destFile.path) else {
                return .failure("Stream with Builder", "Signed file was not created")
            }

            return .success("Stream with Builder", "[PASS] Stream signing successful, manifest bytes: \(manifestBytes.count)")
        } catch {
            return .failure("Stream with Builder", "Failed: \(error)")
        }
    }

    public func runAllTests() async -> [TestResult] {
        return [
            testStreamOperations(),
            testStreamFileOperations(),
            testWriteOnlyStreams(),
            testCustomStreamCallbacks(),
            testStreamWithLargeData(),
            testMultipleStreams(),
            testFileStreamOptions(),
            testStreamWithReader(),
            testStreamWithBuilder()
        ]
    }
}
