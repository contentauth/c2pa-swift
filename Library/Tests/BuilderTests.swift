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
//  BuilderTests.swift
//

import C2PA
import class C2PA.Stream // swiftlint:disable:this duplicate_imports
import Foundation
import Testing

/// Every builder test signs (or archives and then signs) and reads the result
/// back, so a pass means the manifest the builder was asked for is the one in
/// the file.
@Suite struct BuilderTests {

    // MARK: - Helpers

    /// Signs `source` into a temporary file. The caller removes `url`.
    private func sign(_ builder: Builder, source: String = Fixtures.pexelsJPEG, format: String = "image/jpeg") throws -> (url: URL, manifest: Data) {
        let url = Fixtures.tempURL(extension: (source as NSString).pathExtension)
        let manifest = try builder.sign(
            format: format, source: Fixtures.stream(source), destination: Stream(writeTo: url), signer: Fixtures.signer())
        return (url, manifest)
    }

    /// The created-asset manifest with extra top-level members.
    private func createdManifestJSON(adding extra: [String: Any]) throws -> String {
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(Fixtures.createdManifestJSON().utf8)) as? [String: Any])
        object.merge(extra) { _, new in new }
        return try JSONSerialization.data(withJSONObject: object).utf8Text
    }

    /// A context whose settings configure the test certificate as its signer,
    /// for the context-signed (embeddable) flows.
    private func signerContext(extra: [String: Any] = [:]) throws -> C2PAContext {
        try C2PAContext(settings: Fixtures.localSignerSettings(adding: extra))
    }

    /// A builder that can write ingredient archives: c2pa-rs refuses unless
    /// builder.generate_c2pa_archive is on.
    private func ingredientArchiveBuilder() throws -> Builder {
        let settings = try C2PASettings(json: #"{"version": 1, "builder": {"generate_c2pa_archive": true}}"#)
        return try Builder(context: C2PAContext(settings: settings), manifestJSON: Fixtures.createdManifestJSON())
    }

    private func archive(_ builder: Builder) throws -> URL {
        let url = Fixtures.tempURL(extension: "c2pa")
        try builder.writeArchive(to: Stream(writeTo: url))
        return url
    }

    private func thumbnailBytes(of signed: URL) throws -> Data {
        let reader = try Reader(format: "image/jpeg", stream: Stream(readFrom: signed))
        let thumbnail = try #require(try ManifestStore(json: reader.json()).active["thumbnail"] as? [String: Any])
        let identifier = try #require(thumbnail["identifier"] as? String)
        let out = Fixtures.tempURL(extension: "bin")
        defer { try? FileManager.default.removeItem(at: out) }
        try reader.resource(uri: identifier, to: Stream(writeTo: out))
        return try Data(contentsOf: out)
    }

    private let jumbfLabel = Data("c2pa".utf8)

    // MARK: - Signing

    @Test func builderAPI() throws {
        let store = try Fixtures.signAndRead(Builder(manifestJSON: Fixtures.createdManifestJSON()))
        #expect(try store.assertionLabels() == ["c2pa.actions.v2", "c2pa.test"])
        #expect(try store.actions() == ["c2pa.created"])
        let signature = try store.signatureInfo()
        #expect(signature["alg"] as? String == "Es256")
        #expect(signature["issuer"] as? String == "C2PA Test Signing Cert")
        #expect(store.validationState == "Valid")
    }

    @Test func builderContextManifestDefinition() throws {
        let manifest = ManifestDefinition.created(
            title: "ctx_def.jpg",
            claimGeneratorInfo: ClaimGeneratorInfo(name: "TestApp", version: "1.0"),
            digitalSourceType: .digitalCapture)
        let store = try Fixtures.signAndRead(Builder(context: C2PAContext(), manifest: manifest))
        #expect(try store.actions() == ["c2pa.created"])
    }

    @Test func builderSupportedMimeTypes() {
        let types = Builder.supportedMimeTypes
        #expect(types.contains("image/jpeg"))
        #expect(types.contains("video/mp4"))
    }

    @Test func builderHashType() throws {
        let builder = try Builder(manifestJSON: Fixtures.createdManifestJSON())
        #expect(try builder.hashType(format: "image/jpeg") == .dataHash)
        #expect(try builder.hashType(format: "video/mp4") == .bmffHash)
    }

    // MARK: - Intents and actions

    @Test func builderSetIntentCreate() throws {
        let builder = try Builder(manifestJSON: Fixtures.editManifestJSON())
        try builder.setIntent(.create(.digitalCapture))
        #expect(try Fixtures.signAndRead(builder).actions().first == "c2pa.created")
    }

    /// The edit intent takes the source asset as the parent ingredient.
    @Test func builderSetIntentEdit() throws {
        let builder = try Builder(manifestJSON: Fixtures.editManifestJSON())
        try builder.setIntent(.edit)
        let store = try Fixtures.signAndRead(builder)
        #expect(try store.actions().first == "c2pa.opened")
        let ingredients = try store.ingredients()
        #expect(ingredients.count == 1)
        #expect(ingredients.first?["relationship"] as? String == "parentOf")
    }

    /// An update manifest on an asset that already has one: the store gains a
    /// manifest whose parent is the previous one.
    @Test func builderSetIntentUpdate() throws {
        let builder = try Builder(manifestJSON: Fixtures.editManifestJSON())
        try builder.setIntent(.update)
        let store = try Fixtures.signAndRead(builder, source: Fixtures.adobeJPEG)
        #expect(store.manifestCount == 2)
        #expect(store.activeLabel != Fixtures.adobeActiveManifest)
        #expect(try store.ingredients().first?["relationship"] as? String == "parentOf")
    }

    @Test func builderAddAction() throws {
        let builder = try Builder(manifestJSON: Fixtures.editManifestJSON())
        try builder.setIntent(.edit)
        try builder.addAction(Action(action: "c2pa.edited", softwareAgent: "test/1.0"))
        let actions = try Fixtures.signAndRead(builder).actions()
        #expect(actions.contains("c2pa.edited"), "actions: \(actions)")
    }

    // MARK: - Ingredients and resources

    @Test func builderAddIngredient() throws {
        let builder = try Builder(manifestJSON: Fixtures.createdManifestJSON())
        try builder.addIngredient(
            json: #"{"title": "pexels.jpg", "relationship": "componentOf"}"#,
            format: "image/jpeg",
            from: Fixtures.stream(Fixtures.pexelsJPEG))
        let ingredients = try Fixtures.signAndRead(builder).ingredients()
        #expect(ingredients.count == 1)
        #expect(ingredients.first?["title"] as? String == "pexels.jpg")
        #expect(ingredients.first?["relationship"] as? String == "componentOf")
    }

    @Test func readIngredient() throws {
        let store = try ManifestStore(json: C2PA.readFile(at: Fixtures.url(Fixtures.adobeJPEG)))
        let ingredient = try #require(try store.ingredients().first)
        #expect(ingredient["title"] as? String == "I.jpg")
        #expect(ingredient["thumbnail"] != nil)
    }

    /// A resource added under the identifier the manifest's thumbnail names
    /// becomes the claim thumbnail.
    @Test func builderAddResource() throws {
        let builder = try Builder(
            manifestJSON: createdManifestJSON(adding: ["thumbnail": ["format": "image/png", "identifier": "thumbnail"]]))
        try builder.addResource(uri: "thumbnail", stream: Stream(data: Fixtures.tinyPNG()))
        let signed = try sign(builder)
        defer { try? FileManager.default.removeItem(at: signed.url) }
        #expect(try thumbnailBytes(of: signed.url) == Fixtures.tinyPNG())
    }

    /// With a base path, a resource identifier is a file relative to it.
    @Test func builderSetBasePath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("c2pa-base-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.tinyPNG().write(to: dir.appendingPathComponent("thumb.png"))

        let builder = try Builder(
            manifestJSON: createdManifestJSON(adding: ["thumbnail": ["format": "image/png", "identifier": "thumb.png"]]))
        try builder.setBasePath(dir)
        let signed = try sign(builder)
        defer { try? FileManager.default.removeItem(at: signed.url) }
        #expect(try thumbnailBytes(of: signed.url) == Fixtures.tinyPNG())
    }

    /// An ingredient is exported by its label (or instance_id), not its title.
    @Test func ingredientArchiveRoundtrip() throws {
        let exporter = try ingredientArchiveBuilder()
        try exporter.addIngredient(
            json: #"{"title": "archive_ingredient.jpg", "label": "archive-ingredient", "relationship": "componentOf"}"#,
            format: "image/jpeg",
            from: Fixtures.stream(Fixtures.pexelsJPEG))
        let archiveURL = Fixtures.tempURL(extension: "c2pa")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try exporter.writeIngredientArchive(id: "archive-ingredient", to: Stream(writeTo: archiveURL))
        #expect(try !Data(contentsOf: archiveURL).isEmpty)

        let importer = try Builder(manifestJSON: Fixtures.createdManifestJSON())
        try importer.addIngredient(fromArchive: Stream(readFrom: archiveURL))
        let ingredients = try Fixtures.signAndRead(importer).ingredients()
        #expect(ingredients.map { $0["title"] as? String } == ["archive_ingredient.jpg"])
    }

    @Test func addIngredientFromArchive() throws {
        let exporter = try ingredientArchiveBuilder()
        try exporter.addIngredient(
            json: #"{"title": "ing.jpg", "instance_id": "xmp:iid:ing-1", "relationship": "componentOf"}"#,
            format: "image/jpeg",
            from: Fixtures.stream(Fixtures.pexelsJPEG))
        let archiveURL = Fixtures.tempURL(extension: "c2pa")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try exporter.writeIngredientArchive(id: "xmp:iid:ing-1", to: Stream(writeTo: archiveURL))

        let importer = try Builder(manifestJSON: Fixtures.createdManifestJSON())
        try importer.addIngredient(fromArchive: Stream(readFrom: archiveURL))
        let ingredient = try #require(try Fixtures.signAndRead(importer).ingredients().first)
        #expect(ingredient["title"] as? String == "ing.jpg")
        #expect(ingredient["relationship"] as? String == "componentOf")
    }

    // MARK: - Archives

    @Test func builderFromArchive() throws {
        let archiveURL = try archive(Builder(manifestJSON: Fixtures.createdManifestJSON()))
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        let reopened = try Builder(archiveStream: Stream(readFrom: archiveURL))
        #expect(try Fixtures.signAndRead(reopened).assertionLabels().contains("c2pa.test"))
    }

    /// Archiving a reopened archive keeps the definition.
    @Test func builderFromArchiveRoundtrip() throws {
        let first = try archive(Builder(manifestJSON: Fixtures.createdManifestJSON()))
        defer { try? FileManager.default.removeItem(at: first) }
        let second = try archive(Builder(archiveStream: Stream(readFrom: first)))
        defer { try? FileManager.default.removeItem(at: second) }
        let store = try Fixtures.signAndRead(Builder(archiveStream: Stream(readFrom: second)))
        #expect(try store.assertionLabels() == ["c2pa.actions.v2", "c2pa.test"])
    }

    @Test func builderArchiveFromContext() throws {
        let archiveURL = try archive(Builder(manifestJSON: Fixtures.createdManifestJSON()))
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        let reopened = try Builder(context: C2PAContext(), archiveStream: Stream(readFrom: archiveURL))
        #expect(try Fixtures.signAndRead(reopened).assertionLabels().contains("c2pa.test"))
    }

    // MARK: - Remote and sidecar manifests

    /// No-embed leaves the asset without a manifest; the returned bytes are the
    /// manifest, readable as a sidecar.
    @Test func builderNoEmbed() throws {
        let builder = try Builder(manifestJSON: Fixtures.createdManifestJSON())
        builder.setNoEmbed()
        let signed = try sign(builder)
        defer { try? FileManager.default.removeItem(at: signed.url) }

        #expect(!signed.manifest.isEmpty)
        let error = #expect(throws: C2PAError.self) { try C2PA.readFile(at: signed.url) }
        if case .api(let message) = error {
            #expect(message.contains("ManifestNotFound"), "message: \(message)")
        }
        let sidecar = try Reader(format: "image/jpeg", stream: Stream(readFrom: signed.url), manifest: signed.manifest)
        #expect(try ManifestStore(json: sidecar.json()).assertionLabels().contains("c2pa.test"))
    }

    /// A remote URL is written into the asset's XMP as its provenance reference.
    @Test func builderRemoteURL() throws {
        let remote = "https://example.com/manifest.c2pa"
        let builder = try Builder(manifestJSON: Fixtures.createdManifestJSON())
        try builder.setRemote(url: try #require(URL(string: remote)))
        let signed = try sign(builder)
        defer { try? FileManager.default.removeItem(at: signed.url) }
        #expect(try Data(contentsOf: signed.url).range(of: Data(remote.utf8)) != nil, "the remote URL is not in the asset")
    }

    // MARK: - Embeddable (two-pass) signing

    @Test func needsPlaceholder() throws {
        let builder = try Builder(context: C2PAContext(), manifestJSON: Fixtures.createdManifestJSON())
        #expect(try builder.needsPlaceholder(format: "image/jpeg"))
    }

    /// The data-hash flow end to end: the placeholder goes in after the JPEG's
    /// start-of-image marker, its range is excluded from the hash, and the
    /// signed manifest, which must be the placeholder's size, replaces it.
    private func signDataHashed(_ builder: Builder) throws -> ManifestStore {
        let placeholder = try builder.placeholder(format: "image/jpeg")
        var asset = try Fixtures.data(Fixtures.pexelsJPEG)
        asset.insert(contentsOf: placeholder, at: 2)
        try builder.setDataHashExclusions([(start: 2, length: UInt64(placeholder.count))])
        try builder.updateHashFromStream(format: "image/jpeg", stream: Stream(data: asset))

        let signed = try builder.signEmbeddable(format: "image/jpeg")
        try #require(signed.count == placeholder.count, "signed \(signed.count) bytes into a \(placeholder.count)-byte placeholder")
        asset.replaceSubrange(2..<(2 + placeholder.count), with: signed)

        return try ManifestStore(json: Reader(format: "image/jpeg", stream: Stream(data: asset)).json())
    }

    @Test func dataHashSigningWorkflow() throws {
        let builder = try Builder(context: signerContext(), manifestJSON: Fixtures.createdManifestJSON())
        let store = try signDataHashed(builder)
        #expect(try store.assertionLabels().contains("c2pa.test"))
        #expect(store.validationState == "Valid")
    }

    /// The same flow with a callback signer handed to the context instead of
    /// one configured in its settings.
    @Test func dataHashFlowWithCallbackSigner() throws {
        let builder = try Builder(
            context: C2PAContext(signer: Fixtures.callbackSigner()), manifestJSON: Fixtures.createdManifestJSON())
        let store = try signDataHashed(builder)
        #expect(try store.assertionLabels().contains("c2pa.test"))
        #expect(store.validationState == "Valid")
    }

    /// Raw manifest bytes composed for JPEG become APP11 segments. Composing
    /// needs only a context, so the static form frames them identically, on a
    /// default context and on one passed in.
    @Test func composeManifest() throws {
        let builder = try Builder(manifestJSON: Fixtures.createdManifestJSON())
        builder.setNoEmbed()
        let signed = try sign(builder)
        defer { try? FileManager.default.removeItem(at: signed.url) }

        let composed = try builder.composeManifest(signed.manifest, format: "image/jpeg")
        #expect(composed.count > signed.manifest.count)
        #expect(composed.prefix(2) == Data([0xFF, 0xEB]), "expected a JPEG APP11 marker")
        #expect(try Builder.composeManifest(signed.manifest, format: "image/jpeg") == composed)
        #expect(try Builder.composeManifest(signed.manifest, format: "image/jpeg", context: C2PAContext()) == composed)
    }

    /// Composing frames the bytes without validating them, so the failure it
    /// can report is a format with no asset handler.
    @Test func composeManifestRejectsUnsupportedFormat() throws {
        let context = try C2PAContext()
        #expect(throws: C2PAError.self) {
            try Builder.composeManifest(Data([0x00, 0x01, 0x02, 0x03]), format: "application/x-unsupported", context: context)
        }
    }

    /// The fragmented BMFF flow; the asset itself won't validate (the mdat
    /// bytes are dummies), but every step must succeed and produce a manifest.
    @Test func bmffMerkleHashing() throws {
        let builder = try Builder(
            context: signerContext(extra: ["builder": ["created_assertion_labels": ["c2pa.actions"]]]),
            manifestJSON: Fixtures.createdManifestJSON())
        _ = try builder.placeholder(format: "video/mp4")
        try builder.setFixedSizeMerkle(1)
        try builder.hashMdatBytes(mdatId: 0, data: Data(repeating: 0xAB, count: 4096), largeSize: true)
        try builder.updateHashFromStream(format: "video/mp4", stream: Fixtures.stream(Fixtures.videoMP4))
        let embeddable = try builder.signEmbeddable(format: "video/mp4")
        #expect(embeddable.range(of: jumbfLabel) != nil, "no c2pa manifest store in the embeddable bytes")
    }
}
