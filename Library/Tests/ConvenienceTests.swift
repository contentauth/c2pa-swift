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
//  ConvenienceTests.swift
//

import C2PA
import Foundation
import Testing

@Suite struct ConvenienceTests {

    private func expectAPIError(_ error: C2PAError?, containing text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .api(let message) = error else {
            Issue.record("expected .api containing \"\(text)\", got \(String(describing: error))", sourceLocation: sourceLocation)
            return
        }
        #expect(message.contains(text), "message: \(message)", sourceLocation: sourceLocation)
    }

    // MARK: - readFile

    @Test func readFileWithManifest() throws {
        let store = try ManifestStore(json: C2PA.readFile(at: Fixtures.url(Fixtures.adobeJPEG)))
        #expect(store.activeLabel == Fixtures.adobeActiveManifest)
        #expect(try store.active["title"] as? String == "CI.jpg")
    }

    @Test func readFileWithoutManifest() throws {
        let url = try Fixtures.url(Fixtures.pexelsJPEG)
        let error = #expect(throws: C2PAError.self) { try C2PA.readFile(at: url) }
        expectAPIError(error, containing: "ManifestNotFound")
    }

    /// The doc comment: the underlying file error when the file cannot be opened.
    @Test func readFileNonExistent() {
        let missing = Fixtures.tempURL(extension: "jpg")
        let error = #expect(throws: (any Error).self) { try C2PA.readFile(at: missing) }
        #expect(!(error is C2PAError), "a missing file surfaces the file error, got \(String(describing: error))")
        #expect((error as NSError?)?.domain == NSCocoaErrorDomain, "error: \(String(describing: error))")
    }

    @Test func readFileUnknownExtension() throws {
        let url = Fixtures.tempURL(extension: "zzz")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0x00, 0x01]).write(to: url)
        let error = #expect(throws: C2PAError.self) { try C2PA.readFile(at: url) }
        expectAPIError(error, containing: "unknown file type")
    }

    /// A file of a type c2pa cannot read (plain text) is refused.
    @Test func readFileInvalidFile() throws {
        let url = Fixtures.tempURL(extension: "txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("This is not a C2PA file".utf8).write(to: url)
        #expect(throws: C2PAError.self) { try C2PA.readFile(at: url) }
    }

    // MARK: - signFile

    @Test func signFile() throws {
        let destination = Fixtures.tempURL(extension: "jpg")
        defer { try? FileManager.default.removeItem(at: destination) }
        try C2PA.signFile(
            source: Fixtures.url(Fixtures.pexelsJPEG),
            destination: destination,
            manifestJSON: Fixtures.createdManifestJSON(claimGenerator: "signFile_test/1.0"),
            signerInfo: Fixtures.signerInfo())
        let store = try ManifestStore(json: C2PA.readFile(at: destination))
        #expect(try store.assertionLabels() == ["c2pa.actions.v2", "c2pa.test"])
        #expect(store.validationState == "Valid")
    }

    @Test(arguments: [
        "",
        "this is definitely not json",
        "{",
        #"{"foo": "bar"}"#
    ])
    func signFileWithInvalidManifest(manifestJSON: String) throws {
        let destination = Fixtures.tempURL(extension: "jpg")
        defer { try? FileManager.default.removeItem(at: destination) }
        let source = try Fixtures.url(Fixtures.pexelsJPEG)
        let signerInfo = try Fixtures.signerInfo()
        #expect(throws: C2PAError.self) {
            try C2PA.signFile(source: source, destination: destination, manifestJSON: manifestJSON, signerInfo: signerInfo)
        }
    }
}
