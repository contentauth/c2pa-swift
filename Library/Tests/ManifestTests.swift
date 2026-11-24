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
        #expect(manifest.claimVersion == nil, "c2pa-rs treats an absent claim version as 2")
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

    /// Equality has to look at what each kind of reference holds, or any two
    /// references with the same algorithm compare equal.
    @Test func referenceEquality() {
        let resource = ResourceRef(format: "image/jpeg", identifier: "a.jpg")
        #expect(resource == ResourceRef(format: "image/jpeg", identifier: "a.jpg"))
        #expect(resource != ResourceRef(format: "image/jpeg", identifier: "b.jpg"))
        #expect(resource != ResourceRef(format: "image/png", identifier: "a.jpg"))
        #expect(resource != ResourceRef(format: "image/jpeg", hash: "h", identifier: "a.jpg"))
        #expect(resource != ResourceRef(dataTypes: [AssetType(type: "t")], format: "image/jpeg", identifier: "a.jpg"))
        #expect(resource != ResourceRef(alg: "sha256", format: "image/jpeg", identifier: "a.jpg"))

        let hashed = HashedUri(hash: [1, 2], url: "self#jumbf=a")
        #expect(hashed == HashedUri(hash: [1, 2], url: "self#jumbf=a"))
        #expect(hashed != HashedUri(hash: [1, 3], url: "self#jumbf=a"))
        #expect(hashed != HashedUri(hash: [1, 2], url: "self#jumbf=b"))
        #expect(hashed != HashedUri(alg: "sha256", hash: [1, 2], url: "self#jumbf=a"))

        // Through the base type too, which is how ClaimGeneratorInfo holds an icon.
        let asBase: [UriOrResource] = [resource, hashed, UriOrResource()]
        for (left, leftValue) in asBase.enumerated() {
            for (right, rightValue) in asBase.enumerated() {
                #expect((leftValue == rightValue) == (left == right), "\(left) against \(right)")
            }
        }
    }

    /// c2pa-rs takes hash bytes as an array of numbers and reports them as
    /// b64'<base64>'. A plain string in that place means the bytes of the
    /// string itself, so it is never written and never accepted.
    @Test func hashedUriHashForms() throws {
        func decode(_ hash: String) throws -> HashedUri {
            try JSONDecoder().decode(HashedUri.self, from: Data(#"{"url":"self#jumbf=a","hash":\#(hash)}"#.utf8))
        }
        #expect(try decode("[96, 128]").hash == [96, 128])
        #expect(try decode(#""b64'YIA='""#).hash == [96, 128])
        #expect(try decode(#""b64''""#).hash == [])
        #expect(try JSONValue(encoding: HashedUri(hash: [96, 128], url: "self#jumbf=a"))["hash"] == .array([.number(96), .number(128)]))

        for rejected in [#""YIA=""#, #""b64'!'""#, #""b64'YIA=""#, "[256]", "[-1]", "[1.5]", "null", "{}"] {
            #expect(throws: DecodingError.self, "hash \(rejected)") { try decode(rejected) }
        }
    }

    /// A status code this library does not list has to survive: the set is
    /// open, and c2pa-rs adds to it between releases.
    @Test func unlistedStatusCode() throws {
        let status = try JSONDecoder().decode(ValidationStatus.self, from: Data(#"{"code":"vendor.custom"}"#.utf8))
        #expect(status.code == "vendor.custom")
        #expect(status.statusCode == nil)
        #expect(try JSONValue(encoding: status) == .object(["code": .string("vendor.custom")]))

        let listed = try JSONDecoder().decode(
            ValidationStatus.self, from: Data(#"{"code":"cawg.identity.well-formed"}"#.utf8))
        #expect(listed.statusCode == .cawgIdentityWellFormed)
        #expect(ValidationStatus(code: .claimSignatureValidated).code == "claimSignature.validated")
    }

    @Test func statusCodesAreUnique() {
        #expect(ValidationStatusCode.allCases.count == 140)
        #expect(Set(ValidationStatusCode.allCases.map(\.rawValue)).count == ValidationStatusCode.allCases.count)
    }

    /// The codes c2pa-rs reports that were missing while the enum was closed.
    @Test(arguments: [
        "assertion.metadata.disallowed", "assertion.required.missing", "claim.required.missing",
        "manifest.unknownProvenance", "manifest.unreferenced",
        "cawg.ica.credential_valid", "cawg.ica.did_unavailable", "cawg.ica.invalid_alg",
        "cawg.ica.invalid_content_type", "cawg.ica.invalid_cose_sign1", "cawg.ica.invalid_did_document",
        "cawg.ica.invalid_issuer", "cawg.ica.invalid_verifiable_credential", "cawg.ica.signature_mismatch",
        "cawg.ica.signer_payload.mismatch", "cawg.ica.time_stamp.invalid", "cawg.ica.time_stamp.validated",
        "cawg.ica.untrusted_issuer", "cawg.ica.valid_from.invalid", "cawg.ica.valid_from.missing",
        "cawg.ica.valid_until.invalid", "cawg.identity.assertion.duplicate", "cawg.identity.assertion.mismatch",
        "cawg.identity.cbor.invalid", "cawg.identity.hard_binding_missing", "cawg.identity.pad.invalid",
        "cawg.identity.sig_type.unknown", "cawg.identity.well-formed", "cawg.x509.algorithm.unsupported",
        "cawg.x509.credential.invalid", "cawg.x509.credential.trusted", "cawg.x509.credential.untrusted",
        "cawg.x509.signature.mismatch", "cawg.x509.signature.outside_validity", "cawg.x509.signature.validated"
    ])
    func upstreamStatusCodeIsListed(code: String) {
        #expect(ValidationStatusCode(rawValue: code) != nil)
    }

    /// c2pa-rs requires nothing in a manifest definition, so nothing may be
    /// required to decode one. Keys this model does not know are ignored.
    @Test(arguments: ["{}", #"{"intent":"edit","no_embed":true,"timestamp_manifest_labels":[]}"#])
    func minimalDefinitionDecodes(json: String) throws {
        let manifest = try ManifestDefinition.fromJSON(json)
        #expect(manifest.assertions.isEmpty)
        #expect(manifest.claimGeneratorInfo.isEmpty)
        #expect(manifest.ingredients.isEmpty)
        #expect(manifest.format == "application/octet-stream")
        #expect(manifest.title == nil)
        #expect(manifest.claimVersion == nil)
        #expect(manifest.hashAlg == nil)
    }

    @Test func generatorIconVariants() throws {
        func icon(_ json: String) throws -> UriOrResource? {
            try JSONDecoder().decode(ClaimGeneratorInfo.self, from: Data(#"{"name":"App","icon":\#(json)}"#.utf8)).icon
        }
        let resource = try #require(try icon(#"{"format":"image/png","identifier":"icon.png"}"#) as? ResourceRef)
        #expect(resource.format == "image/png" && resource.identifier == "icon.png")

        let hashed = try #require(try icon(#"{"url":"self#jumbf=icon","hash":"b64'YIA='","alg":"sha256"}"#) as? HashedUri)
        #expect(hashed.url == "self#jumbf=icon" && hashed.hash == [96, 128] && hashed.alg == "sha256")

        #expect(try icon("null") == nil)
        // Neither a resource reference nor a hashed URI.
        #expect(throws: DecodingError.self) { try icon(#"{"alg":"sha256"}"#) }
    }

    @Test func metadataDateTimeIsAString() throws {
        let metadata = Metadata(dateTime: "2026-01-02T03:04:05Z")
        #expect(try JSONValue(encoding: metadata) == .object(["dateTime": .string("2026-01-02T03:04:05Z")]))
        // c2pa-rs does not check the string, so neither may decoding.
        let odd = try JSONDecoder().decode(Metadata.self, from: Data(#"{"dateTime":"yesterday"}"#.utf8))
        #expect(odd.dateTime == "yesterday")
        #expect(odd.additionalFields == nil)
    }

    @Test func metadataLocalizationsAreTyped() throws {
        let json = #"{"localizations":[{"dc:title":{"en-US":"Five Cats"}}]}"#
        let metadata = try JSONDecoder().decode(Metadata.self, from: Data(json.utf8))
        #expect(metadata.localizations == [["dc:title": ["en-US": "Five Cats"]]])
        #expect(metadata.additionalFields == nil, "localizations is modelled, not an unknown field")
    }

    @Test func generatorSpecVersionIsTyped() throws {
        let info = try JSONDecoder().decode(
            ClaimGeneratorInfo.self, from: Data(#"{"name":"App","specVersion":"2.4.0"}"#.utf8))
        #expect(info.specVersion == "2.4.0")
        #expect(info.additionalFields == nil, "specVersion is modelled, not an unknown field")
    }

    @Test func shapeInsideIsOptional() throws {
        let json = #"{"type":"rectangle","unit":"pixel","origin":{"x":0,"y":0}}"#
        let shape = try JSONDecoder().decode(Shape.self, from: Data(json.utf8))
        #expect(shape.inside == nil)
        #expect(try JSONValue(encoding: shape)["inside"] == nil)
        #expect(Shape(type: .rectangle, origin: Coordinate(x: 0, y: 0), unit: .pixel).inside == nil)
    }

    @Test func digitalSourceTypesAddedUpstream() {
        #expect(DigitalSourceType.empty.rawValue == "http://c2pa.org/digitalsourcetype/empty")
        #expect(
            DigitalSourceType.trainedAlgorithmicData.rawValue
                == "http://c2pa.org/digitalsourcetype/trainedAlgorithmicData")
        #expect(
            DigitalSourceType.computationalCapture.rawValue
                == "http://cv.iptc.org/newscodes/digitalsourcetype/computationalCapture")
    }

    @Test func massInit() {
        #expect(Ingredient().title == nil)

        let statusCodes = StatusCodes(failure: [], informational: [], success: [])
        #expect(statusCodes.failure.isEmpty && statusCodes.informational.isEmpty && statusCodes.success.isEmpty)

        #expect(Metadata().dateTime == nil)
        #expect(ValidationStatus(code: .algorithmUnsupported).statusCode == .algorithmUnsupported)

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

    /// No c2pa-rs schema describes an action: assertion data is any JSON there.
    /// The reference is the Action struct in sdk/src/assertions/actions.rs,
    /// whose ten members these are.
    @Test func actionEncodesTheUpstreamMembers() throws {
        let action = Action(
            action: "c2pa.edited",
            digitalSourceType: "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",
            softwareAgent: "TestApp",
            parameters: ["ingredientIds": AnyCodable(["xmp.iid:1"])],
            when: "2026-03-12T10:00:00Z",
            changes: [RegionOfInterest(region: [RegionRange(type: .temporal)])],
            related: [Action(action: "c2pa.cropped")],
            reason: "c2pa.PII.present",
            softwareAgentIndex: 0,
            description: "Cropped and retouched")
        let encoded = try #require(try JSONValue(encoding: action).objectValue)
        #expect(
            Set(encoded.keys) == [
                "action", "when", "softwareAgent", "softwareAgentIndex", "changes", "parameters",
                "digitalSourceType", "related", "reason", "description"
            ])
        #expect(try JSONDecoder().decode(Action.self, from: JSONEncoder().encode(action)) == action)
    }

    /// c2pa-rs refuses to sign a manifest whose related entries are not actions.
    @Test func relatedActionsNest() throws {
        let action = Action(action: "c2pa.edited", related: [Action(action: "c2pa.cropped", description: "tighter")])
        let related = try #require(try JSONValue(encoding: action)["related"]?.arrayValue)
        #expect(related == [.object(["action": .string("c2pa.cropped"), "description": .string("tighter")])])
        #expect(try JSONDecoder().decode(Action.self, from: JSONEncoder().encode(action)) == action)
        #expect(action != Action(action: "c2pa.edited", related: [Action(action: "c2pa.cropped")]))
    }

    @Test func actionEqualityCoversEveryMember() {
        let action = Action(action: "c2pa.edited")
        #expect(action != Action(action: "c2pa.edited", softwareAgentIndex: 1))
        #expect(action != Action(action: "c2pa.edited", description: "d"))
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

    /// A definition read from JSON may have no title; one still cannot be built from it.
    @Test(arguments: ["", nil] as [String?])
    func validatorEmptyTitle(title: String?) {
        var manifest = ManifestDefinition(claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")], title: "test")
        manifest.title = title
        let result = ManifestValidator.validate(manifest)
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

    /// An absent claim version means the current one, so there is nothing to warn about.
    @Test func validatorAcceptsAbsentClaimVersion() {
        let result = ManifestValidator.validate(
            ManifestDefinition(claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")], title: "test"))
        #expect(!result.warnings.contains { $0.contains("outdated") }, "warnings: \(result.warnings)")
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

    /// A manifest with an action that relates to another action, and an
    /// ingredient whose metadata carries a date.
    static func nestedRelatedManifest() -> ManifestDefinition {
        let component = Ingredient(
            format: "image/jpeg", metadata: Metadata(dateTime: "2026-01-02T03:04:05Z"), relationship: .componentOf,
            title: "component.jpg")
        return ManifestDefinition(
            assertions: [
                .actions(actions: [
                    Action(action: .created, digitalSourceType: .digitalCapture),
                    Action(
                        action: PredefinedAction.edited.rawValue,
                        related: [Action(action: PredefinedAction.cropped.rawValue)], description: "Cropped")
                ])
            ],
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "TestApp", version: "1.0")],
            ingredients: [component],
            title: "test.jpg")
    }

    /// Both shapes were refused by c2pa-rs when signing: related entries that
    /// were strings, and a metadata date that was a number.
    @Test func signsNestedRelatedActionAndMetadataDate() throws {
        let manifest = Self.nestedRelatedManifest()
        let store = try Fixtures.signAndRead(Builder(manifest: manifest))
        let ingredient = try #require(try store.ingredients().first)
        #expect((ingredient["metadata"] as? [String: Any])?["dateTime"] as? String == "2026-01-02T03:04:05Z")
        #expect(try store.actions() == ["c2pa.created", "c2pa.edited"])
        let edited = try #require(try store.actionEntries().last)
        #expect((edited["related"] as? [[String: Any]])?.first?["action"] as? String == "c2pa.cropped")
        #expect(edited["description"] as? String == "Cropped")
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
