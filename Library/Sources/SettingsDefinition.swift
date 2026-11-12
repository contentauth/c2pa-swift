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
//  SettingsDefinition.swift
//

import Foundation

// MARK: - Top-Level Settings

/// A type-safe representation of the C2PA settings JSON schema.
///
/// Use `C2PASettingsDefinition` to construct settings programmatically with
/// compile-time type checking rather than building raw JSON strings.
///
/// All properties are optional. Only set the values you need; unset properties
/// are omitted from the encoded JSON.
///
/// ## Example
///
/// ```swift
/// let definition = C2PASettingsDefinition(
///     version: 1,
///     signer: .local(LocalSignerSettings(
///         alg: "es256",
///         signCert: certPEM,
///         privateKey: keyPEM,
///         tsaUrl: "http://timestamp.digicert.com"
///     ))
/// )
///
/// let settings = try C2PASettings(definition: definition)
/// ```
///
/// - SeeAlso: ``C2PASettings/init(definition:)``
public struct C2PASettingsDefinition: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case version
        case trust
        case cawgTrust = "cawg_trust"
        case core
        case verify
        case builder
        case signer
        case cawgX509Signer = "cawg_x509_signer"
    }

    /// The settings schema version. Currently `1`.
    public var version: Int?

    /// Trust configuration for manifest verification.
    public var trust: TrustSettings?

    /// CAWG-specific trust configuration.
    public var cawgTrust: TrustSettings?

    /// Core library settings.
    public var core: CoreSettings?

    /// Verification behavior settings.
    public var verify: VerifySettings?

    /// Builder configuration.
    public var builder: BuilderSettingsDefinition?

    /// Signer configuration (local or remote).
    public var signer: SignerSettings?

    /// CAWG X.509 signer configuration.
    ///
    /// Applies only on top of ``signer``: when a context signs with the signer these
    /// settings configure, it also adds a `cawg.identity` assertion. A ``Signer`` passed to
    /// ``C2PAContext/init(settings:signer:onProgress:httpResolver:)`` is used as it is, so
    /// this section is ignored for it.
    public var cawgX509Signer: SignerSettings?

    public init(
        version: Int? = nil,
        trust: TrustSettings? = nil,
        cawgTrust: TrustSettings? = nil,
        core: CoreSettings? = nil,
        verify: VerifySettings? = nil,
        builder: BuilderSettingsDefinition? = nil,
        signer: SignerSettings? = nil,
        cawgX509Signer: SignerSettings? = nil
    ) {
        self.version = version
        self.trust = trust
        self.cawgTrust = cawgTrust
        self.core = core
        self.verify = verify
        self.builder = builder
        self.signer = signer
        self.cawgX509Signer = cawgX509Signer
    }

    /// Decodes a `C2PASettingsDefinition` from a JSON string.
    ///
    /// - Parameter json: A JSON string containing settings.
    /// - Returns: The decoded settings definition.
    /// - Throws: `DecodingError` if the JSON is invalid.
    public static func fromJSON(_ json: String) throws -> C2PASettingsDefinition {
        try C2PAJson.decode(C2PASettingsDefinition.self, from: json)
    }

    /// Encodes this settings definition to a JSON string.
    ///
    /// - Returns: A compact JSON string.
    /// - Throws: `EncodingError` if encoding fails.
    public func toJSON() throws -> String {
        try C2PAJson.encode(self)
    }

    /// Encodes this settings definition to a pretty-printed JSON string.
    ///
    /// - Returns: A formatted JSON string.
    /// - Throws: `EncodingError` if encoding fails.
    public func toPrettyJSON() throws -> String {
        try C2PAJson.encodePretty(self)
    }
}

// MARK: - Trust Settings

/// Trust configuration for manifest verification.
public struct TrustSettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case verifyTrustList = "verify_trust_list"
        case userAnchors = "user_anchors"
        case trustAnchors = "trust_anchors"
        case trustConfig = "trust_config"
        case allowedList = "allowed_list"
    }

    /// Whether to verify against the trust list.
    public var verifyTrustList: Bool?

    /// User-provided trust anchors in PEM format.
    public var userAnchors: String?

    /// Trust anchors in PEM format.
    public var trustAnchors: String?

    /// Trust configuration JSON.
    public var trustConfig: String?

    /// Allowed list of signing credentials.
    public var allowedList: String?

    public init(
        verifyTrustList: Bool? = nil,
        userAnchors: String? = nil,
        trustAnchors: String? = nil,
        trustConfig: String? = nil,
        allowedList: String? = nil
    ) {
        self.verifyTrustList = verifyTrustList
        self.userAnchors = userAnchors
        self.trustAnchors = trustAnchors
        self.trustConfig = trustConfig
        self.allowedList = allowedList
    }
}

// MARK: - Core Settings

/// Core library configuration.
public struct CoreSettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case merkleTreeChunkSizeInKb = "merkle_tree_chunk_size_in_kb"
        case merkleTreeMaxProofs = "merkle_tree_max_proofs"
        case backingStoreMemoryThresholdInMb = "backing_store_memory_threshold_in_mb"
        case decodeIdentityAssertions = "decode_identity_assertions"
        case allowedNetworkHosts = "allowed_network_hosts"
    }

    /// Chunk size for Merkle tree hashing, in kilobytes.
    public var merkleTreeChunkSizeInKb: Int?

    /// Maximum number of Merkle tree proofs.
    public var merkleTreeMaxProofs: Int?

    /// Memory threshold before switching to disk-backed storage, in megabytes.
    public var backingStoreMemoryThresholdInMb: Int?

    /// Whether to decode identity assertions.
    public var decodeIdentityAssertions: Bool?

    /// List of allowed network hosts for remote operations.
    public var allowedNetworkHosts: [String]?

    public init(
        merkleTreeChunkSizeInKb: Int? = nil,
        merkleTreeMaxProofs: Int? = nil,
        backingStoreMemoryThresholdInMb: Int? = nil,
        decodeIdentityAssertions: Bool? = nil,
        allowedNetworkHosts: [String]? = nil
    ) {
        self.merkleTreeChunkSizeInKb = merkleTreeChunkSizeInKb
        self.merkleTreeMaxProofs = merkleTreeMaxProofs
        self.backingStoreMemoryThresholdInMb = backingStoreMemoryThresholdInMb
        self.decodeIdentityAssertions = decodeIdentityAssertions
        self.allowedNetworkHosts = allowedNetworkHosts
    }
}

// MARK: - Verify Settings

/// Verification behavior configuration.
public struct VerifySettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case verifyAfterReading = "verify_after_reading"
        case verifyAfterSign = "verify_after_sign"
        case verifyTrust = "verify_trust"
        case verifyTimestampTrust = "verify_timestamp_trust"
        case ocspFetch = "ocsp_fetch"
        case remoteManifestFetch = "remote_manifest_fetch"
        case skipIngredientConflictResolution = "skip_ingredient_conflict_resolution"
        case strictV1Validation = "strict_v1_validation"
    }

    /// Whether to verify manifests after reading.
    public var verifyAfterReading: Bool?

    /// Whether to verify manifests after signing.
    public var verifyAfterSign: Bool?

    /// Whether to verify trust chains.
    public var verifyTrust: Bool?

    /// Whether to verify timestamp trust.
    public var verifyTimestampTrust: Bool?

    /// Whether to fetch OCSP responses.
    public var ocspFetch: Bool?

    /// Whether to fetch remote manifests.
    public var remoteManifestFetch: Bool?

    /// Whether to skip ingredient conflict resolution.
    public var skipIngredientConflictResolution: Bool?

    /// Whether to use strict v1 validation rules.
    public var strictV1Validation: Bool?

    public init(
        verifyAfterReading: Bool? = nil,
        verifyAfterSign: Bool? = nil,
        verifyTrust: Bool? = nil,
        verifyTimestampTrust: Bool? = nil,
        ocspFetch: Bool? = nil,
        remoteManifestFetch: Bool? = nil,
        skipIngredientConflictResolution: Bool? = nil,
        strictV1Validation: Bool? = nil
    ) {
        self.verifyAfterReading = verifyAfterReading
        self.verifyAfterSign = verifyAfterSign
        self.verifyTrust = verifyTrust
        self.verifyTimestampTrust = verifyTimestampTrust
        self.ocspFetch = ocspFetch
        self.remoteManifestFetch = remoteManifestFetch
        self.skipIngredientConflictResolution = skipIngredientConflictResolution
        self.strictV1Validation = strictV1Validation
    }
}

// MARK: - Builder Settings

/// Builder configuration within settings.
public struct BuilderSettingsDefinition: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case vendor
        case claimGeneratorInfo = "claim_generator_info"
        case thumbnail
        case actions
        case certificateStatusFetch = "certificate_status_fetch"
        case certificateStatusShouldOverride = "certificate_status_should_override"
        case intent
        case createdAssertionLabels = "created_assertion_labels"
        case preferBoxHash = "prefer_box_hash"
        case generateC2paArchive = "generate_c2pa_archive"
        case autoTimestampAssertion = "auto_timestamp_assertion"
    }

    /// Vendor prefix for manifest labels.
    public var vendor: String?

    /// Claim generator information.
    public var claimGeneratorInfo: ClaimGeneratorInfoSettings?

    /// Thumbnail generation settings.
    public var thumbnail: ThumbnailSettings?

    /// Actions configuration.
    public var actions: ActionsSettings?

    /// Scope for fetching certificate status (OCSP).
    public var certificateStatusFetch: OcspFetchScope?

    /// Whether certificate status should override existing status.
    public var certificateStatusShouldOverride: Bool?

    /// The intent for building manifests.
    public var intent: SettingsIntent?

    /// Labels of assertions considered "created" by the builder.
    public var createdAssertionLabels: [String]?

    /// Whether to prefer box hash for large assets.
    public var preferBoxHash: Bool?

    /// Whether to generate a C2PA archive.
    public var generateC2paArchive: Bool?

    /// Automatic timestamp assertion settings.
    public var autoTimestampAssertion: TimeStampSettings?

    public init(
        vendor: String? = nil,
        claimGeneratorInfo: ClaimGeneratorInfoSettings? = nil,
        thumbnail: ThumbnailSettings? = nil,
        actions: ActionsSettings? = nil,
        certificateStatusFetch: OcspFetchScope? = nil,
        certificateStatusShouldOverride: Bool? = nil,
        intent: SettingsIntent? = nil,
        createdAssertionLabels: [String]? = nil,
        preferBoxHash: Bool? = nil,
        generateC2paArchive: Bool? = nil,
        autoTimestampAssertion: TimeStampSettings? = nil
    ) {
        self.vendor = vendor
        self.claimGeneratorInfo = claimGeneratorInfo
        self.thumbnail = thumbnail
        self.actions = actions
        self.certificateStatusFetch = certificateStatusFetch
        self.certificateStatusShouldOverride = certificateStatusShouldOverride
        self.intent = intent
        self.createdAssertionLabels = createdAssertionLabels
        self.preferBoxHash = preferBoxHash
        self.generateC2paArchive = generateC2paArchive
        self.autoTimestampAssertion = autoTimestampAssertion
    }
}

// MARK: - Claim Generator Info Settings

/// Claim generator information for settings.
public struct ClaimGeneratorInfoSettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case name
        case version
        case operatingSystem = "operating_system"
    }

    /// The name of the claim generator.
    public var name: String

    /// The version of the claim generator.
    public var version: String?

    /// The operating system the claim generator runs on.
    public var operatingSystem: String?

    public init(
        name: String,
        version: String? = nil,
        operatingSystem: String? = nil
    ) {
        self.name = name
        self.version = version
        self.operatingSystem = operatingSystem
    }
}

// MARK: - Thumbnail Settings

/// Thumbnail generation configuration.
public struct ThumbnailSettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case enabled
        case ignoreErrors = "ignore_errors"
        case longEdge = "long_edge"
        case format
        case preferSmallestFormat = "prefer_smallest_format"
        case quality
    }

    /// Whether thumbnail generation is enabled.
    public var enabled: Bool?

    /// Whether to ignore errors during thumbnail generation.
    public var ignoreErrors: Bool?

    /// The long edge dimension in pixels.
    public var longEdge: Int?

    /// The image format for generated thumbnails.
    public var format: ThumbnailFormat?

    /// Whether to prefer the smallest format.
    public var preferSmallestFormat: Bool?

    /// The quality level for generated thumbnails.
    public var quality: ThumbnailQuality?

    public init(
        enabled: Bool? = nil,
        ignoreErrors: Bool? = nil,
        longEdge: Int? = nil,
        format: ThumbnailFormat? = nil,
        preferSmallestFormat: Bool? = nil,
        quality: ThumbnailQuality? = nil
    ) {
        self.enabled = enabled
        self.ignoreErrors = ignoreErrors
        self.longEdge = longEdge
        self.format = format
        self.preferSmallestFormat = preferSmallestFormat
        self.quality = quality
    }
}

/// Thumbnail image format.
public enum ThumbnailFormat: String, Codable, Sendable {
    case png
    case jpeg
    case gif
    case webp
    case tiff
}

/// Thumbnail quality level.
public enum ThumbnailQuality: String, Codable, Sendable {
    case low
    case medium
    case high
}

// MARK: - Actions Settings

/// Actions configuration for the builder.
public struct ActionsSettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case allActionsIncluded = "all_actions_included"
        case templates
        case autoCreatedAction = "auto_created_action"
        case autoOpenedAction = "auto_opened_action"
        case autoPlacedAction = "auto_placed_action"
    }

    /// Whether all actions are included.
    public var allActionsIncluded: Bool?

    /// Action templates.
    public var templates: [ActionTemplateSettings]?

    /// Auto-created action settings.
    public var autoCreatedAction: AutoActionSettings?

    /// Auto-opened action settings.
    public var autoOpenedAction: AutoActionSettings?

    /// Auto-placed action settings.
    public var autoPlacedAction: AutoActionSettings?

    public init(
        allActionsIncluded: Bool? = nil,
        templates: [ActionTemplateSettings]? = nil,
        autoCreatedAction: AutoActionSettings? = nil,
        autoOpenedAction: AutoActionSettings? = nil,
        autoPlacedAction: AutoActionSettings? = nil
    ) {
        self.allActionsIncluded = allActionsIncluded
        self.templates = templates
        self.autoCreatedAction = autoCreatedAction
        self.autoOpenedAction = autoOpenedAction
        self.autoPlacedAction = autoPlacedAction
    }
}

/// A template for an action assertion.
public struct ActionTemplateSettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case action
        case softwareAgent = "software_agent"
        case softwareAgentIndex = "software_agent_index"
        case sourceType = "source_type"
        case description
    }

    /// The action identifier.
    public var action: String

    /// Software agent information for this action.
    public var softwareAgent: ClaimGeneratorInfoSettings?

    /// Index of the software agent in the claim generator info list.
    public var softwareAgentIndex: Int?

    /// The digital source type for this action.
    public var sourceType: String?

    /// A human-readable description of the action.
    public var description: String?

    public init(
        action: String,
        softwareAgent: ClaimGeneratorInfoSettings? = nil,
        softwareAgentIndex: Int? = nil,
        sourceType: String? = nil,
        description: String? = nil
    ) {
        self.action = action
        self.softwareAgent = softwareAgent
        self.softwareAgentIndex = softwareAgentIndex
        self.sourceType = sourceType
        self.description = description
    }
}

/// Settings for automatic action generation.
public struct AutoActionSettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case enabled
        case sourceType = "source_type"
    }

    /// Whether the automatic action is enabled.
    public var enabled: Bool

    /// The digital source type for the automatic action.
    public var sourceType: String?

    public init(enabled: Bool, sourceType: String? = nil) {
        self.enabled = enabled
        self.sourceType = sourceType
    }
}

// MARK: - Timestamp Settings

/// Timestamp assertion configuration.
public struct TimeStampSettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case enabled
        case skipExisting = "skip_existing"
        case fetchScope = "fetch_scope"
    }

    /// Whether automatic timestamping is enabled.
    public var enabled: Bool?

    /// Whether to skip timestamping if a timestamp already exists.
    public var skipExisting: Bool?

    /// The scope for fetching timestamps.
    public var fetchScope: TimeStampFetchScope?

    public init(
        enabled: Bool? = nil,
        skipExisting: Bool? = nil,
        fetchScope: TimeStampFetchScope? = nil
    ) {
        self.enabled = enabled
        self.skipExisting = skipExisting
        self.fetchScope = fetchScope
    }
}

/// Scope for fetching timestamps.
public enum TimeStampFetchScope: String, Codable, Sendable {
    case parent
    case all
}

/// Scope for fetching OCSP certificate status.
public enum OcspFetchScope: String, Codable, Sendable {
    case all
    case active
}

// MARK: - Settings Intent

/// The intent for building manifests, specified in settings.
///
/// - SeeAlso: ``BuilderIntent``
public enum SettingsIntent: Codable, Sendable, Equatable {
    /// A new digital creation with the specified digital source type URI.
    case create(String)

    /// An edit of a pre-existing parent asset.
    case edit

    /// A restricted version of edit for non-editorial changes.
    case update

    private enum CodingKeys: String, CodingKey {
        case create = "Create"
    }

    private struct CreatePayload: Codable, Sendable {
        enum CodingKeys: String, CodingKey {
            case digitalSourceType = "digital_source_type"
        }
        let digitalSourceType: String
    }

    public init(from decoder: Decoder) throws {
        // Try as a plain string first ("Edit" or "Update")
        if let container = try? decoder.singleValueContainer(),
           let stringValue = try? container.decode(String.self) {
            switch stringValue {
            case "Edit":
                self = .edit
                return
            case "Update":
                self = .update
                return
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown intent string: \(stringValue)")
            }
        }

        // Try as an object {"Create": {"digital_source_type": "..."}}
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payload = try container.decode(CreatePayload.self, forKey: .create)
        self = .create(payload.digitalSourceType)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .edit:
            var container = encoder.singleValueContainer()
            try container.encode("Edit")
        case .update:
            var container = encoder.singleValueContainer()
            try container.encode("Update")
        case .create(let digitalSourceType):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(CreatePayload(digitalSourceType: digitalSourceType), forKey: .create)
        }
    }
}

// MARK: - Signer Settings

/// Signer configuration, either local or remote.
public enum SignerSettings: Codable, Sendable, Equatable {
    /// A local signer with credentials stored on-device.
    case local(LocalSignerSettings)

    /// A remote signer that delegates to a signing service.
    case remote(RemoteSignerSettings)

    private enum CodingKeys: String, CodingKey {
        case local
        case remote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let local = try container.decodeIfPresent(LocalSignerSettings.self, forKey: .local) {
            self = .local(local)
        } else if let remote = try container.decodeIfPresent(RemoteSignerSettings.self, forKey: .remote) {
            self = .remote(remote)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "SignerSettings must contain either 'local' or 'remote'"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .local(let settings):
            try container.encode(settings, forKey: .local)
        case .remote(let settings):
            try container.encode(settings, forKey: .remote)
        }
    }
}

/// Local signer credentials and configuration.
public struct LocalSignerSettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case alg
        case signCert = "sign_cert"
        case privateKey = "private_key"
        case tsaUrl = "tsa_url"
        case referencedAssertions = "referenced_assertions"
        case roles
    }

    /// The signing algorithm identifier (e.g., "es256").
    public var alg: String

    /// The certificate chain in PEM format.
    public var signCert: String

    /// The private key in PEM format.
    public var privateKey: String

    /// Optional URL of a timestamp authority.
    public var tsaUrl: String?

    /// Assertion labels referenced by the signer.
    public var referencedAssertions: [String]?

    /// Signer roles.
    public var roles: [String]?

    public init(
        alg: String,
        signCert: String,
        privateKey: String,
        tsaUrl: String? = nil,
        referencedAssertions: [String]? = nil,
        roles: [String]? = nil
    ) {
        self.alg = alg
        self.signCert = signCert
        self.privateKey = privateKey
        self.tsaUrl = tsaUrl
        self.referencedAssertions = referencedAssertions
        self.roles = roles
    }
}

/// Remote signer configuration.
public struct RemoteSignerSettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case url
        case alg
        case signCert = "sign_cert"
        case tsaUrl = "tsa_url"
        case referencedAssertions = "referenced_assertions"
        case roles
    }

    /// The URL of the remote signing service.
    public var url: String

    /// The signing algorithm identifier.
    public var alg: String

    /// The certificate chain in PEM format.
    public var signCert: String

    /// Optional URL of a timestamp authority.
    public var tsaUrl: String?

    /// Assertion labels referenced by the signer.
    public var referencedAssertions: [String]?

    /// Signer roles.
    public var roles: [String]?

    public init(
        url: String,
        alg: String,
        signCert: String,
        tsaUrl: String? = nil,
        referencedAssertions: [String]? = nil,
        roles: [String]? = nil
    ) {
        self.url = url
        self.alg = alg
        self.signCert = signCert
        self.tsaUrl = tsaUrl
        self.referencedAssertions = referencedAssertions
        self.roles = roles
    }
}
