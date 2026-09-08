// This file is licensed to you under the Apache License, Version 2.0
// (http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
// (http://opensource.org/licenses/MIT), at your option.
//
// Unless required by applicable law or agreed to in writing, this software is
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
// ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
// files for the specific language governing permissions and limitations under
// each license.

import C2PA
import Foundation

public final class SettingsDefinitionTests: TestImplementation {

    public init() {}

    public func testRoundTrip() -> TestResult {
        let definition = C2PASettingsDefinition(
            version: 1,
            verify: VerifySettings(
                verifyAfterReading: true,
                verifyTrust: false
            ),
            builder: BuilderSettingsDefinition(
                vendor: "com.example",
                thumbnail: ThumbnailSettings(
                    format: .jpeg,
                    quality: .medium
                ),
                intent: .edit
            ),
            signer: .local(LocalSignerSettings(
                alg: "es256",
                signCert: "-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----",
                privateKey: "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----",
                tsaUrl: "http://timestamp.example.com"
            ))
        )

        do {
            let json = try definition.toJSON()
            let decoded = try C2PASettingsDefinition.fromJSON(json)

            guard decoded == definition else {
                return .failure("Round Trip", "Decoded definition does not match original")
            }

            return .success("Round Trip", "[PASS] Settings definition round-trips through JSON")
        } catch {
            return .failure("Round Trip", "Failed: \(error)")
        }
    }

    public func testFromJSON() -> TestResult {
        let json = """
        {
            "version": 1,
            "verify": {
                "verify_after_reading": true,
                "ocsp_fetch": false
            },
            "builder": {
                "vendor": "test-vendor",
                "thumbnail": {
                    "format": "png",
                    "quality": "high",
                    "long_edge": 512
                }
            }
        }
        """

        do {
            let definition = try C2PASettingsDefinition.fromJSON(json)

            guard definition.version == 1 else {
                return .failure("From JSON", "Expected version 1, got \(String(describing: definition.version))")
            }
            guard definition.verify?.verifyAfterReading == true else {
                return .failure("From JSON", "Expected verifyAfterReading true")
            }
            guard definition.verify?.ocspFetch == false else {
                return .failure("From JSON", "Expected ocspFetch false")
            }
            guard definition.builder?.vendor == "test-vendor" else {
                return .failure("From JSON", "Expected vendor 'test-vendor'")
            }
            guard definition.builder?.thumbnail?.format == .png else {
                return .failure("From JSON", "Expected thumbnail format png")
            }
            guard definition.builder?.thumbnail?.quality == .high else {
                return .failure("From JSON", "Expected thumbnail quality high")
            }
            guard definition.builder?.thumbnail?.longEdge == 512 else {
                return .failure("From JSON", "Expected thumbnail longEdge 512")
            }

            return .success("From JSON", "[PASS] Settings definition decoded from JSON correctly")
        } catch {
            return .failure("From JSON", "Failed: \(error)")
        }
    }

    public func testPartialSettings() -> TestResult {
        let definition = C2PASettingsDefinition(version: 1)

        do {
            let json = try definition.toJSON()
            let decoded = try C2PASettingsDefinition.fromJSON(json)

            guard decoded.version == 1 else {
                return .failure("Partial Settings", "Expected version 1")
            }
            guard decoded.trust == nil else {
                return .failure("Partial Settings", "Expected nil trust")
            }
            guard decoded.signer == nil else {
                return .failure("Partial Settings", "Expected nil signer")
            }
            guard decoded.builder == nil else {
                return .failure("Partial Settings", "Expected nil builder")
            }

            return .success("Partial Settings", "[PASS] Partial settings encode/decode correctly")
        } catch {
            return .failure("Partial Settings", "Failed: \(error)")
        }
    }

    public func testSignerLocalSerialization() -> TestResult {
        let signer = SignerSettings.local(LocalSignerSettings(
            alg: "es256",
            signCert: "cert",
            privateKey: "key",
            tsaUrl: "http://tsa.example.com",
            referencedAssertions: ["cawg.training-mining"]
        ))

        do {
            let json = try C2PAJson.encode(signer)
            let decoded = try C2PAJson.decode(SignerSettings.self, from: json)

            guard decoded == signer else {
                return .failure("Signer Local", "Decoded signer does not match original")
            }

            guard case .local(let local) = decoded else {
                return .failure("Signer Local", "Expected local signer")
            }
            guard local.alg == "es256" else {
                return .failure("Signer Local", "Expected alg es256")
            }
            guard local.referencedAssertions == ["cawg.training-mining"] else {
                return .failure("Signer Local", "Expected referenced assertions")
            }

            return .success("Signer Local", "[PASS] Local signer settings serialize correctly")
        } catch {
            return .failure("Signer Local", "Failed: \(error)")
        }
    }

    public func testSignerRemoteSerialization() -> TestResult {
        let signer = SignerSettings.remote(RemoteSignerSettings(
            url: "https://signing.example.com",
            alg: "es384",
            signCert: "cert"
        ))

        do {
            let json = try C2PAJson.encode(signer)
            let decoded = try C2PAJson.decode(SignerSettings.self, from: json)

            guard case .remote(let remote) = decoded else {
                return .failure("Signer Remote", "Expected remote signer")
            }
            guard remote.url == "https://signing.example.com" else {
                return .failure("Signer Remote", "Expected remote URL")
            }
            guard remote.alg == "es384" else {
                return .failure("Signer Remote", "Expected alg es384")
            }

            return .success("Signer Remote", "[PASS] Remote signer settings serialize correctly")
        } catch {
            return .failure("Signer Remote", "Failed: \(error)")
        }
    }

    public func testIntentSerialization() -> TestResult {
        do {
            // Test edit
            let editJSON = try C2PAJson.encode(SettingsIntent.edit)
            let decodedEdit = try C2PAJson.decode(SettingsIntent.self, from: editJSON)
            guard decodedEdit == .edit else {
                return .failure("Intent Serialization", "Edit intent round-trip failed")
            }

            // Test update
            let updateJSON = try C2PAJson.encode(SettingsIntent.update)
            let decodedUpdate = try C2PAJson.decode(SettingsIntent.self, from: updateJSON)
            guard decodedUpdate == .update else {
                return .failure("Intent Serialization", "Update intent round-trip failed")
            }

            // Test create
            let createIntent = SettingsIntent.create("http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture")
            let createJSON = try C2PAJson.encode(createIntent)
            let decodedCreate = try C2PAJson.decode(SettingsIntent.self, from: createJSON)
            guard decodedCreate == createIntent else {
                return .failure("Intent Serialization", "Create intent round-trip failed")
            }

            return .success("Intent Serialization", "[PASS] All intent variants serialize correctly")
        } catch {
            return .failure("Intent Serialization", "Failed: \(error)")
        }
    }

    public func testEnumValues() -> TestResult {
        // ThumbnailFormat
        let formats: [(ThumbnailFormat, String)] = [
            (.png, "png"), (.jpeg, "jpeg"), (.gif, "gif"), (.webp, "webp"), (.tiff, "tiff")
        ]
        for (format, expected) in formats {
            guard format.rawValue == expected else {
                return .failure("Enum Values", "ThumbnailFormat.\(format) expected rawValue '\(expected)', got '\(format.rawValue)'")
            }
        }

        // ThumbnailQuality
        let qualities: [(ThumbnailQuality, String)] = [
            (.low, "low"), (.medium, "medium"), (.high, "high")
        ]
        for (quality, expected) in qualities {
            guard quality.rawValue == expected else {
                return .failure("Enum Values", "ThumbnailQuality.\(quality) expected rawValue '\(expected)', got '\(quality.rawValue)'")
            }
        }

        // OcspFetchScope
        guard OcspFetchScope.all.rawValue == "all" else {
            return .failure("Enum Values", "OcspFetchScope.all rawValue mismatch")
        }
        guard OcspFetchScope.active.rawValue == "active" else {
            return .failure("Enum Values", "OcspFetchScope.active rawValue mismatch")
        }

        // TimeStampFetchScope
        guard TimeStampFetchScope.parent.rawValue == "parent" else {
            return .failure("Enum Values", "TimeStampFetchScope.parent rawValue mismatch")
        }
        guard TimeStampFetchScope.all.rawValue == "all" else {
            return .failure("Enum Values", "TimeStampFetchScope.all rawValue mismatch")
        }

        return .success("Enum Values", "[PASS] All enum rawValues match expected strings")
    }

    public func testExistingSettingsJSON() -> TestResult {
        guard let data = TestUtilities.loadTestResource(name: "test_settings_with_cawg_signing", ext: "json"),
              let json = String(data: data, encoding: .utf8) else {
            return .failure("Existing JSON", "Could not load test_settings_with_cawg_signing.json")
        }

        do {
            let definition = try C2PASettingsDefinition.fromJSON(json)

            guard definition.version == 1 else {
                return .failure("Existing JSON", "Expected version 1")
            }

            guard case .local(let signer) = definition.signer else {
                return .failure("Existing JSON", "Expected local signer")
            }
            guard signer.alg == "es256" else {
                return .failure("Existing JSON", "Expected signer alg es256")
            }
            guard signer.tsaUrl == "http://timestamp.digicert.com" else {
                return .failure("Existing JSON", "Expected signer tsa_url")
            }

            guard case .local(let cawg) = definition.cawgX509Signer else {
                return .failure("Existing JSON", "Expected local cawg signer")
            }
            guard cawg.referencedAssertions == ["cawg.training-mining"] else {
                return .failure("Existing JSON", "Expected cawg referenced assertions")
            }

            return .success("Existing JSON", "[PASS] Existing test settings JSON decoded correctly")
        } catch {
            return .failure("Existing JSON", "Failed: \(error)")
        }
    }

    public func testPrettyJSON() -> TestResult {
        let definition = C2PASettingsDefinition(
            version: 1,
            core: CoreSettings(merkleTreeChunkSizeInKb: 64)
        )

        do {
            let pretty = try definition.toPrettyJSON()
            let compact = try definition.toJSON()

            guard pretty.count > compact.count else {
                return .failure("Pretty JSON", "Pretty JSON should be longer than compact")
            }
            guard pretty.contains("\n") else {
                return .failure("Pretty JSON", "Pretty JSON should contain newlines")
            }

            let decoded = try C2PASettingsDefinition.fromJSON(pretty)
            guard decoded == definition else {
                return .failure("Pretty JSON", "Pretty JSON should decode back to original")
            }

            return .success("Pretty JSON", "[PASS] toPrettyJSON produces formatted, decodable JSON")
        } catch {
            return .failure("Pretty JSON", "Failed: \(error)")
        }
    }

    public func testTrustSettings() -> TestResult {
        let trust = TrustSettings(
            verifyTrustList: true,
            userAnchors: "user-anchor-pem",
            trustAnchors: "trust-anchor-pem",
            trustConfig: "{\"trust\": true}",
            allowedList: "allowed-list"
        )

        do {
            let json = try C2PAJson.encode(trust)
            let decoded = try C2PAJson.decode(TrustSettings.self, from: json)
            guard decoded == trust else {
                return .failure("Trust Settings", "Round trip failed")
            }

            return .success("Trust Settings", "[PASS] TrustSettings round-trips correctly")
        } catch {
            return .failure("Trust Settings", "Failed: \(error)")
        }
    }

    public func testCoreSettings() -> TestResult {
        let core = CoreSettings(
            merkleTreeChunkSizeInKb: 64,
            merkleTreeMaxProofs: 100,
            backingStoreMemoryThresholdInMb: 256,
            decodeIdentityAssertions: true,
            allowedNetworkHosts: ["example.com", "cdn.example.com"]
        )

        do {
            let json = try C2PAJson.encode(core)
            let decoded = try C2PAJson.decode(CoreSettings.self, from: json)
            guard decoded == core else {
                return .failure("Core Settings", "Round trip failed")
            }

            return .success("Core Settings", "[PASS] CoreSettings round-trips correctly")
        } catch {
            return .failure("Core Settings", "Failed: \(error)")
        }
    }

    public func testVerifySettings() -> TestResult {
        let verify = VerifySettings(
            verifyAfterReading: true,
            verifyAfterSign: false,
            verifyTrust: true,
            verifyTimestampTrust: false,
            ocspFetch: true,
            remoteManifestFetch: false,
            skipIngredientConflictResolution: true,
            strictV1Validation: false
        )

        do {
            let json = try C2PAJson.encode(verify)
            let decoded = try C2PAJson.decode(VerifySettings.self, from: json)
            guard decoded == verify else {
                return .failure("Verify Settings", "Round trip failed")
            }

            return .success("Verify Settings", "[PASS] VerifySettings round-trips correctly")
        } catch {
            return .failure("Verify Settings", "Failed: \(error)")
        }
    }

    public func testBuilderSettings() -> TestResult {
        let builder = BuilderSettingsDefinition(
            vendor: "com.test",
            claimGeneratorInfo: ClaimGeneratorInfoSettings(
                name: "TestApp",
                version: "1.0",
                operatingSystem: "iOS 17"
            ),
            thumbnail: ThumbnailSettings(
                enabled: true,
                ignoreErrors: false,
                longEdge: 1024,
                format: .webp,
                preferSmallestFormat: true,
                quality: .low
            ),
            actions: ActionsSettings(
                allActionsIncluded: true,
                templates: [
                    ActionTemplateSettings(
                        action: "c2pa.created",
                        softwareAgent: ClaimGeneratorInfoSettings(name: "TestAgent"),
                        sourceType: "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",
                        description: "Test action"
                    )
                ],
                autoCreatedAction: AutoActionSettings(enabled: true, sourceType: "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"),
                autoOpenedAction: AutoActionSettings(enabled: false),
                autoPlacedAction: AutoActionSettings(enabled: true)
            ),
            certificateStatusFetch: .all,
            certificateStatusShouldOverride: false,
            intent: .create("http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"),
            createdAssertionLabels: ["c2pa.actions"],
            preferBoxHash: true,
            generateC2paArchive: false,
            autoTimestampAssertion: TimeStampSettings(
                enabled: true,
                skipExisting: false,
                fetchScope: .all
            )
        )

        do {
            let json = try C2PAJson.encode(builder)
            let decoded = try C2PAJson.decode(BuilderSettingsDefinition.self, from: json)
            guard decoded == builder else {
                return .failure("Builder Settings", "Round trip failed")
            }
            guard decoded.claimGeneratorInfo?.name == "TestApp" else {
                return .failure("Builder Settings", "ClaimGeneratorInfo name mismatch")
            }
            guard decoded.actions?.templates?.count == 1 else {
                return .failure("Builder Settings", "Expected 1 action template")
            }
            guard decoded.actions?.autoCreatedAction?.enabled == true else {
                return .failure("Builder Settings", "autoCreatedAction should be enabled")
            }
            guard decoded.autoTimestampAssertion?.fetchScope == .all else {
                return .failure("Builder Settings", "fetchScope should be .all")
            }

            return .success("Builder Settings", "[PASS] BuilderSettingsDefinition round-trips correctly")
        } catch {
            return .failure("Builder Settings", "Failed: \(error)")
        }
    }

    public func testFullDefinitionRoundTrip() -> TestResult {
        let definition = C2PASettingsDefinition(
            version: 1,
            trust: TrustSettings(verifyTrustList: true),
            cawgTrust: TrustSettings(verifyTrustList: false, userAnchors: "cawg-anchors"),
            core: CoreSettings(merkleTreeChunkSizeInKb: 32, decodeIdentityAssertions: true),
            verify: VerifySettings(verifyAfterReading: true, strictV1Validation: false),
            builder: BuilderSettingsDefinition(
                vendor: "full-test",
                intent: .update
            ),
            signer: .local(LocalSignerSettings(
                alg: "ps256",
                signCert: "cert-pem",
                privateKey: "key-pem",
                roles: ["signer", "validator"]
            )),
            cawgX509Signer: .remote(RemoteSignerSettings(
                url: "https://cawg.example.com",
                alg: "es256",
                signCert: "cawg-cert"
            ))
        )

        do {
            let json = try definition.toJSON()
            let decoded = try C2PASettingsDefinition.fromJSON(json)
            guard decoded == definition else {
                return .failure("Full Definition", "Full round trip failed")
            }

            guard case .local(let signer) = decoded.signer else {
                return .failure("Full Definition", "Expected local signer")
            }
            guard signer.roles == ["signer", "validator"] else {
                return .failure("Full Definition", "Signer roles mismatch")
            }

            guard case .remote(let cawg) = decoded.cawgX509Signer else {
                return .failure("Full Definition", "Expected remote cawg signer")
            }
            guard cawg.url == "https://cawg.example.com" else {
                return .failure("Full Definition", "CAWG URL mismatch")
            }

            guard decoded.cawgTrust?.userAnchors == "cawg-anchors" else {
                return .failure("Full Definition", "cawgTrust userAnchors mismatch")
            }

            return .success("Full Definition", "[PASS] Full definition with all sections round-trips correctly")
        } catch {
            return .failure("Full Definition", "Failed: \(error)")
        }
    }

    public func testC2PASettingsFromDefinition() -> TestResult {
        let definition = C2PASettingsDefinition(version: 1)

        do {
            let settings = try C2PASettings(definition: definition)
            // If we get here, the settings loaded successfully into the C API
            _ = settings
            return .success("Settings From Definition", "[PASS] C2PASettings created from definition")
        } catch {
            return .failure("Settings From Definition", "Failed: \(error)")
        }
    }

    public func testC2PASettingsLoadDefinition() -> TestResult {
        do {
            let settings = try C2PASettings(json: "{\"version\": 1}")
            let definition = C2PASettingsDefinition(
                version: 1,
                verify: VerifySettings(verifyAfterReading: true)
            )
            try settings.load(definition: definition)
            return .success("Settings Load Definition", "[PASS] C2PASettings.load(definition:) succeeded")
        } catch {
            return .failure("Settings Load Definition", "Failed: \(error)")
        }
    }

    public func testC2PASettingsSetValue() -> TestResult {
        do {
            let settings = try C2PASettings(json: "{\"version\": 1}")

            // Set a value the C API accepts
            try settings.setValue(true, forPath: "verify.verify_after_reading")

            return .success("Settings SetValue", "[PASS] setValue works for nested paths")
        } catch {
            return .failure("Settings SetValue", "Failed: \(error)")
        }
    }

    public func testC2PASettingsSetValueErrors() -> TestResult {
        // Test empty path
        do {
            let settings = try C2PASettings(json: "{\"version\": 1}")
            try settings.setValue("value", forPath: "")
            return .failure("Settings SetValue Errors", "Should have thrown for empty path")
        } catch {
            // Expected
        }

        return .success("Settings SetValue Errors", "[PASS] setValue throws for invalid inputs")
    }

    public func testSignerWithRoles() -> TestResult {
        let local = LocalSignerSettings(
            alg: "es256",
            signCert: "cert",
            privateKey: "key",
            tsaUrl: nil,
            referencedAssertions: nil,
            roles: ["signer"]
        )

        let remote = RemoteSignerSettings(
            url: "https://example.com",
            alg: "es384",
            signCert: "cert",
            tsaUrl: "http://tsa.example.com",
            referencedAssertions: ["assertion1"],
            roles: ["validator"]
        )

        do {
            let localJSON = try C2PAJson.encode(local)
            let decodedLocal = try C2PAJson.decode(LocalSignerSettings.self, from: localJSON)
            guard decodedLocal.roles == ["signer"] else {
                return .failure("Signer Roles", "Local roles mismatch")
            }
            guard decodedLocal.tsaUrl == nil else {
                return .failure("Signer Roles", "Local tsaUrl should be nil")
            }

            let remoteJSON = try C2PAJson.encode(remote)
            let decodedRemote = try C2PAJson.decode(RemoteSignerSettings.self, from: remoteJSON)
            guard decodedRemote.roles == ["validator"] else {
                return .failure("Signer Roles", "Remote roles mismatch")
            }
            guard decodedRemote.tsaUrl == "http://tsa.example.com" else {
                return .failure("Signer Roles", "Remote tsaUrl mismatch")
            }

            return .success("Signer Roles", "[PASS] Signer settings with all optional fields round-trip correctly")
        } catch {
            return .failure("Signer Roles", "Failed: \(error)")
        }
    }

    public func testActionTemplateWithIndex() -> TestResult {
        let template = ActionTemplateSettings(
            action: "c2pa.edited",
            softwareAgentIndex: 0,
            description: "Edited with app"
        )

        do {
            let json = try C2PAJson.encode(template)
            let decoded = try C2PAJson.decode(ActionTemplateSettings.self, from: json)
            guard decoded == template else {
                return .failure("Action Template", "Round trip failed")
            }
            guard decoded.softwareAgentIndex == 0 else {
                return .failure("Action Template", "softwareAgentIndex mismatch")
            }
            guard decoded.softwareAgent == nil else {
                return .failure("Action Template", "softwareAgent should be nil")
            }

            return .success("Action Template", "[PASS] ActionTemplateSettings round-trips correctly")
        } catch {
            return .failure("Action Template", "Failed: \(error)")
        }
    }

    public func testTimestampParentScope() -> TestResult {
        let timestamp = TimeStampSettings(
            enabled: true,
            skipExisting: true,
            fetchScope: .parent
        )

        do {
            let json = try C2PAJson.encode(timestamp)
            let decoded = try C2PAJson.decode(TimeStampSettings.self, from: json)
            guard decoded == timestamp else {
                return .failure("Timestamp Parent", "Round trip failed")
            }
            guard decoded.fetchScope == .parent else {
                return .failure("Timestamp Parent", "fetchScope should be .parent")
            }

            return .success("Timestamp Parent", "[PASS] TimeStampSettings with parent scope round-trips")
        } catch {
            return .failure("Timestamp Parent", "Failed: \(error)")
        }
    }

    public func testBuilderDefaultCreatedAssertionLabels() -> TestResult {
        let labels = Builder.defaultCreatedAssertionLabels
        guard !labels.isEmpty else {
            return .failure("Builder Default Created Labels", "Default label list is empty")
        }
        guard labels.contains("c2pa.actions"), labels.contains("c2pa.ingredient") else {
            return .failure("Builder Default Created Labels", "Missing expected default labels: \(labels)")
        }
        return .success("Builder Default Created Labels", "[PASS] \(labels.count) default created-assertion labels")
    }

    public func testC2PASettingsCreatedAssertionLabels() -> TestResult {
        do {
            let settings = try C2PASettings(createdAssertionLabels: ["com.example.custom"])
            _ = settings
            return .success("Settings Created Labels", "[PASS] C2PASettings created from an explicit label list")
        } catch {
            return .failure("Settings Created Labels", "Failed: \(error)")
        }
    }

    public func testC2PASettingsAdditionalCreatedAssertionLabels() -> TestResult {
        do {
            // A label already in the defaults must not break construction when repeated.
            let settings = try C2PASettings(
                additionalCreatedAssertionLabels: ["com.example.custom", "c2pa.actions"])
            _ = settings
            return .success(
                "Settings Additional Created Labels",
                "[PASS] C2PASettings created from defaults plus extra labels")
        } catch {
            return .failure("Settings Additional Created Labels", "Failed: \(error)")
        }
    }

    public func runAllTests() async -> [TestResult] {
        return [
            testRoundTrip(),
            testFromJSON(),
            testPartialSettings(),
            testSignerLocalSerialization(),
            testSignerRemoteSerialization(),
            testIntentSerialization(),
            testEnumValues(),
            testExistingSettingsJSON(),
            testPrettyJSON(),
            testTrustSettings(),
            testCoreSettings(),
            testVerifySettings(),
            testBuilderSettings(),
            testFullDefinitionRoundTrip(),
            testC2PASettingsFromDefinition(),
            testC2PASettingsLoadDefinition(),
            testC2PASettingsSetValue(),
            testC2PASettingsSetValueErrors(),
            testSignerWithRoles(),
            testActionTemplateWithIndex(),
            testTimestampParentScope(),
            testBuilderDefaultCreatedAssertionLabels(),
            testC2PASettingsCreatedAssertionLabels(),
            testC2PASettingsAdditionalCreatedAssertionLabels()
        ]
    }
}
