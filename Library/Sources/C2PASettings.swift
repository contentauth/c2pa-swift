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
@safe
public final class C2PASettings {
    private let ptr: UnsafeMutablePointer<C2paSettings>

    /// The native settings handle, used to configure a ``C2PAContext``.
    var rawPtr: UnsafeMutablePointer<C2paSettings> { unsafe ptr }

    /// Creates settings from a JSON string.
    ///
    /// - Parameter json: A JSON string containing C2PA settings.
    /// - Throws: ``C2PAError`` if the JSON is invalid.
    public init(json: String) throws(C2PAError) {
        unsafe self.ptr = try unsafe Self.makeHandle(from: json, format: "json")
    }

    /// Creates settings from a TOML string.
    ///
    /// - Parameter toml: A TOML string containing C2PA settings.
    /// - Throws: ``C2PAError`` if the TOML is invalid.
    public init(toml: String) throws(C2PAError) {
        unsafe self.ptr = try unsafe Self.makeHandle(from: toml, format: "toml")
    }

    /// Creates settings from a type-safe ``C2PASettingsDefinition``.
    ///
    /// The definition is encoded to JSON and applied to the C2PA runtime.
    ///
    /// - Parameter definition: A settings definition struct.
    /// - Throws: ``C2PAError`` if the settings are invalid, or the underlying encoding
    ///   error if the definition cannot be encoded as JSON.
    ///
    /// - SeeAlso: ``C2PASettingsDefinition``
    public init(definition: C2PASettingsDefinition) throws {
        let json = try C2PAJson.encode(definition)
        unsafe self.ptr = try unsafe Self.makeHandle(from: json, format: "json")
    }

    // No type-specific c2pa_settings_free exists; c2pa_free is the documented
    // general-purpose free and returns an int we intentionally discard.
    deinit { _ = unsafe c2pa_free(ptr) }

    /// Loads additional JSON settings, merging with existing configuration.
    ///
    /// - Parameter json: A JSON string containing C2PA settings to merge.
    /// - Throws: ``C2PAError`` if the JSON is invalid.
    public func load(json: String) throws(C2PAError) {
        try unsafe Self.applyString(json, format: "json", to: ptr)
    }

    /// Loads additional TOML settings, merging with existing configuration.
    ///
    /// - Parameter toml: A TOML string containing C2PA settings to merge.
    /// - Throws: ``C2PAError`` if the TOML is invalid.
    public func load(toml: String) throws(C2PAError) {
        try unsafe Self.applyString(toml, format: "toml", to: ptr)
    }

    /// Loads settings from a type-safe ``C2PASettingsDefinition``,
    /// merging with existing configuration.
    ///
    /// - Parameter definition: A settings definition struct.
    /// - Throws: ``C2PAError`` if the settings are invalid, or the underlying encoding
    ///   error if the definition cannot be encoded as JSON.
    public func load(definition: C2PASettingsDefinition) throws {
        let json = try C2PAJson.encode(definition)
        try unsafe Self.applyString(json, format: "json", to: ptr)
    }

    /// Sets a single value at the given dot-separated path within the settings.
    ///
    /// The value is applied to the native settings directly, so this works whether the
    /// settings were loaded from JSON, TOML or a ``C2PASettingsDefinition``.
    ///
    /// - Parameters:
    ///   - value: The value to set: a `String`, `Bool`, `Int`, `Double`, or an array of
    ///     strings. To set a whole object, use ``load(json:)`` instead.
    ///   - path: A dot-separated path (e.g., `"builder.thumbnail.format"`). A well-formed
    ///     path that names no setting is ignored, as unknown keys are when loading settings.
    ///
    /// - Throws: ``C2PAError`` if the path is empty or has an empty segment (a leading,
    ///   trailing or doubled dot), if the value has no JSON representation, is null or is
    ///   an object, or if it is the wrong type for the setting at `path`. Serializing the
    ///   value can also throw the underlying `JSONSerialization` error.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let settings = try C2PASettings(toml: settingsTOML)
    /// try settings.setValue("es256", forPath: "signer.local.alg")
    /// ```
    public func setValue(_ value: Any, forPath path: String) throws {
        guard !path.isEmpty else {
            throw C2PAError.api("Path must not be empty")
        }
        // The native call splits the path on "." and keeps empty segments, so a leading or
        // doubled dot would store the value under an empty key and report success without
        // changing a setting.
        let segments = path.split(separator: ".", omittingEmptySubsequences: false)
        guard !segments.contains(where: \.isEmpty) else {
            throw C2PAError.api("Path must not contain empty segments: \(path)")
        }

        // The native call takes the value as JSON text. Validity is checked on the value
        // wrapped in an array, because isValidJSONObject only accepts a collection at the
        // top level, and it is checked at all because an unencodable value raises an
        // Objective-C exception, not a Swift error.
        guard JSONSerialization.isValidJSONObject([value]) else {
            throw C2PAError.api("Cannot encode a value of type \(type(of: value)) as JSON")
        }
        let encoded = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        guard let json = String(data: encoded, encoding: .utf8) else {
            throw C2PAError.utf8
        }

        _ = try unsafe guardNonNegative(Int64(c2pa_settings_set_value(ptr, path, json)))
    }

    // MARK: - Private

    /// Allocates a native settings handle and applies the given string,
    /// freeing the handle if the update fails (a failed initializer does not
    /// run `deinit`).
    private static func makeHandle(
        from string: String,
        format: String
    ) throws(C2PAError) -> UnsafeMutablePointer<C2paSettings> {
        let handle = try unsafe guardNotNull(c2pa_settings_new())
        do {
            try unsafe applyString(string, format: format, to: handle)
        } catch {
            _ = unsafe c2pa_free(handle)
            throw error
        }
        return unsafe handle
    }

    /// Applies a settings string in the given format to a native handle.
    private static func applyString(
        _ string: String,
        format: String,
        to handle: UnsafeMutablePointer<C2paSettings>
    ) throws(C2PAError) {
        // The check sits outside the closures because `String.withCString` erases the type of
        // an error thrown inside it.
        let result = unsafe string.withCString { settingsPtr in
            unsafe format.withCString { formatPtr in
                unsafe c2pa_settings_update_from_string(handle, settingsPtr, formatPtr)
            }
        }
        guard result == 0 else {
            throw C2PAError.api(lastC2PAError())
        }
    }
}
