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
//  Signer.swift
//

import C2PAC
import Foundation

/// A cryptographic signer for creating C2PA signatures.
///
/// `Signer` encapsulates the signing credentials and algorithm needed to
/// cryptographically sign C2PA manifests. It supports multiple initialization
/// methods for different credential sources:
///
/// - PEM-encoded certificates and private keys
/// - Custom signing closures (for hardware keys or remote signing)
/// - ``SignerInfo`` convenience wrapper
///
/// ## Topics
///
/// ### Creating a Signer
/// - ``init(certsPEM:privateKeyPEM:algorithm:tsa:)``
/// - ``init(info:)``
/// - ``init(algorithm:certificateChainPEM:tsa:sign:)``
/// - ``withCawgIdentity(_:identity:referencedAssertions:roles:)``
///
/// ### Signing Operations
/// - ``reserveSize()``
///
/// ### Keychain Utilities
/// - ``exportPublicKeyPEM(fromKeychainTag:)``
///
/// ## Example with PEM Credentials
///
/// ```swift
/// let signer = try Signer(
///     certsPEM: certificateChainPEM,
///     privateKeyPEM: privateKeyPEM,
///     algorithm: .es256,
///     tsa: URL(string: "http://timestamp.digicert.com")
/// )
/// ```
///
/// ## Example with Custom Signing Closure
///
/// ```swift
/// let signer = try Signer(
///     algorithm: .es256,
///     certificateChainPEM: certChainPEM,
///     tsa: URL(string: "http://timestamp.digicert.com")
/// ) { dataToSign in
///     // Custom signing logic (e.g., hardware key, remote service)
///     return try signWithHardwareKey(dataToSign)
/// }
/// ```
///
/// - SeeAlso: ``KeychainSigner``, ``SecureEnclaveSigner``, ``WebServiceSigner``
public final class Signer {

    /// The possible formats a settings string can have.
    public enum SettingsFormat: String {

        /// Settings are provided as a JSON formatted string
        case json

        /// Settings are provided as a TOML formatted string
        case toml
    }

    let ptr: UnsafeMutablePointer<C2paSigner>
    private var retainedContext: Unmanaged<AnyObject>?
    /// When true, the native signer was consumed by ``withCawgIdentity(_:identity:referencedAssertions:roles:)``
    /// and must not be freed by this instance.
    private var consumed = false
    /// Input signers consumed into this combined signer; held so their callback contexts
    /// outlive this signer and are released only after this signer is freed.
    private var consumedSigners: [Signer] = []

    private init(ptr: UnsafeMutablePointer<C2paSigner>) {
        self.ptr = ptr
    }

    /// Creates a signer with PEM-encoded certificates and private key.
    ///
    /// This is the most common initialization method for signers using
    /// standard PEM-encoded credentials.
    ///
    /// - Parameters:
    ///   - certsPEM: The certificate chain in PEM format.
    ///   - privateKeyPEM: The private key in PEM format.
    ///   - algorithm: The signing algorithm to use.
    ///   - tsa: Optional URL of a timestamp authority for trusted timestamps.
    ///
    /// - Throws: ``C2PAError`` if the credentials are invalid or incompatible.
    ///
    /// - SeeAlso: ``init(info:)``
    public convenience init(
        certsPEM: String,
        privateKeyPEM: String,
        algorithm: SigningAlgorithm,
        tsa: URL? = nil
    ) throws {
        var raw: UnsafeMutablePointer<C2paSigner>!
        try withSignerInfo(
            algorithm: algorithm.rawValue,
            cert: certsPEM,
            key: privateKeyPEM,
            tsa: tsa
        ) { algPtr, certPtr, keyPtr, tsaPtr in
            var info = C2paSignerInfo(
                alg: algPtr,
                sign_cert: certPtr,
                private_key: keyPtr,
                ta_url: tsaPtr)
            raw = try guardNotNull(c2pa_signer_from_info(&info))
        }
        self.init(ptr: raw)
    }

    /// Creates a signer from a ``SignerInfo`` struct.
    ///
    /// This convenience initializer accepts a ``SignerInfo`` struct containing
    /// all necessary signing credentials.
    ///
    /// - Parameter info: The signing credentials and configuration.
    ///
    /// - Throws: ``C2PAError`` if the credentials are invalid or incompatible.
    ///
    /// - SeeAlso: ``SignerInfo``
    public convenience init(info: SignerInfo) throws {
        try self.init(
            certsPEM: info.certificatePEM,
            privateKeyPEM: info.privateKeyPEM,
            algorithm: info.algorithm,
            tsa: info.tsa)
    }

    /// Creates a signer from JSON settings configuration.
    ///
    /// This initializer creates a signer from a JSON settings object that can
    /// include certificate paths, private keys, algorithm selection, and other
    /// configuration options. This is useful for loading signer configuration
    /// from external sources, configuration files, or for CAWG (Coalition for
    /// Content Provenance and Authenticity Working Group) signers.
    ///
    /// - Parameter settingsJSON: A JSON string containing signer configuration.
    ///
    /// - Throws: ``C2PAError`` if the settings are invalid or the signer cannot be created.
    ///
    /// ## Settings Format
    ///
    /// The JSON should follow the C2PA settings format. For a CAWG signer:
    ///
    /// ```json
    /// {
    ///     "version": 1,
    ///     "cawg_x509_signer": {
    ///         "local": {
    ///             "alg": "es256",
    ///             "sign_cert": "-----BEGIN CERTIFICATE-----\n...",
    ///             "private_key": "-----BEGIN PRIVATE KEY-----\n...",
    ///             "tsa_url": "http://timestamp.digicert.com"
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// ## Example
    ///
    /// ```swift
    /// let settingsJSON = """
    /// {
    ///     "version": 1,
    ///     "cawg_x509_signer": {
    ///         "local": {
    ///             "alg": "es256",
    ///             "sign_cert": "\(certPEM)",
    ///             "private_key": "\(keyPEM)",
    ///             "tsa_url": "http://timestamp.digicert.com"
    ///         }
    ///     }
    /// }
    /// """
    ///
    /// let signer = try Signer(settingsJSON: settingsJSON)
    /// ```
    ///
    /// - Note: This method requires C2PAC framework v0.71.0 or later.
    ///
    /// - SeeAlso: ``init(certsPEM:privateKeyPEM:algorithm:tsa:)``
    public convenience init(settingsJSON: String) throws {
        try self.init(settings: settingsJSON, format: .json)
    }

    /// Creates a signer from TOML settings configuration.
    ///
    /// This initializer creates a signer from a TOML settings string. TOML format
    /// supports additional features like CAWG (Creator Assertions Working Group)
    /// X.509 signers that generate identity assertions.
    ///
    /// - Parameter settingsTOML: A TOML string containing signer configuration.
    ///
    /// - Throws: ``C2PAError`` if the settings are invalid or the signer cannot be created.
    ///
    /// ## CAWG Signer Example
    ///
    /// ```swift
    /// let settingsTOML = """
    /// version = 1
    ///
    /// [cawg_x509_signer.local]
    /// alg = "es256"
    /// sign_cert = \"\"\"-----BEGIN CERTIFICATE-----
    /// ...certificate chain...
    /// -----END CERTIFICATE-----
    /// \"\"\"
    /// private_key = \"\"\"-----BEGIN PRIVATE KEY-----
    /// ...private key...
    /// -----END PRIVATE KEY-----
    /// \"\"\"
    /// tsa_url = "http://timestamp.digicert.com"
    /// referenced_assertions = ["cawg.training-mining"]
    /// """
    ///
    /// let signer = try Signer(settingsTOML: settingsTOML)
    /// ```
    ///
    /// - Note: This method requires C2PAC framework v0.72.0 or later.
    ///
    /// - SeeAlso: ``init(settingsJSON:)``
    public convenience init(settingsTOML: String) throws {
        try self.init(settings: settingsTOML, format: .toml)
    }

    /// Creates a signer from settings configuration in the specified format.
    ///
    /// - Parameters:
    ///   - settings: The settings string in the specified format.
    ///   - format: The format of the settings string ("json" or "toml").
    ///
    /// - Throws: ``C2PAError`` if the settings are invalid or the signer cannot be created.
    private convenience init(settings: String, format: SettingsFormat) throws {
        let raw = try settings.withCString { settingsPtr in
            try format.rawValue.withCString { formatPtr in
                let result = c2pa_load_settings(settingsPtr, formatPtr)
                guard result == 0 else {
                    throw C2PAError.api(lastC2PAError())
                }
                return try guardNotNull(c2pa_signer_from_settings())
            }
        }
        self.init(ptr: raw)
    }

    /// Loads global C2PA settings without creating a signer.
    ///
    /// This method loads settings that will be used by subsequent signing operations.
    /// Use this to load CAWG identity assertion settings separately from the main signer.
    ///
    /// - Parameters:
    ///   - settings: The settings string in the specified format.
    ///   - format: The format of the settings string ("json" or "toml").
    ///
    /// - Throws: ``C2PAError`` if the settings are invalid.
    public static func loadSettings(_ settings: String, format: SettingsFormat) throws {
        try settings.withCString { settingsPtr in
            try format.rawValue.withCString { formatPtr in
                let result = c2pa_load_settings(settingsPtr, formatPtr)
                guard result == 0 else {
                    throw C2PAError.api(lastC2PAError())
                }
            }
        }
    }

    /// Creates a signer with a custom signing closure.
    ///
    /// This initializer enables advanced signing scenarios where the private key
    /// is not directly accessible as PEM data. Common use cases include:
    ///
    /// - Hardware security modules (HSM)
    /// - Secure Enclave on iOS/macOS devices
    /// - Remote signing services
    /// - Keychain-stored keys
    ///
    /// The signing closure receives the data to be signed and must return the
    /// signature bytes. The closure is called during the signing operation.
    ///
    /// - Parameters:
    ///   - algorithm: The signing algorithm that matches your closure's implementation.
    ///   - certificateChainPEM: The certificate chain in PEM format.
    ///   - tsa: Optional URL of a timestamp authority for trusted timestamps.
    ///   - sign: A closure that accepts data to sign and returns the signature.
    ///
    /// - Throws: ``C2PAError`` if the signer cannot be created.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let signer = try Signer(
    ///     algorithm: .es256,
    ///     certificateChainPEM: certChain,
    ///     tsa: URL(string: "http://timestamp.digicert.com")
    /// ) { dataToSign in
    ///     let signature = try SecKeyCreateSignature(
    ///         privateKeyRef,
    ///         .ecdsaSignatureMessageX962SHA256,
    ///         dataToSign as CFData,
    ///         nil
    ///     )
    ///     return signature as Data
    /// }
    /// ```
    ///
    /// - SeeAlso: ``SecureEnclaveSigner``, ``KeychainSigner``
    public convenience init(
        algorithm: SigningAlgorithm,
        certificateChainPEM: String,
        tsa: URL? = nil,
        sign: @escaping (Data) throws -> Data
    ) throws {
        // keep closure alive
        final class Box {
            let fn: (Data) throws -> Data
            init(_ fn: @escaping (Data) throws -> Data) { self.fn = fn }
        }
        let box = Box(sign)
        let ref = Unmanaged.passRetained(box as AnyObject)  // Retain Box as AnyObject

        let tramp: SignerCallback = { ctx, bytes, len, dst, dstCap in
            // ctx is the opaque pointer to our Box instance
            guard let ctx, let bytes, let dst else { return -1 }
            let b = Unmanaged<Box>.fromOpaque(ctx).takeUnretainedValue()
            let msg = Data(bytes: bytes, count: Int(len))  // len is uintptr_t (UInt)

            do {
                let sig = try b.fn(msg)
                // dstCap is uintptr_t (UInt)
                guard UInt(sig.count) <= dstCap else { return -1 }  // Compare UInts
                sig.copyBytes(to: dst, count: sig.count)
                return sig.count
            } catch {
                return -1
            }
        }

        var raw: UnsafeMutablePointer<C2paSigner>!
        try certificateChainPEM.withCString { certPtr in
            try withOptionalCString(tsa?.absoluteString) { tsaPtr in
                raw = try guardNotNull(
                    c2pa_signer_create(
                        ref.toOpaque(),  // Pass opaque pointer to Box instance
                        tramp,
                        algorithm.cValue,
                        certPtr,
                        tsaPtr
                    )
                )
            }
        }

        self.init(ptr: raw)
        retainedContext = ref  // Store the Unmanaged<AnyObject>
    }

    deinit {
        if !consumed { _ = c2pa_free(ptr) }
        retainedContext?.release()
    }

    /// Returns the expected signature size in bytes for this signer.
    ///
    /// This method is used internally to allocate buffer space for the signature.
    /// The size depends on the signing algorithm configured for this signer.
    ///
    /// - Returns: The signature size in bytes.
    ///
    /// - Throws: ``C2PAError`` if the size cannot be determined.
    public func reserveSize() throws -> Int {
        try Int(guardNonNegative(c2pa_signer_reserve_size(ptr)))
    }

    /// Combines a claim signer with an X.509 identity signer into a single signer that
    /// emits a `cawg.identity` assertion alongside the C2PA claim signature.
    ///
    /// Both `claimSigner` and `identitySigner` are **consumed** by this call: ownership
    /// transfers to the returned signer, and they must not be reused or signed with afterward.
    ///
    /// - Parameters:
    ///   - claimSigner: The signer used to sign the C2PA claim. Consumed by this call.
    ///   - identitySigner: The signer used to sign the X.509 identity assertion. Consumed by this call.
    ///   - referencedAssertions: Names of assertions to reference in the identity assertion.
    ///   - roles: The named actor's roles.
    ///
    /// - Returns: A combined ``Signer`` that emits a `cawg.identity` assertion.
    ///
    /// - Throws: ``C2PAError`` if the combined signer cannot be created.
    public static func withCawgIdentity(
        _ claimSigner: Signer,
        identity identitySigner: Signer,
        referencedAssertions: [String] = [],
        roles: [String] = []
    ) throws -> Signer {
        claimSigner.consumed = true
        identitySigner.consumed = true
        let raw = try withCStringArray(referencedAssertions) { refs in
            try withCStringArray(roles) { roleList in
                try guardNotNull(
                    c2pa_identity_signer_create(claimSigner.ptr, identitySigner.ptr, refs, roleList))
            }
        }
        let combined = Signer(ptr: raw)
        combined.consumedSigners = [claimSigner, identitySigner]
        return combined
    }
}

extension Signer {
    /// Exports the public key from a keychain-stored key as PEM format.
    ///
    /// This utility method retrieves a private key from the iOS/macOS keychain
    /// and exports its corresponding public key in PEM format. This is useful
    /// when working with keychain-stored keys that need to be shared or
    /// included in certificate signing requests.
    ///
    /// - Parameter keyTag: The keychain tag identifying the private key.
    ///
    /// - Returns: The public key in PEM format.
    ///
    /// - Throws: ``C2PAError`` if the key cannot be found or exported.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let publicKeyPEM = try Signer.exportPublicKeyPEM(
    ///     fromKeychainTag: "com.example.signing.key"
    /// )
    /// ```
    ///
    /// - SeeAlso: ``KeychainSigner``, ``SecureEnclaveSigner``
    public static func exportPublicKeyPEM(fromKeychainTag keyTag: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
            let privateKey = item as! SecKey?
        else {
            throw C2PAError.keySearchFailed(keyTag, status)
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw C2PAError.publicKeyExtractionFailed
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
        else {
            throw C2PAError.publicKeyExportFailed(error?.takeRetainedValue())
        }

        let base64 = publicKeyData.base64EncodedString(options: [
            .lineLength64Characters, .endLineWithLineFeed
        ])
        return "-----BEGIN PUBLIC KEY-----\n\(base64)\n-----END PUBLIC KEY-----"
    }
}
