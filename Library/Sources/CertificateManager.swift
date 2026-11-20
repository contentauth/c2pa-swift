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
//  CertificateManager.swift
//

import Crypto
import Foundation
import Security
import SwiftASN1
import X509

/// A utility class for managing X.509 certificates and certificate signing requests.
///
/// `CertificateManager` provides methods for creating self-signed certificate chains
/// and certificate signing requests (CSRs), particularly for use with Secure Enclave
/// and keychain-stored keys.
///
/// ## Topics
///
/// ### Creating Certificates
/// - ``createSelfSignedCertificateChain(for:config:)``
///
/// ### Creating Certificate Signing Requests
/// - ``createCSR(for:config:)``
/// - ``createCSR(keyTag:config:)``
///
/// ### Configuration
/// - ``CertificateConfig``
///
/// ### Errors
/// - ``CertificateError``
public class CertificateManager {

    /// Errors that can occur during certificate operations.
    public enum CertificateError: LocalizedError {
        case invalidKeyData
        case unsupportedAlgorithm
        case unsupportedKeyFormat
        case signingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidKeyData:
                return "Invalid key data"
            case .unsupportedAlgorithm:
                return "Unsupported algorithm"
            case .unsupportedKeyFormat:
                return "Unsupported key format"
            case .signingFailed(let details):
                return "Failed to sign: \(details)"
            }
        }
    }

    /// Configuration for creating X.509 certificates.
    ///
    /// This structure contains the distinguished name fields and validity period
    /// used when generating certificates or certificate signing requests.
    public struct CertificateConfig {
        /// The common name (CN) field, typically the name of the entity.
        public let commonName: String

        /// The organization (O) field.
        public let organization: String

        /// The organizational unit (OU) field.
        public let organizationalUnit: String

        /// The country (C) field, as a two-letter ISO code.
        public let country: String

        /// The state or province (ST) field.
        public let state: String

        /// The locality or city (L) field.
        public let locality: String

        /// Optional email address for the certificate.
        public let emailAddress: String?

        /// The number of days the certificate should be valid.
        public let validityDays: Int

        /// Creates a new certificate configuration.
        ///
        /// - Parameters:
        ///   - commonName: The common name for the certificate.
        ///   - organization: The organization name.
        ///   - organizationalUnit: The organizational unit.
        ///   - country: The two-letter country code.
        ///   - state: The state or province.
        ///   - locality: The city or locality.
        ///   - emailAddress: Optional email address.
        ///   - validityDays: Number of days the certificate is valid. Defaults to 365.
        public init(
            commonName: String,
            organization: String,
            organizationalUnit: String,
            country: String,
            state: String,
            locality: String,
            emailAddress: String? = nil,
            validityDays: Int = 365
        ) {
            self.commonName = commonName
            self.organization = organization
            self.organizationalUnit = organizationalUnit
            self.country = country
            self.state = state
            self.locality = locality
            self.emailAddress = emailAddress
            self.validityDays = validityDays
        }
    }

    /// Creates a self-signed certificate chain for testing purposes.
    ///
    /// This method generates a complete three-tier certificate chain (root CA,
    /// intermediate CA, and end-entity certificate) suitable for C2PA signing.
    /// The chain is self-signed and should only be used for testing and development.
    ///
    /// - Parameters:
    ///   - publicKey: The public key for which to create the certificate chain.
    ///   - config: The certificate configuration containing distinguished name fields.
    ///
    /// - Returns: A PEM-encoded string containing the complete certificate chain
    ///   (end-entity, intermediate, and root certificates).
    ///
    /// - Throws: ``CertificateError`` if certificate generation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let config = CertificateManager.CertificateConfig(
    ///     commonName: "Test Signer",
    ///     organization: "Example Inc",
    ///     organizationalUnit: "Engineering",
    ///     country: "US",
    ///     state: "California",
    ///     locality: "San Francisco"
    /// )
    ///
    /// let certChain = try CertificateManager.createSelfSignedCertificateChain(
    ///     for: publicKey,
    ///     config: config
    /// )
    /// ```
    ///
    /// - Important: This creates self-signed certificates that are not trusted by default.
    ///   For production use, obtain certificates from a trusted Certificate Authority.
    ///
    /// - SeeAlso: ``createCSR(for:config:)``
    public static func createSelfSignedCertificateChain(
        for publicKey: SecKey,
        config: CertificateConfig
    ) throws -> String {
        // For Secure Enclave keys, we need to create a certificate chain
        // using regular P256 keys for the CA certificates
        let rootKeyPair = P256.Signing.PrivateKey()
        let intermediateKeyPair = P256.Signing.PrivateKey()

        let rootConfig = CertificateConfig(
            commonName: "\(config.organization) Root CA",
            organization: config.organization,
            organizationalUnit: config.organizationalUnit,
            country: config.country,
            state: config.state,
            locality: config.locality,
            validityDays: config.validityDays * 10
        )

        let rootCert = try createRootCA(
            privateKey: rootKeyPair,
            config: rootConfig
        )

        let intermediateConfig = CertificateConfig(
            commonName: "\(config.organization) Intermediate CA",
            organization: config.organization,
            organizationalUnit: config.organizationalUnit,
            country: config.country,
            state: config.state,
            locality: config.locality,
            validityDays: config.validityDays * 5
        )

        let intermediateCert = try createIntermediateCA(
            privateKey: intermediateKeyPair,
            config: intermediateConfig,
            issuerCertificate: rootCert,
            issuerPrivateKey: rootKeyPair
        )

        let endEntityCert = try createEndEntityCertificate(
            publicKey: publicKey,
            config: config,
            issuerCertificate: intermediateCert,
            issuerPrivateKey: intermediateKeyPair
        )

        let endEntity = try endEntityCert.serializeAsPEM().pemString
        let intermediate = try intermediateCert.serializeAsPEM().pemString
        let root = try rootCert.serializeAsPEM().pemString

        return endEntity + "\n" + intermediate + "\n" + root
    }

    /// Creates a Certificate Signing Request (CSR) for a public key.
    ///
    /// This method generates a PKCS#10 certificate signing request that can be
    /// submitted to a Certificate Authority (CA) to obtain a signed certificate.
    /// It works with Secure Enclave keys and regular keychain keys.
    ///
    /// - Parameters:
    ///   - publicKey: The public key for which to create the CSR.
    ///   - config: The certificate configuration containing subject information.
    ///
    /// - Returns: A PEM-encoded certificate signing request.
    ///
    /// - Throws: ``CertificateError`` if the CSR cannot be created.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let config = CertificateManager.CertificateConfig(
    ///     commonName: "My Signing Key",
    ///     organization: "Example Inc",
    ///     organizationalUnit: "Security",
    ///     country: "US",
    ///     state: "California",
    ///     locality: "San Francisco",
    ///     emailAddress: "security@example.com"
    /// )
    ///
    /// let csrPEM = try CertificateManager.createCSR(
    ///     for: publicKey,
    ///     config: config
    /// )
    /// // Submit csrPEM to your CA
    /// ```
    ///
    /// - Note: For Secure Enclave keys, the private key never leaves the hardware.
    ///   The CSR is signed using the Secure Enclave's signing capabilities.
    ///
    /// - SeeAlso: ``createCSR(keyTag:config:)``
    public static func createCSR(
        for publicKey: SecKey,
        config: CertificateConfig
    ) throws -> String {
        // For Secure Enclave keys, we need to manually create the CSR
        // because we don't have access to the private key material

        // Find the corresponding private key reference (not the key material)
        guard let privateKey = try findPrivateKey(for: publicKey) else {
            throw CertificateError.invalidKeyData
        }

        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CertificateError.invalidKeyData
        }

        // Parse to get P256 public key for use with Certificate.PublicKey
        let p256PublicKey = try parseSecKeyPublicKey(publicKeyData)

        return try createCSRManually(
            publicKey: p256PublicKey,
            privateKey: privateKey,
            config: config
        )
    }

    /// Creates a Certificate Signing Request (CSR) for a keychain-stored key.
    ///
    /// This convenience method creates a CSR for a key stored in the keychain,
    /// identified by its tag. The key is retrieved from the keychain and a CSR
    /// is generated using its public key component.
    ///
    /// - Parameters:
    ///   - keyTag: The keychain tag identifying the private key.
    ///   - config: The certificate configuration containing subject information.
    ///
    /// - Returns: A PEM-encoded certificate signing request.
    ///
    /// - Throws: ``CertificateError`` if the key cannot be found or the CSR cannot be created.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let csrPEM = try CertificateManager.createCSR(
    ///     keyTag: "com.example.signing.key",
    ///     config: config
    /// )
    /// ```
    ///
    /// - SeeAlso: ``createCSR(for:config:)``
    public static func createCSR(
        keyTag: String,
        config: CertificateConfig
    ) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = unsafe SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
            let privateKey = item as! SecKey?
        else {
            throw CertificateError.invalidKeyData
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CertificateError.invalidKeyData
        }

        return try createCSR(for: publicKey, config: config)
    }

    // MARK: - Private Methods

    private static func createRootCA(
        privateKey: P256.Signing.PrivateKey,
        config: CertificateConfig
    ) throws -> Certificate {
        let subject = try createDistinguishedName(from: config)

        let extensions = try Certificate.Extensions {
            BasicConstraints.isCertificateAuthority(maxPathLength: 1)
            KeyUsage(keyCertSign: true, cRLSign: true)
            SubjectKeyIdentifier(hash: Certificate.PublicKey(privateKey.publicKey))
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(privateKey.publicKey),
            notValidBefore: Date().addingTimeInterval(-5 * 60),  // 5 minutes ago for clock skew
            notValidAfter: Date().addingTimeInterval(
                TimeInterval(config.validityDays * 24 * 60 * 60)),
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(privateKey)
        )

        return certificate
    }

    private static func createIntermediateCA(
        privateKey: P256.Signing.PrivateKey,
        config: CertificateConfig,
        issuerCertificate: Certificate,
        issuerPrivateKey: P256.Signing.PrivateKey
    ) throws -> Certificate {
        let subject = try createDistinguishedName(from: config)

        let extensions = try Certificate.Extensions {
            BasicConstraints.isCertificateAuthority(maxPathLength: 0)
            KeyUsage(keyCertSign: true, cRLSign: true)
            SubjectKeyIdentifier(hash: Certificate.PublicKey(privateKey.publicKey))
            AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(
                    Insecure.SHA1.hash(data: issuerPrivateKey.publicKey.x963Representation))
            )
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(privateKey.publicKey),
            notValidBefore: Date().addingTimeInterval(-5 * 60),  // 5 minutes ago for clock skew
            notValidAfter: Date().addingTimeInterval(
                TimeInterval(config.validityDays * 24 * 60 * 60)),
            issuer: issuerCertificate.subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(issuerPrivateKey)
        )

        return certificate
    }

    private static func createEndEntityCertificate(
        publicKey: SecKey,
        config: CertificateConfig,
        issuerCertificate: Certificate,
        issuerPrivateKey: P256.Signing.PrivateKey
    ) throws -> Certificate {
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CertificateError.invalidKeyData
        }

        let p256PublicKey = try parseSecKeyPublicKey(publicKeyData)

        let subject = try createDistinguishedName(from: config)

        let extensions = try Certificate.Extensions {
            BasicConstraints.notCertificateAuthority
            KeyUsage(digitalSignature: true)
            try ExtendedKeyUsage([.emailProtection])
            SubjectKeyIdentifier(hash: Certificate.PublicKey(p256PublicKey))
            AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(
                    Insecure.SHA1.hash(data: issuerPrivateKey.publicKey.x963Representation))
            )
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(p256PublicKey),
            notValidBefore: Date().addingTimeInterval(-5 * 60),  // 5 minutes ago for clock skew
            notValidAfter: Date().addingTimeInterval(
                TimeInterval(config.validityDays * 24 * 60 * 60)),
            issuer: issuerCertificate.subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(issuerPrivateKey)
        )

        return certificate
    }

    private static func createDistinguishedName(from config: CertificateConfig) throws
        -> DistinguishedName
    {
        try DistinguishedName {
            CommonName(config.commonName)
            OrganizationName(config.organization)
            OrganizationalUnitName(config.organizationalUnit)
            CountryName(config.country)
            StateOrProvinceName(config.state)
            LocalityName(config.locality)
            if let email = config.emailAddress {
                EmailAddress(email)
            }
        }
    }

    private static func parseSecKeyPublicKey(_ data: Data) throws -> P256.Signing.PublicKey {
        // SecKey exports P-256 public keys in X9.63 format (65 bytes: 0x04 || x || y)
        if data.count == 65 && data[0] == 0x04 {
            // It's an uncompressed point, which is what we expect
            return try P256.Signing.PublicKey(x963Representation: data)
        } else {
            throw CertificateError.unsupportedKeyFormat
        }
    }

    // Manually creates a CSR for Secure Enclave keys where we don't have private key access
    private static func createCSRManually(
        publicKey: P256.Signing.PublicKey,
        privateKey: SecKey,
        config: CertificateConfig
    ) throws -> String {
        let subject = try createDistinguishedName(from: config)

        // Create the CertificationRequestInfo
        var infoSerializer = DER.Serializer()
        try infoSerializer.appendConstructedNode(identifier: .sequence) { coder in
            try coder.serialize(0)  // version
            try coder.serialize(subject)

            // SubjectPublicKeyInfo
            try coder.appendConstructedNode(identifier: .sequence) { spkiCoder in
                try spkiCoder.appendConstructedNode(identifier: .sequence) { algCoder in
                    try algCoder.serialize(
                        try ASN1ObjectIdentifier(
                            elements: [1, 2, 840, 10045, 2, 1]))  // ecPublicKey
                    try algCoder.serialize(
                        try ASN1ObjectIdentifier(
                            elements: [1, 2, 840, 10045, 3, 1, 7]))  // secp256r1
                }
                try spkiCoder.serialize(
                    ASN1BitString(bytes: ArraySlice(publicKey.x963Representation)))
            }

            // Attributes (empty context-specific tag [0])
            coder.appendConstructedNode(
                identifier: .init(tagWithNumber: 0, tagClass: .contextSpecific)
            ) { _ in }
        }

        let infoData = Data(infoSerializer.serializedBytes)

        // Sign the CertificationRequestInfo
        let signature = try signData(infoData, with: privateKey)

        // Build the complete CSR manually using raw bytes
        // Structure: SEQUENCE { certificationRequestInfo, signatureAlgorithm, signature }
        var finalDER = Data()

        // Prepare signature algorithm
        var algSerializer = DER.Serializer()
        try algSerializer.appendConstructedNode(identifier: .sequence) { algCoder in
            try algCoder.serialize(
                try ASN1ObjectIdentifier(elements: [1, 2, 840, 10045, 4, 3, 2]))  // ecdsaWithSHA256
        }
        let algData = Data(algSerializer.serializedBytes)

        // Prepare signature
        var sigSerializer = DER.Serializer()
        try sigSerializer.serialize(ASN1BitString(bytes: ArraySlice(signature)))
        let sigData = Data(sigSerializer.serializedBytes)

        // Calculate total length
        let totalLength = infoData.count + algData.count + sigData.count

        // Build outer SEQUENCE
        finalDER.append(0x30)  // SEQUENCE tag

        // Encode length
        if totalLength < 128 {
            finalDER.append(UInt8(totalLength))
        } else if totalLength < 256 {
            finalDER.append(0x81)
            finalDER.append(UInt8(totalLength))
        } else {
            finalDER.append(0x82)
            finalDER.append(UInt8((totalLength >> 8) & 0xFF))
            finalDER.append(UInt8(totalLength & 0xFF))
        }

        // Append the three components
        finalDER.append(infoData)
        finalDER.append(algData)
        finalDER.append(sigData)

        let pemDocument = PEMDocument(type: "CERTIFICATE REQUEST", derBytes: Array(finalDER))

        return pemDocument.pemString
    }

    // Signs data with a SecKey private key
    private static func signData(_ data: Data, with privateKey: SecKey) throws -> Data {
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256

        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw CertificateError.unsupportedAlgorithm
        }

        var error: Unmanaged<CFError>?
        guard
            let signature = unsafe SecKeyCreateSignature(
                privateKey,
                algorithm,
                data as CFData,
                &error
            ) as Data?
        else {
            if let error = unsafe error?.takeRetainedValue() {
                throw CertificateError.signingFailed(error.localizedDescription)
            }
            throw CertificateError.signingFailed("Unknown signing error")
        }

        return signature
    }

    // Finds the private key corresponding to a public key
    private static func findPrivateKey(for publicKey: SecKey) throws -> SecKey? {
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CertificateError.invalidKeyData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var items: CFTypeRef?
        let status = unsafe SecItemCopyMatching(query as CFDictionary, &items)

        guard status == errSecSuccess,
            let keys = items as? [SecKey]
        else {
            return nil
        }

        for privateKey in keys {
            if let candidatePublicKey = SecKeyCopyPublicKey(privateKey),
                let candidatePublicKeyData = SecKeyCopyExternalRepresentation(
                    candidatePublicKey, nil) as Data?,
                candidatePublicKeyData == publicKeyData
            {
                return privateKey
            }
        }

        return nil
    }
}
