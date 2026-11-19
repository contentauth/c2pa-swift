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
//  ManifestTests.swift
//

import C2PA
import Foundation
import Testing

@Suite struct ManifestTests {

    // MARK: - Definitions

    @Test func minimal() throws {
        let manifest = ManifestDefinition(claimGeneratorInfo: [], title: "test")
        #expect(manifest.claimVersion == 2)
        #expect(manifest.format == "application/octet-stream")
        #expect(manifest.title == "test")
        try expectRoundTrip(manifest)
    }

    @Test func created() throws {
        let manifest = ManifestDefinition(
            assertions: [.actions(actions: [.init(action: .created, digitalSourceType: .digitalCapture)])],
            claimGeneratorInfo: [.init()],
            title: "test")

        guard case .actions(let actions) = try #require(manifest.assertions.first) else {
            Issue.record("first assertion is not .actions")
            return
        }
        let action = try #require(actions.first)
        #expect(action.action == "c2pa.created")
        #expect(action.digitalSourceType == "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture")

        // The default claim generator describes the running app, which for a
        // hosted test bundle is the TestHost app.
        let info = try #require(manifest.claimGeneratorInfo.first)
        #expect(info.name == "TestHost")
        let version = try #require(info.version)
        #expect(version.range(of: #"^[\d.]+$"#, options: .regularExpression) != nil, "version \(version) is not dotted digits")

        try expectRoundTrip(manifest)
    }

    @Test func enumRendering() throws {
        let shape = Shape(type: .rectangle, origin: .init(x: 10, y: 10), width: 80, height: 80, unit: .percent)
        let data = try JSONEncoder().encode(shape)
        #expect(try JSONDecoder().decode(Shape.self, from: data) == shape, "JSON: \(data.utf8Text)")
    }

    @Test func regionOfInterest() {
        let range = RegionRange(type: .frame)
        #expect(RegionOfInterest(region: [range], type: .animal) == RegionOfInterest(region: [range], type: .animal))
    }

    @Test func resourceRef() throws {
        let ref = ResourceRef(format: "application/octet-string", identifier: "")
        let data = try JSONEncoder().encode(ref)
        #expect(try JSONDecoder().decode(ResourceRef.self, from: data) == ref)
    }

    @Test func hashedUri() throws {
        let uri = HashedUri(hash: [], url: "foo")
        let data = try JSONEncoder().encode(uri)
        #expect(try JSONDecoder().decode(HashedUri.self, from: data) == uri)
    }

    @Test func uriOrResource() {
        #expect(UriOrResource(alg: "foo") == UriOrResource(alg: "foo"))
    }

    @Test func massInit() {
        #expect(Ingredient().title == nil)

        let statusCodes = StatusCodes(failure: [], informational: [], success: [])
        #expect(statusCodes.failure.isEmpty && statusCodes.informational.isEmpty && statusCodes.success.isEmpty)

        #expect(Metadata().dateTime == nil)
        #expect(ValidationStatus(code: .algorithmUnsupported).code == .algorithmUnsupported)

        let time = Time()
        #expect(time.start == nil && time.end == nil)

        let textSelector = TextSelector(fragment: "test-fragment")
        #expect(textSelector.fragment == "test-fragment")

        let reviewRating = ReviewRating(explanation: "test explanation", value: 5)
        #expect(reviewRating.explanation == "test explanation" && reviewRating.value == 5)

        #expect(DataSource(type: "test-type").type == "test-type")
        #expect(MetadataActor().identifier == nil)
        #expect(ValidationResults().activeManifest == nil)

        let delta = IngredientDeltaValidationResult(ingredientAssertionUri: "test-uri", validationDeltas: statusCodes)
        #expect(delta.ingredientAssertionUri == "test-uri")

        let item = Item(identifier: "track_id", value: "2")
        #expect(item.identifier == "track_id" && item.value == "2")

        #expect(AssetType(type: "image/jpeg").type == "image/jpeg")

        let frame = Frame()
        #expect(frame.start == nil && frame.end == nil)

        let textSelectorRange = TextSelectorRange(selector: textSelector)
        #expect(textSelectorRange.selector.fragment == "test-fragment")
        #expect(Text(selectors: [textSelectorRange]).selectors.count == 1)
    }

    @Test(arguments: [
        (PredefinedAction.mastered, "c2pa.mastered"),
        (.mixed, "c2pa.mixed"),
        (.remixed, "c2pa.remixed"),
        (.resizedProportional, "c2pa.resized.proportional"),
        (.watermarkedBound, "c2pa.watermarked.bound"),
        (.watermarkedUnbound, "c2pa.watermarked.unbound"),
        (.fontCharactersAdded, "font.charactersAdded"),
        (.fontCharactersDeleted, "font.charactersDeleted"),
        (.fontCharactersModified, "font.charactersModified"),
        (.fontCreatedFromVariableFont, "font.createdFromVariableFont"),
        (.fontEdited, "font.edited"),
        (.fontHinted, "font.hinted"),
        (.fontMerged, "font.merged"),
        (.fontOpenTypeFeatureAdded, "font.openTypeFeatureAdded"),
        (.fontOpenTypeFeatureModified, "font.openTypeFeatureModified"),
        (.fontOpenTypeFeatureRemoved, "font.openTypeFeatureRemoved"),
        (.fontSubset, "font.subset")
    ])
    func newPredefinedActions(action: PredefinedAction, expected: String) {
        #expect(action.rawValue == expected)
    }

    // MARK: - Actions

    @Test func actionV2SoftwareAgent() throws {
        let v1 = Action(action: "c2pa.created", softwareAgent: "MyApp/1.0")
        #expect(v1.softwareAgentString == "MyApp/1.0")
        #expect(v1.softwareAgentInfo == nil, "a string agent has no object form")

        let v2 = Action(action: .created, softwareAgentInfo: ClaimGeneratorInfo(name: "TestApp", version: "2.0"))
        #expect(v2.softwareAgentString == nil, "an object agent has no string form")
        #expect(try #require(v2.softwareAgentInfo).name == "TestApp")
    }

    @Test func actionNewFields() throws {
        let action = Action(
            action: "c2pa.created",
            digitalSourceType: "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",
            softwareAgent: "TestApp",
            when: "2026-03-12T10:00:00Z",
            reason: "Initial capture"
        )
        #expect(action.when == "2026-03-12T10:00:00Z")
        #expect(action.reason == "Initial capture")
        #expect(action.changes == nil)
        #expect(action.related == nil)

        let data = try JSONEncoder().encode(action)
        #expect(try JSONDecoder().decode(Action.self, from: data) == action)
    }

    /// Guards the JSON key names themselves, which a Swift encode/decode round
    /// trip cannot catch: c2pa-rs renames these fields to camelCase and defines
    /// no snake_case aliases, so a mismatch silently drops the values.
    @Test func actionWireKeys() throws {
        let action = Action(
            action: "c2pa.created",
            digitalSourceType: "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",
            softwareAgent: "TestApp"
        )
        let json = try JSONEncoder().encode(action).utf8Text
        for key in ["\"digitalSourceType\"", "\"softwareAgent\""] {
            #expect(json.contains(key), "encoded JSON is missing \(key): \(json)")
        }
        for key in ["\"digital_source_type\"", "\"software_agent\""] {
            #expect(!json.contains(key), "encoded JSON uses snake_case \(key): \(json)")
        }

        // Decoding must accept the camelCase form c2pa-rs actually emits.
        let wireJSON = """
            {"action":"c2pa.created",\
            "digitalSourceType":"http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",\
            "softwareAgent":"TestApp"}
            """
        let decoded = try JSONDecoder().decode(Action.self, from: Data(wireJSON.utf8))
        #expect(decoded.digitalSourceType?.hasSuffix("digitalCapture") == true)
        #expect(decoded.softwareAgentString == "TestApp")
    }

    /// One model's encoded form paired with the wire keys c2pa-rs expects from it.
    struct WireKeyCheck: CustomTestStringConvertible, Sendable {
        let model: String
        let encoded: Data
        let expected: [String]
        var testDescription: String { model }
    }

    /// The wire names c2pa-rs reads and writes, verified against its serde
    /// attributes. Manifest assertions carry explicit camelCase renames, while
    /// other structs keep Rust's snake_case default, so these are checked rather
    /// than inferred.
    static func wireKeyChecks() throws -> [WireKeyCheck] {
        let hashedUri = HashedUri(hash: [0x01, 0x02], url: "self#jumbf=c2pa.assertions/c2pa.actions")
        let statusCodes = StatusCodes(failure: [], informational: [], success: [])
        let encoder = JSONEncoder()
        return [
            WireKeyCheck(
                model: "Action",
                encoded: try encoder.encode(
                    Action(
                        action: "c2pa.created",
                        digitalSourceType: "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",
                        softwareAgent: "TestApp")),
                expected: ["digitalSourceType", "softwareAgent"]),
            WireKeyCheck(
                model: "Ingredient",
                encoded: try encoder.encode(
                    Ingredient(
                        activeManifest: "urn:c2pa:test",
                        dataTypes: [],
                        documentId: "doc-1",
                        informationalUri: "https://example.org/info",
                        instanceId: "instance-1",
                        validationResults: ValidationResults(activeManifest: statusCodes),
                        validationStatus: [])),
                expected: [
                    "active_manifest", "data_types", "document_id", "informational_URI",
                    "instance_id", "validation_results", "validation_status"
                ]),
            WireKeyCheck(
                model: "ValidationResults",
                encoded: try encoder.encode(ValidationResults(activeManifest: statusCodes, ingredientDeltas: [])),
                expected: ["activeManifest", "ingredientDeltas"]),
            WireKeyCheck(
                model: "IngredientDeltaValidationResult",
                encoded: try encoder.encode(
                    IngredientDeltaValidationResult(
                        ingredientAssertionUri: "self#jumbf=c2pa.assertions/c2pa.ingredient",
                        validationDeltas: statusCodes)),
                expected: ["ingredientAssertionURI", "validationDeltas"]),
            WireKeyCheck(
                model: "Metadata",
                encoded: try encoder.encode(
                    Metadata(
                        dataSource: DataSource(type: "signer"),
                        dateTime: Date(timeIntervalSince1970: 0),
                        reference: hashedUri,
                        reviewRatings: [ReviewRating(explanation: "ok", value: 5)])),
                expected: ["dataSource", "dateTime", "reviewRatings"]),
            WireKeyCheck(
                model: "ClaimGeneratorInfo",
                encoded: try encoder.encode(ClaimGeneratorInfo(name: "TestApp", operatingSystem: "iOS")),
                expected: ["operating_system"]),
            WireKeyCheck(
                model: "ResourceRef",
                encoded: try encoder.encode(ResourceRef(dataTypes: [], format: "image/jpeg", identifier: "self#jumbf=c2pa")),
                expected: ["data_types"]),
            WireKeyCheck(
                model: "ManifestDefinition",
                encoded: try encoder.encode(
                    ManifestDefinition(
                        claimGeneratorInfo: [ClaimGeneratorInfo(name: "TestApp")],
                        instanceId: "instance-1",
                        title: "wire-key drift check")),
                expected: ["claim_generator_info", "claim_version", "instance_id"])
        ]
    }

    /// Reports a key whose spelling drifted (same name modulo case and
    /// underscores) separately from one that is missing outright: c2pa-rs defines
    /// no aliases, so a drifted key is silently dropped rather than rejected.
    @Test(arguments: try wireKeyChecks())
    func manifestWireKeyDrift(check: WireKeyCheck) throws {
        let object = try JSONSerialization.jsonObject(with: check.encoded)
        let keys = Set(try #require(object as? [String: Any], "encoded JSON is not an object").keys)
        func normalized(_ key: String) -> String { key.replacingOccurrences(of: "_", with: "").lowercased() }
        for key in check.expected where !keys.contains(key) {
            if let drifted = keys.first(where: { normalized($0) == normalized(key) }) {
                Issue.record("expected key '\(key)' but found '\(drifted)'")
            } else {
                Issue.record("expected key '\(key)' is absent (encoded: \(keys.sorted()))")
            }
        }
    }

    // MARK: - Unknown fields

    /// c2pa-rs keeps unrecognized members in a flattened map, so a manifest
    /// written by another generator must survive a decode/encode cycle here.
    @Test func claimGeneratorInfoPreservesUnknownFields() throws {
        let source = """
            {"name":"Other/1.0","operating_system":"iOS 18",\
            "vendorSpecific":{"channel":"beta"},"buildCount":7}
            """
        let decoded = try JSONDecoder().decode(ClaimGeneratorInfo.self, from: Data(source.utf8))
        let extras = try #require(decoded.additionalFields)
        #expect(Set(extras.keys) == ["vendorSpecific", "buildCount"])
        #expect(extras["name"] == nil, "a modeled key leaked into additionalFields")

        let reencoded = try JSONEncoder().encode(decoded)
        let json = reencoded.utf8Text
        for key in ["\"vendorSpecific\"", "\"buildCount\"", "\"operating_system\""] {
            #expect(json.contains(key), "re-encoded JSON dropped \(key): \(json)")
        }
        #expect(try JSONDecoder().decode(ClaimGeneratorInfo.self, from: reencoded) == decoded, "round trip is not stable")
    }

    /// c2pa-rs accepts the schema.org spelling when decoding but always writes
    /// operating_system, so decoding must accept both and encoding must normalize.
    @Test func claimGeneratorInfoOperatingSystemAlias() throws {
        let aliased = """
            {"name":"Other/1.0","schema.org.SoftwareApplication.operatingSystem":"macOS 15"}
            """
        let decoded = try JSONDecoder().decode(ClaimGeneratorInfo.self, from: Data(aliased.utf8))
        #expect(decoded.operatingSystem == "macOS 15")
        #expect(decoded.additionalFields == nil, "the alias key leaked into additionalFields")

        let json = try JSONEncoder().encode(decoded).utf8Text
        #expect(json.contains("\"operating_system\""))
        #expect(!json.contains("schema.org"), "re-encoded using the alias spelling: \(json)")
    }

    /// The C2PA metadata object is explicitly open-ended.
    @Test func metadataPreservesUnknownFields() throws {
        let source = """
            {"dataSource":{"type":"signer"},"org.example.custom":"kept","weight":3}
            """
        let decoded = try JSONDecoder().decode(Metadata.self, from: Data(source.utf8))
        #expect(Set(try #require(decoded.additionalFields).keys) == ["org.example.custom", "weight"])
        #expect(decoded.dataSource?.type == "signer")

        let json = try JSONEncoder().encode(decoded).utf8Text
        for key in ["\"org.example.custom\"", "\"weight\"", "\"dataSource\""] {
            #expect(json.contains(key), "re-encoded JSON dropped \(key): \(json)")
        }
    }

    // MARK: - Validation

    @Test func validateAndLog() {
        let manifest = ManifestDefinition(claimGeneratorInfo: [ClaimGeneratorInfo()], title: "test")
        let result = ManifestValidator.validateAndLog(manifest)
        #expect(result.isValid, "errors: \(result.errors)")
    }

    @Test func customAssertionLabelValidation() {
        let bare = ManifestDefinition(
            assertions: [.custom(label: "nolabel", data: AnyCodable("test"))],
            claimGeneratorInfo: [ClaimGeneratorInfo()],
            title: "test")
        let warnings = ManifestValidator.validate(bare).warnings
        #expect(warnings.contains { $0.contains("namespaced format") }, "warnings: \(warnings)")

        let namespaced = ManifestDefinition(
            assertions: [.custom(label: "com.example.test", data: AnyCodable("test"))],
            claimGeneratorInfo: [ClaimGeneratorInfo()],
            title: "test")
        #expect(!ManifestValidator.validate(namespaced).warnings.contains { $0.contains("namespaced format") })
    }

    @Test func validatorEmptyTitle() {
        let result = ManifestValidator.validate(ManifestDefinition(claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")], title: ""))
        #expect(result.errors.contains { $0.contains("title") }, "errors: \(result.errors)")
    }

    @Test func validatorEmptyClaimGeneratorInfo() {
        let result = ManifestValidator.validate(ManifestDefinition(claimGeneratorInfo: [], title: "test"))
        #expect(result.errors.contains { $0.contains("claim_generator_info") }, "errors: \(result.errors)")
    }

    @Test func validatorOldClaimVersion() {
        let result = ManifestValidator.validate(
            ManifestDefinition(claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")], claimVersion: 1, title: "test"))
        #expect(result.warnings.contains { $0.contains("outdated") }, "warnings: \(result.warnings)")
    }

    @Test func validatorDeprecatedAssertionLabels() {
        let result = ManifestValidator.validate(
            ManifestDefinition(
                assertions: [.custom(label: "stds.exif", data: AnyCodable("test"))],
                claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
                title: "test"))
        #expect(result.warnings.contains { $0.contains("Deprecated") && $0.contains("stds.exif") }, "warnings: \(result.warnings)")
    }

    @Test func validatorCawgAssertionAccepted() {
        let result = ManifestValidator.validate(
            ManifestDefinition(
                assertions: [.cawgIdentity(data: ["test": AnyCodable("value")])],
                claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
                title: "test"))
        #expect(result.isValid, "errors: \(result.errors)")
    }

    @Test func validatorMultipleParents() {
        let result = ManifestValidator.validate(
            ManifestDefinition(
                claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
                ingredients: [.parent(title: "parent1.jpg"), .parent(title: "parent2.jpg")],
                title: "test"))
        #expect(result.warnings.contains { $0.contains("Multiple parent") }, "warnings: \(result.warnings)")
    }

    @Test func validateJSON() throws {
        let json = try ManifestDefinition(claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")], title: "test").toJSON()
        let result = ManifestValidator.validateJSON(json)
        #expect(result.isValid, "errors: \(result.errors)")
    }

    @Test func validateJSONInvalid() {
        #expect(!ManifestValidator.validateJSON("not valid json {{{").isValid)
    }

    // MARK: - Factories and conveniences

    @Test func createdFactory() throws {
        let manifest = ManifestDefinition.created(
            title: "photo.jpg",
            claimGeneratorInfo: ClaimGeneratorInfo(name: "TestApp"),
            digitalSourceType: .digitalCapture)
        guard case .actions(let actions) = try #require(manifest.assertions.first) else {
            Issue.record("first assertion is not .actions")
            return
        }
        #expect(actions.first?.action == PredefinedAction.created.rawValue)
    }

    @Test func editedFactory() {
        let manifest = ManifestDefinition.edited(
            title: "edited.jpg",
            claimGeneratorInfo: ClaimGeneratorInfo(name: "TestApp"),
            parentIngredient: Ingredient.parent(title: "original.jpg"),
            editActions: [Action(action: PredefinedAction.cropped.rawValue)])
        #expect(manifest.ingredients.count == 1)
        #expect(manifest.ingredients.first?.relationship == .parentOf)
    }

    @Test func mixedAssertions() {
        let manifest = ManifestDefinition(
            assertions: [.metadata, .cawgIdentity(data: ["sig_type": AnyCodable("cawg.x509")])],
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "TestApp")],
            title: "test.jpg")
        #expect(manifest.assertions.count == 2)
        #expect(manifest.assertions.last?.baseLabel == "cawg.identity")
    }

    @Test func assertionLabels() {
        let manifest = ManifestDefinition(
            assertions: [.metadata, .metadata, .dataHash],
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "TestApp")],
            title: "test.jpg")
        let labels = manifest.assertionLabels()
        #expect(labels.contains("c2pa.metadata"))
        #expect(labels.contains("c2pa.hash.data"))
    }

    @Test func toJSON() throws {
        let json = try ManifestDefinition(claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")], title: "json.jpg").toJSON()
        #expect(json.contains("json.jpg"))
    }

    @Test func toPrettyJSON() throws {
        let json = try ManifestDefinition(claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")], title: "pretty.jpg").toPrettyJSON()
        #expect(json.contains("\n"))
    }

    @Test func fromJSON() throws {
        let json = try ManifestDefinition(claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")], title: "fromjson.jpg").toJSON()
        #expect(try ManifestDefinition.fromJSON(json).title == "fromjson.jpg")
    }

    @Test func descriptionContainsTitle() {
        #expect(ManifestDefinition(claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")], title: "desc.jpg").description.contains("desc.jpg"))
    }

    @Test func ingredientParentFactory() {
        let ingredient = Ingredient.parent(title: "parent.jpg", format: "image/jpeg")
        #expect(ingredient.relationship == .parentOf)
        #expect(ingredient.title == "parent.jpg")
    }

    @Test func ingredientComponentFactory() {
        #expect(Ingredient.component(title: "watermark.png").relationship == .componentOf)
    }

    @Test func ingredientInputToFactory() {
        #expect(Ingredient.inputTo(title: "training.jpg").relationship == .inputTo)
    }

    // MARK: - Builder validation

    @Test func builderInitManifestValid() throws {
        let manifest = ManifestDefinition.created(
            title: "test.jpg",
            claimGeneratorInfo: ClaimGeneratorInfo(name: "TestApp", version: "1.0"),
            digitalSourceType: .digitalCapture)
        #expect(try Fixtures.signAndRead(Builder(manifest: manifest)).actions() == ["c2pa.created"])
    }

    @Test func builderInitManifestInvalid() throws {
        let error = try #require(throws: C2PAError.self) {
            try Builder(manifest: ManifestDefinition(claimGeneratorInfo: [], title: ""))
        }
        guard case .manifestValidationFailed(let result) = error else {
            Issue.record("expected manifestValidationFailed, got \(error)")
            return
        }
        #expect(result.hasErrors)
    }

    /// init(manifestJSON:) does not validate; the C layer rejects invalid JSON.
    @Test func builderInitJSONInvalid() {
        #expect(throws: C2PAError.self) {
            try Builder(manifestJSON: "not valid json")
        }
    }

    // MARK: - Helpers

    /// The manifest's description is its JSON; decoding it must give the same manifest.
    private func expectRoundTrip(_ manifest: ManifestDefinition, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let decoded = try JSONDecoder().decode(ManifestDefinition.self, from: Data(manifest.description.utf8))
        #expect(decoded == manifest, "\(manifest.description) != \(decoded.description)", sourceLocation: sourceLocation)
    }
}
