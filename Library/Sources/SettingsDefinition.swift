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
        case core
        case verify
        case builder
        case signer
        case cawgX509Signer = "cawg_x509_signer"
        case softBinding = "soft_binding"
    }

    /// The settings schema version. Currently `1`.
    public var version: Int?

    /// Trust lists for claim signers, time-stamp authorities and CAWG identities.
    public var trust: TrustSettings?

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

    /// Soft binding algorithms to validate against.
    public var softBinding: SoftBindingSettings?

    public init(
        version: Int? = nil,
        trust: TrustSettings? = nil,
        core: CoreSettings? = nil,
        verify: VerifySettings? = nil,
        builder: BuilderSettingsDefinition? = nil,
        signer: SignerSettings? = nil,
        cawgX509Signer: SignerSettings? = nil,
        softBinding: SoftBindingSettings? = nil
    ) {
        self.version = version
        self.trust = trust
        self.core = core
        self.verify = verify
        self.builder = builder
        self.signer = signer
        self.cawgX509Signer = cawgX509Signer
        self.softBinding = softBinding
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
///
/// Each entry of ``anchors`` is one trust list and says what it is trusted
/// for: claim signers, time-stamp authorities or CAWG identities.
public struct TrustSettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case anchors
        case trustConfig = "trust_config"
        case useDefaultEkus = "use_default_ekus"
    }

    /// The trust lists certificates are validated against.
    public var anchors: [TrustAnchor]?

    /// Extended key usage (EKU) object identifiers a certificate must carry,
    /// one per line. While ``useDefaultEkus`` is on they are accepted in
    /// addition to the ones the C2PA specification defines.
    public var trustConfig: String?

    /// Whether the EKUs the C2PA specification defines are accepted alongside
    /// those in ``trustConfig``. When off, only the listed ones are accepted
    /// for claim signing. Defaults to `true`.
    public var useDefaultEkus: Bool?

    public init(
        anchors: [TrustAnchor]? = nil,
        trustConfig: String? = nil,
        useDefaultEkus: Bool? = nil
    ) {
        self.anchors = anchors
        self.trustConfig = trustConfig
        self.useDefaultEkus = useDefaultEkus
    }
}

/// One trust list, and what it is trusted for.
public struct TrustAnchor: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case trustAnchors = "trust_anchors"
        case trustKind = "trust_kind"
        case trustUri = "trust_uri"
        case trustConfig = "trust_config"
        case allowedList = "allowed_list"
        case trustedIcaIssuers = "trusted_ica_issuers"
    }

    /// The trusted root certificates, as a PEM bundle. Leave empty for an
    /// anchor that only carries an ``allowedList``.
    public var trustAnchors: String

    /// What the list is trusted for.
    public var trustKind: TrustListKind

    /// A URI identifying the list. One is generated when absent. Validation
    /// results name the list a certificate chained to by this URI.
    public var trustUri: String?

    /// Extended key usage (EKU) object identifiers certificates validated
    /// against this list must carry, one per line. They add to
    /// ``TrustSettings/trustConfig``; for a ``TrustListKind/cawg`` list they
    /// replace it.
    public var trustConfig: String?

    /// Certificates trusted as they are, without a chain to a root, as a PEM
    /// bundle. Only the list of a ``TrustListKind/manifest`` anchor trusts
    /// claim signers; that of a ``TrustListKind/cawg`` anchor trusts CAWG
    /// identities only.
    public var allowedList: String?

    /// DIDs of the identity claims aggregators whose credentials are trusted.
    /// None is trusted when the list is absent.
    public var trustedIcaIssuers: [String]?

    public init(
        trustAnchors: String,
        trustKind: TrustListKind = .manifest,
        trustUri: String? = nil,
        trustConfig: String? = nil,
        allowedList: String? = nil,
        trustedIcaIssuers: [String]? = nil
    ) {
        self.trustAnchors = trustAnchors
        self.trustKind = trustKind
        self.trustUri = trustUri
        self.trustConfig = trustConfig
        self.allowedList = allowedList
        self.trustedIcaIssuers = trustedIcaIssuers
    }
}

/// What a trust list is trusted for.
public enum TrustListKind: String, Codable, Sendable, CaseIterable {
    /// Certificates that sign claims.
    case manifest
    /// Certificates of time-stamp authorities.
    case tsa
    /// Certificates that sign CAWG identity assertions.
    case cawg
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
        case allowRedirects = "allow_redirects"
        case preferCompressManifests = "prefer_compress_manifests"
        case maxDecompressedManifestSizeInMb = "max_decompressed_manifest_size_in_mb"
        case timeStampRequestAttempts = "time_stamp_request_attempts"
        case timeStampRequestTimeoutInMs = "time_stamp_request_timeout_in_ms"
        case timeStampRetryDelayInMs = "time_stamp_retry_delay_in_ms"
        case httpRequestTimeoutInMs = "http_request_timeout_in_ms"
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

    /// Whether HTTP redirects are followed. When on, a redirect to an address
    /// that is not publicly routable is still refused. Defaults to `true`.
    public var allowRedirects: Bool?

    /// Whether manifests are compressed when their content allows it.
    /// Defaults to `false`.
    public var preferCompressManifests: Bool?

    /// Largest size a compressed manifest may decompress to, in megabytes.
    /// Defaults to 32 and may not exceed 1024.
    public var maxDecompressedManifestSizeInMb: Int?

    /// How many times a time-stamp request is sent before its last error is
    /// returned. A new attempt follows only a transient failure: no answer, a
    /// timeout, or an HTTP 408, 429, 500, 502, 503 or 504. Defaults to 3 and
    /// must be at least 1; `1` disables retries.
    ///
    /// With the defaults, signing against a time-stamp authority that does not
    /// answer takes about 31 seconds to fail: three attempts of
    /// ``timeStampRequestTimeoutInMs`` each, with pauses of
    /// ``timeStampRetryDelayInMs`` and twice that between them. Lower this
    /// value or the timeout to fail sooner.
    public var timeStampRequestAttempts: Int?

    /// Time limit of each time-stamp request attempt, in milliseconds.
    /// Defaults to 10,000 and must be positive.
    public var timeStampRequestTimeoutInMs: Int?

    /// Pause before the second time-stamp request attempt, in milliseconds,
    /// doubled before each later one. Defaults to 500.
    public var timeStampRetryDelayInMs: Int?

    /// Time limit of the other HTTP requests, in milliseconds: remote manifest
    /// and OCSP fetches, CAWG `did:web` resolution and remote signing from
    /// settings. Defaults to 10,000 and must be positive.
    ///
    /// This does not interrupt a resolver passed to
    /// ``C2PAContext/init(settings:signer:onProgress:httpResolver:)``, which
    /// has to enforce its own limit.
    public var httpRequestTimeoutInMs: Int?

    public init(
        merkleTreeChunkSizeInKb: Int? = nil,
        merkleTreeMaxProofs: Int? = nil,
        backingStoreMemoryThresholdInMb: Int? = nil,
        decodeIdentityAssertions: Bool? = nil,
        allowedNetworkHosts: [String]? = nil,
        allowRedirects: Bool? = nil,
        preferCompressManifests: Bool? = nil,
        maxDecompressedManifestSizeInMb: Int? = nil,
        timeStampRequestAttempts: Int? = nil,
        timeStampRequestTimeoutInMs: Int? = nil,
        timeStampRetryDelayInMs: Int? = nil,
        httpRequestTimeoutInMs: Int? = nil
    ) {
        self.merkleTreeChunkSizeInKb = merkleTreeChunkSizeInKb
        self.merkleTreeMaxProofs = merkleTreeMaxProofs
        self.backingStoreMemoryThresholdInMb = backingStoreMemoryThresholdInMb
        self.decodeIdentityAssertions = decodeIdentityAssertions
        self.allowedNetworkHosts = allowedNetworkHosts
        self.allowRedirects = allowRedirects
        self.preferCompressManifests = preferCompressManifests
        self.maxDecompressedManifestSizeInMb = maxDecompressedManifestSizeInMb
        self.timeStampRequestAttempts = timeStampRequestAttempts
        self.timeStampRequestTimeoutInMs = timeStampRequestTimeoutInMs
        self.timeStampRetryDelayInMs = timeStampRetryDelayInMs
        self.httpRequestTimeoutInMs = httpRequestTimeoutInMs
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
        case ocspFetchShouldOverride = "ocsp_fetch_should_override"
        case maxManifestResponseSize = "max_manifest_response_size"
        case verifyAfterSignHash = "verify_after_sign_hash"
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

    /// Whether a fresh OCSP response is fetched first during validation,
    /// before any certificate status assertion or stapled response is used.
    /// Implies ``ocspFetch``. Defaults to `false`.
    public var ocspFetchShouldOverride: Bool?

    /// Largest remote manifest response accepted, in bytes. Defaults to
    /// 10,485,760 (10 MiB) and must be positive.
    public var maxManifestResponseSize: Int?

    /// Whether verification after signing also checks the asset hash. Has no
    /// effect unless ``verifyAfterSign`` is on. Defaults to `false`.
    public var verifyAfterSignHash: Bool?

    public init(
        verifyAfterReading: Bool? = nil,
        verifyAfterSign: Bool? = nil,
        verifyTrust: Bool? = nil,
        verifyTimestampTrust: Bool? = nil,
        ocspFetch: Bool? = nil,
        remoteManifestFetch: Bool? = nil,
        skipIngredientConflictResolution: Bool? = nil,
        strictV1Validation: Bool? = nil,
        ocspFetchShouldOverride: Bool? = nil,
        maxManifestResponseSize: Int? = nil,
        verifyAfterSignHash: Bool? = nil
    ) {
        self.verifyAfterReading = verifyAfterReading
        self.verifyAfterSign = verifyAfterSign
        self.verifyTrust = verifyTrust
        self.verifyTimestampTrust = verifyTimestampTrust
        self.ocspFetch = ocspFetch
        self.remoteManifestFetch = remoteManifestFetch
        self.skipIngredientConflictResolution = skipIngredientConflictResolution
        self.strictV1Validation = strictV1Validation
        self.ocspFetchShouldOverride = ocspFetchShouldOverride
        self.maxManifestResponseSize = maxManifestResponseSize
        self.verifyAfterSignHash = verifyAfterSignHash
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
        case bmffHashExcludeFreeAndSkipBoxes = "bmff_hash_exclude_free_and_skip_boxes"
        case ignoreIngredientErrors = "ignore_ingredient_errors"
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

    /// Whether `free` and `skip` boxes are left out of the BMFF (MP4) hard
    /// binding hash. Applications commonly rewrite that padding after signing,
    /// so it is excluded by default; turn this off to have a later change to
    /// either box invalidate the binding. Defaults to `true`.
    public var bmffHashExcludeFreeAndSkipBoxes: Bool?

    /// Whether an error met while loading or validating an ingredient's
    /// manifest is recorded in the ingredient's validation results instead of
    /// being thrown, so the ingredient still loads. Defaults to `false`.
    public var ignoreIngredientErrors: Bool?

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
        autoTimestampAssertion: TimeStampSettings? = nil,
        bmffHashExcludeFreeAndSkipBoxes: Bool? = nil,
        ignoreIngredientErrors: Bool? = nil
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
        self.bmffHashExcludeFreeAndSkipBoxes = bmffHashExcludeFreeAndSkipBoxes
        self.ignoreIngredientErrors = ignoreIngredientErrors
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
public enum ThumbnailFormat: String, Codable, Sendable, CaseIterable {
    case png
    case jpeg
    case gif
    case webp
    case tiff
    public init(from decoder: Decoder) throws {
        self = try decodeIgnoringCase(Self.self, from: decoder)
    }
}

/// Thumbnail quality level.
public enum ThumbnailQuality: String, Codable, Sendable, CaseIterable {
    case low
    case medium
    case high
    public init(from decoder: Decoder) throws {
        self = try decodeIgnoringCase(Self.self, from: decoder)
    }
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
        case autoAllActionsIncluded = "auto_all_actions_included"
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

    /// Whether a manifest whose only recorded action is `c2pa.opened` is
    /// marked as including all actions. Turning this on asserts that every
    /// change made to the asset is recorded as an action. It takes priority
    /// over ``allActionsIncluded`` where it applies. Defaults to `false`.
    public var autoAllActionsIncluded: Bool?

    public init(
        allActionsIncluded: Bool? = nil,
        templates: [ActionTemplateSettings]? = nil,
        autoCreatedAction: AutoActionSettings? = nil,
        autoOpenedAction: AutoActionSettings? = nil,
        autoPlacedAction: AutoActionSettings? = nil,
        autoAllActionsIncluded: Bool? = nil
    ) {
        self.allActionsIncluded = allActionsIncluded
        self.templates = templates
        self.autoCreatedAction = autoCreatedAction
        self.autoOpenedAction = autoOpenedAction
        self.autoPlacedAction = autoPlacedAction
        self.autoAllActionsIncluded = autoAllActionsIncluded
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
public enum TimeStampFetchScope: String, Codable, Sendable, CaseIterable {
    case parent
    case all
    public init(from decoder: Decoder) throws {
        self = try decodeIgnoringCase(Self.self, from: decoder)
    }
}

/// Scope for fetching OCSP certificate status.
public enum OcspFetchScope: String, Codable, Sendable, CaseIterable {
    case all
    case active
    public init(from decoder: Decoder) throws {
        self = try decodeIgnoringCase(Self.self, from: decoder)
    }
}

/// Decodes an enumeration value the way c2pa-rs reads it: lowercased before
/// it is matched, so `"PNG"` and `"png"` are the same value.
private func decodeIgnoringCase<Value: RawRepresentable>(
    _ type: Value.Type, from decoder: Decoder
) throws -> Value where Value.RawValue == String {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let value = Value(rawValue: text.lowercased()) else {
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "Unknown \(Value.self) value: \(text)")
    }
    return value
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
        case create
    }

    public init(from decoder: Decoder) throws {
        // "edit" or "update". c2pa-rs lowercases the string before matching it.
        if let container = try? decoder.singleValueContainer(),
           let stringValue = try? container.decode(String.self) {
            switch stringValue.lowercased() {
            case "edit":
                self = .edit
            case "update":
                self = .update
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown intent string: \(stringValue)")
            }
            return
        }

        // {"create": "<digital source type>"}
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .create(try container.decode(String.self, forKey: .create))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .edit:
            var container = encoder.singleValueContainer()
            try container.encode("edit")
        case .update:
            var container = encoder.singleValueContainer()
            try container.encode("update")
        case .create(let digitalSourceType):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(digitalSourceType, forKey: .create)
        }
    }
}

// MARK: - Soft Binding Settings

/// Soft binding configuration.
public struct SoftBindingSettings: Codable, Sendable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case softBindingAlgorithms = "soft_binding_algorithms"
    }

    /// The soft binding algorithms to validate against. When absent,
    /// validation may report soft binding errors.
    public var softBindingAlgorithms: [String]?

    public init(softBindingAlgorithms: [String]? = nil) {
        self.softBindingAlgorithms = softBindingAlgorithms
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
