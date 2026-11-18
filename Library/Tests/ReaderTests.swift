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
//  ReaderTests.swift
//

import C2PA
import class C2PA.Stream // swiftlint:disable:this duplicate_imports
import Foundation
import Testing

/// Reads the fixtures whose manifests are known: adobe-20220124-CI.jpg (one
/// manifest, one ingredient) and video1.mp4 (two manifests). The expected
/// values were read from the files with c2pa-rs v0.91.3.
@Suite struct ReaderTests {

    private func adobeReader() throws -> Reader {
        try Reader(format: "image/jpeg", stream: Fixtures.stream(Fixtures.adobeJPEG))
    }

    /// Collects what a Reader writes for a resource.
    private func resourceData(_ reader: Reader, uri: String) throws -> Data {
        let output = Fixtures.tempURL(extension: "bin")
        defer { try? FileManager.default.removeItem(at: output) }
        try reader.resource(uri: uri, to: Stream(writeTo: output))
        return try Data(contentsOf: output)
    }

    private func expectAPIError(_ error: C2PAError, containing text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .api(let message) = error else {
            Issue.record("expected .api containing \(text), got \(error)", sourceLocation: sourceLocation)
            return
        }
        #expect(message.contains(text), "message: \(message)", sourceLocation: sourceLocation)
    }

    // MARK: - Manifest content

    @Test func readsActiveManifest() throws {
        let store = try ManifestStore(json: adobeReader().json())
        #expect(store.activeLabel == Fixtures.adobeActiveManifest)
        let active = try store.active
        #expect(active["title"] as? String == "CI.jpg")
        #expect(active["format"] as? String == "image/jpeg")
        #expect(active["claim_generator"] as? String == "make_test_images/0.16.1 c2pa-rs/0.16.1")
        let labels = try store.assertionLabels()
        #expect(labels.contains("stds.schema-org.CreativeWork"))
        #expect(labels.contains { $0.hasPrefix("c2pa.actions") })
        #expect(try store.actions() == ["c2pa.created", "c2pa.drawing", "c2pa.placed", "c2pa.resized"])
        #expect(try store.signatureInfo()["issuer"] as? String == "C2PA Test Signing Cert")
    }

    @Test func readerWithMultipleStreams() throws {
        let first = try adobeReader().json()
        let second = try adobeReader().json()
        #expect(first == second, "two readers over the same image disagree")
        #expect(try ManifestStore(json: first).activeLabel == Fixtures.adobeActiveManifest)
    }

    @Test func videoManifest() throws {
        let reader = try Reader(format: "video/mp4", stream: Fixtures.stream(Fixtures.videoMP4))
        let store = try ManifestStore(json: reader.json())
        #expect(store.manifestCount == 2)
        #expect(try store.active["title"] as? String == "My Title")
        let ingredient = try #require(try store.ingredients().first)
        #expect(ingredient["title"] as? String == "video1.mp4")
        #expect(ingredient["relationship"] as? String == "parentOf")
        #expect(try store.assertionLabels().contains("my.assertion"))
    }

    @Test(arguments: [(Fixtures.adobeJPEG, "image/jpeg"), (Fixtures.videoMP4, "video/mp4")])
    func readerValidation(fixture: String, format: String) throws {
        let reader = try Reader(format: format, stream: Fixtures.stream(fixture))
        #expect(try ManifestStore(json: reader.json()).validationState == "Valid")
    }

    /// The doc only promises an error for an unreadable stream or a missing
    /// manifest; c2pa identifies a JPEG by its content, so a wrong format
    /// string still reads the manifest.
    @Test func readerSniffsContentDespiteFormatString() throws {
        let reader = try Reader(format: "invalid/format", stream: Fixtures.stream(Fixtures.adobeJPEG))
        #expect(try ManifestStore(json: reader.json()).activeLabel == Fixtures.adobeActiveManifest)
    }

    @Test func readerIngredientExtraction() throws {
        let ingredients = try ManifestStore(json: adobeReader().json()).ingredients()
        #expect(ingredients.count == 1)
        #expect(ingredients.first?["title"] as? String == "I.jpg")
        #expect(ingredients.first?["relationship"] as? String == "componentOf")
    }

    @Test func readerThumbnailExtraction() throws {
        let reader = try adobeReader()
        let store = try ManifestStore(json: reader.json())
        let thumbnail = try #require(try store.active["thumbnail"] as? [String: Any])
        #expect(thumbnail["format"] as? String == "image/jpeg")
        #expect(thumbnail["identifier"] as? String == Fixtures.adobeThumbnailURI)
        #expect(try store.ingredients().first?["thumbnail"] != nil, "the ingredient carries its own thumbnail")
    }

    @Test func resourceReading() throws {
        let data = try resourceData(adobeReader(), uri: Fixtures.adobeThumbnailURI)
        #expect(data.count == 76482)
        #expect(data.prefix(3) == Data([0xFF, 0xD8, 0xFF]), "the claim thumbnail is a JPEG")
    }

    @Test func readerResourceErrorHandling() throws {
        let reader = try adobeReader()
        let error = try #require(throws: C2PAError.self) {
            try resourceData(reader, uri: "http://example.com/nonexistent")
        }
        expectAPIError(error, containing: "ResourceNotFound")
    }

    @Test func readerRemoteURL() throws {
        #expect(try adobeReader().remote() == nil, "the manifest is embedded")
    }

    @Test func readerIsEmbedded() throws {
        #expect(try adobeReader().isEmbedded())
    }

    // MARK: - JSON forms

    @Test func readerJSONParsing() {
        let error = #expect(throws: C2PAError.self) {
            try Reader(format: "image/jpeg", stream: Fixtures.stream(Fixtures.pexelsJPEG))
        }
        if let error { expectAPIError(error, containing: "ManifestNotFound") }
    }

    @Test func readerDetailedJSON() throws {
        let detailed = try ManifestStore(json: adobeReader().detailedJSON())
        let active = try detailed.active
        for key in ["claim", "assertion_store", "signature"] {
            #expect(active[key] != nil, "detailed manifest is missing \(key)")
        }
    }

    @Test func readerDetailedJSONComparison() throws {
        let reader = try adobeReader()
        let standard = try reader.json()
        let detailed = try reader.detailedJSON()
        #expect(standard != detailed)
        #expect(try ManifestStore(json: standard).activeLabel == ManifestStore(json: detailed).activeLabel)
    }

    @Test func readerCrJSON() throws {
        let object = try JSONSerialization.jsonObject(with: Data(adobeReader().crJSON().utf8)) as? [String: Any]
        let keys = Set(try #require(object).keys)
        #expect(keys.isSuperset(of: ["@context", "manifests", "jsonGenerator"]), "keys: \(keys.sorted())")
    }

    // MARK: - Construction

    @Test func readerFromContext() throws {
        let context = try C2PAContext(settings: C2PASettings(json: #"{"version": 1}"#))
        let reader = try Reader(context: context, format: "image/jpeg", stream: Fixtures.stream(Fixtures.adobeJPEG))
        #expect(try ManifestStore(json: reader.json()).activeLabel == Fixtures.adobeActiveManifest)
    }

    /// Bytes that are not a manifest store must be rejected, not read as an empty one.
    @Test func readerWithManifestData() {
        let notAManifest = Data(#"{"claim_generator": "test/1.0", "assertions": []}"#.utf8)
        #expect(throws: C2PAError.self) {
            let reader = try Reader(format: "image/jpeg", stream: Fixtures.stream(Fixtures.pexelsJPEG), manifest: notAManifest)
            _ = try reader.json()
        }
    }

    @Test func readerSupportedMimeTypes() {
        let types = Reader.supportedMimeTypes
        #expect(types.contains("image/jpeg"))
        #expect(types.contains("video/mp4"))
    }
}
