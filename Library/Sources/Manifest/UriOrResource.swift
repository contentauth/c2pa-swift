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
//  UriOrResource.swift
//

import Foundation

/// - SeeAlso: [UriOrResource Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema/#uriorresource)
open class UriOrResource: Codable, Equatable {

    // MARK: Equatable

    public static func == (lhs: UriOrResource, rhs: UriOrResource) -> Bool {
        lhs.isEqual(to: rhs)
    }

    /// Whether `other` is the same kind of reference with the same members.
    ///
    /// A subclass that adds members overrides this, calls `super` and
    /// compares what it added, so `==` holds for the whole value however it
    /// is typed at the call site.
    open func isEqual(to other: UriOrResource) -> Bool {
        type(of: self) == type(of: other) && alg == other.alg
    }

    // MARK: UriOrResource

    /// A string identifying the cryptographic hash algorithm used to compute the hash.
    open var alg: String?

    /// - Parameters:
    ///   - alg: A string identifying the cryptographic hash algorithm used to compute the hash.
    public init(alg: String? = nil) {
        self.alg = alg
    }
}
