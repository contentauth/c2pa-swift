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
//  TimeType.swift
//

import Foundation

/// The type of time.
/// - SeeAlso: [TimeType Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema/#timetype)
public enum TimeType: String, Codable, Sendable, CaseIterable {

    /// Times are described using Normal Play Time (npt) as described in RFC 2326.
    case npt
}
