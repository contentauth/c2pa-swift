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
//  WebServiceSigner.swift
//

import C2PAC
import Crypto
import Foundation
import SwiftASN1
import X509
import os

/// A signer that delegates cryptographic operations to a remote web service.
///
/// `WebServiceSigner` enables signing scenarios where the private key is managed
/// by a remote server rather than on the client device. This is useful for:
///
/// - Centralized key management
/// - Cloud-based signing services
/// - Enterprise signing workflows
/// - Multi-device signing with consistent credentials
///
/// The web service must implement the C2PA signing service protocol, providing
/// endpoints for configuration and signing operations.
///
/// ## Topics
///
/// ### Creating a Web Service Signer
/// - ``init(configurationEndpoint:bearerToken:headers:urlSession:)``
/// - ``createSigner()``
///
/// ## Example
///
/// ```swift
/// let webServiceSigner = WebServiceSigner(
///     configurationEndpoint: URL(string: "https://signing.example.com/config")!,
///     bearerToken: "your-auth-token"
/// )
///
/// let signer = try await webServiceSigner.createSigner()
///
/// let builder = try Builder(manifestJSON: manifestJSON)
/// try builder.sign(
///     format: "image/jpeg",
///     source: sourceStream,
///     destination: destStream,
///     signer: signer
/// )
/// ```
///
/// - SeeAlso: ``Signer``, ``SignerError``
public final class WebServiceSigner: Sendable {
    private let configurationEndpoint: URL
    private let bearerToken: String?
    private let customHeaders: [String: String]
    private let urlSession: URLSession

    private let log = Logger(subsystem: "org.contentauth.c2pa", category: "WebServiceSigner")

    /// Creates a new web service signer client.
    ///
    /// - Parameters:
    ///   - configurationEndpoint: The URL of the signing service configuration endpoint.
    ///   - bearerToken: Optional bearer token for authentication.
    ///   - headers: Additional custom HTTP headers to include in requests.
    ///   - urlSession: Optional ``URLSession`` object. If not given ``URLSession.shared`` will be used.
    public init(configurationEndpoint: URL, bearerToken: String? = nil, headers: [String: String] = [:], urlSession: URLSession = .shared) {
        self.configurationEndpoint = configurationEndpoint
        self.bearerToken = bearerToken
        self.customHeaders = headers
        self.urlSession = urlSession
    }

    /// Creates a ``Signer`` instance configured to use this web service.
    ///
    /// This method fetches the signing configuration from the remote service,
    /// including the certificate chain, timestamp URL, and signing algorithm.
    /// The returned signer will delegate all signing operations to the web service.
    ///
    /// - Returns: A configured ``Signer`` instance ready for use.
    ///
    /// - Throws: ``SignerError`` if the configuration cannot be fetched, is invalid,
    ///   or if the signing service is unavailable.
    public func createSigner() async throws -> Signer {
        let configuration = try await fetchConfiguration()
        let signingAlgorithm = try mapAlgorithm(configuration.algorithm)
        let certificateChain = try parseCertificateChain(configuration.certificateChain)

        // Use strong self capture to keep WebServiceSigner alive
        return try Signer(
            algorithm: signingAlgorithm,
            certificateChainPEM: certificateChain,
            tsa: configuration.timestamp,
            asyncSigner: { [self] data in
                log.info("AsyncSigner called with data size: \(data.count)")
                return try await self.signData(data, signing: configuration.signingEndpoint)
            }
        )
    }

    private func mapAlgorithm(_ algorithmString: String) throws -> SigningAlgorithm {
        guard let algorithm = SigningAlgorithm(rawValue: algorithmString.lowercased()) else {
            throw SignerError.unsupportedAlgorithm(algorithmString)
        }

        return algorithm
    }

    private func fetchConfiguration() async throws -> SignerConfiguration {
        var request = URLRequest(url: configurationEndpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Apply custom headers first
        for (key, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Bearer token can override Authorization header if provided
        if let bearerToken = bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SignerError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw SignerError.httpError(statusCode: httpResponse.statusCode)
        }

        return try C2PAJson.decode(SignerConfiguration.self, from: data)
    }

    private func signData(_ data: Data, signing: URL) async throws -> Data {
        log.info("Starting signData with URL: \(signing)")
        log.info("Data size to sign: \(data.count) bytes")

        var request = URLRequest(url: signing)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Apply custom headers first
        for (key, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Bearer token can override Authorization header if provided
        if let bearerToken = bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            log.info("Added bearer token to request")
        }

        let requestBody = SignRequest(claim: data.base64EncodedString())
        request.httpBody = try C2PAJson.encoder.encode(requestBody)
        log.info("Request body size: \(request.httpBody?.count ?? 0) bytes")
        log.info("Making POST request to: \(signing.absoluteString)")

        let (responseData, response) = try await urlSession.data(for: request)
        log.info("Received response")

        guard let httpResponse = response as? HTTPURLResponse else {
            log.error("Response is not HTTPURLResponse")
            throw SignerError.invalidResponse
        }

        log.info("Response status code: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            log.error("HTTP error \(httpResponse.statusCode)")
            if let errorBody = String(data: responseData, encoding: .utf8) {
                log.error("Error response body: \(errorBody)")
            }
            throw SignerError.httpError(statusCode: httpResponse.statusCode)
        }

        let signResponse = try C2PAJson.decode(SignResponse.self, from: responseData)

        guard let signatureData = Data(base64Encoded: signResponse.signature) else {
            log.error("Failed to decode signature from base64")
            throw SignerError.invalidSignature
        }

        log.debug("Successfully decoded signature, size: \(signatureData.count) bytes")
        return signatureData
    }

    private func parseCertificateChain(_ base64Chain: String) throws -> String {
        guard let chainData = Data(base64Encoded: base64Chain) else {
            throw SignerError.invalidCertificateChain
        }

        guard let chainString = String(data: chainData, encoding: .utf8) else {
            throw SignerError.invalidCertificateChain
        }

        // Validate that we have at least one certificate
        guard chainString.contains("BEGIN CERTIFICATE") && chainString.contains("END CERTIFICATE") else {
            throw SignerError.noCertificatesFound
        }

        return chainString
    }
}

private struct SignerConfiguration: Codable {
    enum CodingKeys: String, CodingKey {
        case algorithm
        case timestamp = "timestamp_url"
        case signingEndpoint = "signing_url"
        case certificateChain = "certificate_chain"
    }

    let algorithm: String
    let timestamp: URL
    let signingEndpoint: URL
    let certificateChain: String
}

private struct SignRequest: Codable {
    let claim: String  // Base64-encoded bytes to be signed
}

private struct SignResponse: Codable {
    let signature: String
}

/// Errors that can occur during web service signing operations.
public enum SignerError: LocalizedError {
    /// The provided URL is invalid or malformed.
    case invalidURL

    /// The server returned an invalid or unexpected response.
    case invalidResponse

    /// An HTTP error occurred.
    ///
    /// - Parameter statusCode: The HTTP status code returned by the server.
    case httpError(statusCode: Int)

    /// The signing algorithm is not supported.
    ///
    /// - Parameter algorithm: The unsupported algorithm name.
    case unsupportedAlgorithm(String)

    /// The certificate chain returned by the server is invalid.
    case invalidCertificateChain

    /// No certificates were found in the certificate chain.
    case noCertificatesFound

    /// The signature returned by the server is invalid or cannot be decoded.
    case invalidSignature

    /// The web service signer was deallocated before the operation completed.
    case signerDeallocated

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .unsupportedAlgorithm(let algorithm):
            return "Unsupported algorithm: \(algorithm)"
        case .invalidCertificateChain:
            return "Invalid certificate chain"
        case .noCertificatesFound:
            return "No certificates found in chain"
        case .invalidSignature:
            return "Invalid signature format"
        case .signerDeallocated:
            return "WebServiceSigner was deallocated"
        }
    }
}

extension Signer {
    /// Creates a signer with an asynchronous signing closure.
    ///
    /// This initializer enables signing scenarios that require asynchronous operations,
    /// such as network requests to remote signing services. The closure can perform
    /// async/await operations and will be properly bridged to the synchronous C API.
    ///
    /// - Parameters:
    ///   - algorithm: The signing algorithm.
    ///   - certificateChainPEM: The certificate chain in PEM format.
    ///   - tsa: Optional URL of a timestamp authority.
    ///   - asyncSigner: An async closure that accepts data to sign and returns the signature.
    ///
    /// - Throws: ``C2PAError`` if the signer cannot be created.
    ///
    /// - Note: This is used internally by ``WebServiceSigner`` but can be used for
    ///   other custom async signing implementations.
    ///
    /// - SeeAlso: ``WebServiceSigner``
    public convenience init(
        algorithm: SigningAlgorithm,
        certificateChainPEM: String,
        tsa: URL? = nil,
        asyncSigner: @escaping @Sendable (Data) async throws -> Data
    ) throws {
        try self.init(
            algorithm: algorithm,
            certificateChainPEM: certificateChainPEM,
            tsa: tsa
        ) { data in
            let semaphore = DispatchSemaphore(value: 0)
            // The semaphore's signal/wait pair orders every access to `result`.
            nonisolated(unsafe) var result: Result<Data, Error>?

            Task.detached {
                do {
                    result = .success(try await asyncSigner(data))
                } catch {
                    result = .failure(error)
                }
                semaphore.signal()
            }

            semaphore.wait()

            guard let result else { throw C2PAError.asyncSigningFailed }
            return try result.get()
        }
    }
}
