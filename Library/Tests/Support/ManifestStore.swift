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
//  ManifestStore.swift
//

import Foundation

enum ManifestStoreError: Error, Equatable {
    case notAnObject
    case noActiveManifest
    case missingManifest(String)
}

/// A read-only view of a Reader's manifest store JSON, so tests can assert on
/// titles, labels and ingredients without decoding the full model.
struct ManifestStore {
    let raw: [String: Any]
    let activeLabel: String
    let validationState: String?
    /// The codes in validation_status, for example signingCredential.untrusted.
    let validationCodes: [String]

    init(json: String) throws {
        guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw ManifestStoreError.notAnObject
        }
        guard let active = object["active_manifest"] as? String else {
            throw ManifestStoreError.noActiveManifest
        }
        raw = object
        activeLabel = active
        validationState = object["validation_state"] as? String
        validationCodes = (object["validation_status"] as? [[String: Any]] ?? []).compactMap { $0["code"] as? String }
    }

    var manifestCount: Int {
        (raw["manifests"] as? [String: Any])?.count ?? 0
    }

    func manifest(_ label: String) throws -> [String: Any] {
        guard let manifest = (raw["manifests"] as? [String: Any])?[label] as? [String: Any] else {
            throw ManifestStoreError.missingManifest(label)
        }
        return manifest
    }

    var active: [String: Any] {
        get throws { try manifest(activeLabel) }
    }

    /// The assertion labels of a manifest; nil means the active one.
    func assertionLabels(of label: String? = nil) throws -> [String] {
        let assertions = try manifest(label ?? activeLabel)["assertions"] as? [[String: Any]] ?? []
        return assertions.compactMap { $0["label"] as? String }
    }

    func ingredients(of label: String? = nil) throws -> [[String: Any]] {
        try manifest(label ?? activeLabel)["ingredients"] as? [[String: Any]] ?? []
    }

    func signatureInfo(of label: String? = nil) throws -> [String: Any] {
        try manifest(label ?? activeLabel)["signature_info"] as? [String: Any] ?? [:]
    }

    /// The action names in the manifest's actions assertion (c2pa.actions or c2pa.actions.v2).
    func actions(of label: String? = nil) throws -> [String] {
        let assertions = try manifest(label ?? activeLabel)["assertions"] as? [[String: Any]] ?? []
        return assertions
            .filter { ($0["label"] as? String)?.hasPrefix("c2pa.actions") == true }
            .flatMap { (($0["data"] as? [String: Any])?["actions"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["action"] as? String }
    }
}
