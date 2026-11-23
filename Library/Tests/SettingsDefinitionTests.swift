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

    /// c2pa-rs names the variants in lowercase and gives create its source type
    /// directly. Any other shape is rejected when the settings load.
    @Test func intentWireForms() throws {
        #expect(
            try JSONValue(encoding: SettingsIntent.create(digitalCapture)) == .object(["create": .string(digitalCapture)]))
        #expect(try JSONValue(encoding: SettingsIntent.edit) == .string("edit"))
        #expect(try JSONValue(encoding: SettingsIntent.update) == .string("update"))
    }

    /// c2pa-rs lowercases an intent string before matching it.
    @Test(arguments: ["edit", "Edit", "EDIT"])
    func intentStringDecodesInAnyCase(spelling: String) throws {
        #expect(try C2PAJson.decode(SettingsIntent.self, from: "\"\(spelling)\"") == .edit)
    }

    /// c2pa-rs lowercases these four values too before matching them, so
    /// settings it accepts must decode here.
    @Test func enumValuesDecodeInAnyCase() throws {
        let thumbnail = try C2PAJson.decode(ThumbnailSettings.self, from: #"{"format": "PNG", "quality": "High"}"#)
        #expect(thumbnail.format == .png)
        #expect(thumbnail.quality == .high)
        let timeStamp = try C2PAJson.decode(TimeStampSettings.self, from: #"{"fetch_scope": "Parent"}"#)
        #expect(timeStamp.fetchScope == .parent)
        let builder = try C2PAJson.decode(BuilderSettingsDefinition.self, from: #"{"certificate_status_fetch": "ALL"}"#)
        #expect(builder.certificateStatusFetch == .all)

        // Written back the way c2pa-rs writes them.
        #expect(try JSONValue(encoding: thumbnail) == .object(["format": .string("png"), "quality": .string("high")]))
        #expect(throws: DecodingError.self) {
            try C2PAJson.decode(ThumbnailSettings.self, from: #"{"format": "bmp"}"#)
        }
        #expect(throws: DecodingError.self) {
            try C2PAJson.decode(ThumbnailSettings.self, from: #"{"format": 1}"#)
        }
    }

    /// The first is the shape earlier releases wrote for create, which c2pa-rs
    /// rejects. None of these may decode to an intent.
    @Test(arguments: [
        #"{"Create":{"digital_source_type":"http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"}}"#,
        #"{"create":{"digital_source_type":"http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"}}"#,
        #""create""#,
        #""delete""#,
        "1"
    ])
    func intentRejectsOtherShapes(json: String) {
        #expect(throws: DecodingError.self) { try C2PAJson.decode(SettingsIntent.self, from: json) }
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
            anchors: [
                TrustAnchor(trustAnchors: "manifest-roots", trustUri: "https://example.com/list", allowedList: "leaf"),
                TrustAnchor(trustAnchors: "tsa-roots", trustKind: .tsa),
                TrustAnchor(
                    trustAnchors: "cawg-roots", trustKind: .cawg, trustConfig: "1.3.6.1.5.5.7.3.4",
                    trustedIcaIssuers: ["did:web:example.com"])
            ],
            trustConfig: "1.3.6.1.5.5.7.3.36",
            useDefaultEkus: false)
        #expect(try C2PAJson.decode(TrustSettings.self, from: C2PAJson.encode(trust)) == trust)
    }

    /// c2pa-rs rejects an anchor without trust_kind, so the default is written out.
    @Test func trustAnchorDefaultsToManifestKind() throws {
        let anchor = TrustAnchor(trustAnchors: "roots")
        #expect(anchor.trustKind == .manifest)
        #expect(try JSONValue(encoding: anchor)["trust_kind"] == .string("manifest"))
    }

    /// c2pa-rs ignores each of these keys where earlier releases wrote them.
    /// allowed_list remains, but only inside an anchor.
    @Test func trustWritesNoRemovedKeys() throws {
        let definition = C2PASettingsDefinition(
            trust: TrustSettings(anchors: [TrustAnchor(trustAnchors: "roots", allowedList: "leaf")]))
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(definition.toJSON().utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["trust"])
        let trust = try #require(object["trust"] as? [String: Any])
        #expect(Set(trust.keys) == ["anchors"])
        let anchor = try #require((trust["anchors"] as? [[String: Any]])?.first)
        #expect(Set(anchor.keys) == ["trust_anchors", "trust_kind", "allowed_list"])
    }

    @Test(arguments: [#"{"trust_kind":"manifest"}"#, #"{"trust_anchors":"roots"}"#, #"{"trust_anchors":"roots","trust_kind":"CAWG"}"#])
    func trustAnchorRejectsWhatUpstreamRejects(json: String) {
        #expect(throws: DecodingError.self) { try C2PAJson.decode(TrustAnchor.self, from: json) }
    }

    @Test func coreSettings() throws {
        let core = CoreSettings(
            merkleTreeChunkSizeInKb: 64,
            merkleTreeMaxProofs: 100,
            backingStoreMemoryThresholdInMb: 256,
            decodeIdentityAssertions: true,
            allowedNetworkHosts: ["example.com", "cdn.example.com"],
            allowRedirects: false,
            preferCompressManifests: true,
            maxDecompressedManifestSizeInMb: 16,
            timeStampRequestAttempts: 2,
            timeStampRequestTimeoutInMs: 5_000,
            timeStampRetryDelayInMs: 250,
            httpRequestTimeoutInMs: 8_000)
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
            strictV1Validation: false,
            ocspFetchShouldOverride: true,
            maxManifestResponseSize: 1_048_576,
            verifyAfterSignHash: true)
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
                autoPlacedAction: AutoActionSettings(enabled: true),
                autoAllActionsIncluded: true),
            certificateStatusFetch: .all,
            certificateStatusShouldOverride: false,
            intent: .create(digitalCapture),
            createdAssertionLabels: ["c2pa.actions"],
            preferBoxHash: true,
            generateC2paArchive: false,
            autoTimestampAssertion: TimeStampSettings(enabled: true, skipExisting: false, fetchScope: .all),
            bmffHashExcludeFreeAndSkipBoxes: false,
            ignoreIngredientErrors: true
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
            trust: TrustSettings(
                anchors: [TrustAnchor(trustAnchors: "cawg-anchors", trustKind: .cawg)], useDefaultEkus: true),
            core: CoreSettings(merkleTreeChunkSizeInKb: 32, decodeIdentityAssertions: true),
            verify: VerifySettings(verifyAfterReading: true, strictV1Validation: false),
            builder: BuilderSettingsDefinition(vendor: "full-test", intent: .update),
            signer: .local(LocalSignerSettings(alg: "ps256", signCert: "cert-pem", privateKey: "key-pem", roles: ["signer", "validator"])),
            cawgX509Signer: .remote(RemoteSignerSettings(url: "https://cawg.example.com", alg: "es256", signCert: "cawg-cert")),
            softBinding: SoftBindingSettings(softBindingAlgorithms: ["com.example.watermark.1"])
        )
        let decoded = try C2PASettingsDefinition.fromJSON(definition.toJSON())
        #expect(decoded == definition)
        guard case .local(let signer) = decoded.signer, case .remote(let cawg) = decoded.cawgX509Signer else {
            Issue.record("signer kinds changed in the round trip")
            return
        }
        #expect(signer.roles == ["signer", "validator"])
        #expect(cawg.url == "https://cawg.example.com")
        #expect(decoded.trust?.anchors?.first?.trustKind == .cawg)
        #expect(decoded.softBinding?.softBindingAlgorithms == ["com.example.watermark.1"])
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

    @Test func c2paSettingsLoadJSON() throws {
        let settings = try C2PASettings(json: #"{"version": 1}"#)
        try settings.load(json: #"{"version": 1, "builder": {"thumbnail": {"enabled": false}}}"#)
        #expect(try !signedManifestHasThumbnail(settings))
    }

    @Test func c2paSettingsLoadTOML() throws {
        let settings = try C2PASettings(toml: "version = 1")
        try settings.load(toml: "version = 1\n\n[builder.thumbnail]\nenabled = false\n")
        #expect(try !signedManifestHasThumbnail(settings))
    }

    @Test func c2paSettingsRejectMalformedJSON() {
        #expect(throws: C2PAError.self) { try C2PASettings(json: #"{"version": "#) }
    }

    @Test func c2paSettingsLoadRejectsMalformedTOML() throws {
        let settings = try C2PASettings(toml: "version = 1")
        #expect(throws: C2PAError.self) { try settings.load(toml: "version = ") }
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

    /// The value goes to the native settings, so it works on settings loaded
    /// from TOML. The signer is declared with an algorithm the test key cannot
    /// sign with: signing succeeds only once es256 has reached the native
    /// settings and the rest of the signer section came through intact.
    @Test func c2paSettingsSetValueOnTOML() throws {
        let certs = try Fixtures.certsPEM()
        let key = try Fixtures.privateKeyPEM()
        let settings = try C2PASettings(toml: #"""
            version = 1

            [signer.local]
            alg = "es384"
            sign_cert = """
            \#(certs)"""
            private_key = """
            \#(key)"""
            """#)

        func sign() throws -> ManifestStore {
            let builder = try Builder(context: C2PAContext(settings: settings), manifestJSON: Fixtures.createdManifestJSON())
            return try Fixtures.signAndReadWithContextSigner(builder)
        }

        // Were this to sign, the success after setValue would prove nothing.
        #expect(throws: C2PAError.self, "signed with an algorithm the test key does not support") {
            try sign()
        }
        try settings.setValue("es256", forPath: "signer.local.alg")
        #expect(try sign().signatureInfo()["alg"] as? String == "Es256")
    }

    /// Left to the native call, a leading or doubled dot stores the value under
    /// an empty key, changes no setting and reports success. The message pins
    /// each throw to the wrapper's own check.
    @Test(arguments: [".", ".verify.verify_after_reading", "verify..verify_after_reading", "verify.verify_after_reading."])
    func c2paSettingsSetValueRejectsEmptyPathSegments(path: String) throws {
        let settings = try C2PASettings(json: #"{"version": 1}"#)
        let error = try #require(throws: C2PAError.self) {
            try settings.setValue(true, forPath: path)
        }
        guard case .api(let message) = error else {
            Issue.record("expected .api, got \(error)")
            return
        }
        #expect(message.contains("empty segments"), "message: \(message)")
    }

    /// JSONSerialization raises an Objective-C exception for a value it cannot
    /// encode, so setValue has to turn it away first.
    @Test func c2paSettingsSetValueRejectsUnencodableValue() throws {
        let settings = try C2PASettings(json: #"{"version": 1}"#)
        #expect(throws: C2PAError.self) {
            try settings.setValue(Date(), forPath: "verify.verify_after_reading")
        }
    }

    @Test func c2paSettingsSetValueRejectsNull() throws {
        let settings = try C2PASettings(json: #"{"version": 1}"#)
        #expect(throws: C2PAError.self) {
            try settings.setValue(NSNull(), forPath: "verify.verify_after_reading")
        }
    }

    // MARK: - New keys reach the C layer

    /// A definition with every modelled key set to a value c2pa-rs accepts.
    static func everyKeyDefinition() throws -> C2PASettingsDefinition {
        let root = try Fixtures.rootBundlePEM()
        let leaf = try Fixtures.leafCertificatePEM()
        let digitalCapture = DigitalSourceType.digitalCapture.rawValue
        let generator = ClaimGeneratorInfoSettings(name: "TestApp", version: "1.0", operatingSystem: "arm64-apple-ios")
        let autoAction = AutoActionSettings(enabled: true, sourceType: digitalCapture)
        return C2PASettingsDefinition(
            version: 1,
            trust: TrustSettings(
                anchors: [
                    TrustAnchor(
                        trustAnchors: root, trustKind: .manifest, trustUri: "https://example.com/trust-list",
                        trustConfig: "1.3.6.1.5.5.7.3.36", allowedList: leaf,
                        trustedIcaIssuers: ["did:web:example.com"]),
                    TrustAnchor(trustAnchors: root, trustKind: .tsa),
                    TrustAnchor(trustAnchors: root, trustKind: .cawg)
                ],
                trustConfig: "1.3.6.1.5.5.7.3.36",
                useDefaultEkus: true),
            core: CoreSettings(
                merkleTreeChunkSizeInKb: 64,
                merkleTreeMaxProofs: 5,
                backingStoreMemoryThresholdInMb: 256,
                decodeIdentityAssertions: true,
                allowedNetworkHosts: ["*.example.com"],
                allowRedirects: false,
                preferCompressManifests: true,
                maxDecompressedManifestSizeInMb: 16,
                timeStampRequestAttempts: 2,
                timeStampRequestTimeoutInMs: 500,
                timeStampRetryDelayInMs: 10,
                httpRequestTimeoutInMs: 500),
            verify: VerifySettings(
                verifyAfterReading: true,
                verifyAfterSign: true,
                verifyTrust: true,
                verifyTimestampTrust: true,
                ocspFetch: false,
                remoteManifestFetch: false,
                skipIngredientConflictResolution: false,
                strictV1Validation: false,
                ocspFetchShouldOverride: false,
                maxManifestResponseSize: 1_048_576,
                verifyAfterSignHash: true),
            builder: BuilderSettingsDefinition(
                vendor: "com.example",
                claimGeneratorInfo: generator,
                thumbnail: ThumbnailSettings(
                    enabled: true, ignoreErrors: true, longEdge: 512, format: .jpeg, preferSmallestFormat: true,
                    quality: .low),
                actions: ActionsSettings(
                    allActionsIncluded: true,
                    templates: [
                        ActionTemplateSettings(
                            action: "c2pa.edited", softwareAgent: generator, softwareAgentIndex: 0,
                            sourceType: digitalCapture, description: "Edited in TestApp")
                    ],
                    autoCreatedAction: autoAction,
                    autoOpenedAction: autoAction,
                    autoPlacedAction: autoAction,
                    autoAllActionsIncluded: true),
                certificateStatusFetch: .active,
                certificateStatusShouldOverride: false,
                intent: .create(digitalCapture),
                createdAssertionLabels: ["c2pa.actions"],
                preferBoxHash: true,
                generateC2paArchive: true,
                autoTimestampAssertion: TimeStampSettings(enabled: false, skipExisting: true, fetchScope: .parent),
                bmffHashExcludeFreeAndSkipBoxes: false,
                ignoreIngredientErrors: true),
            signer: .local(
                LocalSignerSettings(
                    alg: "es256", signCert: try Fixtures.certsPEM(), privateKey: try Fixtures.privateKeyPEM(),
                    tsaUrl: "http://tsa.example.com", referencedAssertions: ["c2pa.actions"],
                    roles: ["cawg.creator"])),
            cawgX509Signer: .remote(
                RemoteSignerSettings(
                    url: "https://signer.example.com", alg: "es256", signCert: try Fixtures.certsPEM(),
                    tsaUrl: "http://tsa.example.com", referencedAssertions: ["c2pa.actions"],
                    roles: ["cawg.creator"])),
            softBinding: SoftBindingSettings(softBindingAlgorithms: ["com.example.watermark.1"]))
    }

    /// c2pa-rs refuses settings it cannot deserialize, so loading every key at
    /// once catches a key whose value has the wrong shape. With the create
    /// intent this failed before the intent was written the way c2pa-rs reads it.
    @Test func everyKeyLoads() throws {
        _ = try C2PASettings(definition: Self.everyKeyDefinition())
    }

    /// Shows the request settings are read: c2pa-rs validates this one.
    @Test func zeroTimeStampAttemptsAreRejected() throws {
        let definition = C2PASettingsDefinition(version: 1, core: CoreSettings(timeStampRequestAttempts: 0))
        let error = try #require(throws: C2PAError.self) { try C2PASettings(definition: definition) }
        #expect("\(error)".contains("time_stamp_request_attempts"), "error: \(error)")
    }

    // c2pa-rs ignores keys it does not know, so settings that merely load prove
    // nothing about their names. These show an effect for each trust key: the
    // validation state of an asset signed with the test certificate.

    enum TrustCase: String, CaseIterable, CustomTestStringConvertible {
        case noAnchors, manifestAnchor, timeStampAnchor, cawgAnchor, allowedListOnly, unrelatedExtendedKeyUsage

        var testDescription: String { rawValue }

        var expectedState: String {
            switch self {
            case .manifestAnchor, .allowedListOnly: "Trusted"
            case .noAnchors, .timeStampAnchor, .cawgAnchor: "Valid"
            case .unrelatedExtendedKeyUsage: "Invalid"
            }
        }

        func trust() throws -> TrustSettings {
            let root = try Fixtures.rootBundlePEM()
            return switch self {
            case .noAnchors:
                TrustSettings()
            case .manifestAnchor:
                TrustSettings(anchors: [TrustAnchor(trustAnchors: root)])
            case .timeStampAnchor:
                TrustSettings(anchors: [TrustAnchor(trustAnchors: root, trustKind: .tsa)])
            case .cawgAnchor:
                TrustSettings(anchors: [TrustAnchor(trustAnchors: root, trustKind: .cawg)])
            case .allowedListOnly:
                // No root at all: the signing certificate itself is allowed.
                TrustSettings(anchors: [TrustAnchor(trustAnchors: "", allowedList: try Fixtures.leafCertificatePEM())])
            case .unrelatedExtendedKeyUsage:
                // The root is trusted, but only a purpose the certificate lacks is accepted.
                TrustSettings(
                    anchors: [TrustAnchor(trustAnchors: root)], trustConfig: "1.2.3.4", useDefaultEkus: false)
            }
        }
    }

    @Test(arguments: TrustCase.allCases)
    func trustSettingsDecideValidationState(trustCase: TrustCase) throws {
        let settings = try C2PASettings(definition: C2PASettingsDefinition(version: 1, trust: trustCase.trust()))
        let store = try Fixtures.signAndRead(
            Builder(manifestJSON: Fixtures.createdManifestJSON()), readingWith: settings)
        #expect(store.validationState == trustCase.expectedState, "validation status: \(store.validationCodes)")
    }

    /// The trust list a certificate chained to is named in the results by its URI.
    @Test func trustListURIIsReported() throws {
        let anchor = TrustAnchor(trustAnchors: try Fixtures.rootBundlePEM(), trustUri: "https://example.com/trust-list")
        let settings = try C2PASettings(
            definition: C2PASettingsDefinition(version: 1, trust: TrustSettings(anchors: [anchor])))
        let store = try Fixtures.signAndRead(
            Builder(manifestJSON: Fixtures.createdManifestJSON()), readingWith: settings)
        let results = try #require(store.raw["validation_results"] as? [String: Any])
        #expect(results["trustListUri"] as? String == "https://example.com/trust-list")
    }
}
