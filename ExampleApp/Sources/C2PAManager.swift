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
import CoreLocation
import Crypto
import Foundation
import ImageIO
import OSLog
import Security
import UIKit

@MainActor
final class C2PAManager: ObservableObject {
    static let shared = C2PAManager()

    @Published var isProcessing = false
    @Published var lastError: String?

    var defaultCertificateData: Data?
    var defaultPrivateKeyData: Data?

    private init() {
        loadDefaultCertificates()

        // Listen for signing mode changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(signingModeChanged),
            name: Notification.Name("SigningModeChanged"),
            object: nil
        )
    }

    @objc private func signingModeChanged() {
        os_log("Signing mode changed", log: Logger.general, type: .info)
    }

    private func loadDefaultCertificates() {
        if let certURL = Bundle.main.url(forResource: "default_certs", withExtension: "pem"),
            let keyURL = Bundle.main.url(forResource: "default_private", withExtension: "key")
        {
            do {
                defaultCertificateData = try Data(contentsOf: certURL)
                defaultPrivateKeyData = try Data(contentsOf: keyURL)
                os_log(
                    "Default certificates loaded successfully", log: Logger.certificate, type: .info
                )
            } catch {
                os_log(
                    "Error loading default certificates: %{public}@", log: Logger.error,
                    type: .error, error.localizedDescription)
            }
        }
    }

    // MARK: - Main Public Interface

    func signAndSaveImage(
        _ image: UIImage, location: CLLocation? = nil,
        completion: @escaping (Bool, String?, Data?) -> Void
    ) {
        isProcessing = true
        lastError = nil

        Task {
            do {
                guard
                    let imageData = image.jpegData(
                        compressionQuality: Constants.Image.jpegCompressionQuality)
                else {
                    await MainActor.run {
                        self.isProcessing = false
                        let error = C2PAManagerError.imageConversionFailed
                        self.lastError = error.localizedDescription
                        completion(false, self.lastError, nil)
                    }
                    return
                }

                os_log(
                    "Original image data size: %d bytes", log: Logger.general, type: .debug,
                    imageData.count)

                let signingModeString =
                    UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.signingMode)
                    ?? "Default"
                let signingMode = SigningMode(rawValue: signingModeString) ?? .defaultMode

                os_log(
                    "Using signing mode: %{public}@", log: Logger.signing, type: .info,
                    signingMode.rawValue)

                // Use the unified signing method
                let signedImageData = try await signImageData(
                    imageData,
                    signingMode: signingMode,
                    location: location
                )

                os_log(
                    "Signed image data size: %d bytes", log: Logger.signing, type: .debug,
                    signedImageData.count)
                os_log(
                    "Size difference: %d bytes", log: Logger.signing, type: .debug,
                    signedImageData.count - imageData.count)

                let savedURL = try PhotoStorageManager.shared.saveSignedPhoto(signedImageData)
                os_log(
                    "Saved signed photo with C2PA credentials to app storage: %{public}@",
                    log: Logger.storage, type: .info, savedURL.lastPathComponent)

                // Comprehensive C2PA verification
                os_log("Starting C2PA verification of saved file...", log: Logger.verification, type: .info)
                do {
                    // Read the file back and verify C2PA credentials
                    let manifestJSON = try C2PA.readFile(at: savedURL)

                    os_log("C2PA VERIFICATION SUCCESS", log: Logger.verification, type: .info)
                    os_log("Manifest JSON loaded successfully", log: Logger.verification, type: .info)

                    // Log raw JSON length for debugging
                    os_log(
                        "Manifest JSON length: %d characters", log: Logger.verification, type: .debug,
                        manifestJSON.count)

                    // Parse the JSON to inspect the manifest
                    if let jsonData = manifestJSON.data(using: .utf8),
                        let manifestStore = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                    {

                        // Check for active manifest
                        if let activeManifest = manifestStore["active_manifest"] as? [String: Any] {
                            os_log("Active manifest found", log: Logger.verification, type: .info)

                            // Log claim generator
                            if let claimGenerator = activeManifest["claim_generator"] as? String {
                                os_log(
                                    "Claim generator: %{public}@",
                                    log: Logger.verification, type: .info, claimGenerator)

                                // Check if this is using test mode
                                if claimGenerator.contains("Example") || claimGenerator.contains("Test") {
                                    os_log(
                                        "WARNING: Using test/example claim generator - will not validate on public verifiers",
                                        log: Logger.verification, type: .error)
                                }
                            }

                            // Log title
                            if let title = activeManifest["title"] as? String {
                                os_log(
                                    "Title: %{public}@",
                                    log: Logger.verification, type: .info, title)
                            }

                            // Check signature info
                            if let signatureInfo = activeManifest["signature_info"] as? [String: Any] {
                                os_log("Signature info present", log: Logger.verification, type: .info)

                                if let alg = signatureInfo["alg"] as? String {
                                    os_log(
                                        "Algorithm: %{public}@",
                                        log: Logger.verification, type: .info, alg)
                                }

                                if let issuer = signatureInfo["issuer"] as? String {
                                    os_log(
                                        "Certificate issuer: %{public}@",
                                        log: Logger.verification, type: .info, issuer)
                                }

                                if let time = signatureInfo["time"] as? String {
                                    os_log(
                                        "Signature time: %{public}@",
                                        log: Logger.verification, type: .info, time)
                                }
                            } else {
                                os_log(
                                    "No signature info found in manifest",
                                    log: Logger.verification, type: .error)
                            }

                            // Check assertions
                            if let assertions = activeManifest["assertions"] as? [[String: Any]] {
                                os_log(
                                    "Found %d assertions",
                                    log: Logger.verification, type: .info, assertions.count)

                                for assertion in assertions {
                                    if let label = assertion["label"] as? String {
                                        os_log(
                                            "  - Assertion: %{public}@",
                                            log: Logger.verification, type: .debug, label)
                                    }
                                }
                            }

                            // Check instance ID
                            if let instanceID = activeManifest["instance_id"] as? String {
                                os_log(
                                    "Instance ID: %{public}@",
                                    log: Logger.verification, type: .debug, instanceID)
                            }

                        } else {
                            os_log(
                                "No active manifest found in manifest store",
                                log: Logger.verification, type: .error)
                        }

                        // Check manifests
                        if let manifests = manifestStore["manifests"] as? [String: Any] {
                            os_log(
                                "Total manifests in store: %d",
                                log: Logger.verification, type: .info, manifests.count)
                        }

                        // Check validation status if present
                        if let validationStatus = manifestStore["validation_status"] as? [[String: Any]] {
                            os_log(
                                "Validation status entries: %d",
                                log: Logger.verification, type: .info, validationStatus.count)

                            for status in validationStatus {
                                if let code = status["code"] as? String {
                                    if code.contains("error") || code.contains("failure") {
                                        os_log(
                                            "Validation error: %{public}@",
                                            log: Logger.verification, type: .error, code)
                                    } else {
                                        os_log(
                                            "Validation status: %{public}@",
                                            log: Logger.verification, type: .info, code)
                                    }
                                }
                            }
                        }

                    } else {
                        // If we can't parse the JSON, just log it as raw
                        os_log(
                            "Raw manifest JSON (first 500 chars): %{public}@",
                            log: Logger.verification, type: .debug,
                            String(manifestJSON.prefix(500)))
                    }

                } catch {
                    os_log("C2PA VERIFICATION FAILED", log: Logger.verification, type: .error)
                    os_log(
                        "Error: %{public}@", log: Logger.verification, type: .error,
                        error.localizedDescription)

                    // Try to provide more specific error information
                    if let c2paError = error as? C2PAError {
                        os_log(
                            "C2PA Error details: %{public}@",
                            log: Logger.verification, type: .error,
                            String(describing: c2paError))
                    }

                    // Still save the file even if verification fails
                    os_log(
                        "File saved but C2PA verification failed - credentials may be malformed",
                        log: Logger.verification, type: .error)
                }


                // Return the signed data and saved URL
                let fileName = savedURL.lastPathComponent
                let imageDataCopy = signedImageData

                if signingMode == .secureEnclave {
                    // Wait 1 second to let Face ID UI complete its animation
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }

                await MainActor.run {
                    self.isProcessing = false
                    completion(true, fileName, imageDataCopy)
                }
            } catch {
                os_log(
                    "Error saving image: %{public}@", log: Logger.error, type: .error,
                    error.localizedDescription)
                await MainActor.run {
                    self.isProcessing = false
                    self.lastError = error.localizedDescription
                    completion(false, error.localizedDescription, nil)
                }
            }
        }
    }

    // MARK: - Unified Signing Implementation

    /// Sign image data using the configured signing mode
    func signImageData(
        _ imageData: Data,
        signingMode: SigningMode,
        location: CLLocation? = nil
    ) async throws -> Data {
        os_log(
            "Signing with mode: %{public}@", log: Logger.signing, type: .info,
            signingMode.rawValue)

        // Create manifest JSON with signing mode metadata
        let manifestJSON = try createManifestJSON(location: location, signingMode: signingMode)

        // Create temporary files for image processing
        let tempDir = FileManager.default.temporaryDirectory
        let inputURL = tempDir.appendingPathComponent("input_\(UUID().uuidString).jpg")
        let outputURL = tempDir.appendingPathComponent("output_\(UUID().uuidString).jpg")

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        try imageData.write(to: inputURL)

        // Create the appropriate signer based on the mode
        os_log("Creating signer for mode: %{public}@", log: Logger.signing, type: .info, signingMode.rawValue)
        let signer: Signer
        do {
            signer = try await createSigner(for: signingMode)
            os_log("Signer created successfully", log: Logger.signing, type: .info)
        } catch {
            os_log("Failed to create signer: %{public}@", log: Logger.signing, type: .error, String(describing: error))
            throw error
        }

        // Sign the image using the Library's Builder
        os_log("Creating Builder with manifest", log: Logger.signing, type: .info)
        let builder: Builder
        do {
            builder = try Builder(manifestJSON: manifestJSON)
            os_log("Builder created successfully", log: Logger.signing, type: .info)
        } catch {
            os_log("Failed to create Builder: %{public}@", log: Logger.signing, type: .error, String(describing: error))
            throw error
        }

        // Check input file before signing
        let inputFileSize = try FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? Int64 ?? 0
        os_log(
            "Input file size: %lld bytes at %{public}@", log: Logger.signing, type: .debug, inputFileSize, inputURL.path
        )

        os_log("Creating source and destination streams", log: Logger.signing, type: .info)
        let sourceStream = try Stream(readFrom: inputURL)
        let destStream = try Stream(writeTo: outputURL)

        os_log("Starting builder.sign operation", log: Logger.signing, type: .info)
        os_log("  Format: image/jpeg", log: Logger.signing, type: .debug)
        os_log("  Input: %{public}@", log: Logger.signing, type: .debug, inputURL.lastPathComponent)
        os_log("  Output: %{public}@", log: Logger.signing, type: .debug, outputURL.lastPathComponent)

        do {
            try builder.sign(
                format: "image/jpeg",
                source: sourceStream,
                destination: destStream,
                signer: signer
            )
            os_log("builder.sign completed successfully", log: Logger.signing, type: .info)
        } catch {
            os_log(
                "builder.sign failed with error: %{public}@", log: Logger.signing, type: .error,
                String(describing: error))

            // Check if it's a C2PA error
            if let c2paError = error as? C2PAError {
                os_log("C2PA Error type: %{public}@", log: Logger.signing, type: .error, String(describing: c2paError))
            }

            throw error
        }

        // Ensure streams are released before reading the file
        // The streams will be deallocated when they go out of scope here
        _ = sourceStream  // Keep reference to prevent early deallocation
        _ = destStream  // Keep reference to prevent early deallocation

        // Check if output file exists and has content
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: outputURL.path) else {
            os_log("Output file does not exist at: %{public}@", log: Logger.signing, type: .error, outputURL.path)
            throw C2PAManagerError.signingFailed("Output file was not created")
        }

        let attributes = try fileManager.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        os_log("Output file size: %lld bytes", log: Logger.signing, type: .debug, fileSize)

        guard fileSize > 0 else {
            os_log("Output file is empty", log: Logger.signing, type: .error)
            throw C2PAManagerError.signingFailed("Output file is empty")
        }

        // Read the signed image data
        let signedData = try Data(contentsOf: outputURL)

        os_log(
            "Successfully signed image. Original: %d bytes, Signed: %d bytes",
            log: Logger.signing, type: .info, imageData.count, signedData.count)

        return signedData
    }

    /// Create the appropriate Signer instance based on the signing mode
    private func createSigner(for mode: SigningMode) async throws -> Signer {
        switch mode {
        case .defaultMode:
            return try await createDefaultSigner()

        case .keychain:
            return try await createKeychainSigner()

        case .secureEnclave:
            return try await createSecureEnclaveSigner()

        case .custom:
            return try await createCustomSigner()

        case .remote:
            return try await createRemoteSigner()
        }
    }

    // MARK: - Default Mode Signer

    private func createDefaultSigner() async throws -> Signer {
        guard let certData = defaultCertificateData,
            let keyData = defaultPrivateKeyData,
            let certPEM = String(data: certData, encoding: .utf8),
            let keyPEM = String(data: keyData, encoding: .utf8)
        else {
            throw C2PAManagerError.certificatesNotAvailable
        }

        os_log("Creating default signer with included test certificates", log: Logger.signing, type: .info)

        return try Signer(
            certsPEM: certPEM,
            privateKeyPEM: keyPEM,
            algorithm: .es256,
            tsa: Constants.Signing.defaultTSA
        )
    }

    // MARK: - Keychain Signer

    private func createKeychainSigner() async throws -> Signer {
        let keyTag = Constants.Keychain.keychainPrivateKeyTag
        let certChainKey = keyTag + Constants.Keychain.certChainSuffix

        // Try to get existing certificate chain
        let certChainPEM = try await getOrCreateKeychainCertificate(keyTag: keyTag, certChainKey: certChainKey)

        os_log("Creating keychain signer with tag: %{public}@", log: Logger.signing, type: .info, keyTag)

        return try Signer(
            algorithm: .es256,
            certificateChainPEM: certChainPEM,
            tsa: Constants.Signing.defaultTSA,
            keychainKeyTag: keyTag
        )
    }

    private func getOrCreateKeychainCertificate(keyTag: String, certChainKey: String) async throws -> String {
        // Check if certificate chain already exists
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certChainKey,
            kSecReturnData as String: true
        ]

        var certItem: CFTypeRef?
        let certStatus = SecItemCopyMatching(certQuery as CFDictionary, &certItem)

        if certStatus == errSecSuccess,
            let certData = certItem as? Data,
            let certString = String(data: certData, encoding: .utf8)
        {
            os_log("Found existing certificate chain for keychain key", log: Logger.certificate, type: .info)
            return certString
        }

        // Certificate doesn't exist, create new one
        os_log("Creating new certificate chain for keychain key", log: Logger.certificate, type: .info)

        // First ensure the key exists or create it
        let privateKey = try ensureKeychainKey(tag: keyTag)

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw C2PAManagerError.privateKeyExportFailed
        }

        let config = CertificateManager.CertificateConfig(
            commonName: "C2PA Keychain User",
            organization: "C2PA Example",
            organizationalUnit: "Mobile",
            country: "US",
            state: "CA",
            locality: "San Francisco",
            emailAddress: "keychain@example.com"
        )

        let certChain = try CertificateManager.createSelfSignedCertificateChain(
            for: publicKey,
            config: config
        )

        // Save certificate chain for future use
        let certChainData = certChain.data(using: .utf8)!
        let saveQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certChainKey,
            kSecValueData as String: certChainData
        ]

        SecItemDelete(saveQuery as CFDictionary)
        let saveStatus = SecItemAdd(saveQuery as CFDictionary, nil)

        if saveStatus != errSecSuccess {
            os_log(
                "Warning: Could not cache certificate chain: %d", log: Logger.certificate,
                type: .error, saveStatus)
        }

        return certChain
    }

    private func ensureKeychainKey(tag: String) throws -> SecKey {
        // Try to get existing key
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let key = item as! SecKey? {
            os_log("Found existing keychain key", log: Logger.signing, type: .info)
            return key
        }

        // Create new key
        os_log("Creating new keychain key", log: Logger.signing, type: .info)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag.data(using: .utf8)!
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw C2PAManagerError.keychainKeyCreationFailed(error.localizedDescription)
            }
            throw C2PAManagerError.keychainKeyCreationFailed("Unknown error")
        }

        return privateKey
    }

    // MARK: - Secure Enclave Signer

    private func createSecureEnclaveSigner() async throws -> Signer {
        let keyTag = Constants.Keychain.secureEnclaveKeyTag
        let certChainKey = keyTag + Constants.Keychain.certChainSuffix

        // Get or create certificate chain for Secure Enclave key
        let certChainPEM = try await getOrCreateSecureEnclaveCertificate(keyTag: keyTag, certChainKey: certChainKey)

        os_log("Creating Secure Enclave signer", log: Logger.signing, type: .info)

        let config = SecureEnclaveSignerConfig(
            keyTag: keyTag,
            accessControl: [.privateKeyUsage]
        )

        return try Signer(
            algorithm: .es256,
            certificateChainPEM: certChainPEM,
            tsa: Constants.Signing.defaultTSA,
            secureEnclaveConfig: config
        )
    }

    private func getOrCreateSecureEnclaveCertificate(keyTag: String, certChainKey: String) async throws -> String {
        // Check if certificate chain already exists
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certChainKey,
            kSecReturnData as String: true
        ]

        var certItem: CFTypeRef?
        let certStatus = SecItemCopyMatching(certQuery as CFDictionary, &certItem)

        if certStatus == errSecSuccess,
            let certData = certItem as? Data,
            let certString = String(data: certData, encoding: .utf8)
        {
            os_log("Found existing certificate chain for Secure Enclave key", log: Logger.certificate, type: .info)
            os_log("Using cached certificate chain from keychain", log: Logger.certificate, type: .info)

            // Log the cached certificate details
            os_log("=== CACHED CERTIFICATE CHAIN (PEM) ===", log: Logger.certificate, type: .info)
            os_log("%{public}@", log: Logger.certificate, type: .info, certString)
            os_log("=== END CACHED CERTIFICATE CHAIN ===", log: Logger.certificate, type: .info)
            logCertificateDetails(certString)

            return certString
        }

        // Certificate doesn't exist, create new one
        os_log("Creating new certificate chain for Secure Enclave key", log: Logger.certificate, type: .info)

        // Ensure Secure Enclave key exists (will be created by SecureEnclaveSigner if needed)
        let config = SecureEnclaveSignerConfig(
            keyTag: keyTag,
            accessControl: [.privateKeyUsage]
        )

        // Create the key if it doesn't exist
        _ = try Signer.createSecureEnclaveKey(config: config)

        // Generate CSR for Secure Enclave key
        let certConfig = CertificateManager.CertificateConfig(
            commonName: "C2PA Secure Enclave User",
            organization: "C2PA Example",
            organizationalUnit: "Mobile SE",
            country: "US",
            state: "CA",
            locality: "San Francisco",
            emailAddress: "se@example.com"
        )

        // Generate CSR using the key tag
        let csrPEM = try CertificateManager.createCSR(
            keyTag: keyTag,
            config: certConfig
        )

        // Submit CSR to signing server for enrollment
        let certChain = try await enrollCertificate(csrPEM: csrPEM)

        // Save certificate chain for future use
        let certChainData = certChain.data(using: .utf8)!
        let saveQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certChainKey,
            kSecValueData as String: certChainData
        ]

        SecItemDelete(saveQuery as CFDictionary)
        let saveStatus = SecItemAdd(saveQuery as CFDictionary, nil)

        if saveStatus != errSecSuccess {
            os_log(
                "Warning: Could not cache SE certificate chain: %d", log: Logger.certificate,
                type: .error, saveStatus)
        }

        return certChain
    }

    // MARK: - Custom Signer

    private func createCustomSigner() async throws -> Signer {
        let keyTag = Constants.Keychain.customPrivateKeyTag

        // First ensure the custom private key is imported into the keychain as a SecKey
        try await ensureCustomKeyInKeychain(keyTag: keyTag)

        // Get the certificate chain
        let certChainPEM = try await getCustomCertificateChain(keyTag: keyTag)

        os_log("Creating custom signer using keychain with tag: %{public}@", log: Logger.signing, type: .info, keyTag)

        // Use the KeychainSigner with the custom key tag
        return try Signer(
            algorithm: .es256,
            certificateChainPEM: certChainPEM,
            tsa: Constants.Signing.defaultTSA,
            keychainKeyTag: keyTag
        )
    }

    private func ensureCustomKeyInKeychain(keyTag: String) async throws {
        // Check if the key is already in keychain as a SecKey
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(keyQuery as CFDictionary, &item)

        if status == errSecSuccess, item != nil {
            os_log("Custom key already in keychain", log: Logger.signing, type: .info)
            return
        }

        // Key not found, need to import from the stored PEM
        let (_, keyData) = try getCustomCertificate()

        guard let keyPEM = String(data: keyData, encoding: .utf8) else {
            throw C2PAManagerError.invalidCertificateFormat
        }

        // Import the PEM private key into keychain
        try importPrivateKeyToKeychain(pemKey: keyPEM, keyTag: keyTag)
    }

    private func importPrivateKeyToKeychain(pemKey: String, keyTag: String) throws {
        // Remove PEM headers/footers and decode base64
        let lines = pemKey.components(separatedBy: .newlines)
        let base64Key =
            lines
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()

        guard let keyData = Data(base64Encoded: base64Key) else {
            throw C2PAManagerError.invalidCertificateFormat
        }

        // Import as EC private key
        let keyDict: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, keyDict as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw C2PAManagerError.keychainKeyCreationFailed("Failed to import key: \(error)")
            }
            throw C2PAManagerError.keychainKeyCreationFailed("Failed to import private key")
        }

        // Store in keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecValueRef as String: privateKey,
            kSecAttrIsPermanent as String: true
        ]

        // Delete any existing key
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw C2PAManagerError.keychainKeyCreationFailed("Failed to store key in keychain: \(addStatus)")
        }

        os_log("Successfully imported custom private key to keychain", log: Logger.signing, type: .info)
    }

    private func getCustomCertificateChain(keyTag: String) async throws -> String {
        let certChainKey = keyTag + Constants.Keychain.certChainSuffix

        // Try to get the certificate chain from keychain
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certChainKey,
            kSecReturnData as String: true
        ]

        var certItem: CFTypeRef?
        let certStatus = SecItemCopyMatching(certQuery as CFDictionary, &certItem)

        if certStatus == errSecSuccess,
            let certData = certItem as? Data,
            let certString = String(data: certData, encoding: .utf8)
        {
            return certString
        }

        // If not found, get from the old storage location
        let (certData, _) = try getCustomCertificate()
        guard let certPEM = String(data: certData, encoding: .utf8) else {
            throw C2PAManagerError.invalidCertificateFormat
        }

        // Save for future use
        let saveQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: certChainKey,
            kSecValueData as String: certData
        ]

        SecItemDelete(saveQuery as CFDictionary)
        _ = SecItemAdd(saveQuery as CFDictionary, nil)

        return certPEM
    }

    // MARK: - Certificate Logging

    private func logCertificateDetails(_ certChainPEM: String) {
        os_log("=== PARSING CERTIFICATE CHAIN ===", log: Logger.certificate, type: .info)

        // Split the PEM chain into individual certificates
        let certPattern = "-----BEGIN CERTIFICATE-----[\\s\\S]*?-----END CERTIFICATE-----"
        guard let regex = try? NSRegularExpression(pattern: certPattern, options: []) else {
            os_log("Failed to create regex for certificate parsing", log: Logger.certificate, type: .error)
            return
        }

        let matches = regex.matches(
            in: certChainPEM, options: [], range: NSRange(location: 0, length: certChainPEM.count))

        os_log("Found %d certificate(s) in chain", log: Logger.certificate, type: .info, matches.count)

        for (index, match) in matches.enumerated() {
            guard let range = Range(match.range, in: certChainPEM) else { continue }
            let certPEM = String(certChainPEM[range])

            os_log("=== CERTIFICATE %d ===", log: Logger.certificate, type: .info, index + 1)

            // Extract the base64 content between the headers
            let lines = certPEM.components(separatedBy: .newlines)
            let base64Lines = lines.filter {
                !$0.contains("BEGIN CERTIFICATE") && !$0.contains("END CERTIFICATE") && !$0.isEmpty
            }
            let base64String = base64Lines.joined()

            guard let certData = Data(base64Encoded: base64String) else {
                os_log("Failed to decode base64 for certificate %d", log: Logger.certificate, type: .error, index + 1)
                continue
            }

            // Try to parse with SecCertificateCreateWithData
            guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
                os_log(
                    "Failed to parse certificate %d with SecCertificate", log: Logger.certificate, type: .error,
                    index + 1)
                continue
            }

            // Get certificate summary
            if let summary = SecCertificateCopySubjectSummary(certificate) as String? {
                os_log("  Subject: %{public}@", log: Logger.certificate, type: .info, summary)
            }

            // Try to get more details using the certificate data
            logCertificateDetailsFromDER(certData, index: index + 1)

            os_log("=== END CERTIFICATE %d ===", log: Logger.certificate, type: .info, index + 1)
        }

        os_log("=== END PARSING CERTIFICATE CHAIN ===", log: Logger.certificate, type: .info)
    }

    private func logCertificateDetailsFromDER(_ certData: Data, index: Int) {
        // Log the certificate size
        os_log("  Size: %d bytes", log: Logger.certificate, type: .info, certData.count)

        // Try to extract basic fields from the DER structure
        // This is a simplified parser - for production, use a proper X.509 library

        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            return
        }

        // Get serial number
        if let serialNumber = SecCertificateCopySerialNumberData(certificate, nil) as Data? {
            let serialHex = serialNumber.map { String(format: "%02x", $0) }.joined()
            os_log("  Serial Number: %{public}@", log: Logger.certificate, type: .info, serialHex)
        }

        // Try to get the public key to verify it matches our Secure Enclave key
        if let publicKey = SecCertificateCopyKey(certificate) {
            var error: Unmanaged<CFError>?
            if let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? {
                let keyHex = publicKeyData.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " ")
                os_log("  Public Key (first 32 bytes): %{public}@", log: Logger.certificate, type: .info, keyHex)
                os_log("  Public Key Size: %d bytes", log: Logger.certificate, type: .info, publicKeyData.count)
            } else if let error = error?.takeRetainedValue() {
                os_log(
                    "  Could not extract public key: %{public}@", log: Logger.certificate, type: .debug,
                    error.localizedDescription)
            }
        }

        // Parse basic X.509 fields manually from DER
        // This is a simplified check - just looking for common patterns
        if let utf8Data = String(data: certData, encoding: .utf8) {
            // Try to find CN (Common Name) patterns
            if let cnRange = utf8Data.range(of: "CN=") {
                let startIndex = cnRange.upperBound
                let endIndex = utf8Data.index(
                    startIndex, offsetBy: min(50, utf8Data.distance(from: startIndex, to: utf8Data.endIndex)))
                let cnValue = String(utf8Data[startIndex..<endIndex])
                os_log("  Possible CN in cert: %{public}@", log: Logger.certificate, type: .debug, cnValue)
            }
        }

        // Check if this looks like a self-signed certificate
        let certDescription = SecCertificateCopySubjectSummary(certificate) as String? ?? "Unknown"
        os_log("  Certificate Summary: %{public}@", log: Logger.certificate, type: .info, certDescription)

        // Log first 200 bytes of hex for debugging
        let hexPrefix = certData.prefix(200).map { String(format: "%02x", $0) }.joined(separator: " ")
        os_log("  DER hex (first 200 bytes): %{public}@", log: Logger.certificate, type: .debug, hexPrefix)
    }

    // MARK: - Certificate Enrollment

    private func enrollCertificate(csrPEM: String) async throws -> String {
        let serverURL = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.remoteSigningURL) ?? ""
        let bearerToken = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.remoteBearerToken) ?? ""

        guard !serverURL.isEmpty else {
            throw C2PAManagerError.remoteSigningNotConfigured
        }

        guard let url = URL(string: "\(serverURL)/api/v1/certificates/sign") else {
            throw C2PAManagerError.invalidURL
        }

        os_log("Enrolling certificate with server: %{public}@", log: Logger.certificate, type: .info, serverURL)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        struct EnrollmentRequest: Codable {
            let csr: String
            let metadata: EnrollmentMetadata?
        }

        struct EnrollmentMetadata: Codable {
            let device_id: String?
            let app_version: String?
        }

        struct EnrollmentResponse: Codable {
            let certificate_id: String
            let certificate_chain: String
            let expires_at: Date
            let serial_number: String
        }

        let enrollmentRequest = EnrollmentRequest(
            csr: csrPEM,
            metadata: EnrollmentMetadata(
                device_id: UIDevice.current.identifierForVendor?.uuidString,
                app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            )
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(enrollmentRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw C2PAManagerError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw C2PAManagerError.networkError("Enrollment failed: \(errorMessage)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let enrollmentResponse = try decoder.decode(EnrollmentResponse.self, from: data)

        os_log(
            "Certificate enrolled successfully. Certificate ID: %{public}@",
            log: Logger.certificate, type: .info, enrollmentResponse.certificate_id)

        // Log the raw certificate chain
        os_log("=== RAW CERTIFICATE CHAIN (PEM) ===", log: Logger.certificate, type: .info)
        os_log("%{public}@", log: Logger.certificate, type: .info, enrollmentResponse.certificate_chain)
        os_log("=== END RAW CERTIFICATE CHAIN ===", log: Logger.certificate, type: .info)

        // Parse and log certificate details
        logCertificateDetails(enrollmentResponse.certificate_chain)

        return enrollmentResponse.certificate_chain
    }

    // MARK: - Remote Service Signer

    private func createRemoteSigner() async throws -> Signer {
        let remoteURL = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.remoteSigningURL) ?? ""
        let bearerToken = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.remoteBearerToken)

        guard !remoteURL.isEmpty else {
            throw C2PAManagerError.remoteSigningNotConfigured
        }

        // Construct the full configuration URL if not already a full path
        let configurationURLString: String
        if remoteURL.contains("/api/v1/c2pa/configuration") {
            configurationURLString = remoteURL
        } else {
            configurationURLString = "\(remoteURL.trimmingCharacters(in: .init(charactersIn: "/")))/api/v1/c2pa/configuration"
        }

        guard let configurationEndpoint = URL(string: configurationURLString) else {
            throw C2PAManagerError.remoteSigningNotConfigured
        }

        os_log(
            "Creating remote service signer with configuration URL: %{public}@", log: Logger.signing, type: .info,
            configurationURLString)

        let customHeaders = [
            "X-Client-Version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "X-Client-Platform": "iOS-\(UIDevice.current.systemVersion)"
        ]

        let webServiceSigner = WebServiceSigner(
            configurationEndpoint: configurationEndpoint,
            bearerToken: bearerToken,
            headers: customHeaders
        )

        os_log("Fetching configuration and creating signer from remote service", log: Logger.signing, type: .info)

        do {
            let signer = try await webServiceSigner.createSigner()
            os_log("Successfully created remote service signer", log: Logger.signing, type: .info)
            return signer
        } catch {
            os_log(
                "Failed to create remote signer: %{public}@", log: Logger.signing, type: .error,
                error.localizedDescription)
            throw C2PAManagerError.remoteServiceError(error.localizedDescription)
        }
    }

    // MARK: - Manifest Creation

    private func createManifestJSON(location: CLLocation? = nil, signingMode: SigningMode? = nil) throws -> String {
        // Get the signing mode if not provided
        let mode =
            signingMode
            ?? {
                let signingModeString =
                    UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.signingMode) ?? "Default"
                return SigningMode(rawValue: signingModeString) ?? .defaultMode
            }()

        // Create distinct metadata for each signing mode
        let claimGenerator: String
        let title: String
        let signingMethodDescription: String
        let signingMethodColor: String  // Visual indicator

        switch mode {
        case .defaultMode:
            claimGenerator = "C2PA iOS Example/1.0.0 [DEFAULT TEST CERT]"
            title = "DEFAULT MODE - Test Certificate"
            signingMethodDescription = "Signed with included test certificate (for development only)"
            signingMethodColor = "BLUE"

        case .keychain:
            claimGenerator = "C2PA iOS Example/1.0.0 [KEYCHAIN]"
            title = "KEYCHAIN MODE - Software Key"
            signingMethodDescription = "Signed with software key stored in iOS Keychain"
            signingMethodColor = "GREEN"

        case .secureEnclave:
            claimGenerator = "C2PA iOS Example/1.0.0 [SECURE ENCLAVE]"
            title = "SECURE ENCLAVE - Hardware Security"
            signingMethodDescription = "Signed with hardware-backed key in Secure Enclave"
            signingMethodColor = "YELLOW"

        case .custom:
            claimGenerator = "C2PA iOS Example/1.0.0 [CUSTOM CERT]"
            title = "CUSTOM MODE - User Certificate"
            signingMethodDescription = "Signed with user-provided certificate and private key"
            signingMethodColor = "PURPLE"

        case .remote:
            claimGenerator = "C2PA iOS Example/1.0.0 [REMOTE SERVICE]"
            title = "REMOTE MODE - Web Service"
            signingMethodDescription = "Signed via remote signing service"
            signingMethodColor = "RED"
        }

        var manifest: [String: Any] = [
            "claim_generator": claimGenerator,
            "title": title,
            "assertions": []
        ]

        // Add location assertion if available
        if let location = location {
            let locationAssertion: [String: Any] = [
                "label": "stds.exif",
                "data": [
                    "exif:GPSLatitude": location.coordinate.latitude,
                    "exif:GPSLongitude": location.coordinate.longitude,
                    "exif:GPSAltitude": location.altitude,
                    "exif:GPSTimeStamp": ISO8601DateFormatter().string(from: location.timestamp)
                ]
            ]

            var assertions = manifest["assertions"] as! [[String: Any]]
            assertions.append(locationAssertion)
            manifest["assertions"] = assertions
        }

        // Add creation time assertion with signing method details
        let creationAssertion: [String: Any] = [
            "label": "c2pa.actions",
            "data": [
                "actions": [
                    [
                        "action": "c2pa.created",
                        "when": ISO8601DateFormatter().string(from: Date()),
                        "softwareAgent": claimGenerator,
                        "description": signingMethodDescription
                    ]
                ]
            ]
        ]

        var assertions = manifest["assertions"] as! [[String: Any]]
        assertions.append(creationAssertion)
        manifest["assertions"] = assertions

        // Add custom assertion with signing method metadata
        let signingMethodAssertion: [String: Any] = [
            "label": "org.contentauth.signing_method",
            "data": [
                "method": mode.rawValue,
                "description": signingMethodDescription,
                "color_indicator": signingMethodColor,
                "security_level": getSecurityLevel(for: mode),
                "device_info": [
                    "platform": "iOS",
                    "model": UIDevice.current.model,
                    "os_version": UIDevice.current.systemVersion,
                    "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                ],
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        ]

        assertions.append(signingMethodAssertion)
        manifest["assertions"] = assertions

        let jsonData = try JSONSerialization.data(withJSONObject: manifest)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw C2PAManagerError.manifestCreationFailed
        }

        return jsonString
    }

    // MARK: - Helper Methods

    private func getSecurityLevel(for mode: SigningMode) -> String {
        switch mode {
        case .defaultMode:
            return "TEST_ONLY"
        case .keychain:
            return "SOFTWARE"
        case .secureEnclave:
            return "HARDWARE"
        case .custom:
            return "USER_PROVIDED"
        case .remote:
            return "REMOTE_SERVICE"
        }
    }

    func getCustomCertificate() throws -> (Data, Data) {
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Constants.Keychain.customCertificateKey,
            kSecReturnData as String: true
        ]

        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Constants.Keychain.customPrivateKeyKey,
            kSecReturnData as String: true
        ]

        var certItem: CFTypeRef?
        var keyItem: CFTypeRef?

        let certStatus = SecItemCopyMatching(certQuery as CFDictionary, &certItem)
        let keyStatus = SecItemCopyMatching(keyQuery as CFDictionary, &keyItem)

        guard certStatus == errSecSuccess,
            let certData = certItem as? Data,
            keyStatus == errSecSuccess,
            let keyData = keyItem as? Data
        else {
            throw C2PAManagerError.customCertificatesNotFound
        }

        return (certData, keyData)
    }

}

// MARK: - Error Definition

enum C2PAManagerError: LocalizedError {
    case imageConversionFailed
    case certificatesNotAvailable
    case invalidCertificateFormat

    case keychainKeyNotFound(String)
    case invalidCertificateChain
    case privateKeyExportFailed
    case secureEnclaveNotSupported
    case customCertificatesNotFound
    case remoteSigningNotConfigured
    case invalidRemoteURL
    case remoteCertificateFetchFailed
    case remoteServiceError(String)
    case manifestCreationFailed
    case keychainKeyCreationFailed(String)
    case secureEnclaveKeyNotFound
    case customError(String)
    case invalidURL
    case signingFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to JPEG"
        case .certificatesNotAvailable:
            return "Default certificates not available"
        case .invalidCertificateFormat:
            return "Invalid certificate or key format"
        case .keychainKeyNotFound(let tag):
            return "Key not found in keychain for tag: \(tag)"
        case .invalidCertificateChain:
            return "Invalid certificate chain format"
        case .privateKeyExportFailed:
            return "Could not export private key"
        case .secureEnclaveNotSupported:
            return "Secure Enclave is not supported on this device"
        case .customCertificatesNotFound:
            return "Custom certificates not found in keychain. Please upload certificates in Settings."
        case .remoteSigningNotConfigured:
            return "Remote signing URL and bearer token not configured. Please configure in Settings."
        case .invalidRemoteURL:
            return "Invalid remote signing URL"
        case .remoteCertificateFetchFailed:
            return "Failed to get certificate from remote service"
        case .remoteServiceError(let error):
            return "Remote service error: \(error)"
        case .manifestCreationFailed:
            return "Failed to create C2PA manifest"
        case .keychainKeyCreationFailed(let reason):
            return "Failed to create keychain key: \(reason)"
        case .secureEnclaveKeyNotFound:
            return "Secure Enclave key not found"
        case .customError(let message):
            return message
        case .invalidURL:
            return "Invalid URL"
        case .signingFailed(let message):
            return "Signing failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Constants Extension

extension Constants {
    enum Signing {
        static let defaultTSA = URL(string: "http://timestamp.digicert.com")
    }
}
