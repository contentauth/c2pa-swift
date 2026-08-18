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
//  AdditionalFields.swift
//

import Foundation

/// A coding key for JSON members that have no matching property.
///
/// Swift's synthesized `Codable` drops unrecognized members, whereas the c2pa-rs
/// structs these models mirror capture them in a `#[serde(flatten)]` map. Decoding
/// through this key lets a model round-trip fields it does not itself understand.
struct AdditionalFieldsCodingKey: CodingKey {
    let stringValue: String

    var intValue: Int? { nil }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        nil
    }
}

extension Decoder {
    /// Collects every member whose key is not in `known`.
    ///
    /// - Parameter known: Keys the model decodes into its own properties, including any
    ///   alias it accepts. Passing an incomplete set would duplicate a known field into
    ///   the additional-fields map and re-encode it twice.
    ///
    /// - Returns: The unrecognized members, or `nil` when there are none, so a model
    ///   that saw no extras encodes nothing rather than an empty object.
    func decodeAdditionalFields(excluding known: Set<String>) throws -> [String: AnyCodable]? {
        let container = try self.container(keyedBy: AdditionalFieldsCodingKey.self)
        var fields: [String: AnyCodable] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            fields[key.stringValue] = try container.decode(AnyCodable.self, forKey: key)
        }
        return fields.isEmpty ? nil : fields
    }
}

extension Encoder {
    /// Writes previously unrecognized members back alongside the model's own keys.
    ///
    /// Keys in `known` are skipped: the model has already encoded those itself, and
    /// encoding the same key twice into one container traps at runtime.
    func encodeAdditionalFields(_ fields: [String: AnyCodable]?, excluding known: Set<String>) throws {
        guard let fields, !fields.isEmpty else { return }
        var container = self.container(keyedBy: AdditionalFieldsCodingKey.self)
        for (key, value) in fields where !known.contains(key) {
            try container.encode(value, forKey: AdditionalFieldsCodingKey(key))
        }
    }
}
