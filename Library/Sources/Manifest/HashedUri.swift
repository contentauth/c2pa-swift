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
//  HashedUri.swift
//

import Foundation

/// A HashedUri provides a reference to content available within the same manifest store. This is described in §8.3, URI References of the C2PA Technical Specification.
/// - SeeAlso: [C2PA Specification: URI References](https://c2pa.org/specifications/specifications/2.1/specs/C2PA_Specification.html#_uri_references)

/// - SeeAlso: [HashedUri Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema/#hasheduri)
open class HashedUri: UriOrResource {

    public enum CodingKeys: String, CodingKey {
        case hash
        case url
    }

    /// Byte string containing the hash value.
    ///
    /// It is written as a JSON array of numbers, which is how c2pa-rs takes
    /// hash bytes. A ``Reader`` reports them as `b64'<base64>'`, and that form
    /// is read too.
    open var hash: [UInt8]

    /// JUMBF URI reference
    open var url: String

    /// - Parameters:
    ///   - alg: A string identifying the cryptographic hash algorithm used to compute the hash.
    ///   - hash: Byte string containing the hash value.
    ///   - url: JUMBF URI reference
    public init(alg: String? = nil, hash: [UInt8], url: String) {
        self.hash = hash
        self.url = url

        super.init(alg: alg)
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        hash = try Self.decodeHash(from: container)
        url = try container.decode(String.self, forKey: .url)

        try super.init(from: decoder)
    }

    /// Reads the hash from an array of byte values or from `b64'<base64>'`.
    ///
    /// A string without that wrapper is refused: c2pa-rs would take it as the
    /// bytes of the string itself, which is never what a hash is.
    private static func decodeHash(from container: KeyedDecodingContainer<CodingKeys>) throws -> [UInt8] {
        if let bytes = try? container.decode([UInt8].self, forKey: .hash) {
            return bytes
        }
        let prefix = "b64'"
        let suffix = "'"
        if let text = try? container.decode(String.self, forKey: .hash),
           text.count >= prefix.count + suffix.count, text.hasPrefix(prefix), text.hasSuffix(suffix),
           let data = Data(base64Encoded: String(text.dropFirst(prefix.count).dropLast(suffix.count))) {
            return [UInt8](data)
        }
        throw DecodingError.dataCorruptedError(
            forKey: .hash, in: container,
            debugDescription: "Expected an array of byte values or a b64'<base64>' string")
    }

    override open func isEqual(to other: UriOrResource) -> Bool {
        guard super.isEqual(to: other), let other = other as? HashedUri else { return false }
        return hash == other.hash && url == other.url
    }

    override open func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(hash, forKey: .hash)
        try container.encode(url, forKey: .url)
    }
}
