// This file is licensed to you under the Apache License, Version 2.0 
// (http://www.apache.org/licenses/LICENSE-2.0) or the MIT license 
// (http://opensource.org/licenses/MIT), at your option.
//
// Unless required by applicable law or agreed to in writing, this software is 
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF 
// ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE 
// files for the specific language governing permissions and limitations under
// each license.

import Crypto
import Foundation
import SwiftASN1
import Vapor
import X509

// Sendable: all stored properties are immutable, and Vapor's StorageKey requires it
// under the Swift 6 language mode.
final class CertificateSigningService: Sendable {
    private let rootCA: Certificate
    private let rootCAPrivateKey: P256.Signing.PrivateKey
    private let intermediateCA: Certificate
    private let intermediateCAPrivateKey: P256.Signing.PrivateKey

    init() {
        do {
            let rootPrivateKey = P256.Signing.PrivateKey()
            let rootSubject = try DistinguishedName {
                CommonName("C2PA Test Root CA")
                OrganizationName("C2PA Signing Server")
                OrganizationalUnitName("Certificate Authority")
                CountryName("US")
                StateOrProvinceName("California")
                LocalityName("San Francisco")
            }

            let rootExtensions = try Certificate.Extensions {
                BasicConstraints.isCertificateAuthority(maxPathLength: 1)
                KeyUsage(keyCertSign: true, cRLSign: true)
                SubjectKeyIdentifier(hash: Certificate.PublicKey(rootPrivateKey.publicKey))
            }

            let rootCert = try Certificate(
                version: .v3,
                serialNumber: Certificate.SerialNumber(),
                publicKey: Certificate.PublicKey(rootPrivateKey.publicKey),
                notValidBefore: Date().addingTimeInterval(-5 * 60),  // 5 minutes ago for clock skew
                notValidAfter: Date().addingTimeInterval(10 * 365 * 24 * 60 * 60),
                issuer: rootSubject,
                subject: rootSubject,
                signatureAlgorithm: .ecdsaWithSHA256,
                extensions: rootExtensions,
                issuerPrivateKey: Certificate.PrivateKey(rootPrivateKey)
            )

            let intermediatePrivateKey = P256.Signing.PrivateKey()
            let intermediateSubject = try DistinguishedName {
                CommonName("C2PA Test Intermediate CA")
                OrganizationName("C2PA Signing Server")
                OrganizationalUnitName("Certificate Authority")
                CountryName("US")
                StateOrProvinceName("California")
                LocalityName("San Francisco")
            }

            let rootPublicKeyData = rootPrivateKey.publicKey.x963Representation
            let rootKeyIdentifier = ArraySlice(Insecure.SHA1.hash(data: rootPublicKeyData))

            let intermediateExtensions = try Certificate.Extensions {
                BasicConstraints.isCertificateAuthority(maxPathLength: 0)
                KeyUsage(keyCertSign: true, cRLSign: true)
                SubjectKeyIdentifier(hash: Certificate.PublicKey(intermediatePrivateKey.publicKey))
                AuthorityKeyIdentifier(
                    keyIdentifier: rootKeyIdentifier
                )
            }

            let intermediateCert = try Certificate(
                version: .v3,
                serialNumber: Certificate.SerialNumber(),
                publicKey: Certificate.PublicKey(intermediatePrivateKey.publicKey),
                notValidBefore: Date().addingTimeInterval(-5 * 60),
                notValidAfter: Date().addingTimeInterval(5 * 365 * 24 * 60 * 60),
                issuer: rootCert.subject,
                subject: intermediateSubject,
                signatureAlgorithm: .ecdsaWithSHA256,
                extensions: intermediateExtensions,
                issuerPrivateKey: Certificate.PrivateKey(rootPrivateKey)
            )

            self.rootCA = rootCert
            self.rootCAPrivateKey = rootPrivateKey
            self.intermediateCA = intermediateCert
            self.intermediateCAPrivateKey = intermediatePrivateKey
        } catch {
            fatalError("Failed to initialize CA certificates: \(error)")
        }
    }

    func signCSR(_ csrPEM: String) async throws -> SignedCertificateResponse {
        let pemDocument = try PEMDocument(pemString: csrPEM)
        let csr = try X509.CertificateSigningRequest(derEncoded: pemDocument.derBytes)

        let extensions = try Certificate.Extensions {
            BasicConstraints.notCertificateAuthority
            KeyUsage(digitalSignature: true)
            try ExtendedKeyUsage([.emailProtection])
            SubjectKeyIdentifier(hash: csr.publicKey)
            AuthorityKeyIdentifier(
                keyIdentifier: ArraySlice(
                    Insecure.SHA1.hash(data: intermediateCAPrivateKey.publicKey.x963Representation))
            )
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: csr.publicKey,
            notValidBefore: Date().addingTimeInterval(-60),
            notValidAfter: Date().addingTimeInterval(365 * 24 * 60 * 60),
            issuer: intermediateCA.subject,
            subject: csr.subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(intermediateCAPrivateKey)
        )

        let certificateChain = try [
            certificate.serializeAsPEM().pemString,
            intermediateCA.serializeAsPEM().pemString,
            rootCA.serializeAsPEM().pemString
        ].joined(separator: "\n")

        return SignedCertificateResponse(
            certificate_id: UUID().uuidString,
            certificate_chain: certificateChain,
            expires_at: certificate.notValidAfter,
            serial_number: String(describing: certificate.serialNumber)
        )
    }
}
