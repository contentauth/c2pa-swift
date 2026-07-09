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
//  HashType.swift
//

import C2PAC
import Foundation

/// Hard-binding hash type a ``Builder`` uses for a given asset format.
///
/// Mirrors the native `C2paHashType`.
///
/// - SeeAlso: ``Builder/hashType(format:)``
public enum HashType: Int, Sendable {
    /// Placeholder + exclusions + hash + sign (JPEG, PNG, etc.).
    case dataHash = 0
    /// Placeholder + hash + sign (MP4, AVIF, HEIF/HEIC).
    case bmffHash = 1
    /// Hash + sign, no placeholder needed.
    case boxHash = 2

    /// Maps the native `C2paHashType` to a Swift case; `nil` if unrecognized.
    init?(c value: C2paHashType) {
        switch value {
        case DataHash: self = .dataHash
        case BmffHash: self = .bmffHash
        case BoxHash: self = .boxHash
        default: return nil
        }
    }
}
