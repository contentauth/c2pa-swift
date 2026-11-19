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
//  SupportTests.swift
//

import C2PA
import Foundation
import Testing

@Suite struct FixturesTests {

    @Test func missingFixtureThrows() {
        #expect(throws: FixtureError.missing("nope.jpg")) {
            try Fixtures.url("nope.jpg")
        }
    }

    @Test(arguments: [
        Fixtures.adobeJPEG, Fixtures.pexelsJPEG, Fixtures.videoMP4,
        "es256_certs.pem", "es256_private.key",
        "test_settings_with_cawg_signing.json", "test_settings_with_cawg_signing.toml"
    ])
    func everyFixtureLoads(name: String) throws {
        #expect(try !Fixtures.data(name).isEmpty)
    }

    @Test func tempURLsAreUnique() {
        let urls = (0..<100).map { _ in Fixtures.tempURL(extension: "jpg") }
        #expect(Set(urls).count == 100)
        #expect(urls.allSatisfy { $0.pathExtension == "jpg" })
    }

    @Test func keyTagsAreUnique() {
        let first = Fixtures.uniqueKeyTag("k")
        let second = Fixtures.uniqueKeyTag("k")
        #expect(first != second)
        #expect(first.hasPrefix("org.contentauth.test.k."))
    }

    @Test func signerReservesSpace() throws {
        #expect(try Fixtures.signer().reserveSize() > 0)
    }
}

@Suite struct ManifestStoreTests {

    @Test func parsesAdobe() throws {
        let reader = try Reader(format: "image/jpeg", stream: Fixtures.stream(Fixtures.adobeJPEG))
        let store = try ManifestStore(json: reader.json())
        #expect(store.activeLabel == Fixtures.adobeActiveManifest)
        #expect(try store.active["title"] as? String == "CI.jpg")
        #expect(try store.ingredients().first?["title"] as? String == "I.jpg")
        #expect(store.validationState == "Valid")
    }

    @Test func rejectsJSONWithoutActiveManifest() {
        #expect(throws: ManifestStoreError.self) {
            try ManifestStore(json: #"{"manifests": {}}"#)
        }
    }
}

@Suite struct TestEnvironmentTests {

    @Test(.enabled(if: TestEnvironment.signingServerRequired, "The signing server is optional in this run"))
    func signingServerReachableWhenRequired() async throws {
        try await TestEnvironment.requireSigningServer()
    }

    @Test func serverProbeRetriesUntilAnswered() async {
        var attempts = 0
        let result = await TestEnvironment.awaitSigningServer(pause: .zero) {
            attempts += 1
            return attempts < 3 ? .unanswered("timed out") : .reachable
        }
        #expect(result == .reachable)
        #expect(attempts == 3)
    }

    @Test func serverProbeStopsWhenNothingListens() async {
        var attempts = 0
        let result = await TestEnvironment.awaitSigningServer(pause: .zero) {
            attempts += 1
            return .notListening("connection refused")
        }
        #expect(result == .notListening("connection refused"))
        #expect(attempts == 1)
    }

    @Test func serverProbeGivesUpWhenPatienceRunsOut() async {
        var attempts = 0
        let result = await TestEnvironment.awaitSigningServer(patience: .zero, pause: .zero) {
            attempts += 1
            return .unanswered("timed out")
        }
        #expect(result == .unanswered("timed out"))
        #expect(attempts == 1)
    }
}
