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
//  ManifestSchemaConformanceTests.swift
//

import C2PA
import Foundation
import Testing

/// Checks the manifest models against the ManifestDefinition schema c2pa-rs
/// exports, and the Builder and Reader schemas against that one.
///
/// c2pa-rs ignores manifest keys it does not know, so a key that drifts is
/// dropped without an error. Regenerate the schemas with `make update-schemas`
/// after changing `C2PA_VERSION`; what fails here is what drifted.
@Suite struct ManifestSchemaConformanceTests {

    private static let schemaName = "ManifestDefinition.schema.json"

    // MARK: - Samples

    // Every sample sets every property, so each key the model has is encoded.

    private static let digitalCapture = DigitalSourceType.digitalCapture.rawValue

    private static func assetType() -> AssetType {
        AssetType(type: "c2pa.types.dataset", version: "1.0")
    }

    private static func hashedUri() -> HashedUri {
        HashedUri(alg: "sha256", hash: [0, 96, 128, 255], url: "self#jumbf=c2pa.assertions/c2pa.actions.v2")
    }

    private static func resourceRef() -> ResourceRef {
        ResourceRef(
            alg: "sha256", dataTypes: [assetType()], format: "image/jpeg", hash: "Lzh2bGFo", identifier: "thumbnail.jpg")
    }

    private static func actor() -> MetadataActor {
        MetadataActor(credentials: [hashedUri()], identifier: "did:web:example.com")
    }

    private static func dataSource() -> DataSource {
        DataSource(actors: [actor()], details: "From the camera", type: "localProvider.REE")
    }

    private static func reviewRating() -> ReviewRating {
        ReviewRating(code: "actions.unknownActionsPerformed", explanation: "Reviewed", value: 4)
    }

    private static func coordinate() -> Coordinate {
        Coordinate(x: 0.25, y: 12)
    }

    private static func frame() -> Frame {
        Frame(end: 48, start: 24)
    }

    private static func item() -> Item {
        Item(identifier: "track_id", value: "2")
    }

    private static func textSelector() -> TextSelector {
        TextSelector(end: 120, fragment: "xpointer(/doc/chapter[2])", start: 80)
    }

    private static func textSelectorRange() -> TextSelectorRange {
        TextSelectorRange(end: textSelector(), selector: textSelector())
    }

    private static func text() -> Text {
        Text(selectors: [textSelectorRange()])
    }

    private static func time() -> Time {
        Time(end: "00:00:10", start: "00:00:02", type: .npt)
    }

    private static func shape() -> Shape {
        Shape(
            type: .polygon, origin: coordinate(), width: 100, height: 50.5, vertices: [coordinate(), coordinate()],
            inside: false, unit: .percent)
    }

    private static func range() -> RegionRange {
        RegionRange(frame: frame(), item: item(), shape: shape(), text: text(), time: time(), type: .spatial)
    }

    private static func regionOfInterest() -> RegionOfInterest {
        RegionOfInterest(
            description: "The cropped area",
            identifier: "region-1",
            // A region's metadata may hold a region again; one level is enough here.
            metadata: Metadata(dateTime: "2026-01-02T03:04:05Z"),
            name: "Crop",
            region: [range()],
            type: ImageRegionType.human.rawValue)
    }

    private static func metadata() -> Metadata {
        Metadata(
            dataSource: dataSource(),
            dateTime: "2026-01-02T03:04:05Z",
            localizations: [["dc:title": ["en-US": "Kevin's Five Cats", "es-MX": "Los Cinco Gatos de Kevin"]]],
            reference: hashedUri(),
            regionOfInterest: regionOfInterest(),
            reviewRatings: [reviewRating()])
    }

    private static func claimGeneratorInfo(icon: UriOrResource) -> ClaimGeneratorInfo {
        ClaimGeneratorInfo(
            icon: icon, name: "TestApp", operatingSystem: "arm64-apple-ios", specVersion: "2.4.0", version: "1.0")
    }

    private static func validationStatus() -> ValidationStatus {
        ValidationStatus(
            code: .claimSignatureValidated, explanation: "claim signature valid", success: true,
            url: "self#jumbf=c2pa.signature")
    }

    private static func statusCodes() -> StatusCodes {
        StatusCodes(failure: [validationStatus()], informational: [validationStatus()], success: [validationStatus()])
    }

    private static func ingredientDelta() -> IngredientDeltaValidationResult {
        IngredientDeltaValidationResult(
            ingredientAssertionUri: "self#jumbf=c2pa.assertions/c2pa.ingredient.v3", validationDeltas: statusCodes())
    }

    private static func validationResults() -> ValidationResults {
        ValidationResults(
            activeManifest: statusCodes(),
            ingredientDeltas: [ingredientDelta()],
            specVersion: "2.4.0",
            timestampTrustListUri: "https://example.com/tsa-trust-list",
            trustListUri: "https://example.com/trust-list",
            validationTime: "2026-01-02T03:04:05Z")
    }

    private static func ingredient() -> Ingredient {
        Ingredient(
            activeManifest: "urn:c2pa:11111111-2222-3333-4444-555555555555",
            data: resourceRef(),
            dataTypes: [assetType()],
            description: "The original photo",
            digitalSourceType: digitalCapture,
            documentId: "xmp.did:1",
            format: "image/jpeg",
            hash: "Lzh2bGFo",
            informationalUri: "https://example.com/about",
            instanceId: "xmp.iid:1",
            isCreated: true,
            label: "c2pa.ingredient.v3",
            manifestData: resourceRef(),
            metadata: metadata(),
            ocspResponses: [resourceRef()],
            provenance: "https://example.com/provenance",
            relationship: .parentOf,
            thumbnail: resourceRef(),
            title: "original.jpg",
            validationResults: validationResults(),
            validationStatus: [validationStatus()])
    }

    private static func actions() -> AssertionDefinition {
        .actions(actions: [Action(action: PredefinedAction.created.rawValue, digitalSourceType: digitalCapture)])
    }

    private static func manifestDefinition() throws -> ManifestDefinition {
        let definition = ManifestDefinition(
            assertions: [actions()],
            claimGeneratorInfo: [claimGeneratorInfo(icon: resourceRef())],
            claimVersion: 2,
            format: "image/jpeg",
            hashAlg: "sha256",
            ingredients: [ingredient()],
            instanceId: "xmp.iid:2",
            label: "urn:c2pa:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            redactions: ["self#jumbf=c2pa.assertions/c2pa.metadata"],
            thumbnail: resourceRef(),
            title: "edited.jpg",
            vendor: "com.example")
        // The metadata member is deprecated, as it is in c2pa-rs, so no
        // initializer takes it. It is still coded, and so still checked.
        guard case .object(var members) = try JSONValue(encoding: definition) else { return definition }
        members["metadata"] = .array([try JSONValue(encoding: metadata())])
        return try JSONDecoder().decode(ManifestDefinition.self, from: JSONValue.object(members).data())
    }

    // MARK: - Models

    private static let models: [ModelCase] = [
        ModelCase(JSONSchema.rootName, sample: manifestDefinition),
        ModelCase(
            "AssertionDefinition", sample: actions,
            unmodelled: [
                "created": "the enum of assertion kinds has no per-assertion flags",
                "kind": "the enum of assertion kinds has no per-assertion flags"
            ]),
        ModelCase("AssertionMetadata", sample: metadata),
        ModelCase("Actor", sample: actor),
        ModelCase("AssetType", sample: assetType),
        ModelCase("ClaimGeneratorInfo", variant: "resource icon", sample: { claimGeneratorInfo(icon: resourceRef()) }),
        ModelCase("ClaimGeneratorInfo", variant: "hashed URI icon", sample: { claimGeneratorInfo(icon: hashedUri()) }),
        ModelCase("Coordinate", sample: coordinate),
        ModelCase("DataSource", sample: dataSource),
        ModelCase("Frame", sample: frame),
        ModelCase("HashedUri", sample: hashedUri),
        ModelCase("Ingredient", sample: ingredient),
        ModelCase("IngredientDeltaValidationResult", sample: ingredientDelta),
        ModelCase("Item", sample: item),
        ModelCase("Range", sample: range),
        ModelCase("RegionOfInterest", sample: regionOfInterest),
        ModelCase("ResourceRef", sample: resourceRef),
        ModelCase("ReviewRating", sample: reviewRating),
        ModelCase("Shape", sample: shape),
        ModelCase("StatusCodes", sample: statusCodes),
        ModelCase("Text", sample: text),
        ModelCase("TextSelector", sample: textSelector),
        ModelCase("TextSelectorRange", sample: textSelectorRange),
        ModelCase("Time", sample: time),
        ModelCase("ValidationResults", sample: validationResults),
        ModelCase("ValidationStatus", sample: validationStatus)
    ]

    @Test(arguments: models)
    func modelMatchesSchema(_ model: ModelCase) throws {
        expectConformance(model, in: try JSONSchema(named: Self.schemaName))
    }

    // MARK: - Enumerations

    @Test func enumerationsMatchSchema() throws {
        let schema = try JSONSchema(named: Self.schemaName)
        expectEnumeration(Relationship.self, matches: "Relationship", in: schema)
        expectEnumeration(RangeType.self, matches: "RangeType", in: schema)
        expectEnumeration(ShapeType.self, matches: "ShapeType", in: schema)
        expectEnumeration(UnitType.self, matches: "UnitType", in: schema)
        expectEnumeration(TimeType.self, matches: "TimeType", in: schema)
        // Any other string is a valid source type too; the cases are the listed ones.
        expectEnumeration(DigitalSourceType.self, matches: "DigitalSourceType", in: schema, open: true)
    }

    // MARK: - Definition coverage

    private static let enumerations: Set<String> = [
        "Relationship", "RangeType", "ShapeType", "UnitType", "TimeType", "DigitalSourceType"
    ]

    private static let unmodelledDefinitions: [String: String] = [
        "AssertionData": "any JSON value",
        "DateT": "a plain String",
        "ManifestAssertionKind": "AssertionDefinition does not model the kind of an assertion",
        "UriOrResource": "either of two models; both are checked as the icon of ClaimGeneratorInfo"
    ]

    @Test func everyDefinitionIsClassified() throws {
        let mapped = Set(Self.models.map(\.definition)).subtracting([JSONSchema.rootName])
        expectEveryDefinitionClassified(
            in: try JSONSchema(named: Self.schemaName),
            mapped: mapped.union(Self.enumerations),
            unmodelled: Self.unmodelledDefinitions)
    }

    // MARK: - Builder and Reader schemas

    // The models are checked against the ManifestDefinition schema. These show
    // that doing so also covers the definitions the other two schemas share
    // with it, and name what each of them adds.

    private func expectSharedDefinitions(
        of siblingName: String, plus added: [String: String], sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let reference = try JSONSchema(named: Self.schemaName)
        let sibling = try JSONSchema(named: siblingName)
        for name in sibling.definitionNames.intersection(reference.definitionNames).sorted() {
            #expect(
                try sibling.structure(of: name) == reference.structure(of: name),
                "\(name) differs between \(siblingName) and \(Self.schemaName)", sourceLocation: sourceLocation)
        }
        #expect(
            sibling.definitionNames.subtracting(reference.definitionNames) == Set(added.keys),
            sourceLocation: sourceLocation)
    }

    private func rootProperties(_ name: String) throws -> Set<String> {
        Set(try #require(JSONSchema(named: name).root["properties"]?.objectValue).keys)
    }

    @Test func builderSchemaSharesDefinitions() throws {
        try expectSharedDefinitions(
            of: "Builder.schema.json",
            plus: ["BuilderIntent": "set with Builder.setIntent; its settings form is checked against the Settings schema"])

        // The Builder root is the manifest definition plus these. The first
        // three are Builder methods; nothing sets the fourth.
        let added = try rootProperties("Builder.schema.json").subtracting(rootProperties(Self.schemaName))
        #expect(added == ["intent", "no_embed", "remote_url", "timestamp_manifest_labels"])
        #expect(try rootProperties(Self.schemaName).isSubset(of: rootProperties("Builder.schema.json")))
    }

    @Test func readerSchemaSharesDefinitions() throws {
        let noModel = "Reader output has no typed model; Reader.json() returns the JSON"
        try expectSharedDefinitions(
            of: "Reader.schema.json",
            plus: [
                "Manifest": noModel, "ManifestAssertion": noModel, "ManifestData": noModel,
                "SignatureInfo": noModel, "SigningAlgSchema": noModel, "ValidationState": noModel
            ])
        // Everything the manifest definition schema defines, apart from what
        // describes input to a Builder, is also what a Reader reports.
        let reference = try JSONSchema(named: Self.schemaName)
        let reader = try JSONSchema(named: "Reader.schema.json")
        #expect(reference.definitionNames.subtracting(reader.definitionNames) == ["AssertionData", "AssertionDefinition"])
    }
}
