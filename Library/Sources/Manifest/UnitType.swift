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
//  UnitType.swift
//

import Foundation

/// The type of unit for the range.
/// - SeeAlso: [UnitType Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema/#unittype)
public enum UnitType: String, Codable, Sendable, CaseIterable {

    /// Use pixels.
    case pixel

    /// Use percentage.
    case percent
}
