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
//  WebServiceSignerTests.swift
//

import C2PA
import Foundation
import Testing

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Answers every request with one status and records the requests, so a
/// WebServiceSigner's outgoing request can be inspected without a server.
private final class RecordingURLProtocol: URLProtocol {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var status = 401
        private var requests: [URLRequest] = []

        func reset(status: Int) {
            lock.lock()
            defer { lock.unlock() }
            self.status = status
            requests = []
        }

        func record(_ request: URLRequest) -> Int {
            lock.lock()
            defer { lock.unlock() }
            requests.append(request)
            return status
        }

        var recorded: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests
        }
    }

    static let state = State()

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let status = Self.state.record(request)
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var sizes: [Int] = []

    func record(_ size: Int) {
        lock.lock()
        defer { lock.unlock() }
        sizes.append(size)
    }

    var recorded: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return sizes
    }
}

@Suite(.serialized) struct WebServiceSignerTests {

    // MARK: - Without a server

    /// The bearer token and custom headers reach the configuration request,
    /// and a non-200 answer surfaces as SignerError.httpError.
    @Test func webServiceSignerCreation() async throws {
        RecordingURLProtocol.state.reset(status: 401)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let signer = WebServiceSigner(
            configurationEndpoint: try #require(URL(string: "https://example.com/config")),
            bearerToken: "test-token",
            headers: ["X-Custom-Header": "test-value", "Authorization": "overridden"],
            urlSession: session)
        let error = await #expect(throws: SignerError.self) { try await signer.createSigner() }
        guard case .httpError(let status) = error else {
            Issue.record("expected .httpError, got \(String(describing: error))")
            return
        }
        #expect(status == 401)

        let request = try #require(RecordingURLProtocol.state.recorded.first)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token", "the bearer token wins over a custom Authorization header")
        #expect(request.value(forHTTPHeaderField: "X-Custom-Header") == "test-value")
    }

    @Test func createSignerInvalidURL() async throws {
        let signer = WebServiceSigner(configurationEndpoint: try #require(URL(string: "not-a-valid-url")))
        await #expect(throws: (any Error).self) { try await signer.createSigner() }
        await withKnownIssue("createSigner lets URLError escape instead of SignerError.invalidURL") {
            let error = await #expect(throws: SignerError.self) { try await signer.createSigner() }
            guard case .invalidURL = error else {
                Issue.record("expected .invalidURL, got \(String(describing: error))")
                return
            }
        }
    }

    @Test func createSignerConnectionFailure() async throws {
        let signer = WebServiceSigner(configurationEndpoint: try #require(URL(string: "http://localhost:59999/nonexistent")))
        await #expect(throws: (any Error).self) { try await signer.createSigner() }
        await withKnownIssue("createSigner lets URLError escape for an unreachable service instead of SignerError") {
            await #expect(throws: SignerError.self) { try await signer.createSigner() }
        }
    }

    /// An async signer that really signs with the test key produces a Valid manifest.
    @Test func asyncSignerCreation() throws {
        let key = try P256.Signing.PrivateKey(pemRepresentation: Fixtures.privateKeyPEM())
        let calls = CallRecorder()
        let signer = try Signer(algorithm: .es256, certificateChainPEM: Fixtures.certsPEM(), tsa: nil, asyncSigner: { data in
            calls.record(data.count)
            try await Task.sleep(nanoseconds: 1_000_000)
            return try key.signature(for: data).rawRepresentation
        })
        let store = try Fixtures.signAndRead(Builder(manifestJSON: Fixtures.createdManifestJSON(claimGenerator: "async_signer_test/1.0")), signer: signer)
        #expect(calls.recorded.count == 1)
        #expect(calls.recorded.first.map { $0 > 0 } == true)
        #expect(store.validationState == "Valid")
    }

    @Test func asyncSignerWithTSA() throws {
        let certs = try Fixtures.certsPEM()
        let without = try Signer(algorithm: .es256, certificateChainPEM: certs, tsa: nil, asyncSigner: { _ in Data(count: 64) })
        let with = try Signer(
            algorithm: .es256, certificateChainPEM: certs, tsa: URL(string: "http://timestamp.digicert.com"), asyncSigner: { _ in Data(count: 64) })
        #expect(try with.reserveSize() > 0)
        #expect(try with.reserveSize() >= without.reserveSize(), "a TSA must not shrink the reserve")
    }

    // MARK: - Against the signing server

    @Suite(.requiresSigningServer) struct WithServer {

        /// Configuration, remote signing and read-back through the signing server.
        @Test func webServiceSignerWithLocalServer() async throws {
            try await TestEnvironment.requireSigningServer()
            let signer = WebServiceSigner(
                configurationEndpoint: TestEnvironment.signingServerURL.appendingPathComponent("api/v1/c2pa/configuration"),
                bearerToken: TestEnvironment.signingServerToken)
            let remote = try await signer.createSigner()
            #expect(try remote.reserveSize() > 0)
            let store = try Fixtures.signAndRead(
                Builder(manifestJSON: Fixtures.createdManifestJSON(claimGenerator: "webservice_test/1.0")), signer: remote)
            #expect(try store.assertionLabels().contains("c2pa.test"))
            #expect(store.validationState == "Valid", "validation status: \(store.validationCodes)")
        }
    }
}
