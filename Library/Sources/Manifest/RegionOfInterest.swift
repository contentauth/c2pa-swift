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
//  RegionOfInterest.swift
//

import Foundation

/// A region of interest within an asset describing the change.
/// - SeeAlso: [RegionOfInterest Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema/#regionofinterest)
open class RegionOfInterest: Codable, Equatable {

    // MARK: Equatable

    public static func == (lhs: RegionOfInterest, rhs: RegionOfInterest) -> Bool {
        lhs.description == rhs.description
            && lhs.identifier == rhs.identifier
            && lhs.metadata == rhs.metadata
            && lhs.name == rhs.name
            && lhs.region == rhs.region
            && lhs.type == rhs.type
    }

    // MARK: RegionOfInterest

    /// A free-text string.
    open var description: String?

    /// A free-text string representing a machine-readable, unique to this assertion, identifier for the region.
    open var identifier: String?

    /// Additional information about the asset.
    open var metadata: Metadata?

    /// A free-text string representing a human-readable name for the region which might be used in a user interface.
    open var name: String?

    /// A range describing the region of interest for the specific asset.
    open var region: [RegionRange]

    /// A value from a controlled vocabulary such as ``ImageRegionType`` or an entity-specific value
    /// (e.g., com.litware.newType) that represents the type of thing(s) depicted by a region.
    open var type: String?

    /// - Parameters:
    ///   - description: A free-text string.
    ///   - identifier: A free-text string representing a machine-readable, unique to this assertion, identifier for the region.
    ///   - metadata: Additional information about the asset.
    ///   - name: A free-text string representing a human-readable name for the region which might be used in a user interface.
    ///   - region: A range describing the region of interest for the specific asset.
    ///   - type: A value from a controlled vocabulary such as ``ImageRegionType`` or an entity-specific value
    /// (e.g., com.litware.newType) that represents the type of thing(s) depicted by a region.
    public init(
        description: String? = nil,
        identifier: String? = nil,
        metadata: Metadata? = nil,
        name: String? = nil,
        region: [RegionRange],
        type: String? = nil
    ) {
        self.description = description
        self.identifier = identifier
        self.metadata = metadata
        self.name = name
        self.region = region
        self.type = type
    }

    /// - Parameters:
    ///   - description: A free-text string.
    ///   - identifier: A free-text string representing a machine-readable, unique to this assertion, identifier for the region.
    ///   - metadata: Additional information about the asset.
    ///   - name: A free-text string representing a human-readable name for the region which might be used in a user interface.
    ///   - region: A range describing the region of interest for the specific asset.
    ///   - type: A value from the controlled vocabulary ``ImageRegionType`` that represents the type of thing(s) depicted by a region.
    public convenience init(
        description: String? = nil,
        identifier: String? = nil,
        metadata: Metadata? = nil,
        name: String? = nil,
        region: [RegionRange],
        type: ImageRegionType
    ) {
        self.init(
            description: description,
            identifier: identifier,
            metadata: metadata,
            name: name,
            region: region,
            type: type.rawValue)
    }
}
