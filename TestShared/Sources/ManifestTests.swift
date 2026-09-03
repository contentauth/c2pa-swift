import C2PA
import Foundation

// Manifest tests - pure Swift implementation
public final class ManifestTests: TestImplementation {

    public init() {}

    public func testMinimal() -> TestResult {
        let manifest = ManifestDefinition(claimGeneratorInfo: [], title: "test")

        if manifest.claimVersion != 2 {
            return .failure("Manifest", "claimVersion != 2, got \(manifest.claimVersion)")
        }

        if manifest.format != "application/octet-stream" {
            return .failure("Manifest", "format != application/octet-stream, got \(manifest.format)")
        }

        if manifest.title != "test" {
            return .failure("Manifest", "title != test, got \(manifest.title)")
        }

        return cloneAndCompare(manifest)
    }

    public func testCreated() -> TestResult {
        let manifest = ManifestDefinition(
            assertions: [.actions(actions: [.init(action: .created, digitalSourceType: .digitalCapture)])],
            claimGeneratorInfo: [.init()],
            title: "test")

        guard case .actions(let actions) = manifest.assertions.first! else {
            return .failure("Manifest", "manifest.assertions.first != .actions")
        }

        guard let action = actions.first else {
            return .failure("Manifest", "actions.first == nil")
        }

        if action.action != "c2pa.created" {
            return .failure("Manifest", "action.action != c2pa.created, got \(action.action)")
        }

        if action.digitalSourceType != "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture" {
            return .failure("Manifest", "action.digitalSourceType != http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture, got \(action.digitalSourceType ?? "(nil)")")
        }

        guard let info = manifest.claimGeneratorInfo.first else {
            return .failure("Manifest", "claimGeneratorInfo.first == nil")
        }

        if info.name != "xctest" {
            return .failure("Manifest", "claimGeneratorInfo.name != xctest, got \(manifest.claimGeneratorInfo.first?.name ?? "(nil)")")
        }

        guard let version = info.version else {
            return .failure("Manifest", "claimGeneratorInfo.version == nil")
        }

        let regex: NSRegularExpression

        do {
            regex = try NSRegularExpression(pattern: "^[\\d.]+$")
        } catch {
            return .failure("Manifest", "Error: \(error)")
        }

        guard let match = regex.firstMatch(in: version, range: .init(version.startIndex ..< version.endIndex, in: version)),
              match.range.lowerBound == 0 && match.range.upperBound == version.count
        else {
            return .failure("Manifest", "claimGeneratorInfo.version !~ /^[\\d.]+$/")
        }

        return cloneAndCompare(manifest)
    }

    public func testEnumRendering() -> TestResult {
        let shape = Shape(type: .rectangle, origin: .init(x: 10, y: 10), width: 80, height: 80, unit: .percent)

        do {
            let data = try JSONEncoder().encode(shape)
            let json = String(data: data, encoding: .utf8)

            let s2 = try JSONDecoder().decode(Shape.self, from: data)

            if shape == s2 {
                return .success("Manifest", "[PASS] enums rendered as expected.")
            } else {
                return .failure("Manifest", "JSON rendering unexpected: \(json ?? "(nil)")")
            }

        } catch {
            return .failure("Manifest", "Error: \(error)")
        }
    }

    public func testRegionOfInterest() -> TestResult {
        let rr = RegionRange(type: .frame)

        let roi1 = RegionOfInterest(region: [rr], type: .animal)
        let roi2 = RegionOfInterest(region: [rr], type: .animal)

        if roi1 == roi2 {
            return .success("Manifest", "[PASS] RegionOfInterests equal.")
        } else {
            return .failure("Manifest", "RegionOfInterests unexpectedly unequal.")
        }
    }

    public func testResourceRef() -> TestResult {
        let r1 = ResourceRef(format: "application/octet-string", identifier: "")

        do {
            let data = try JSONEncoder().encode(r1)

            let r2 = try JSONDecoder().decode(ResourceRef.self, from: data)

            if r1 == r2 {
                return .success("Manifest", "[PASS] ResourceRefs equal.")
            } else {
                return .failure("Manifest", "ResourceRefs unexpectedly unequal.")
            }
        } catch {
            return .failure("Manifest", "Error: \(error)")
        }
    }

    public func testHashedUri() -> TestResult {
        let hu1 = HashedUri(hash: [], url: "foo")

        do {
            let data = try JSONEncoder().encode(hu1)

            let hu2 = try JSONDecoder().decode(HashedUri.self, from: data)

            if hu1 == hu2 {
                return .success("Manifest", "[PASS] HashedUris equal.")
            } else {
                return .failure("Manifest", "HashedUris unexpectedly unequal.")
            }
        } catch {
            return .failure("Manifest", "Error: \(error)")
        }
    }

    public func testUriOrResource() -> TestResult {
        let uor1 = UriOrResource(alg: "foo")
        let uor2 = UriOrResource(alg: "foo")

        if uor1 == uor2 {
            return .success("Manifest", "[PASS] UriOrResources equal.")
        } else {
            return .failure("Manifest", "UriOrResources unexpectedly unequal.")
        }
    }

    public func testMassInit() -> TestResult {
        var testSteps: [String] = []

        // Test Ingredient default values
        let ingredient = Ingredient()
        guard ingredient.title == nil else {
            return .failure("Mass Init", "Ingredient.title should be nil by default")
        }
        testSteps.append("Ingredient: defaults verified")

        // Test StatusCodes with empty arrays
        let statusCodes = StatusCodes(failure: [], informational: [], success: [])
        guard statusCodes.failure.isEmpty && statusCodes.informational.isEmpty && statusCodes.success.isEmpty else {
            return .failure("Mass Init", "StatusCodes arrays should be empty")
        }
        testSteps.append("StatusCodes: empty arrays verified")

        // Test Metadata default
        let metadata = Metadata()
        guard metadata.dateTime == nil else {
            return .failure("Mass Init", "Metadata.dateTime should be nil by default")
        }
        testSteps.append("Metadata: defaults verified")

        // Test ValidationStatus with specific code
        let validationStatus = ValidationStatus(code: .algorithmUnsupported)
        guard validationStatus.code == .algorithmUnsupported else {
            return .failure("Mass Init", "ValidationStatus.code mismatch: expected .algorithmUnsupported, got '\(validationStatus.code)'")
        }
        testSteps.append("ValidationStatus: code verified")

        // Test Time default
        let time = Time()
        guard time.start == nil && time.end == nil else {
            return .failure("Mass Init", "Time.start and .end should be nil by default")
        }
        testSteps.append("Time: defaults verified")

        // Test TextSelector with fragment
        let textSelector = TextSelector(fragment: "test-fragment")
        guard textSelector.fragment == "test-fragment" else {
            return .failure("Mass Init", "TextSelector.fragment mismatch")
        }
        testSteps.append("TextSelector: fragment verified")

        // Test ReviewRating with values
        let reviewRating = ReviewRating(explanation: "test explanation", value: 5)
        guard reviewRating.explanation == "test explanation" && reviewRating.value == 5 else {
            return .failure("Mass Init", "ReviewRating values mismatch")
        }
        testSteps.append("ReviewRating: values verified")

        // Test DataSource with type
        let dataSource = DataSource(type: "test-type")
        guard dataSource.type == "test-type" else {
            return .failure("Mass Init", "DataSource.type mismatch")
        }
        testSteps.append("DataSource: type verified")

        // Test MetadataActor default
        let metadataActor = MetadataActor()
        guard metadataActor.identifier == nil else {
            return .failure("Mass Init", "MetadataActor.identifier should be nil by default")
        }
        testSteps.append("MetadataActor: defaults verified")

        // Test ValidationResults default
        let validationResults = ValidationResults()
        guard validationResults.activeManifest == nil else {
            return .failure("Mass Init", "ValidationResults.activeManifest should be nil by default")
        }
        testSteps.append("ValidationResults: defaults verified")

        // Test IngredientDeltaValidationResult
        let deltaResult = IngredientDeltaValidationResult(ingredientAssertionUri: "test-uri", validationDeltas: statusCodes)
        guard deltaResult.ingredientAssertionUri == "test-uri" else {
            return .failure("Mass Init", "IngredientDeltaValidationResult.ingredientAssertionUri mismatch")
        }
        testSteps.append("IngredientDeltaValidationResult: values verified")

        // Test Item with values
        let item = Item(identifier: "track_id", value: "2")
        guard item.identifier == "track_id" && item.value == "2" else {
            return .failure("Mass Init", "Item values mismatch")
        }
        testSteps.append("Item: values verified")

        // Test AssetType with type
        let assetType = AssetType(type: "image/jpeg")
        guard assetType.type == "image/jpeg" else {
            return .failure("Mass Init", "AssetType.type mismatch")
        }
        testSteps.append("AssetType: type verified")

        // Test Frame default
        let frame = Frame()
        guard frame.start == nil && frame.end == nil else {
            return .failure("Mass Init", "Frame.start and .end should be nil by default")
        }
        testSteps.append("Frame: defaults verified")

        // Test TextSelectorRange with selector
        let textSelectorRange = TextSelectorRange(selector: textSelector)
        guard textSelectorRange.selector.fragment == "test-fragment" else {
            return .failure("Mass Init", "TextSelectorRange.selector.fragment mismatch")
        }
        testSteps.append("TextSelectorRange: selector verified")

        // Test Text with selectors
        let text = Text(selectors: [textSelectorRange])
        guard text.selectors.count == 1 else {
            return .failure("Mass Init", "Text.selectors should have 1 element")
        }
        testSteps.append("Text: selectors count verified")

        return .success("Mass Init", testSteps.joined(separator: "\n"))
    }

    public func testNewPredefinedActions() -> TestResult {
        let cases: [(PredefinedAction, String)] = [
            (.mastered, "c2pa.mastered"),
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
        ]
        for (action, expected) in cases {
            guard action.rawValue == expected else {
                return .failure("PredefinedAction", "\(action) rawValue '\(action.rawValue)' != '\(expected)'")
            }
        }
        return .success("PredefinedAction", "[PASS] All 17 new action cases verified")
    }

    public func testActionV2SoftwareAgent() -> TestResult {
        // Test v1 string softwareAgent
        let v1Action = Action(action: "c2pa.created", softwareAgent: "MyApp/1.0")
        guard v1Action.softwareAgentString == "MyApp/1.0" else {
            return .failure("Action v2", "softwareAgentString should be 'MyApp/1.0', got '\(v1Action.softwareAgentString ?? "nil")'")
        }
        guard v1Action.softwareAgentInfo == nil else {
            return .failure("Action v2", "softwareAgentInfo should be nil for v1 string agent")
        }

        // Test v2 ClaimGeneratorInfo softwareAgent
        let generatorInfo = ClaimGeneratorInfo(name: "TestApp", version: "2.0")
        let v2Action = Action(
            action: .created,
            softwareAgentInfo: generatorInfo
        )
        guard v2Action.softwareAgentString == nil else {
            return .failure("Action v2", "softwareAgentString should be nil for v2 object agent")
        }
        guard let decoded = v2Action.softwareAgentInfo else {
            return .failure("Action v2", "softwareAgentInfo should decode to ClaimGeneratorInfo")
        }
        guard decoded.name == "TestApp" else {
            return .failure("Action v2", "softwareAgentInfo.name should be 'TestApp', got '\(decoded.name)'")
        }

        return .success("Action v2", "[PASS] v1 string and v2 object softwareAgent verified")
    }

    public func testActionNewFields() -> TestResult {
        let action = Action(
            action: "c2pa.created",
            digitalSourceType: "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",
            softwareAgent: "TestApp",
            when: "2026-03-12T10:00:00Z",
            reason: "Initial capture"
        )

        guard action.when == "2026-03-12T10:00:00Z" else {
            return .failure("Action Fields", "when mismatch")
        }
        guard action.reason == "Initial capture" else {
            return .failure("Action Fields", "reason mismatch")
        }
        guard action.changes == nil else {
            return .failure("Action Fields", "changes should be nil by default")
        }
        guard action.related == nil else {
            return .failure("Action Fields", "related should be nil by default")
        }

        // Test round-trip encoding/decoding
        do {
            let data = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(Action.self, from: data)
            guard action == decoded else {
                return .failure("Action Fields", "Round-trip encoding/decoding mismatch")
            }
        } catch {
            return .failure("Action Fields", "Encoding error: \(error)")
        }

        return .success("Action Fields", "[PASS] Action new fields and round-trip verified")
    }

    public func testActionWireKeys() -> TestResult {
        // Guards the JSON key names themselves, which a Swift-encode/Swift-decode
        // round-trip cannot catch: c2pa-rs renames these fields to camelCase and
        // defines no snake_case aliases, so a mismatch silently drops the values.
        let action = Action(
            action: "c2pa.created",
            digitalSourceType: "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",
            softwareAgent: "TestApp"
        )

        let json: String
        do {
            json = String(data: try JSONEncoder().encode(action), encoding: .utf8) ?? ""
        } catch {
            return .failure("Action Wire Keys", "Encoding error: \(error)")
        }

        for key in ["\"digitalSourceType\"", "\"softwareAgent\""] where !json.contains(key) {
            return .failure("Action Wire Keys", "Encoded JSON is missing \(key): \(json)")
        }
        for key in ["\"digital_source_type\"", "\"software_agent\""] where json.contains(key) {
            return .failure("Action Wire Keys", "Encoded JSON uses snake_case \(key): \(json)")
        }

        // Decoding must accept the camelCase form c2pa-rs actually emits.
        let wireJSON = """
        {"action":"c2pa.created",\
        "digitalSourceType":"http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",\
        "softwareAgent":"TestApp"}
        """
        do {
            let decoded = try JSONDecoder().decode(Action.self, from: Data(wireJSON.utf8))
            guard decoded.digitalSourceType?.hasSuffix("digitalCapture") == true else {
                return .failure("Action Wire Keys", "digitalSourceType did not decode from camelCase key")
            }
            guard decoded.softwareAgentString == "TestApp" else {
                return .failure("Action Wire Keys", "softwareAgent did not decode from camelCase key")
            }
        } catch {
            return .failure("Action Wire Keys", "Decoding error: \(error)")
        }

        return .success("Action Wire Keys", "[PASS] camelCase JSON keys verified in both directions")
    }

    /// One model's encoded form paired with the wire keys c2pa-rs expects from it.
    private struct WireKeyCheck {
        let model: String
        let encoded: Data
        let expected: [String]
    }

    /// Normalizes a JSON key so that spellings differing only in case or underscores
    /// collide: `digital_source_type` and `digitalSourceType` both become
    /// `digitalsourcetype`.
    private func normalizedKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: "").lowercased()
    }

    /// Checks one model's encoded top-level keys against the wire names c2pa-rs uses.
    ///
    /// Reports a key whose spelling drifted (same name modulo case and underscores, but
    /// not an exact match) separately from one that is missing outright, since the former
    /// is the silent-data-loss case: c2pa-rs defines no aliases, so a drifted key is
    /// dropped rather than rejected.
    private func wireKeyMismatch(_ check: WireKeyCheck) -> String? {
        let model = check.model
        guard let object = try? JSONSerialization.jsonObject(with: check.encoded),
            let dictionary = object as? [String: Any]
        else {
            return "\(model): encoded JSON is not an object"
        }
        let actual = Set(dictionary.keys)
        for key in check.expected where !actual.contains(key) {
            if let drifted = actual.first(where: { normalizedKey($0) == normalizedKey(key) }) {
                return "\(model): expected key '\(key)' but found '\(drifted)'"
            }
            return "\(model): expected key '\(key)' is absent (encoded: \(actual.sorted()))"
        }
        return nil
    }

    public func testManifestWireKeyDrift() -> TestResult {
        // The wire names c2pa-rs reads and writes, verified against its serde attributes.
        // c2pa-rs uses two conventions: manifest assertions carry explicit camelCase
        // renames, while settings structs keep Rust's snake_case default. The same concept
        // is spelled differently in each, so these must be checked rather than inferred.
        let hashedUri = HashedUri(hash: [0x01, 0x02], url: "self#jumbf=c2pa.assertions/c2pa.actions")
        let statusCodes = StatusCodes(failure: [], informational: [], success: [])

        var checks: [WireKeyCheck] = []
        do {
            checks.append(WireKeyCheck(
                model: "Action",
                encoded: try JSONEncoder().encode(
                    Action(
                        action: "c2pa.created",
                        digitalSourceType: "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",
                        softwareAgent: "TestApp")),
                expected: ["digitalSourceType", "softwareAgent"]))

            checks.append(WireKeyCheck(
                model: "Ingredient",
                encoded: try JSONEncoder().encode(
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
                ]))

            checks.append(WireKeyCheck(
                model: "ValidationResults",
                encoded: try JSONEncoder().encode(
                    ValidationResults(activeManifest: statusCodes, ingredientDeltas: [])),
                expected: ["activeManifest", "ingredientDeltas"]))

            checks.append(WireKeyCheck(
                model: "IngredientDeltaValidationResult",
                encoded: try JSONEncoder().encode(
                    IngredientDeltaValidationResult(
                        ingredientAssertionUri: "self#jumbf=c2pa.assertions/c2pa.ingredient",
                        validationDeltas: statusCodes)),
                expected: ["ingredientAssertionURI", "validationDeltas"]))

            checks.append(WireKeyCheck(
                model: "Metadata",
                encoded: try JSONEncoder().encode(
                    Metadata(
                        dataSource: DataSource(type: "signer"),
                        dateTime: Date(timeIntervalSince1970: 0),
                        reference: hashedUri,
                        reviewRatings: [ReviewRating(explanation: "ok", value: 5)])),
                expected: ["dataSource", "dateTime", "reviewRatings"]))

            checks.append(WireKeyCheck(
                model: "ClaimGeneratorInfo",
                encoded: try JSONEncoder().encode(
                    ClaimGeneratorInfo(name: "TestApp", operatingSystem: "iOS")),
                expected: ["operating_system"]))

            checks.append(WireKeyCheck(
                model: "ResourceRef",
                encoded: try JSONEncoder().encode(
                    ResourceRef(dataTypes: [], format: "image/jpeg", identifier: "self#jumbf=c2pa")),
                expected: ["data_types"]))

            checks.append(WireKeyCheck(
                model: "ManifestDefinition",
                encoded: try JSONEncoder().encode(
                    ManifestDefinition(
                        claimGeneratorInfo: [ClaimGeneratorInfo(name: "TestApp")],
                        instanceId: "instance-1",
                        title: "wire-key drift check")),
                expected: ["claim_generator_info", "claim_version", "instance_id"]))
        } catch {
            return .failure("Wire Key Drift", "Encoding error: \(error)")
        }

        for check in checks {
            if let mismatch = wireKeyMismatch(check) {
                return .failure("Wire Key Drift", mismatch)
            }
        }
        return .success(
            "Wire Key Drift", "[PASS] \(checks.count) models match their c2pa-rs wire keys")
    }

    public func testClaimGeneratorInfoPreservesUnknownFields() -> TestResult {
        // c2pa-rs keeps unrecognized members in a flattened map, so a manifest written by
        // another generator must survive a decode/encode cycle here rather than losing them.
        let source = """
        {"name":"Other/1.0","operating_system":"iOS 18",\
        "vendorSpecific":{"channel":"beta"},"buildCount":7}
        """
        do {
            let decoded = try JSONDecoder().decode(ClaimGeneratorInfo.self, from: Data(source.utf8))
            guard let extras = decoded.additionalFields else {
                return .failure("CGI Unknown Fields", "additionalFields should not be nil")
            }
            guard Set(extras.keys) == ["vendorSpecific", "buildCount"] else {
                return .failure("CGI Unknown Fields", "unexpected extras: \(extras.keys.sorted())")
            }
            guard decoded.additionalFields?["name"] == nil else {
                return .failure("CGI Unknown Fields", "a modeled key leaked into additionalFields")
            }

            let reencoded = try JSONEncoder().encode(decoded)
            let json = String(data: reencoded, encoding: .utf8) ?? ""
            for key in ["\"vendorSpecific\"", "\"buildCount\"", "\"operating_system\""] where !json.contains(key) {
                return .failure("CGI Unknown Fields", "re-encoded JSON dropped \(key): \(json)")
            }

            // Decoding the re-encoded form must land in the same place.
            let again = try JSONDecoder().decode(ClaimGeneratorInfo.self, from: reencoded)
            guard again == decoded else {
                return .failure("CGI Unknown Fields", "round-trip is not stable")
            }
        } catch {
            return .failure("CGI Unknown Fields", "Error: \(error)")
        }
        return .success("CGI Unknown Fields", "[PASS] unknown fields survive the round-trip")
    }

    public func testClaimGeneratorInfoOperatingSystemAlias() -> TestResult {
        // c2pa-rs accepts the schema.org spelling when decoding but always writes
        // operating_system, so decoding must accept both and encoding must normalize.
        let aliased = """
        {"name":"Other/1.0","schema.org.SoftwareApplication.operatingSystem":"macOS 15"}
        """
        do {
            let decoded = try JSONDecoder().decode(ClaimGeneratorInfo.self, from: Data(aliased.utf8))
            guard decoded.operatingSystem == "macOS 15" else {
                return .failure(
                    "CGI OS Alias", "alias did not decode, got \(decoded.operatingSystem ?? "nil")")
            }
            guard decoded.additionalFields == nil else {
                return .failure("CGI OS Alias", "the alias key leaked into additionalFields")
            }

            let json = String(data: try JSONEncoder().encode(decoded), encoding: .utf8) ?? ""
            guard json.contains("\"operating_system\"") else {
                return .failure("CGI OS Alias", "did not re-encode as operating_system: \(json)")
            }
            guard !json.contains("schema.org") else {
                return .failure("CGI OS Alias", "re-encoded using the alias spelling: \(json)")
            }
        } catch {
            return .failure("CGI OS Alias", "Error: \(error)")
        }
        return .success("CGI OS Alias", "[PASS] alias decodes and normalizes to operating_system")
    }

    public func testMetadataPreservesUnknownFields() -> TestResult {
        // The C2PA metadata object is explicitly open-ended.
        let source = """
        {"dataSource":{"type":"signer"},"org.example.custom":"kept","weight":3}
        """
        do {
            let decoded = try JSONDecoder().decode(Metadata.self, from: Data(source.utf8))
            guard let extras = decoded.additionalFields,
                Set(extras.keys) == ["org.example.custom", "weight"]
            else {
                return .failure(
                    "Metadata Unknown Fields",
                    "unexpected extras: \(decoded.additionalFields?.keys.sorted() ?? [])")
            }
            guard decoded.dataSource?.type == "signer" else {
                return .failure("Metadata Unknown Fields", "modeled dataSource did not decode")
            }

            let json = String(data: try JSONEncoder().encode(decoded), encoding: .utf8) ?? ""
            for key in ["\"org.example.custom\"", "\"weight\"", "\"dataSource\""] where !json.contains(key) {
                return .failure("Metadata Unknown Fields", "re-encoded JSON dropped \(key): \(json)")
            }
        } catch {
            return .failure("Metadata Unknown Fields", "Error: \(error)")
        }
        return .success("Metadata Unknown Fields", "[PASS] unknown fields survive the round-trip")
    }

    public func testValidateAndLog() -> TestResult {
        let manifest = ManifestDefinition(
            claimGeneratorInfo: [ClaimGeneratorInfo()],
            title: "test"
        )
        let result = ManifestValidator.validateAndLog(manifest)
        guard result.isValid else {
            return .failure("ValidateAndLog", "Valid manifest reported as invalid: \(result.errors)")
        }
        return .success("ValidateAndLog", "[PASS] validateAndLog works for valid manifest")
    }

    public func testCustomAssertionLabelValidation() -> TestResult {
        let manifest = ManifestDefinition(
            assertions: [.custom(label: "nolabel", data: AnyCodable("test"))],
            claimGeneratorInfo: [ClaimGeneratorInfo()],
            title: "test"
        )
        let result = ManifestValidator.validate(manifest)
        guard result.warnings.contains(where: { $0.contains("namespaced format") }) else {
            return .failure("Custom Label", "Expected warning about namespaced format, got: \(result.warnings)")
        }

        // Verify properly namespaced label does not trigger warning
        let manifest2 = ManifestDefinition(
            assertions: [.custom(label: "com.example.test", data: AnyCodable("test"))],
            claimGeneratorInfo: [ClaimGeneratorInfo()],
            title: "test"
        )
        let result2 = ManifestValidator.validate(manifest2)
        guard !result2.warnings.contains(where: { $0.contains("namespaced format") }) else {
            return .failure("Custom Label", "Should not warn for properly namespaced label")
        }

        return .success("Custom Label", "[PASS] Custom assertion label validation verified")
    }

    // MARK: - ManifestDefinition Factory Methods

    public func testCreatedFactory() -> TestResult {
        let manifest = ManifestDefinition.created(
            title: "photo.jpg",
            claimGeneratorInfo: ClaimGeneratorInfo(name: "TestApp"),
            digitalSourceType: .digitalCapture
        )
        guard !manifest.assertions.isEmpty else {
            return .failure("Created Factory", "Should have assertions")
        }
        if case .actions(let actions) = manifest.assertions.first {
            guard actions.first?.action == PredefinedAction.created.rawValue else {
                return .failure("Created Factory", "First action should be c2pa.created")
            }
        } else {
            return .failure("Created Factory", "First assertion should be .actions")
        }
        return .success("Created Factory", "[PASS] ManifestDefinition.created() works")
    }

    public func testEditedFactory() -> TestResult {
        let parent = Ingredient.parent(title: "original.jpg")
        let manifest = ManifestDefinition.edited(
            title: "edited.jpg",
            claimGeneratorInfo: ClaimGeneratorInfo(name: "TestApp"),
            parentIngredient: parent,
            editActions: [Action(action: PredefinedAction.cropped.rawValue)]
        )
        guard manifest.ingredients.count == 1 else {
            return .failure("Edited Factory", "Should have 1 ingredient")
        }
        guard manifest.ingredients.first?.relationship == .parentOf else {
            return .failure("Edited Factory", "Ingredient should be parentOf")
        }
        return .success("Edited Factory", "[PASS] ManifestDefinition.edited() works")
    }

    public func testMixedAssertions() -> TestResult {
        let manifest = ManifestDefinition(
            assertions: [
                .metadata,
                .cawgIdentity(data: ["sig_type": AnyCodable("cawg.x509")])
            ],
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "TestApp")],
            title: "test.jpg"
        )
        guard manifest.assertions.count == 2 else {
            return .failure("MixedAssertions", "Should have 2 assertions")
        }
        guard manifest.assertions[1].baseLabel == "cawg.identity" else {
            return .failure("MixedAssertions", "Second assertion should be cawg.identity")
        }
        return .success("MixedAssertions", "[PASS] Mixed assertion types in single list works")
    }

    // MARK: - ManifestDefinition Convenience Methods

    public func testAssertionLabels() -> TestResult {
        let manifest = ManifestDefinition(
            assertions: [.metadata, .metadata, .dataHash],
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "TestApp")],
            title: "test.jpg"
        )
        let labels = manifest.assertionLabels()
        guard labels.contains("c2pa.metadata") else {
            return .failure("AssertionLabels", "Should contain c2pa.metadata")
        }
        guard labels.contains("c2pa.hash.data") else {
            return .failure("AssertionLabels", "Should contain c2pa.hash.data")
        }
        return .success("AssertionLabels", "[PASS] assertionLabels() works")
    }

    public func testToJSON() -> TestResult {
        let manifest = ManifestDefinition(
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
            title: "json.jpg"
        )
        do {
            let json = try manifest.toJSON()
            guard json.contains("json.jpg") else {
                return .failure("toJSON", "JSON should contain title")
            }
            return .success("toJSON", "[PASS] toJSON() works")
        } catch {
            return .failure("toJSON", "Error: \(error)")
        }
    }

    public func testToPrettyJSON() -> TestResult {
        let manifest = ManifestDefinition(
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
            title: "pretty.jpg"
        )
        do {
            let json = try manifest.toPrettyJSON()
            guard json.contains("\n") else {
                return .failure("toPrettyJSON", "Pretty JSON should contain newlines")
            }
            return .success("toPrettyJSON", "[PASS] toPrettyJSON() works")
        } catch {
            return .failure("toPrettyJSON", "Error: \(error)")
        }
    }

    public func testFromJSON() -> TestResult {
        let manifest = ManifestDefinition(
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
            title: "fromjson.jpg"
        )
        do {
            let json = try manifest.toJSON()
            let decoded = try ManifestDefinition.fromJSON(json)
            guard decoded.title == "fromjson.jpg" else {
                return .failure("fromJSON", "Title mismatch")
            }
            return .success("fromJSON", "[PASS] fromJSON() round-trip works")
        } catch {
            return .failure("fromJSON", "Error: \(error)")
        }
    }

    public func testDescription() -> TestResult {
        let manifest = ManifestDefinition(
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
            title: "desc.jpg"
        )
        let desc = manifest.description
        guard desc.contains("desc.jpg") else {
            return .failure("Description", "description should contain title")
        }
        return .success("Description", "[PASS] CustomStringConvertible works")
    }

    // MARK: - Ingredient Factory Methods

    public func testIngredientParentFactory() -> TestResult {
        let ingredient = Ingredient.parent(title: "parent.jpg", format: "image/jpeg")
        guard ingredient.relationship == .parentOf else {
            return .failure("Ingredient.parent", "Should have parentOf relationship")
        }
        guard ingredient.title == "parent.jpg" else {
            return .failure("Ingredient.parent", "Title mismatch")
        }
        return .success("Ingredient.parent", "[PASS] Ingredient.parent() works")
    }

    public func testIngredientComponentFactory() -> TestResult {
        let ingredient = Ingredient.component(title: "watermark.png")
        guard ingredient.relationship == .componentOf else {
            return .failure("Ingredient.component", "Should have componentOf relationship")
        }
        return .success("Ingredient.component", "[PASS] Ingredient.component() works")
    }

    public func testIngredientInputToFactory() -> TestResult {
        let ingredient = Ingredient.inputTo(title: "training.jpg")
        guard ingredient.relationship == .inputTo else {
            return .failure("Ingredient.inputTo", "Should have inputTo relationship")
        }
        return .success("Ingredient.inputTo", "[PASS] Ingredient.inputTo() works")
    }

    // MARK: - ManifestValidator Coverage

    public func testValidatorEmptyTitle() -> TestResult {
        let manifest = ManifestDefinition(
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
            title: ""
        )
        let result = ManifestValidator.validate(manifest)
        guard result.errors.contains(where: { $0.contains("title") }) else {
            return .failure("Empty Title", "Expected title error, got: \(result.errors)")
        }
        return .success("Empty Title", "[PASS] Empty title produces error")
    }

    public func testValidatorEmptyClaimGeneratorInfo() -> TestResult {
        let manifest = ManifestDefinition(claimGeneratorInfo: [], title: "test")
        let result = ManifestValidator.validate(manifest)
        guard result.errors.contains(where: { $0.contains("claim_generator_info") }) else {
            return .failure("Empty CGI", "Expected CGI error, got: \(result.errors)")
        }
        return .success("Empty CGI", "[PASS] Empty claimGeneratorInfo produces error")
    }

    public func testValidatorOldClaimVersion() -> TestResult {
        let manifest = ManifestDefinition(
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
            claimVersion: 1,
            title: "test"
        )
        let result = ManifestValidator.validate(manifest)
        guard result.warnings.contains(where: { $0.contains("outdated") }) else {
            return .failure("Old Version", "Expected version warning, got: \(result.warnings)")
        }
        return .success("Old Version", "[PASS] Old claim version produces warning")
    }

    public func testValidatorDeprecatedAssertionLabels() -> TestResult {
        let manifest = ManifestDefinition(
            assertions: [.custom(label: "stds.exif", data: AnyCodable("test"))],
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
            title: "test"
        )
        let result = ManifestValidator.validate(manifest)
        guard result.warnings.contains(where: { $0.contains("Deprecated") && $0.contains("stds.exif") }) else {
            return .failure("Deprecated Labels", "Expected deprecated warning, got: \(result.warnings)")
        }
        return .success("Deprecated Labels", "[PASS] Deprecated labels produce warnings")
    }

    public func testValidatorCawgAssertionAccepted() -> TestResult {
        let manifest = ManifestDefinition(
            assertions: [.cawgIdentity(data: ["test": AnyCodable("value")])],
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
            title: "test"
        )
        let result = ManifestValidator.validate(manifest)
        guard result.isValid else {
            return .failure("CAWG Assertion", "CAWG identity in assertions should be valid, got errors: \(result.errors)")
        }
        return .success("CAWG Assertion", "[PASS] CAWG identity assertion accepted in assertions list")
    }

    public func testValidatorMultipleParents() -> TestResult {
        let manifest = ManifestDefinition(
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
            ingredients: [
                .parent(title: "parent1.jpg"),
                .parent(title: "parent2.jpg")
            ],
            title: "test"
        )
        let result = ManifestValidator.validate(manifest)
        guard result.warnings.contains(where: { $0.contains("Multiple parent") }) else {
            return .failure("Multiple Parents", "Expected multiple parent warning, got: \(result.warnings)")
        }
        return .success("Multiple Parents", "[PASS] Multiple parent ingredients produce warning")
    }

    public func testValidateJSON() -> TestResult {
        let manifest = ManifestDefinition(
            claimGeneratorInfo: [ClaimGeneratorInfo(name: "test")],
            title: "test"
        )
        do {
            let json = try manifest.toJSON()
            let result = ManifestValidator.validateJSON(json)
            guard result.isValid else {
                return .failure("ValidateJSON", "Valid JSON should validate, got errors: \(result.errors)")
            }
            return .success("ValidateJSON", "[PASS] validateJSON() works")
        } catch {
            return .failure("ValidateJSON", "Error: \(error)")
        }
    }

    public func testValidateJSONInvalid() -> TestResult {
        let result = ManifestValidator.validateJSON("not valid json {{{")
        guard !result.isValid else {
            return .failure("ValidateJSON Invalid", "Invalid JSON should not validate")
        }
        return .success("ValidateJSON Invalid", "[PASS] Invalid JSON fails validateJSON()")
    }

    // MARK: - Builder Validation Integration Tests

    public func testBuilderInitManifestValid() -> TestResult {
        let manifest = ManifestDefinition.created(
            title: "test.jpg",
            claimGeneratorInfo: ClaimGeneratorInfo(name: "TestApp", version: "1.0"),
            digitalSourceType: .digitalCapture
        )
        do {
            _ = try Builder(manifest: manifest)
            return .success("Builder init(manifest:)", "[PASS] Valid manifest creates builder")
        } catch {
            return .failure("Builder init(manifest:)", "Should not throw for valid manifest: \(error)")
        }
    }

    public func testBuilderInitManifestInvalid() -> TestResult {
        let manifest = ManifestDefinition(
            claimGeneratorInfo: [],
            title: ""
        )
        do {
            _ = try Builder(manifest: manifest)
            return .failure("Builder init(manifest:) invalid", "Should have thrown for invalid manifest")
        } catch let error as C2PAError {
            if case .manifestValidationFailed(let result) = error {
                guard result.hasErrors else {
                    return .failure("Builder init(manifest:) invalid", "Result should have errors")
                }
                return .success("Builder init(manifest:) invalid", "[PASS] Invalid manifest throws manifestValidationFailed")
            }
            return .failure("Builder init(manifest:) invalid", "Wrong error type: \(error)")
        } catch {
            return .failure("Builder init(manifest:) invalid", "Unexpected error: \(error)")
        }
    }

    public func testBuilderInitJSONInvalid() -> TestResult {
        // init(manifestJSON:) does not validate -- it delegates to the C layer,
        // which should reject invalid JSON with a C2PAError.
        do {
            _ = try Builder(manifestJSON: "not valid json")
            return .failure("Builder init(manifestJSON:) invalid", "Should have thrown for invalid JSON")
        } catch is C2PAError {
            return .success("Builder init(manifestJSON:) invalid", "[PASS] Invalid JSON throws C2PAError")
        } catch {
            return .failure("Builder init(manifestJSON:) invalid", "Unexpected error type: \(error)")
        }
    }

    @MainActor
    public func runAllTests() async -> [TestResult] {
        return [
            testMinimal(),
            testCreated(),
            testEnumRendering(),
            testRegionOfInterest(),
            testResourceRef(),
            testHashedUri(),
            testUriOrResource(),
            testMassInit(),
            testNewPredefinedActions(),
            testActionV2SoftwareAgent(),
            testActionNewFields(),
            testActionWireKeys(),
            testManifestWireKeyDrift(),
            testClaimGeneratorInfoPreservesUnknownFields(),
            testClaimGeneratorInfoOperatingSystemAlias(),
            testMetadataPreservesUnknownFields(),
            testValidateAndLog(),
            testCustomAssertionLabelValidation(),
            testCreatedFactory(),
            testEditedFactory(),
            testMixedAssertions(),
            testAssertionLabels(),
            testToJSON(),
            testToPrettyJSON(),
            testFromJSON(),
            testDescription(),
            testIngredientParentFactory(),
            testIngredientComponentFactory(),
            testIngredientInputToFactory(),
            testValidatorEmptyTitle(),
            testValidatorEmptyClaimGeneratorInfo(),
            testValidatorOldClaimVersion(),
            testValidatorDeprecatedAssertionLabels(),
            testValidatorCawgAssertionAccepted(),
            testValidatorMultipleParents(),
            testValidateJSON(),
            testValidateJSONInvalid(),
            testBuilderInitManifestValid(),
            testBuilderInitManifestInvalid(),
            testBuilderInitJSONInvalid()
        ]
    }


    // MARK: Private Methods

    private func cloneAndCompare(_ manifest: ManifestDefinition) -> TestResult {
        guard let data = manifest.description.data(using: .utf8) else {
            return .failure("Manifest", "ManifestDefinition.description could not be decoded to UTF-8 Data!")
        }

        let m2: ManifestDefinition

        do {
            m2 = try JSONDecoder().decode(ManifestDefinition.self, from: data)
        } catch {
            return .failure("Manifest", "Error: \(error)")
        }

        if manifest == m2 {
            return .success("Manifest", "[PASS] Manifest rendered as expected.")
        }

        return .failure("Manifest", "Broken compiled manifest: \(manifest.description) != \(m2.description)")
    }
}
