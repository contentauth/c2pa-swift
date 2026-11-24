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
//  Ingredient.swift
//

import Foundation

/// An Ingredient is any external asset that has been used in the creation of an asset.
/// - SeeAlso: [Ingredient Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema#ingredient)
public struct Ingredient: Codable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case activeManifest = "active_manifest"
        case data
        case dataTypes = "data_types"
        case description
        case digitalSourceType = "digital_source_type"
        case documentId = "document_id"
        case format
        case hash
        case informationalUri = "informational_URI"
        case instanceId = "instance_id"
        case isCreated = "is_created"
        case label
        case manifestData = "manifest_data"
        case metadata
        case ocspResponses = "ocsp_responses"
        case provenance
        case relationship
        case thumbnail
        case title
        case validationResults = "validation_results"
        case validationStatus = "validation_status"
    }

    /// The active manifest label (if one exists).
    /// If this ingredient has a manifest store, this is the label of the active manifest.
    public var activeManifest: String?

    /// A reference to the actual data of the ingredient.
    public var data: ResourceRef?

    /// Additional information about the data’s type to the ingredient V2 structure.
    public var dataTypes: [AssetType]?

    /// Additional description of the ingredient.
    public var description: String?

    /// A URL identifying an IPTC term for how the ingredient was made. Most probably a ``DigitalSourceType``.
    public var digitalSourceType: String?

    /// Document ID from xmpMM:DocumentID in XMP metadata.
    public var documentId: String?

    /// The format of the source file as a MIME type.
    public var format: String?

    /// An optional hash of the asset to prevent duplicates.
    public var hash: String?

    /// URI to an informational page about the ingredient or its data.
    public var informationalUri: String?

    /// Instance ID from xmpMM:InstanceID in XMP metadata.
    public var instanceId: String?

    /// Whether the ingredient assertion is a created one, as opposed to a gathered one.
    public var isCreated: Bool?

    /// The ingredient’s label as assigned in the manifest.
    public var label: String?

    /// A manifest store from the source asset extracted as a binary C2PA blob.
    public var manifestData: ResourceRef?

    /// Any additional ``Metadata`` as defined in the C2PA spec.
    public var metadata: Metadata?

    /// OCSP responses for the ingredient's certificates, each as a reference to the response data.
    public var ocspResponses: [ResourceRef]?

    /// URI from dcterms:provenance in XMP metadata.
    public var provenance: String?

    /// Set to ``Relationship#parentOf`` if this is the parent ingredient.
    /// There can only be one parent ingredient in the ingredients.
    public var relationship: Relationship?

    /// A thumbnail image capturing the visual state at the time of import.
    /// A tuple of thumbnail MIME format (for example image/jpeg) and binary bits of the image.
    public var thumbnail: ResourceRef?

    /// A human-readable title, generally source filename.
    public var title: String?

    /// Validation results (Ingredient.V3)
    public var validationResults: ValidationResults?

    /// Validation status (Ingredient v1 & v2)
    public var validationStatus: [ValidationStatus]?

    /// - Parameters:
    ///   - activeManifest: The active manifest label (if one exists). If this ingredient has a manifest store, this is the label of the active manifest.
    ///   - data: A reference to the actual data of the ingredient.
    ///   - dataTypes: Additional information about the data’s type to the ingredient V2 structure.
    ///   - description: Additional description of the ingredient.
    ///   - digitalSourceType: A URL identifying an IPTC term for how the ingredient was made. Most probably a ``DigitalSourceType``.
    ///   - documentId: Document ID from xmpMM:DocumentID in XMP metadata.
    ///   - format: The format of the source file as a MIME type.
    ///   - hash: An optional hash of the asset to prevent duplicates.
    ///   - informationalUri: URI to an informational page about the ingredient or its data.
    ///   - instanceId: Instance ID from xmpMM:InstanceID in XMP metadata.
    ///   - isCreated: Whether the ingredient assertion is a created one, as opposed to a gathered one.
    ///   - label: The ingredient’s label as assigned in the manifest.
    ///   - manifestData: A manifest store from the source asset extracted as a binary C2PA blob.
    ///   - metadata: Any additional ``Metadata`` as defined in the C2PA spec.
    ///   - ocspResponses: OCSP responses for the ingredient's certificates, each as a reference to the response data.
    ///   - provenance: URI from dcterms:provenance in XMP metadata.
    ///   - relationship: Set to ``Relationship#parentOf`` if this is the parent ingredient. There can only be one parent ingredient in the ingredients.
    ///   - thumbnail: A thumbnail image capturing the visual state at the time of import. A tuple of thumbnail MIME format (for example image/jpeg) and binary bits of the image.
    ///   - title: A human-readable title, generally source filename.
    ///   - validationResults: Validation results (Ingredient.V3)
    ///   - validationStatus: Validation status (Ingredient v1 & v2)
    public init(
        activeManifest: String? = nil,
        data: ResourceRef? = nil,
        dataTypes: [AssetType]? = nil,
        description: String? = nil,
        digitalSourceType: String? = nil,
        documentId: String? = nil,
        format: String? = nil,
        hash: String? = nil,
        informationalUri: String? = nil,
        instanceId: String? = nil,
        isCreated: Bool? = nil,
        label: String? = nil,
        manifestData: ResourceRef? = nil,
        metadata: Metadata? = nil,
        ocspResponses: [ResourceRef]? = nil,
        provenance: String? = nil,
        relationship: Relationship? = nil,
        thumbnail: ResourceRef? = nil,
        title: String? = nil,
        validationResults: ValidationResults? = nil,
        validationStatus: [ValidationStatus]? = nil
    ) {
        self.activeManifest = activeManifest
        self.data = data
        self.dataTypes = dataTypes
        self.description = description
        self.digitalSourceType = digitalSourceType
        self.documentId = documentId
        self.format = format
        self.hash = hash
        self.informationalUri = informationalUri
        self.instanceId = instanceId
        self.isCreated = isCreated
        self.label = label
        self.manifestData = manifestData
        self.metadata = metadata
        self.ocspResponses = ocspResponses
        self.provenance = provenance
        self.relationship = relationship
        self.thumbnail = thumbnail
        self.title = title
        self.validationResults = validationResults
        self.validationStatus = validationStatus
    }

    // MARK: - Factory Methods

    /// Creates a parent ingredient.
    ///
    /// A parent ingredient is the primary source asset that was modified
    /// to create the current asset.
    ///
    /// - Parameters:
    ///   - title: A human-readable title.
    ///   - format: Optional MIME type of the ingredient.
    /// - Returns: An ingredient configured as a parent.
    public static func parent(title: String, format: String? = nil) -> Ingredient {
        Ingredient(format: format, relationship: .parentOf, title: title)
    }

    /// Creates a component ingredient.
    ///
    /// A component ingredient is a secondary source asset incorporated
    /// into the current asset (e.g., a watermark or overlay).
    ///
    /// - Parameters:
    ///   - title: A human-readable title.
    ///   - format: Optional MIME type of the ingredient.
    /// - Returns: An ingredient configured as a component.
    public static func component(title: String, format: String? = nil) -> Ingredient {
        Ingredient(format: format, relationship: .componentOf, title: title)
    }

    /// Creates an inputTo ingredient.
    ///
    /// An inputTo ingredient was used as input to a process that
    /// generated the current asset (e.g., training data for AI).
    ///
    /// - Parameters:
    ///   - title: A human-readable title.
    ///   - format: Optional MIME type of the ingredient.
    /// - Returns: An ingredient configured as inputTo.
    public static func inputTo(title: String, format: String? = nil) -> Ingredient {
        Ingredient(format: format, relationship: .inputTo, title: title)
    }
}
