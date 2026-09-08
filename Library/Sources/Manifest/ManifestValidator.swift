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
//  ManifestValidator.swift
//

import Foundation

/// Validates C2PA manifest definitions for spec compliance.
///
/// `ManifestValidator` checks manifests against the C2PA 2.3 specification
/// and CAWG requirements, identifying errors that would prevent signing and
/// warnings about deprecated or suboptimal configurations.
///
/// ## Example
///
/// ```swift
/// let result = ManifestValidator.validate(manifest)
/// if result.isValid {
///     let builder = try Builder(manifestJSON: manifest.toJSON())
/// } else {
///     for error in result.errors {
///         print("Validation error: \(error)")
///     }
/// }
/// ```
///
/// - SeeAlso: ``ManifestValidationResult``, ``ManifestDefinition``
public enum ManifestValidator {
    /// The recommended claim version for new manifests.
    public static let recommendedClaimVersion: UInt8 = 2

    /// Assertion labels that are deprecated in the C2PA 2.3 specification.
    ///
    /// These labels should be replaced with their modern equivalents:
    /// - `stds.exif` -> use EXIF data in actions metadata
    /// - `stds.iptc.photo-metadata` -> use IPTC data in actions metadata
    /// - `c2pa.actions` -> use `c2pa.actions.v2`
    public static let deprecatedAssertionLabels: [String: String] = [
        "stds.exif": "Use EXIF data in action metadata instead",
        "stds.iptc.photo-metadata": "Use IPTC data in action metadata instead",
        "c2pa.actions": "Use c2pa.actions.v2 for new manifests"
    ]

    // MARK: - Validation

    /// Validates a manifest definition for C2PA spec compliance.
    ///
    /// - Parameter manifest: The manifest to validate.
    /// - Returns: A ``ManifestValidationResult`` with any errors and warnings.
    public static func validate(_ manifest: ManifestDefinition) -> ManifestValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        validateBasicRequirements(manifest, errors: &errors, warnings: &warnings)
        validateAssertions(manifest, errors: &errors, warnings: &warnings)
        validateIngredients(manifest, warnings: &warnings)

        return ManifestValidationResult(errors: errors, warnings: warnings)
    }

    /// Validates and logs warnings for a ManifestDefinition.
    ///
    /// - Parameter manifest: The manifest to validate.
    /// - Returns: A ``ManifestValidationResult`` with any errors or warnings found.
    @discardableResult
    public static func validateAndLog(_ manifest: ManifestDefinition) -> ManifestValidationResult {
        let result = validate(manifest)
        for error in result.errors {
            NSLog("[C2PA] Manifest validation error: %@", error)
        }
        for warning in result.warnings {
            NSLog("[C2PA] Manifest validation warning: %@", warning)
        }
        return result
    }

    /// Validates a manifest JSON string.
    ///
    /// - Parameter manifestJSON: The JSON string to validate.
    /// - Returns: A ``ManifestValidationResult`` with any errors and warnings.
    public static func validateJSON(_ manifestJSON: String) -> ManifestValidationResult {
        do {
            let manifest = try C2PAJson.decode(ManifestDefinition.self, from: manifestJSON)
            return validate(manifest)
        } catch {
            return ManifestValidationResult(errors: ["Failed to parse manifest JSON: \(error.localizedDescription)"])
        }
    }

    // MARK: - Private

    private static func validateBasicRequirements(
        _ manifest: ManifestDefinition,
        errors: inout [String],
        warnings: inout [String]
    ) {
        // Title is required
        if manifest.title.isEmpty {
            errors.append("Manifest title is required")
        }

        // Claim generator info is required
        if manifest.claimGeneratorInfo.isEmpty {
            errors.append("At least one claim_generator_info entry is required")
        }

        // Claim version
        if manifest.claimVersion < recommendedClaimVersion {
            warnings.append("Claim version \(manifest.claimVersion) is outdated; recommended version is \(recommendedClaimVersion)")
        }
    }

    private static func validateAssertions(
        _ manifest: ManifestDefinition,
        errors: inout [String],
        warnings: inout [String]
    ) {
        for assertion in manifest.assertions {
            let label = assertion.baseLabel
            if let replacement = deprecatedAssertionLabels[label] {
                warnings.append("Deprecated assertion label '\(label)': \(replacement)")
            }
            // Validate custom assertion label format (must use namespaced format)
            if case .custom(let customLabel, _) = assertion {
                if !customLabel.contains(".") {
                    warnings.append(
                        "Custom assertion label '\(customLabel)' should use namespaced format "
                        + "(e.g., 'com.example.custom' or vendor prefix)"
                    )
                }
            }
        }
    }

    private static func validateIngredients(
        _ manifest: ManifestDefinition,
        warnings: inout [String]
    ) {
        let parentIngredients = manifest.ingredients.filter { $0.relationship == .parentOf }
        if parentIngredients.count > 1 {
            warnings.append("Multiple parent ingredients found; only one parent ingredient is allowed")
        }
    }

}
