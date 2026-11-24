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
//  RangeType.swift
//

import Foundation

/// The type of range for the region of interest.
/// - SeeAlso: [RangeType Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema/#rangetype)
public enum RangeType: String, Codable, Sendable, CaseIterable {

    /// A spatial range. See ``Shape`` for more details.
    case spatial

    /// A temporal range. See ``Time`` for more details.
    case temporal

    /// A spatial range. See ``Frame`` for more details.
    case frame

    /// A textual range. See ``Text`` for more details.
    case textual

    /// A range identified by a specific identifier and value. See ``Item`` for more details.
    case identified
}
