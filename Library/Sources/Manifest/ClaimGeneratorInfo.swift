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
//  ClaimGeneratorInfo.swift
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Description of the claim generator, or the software used in generating the claim.
/// - SeeAlso: [ClaimGeneratorInfo Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema#claimgeneratorinfo)
public struct ClaimGeneratorInfo: Codable, Equatable {

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case icon
        case name
        case operatingSystem = "operating_system"
        case version
    }

    /// The alternate spelling c2pa-rs accepts for ``operatingSystem`` when decoding.
    /// It always writes `operating_system`, so this is only ever read, never written.
    static let operatingSystemAlias = "schema.org.SoftwareApplication.operatingSystem"

    private static let knownKeys = Set(CodingKeys.allCases.map(\.rawValue) + [operatingSystemAlias])

    /// Hashed URI to the icon (either embedded or remote).
    public var icon: UriOrResource?

    /// A human readable string naming the claim_generator.
    public var name: String

    /// A human readable string of the OS the claim generator is running on.
    public var operatingSystem: String?

    /// A human readable string of the product’s version
    public var version: String?

    /// Members of the decoded object that this type does not model.
    ///
    /// c2pa-rs keeps these in a flattened map, so a manifest written by another
    /// generator survives a decode/encode cycle here rather than losing them.
    public var additionalFields: [String: AnyCodable]?

    /// - Parameters:
    ///   - icon: Hashed URI to the icon (either embedded or remote).
    ///   - name: A human readable string naming the claim_generator. *(This is automatically evaluated by default. You should not set this yourself!)*
    ///   - operatingSystem: A human readable string of the OS the claim generator is running on. *(You should use ClaimGeneratorInfo.operatingSystem to fill this!)*
    ///   - version: A human readable string of the product’s version. *(This is automatically evaluated by default. You should not set this yourself!)*
    public init(
        icon: UriOrResource? = nil,
        name: String = ClaimGeneratorInfo.appName,
        operatingSystem: String? = nil,
        version: String? = ClaimGeneratorInfo.appVersion,
        additionalFields: [String: AnyCodable]? = nil
    ) {
        self.icon = icon
        self.name = name
        self.operatingSystem = operatingSystem
        self.version = version
        self.additionalFields = additionalFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        icon = try container.decodeIfPresent(UriOrResource.self, forKey: .icon)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)

        if let value = try container.decodeIfPresent(String.self, forKey: .operatingSystem) {
            operatingSystem = value
        } else {
            let aliased = try decoder.container(keyedBy: AdditionalFieldsCodingKey.self)
            operatingSystem = try aliased.decodeIfPresent(
                String.self, forKey: AdditionalFieldsCodingKey(Self.operatingSystemAlias))
        }

        additionalFields = try decoder.decodeAdditionalFields(excluding: Self.knownKeys)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(operatingSystem, forKey: .operatingSystem)
        try container.encodeIfPresent(version, forKey: .version)
        try encoder.encodeAdditionalFields(additionalFields, excluding: Self.knownKeys)
    }

#if os(macOS)
    public static var operatingSystem: String {
        "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
#elseif canImport(UIKit)
    @MainActor
    public static var operatingSystem: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }
#endif

    public static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
            ?? ""
    }

    public static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
