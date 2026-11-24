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
//  ResourceRef.swift
//

import Foundation

/// A reference to a resource to be used in JSON serialization. The underlying data can be read as a stream via Reader::resource_to_stream .
/// - SeeAlso: [ResourceRef Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema#resourceref)
open class ResourceRef: UriOrResource {

    public enum CodingKeys: String, CodingKey {
        case alg
        case dataTypes = "data_types"
        case format
        case hash
        case identifier
    }

    /// More detailed data types as defined in the C2PA spec.
    open var dataTypes: [AssetType]?

    /// The mime type of the referenced resource.
    open var format: String

    /// The hash of the resource (if applicable).
    open var hash: String?

    /// A URI that identifies the resource as referenced from the manifest.
    /// This may be a JUMBF URI, a file path, a URL or any other string. Relative JUMBF URIs will be resolved with the manifest label. Relative file paths will be resolved with the base path if provided.
    open var identifier: String

    /// - Parameters:
    ///   - alg: A string identifying the cryptographic hash algorithm used to compute the hash.
    ///   - dataTypes: More detailed data types as defined in the C2PA spec.
    ///   - format: The mime type of the referenced resource.
    ///   - hash: The hash of the resource (if applicable).
    ///   - identifier: A URI that identifies the resource as referenced from the manifest.
    /// This may be a JUMBF URI, a file path, a URL or any other string. Relative JUMBF URIs will be resolved with the manifest label. Relative file paths will be resolved with the base path if provided.
    public init(alg: String? = nil, dataTypes: [AssetType]? = nil, format: String, hash: String? = nil, identifier: String) {
        self.dataTypes = dataTypes
        self.format = format
        self.hash = hash
        self.identifier = identifier

        super.init(alg: alg)
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        dataTypes = try container.decodeIfPresent([AssetType].self, forKey: .dataTypes)
        format = try container.decode(String.self, forKey: .format)
        hash = try container.decodeIfPresent(String.self, forKey: .hash)
        identifier = try container.decode(String.self, forKey: .identifier)

        try super.init(from: decoder)
    }

    override open func isEqual(to other: UriOrResource) -> Bool {
        guard super.isEqual(to: other), let other = other as? ResourceRef else { return false }
        return dataTypes == other.dataTypes
            && format == other.format
            && hash == other.hash
            && identifier == other.identifier
    }

    override open func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(dataTypes, forKey: .dataTypes)
        try container.encode(format, forKey: .format)
        try container.encodeIfPresent(hash, forKey: .hash)
        try container.encode(identifier, forKey: .identifier)
    }
}
