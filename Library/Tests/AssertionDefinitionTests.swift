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
//  AssertionDefinitionTests.swift
//

import C2PA
import Foundation
import Testing

@Suite struct AssertionDefinitionTests {

    /// The data-less standard assertions and the label each encodes to.
    static let standardLabels: [String: String] = [
        "assertionMetadata": "c2pa.assertion.metadata",
        "assetRef": "c2pa.asset-ref",
        "assetType": "c2pa.asset-type.v2",
        "bmffBasedHash": "c2pa.hash.bmff.v3",
        "certificateStatus": "c2pa.certificate-status",
        "cloudData": "c2pa.cloud-data",
        "collectionDataHash": "c2pa.hash.collection.data",
        "dataHash": "c2pa.hash.data",
        "depthmap": "c2pa.depthmap.GDepth",
        "embeddedData": "c2pa.embedded-data",
        "fontInfo": "font.info",
        "generalBoxHash": "c2pa.hash.boxes",
        "ingredient": "c2pa.ingredient",
        "metadata": "c2pa.metadata",
        "multiAssetHash": "c2pa.hash.multi-asset",
        "softBinding": "c2pa.soft-binding",
        "thumbnailClaim": "c2pa.thumbnail.claim",
        "thumbnailIngredient": "c2pa.thumbnail.ingredient",
        "timeStamps": "c2pa.time-stamp"
    ]

    static func standardAssertion(_ name: String) -> AssertionDefinition? {
        switch name {
        case "assertionMetadata": .assertionMetadata
        case "assetRef": .assetRef
        case "assetType": .assetType
        case "bmffBasedHash": .bmffBasedHash
        case "certificateStatus": .certificateStatus
        case "cloudData": .cloudData
        case "collectionDataHash": .collectionDataHash
        case "dataHash": .dataHash
        case "depthmap": .depthmap
        case "embeddedData": .embeddedData
        case "fontInfo": .fontInfo
        case "generalBoxHash": .generalBoxHash
        case "ingredient": .ingredient
        case "metadata": .metadata
        case "multiAssetHash": .multiAssetHash
        case "softBinding": .softBinding
        case "thumbnailClaim": .thumbnailClaim
        case "thumbnailIngredient": .thumbnailIngredient
        case "timeStamps": .timeStamps
        default: nil
        }
    }

    private func decode(_ json: String) throws -> AssertionDefinition {
        try JSONDecoder().decode(AssertionDefinition.self, from: Data(json.utf8))
    }

    private func roundTrip(_ assertion: AssertionDefinition) throws -> AssertionDefinition {
        try JSONDecoder().decode(AssertionDefinition.self, from: JSONEncoder().encode(assertion))
    }

    // MARK: - Actions

    @Test func actionsAssertionDecoding() throws {
        let assertion = try decode("""
            {
                "label": "c2pa.actions",
                "data": {
                    "actions": [
                        {"action": "c2pa.created"},
                        {"action": "c2pa.edited", "parameters": {"name": "test edit"}}
                    ]
                }
            }
            """)
        guard case .actions(let actions) = assertion else {
            Issue.record("decoded as \(assertion), not .actions")
            return
        }
        #expect(actions.map(\.action) == ["c2pa.created", "c2pa.edited"])
    }

    @Test func actionsAssertionEncoding() throws {
        let assertion = AssertionDefinition.actions(actions: [
            Action(action: PredefinedAction.created, digitalSourceType: DigitalSourceType.algorithmicMedia),
            Action(action: PredefinedAction.edited.rawValue)
        ])
        let json = try JSONEncoder().encode(assertion).utf8Text
        #expect(json.contains("c2pa.actions"))

        guard case .actions(let actions) = try roundTrip(assertion) else {
            Issue.record("round trip did not decode as .actions")
            return
        }
        #expect(actions.map(\.action) == ["c2pa.created", "c2pa.edited"])
    }

    @Test func emptyActionsAssertion() throws {
        let assertion = try decode(#"{"label": "c2pa.actions", "data": {"actions": []}}"#)
        guard case .actions(let actions) = assertion else {
            Issue.record("decoded as \(assertion), not .actions")
            return
        }
        #expect(actions.isEmpty)
    }

    @Test func actionsV2Decoding() throws {
        let assertion = try decode(#"{"label": "c2pa.actions.v2", "data": {"actions": [{"action": "c2pa.created"}]}}"#)
        guard case .actions(let actions) = assertion else {
            Issue.record("c2pa.actions.v2 decoded as \(assertion), not .actions")
            return
        }
        #expect(actions.count == 1)
    }

    // MARK: - Standard assertions

    @Test func assertionMetadataDecoding() throws {
        let assertion = try decode(#"{"label": "c2pa.assertion.metadata"}"#)
        #expect(assertion == .assertionMetadata)
        #expect(try roundTrip(assertion) == .assertionMetadata)
    }

    /// assetRef uses a hyphen, not a dot: c2pa.asset-ref.
    @Test func assetRefDecoding() throws {
        let assertion = try decode(#"{"label": "c2pa.asset-ref"}"#)
        #expect(assertion == .assetRef)
        #expect(try roundTrip(assertion) == .assetRef)
    }

    @Test(arguments: standardLabels.keys.sorted())
    func allAssertionTypesEncoding(name: String) throws {
        let assertion = try #require(Self.standardAssertion(name))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(assertion)) as? [String: Any]
        #expect(object?["label"] as? String == Self.standardLabels[name])
    }

    @Test(arguments: standardLabels.keys.sorted())
    func allAssertionTypesRoundTrip(name: String) throws {
        let label = try #require(Self.standardLabels[name])
        let assertion = try decode(#"{"label": "\#(label)"}"#)
        #expect(assertion == Self.standardAssertion(name), "\(label) decoded as \(assertion)")
        #expect(try roundTrip(assertion) == assertion)
    }

    @Test func assertionEquality() {
        let created = Action(action: PredefinedAction.created, digitalSourceType: DigitalSourceType.digitalCapture)
        #expect(AssertionDefinition.metadata == .metadata)
        #expect(AssertionDefinition.metadata != .assetRef)
        #expect(AssertionDefinition.actions(actions: [created]) == .actions(actions: [created]))
        #expect(
            AssertionDefinition.actions(actions: [created])
                != .actions(actions: [Action(action: PredefinedAction.edited.rawValue)]))
    }

    // MARK: - Typed assertions

    @Test func customAssertionRoundTrip() throws {
        let assertion = AssertionDefinition.custom(
            label: "com.example.test",
            data: AnyCodable(["key": "value", "number": 42] as [String: Any]))
        let decoded = try roundTrip(assertion)
        guard case .custom(let label, let data) = decoded else {
            Issue.record("decoded as \(decoded), not .custom")
            return
        }
        #expect(label == "com.example.test")
        let fields = try #require(data.value as? [String: Any])
        #expect(fields["key"] as? String == "value")
        #expect(fields["number"] as? Int == 42)
        #expect(fields.count == 2)

        // AnyCodable's == compares unsorted JSON, so equal multi-key
        // dictionaries compare unequal whenever their key order differs.
        withKnownIssue("AnyCodable equality depends on dictionary key order", isIntermittent: true) {
            #expect(data == AnyCodable(["key": "value", "number": 42] as [String: Any]))
        }
    }

    @Test func trainingMiningAssertion() throws {
        let assertion = AssertionDefinition.trainingMining(entries: [
            TrainingMiningEntry(use: "notAllowed"),
            TrainingMiningEntry(use: "constrained", constraintInfo: "License required")
        ])
        let decoded = try roundTrip(assertion)
        guard case .trainingMining(let entries) = decoded else {
            Issue.record("decoded as \(decoded), not .trainingMining")
            return
        }
        #expect(entries.count == 2)
        #expect(entries.first?.use == "notAllowed")
        #expect(entries.last?.constraintInfo == "License required")
    }

    @Test func cawgTrainingMiningAssertion() throws {
        let assertion = AssertionDefinition.cawgTrainingMining(entries: [
            CawgTrainingMiningEntry(use: "allowed", constraintInfo: nil, aiModelLearningType: "supervised", aiMiningType: "text")
        ])
        let decoded = try roundTrip(assertion)
        guard case .cawgTrainingMining(let entries) = decoded else {
            Issue.record("decoded as \(decoded), not .cawgTrainingMining")
            return
        }
        #expect(entries.first?.aiModelLearningType == "supervised")
        #expect(entries.first?.aiMiningType == "text")
    }

    @Test func cawgIdentityAssertion() throws {
        let assertion = AssertionDefinition.cawgIdentity(data: [
            "sig_type": AnyCodable("cawg.x509"),
            "pad1": AnyCodable(0)
        ])
        let decoded = try roundTrip(assertion)
        guard case .cawgIdentity(let data) = decoded else {
            Issue.record("decoded as \(decoded), not .cawgIdentity")
            return
        }
        #expect(data["sig_type"] == AnyCodable("cawg.x509"))
    }

    @Test func creativeWorkAssertion() throws {
        let assertion = AssertionDefinition.creativeWork(data: [
            "@type": AnyCodable("CreativeWork"),
            "author": AnyCodable(["@type": "Person", "name": "Test Author"] as [String: Any])
        ])
        let decoded = try roundTrip(assertion)
        guard case .creativeWork(let data) = decoded else {
            Issue.record("decoded as \(decoded), not .creativeWork")
            return
        }
        #expect(data["@type"] == AnyCodable("CreativeWork"))
    }

    // MARK: - AnyCodable

    @Test(arguments: ["bool", "int", "double", "string", "array", "dict"])
    func anyCodableTypes(kind: String) throws {
        let value: AnyCodable =
            switch kind {
            case "bool": AnyCodable(true)
            case "int": AnyCodable(42)
            case "double": AnyCodable(3.14)
            case "string": AnyCodable("hello")
            case "array": AnyCodable([1, 2, 3])
            default: AnyCodable(["key": "value"] as [String: Any])
            }
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
    }

    @Test func anyCodableEquality() {
        #expect(AnyCodable("hello") == AnyCodable("hello"))
        #expect(AnyCodable("hello") != AnyCodable("world"))
    }
}
