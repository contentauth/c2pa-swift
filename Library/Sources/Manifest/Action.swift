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
//  Action.swift
//

import Foundation

/// An action performed on the asset, used in C2PA manifest assertions.
///
/// In C2PA v2, `softwareAgent` may be either a plain string (v1 format) or a
/// `ClaimGeneratorInfo` object (v2 format). Use ``softwareAgentString`` or
/// ``softwareAgentInfo`` to access the value in the desired format.
///
/// - SeeAlso: [Actions Reference](https://opensource.contentauthenticity.org/docs/manifest/writing/assertions-actions#actions)
public struct Action: Codable, Equatable {

    public enum CodingKeys: String, CodingKey {
        case action
        case digitalSourceType = "digitalSourceType"
        case softwareAgent = "softwareAgent"
        case parameters
        case when
        case changes
        case related
        case reason
    }

    /// The action name. Most probably a ``PredefinedAction``.
    public var action: String

    /// A URL identifying an IPTC term. Most probably a ``DigitalSourceType``.
    public var digitalSourceType: String?

    /// The software or hardware used to perform the action.
    ///
    /// In C2PA v1, this is a plain string. In v2, it can be a ``ClaimGeneratorInfo`` object.
    /// Use ``softwareAgentString`` or ``softwareAgentInfo`` to access the typed value.
    public var softwareAgent: AnyCodable?

    /// Additional information describing the action.
    public var parameters: [String: AnyCodable]?

    /// The timestamp when the action was performed (ISO 8601 format).
    public var when: String?

    /// Regions of interest describing what changed.
    public var changes: [RegionOfInterest]?

    /// Related ingredient labels.
    public var related: [String]?

    /// The reason for performing the action (e.g., "c2pa.PII.present").
    public var reason: String?

    // MARK: - Computed Properties

    /// Returns the softwareAgent as a string if it is a plain string value, nil otherwise.
    public var softwareAgentString: String? {
        softwareAgent?.value as? String
    }

    /// Returns the softwareAgent as a ``ClaimGeneratorInfo`` if it is an object, nil otherwise.
    public var softwareAgentInfo: ClaimGeneratorInfo? {
        guard let dict = softwareAgent?.value as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let info = try? JSONDecoder().decode(ClaimGeneratorInfo.self, from: data)
        else { return nil }
        return info
    }

    // MARK: - Initializers

    /// Creates an action with full control over all fields.
    ///
    /// - Parameters:
    ///   - action: The action name. Most probably a ``PredefinedAction``.
    ///   - digitalSourceType: A URL identifying an IPTC term. Most probably a ``DigitalSourceType``.
    ///   - softwareAgent: The software or hardware used to perform the action (string or object).
    ///   - parameters: Additional information describing the action.
    ///   - when: The timestamp when the action was performed (ISO 8601 format).
    ///   - changes: Regions of interest describing what changed.
    ///   - related: Related ingredient labels.
    ///   - reason: The reason for performing the action.
    public init(
        action: String,
        digitalSourceType: String? = nil,
        softwareAgent: AnyCodable? = nil,
        parameters: [String: AnyCodable]? = nil,
        when: String? = nil,
        changes: [RegionOfInterest]? = nil,
        related: [String]? = nil,
        reason: String? = nil
    ) {
        self.action = action
        self.digitalSourceType = digitalSourceType
        self.softwareAgent = softwareAgent
        self.parameters = parameters
        self.when = when
        self.changes = changes
        self.related = related
        self.reason = reason
    }

    /// Creates an action with a string softwareAgent (v1 format).
    ///
    /// - Parameters:
    ///   - action: The action name. Most probably a ``PredefinedAction``.
    ///   - digitalSourceType: A URL identifying an IPTC term. Most probably a ``DigitalSourceType``.
    ///   - softwareAgent: The software or hardware used to perform the action. Defaults to the app name.
    ///   - parameters: Additional information describing the action.
    ///   - when: The timestamp when the action was performed (ISO 8601 format).
    ///   - changes: Regions of interest describing what changed.
    ///   - related: Related ingredient labels.
    ///   - reason: The reason for performing the action.
    public init(
        action: String,
        digitalSourceType: String? = nil,
        softwareAgent: String?,
        parameters: [String: AnyCodable]? = nil,
        when: String? = nil,
        changes: [RegionOfInterest]? = nil,
        related: [String]? = nil,
        reason: String? = nil
    ) {
        self.init(
            action: action,
            digitalSourceType: digitalSourceType,
            softwareAgent: softwareAgent.map { AnyCodable($0) },
            parameters: parameters,
            when: when,
            changes: changes,
            related: related,
            reason: reason
        )
    }

    /// Creates an action with a ``PredefinedAction`` and ``DigitalSourceType``.
    ///
    /// - Parameters:
    ///   - action: The action name as a ``PredefinedAction``.
    ///   - digitalSourceType: A URL identifying an IPTC term as a ``DigitalSourceType``.
    ///   - softwareAgent: The software or hardware used to perform the action. Defaults to the app name.
    ///   - parameters: Additional information describing the action.
    ///   - when: The timestamp when the action was performed (ISO 8601 format).
    ///   - changes: Regions of interest describing what changed.
    ///   - related: Related ingredient labels.
    ///   - reason: The reason for performing the action.
    public init(
        action: PredefinedAction,
        digitalSourceType: DigitalSourceType,
        softwareAgent: String? = ClaimGeneratorInfo.appName,
        parameters: [String: AnyCodable]? = nil,
        when: String? = nil,
        changes: [RegionOfInterest]? = nil,
        related: [String]? = nil,
        reason: String? = nil
    ) {
        self.init(
            action: action.rawValue,
            digitalSourceType: digitalSourceType.rawValue,
            softwareAgent: softwareAgent,
            parameters: parameters,
            when: when,
            changes: changes,
            related: related,
            reason: reason
        )
    }

    /// Creates an action with a ``ClaimGeneratorInfo`` as v2 softwareAgent.
    ///
    /// - Parameters:
    ///   - action: The action name as a ``PredefinedAction``.
    ///   - digitalSourceType: A URL identifying an IPTC term as a ``DigitalSourceType``.
    ///   - softwareAgentInfo: The v2 ``ClaimGeneratorInfo`` for the software that performed the action.
    ///   - parameters: Additional information describing the action.
    ///   - when: The timestamp when the action was performed (ISO 8601 format).
    ///   - changes: Regions of interest describing what changed.
    ///   - related: Related ingredient labels.
    ///   - reason: The reason for performing the action.
    public init(
        action: PredefinedAction,
        digitalSourceType: DigitalSourceType? = nil,
        softwareAgentInfo: ClaimGeneratorInfo,
        parameters: [String: AnyCodable]? = nil,
        when: String? = nil,
        changes: [RegionOfInterest]? = nil,
        related: [String]? = nil,
        reason: String? = nil
    ) {
        let agentData = try? JSONEncoder().encode(softwareAgentInfo)
        let agentDict = agentData.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        self.init(
            action: action.rawValue,
            digitalSourceType: digitalSourceType?.rawValue,
            softwareAgent: agentDict.map { AnyCodable($0) },
            parameters: parameters,
            when: when,
            changes: changes,
            related: related,
            reason: reason
        )
    }

    // MARK: - Equatable

    public static func == (lhs: Action, rhs: Action) -> Bool {
        lhs.action == rhs.action
            && lhs.digitalSourceType == rhs.digitalSourceType
            && lhs.softwareAgent == rhs.softwareAgent
            && lhs.parameters == rhs.parameters
            && lhs.when == rhs.when
            && lhs.changes == rhs.changes
            && lhs.related == rhs.related
            && lhs.reason == rhs.reason
    }
}
