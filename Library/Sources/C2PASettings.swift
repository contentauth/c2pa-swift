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
//  C2PASettings.swift
//

import C2PAC
import Foundation

/// Manages C2PA settings configuration.
///
/// `C2PASettings` provides a Swift-idiomatic interface for loading and applying
/// C2PA settings in JSON or TOML format. Settings control signer configuration,
/// CAWG identity assertions, thumbnail generation, and other build options.
///
/// Settings can be loaded from raw JSON/TOML strings or from a type-safe
/// ``C2PASettingsDefinition`` struct.
///
/// ## Example
///
/// ```swift
/// // From a raw JSON string
/// let settings = try C2PASettings(json: settingsJSON)
///
/// // From a type-safe definition
/// let definition = C2PASettingsDefinition(
///     version: 1,
///     signer: .local(LocalSignerSettings(
///         alg: "es256",
///         signCert: certPEM,
///         privateKey: keyPEM
///     ))
/// )
/// let settings = try C2PASettings(definition: definition)
/// ```
///
/// - SeeAlso: ``Signer``, ``C2PASettingsDefinition``
public final class C2PASettings {
    private var settingsString: String
    private var format: String
    private let ptr: UnsafeMutablePointer<C2paSettings>

    /// The native settings handle, used to configure a ``C2PAContext``.
    var rawPtr: UnsafeMutablePointer<C2paSettings> { ptr }

    /// Creates settings from a JSON string.
    ///
    /// - Parameter json: A JSON string containing C2PA settings.
    /// - Throws: ``C2PAError`` if the JSON is invalid.
    public init(json: String) throws {
        self.settingsString = json
        self.format = "json"
        self.ptr = try Self.makeHandle(from: json, format: "json")
    }

    /// Creates settings from a TOML string.
    ///
    /// - Parameter toml: A TOML string containing C2PA settings.
    /// - Throws: ``C2PAError`` if the TOML is invalid.
    public init(toml: String) throws {
        self.settingsString = toml
        self.format = "toml"
        self.ptr = try Self.makeHandle(from: toml, format: "toml")
    }

    /// Creates settings from a type-safe ``C2PASettingsDefinition``.
    ///
    /// The definition is encoded to JSON and applied to the C2PA runtime.
    ///
    /// - Parameter definition: A settings definition struct.
    /// - Throws: ``C2PAError`` if the settings are invalid.
    ///
    /// - SeeAlso: ``C2PASettingsDefinition``
    public init(definition: C2PASettingsDefinition) throws {
        let json = try C2PAJson.encode(definition)
        self.settingsString = json
        self.format = "json"
        self.ptr = try Self.makeHandle(from: json, format: "json")
    }

    /// Creates settings whose `builder.created_assertion_labels` is exactly `labels`.
    ///
    /// Labels in the list are classified as created assertions; all others are gathered.
    ///
    /// - Parameter labels: The full set of created-assertion labels.
    /// - Throws: ``C2PAError`` if the settings cannot be applied.
    ///
    /// - SeeAlso: ``Builder/defaultCreatedAssertionLabels``,
    ///   ``init(additionalCreatedAssertionLabels:)``
    public convenience init(createdAssertionLabels labels: [String]) throws {
        try self.init(
            definition: C2PASettingsDefinition(
                version: 1,
                builder: BuilderSettingsDefinition(createdAssertionLabels: labels)))
    }

    /// Creates settings that mark ``Builder/defaultCreatedAssertionLabels`` plus
    /// `additionalLabels` as created, the common "add my own created assertions" case.
    ///
    /// Labels already in the defaults are not repeated; the defaults come first.
    ///
    /// - Parameter additionalLabels: Extra created-assertion labels to add to the defaults.
    /// - Throws: ``C2PAError`` if the settings cannot be applied.
    ///
    /// - SeeAlso: ``Builder/defaultCreatedAssertionLabels``, ``init(createdAssertionLabels:)``
    public convenience init(additionalCreatedAssertionLabels additionalLabels: [String]) throws {
        let defaults = Builder.defaultCreatedAssertionLabels
        let extras = additionalLabels.filter { !defaults.contains($0) }
        try self.init(createdAssertionLabels: defaults + extras)
    }

    // No type-specific c2pa_settings_free exists; c2pa_free is the documented
    // general-purpose free and returns an int we intentionally discard.
    deinit { _ = c2pa_free(ptr) }

    /// Loads additional JSON settings, merging with existing configuration.
    ///
    /// - Parameter json: A JSON string containing C2PA settings to merge.
    /// - Throws: ``C2PAError`` if the JSON is invalid.
    public func load(json: String) throws {
        try Self.applyString(json, format: "json", to: ptr)
        self.settingsString = json
        self.format = "json"
    }

    /// Loads additional TOML settings, merging with existing configuration.
    ///
    /// - Parameter toml: A TOML string containing C2PA settings to merge.
    /// - Throws: ``C2PAError`` if the TOML is invalid.
    public func load(toml: String) throws {
        try Self.applyString(toml, format: "toml", to: ptr)
        self.settingsString = toml
        self.format = "toml"
    }

    /// Loads settings from a type-safe ``C2PASettingsDefinition``,
    /// merging with existing configuration.
    ///
    /// - Parameter definition: A settings definition struct.
    /// - Throws: ``C2PAError`` if the settings are invalid.
    public func load(definition: C2PASettingsDefinition) throws {
        let json = try C2PAJson.encode(definition)
        try Self.applyString(json, format: "json", to: ptr)
        self.settingsString = json
        self.format = "json"
    }

    /// Sets a single value at the given dot-separated path within the settings.
    ///
    /// This method parses the current JSON settings, navigates to the specified
    /// path, sets the value, and re-applies the updated settings.
    ///
    /// - Parameters:
    ///   - value: The value to set. Must be a JSON-compatible type
    ///     (`String`, `Int`, `Double`, `Bool`, or `nil`).
    ///   - path: A dot-separated path (e.g., `"builder.thumbnail.format"`).
    ///
    /// - Throws: ``C2PAError`` if the format is not JSON or the path is invalid.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let settings = try C2PASettings(json: "{\"version\": 1}")
    /// try settings.setValue("es256", forPath: "signer.local.alg")
    /// ```
    public func setValue(_ value: Any, forPath path: String) throws {
        guard format == "json" else {
            throw C2PAError.api("setValue is only supported for JSON settings")
        }

        guard let data = settingsString.data(using: .utf8),
              var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw C2PAError.api("Current settings are not a valid JSON object")
        }

        let components = path.split(separator: ".").map(String.init)
        guard !components.isEmpty else {
            throw C2PAError.api("Path must not be empty")
        }

        setNestedValue(&json, components: components, value: value)

        let updatedData = try JSONSerialization.data(withJSONObject: json)
        guard let updatedString = String(data: updatedData, encoding: .utf8) else {
            throw C2PAError.utf8
        }

        try Self.applyString(updatedString, format: "json", to: ptr)
        self.settingsString = updatedString
    }

    /// Creates a ``Signer`` from the loaded settings.
    ///
    /// - Returns: A configured ``Signer`` instance.
    /// - Throws: ``C2PAError`` if a signer cannot be created from the settings.
    public func createSigner() throws -> Signer {
        if format == "json" {
            return try Signer(settingsJSON: settingsString)
        } else {
            return try Signer(settingsTOML: settingsString)
        }
    }

    // MARK: - Private

    /// Allocates a native settings handle and applies the given string,
    /// freeing the handle if the update fails (a failed initializer does not
    /// run `deinit`).
    private static func makeHandle(
        from string: String,
        format: String
    ) throws -> UnsafeMutablePointer<C2paSettings> {
        let handle = try guardNotNull(c2pa_settings_new())
        do {
            try applyString(string, format: format, to: handle)
        } catch {
            _ = c2pa_free(handle)
            throw error
        }
        return handle
    }

    /// Applies a settings string in the given format to a native handle.
    private static func applyString(
        _ string: String,
        format: String,
        to handle: UnsafeMutablePointer<C2paSettings>
    ) throws {
        try string.withCString { settingsPtr in
            try format.withCString { formatPtr in
                let result = c2pa_settings_update_from_string(handle, settingsPtr, formatPtr)
                guard result == 0 else {
                    throw C2PAError.api(lastC2PAError())
                }
            }
        }
    }

    private func setNestedValue(
        _ dict: inout [String: Any],
        components: [String],
        value: Any
    ) {
        guard let key = components.first else { return }

        if components.count == 1 {
            dict[key] = value
        } else {
            var nested = dict[key] as? [String: Any] ?? [:]
            setNestedValue(&nested, components: Array(components.dropFirst()), value: value)
            dict[key] = nested
        }
    }
}
