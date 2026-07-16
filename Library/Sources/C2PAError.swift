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
//  C2PAError.swift
//

import Foundation

/// Errors that can occur during C2PA operations.
///
/// `C2PAError` represents various error conditions that may arise when working
/// with the C2PA library, from low-level C API errors to data validation failures.
///
/// ## Topics
///
/// ### Error Cases
/// - ``api(_:)``
/// - ``nilPointer``
/// - ``utf8``
/// - ``negative(_:)``
/// - ``ed25519NotSupported``
/// - ``keySearchFailed(_:_:_:)``
/// - ``unsupportedAlgorithm(_:_:)``
/// - ``signingFailed(_:_:)``
/// - ``accessControlCreationFailed``
/// - ``keyCreationFailed(_:_:)``
/// - ``publicKeyExtractionFailed``
/// - ``publicKeyExportFailed(_:)``
/// - ``asyncSigningFailed``
/// - ``manifestValidationFailed(_:)``
public enum C2PAError: Error, LocalizedError {
    /// An error reported by the underlying C2PA library.
    ///
    /// - Parameter message: The error message from the Rust/C layer.
    case api(_ message: String)

    /// An unexpected NULL pointer was encountered in the C API.
    case nilPointer

    /// Invalid UTF-8 data was returned from the C2PA library.
    case utf8

    /// A negative status code was returned from the C API.
    ///
    /// - Parameter value: The negative status value.
    case negative(_ value: Int64)

    /// Ed25519 algorithm is not supported by the Keychain.
    case ed25519NotSupported

    /// - Parameter tag: Searched for keychain tag.
    /// - Parameter status: Non-`errSecSuccess` status.
    case keySearchFailed(_ tag: String, _ status: OSStatus, _ isSecureEnclave: Bool = false)

    /// - Parameter algorithm: The algorithm which is not supported.
    /// - Parameter isSecureEnclave: Modifies description text to hint at limitations of the Secure Enclave.
    case unsupportedAlgorithm(_ algorithm: SigningAlgorithm, _ isSecureEnclave: Bool = false)

    /// - Parameter error: Upstream error causing this.
    /// - Parameter isSecureEnclave: Modifies description text to hint at limitations of the Secure Enclave.
    case signingFailed(_ error: Error? = nil, _ isSecureEnclave: Bool = false)

    case accessControlCreationFailed

    /// - Parameter error: Upstream error causing this.
    /// - Parameter isSecureEnclave: Modifies description text to hint at limitations of the Secure Enclave.
    case keyCreationFailed(_ error: Error? = nil, _ isSecureEnclave: Bool = false)

    case publicKeyExtractionFailed

    /// - Parameter error: Upstream error causing this.
    case publicKeyExportFailed(_ error: Error? = nil)

    case asyncSigningFailed

    /// Manifest validation failed before building.
    ///
    /// - Parameter result: The ``ManifestValidationResult`` containing errors and warnings.
    case manifestValidationFailed(_ result: ManifestValidationResult)

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .api(let message):
            return "C2PA API error: \(message)"

        case .nilPointer:
            return "Unexpected NULL pointer"

        case .utf8:
            return "Invalid UTF-8 from C2PA"

        case .negative(let value):
            return "C2PA negative status \(value)"

        case .ed25519NotSupported:
            return "Ed25519 not supported by Keychain"

        case .keySearchFailed(let tag, let status, let isSecureEnclave):
            return "Failed to find key '\(tag)' in \(isSecureEnclave ? "Secure Enclave" : "keychain"): \(status)"

        case .unsupportedAlgorithm(let algorithm, let isSecureEnclave):
            return "\(isSecureEnclave ? "Secure Enclave key" : "Key") doesn't support algorithm \(algorithm)"

        case .signingFailed(let error, let isSecureEnclave):
            return "\(isSecureEnclave ? "Secure Enclave signing" : "Signing") failed\(error != nil ? ": \(error!)" : "")"

        case .accessControlCreationFailed:
            return "Failed to create access control"

        case .keyCreationFailed(let error, let isSecureEnclave):
            return "Failed to create \(isSecureEnclave ? "Secure Enclave" : "") key\(error != nil ? ": \(error!)" : "")"

        case .publicKeyExtractionFailed:
            return "Failed to extract public key"

        case .publicKeyExportFailed(let error):
            return "Failed to export public key\(error != nil ? ": \(error!)" : "")"

        case .asyncSigningFailed:
            return "Async signing operation failed"

        case .manifestValidationFailed(let result):
            return "Manifest validation failed: \(result.errors.joined(separator: "; "))"
        }
    }
}
