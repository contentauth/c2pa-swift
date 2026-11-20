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
//  Intent.swift
//

import C2PAC
import Foundation

/// Specifies what kind of manifest to create when building a C2PA claim.
///
/// The builder intent determines how the manifest is structured and what
/// assertions are automatically added.
///
/// ## Topics
///
/// ### Intent Types
/// - ``create(_:)``
/// - ``edit``
/// - ``update``
///
/// - SeeAlso: ``Builder/setIntent(_:)``
public enum BuilderIntent: Sendable {
    /// A new digital creation with the specified digital source type.
    ///
    /// Use this intent for assets that are being created for the first time,
    /// such as a freshly captured photo or a newly generated image.
    ///
    /// The manifest must not have a parent ingredient. A `c2pa.created` action
    /// will be added if not provided.
    ///
    /// - Parameter digitalSourceType: The type of digital source used to create this asset.
    case create(DigitalSourceType)

    /// An edit of a pre-existing parent asset.
    ///
    /// Use this intent when modifying an existing asset, such as cropping a photo
    /// or applying filters to an image.
    ///
    /// The manifest must have a parent ingredient. A parent ingredient will be
    /// generated from the source stream if not otherwise provided. A `c2pa.opened`
    /// action will be tied to the parent ingredient.
    case edit

    /// A restricted version of edit for non-editorial changes.
    ///
    /// Use this intent for metadata-only updates that don't modify the hashed
    /// content of the asset, such as updating EXIF data or adding descriptions.
    ///
    /// There must be only one ingredient, as a parent. No changes can be made
    /// to the hashed content of the parent.
    case update

    internal func toCIntent() -> (C2paBuilderIntent, C2paDigitalSourceType) {
        switch self {
        case .create(let sourceType):
            (Create, sourceType.toCType())
        case .edit:
            (Edit, Empty)
        case .update:
            (Update, Empty)
        }
    }
}

// MARK: - DigitalSourceType C API Conversion

extension DigitalSourceType {
    /// Converts this digital source type to the corresponding C API type.
    internal func toCType() -> C2paDigitalSourceType {
        switch self {
        case .algorithmicallyEnhanced:
            AlgorithmicallyEnhanced
        case .algorithmicMedia:
            AlgorithmicMedia
        case .composite:
            Composite
        case .compositeCapture:
            CompositeCapture
        case .compositeSynthetic:
            CompositeSynthetic
        case .compositeWithTrainedAlgorithmicMedia:
            CompositeWithTrainedAlgorithmicMedia
        case .dataDrivenMedia:
            DataDrivenMedia
        case .digitalCreation:
            DigitalCreation
        case .digitalCapture:
            DigitalCapture
        case .humanEdits:
            HumanEdits
        case .negativeFilm:
            NegativeFilm
        case .positiveFilm:
            PositiveFilm
        case .print:
            Print
        case .screenCapture:
            ScreenCapture
        case .trainedAlgorithmicMedia:
            TrainedAlgorithmicMedia
        case .virtualRecording:
            VirtualRecording
        }
    }
}
