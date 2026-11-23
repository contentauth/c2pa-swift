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
//  ManifestDefinition.swift
//

import Foundation

/// A definition for creating a C2PA manifest.
///
/// `ManifestDefinition` describes the structure and content of a C2PA manifest,
/// including assertions about the content, its provenance, and ingredients used.
///
/// Whether an assertion is treated as "created" or "gathered" is determined by the
/// `created_assertions` setting in ``C2PASettings``, not by placement in a separate list.
///
/// ## Example
///
/// ```swift
/// let manifest = ManifestDefinition.created(
///     title: "photo.jpg",
///     claimGeneratorInfo: ClaimGeneratorInfo(name: "MyApp", version: "1.0"),
///     digitalSourceType: .digitalCapture
/// )
/// let json = try manifest.toJSON()
/// ```
///
/// - SeeAlso: [Manifest Definition Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema)
public struct ManifestDefinition: Codable, CustomStringConvertible, Equatable {
    public enum CodingKeys: String, CodingKey {
        case assertions
        case claimGeneratorInfo = "claim_generator_info"
        case claimVersion = "claim_version"
        case format
        case hashAlg = "hash_alg"
        case ingredients
        case instanceId = "instance_id"
        case label
        case metadata
        case redactions
        case thumbnail
        case title
        case vendor
    }

    // MARK: - Properties

    /// A list of assertions.
    public var assertions: [AssertionDefinition]

    /// Claim Generator Info is always required with at least one entry.
    public var claimGeneratorInfo: [ClaimGeneratorInfo]

    /// The version of the claim. When absent, a C2PA 2.x claim is signed.
    public var claimVersion: UInt8?

    /// The format of the source file as a MIME type.
    public var format: String

    /// The hash algorithm for asset and assertion hashing: `sha256`, `sha384` or `sha512`.
    /// When absent, `sha256` is used.
    public var hashAlg: String?

    /// A list of ingredients.
    public var ingredients: [Ingredient]

    /// Instance ID from xmpMM:InstanceID in XMP metadata.
    public var instanceId: String?

    /// Pre-defined manifest label. Must be unique. Not intended for general use.
    public var label: String?

    /// Optional manifest metadata.
    @available(*, deprecated, message: "This will be deprecated in the future; not recommended to use.")
    public var metadata: [Metadata]? {
        get { storedMetadata }
        set { storedMetadata = newValue }
    }

    /// Holds ``metadata``, so coding it does not go through the deprecated property.
    private var storedMetadata: [Metadata]?

    /// A list of redactions -- URIs to redacted assertions.
    public var redactions: [String]?

    /// An optional ``ResourceRef`` to a thumbnail image.
    public var thumbnail: ResourceRef?

    /// A human-readable title, generally source filename.
    public var title: String?

    /// Optional prefix added to the generated manifest label (typically a reverse domain name).
    public var vendor: String?

    // MARK: - Initialization

    /// Creates a manifest definition.
    ///
    /// - Parameters:
    ///   - assertions: A list of assertions.
    ///   - claimGeneratorInfo: Required claim generator info (at least one entry).
    ///   - claimVersion: The claim version. When absent, a C2PA 2.x claim is signed.
    ///   - format: The MIME type of the source file.
    ///   - hashAlg: The hash algorithm for asset and assertion hashing. When absent, `sha256` is used.
    ///   - ingredients: A list of ingredients.
    ///   - instanceId: Instance ID from XMP metadata.
    ///   - label: Pre-defined manifest label.
    ///   - redactions: URIs to redacted assertions.
    ///   - thumbnail: A thumbnail image reference.
    ///   - title: A human-readable title.
    ///   - vendor: Prefix for the generated manifest label.
    public init(
        assertions: [AssertionDefinition] = [],
        claimGeneratorInfo: [ClaimGeneratorInfo],
        claimVersion: UInt8? = nil,
        format: String = "application/octet-stream",
        hashAlg: String? = nil,
        ingredients: [Ingredient] = [],
        instanceId: String? = nil,
        label: String? = nil,
        redactions: [String]? = nil,
        thumbnail: ResourceRef? = nil,
        title: String,
        vendor: String? = nil
    ) {
        self.assertions = assertions
        self.claimGeneratorInfo = claimGeneratorInfo
        self.claimVersion = claimVersion
        self.format = format
        self.hashAlg = hashAlg
        self.ingredients = ingredients
        self.instanceId = instanceId
        self.label = label
        self.redactions = redactions
        self.thumbnail = thumbnail
        self.title = title
        self.vendor = vendor
    }

    // MARK: - Codable

    /// The format c2pa-rs assumes when a definition names none.
    private static let defaultFormat = "application/octet-stream"

    /// c2pa-rs requires no member of a manifest definition, so none is required
    /// to decode one: an absent list is empty and an absent format is
    /// `application/octet-stream`. A definition built here still takes a
    /// title, which ``ManifestValidator`` requires.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assertions = try container.decodeIfPresent([AssertionDefinition].self, forKey: .assertions) ?? []
        claimGeneratorInfo =
            try container.decodeIfPresent([ClaimGeneratorInfo].self, forKey: .claimGeneratorInfo) ?? []
        claimVersion = try container.decodeIfPresent(UInt8.self, forKey: .claimVersion)
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? Self.defaultFormat
        hashAlg = try container.decodeIfPresent(String.self, forKey: .hashAlg)
        ingredients = try container.decodeIfPresent([Ingredient].self, forKey: .ingredients) ?? []
        instanceId = try container.decodeIfPresent(String.self, forKey: .instanceId)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        storedMetadata = try container.decodeIfPresent([Metadata].self, forKey: .metadata)
        redactions = try container.decodeIfPresent([String].self, forKey: .redactions)
        thumbnail = try container.decodeIfPresent(ResourceRef.self, forKey: .thumbnail)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        vendor = try container.decodeIfPresent(String.self, forKey: .vendor)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(assertions, forKey: .assertions)
        try container.encode(claimGeneratorInfo, forKey: .claimGeneratorInfo)
        try container.encodeIfPresent(claimVersion, forKey: .claimVersion)
        try container.encode(format, forKey: .format)
        try container.encodeIfPresent(hashAlg, forKey: .hashAlg)
        try container.encode(ingredients, forKey: .ingredients)
        try container.encodeIfPresent(instanceId, forKey: .instanceId)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(storedMetadata, forKey: .metadata)
        try container.encodeIfPresent(redactions, forKey: .redactions)
        try container.encodeIfPresent(thumbnail, forKey: .thumbnail)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(vendor, forKey: .vendor)
    }

    // MARK: - Factory Methods

    /// Creates a manifest for a newly created asset.
    ///
    /// - Parameters:
    ///   - title: A human-readable title.
    ///   - claimGeneratorInfo: The claim generator info.
    ///   - digitalSourceType: The type of digital source.
    /// - Returns: A manifest definition configured for creation.
    public static func created(
        title: String,
        claimGeneratorInfo: ClaimGeneratorInfo,
        digitalSourceType: DigitalSourceType
    ) -> ManifestDefinition {
        ManifestDefinition(
            assertions: [
                .actions(actions: [
                    Action(
                        action: .created,
                        digitalSourceType: digitalSourceType
                    )
                ])
            ],
            claimGeneratorInfo: [claimGeneratorInfo],
            title: title
        )
    }

    /// Creates a manifest for an edited asset.
    ///
    /// - Parameters:
    ///   - title: A human-readable title.
    ///   - claimGeneratorInfo: The claim generator info.
    ///   - parentIngredient: The parent ingredient being edited.
    ///   - editActions: The editing actions performed.
    /// - Returns: A manifest definition configured for editing.
    public static func edited(
        title: String,
        claimGeneratorInfo: ClaimGeneratorInfo,
        parentIngredient: Ingredient,
        editActions: [Action]
    ) -> ManifestDefinition {
        ManifestDefinition(
            assertions: [.actions(actions: editActions)],
            claimGeneratorInfo: [claimGeneratorInfo],
            ingredients: [parentIngredient],
            title: title
        )
    }

    // MARK: - Convenience

    /// Returns the unique base labels of the assertions.
    public func assertionLabels() -> [String] {
        Array(Set(assertions.map { $0.baseLabel }))
    }

    /// Encodes this manifest to a JSON string.
    ///
    /// - Returns: A JSON string representation.
    /// - Throws: `EncodingError` if encoding fails.
    public func toJSON() throws -> String {
        try C2PAJson.encode(self)
    }

    /// Encodes this manifest to a pretty-printed JSON string.
    ///
    /// - Returns: A formatted JSON string representation.
    /// - Throws: `EncodingError` if encoding fails.
    public func toPrettyJSON() throws -> String {
        try C2PAJson.encodePretty(self)
    }

    /// Decodes a manifest from a JSON string.
    ///
    /// - Parameter json: A JSON string to decode.
    /// - Returns: The decoded manifest definition.
    /// - Throws: `DecodingError` if decoding fails.
    public static func fromJSON(_ json: String) throws -> ManifestDefinition {
        try C2PAJson.decode(ManifestDefinition.self, from: json)
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        do {
            return try toJSON()
        } catch {
            return "<ERROR encoding: \(error.localizedDescription)>"
        }
    }
}
