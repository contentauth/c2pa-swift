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
//  SettingsSchemaConformanceTests.swift
//

import C2PA
import Foundation
import Testing

/// Checks the settings models against the Settings schema c2pa-rs exports.
///
/// c2pa-rs ignores settings keys it does not know, so a key that drifts is
/// dropped without an error. Regenerate the schema with `make update-schemas`
/// after changing `C2PA_VERSION`; what fails here is what drifted.
@Suite struct SettingsSchemaConformanceTests {

    private static let schemaName = "Settings.schema.json"

    // MARK: - Samples

    // Every sample sets every property, so each key the model has is encoded.

    private static let digitalCapture = DigitalSourceType.digitalCapture.rawValue

    private static let needsSendableValue =
        "the settings types are Sendable, and no Sendable resource reference or JSON value type exists yet"

    private static func trustAnchor(_ kind: TrustListKind = .manifest) -> TrustAnchor {
        TrustAnchor(
            trustAnchors: "-----BEGIN CERTIFICATE-----\nroot\n-----END CERTIFICATE-----",
            trustKind: kind,
            trustUri: "https://example.com/trust-list",
            trustConfig: "1.3.6.1.5.5.7.3.4",
            allowedList: "-----BEGIN CERTIFICATE-----\nleaf\n-----END CERTIFICATE-----",
            trustedIcaIssuers: ["did:web:example.com"])
    }

    private static func trust() -> TrustSettings {
        TrustSettings(
            anchors: TrustListKind.allCases.map(trustAnchor),
            trustConfig: "1.3.6.1.5.5.7.3.36",
            useDefaultEkus: false)
    }

    private static func core() -> CoreSettings {
        CoreSettings(
            merkleTreeChunkSizeInKb: 64,
            merkleTreeMaxProofs: 5,
            backingStoreMemoryThresholdInMb: 256,
            decodeIdentityAssertions: false,
            allowedNetworkHosts: ["*.example.com", "https://tsa.example.com:443"],
            allowRedirects: false,
            preferCompressManifests: true,
            maxDecompressedManifestSizeInMb: 16,
            timeStampRequestAttempts: 2,
            timeStampRequestTimeoutInMs: 5_000,
            timeStampRetryDelayInMs: 250,
            httpRequestTimeoutInMs: 8_000)
    }

    private static func verify() -> VerifySettings {
        VerifySettings(
            verifyAfterReading: false,
            verifyAfterSign: false,
            verifyTrust: false,
            verifyTimestampTrust: false,
            ocspFetch: true,
            remoteManifestFetch: false,
            skipIngredientConflictResolution: true,
            strictV1Validation: true,
            ocspFetchShouldOverride: true,
            maxManifestResponseSize: 1_048_576,
            verifyAfterSignHash: true)
    }

    private static func softBinding() -> SoftBindingSettings {
        SoftBindingSettings(softBindingAlgorithms: ["com.example.watermark.1"])
    }

    private static func claimGeneratorInfo() -> ClaimGeneratorInfoSettings {
        ClaimGeneratorInfoSettings(name: "TestApp", version: "1.0", operatingSystem: "arm64-apple-ios")
    }

    private static func thumbnail() -> ThumbnailSettings {
        ThumbnailSettings(
            enabled: false, ignoreErrors: false, longEdge: 512, format: .webp, preferSmallestFormat: false,
            quality: .high)
    }

    private static func actionTemplate() -> ActionTemplateSettings {
        ActionTemplateSettings(
            action: "c2pa.edited",
            softwareAgent: claimGeneratorInfo(),
            softwareAgentIndex: 0,
            sourceType: digitalCapture,
            description: "Edited in TestApp")
    }

    private static func autoAction() -> AutoActionSettings {
        AutoActionSettings(enabled: true, sourceType: digitalCapture)
    }

    private static func actions() -> ActionsSettings {
        ActionsSettings(
            allActionsIncluded: true,
            templates: [actionTemplate()],
            autoCreatedAction: autoAction(),
            autoOpenedAction: autoAction(),
            autoPlacedAction: autoAction(),
            autoAllActionsIncluded: true)
    }

    private static func timeStamp() -> TimeStampSettings {
        TimeStampSettings(enabled: true, skipExisting: false, fetchScope: .parent)
    }

    private static func builder() -> BuilderSettingsDefinition {
        BuilderSettingsDefinition(
            vendor: "com.example",
            claimGeneratorInfo: claimGeneratorInfo(),
            thumbnail: thumbnail(),
            actions: actions(),
            certificateStatusFetch: .active,
            certificateStatusShouldOverride: true,
            intent: .create(digitalCapture),
            createdAssertionLabels: ["c2pa.actions"],
            preferBoxHash: true,
            generateC2paArchive: true,
            autoTimestampAssertion: timeStamp(),
            bmffHashExcludeFreeAndSkipBoxes: false,
            ignoreIngredientErrors: true)
    }

    // The schema lists the algorithm as c2pa-rs writes it. c2pa-rs reads it in
    // any letter case, which is why the models keep it a plain string.
    private static func localSignerSettings() -> LocalSignerSettings {
        LocalSignerSettings(
            alg: "Es256", signCert: "cert-pem", privateKey: "key-pem", tsaUrl: "http://tsa.example.com",
            referencedAssertions: ["c2pa.actions"], roles: ["cawg.creator"])
    }

    private static func remoteSignerSettings() -> RemoteSignerSettings {
        RemoteSignerSettings(
            url: "https://signer.example.com", alg: "Ps384", signCert: "cert-pem",
            tsaUrl: "http://tsa.example.com", referencedAssertions: ["c2pa.actions"], roles: ["cawg.creator"])
    }

    private static func localSigner() -> SignerSettings {
        .local(localSignerSettings())
    }

    private static func remoteSigner() -> SignerSettings {
        .remote(remoteSignerSettings())
    }

    private static func definition() -> C2PASettingsDefinition {
        C2PASettingsDefinition(
            version: 1,
            trust: trust(),
            core: core(),
            verify: verify(),
            builder: builder(),
            signer: localSigner(),
            cawgX509Signer: remoteSigner(),
            softBinding: softBinding())
    }

    // MARK: - Models

    private static let models: [ModelCase] = [
        ModelCase(JSONSchema.rootName, sample: definition),
        ModelCase("Trust", sample: trust),
        ModelCase(
            "TrustAnchor", sample: { trustAnchor() },
            // The schema marks nothing required here, but c2pa-rs rejects an
            // anchor that omits either one ("missing field trust_kind").
            alsoRequired: ["trust_anchors", "trust_kind"]),
        ModelCase("Core", sample: core),
        ModelCase("Verify", sample: verify),
        ModelCase("SoftBinding", sample: softBinding),
        ModelCase("BuilderSettings", sample: builder),
        ModelCase("ThumbnailSettings", sample: thumbnail),
        ModelCase("ActionsSettings", sample: actions),
        ModelCase(
            "ActionTemplateSettings", sample: actionTemplate,
            unmodelled: ["icon": needsSendableValue, "template_parameters": needsSendableValue]),
        ModelCase("AutoActionSettings", sample: autoAction),
        ModelCase("TimeStampSettings", sample: timeStamp),
        // Besides icon, c2pa-rs keeps any further member of the generator
        // info. Those have no names to list here, and need the same value type.
        ModelCase("ClaimGeneratorInfoSettings", sample: claimGeneratorInfo, unmodelled: ["icon": needsSendableValue]),
        ModelCase("SignerSettings", variant: "local", sample: localSigner),
        ModelCase("SignerSettings", variant: "remote", sample: remoteSigner),
        // The schema describes the two kinds of signer inline, as the one
        // member of each alternative, so their keys are compared there.
        ModelCase("SignerSettings", member: "local", sample: localSignerSettings),
        ModelCase("SignerSettings", member: "remote", sample: remoteSignerSettings),
        ModelCase("BuilderIntent", variant: "create", sample: { SettingsIntent.create(digitalCapture) }),
        ModelCase("BuilderIntent", variant: "edit", sample: { SettingsIntent.edit }),
        ModelCase("BuilderIntent", variant: "update", sample: { SettingsIntent.update })
    ]

    @Test(arguments: models)
    func modelMatchesSchema(_ model: ModelCase) throws {
        expectConformance(model, in: try JSONSchema(named: Self.schemaName))
    }

    /// The cases of the two enums with associated values. An alternative
    /// c2pa-rs adds would otherwise pass: each case above matches one of them.
    @Test func alternativesMatchSchema() throws {
        let schema = try JSONSchema(named: Self.schemaName)
        #expect(try schema.alternatives(of: "SignerSettings") == ["{local}", "{remote}"])
        #expect(try schema.alternatives(of: "BuilderIntent") == ["{create}", "\"edit\"", "\"update\""])
    }

    // MARK: - Enumerations

    @Test func enumerationsMatchSchema() throws {
        let schema = try JSONSchema(named: Self.schemaName)
        expectEnumeration(ThumbnailFormat.self, matches: "ThumbnailFormat", in: schema)
        expectEnumeration(ThumbnailQuality.self, matches: "ThumbnailQuality", in: schema)
        expectEnumeration(TimeStampFetchScope.self, matches: "TimeStampFetchScope", in: schema)
        expectEnumeration(OcspFetchScope.self, matches: "OcspFetchScope", in: schema)
        expectEnumeration(TrustListKind.self, matches: "TrustListKind", in: schema)
    }

    // MARK: - Definition coverage

    private static let enumerations: Set<String> = [
        "ThumbnailFormat", "ThumbnailQuality", "TimeStampFetchScope", "OcspFetchScope", "TrustListKind"
    ]

    private static let unmodelledDefinitions: [String: String] = [
        "ClaimGeneratorInfoOperatingSystem": "a plain String?: the name, or absent to leave it out",
        "HostPattern": "a plain String",
        "SigningAlgSchema": "alg stays a String, since c2pa-rs reads it in any letter case",
        "DigitalSourceType": "source types stay Strings in settings; the cases are checked against the manifest schema",
        "AssetType": "reached only through the unmodelled icon; checked against the manifest schema",
        "ResourceRef": "reached only through the unmodelled icon; checked against the manifest schema"
    ]

    @Test func everyDefinitionIsClassified() throws {
        let mapped = Set(Self.models.map(\.definition)).subtracting([JSONSchema.rootName])
        expectEveryDefinitionClassified(
            in: try JSONSchema(named: Self.schemaName),
            mapped: mapped.union(Self.enumerations),
            unmodelled: Self.unmodelledDefinitions)
    }

    /// The definitions excused above as checked against the manifest schema
    /// are the same there, so that check does cover them.
    @Test(arguments: ["AssetType", "ResourceRef", "DigitalSourceType"])
    func sharedDefinitionMatchesTheManifestSchema(name: String) throws {
        let manifest = try JSONSchema(named: "ManifestDefinition.schema.json")
        #expect(try JSONSchema(named: Self.schemaName).structure(of: name) == manifest.structure(of: name))
    }

    // MARK: - What c2pa-rs writes

    /// c2pa-rs serializes its settings with every option present, unset ones
    /// as null. The schema carries those defaults, so they are the real input.
    @Test func upstreamDefaultsDecode() throws {
        let schema = try JSONSchema(named: Self.schemaName)
        func upstreamDefault(_ section: String) throws -> JSONValue {
            try #require(schema.root["properties"]?[section]?["default"], "no default for \(section)")
        }
        func decode<Section: Decodable>(_ type: Section.Type, _ section: String) throws -> Section {
            try JSONDecoder().decode(type, from: upstreamDefault(section).data())
        }

        let trust = try decode(TrustSettings.self, "trust")
        #expect(trust.anchors == nil)
        #expect(trust.useDefaultEkus == true)

        let core = try decode(CoreSettings.self, "core")
        #expect(core.merkleTreeChunkSizeInKb == nil)
        #expect(core.timeStampRequestAttempts == 3)
        #expect(core.timeStampRequestTimeoutInMs == 10_000)
        #expect(core.timeStampRetryDelayInMs == 500)
        #expect(core.httpRequestTimeoutInMs == 10_000)
        #expect(core.allowRedirects == true)

        let verify = try decode(VerifySettings.self, "verify")
        #expect(verify.maxManifestResponseSize == 10_485_760)
        #expect(verify.ocspFetchShouldOverride == false)

        let builder = try decode(BuilderSettingsDefinition.self, "builder")
        #expect(builder.intent == nil)
        #expect(builder.bmffHashExcludeFreeAndSkipBoxes == true)
        #expect(builder.ignoreIngredientErrors == false)
        #expect(builder.actions?.autoAllActionsIncluded == false)
        #expect(builder.actions?.autoCreatedAction?.enabled == false)

        #expect(try decode(SoftBindingSettings.self, "soft_binding").softBindingAlgorithms == nil)

        let whole = JSONValue.object([
            "version": .number(1),
            "trust": try upstreamDefault("trust"),
            "core": try upstreamDefault("core"),
            "verify": try upstreamDefault("verify"),
            "builder": try upstreamDefault("builder"),
            "soft_binding": try upstreamDefault("soft_binding")
        ])
        let definition = try JSONDecoder().decode(C2PASettingsDefinition.self, from: whole.data())
        #expect(definition.version == 1)
        #expect(definition.signer == nil)
        #expect(definition.builder?.thumbnail?.longEdge == 1024)
    }
}
