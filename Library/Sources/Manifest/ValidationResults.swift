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
//  ValidationResults.swift
//

import Foundation

/// A map of validation results for a manifest store. The map contains the validation results for the active manifest and any ingredient deltas. It is normal for there to be many
/// - SeeAlso: [ValidationResults Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema/#validationresults)
public struct ValidationResults: Codable, Equatable, Sendable {

    public var activeManifest: StatusCodes?

    public var ingredientDeltas: [IngredientDeltaValidationResult]?

    /// The version of the C2PA specification the validation followed.
    public var specVersion: String?

    /// URI of the trust list the time-stamp authority's certificate chained to.
    public var timestampTrustListUri: String?

    /// URI of the trust list the signing certificate chained to.
    public var trustListUri: String?

    /// When the validation was performed.
    public var validationTime: String?

    public init(
        activeManifest: StatusCodes? = nil,
        ingredientDeltas: [IngredientDeltaValidationResult]? = nil,
        specVersion: String? = nil,
        timestampTrustListUri: String? = nil,
        trustListUri: String? = nil,
        validationTime: String? = nil
    ) {
        self.activeManifest = activeManifest
        self.ingredientDeltas = ingredientDeltas
        self.specVersion = specVersion
        self.timestampTrustListUri = timestampTrustListUri
        self.trustListUri = trustListUri
        self.validationTime = validationTime
    }
}
