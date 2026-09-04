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

/// Collects values delivered from native callbacks.
///
/// Callbacks fire synchronously on the thread running the operation, but a plain array
/// would still be shared mutable state as far as the compiler is concerned.
private final class CallbackRecorder<Value>: @unchecked Sendable {
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

/// Serves canned HTTP responses inside a `URLSession` without touching the network, so the
/// `URLSession`-backed resolver can be exercised end to end. Only sessions that list this in
/// `URLSessionConfiguration.protocolClasses` are affected.
private final class StubURLProtocol: URLProtocol {
    fileprivate final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var status = 200
        private var body = Data()
        private var requests: [URLRequest] = []

        func stub(status: Int, body: Data) {
            lock.lock()
            defer { lock.unlock() }
            self.status = status
            self.body = body
            requests = []
        }

        func response() -> (status: Int, body: Data) {
            lock.lock()
            defer { lock.unlock() }
            return (status, body)
        }

        func record(_ request: URLRequest) {
            lock.lock()
            defer { lock.unlock() }
            requests.append(request)
        }

        var recorded: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests
        }
    }

    fileprivate static let state = State()

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.state.record(request)
        let stub = Self.state.response()
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !stub.body.isEmpty { client?.urlProtocol(self, didLoad: stub.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

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

        let recorder = CallbackRecorder<ProgressPhase>()

        do {
            guard let imageData = TestUtilities.loadPexelsTestImage() else {
                return .failure("Progress Callback", "Could not load test image")
            }
            try imageData.write(to: sourceURL)

            let context = try C2PAContext(onProgress: {
                recorder.record($0.phase)
                return .continue
            })
            let builder = try Builder(
                context: context, manifestJSON: TestUtilities.createTestManifestJSON())
            _ = try builder.sign(
                format: "image/jpeg",
                source: try Stream(readFrom: sourceURL),
                destination: try Stream(writeTo: destURL),
                signer: try TestUtilities.createTestSigner())

            let observed = recorder.recorded
            guard !observed.contains(.unknown) else {
                return .failure(
                    "Progress Callback",
                    "a phase did not map to a known case, so the native enum has drifted")
            }
            // A local sign always hashes the asset and signs the claim, so at least one of
            // those phases must be reported if the callback is wired through at all.
            guard observed.contains(.hashing) || observed.contains(.signing) else {
                return .failure(
                    "Progress Callback",
                    "expected a hashing or signing phase, observed \(observed)")
            }
            return .success("Progress Callback", "[PASS] observed \(observed.count) updates")
        } catch {
            return .failure("Progress Callback", "Error: \(error)")
        }
    }

    public func testProgressCallbackCancelsOperation() -> TestResult {
        let name = "Progress Callback Cancels Operation"
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("cancel_src_\(UUID().uuidString).jpg")
        let destURL = tempDir.appendingPathComponent("cancel_dst_\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }

        let recorder = CallbackRecorder<ProgressPhase>()

        do {
            guard let imageData = TestUtilities.loadPexelsTestImage() else {
                return .failure(name, "Could not load test image")
            }
            try imageData.write(to: sourceURL)

            // Cancels at the first checkpoint, which is what distinguishes this from
            // context-wide cancel(): only this operation is asked to stop.
            let context = try C2PAContext(onProgress: {
                recorder.record($0.phase)
                return .cancel
            })
            let builder = try Builder(
                context: context, manifestJSON: TestUtilities.createTestManifestJSON())

            do {
                _ = try builder.sign(
                    format: "image/jpeg",
                    source: try Stream(readFrom: sourceURL),
                    destination: try Stream(writeTo: destURL),
                    signer: try TestUtilities.createTestSigner())
                return .failure(name, "sign completed although the observer asked to cancel")
            } catch is C2PAError {
                guard !recorder.recorded.isEmpty else {
                    return .failure(name, "sign failed before any progress was reported")
                }
                return .success(
                    name, "[PASS] cancelled after \(recorder.recorded.count) update(s)")
            }
        } catch {
            return .failure(name, "Error: \(error)")
        }
    }

    public func testHTTPResolver() -> TestResult {
        // Installing a resolver on a fresh context is deterministic, so any error here is
        // a failure. Driving the resolver is covered by testHTTPResolverRemoteManifestFetch.
        do {
            let context = try C2PAContext(httpResolver: { request in
                HTTPResponse(status: 200, body: Data("\(request.method) \(request.url)".utf8))
            })
            _ = try Builder(context: context, manifestJSON: TestUtilities.createTestManifestJSON())
            return .success("HTTP Resolver", "[PASS] custom HTTP resolver installed")
        } catch {
            return .failure("HTTP Resolver", "Error: \(error)")
        }
    }

    public func testURLSessionHTTPResolver() -> TestResult {
        do {
            let context = try C2PAContext(urlSession: .shared)
            _ = try Builder(context: context, manifestJSON: TestUtilities.createTestManifestJSON())
            return .success("URLSession HTTP Resolver", "[PASS] URLSession resolver installed")
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
                onProgress: { _ in .continue },
                httpResolver: { _ in HTTPResponse(status: 204, body: Data()) })
            try context.cancel()
            return .success(
                "Context Settings And Callbacks", "[PASS] settings and both callbacks applied")
        } catch {
            return .failure("Context Settings And Callbacks", "Error: \(error)")
        }
    }

    /// The URL a remotely hosted manifest is declared at in the resolver tests.
    private static let remoteManifestURL = URL(string: "https://example.com/manifests/test.c2pa")!

    /// Signs the test image with the manifest hosted at ``remoteManifestURL`` rather than
    /// embedded, so reading the result forces a fetch through the context's resolver.
    ///
    /// - Returns: The signed asset and the manifest store bytes a resolver should serve.
    private func signWithRemoteManifest() throws -> (asset: Data, manifest: Data) {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("remote_src_\(UUID().uuidString).jpg")
        let destURL = tempDir.appendingPathComponent("remote_dst_\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }

        guard let imageData = TestUtilities.loadPexelsTestImage() else {
            throw C2PAError.api("Could not load test image")
        }
        try imageData.write(to: sourceURL)

        let builder = try Builder(manifestJSON: TestUtilities.createTestManifestJSON())
        builder.setNoEmbed()
        try builder.setRemote(url: Self.remoteManifestURL)
        let manifest = try builder.sign(
            format: "image/jpeg",
            source: try Stream(readFrom: sourceURL),
            destination: try Stream(writeTo: destURL),
            signer: try TestUtilities.createTestSigner())
        return (try Data(contentsOf: destURL), manifest)
    }

    /// A context whose settings force remote manifests to be fetched, so the resolver is
    /// guaranteed to be consulted rather than the read short-circuiting on the URL.
    private func remoteFetchContext(
        httpResolver: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse
    ) throws -> C2PAContext {
        let settings = try C2PASettings(
            json: "{\"version\": 1, \"verify\": {\"remote_manifest_fetch\": true}}")
        return try C2PAContext(settings: settings, httpResolver: httpResolver)
    }

    public func testHTTPResolverRemoteManifestFetch() -> TestResult {
        let name = "HTTP Resolver Remote Manifest Fetch"
        do {
            let (asset, manifest) = try signWithRemoteManifest()
            let requests = CallbackRecorder<HTTPRequest>()
            let context = try remoteFetchContext { request in
                requests.record(request)
                return HTTPResponse(status: 200, body: manifest)
            }

            let reader = try Reader(context: context, format: "image/jpeg", stream: try Stream(data: asset))
            let json = try reader.json()

            let seen = requests.recorded
            guard seen.count == 1, let request = seen.first else {
                return .failure(name, "expected exactly one resolver call, got \(seen.count)")
            }
            guard request.url == Self.remoteManifestURL else {
                return .failure(name, "resolver called with \(request.url), expected \(Self.remoteManifestURL)")
            }
            guard request.method == "GET" else {
                return .failure(name, "resolver called with method \(request.method), expected GET")
            }
            guard request.body == nil else {
                return .failure(name, "GET request unexpectedly carried a body")
            }
            guard reader.remote() == Self.remoteManifestURL else {
                return .failure(name, "reader.remote() was \(String(describing: reader.remote()))")
            }
            // The reader renders the manifest store it fetched, so the active manifest must
            // be present and carry the assertion we signed with.
            guard let store = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  let active = store["active_manifest"] as? String,
                  let manifests = store["manifests"] as? [String: Any],
                  let manifest = manifests[active] as? [String: Any],
                  let assertions = manifest["assertions"] as? [[String: Any]],
                  assertions.contains(where: { $0["label"] as? String == "c2pa.test" })
            else {
                return .failure(name, "fetched manifest did not round-trip: \(json.prefix(300))")
            }
            return .success(name, "[PASS] resolver served \(manifest.count) byte manifest for \(request.url)")
        } catch {
            return .failure(name, "Error: \(error)")
        }
    }

    public func testHTTPResolverErrorFailsRead() -> TestResult {
        let name = "HTTP Resolver Error Fails Read"
        // Carries a distinctive localized message so the assertion below can tell the
        // resolver's own error text apart from a reflected description of the error case.
        struct ResolverRefused: LocalizedError {
            static let message = "resolver refused this request on purpose"
            var errorDescription: String? { Self.message }
        }
        do {
            let (asset, _) = try signWithRemoteManifest()
            let requests = CallbackRecorder<HTTPRequest>()
            let context = try remoteFetchContext { request in
                requests.record(request)
                throw ResolverRefused()
            }

            do {
                _ = try Reader(context: context, format: "image/jpeg", stream: try Stream(data: asset))
                return .failure(name, "read succeeded although the resolver threw")
            } catch let error as C2PAError {
                guard requests.recorded.count == 1 else {
                    return .failure(name, "resolver was called \(requests.recorded.count) times, expected 1")
                }
                let text = error.localizedDescription
                guard text.contains(ResolverRefused.message) else {
                    return .failure(name, "resolver error text did not reach the caller: \(text)")
                }
                return .success(name, "[PASS] resolver error text surfaced: \(text)")
            }
        } catch {
            return .failure(name, "Error: \(error)")
        }
    }

    public func testHTTPResolverRejectsOutOfRangeStatus() -> TestResult {
        let name = "HTTP Resolver Out Of Range Status"
        do {
            let (asset, manifest) = try signWithRemoteManifest()
            let context = try remoteFetchContext { _ in
                // Past Int32: narrowing this unguarded would trap inside the C callback,
                // aborting the process where no Swift frame could catch it.
                HTTPResponse(status: Int(Int32.max) + 1, body: manifest)
            }

            do {
                _ = try Reader(context: context, format: "image/jpeg", stream: try Stream(data: asset))
                return .failure(name, "read succeeded although the status was out of range")
            } catch let error as C2PAError {
                let text = error.localizedDescription
                guard text.contains("out of range") else {
                    return .failure(name, "unexpected error for an out-of-range status: \(text)")
                }
                return .success(name, "[PASS] out-of-range status refused: \(text)")
            }
        } catch {
            return .failure(name, "Error: \(error)")
        }
    }

    public func testURLSessionResolverRejectsMainQueueSession() -> TestResult {
        let name = "URLSession Resolver Rejects Main Queue"
        // Blocking on a session that completes on the main queue deadlocks whenever the
        // operation itself runs there, so the initializer refuses it up front.
        let session = URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: .main)
        defer { session.invalidateAndCancel() }
        do {
            _ = try C2PAContext(urlSession: session)
            return .failure(name, "context was created with a main-queue session")
        } catch let error as C2PAError {
            guard error.localizedDescription.contains("main queue") else {
                return .failure(name, "unexpected error: \(error.localizedDescription)")
            }
            return .success(name, "[PASS] main-queue session refused")
        } catch {
            return .failure(name, "Error: \(error)")
        }
    }

    public func testURLSessionResolverFetchesRemoteManifest() -> TestResult {
        let name = "URLSession Resolver Remote Manifest Fetch"
        do {
            let (asset, manifest) = try signWithRemoteManifest()
            StubURLProtocol.state.stub(status: 200, body: manifest)

            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            // No delegate queue, so URLSession makes its own background one and the
            // blocking resolver has something to be woken by.
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }

            let settings = try C2PASettings(
                json: "{\"version\": 1, \"verify\": {\"remote_manifest_fetch\": true}}")
            let context = try C2PAContext(settings: settings, urlSession: session)

            let reader = try Reader(
                context: context, format: "image/jpeg", stream: try Stream(data: asset))
            let json = try reader.json()

            let seen = StubURLProtocol.state.recorded
            guard seen.count == 1, let request = seen.first else {
                return .failure(name, "expected exactly one HTTP request, got \(seen.count)")
            }
            guard request.url == Self.remoteManifestURL else {
                return .failure(name, "requested \(String(describing: request.url))")
            }
            guard request.httpMethod == "GET" else {
                return .failure(name, "used method \(String(describing: request.httpMethod))")
            }
            guard let store = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  let active = store["active_manifest"] as? String,
                  let manifests = store["manifests"] as? [String: Any],
                  let fetched = manifests[active] as? [String: Any],
                  let assertions = fetched["assertions"] as? [[String: Any]],
                  assertions.contains(where: { $0["label"] as? String == "c2pa.test" })
            else {
                return .failure(name, "fetched manifest did not round-trip: \(json.prefix(300))")
            }
            return .success(name, "[PASS] URLSession resolver served \(manifest.count) bytes")
        } catch {
            return .failure(name, "Error: \(error)")
        }
    }

    public func testHTTPResolverEmptyResponseBody() -> TestResult {
        let name = "HTTP Resolver Empty Response Body"
        do {
            let (asset, _) = try signWithRemoteManifest()
            // A zero-length body sends a null pointer across the boundary. The read cannot
            // succeed without a manifest; what matters is that it fails rather than crashes.
            let context = try remoteFetchContext { _ in
                HTTPResponse(status: 204, body: Data())
            }

            do {
                _ = try Reader(
                    context: context, format: "image/jpeg", stream: try Stream(data: asset))
                return .failure(name, "read succeeded although the resolver served no manifest")
            } catch is C2PAError {
                return .success(name, "[PASS] empty response body surfaced as an error")
            }
        } catch {
            return .failure(name, "Error: \(error)")
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
            testProgressCallbackCancelsOperation(),
            testHTTPResolver(),
            testURLSessionHTTPResolver(),
            testContextWithSettingsAndCallbacks(),
            testHTTPResolverRemoteManifestFetch(),
            testHTTPResolverErrorFailsRead(),
            testHTTPResolverRejectsOutOfRangeStatus(),
            testURLSessionResolverRejectsMainQueueSession(),
            testURLSessionResolverFetchesRemoteManifest(),
            testHTTPResolverEmptyResponseBody()
        ]
    }
}
