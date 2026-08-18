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
//  Metadata.swift
//

import Foundation

/// The Metadata structure can be used as part of other assertions or on its own to reference others
/// NOTE: This object can have any number of additional user-defined properties.

/// - SeeAlso: [Metadata Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema#metadata)
public struct Metadata: Codable, Equatable {

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case dataSource
        case dateTime
        case reference
        case regionOfInterest
        case reviewRatings
    }

    private static let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))

    public var dataSource: DataSource?

    public var dateTime: Date?

    public var reference: HashedUri?

    public var regionOfInterest: RegionOfInterest?

    public var reviewRatings: [ReviewRating]?

    /// Members of the decoded object that this type does not model.
    ///
    /// The C2PA metadata object is explicitly open-ended and c2pa-rs keeps these in a
    /// flattened map, so they survive a decode/encode cycle here rather than being lost.
    public var additionalFields: [String: AnyCodable]?

    public init(
        dataSource: DataSource? = nil,
        dateTime: Date? = nil,
        reference: HashedUri? = nil,
        regionOfInterest: RegionOfInterest? = nil,
        reviewRatings: [ReviewRating]? = nil,
        additionalFields: [String: AnyCodable]? = nil
    ) {
        self.dataSource = dataSource
        self.dateTime = dateTime
        self.reference = reference
        self.regionOfInterest = regionOfInterest
        self.reviewRatings = reviewRatings
        self.additionalFields = additionalFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dataSource = try container.decodeIfPresent(DataSource.self, forKey: .dataSource)
        dateTime = try container.decodeIfPresent(Date.self, forKey: .dateTime)
        reference = try container.decodeIfPresent(HashedUri.self, forKey: .reference)
        regionOfInterest = try container.decodeIfPresent(RegionOfInterest.self, forKey: .regionOfInterest)
        reviewRatings = try container.decodeIfPresent([ReviewRating].self, forKey: .reviewRatings)
        additionalFields = try decoder.decodeAdditionalFields(excluding: Self.knownKeys)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(dataSource, forKey: .dataSource)
        try container.encodeIfPresent(dateTime, forKey: .dateTime)
        try container.encodeIfPresent(reference, forKey: .reference)
        try container.encodeIfPresent(regionOfInterest, forKey: .regionOfInterest)
        try container.encodeIfPresent(reviewRatings, forKey: .reviewRatings)
        try encoder.encodeAdditionalFields(additionalFields, excluding: Self.knownKeys)
    }
}
