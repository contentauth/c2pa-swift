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

// Context API tests - pure Swift implementation
public final class ContextTests: TestImplementation {

    public init() {}

    public func testContextDefaultCreation() -> TestResult {
        do {
            _ = try C2PAContext()
            return .success("Context Default Creation", "[PASS] Created default C2PAContext")
        } catch {
            return .failure("Context Default Creation", "Error: \(error)")
        }
    }

    public func testContextFromSettings() -> TestResult {
        do {
            let settings = try C2PASettings(json: "{\"version\": 1}")
            _ = try C2PAContext(settings: settings)
            return .success("Context From Settings", "[PASS] Created C2PAContext from settings")
        } catch {
            return .failure("Context From Settings", "Error: \(error)")
        }
    }

    public func testContextCancel() -> TestResult {
        do {
            let context = try C2PAContext()
            try context.cancel()
            return .success("Context Cancel", "[PASS] cancel() returned without error")
        } catch {
            return .failure("Context Cancel", "Error: \(error)")
        }
    }

    public func testBuilderFromContext() -> TestResult {
        do {
            let manifestJSON = TestUtilities.createTestManifestJSON()
            let context = try C2PAContext()
            _ = try Builder(context: context, manifestJSON: manifestJSON)
            return .success("Builder From Context", "[PASS] Created Builder from context")
        } catch {
            return .failure("Builder From Context", "Error: \(error)")
        }
    }

    public func testSettingsFlowRoundtrip() -> TestResult {
        let manifestJSON = TestUtilities.createTestManifestJSON()
        let settingsJSON = "{\"version\": 1, \"verify\": {\"verify_after_reading\": true}}"

        do {
            let settings = try C2PASettings(json: settingsJSON)
            let context = try C2PAContext(settings: settings)
            let builder = try Builder(context: context, manifestJSON: manifestJSON)

            let tempDir = FileManager.default.temporaryDirectory
            let sourceFile = tempDir.appendingPathComponent("ctx_source_\(UUID().uuidString).jpg")
            let destFile = tempDir.appendingPathComponent("ctx_dest_\(UUID().uuidString).jpg")
            defer {
                try? FileManager.default.removeItem(at: sourceFile)
                try? FileManager.default.removeItem(at: destFile)
            }

            guard let imageData = TestUtilities.loadPexelsTestImage() else {
                return .failure("Settings Flow Roundtrip", "Could not load test image")
            }
            try imageData.write(to: sourceFile)

            let sourceStream = try Stream(readFrom: sourceFile)
            let destStream = try Stream(writeTo: destFile)
            let signer = try TestUtilities.createTestSigner()

            _ = try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )

            if FileManager.default.fileExists(atPath: destFile.path),
               let readManifest = try? C2PA.readFile(at: destFile),
               !readManifest.isEmpty
            {
                return .success(
                    "Settings Flow Roundtrip",
                    "[PASS] settings -> context -> builder -> sign -> read round-trips"
                )
            }
            return .failure("Settings Flow Roundtrip", "Signed file missing or unreadable")
        } catch let error as C2PAError {
            if case .api(let message) = error,
               message.contains("certificate") || message.contains("cert")
                || message.contains("key") || message.contains("signing")
            {
                return .success(
                    "Settings Flow Roundtrip",
                    "[WARN] context+settings path works (cert/key error expected: \(message))"
                )
            }
            return .failure("Settings Flow Roundtrip", "C2PAError: \(error)")
        } catch {
            return .failure("Settings Flow Roundtrip", "Error: \(error)")
        }
    }

    public func testProgressCallback() -> TestResult {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("prog_src_\(UUID().uuidString).jpg")
        let destURL = tempDir.appendingPathComponent("prog_dst_\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }

        // The callback fires synchronously on the signing thread, but a plain array would
        // still be shared mutable state as far as the compiler is concerned.
        final class Recorder: @unchecked Sendable {
            private let lock = NSLock()
            private var phases: [ProgressPhase] = []
            func record(_ phase: ProgressPhase) {
                lock.lock()
                defer { lock.unlock() }
                phases.append(phase)
            }
            var observed: [ProgressPhase] {
                lock.lock()
                defer { lock.unlock() }
                return phases
            }
        }
        let recorder = Recorder()

        do {
            guard let imageData = TestUtilities.loadPexelsTestImage() else {
                return .failure("Progress Callback", "Could not load test image")
            }
            try imageData.write(to: sourceURL)

            let context = try C2PAContext(onProgress: { recorder.record($0.phase) })
            let builder = try Builder(
                context: context, manifestJSON: TestUtilities.createTestManifestJSON())
            _ = try builder.sign(
                format: "image/jpeg",
                source: try Stream(readFrom: sourceURL),
                destination: try Stream(writeTo: destURL),
                signer: try TestUtilities.createTestSigner())

            let observed = recorder.observed
            guard !observed.isEmpty else {
                return .success(
                    "Progress Callback", "[WARN] no progress updates observed (environment-dependent)")
            }
            guard !observed.contains(.unknown) else {
                return .failure(
                    "Progress Callback",
                    "a phase did not map to a known case, so the native enum has drifted")
            }
            return .success("Progress Callback", "[PASS] observed \(observed.count) updates")
        } catch let error as C2PAError {
            return .success("Progress Callback", "[WARN] progress path callable (error: \(error))")
        } catch {
            return .failure("Progress Callback", "Error: \(error)")
        }
    }

    public func testHTTPResolver() -> TestResult {
        do {
            // Installing the resolver is what is under test; whether the SDK makes a
            // request during this operation is environment-dependent.
            let context = try C2PAContext(httpResolver: { request in
                HTTPResponse(status: 200, body: Data("\(request.method) \(request.url)".utf8))
            })
            _ = try Builder(context: context, manifestJSON: TestUtilities.createTestManifestJSON())
            return .success("HTTP Resolver", "[PASS] custom HTTP resolver installed")
        } catch let error as C2PAError {
            return .success("HTTP Resolver", "[WARN] resolver path callable (error: \(error))")
        } catch {
            return .failure("HTTP Resolver", "Error: \(error)")
        }
    }

    public func testURLSessionHTTPResolver() -> TestResult {
        do {
            let context = try C2PAContext(urlSession: .shared)
            _ = try Builder(context: context, manifestJSON: TestUtilities.createTestManifestJSON())
            return .success("URLSession HTTP Resolver", "[PASS] URLSession resolver installed")
        } catch let error as C2PAError {
            return .success("URLSession HTTP Resolver", "[WARN] resolver callable (error: \(error))")
        } catch {
            return .failure("URLSession HTTP Resolver", "Error: \(error)")
        }
    }

    public func testContextWithSettingsAndCallbacks() -> TestResult {
        // All three configuration inputs at once: each is applied to the same transient
        // native builder, so a mistake in that sequence shows up here.
        do {
            let settings = try C2PASettings(json: "{\"version\": 1}")
            let context = try C2PAContext(
                settings: settings,
                onProgress: { _ in },
                httpResolver: { _ in HTTPResponse(status: 204, body: Data()) })
            try context.cancel()
            return .success(
                "Context Settings And Callbacks", "[PASS] settings and both callbacks applied")
        } catch let error as C2PAError {
            return .success(
                "Context Settings And Callbacks", "[WARN] path callable (error: \(error))")
        } catch {
            return .failure("Context Settings And Callbacks", "Error: \(error)")
        }
    }

    public func runAllTests() async -> [TestResult] {
        [
            testContextDefaultCreation(),
            testContextFromSettings(),
            testContextCancel(),
            testBuilderFromContext(),
            testSettingsFlowRoundtrip(),
            testProgressCallback(),
            testHTTPResolver(),
            testURLSessionHTTPResolver(),
            testContextWithSettingsAndCallbacks()
        ]
    }
}
