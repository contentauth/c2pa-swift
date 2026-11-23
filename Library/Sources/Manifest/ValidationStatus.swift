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
//  ValidationStatus.swift
//

import Foundation

/// A ValidationStatus struct describes the validation status of a specific part of a manifest.
///
/// The status code is kept as the string c2pa-rs reported, because the set of codes is open.
/// Use ``statusCode`` to work with the codes this library lists.
///
/// - SeeAlso: [ValidationStatus Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema/#validationstatus)
public struct ValidationStatus: Codable, Equatable, Sendable {

    /// The validation status code, such as `claimSignature.validated`.
    public var code: String

    public var explanation: String?

    public var success: Bool?

    public var url: String?

    /// The ``ValidationStatusCode`` for ``code``, or `nil` if this library does not list the code.
    public var statusCode: ValidationStatusCode? {
        ValidationStatusCode(rawValue: code)
    }

    public init(code: String, explanation: String? = nil, success: Bool? = nil, url: String? = nil) {
        self.code = code
        self.explanation = explanation
        self.success = success
        self.url = url
    }

    /// Creates a validation status from a listed ``ValidationStatusCode``.
    public init(code: ValidationStatusCode, explanation: String? = nil, success: Bool? = nil, url: String? = nil) {
        self.init(code: code.rawValue, explanation: explanation, success: success, url: url)
    }
}
