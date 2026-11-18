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
//  SettingsDefinitionTests.swift
//

import C2PA
import Foundation
import Testing

@Suite struct SettingsDefinitionTests {

    private let digitalCapture = "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"

    // MARK: - Definitions

    @Test func roundTrip() throws {
        let definition = C2PASettingsDefinition(
            version: 1,
            verify: VerifySettings(verifyAfterReading: true, verifyTrust: false),
            builder: BuilderSettingsDefinition(
                vendor: "com.example",
                thumbnail: ThumbnailSettings(format: .jpeg, quality: .medium),
                intent: .edit),
            signer: .local(
                LocalSignerSettings(
                    alg: "es256",
                    signCert: "-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----",
                    privateKey: "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----",
                    tsaUrl: "http://timestamp.example.com"))
        )
        #expect(try C2PASettingsDefinition.fromJSON(definition.toJSON()) == definition)
    }

    @Test func fromJSON() throws {
        let definition = try C2PASettingsDefinition.fromJSON("""
            {
                "version": 1,
                "verify": {"verify_after_reading": true, "ocsp_fetch": false},
                "builder": {
                    "vendor": "test-vendor",
                    "thumbnail": {"format": "png", "quality": "high", "long_edge": 512}
                }
            }
            """)
        #expect(definition.version == 1)
        #expect(definition.verify?.verifyAfterReading == true)
        #expect(definition.verify?.ocspFetch == false)
        #expect(definition.builder?.vendor == "test-vendor")
        #expect(definition.builder?.thumbnail?.format == .png)
        #expect(definition.builder?.thumbnail?.quality == .high)
        #expect(definition.builder?.thumbnail?.longEdge == 512)
    }

    @Test func partialSettings() throws {
        let decoded = try C2PASettingsDefinition.fromJSON(C2PASettingsDefinition(version: 1).toJSON())
        #expect(decoded.version == 1)
        #expect(decoded.trust == nil)
        #expect(decoded.signer == nil)
        #expect(decoded.builder == nil)
    }

    @Test func signerLocalSerialization() throws {
        let signer = SignerSettings.local(
            LocalSignerSettings(
                alg: "es256",
                signCert: "cert",
                privateKey: "key",
                tsaUrl: "http://tsa.example.com",
                referencedAssertions: ["cawg.training-mining"]))
        let decoded = try C2PAJson.decode(SignerSettings.self, from: C2PAJson.encode(signer))
        #expect(decoded == signer)
        guard case .local(let local) = decoded else {
            Issue.record("decoded as \(decoded), not .local")
            return
        }
        #expect(local.alg == "es256")
        #expect(local.referencedAssertions == ["cawg.training-mining"])
    }

    @Test func signerRemoteSerialization() throws {
        let signer = SignerSettings.remote(RemoteSignerSettings(url: "https://signing.example.com", alg: "es384", signCert: "cert"))
        let decoded = try C2PAJson.decode(SignerSettings.self, from: C2PAJson.encode(signer))
        guard case .remote(let remote) = decoded else {
            Issue.record("decoded as \(decoded), not .remote")
            return
        }
        #expect(remote.url == "https://signing.example.com")
        #expect(remote.alg == "es384")
    }

    @Test func intentSerialization() throws {
        for intent in [SettingsIntent.edit, .update, .create(digitalCapture)] {
            #expect(try C2PAJson.decode(SettingsIntent.self, from: C2PAJson.encode(intent)) == intent)
        }
    }

    @Test func enumValues() {
        #expect([ThumbnailFormat.png, .jpeg, .gif, .webp, .tiff].map(\.rawValue) == ["png", "jpeg", "gif", "webp", "tiff"])
        #expect([ThumbnailQuality.low, .medium, .high].map(\.rawValue) == ["low", "medium", "high"])
        #expect(OcspFetchScope.all.rawValue == "all")
        #expect(OcspFetchScope.active.rawValue == "active")
        #expect(TimeStampFetchScope.parent.rawValue == "parent")
        #expect(TimeStampFetchScope.all.rawValue == "all")
    }

    @Test func existingSettingsJSON() throws {
        let definition = try C2PASettingsDefinition.fromJSON(Fixtures.text("test_settings_with_cawg_signing.json"))
        #expect(definition.version == 1)
        guard case .local(let signer) = definition.signer else {
            Issue.record("signer is not .local: \(String(describing: definition.signer))")
            return
        }
        #expect(signer.alg == "es256")
        #expect(signer.tsaUrl == "http://timestamp.digicert.com")
        guard case .local(let cawg) = definition.cawgX509Signer else {
            Issue.record("cawg_x509_signer is not .local: \(String(describing: definition.cawgX509Signer))")
            return
        }
        #expect(cawg.referencedAssertions == ["cawg.training-mining"])
    }

    @Test func prettyJSON() throws {
        let definition = C2PASettingsDefinition(version: 1, core: CoreSettings(merkleTreeChunkSizeInKb: 64))
        let pretty = try definition.toPrettyJSON()
        #expect(pretty.count > (try definition.toJSON()).count)
        #expect(pretty.contains("\n"))
        #expect(try C2PASettingsDefinition.fromJSON(pretty) == definition)
    }

    @Test func trustSettings() throws {
        let trust = TrustSettings(
            verifyTrustList: true,
            userAnchors: "user-anchor-pem",
            trustAnchors: "trust-anchor-pem",
            trustConfig: "{\"trust\": true}",
            allowedList: "allowed-list")
        #expect(try C2PAJson.decode(TrustSettings.self, from: C2PAJson.encode(trust)) == trust)
    }

    @Test func coreSettings() throws {
        let core = CoreSettings(
            merkleTreeChunkSizeInKb: 64,
            merkleTreeMaxProofs: 100,
            backingStoreMemoryThresholdInMb: 256,
            decodeIdentityAssertions: true,
            allowedNetworkHosts: ["example.com", "cdn.example.com"])
        #expect(try C2PAJson.decode(CoreSettings.self, from: C2PAJson.encode(core)) == core)
    }

    @Test func verifySettings() throws {
        let verify = VerifySettings(
            verifyAfterReading: true,
            verifyAfterSign: false,
            verifyTrust: true,
            verifyTimestampTrust: false,
            ocspFetch: true,
            remoteManifestFetch: false,
            skipIngredientConflictResolution: true,
            strictV1Validation: false)
        #expect(try C2PAJson.decode(VerifySettings.self, from: C2PAJson.encode(verify)) == verify)
    }

    @Test func builderSettings() throws {
        let builder = BuilderSettingsDefinition(
            vendor: "com.test",
            claimGeneratorInfo: ClaimGeneratorInfoSettings(name: "TestApp", version: "1.0", operatingSystem: "iOS 17"),
            thumbnail: ThumbnailSettings(
                enabled: true, ignoreErrors: false, longEdge: 1024, format: .webp, preferSmallestFormat: true, quality: .low),
            actions: ActionsSettings(
                allActionsIncluded: true,
                templates: [
                    ActionTemplateSettings(
                        action: "c2pa.created",
                        softwareAgent: ClaimGeneratorInfoSettings(name: "TestAgent"),
                        sourceType: digitalCapture,
                        description: "Test action")
                ],
                autoCreatedAction: AutoActionSettings(enabled: true, sourceType: digitalCapture),
                autoOpenedAction: AutoActionSettings(enabled: false),
                autoPlacedAction: AutoActionSettings(enabled: true)),
            certificateStatusFetch: .all,
            certificateStatusShouldOverride: false,
            intent: .create(digitalCapture),
            createdAssertionLabels: ["c2pa.actions"],
            preferBoxHash: true,
            generateC2paArchive: false,
            autoTimestampAssertion: TimeStampSettings(enabled: true, skipExisting: false, fetchScope: .all)
        )
        let decoded = try C2PAJson.decode(BuilderSettingsDefinition.self, from: C2PAJson.encode(builder))
        #expect(decoded == builder)
        #expect(decoded.claimGeneratorInfo?.name == "TestApp")
        #expect(decoded.actions?.templates?.count == 1)
        #expect(decoded.actions?.autoCreatedAction?.enabled == true)
        #expect(decoded.autoTimestampAssertion?.fetchScope == .all)
    }

    @Test func fullDefinitionRoundTrip() throws {
        let definition = C2PASettingsDefinition(
            version: 1,
            trust: TrustSettings(verifyTrustList: true),
            cawgTrust: TrustSettings(verifyTrustList: false, userAnchors: "cawg-anchors"),
            core: CoreSettings(merkleTreeChunkSizeInKb: 32, decodeIdentityAssertions: true),
            verify: VerifySettings(verifyAfterReading: true, strictV1Validation: false),
            builder: BuilderSettingsDefinition(vendor: "full-test", intent: .update),
            signer: .local(LocalSignerSettings(alg: "ps256", signCert: "cert-pem", privateKey: "key-pem", roles: ["signer", "validator"])),
            cawgX509Signer: .remote(RemoteSignerSettings(url: "https://cawg.example.com", alg: "es256", signCert: "cawg-cert"))
        )
        let decoded = try C2PASettingsDefinition.fromJSON(definition.toJSON())
        #expect(decoded == definition)
        guard case .local(let signer) = decoded.signer, case .remote(let cawg) = decoded.cawgX509Signer else {
            Issue.record("signer kinds changed in the round trip")
            return
        }
        #expect(signer.roles == ["signer", "validator"])
        #expect(cawg.url == "https://cawg.example.com")
        #expect(decoded.cawgTrust?.userAnchors == "cawg-anchors")
    }

    @Test func signerWithRoles() throws {
        let local = LocalSignerSettings(
            alg: "es256", signCert: "cert", privateKey: "key", tsaUrl: nil, referencedAssertions: nil, roles: ["signer"])
        let decodedLocal = try C2PAJson.decode(LocalSignerSettings.self, from: C2PAJson.encode(local))
        #expect(decodedLocal.roles == ["signer"])
        #expect(decodedLocal.tsaUrl == nil)

        let remote = RemoteSignerSettings(
            url: "https://example.com", alg: "es384", signCert: "cert", tsaUrl: "http://tsa.example.com",
            referencedAssertions: ["assertion1"], roles: ["validator"])
        let decodedRemote = try C2PAJson.decode(RemoteSignerSettings.self, from: C2PAJson.encode(remote))
        #expect(decodedRemote.roles == ["validator"])
        #expect(decodedRemote.tsaUrl == "http://tsa.example.com")
    }

    @Test func actionTemplateWithIndex() throws {
        let template = ActionTemplateSettings(action: "c2pa.edited", softwareAgentIndex: 0, description: "Edited with app")
        let decoded = try C2PAJson.decode(ActionTemplateSettings.self, from: C2PAJson.encode(template))
        #expect(decoded == template)
        #expect(decoded.softwareAgentIndex == 0)
        #expect(decoded.softwareAgent == nil)
    }

    @Test func timestampParentScope() throws {
        let timestamp = TimeStampSettings(enabled: true, skipExisting: true, fetchScope: .parent)
        let decoded = try C2PAJson.decode(TimeStampSettings.self, from: C2PAJson.encode(timestamp))
        #expect(decoded == timestamp)
        #expect(decoded.fetchScope == .parent)
    }

    // MARK: - Settings reach the C layer

    // C2PASettings has no getter, so these check the effect: with thumbnails
    // disabled, a signed image's manifest carries no thumbnail.

    private func signedManifestHasThumbnail(_ settings: C2PASettings) throws -> Bool {
        let builder = try Builder(context: C2PAContext(settings: settings), manifestJSON: Fixtures.createdManifestJSON())
        return try Fixtures.signAndRead(builder).active["thumbnail"] != nil
    }

    private let noThumbnail = C2PASettingsDefinition(
        version: 1, builder: BuilderSettingsDefinition(thumbnail: ThumbnailSettings(enabled: false)))

    @Test func defaultSettingsKeepThumbnail() throws {
        #expect(try signedManifestHasThumbnail(C2PASettings(json: #"{"version": 1}"#)))
    }

    @Test func c2paSettingsFromDefinition() throws {
        #expect(try !signedManifestHasThumbnail(C2PASettings(definition: noThumbnail)))
    }

    @Test func c2paSettingsLoadDefinition() throws {
        let settings = try C2PASettings(json: #"{"version": 1}"#)
        try settings.load(definition: noThumbnail)
        #expect(try !signedManifestHasThumbnail(settings))
    }

    @Test func c2paSettingsSetValue() throws {
        let settings = try C2PASettings(json: #"{"version": 1}"#)
        try settings.setValue(false, forPath: "builder.thumbnail.enabled")
        #expect(try !signedManifestHasThumbnail(settings))
    }

    @Test func c2paSettingsSetValueRejectsEmptyPath() throws {
        let settings = try C2PASettings(json: #"{"version": 1}"#)
        let error = try #require(throws: C2PAError.self) {
            try settings.setValue("value", forPath: "")
        }
        guard case .api(let message) = error else {
            Issue.record("expected .api, got \(error)")
            return
        }
        #expect(message == "Path must not be empty")
    }
}
