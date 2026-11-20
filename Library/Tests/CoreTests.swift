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
//  CoreTests.swift
//

import C2PA
import Testing

@Suite struct CoreTests {

    @Test func libraryVersion() {
        // For example "c2pa-c/0.91.3 c2pa-rs/0.91.3".
        #expect(C2PA.version.range(of: #"c2pa-rs/\d+\.\d+\.\d+"#, options: .regularExpression) != nil, "version: \(C2PA.version)")
    }

    @Test func errorEnumCases() {
        #expect(C2PAError.api("Test error").localizedDescription == "C2PA API error: Test error")
        #expect(C2PAError.nilPointer.localizedDescription == "Unexpected NULL pointer")
        #expect(C2PAError.utf8.localizedDescription == "Invalid UTF-8 from C2PA")
        #expect(C2PAError.negative(42).localizedDescription == "C2PA negative status 42")
    }

    private struct Cause: Error, CustomStringConvertible {
        let description = "cause"
    }

    @Test func keyAndSigningErrorDescriptions() {
        #expect(C2PAError.ed25519NotSupported.localizedDescription == "Ed25519 not supported by Keychain")
        #expect(C2PAError.keySearchFailed("tag", -25300).localizedDescription == "Failed to find key 'tag' in keychain: -25300")
        #expect(
            C2PAError.keySearchFailed("tag", -25300, true).localizedDescription
                == "Failed to find key 'tag' in Secure Enclave: -25300")
        #expect(C2PAError.unsupportedAlgorithm(.ed25519).localizedDescription == "Key doesn't support algorithm ed25519")
        #expect(
            C2PAError.unsupportedAlgorithm(.ps256, true).localizedDescription
                == "Secure Enclave key doesn't support algorithm ps256")
        #expect(C2PAError.signingFailed().localizedDescription == "Signing failed")
        #expect(C2PAError.signingFailed(Cause(), true).localizedDescription == "Secure Enclave signing failed: cause")
        #expect(C2PAError.accessControlCreationFailed.localizedDescription == "Failed to create access control")
        #expect(C2PAError.publicKeyExtractionFailed.localizedDescription == "Failed to extract public key")
        #expect(C2PAError.publicKeyExportFailed().localizedDescription == "Failed to export public key")
        #expect(C2PAError.publicKeyExportFailed(Cause()).localizedDescription == "Failed to export public key: cause")
        #expect(C2PAError.asyncSigningFailed.localizedDescription == "Async signing operation failed")
    }

    /// Outside the Secure Enclave the message names no key kind, and leaves no gap where one would go.
    @Test func keyCreationErrorDescriptions() {
        #expect(C2PAError.keyCreationFailed().localizedDescription == "Failed to create key")
        #expect(C2PAError.keyCreationFailed(Cause()).localizedDescription == "Failed to create key: cause")
        #expect(
            C2PAError.keyCreationFailed(Cause(), true).localizedDescription
                == "Failed to create Secure Enclave key: cause")
    }

    @Test func manifestValidationErrorDescription() {
        let result = ManifestValidationResult(errors: ["no title", "no format"])
        #expect(
            C2PAError.manifestValidationFailed(result).localizedDescription
                == "Manifest validation failed: no title; no format")
    }
}
