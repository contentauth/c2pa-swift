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
//  Shape.swift
//

import Foundation

/// A spatial range representing rectangle, circle, or a polygon.
/// - SeeAlso: [Shape Reference](https://opensource.contentauthenticity.org/docs/manifest/json-ref/manifest-definition-schema/#shape)
public struct Shape: Codable, Equatable, Sendable {

    /// The type of shape.
    public var type: ShapeType

    /// The origin of the coordinate in the shape.
    public var origin: Coordinate

    /// The width for rectangles or diameter for circles.
    /// This field can be ignored for polygons.
    public var width: Double?

    /// The height of a rectnagle.
    /// This field can be ignored for circles and polygons.
    public var height: Double?

    /// The vertices of the polygon.
    /// This field can be ignored for rectangles and circles.
    public var vertices: [Coordinate]?

    /// If the range is inside the shape.
    /// A range is inside when this is absent.
    public var inside: Bool?

    /// The type of unit for the shape range.
    public var unit: UnitType

    /// - Parameters:
    ///   - type: The type of shape.
    ///   - origin: The origin of the coordinate in the shape.
    ///   - width: The width for rectangles or diameter for circles. This field can be ignored for polygons.
    ///   - height: The height of a rectnagle. This field can be ignored for circles and polygons.
    ///   - vertices: The vertices of the polygon. This field can be ignored for rectangles and circles.
    ///   - inside: If the range is inside the shape. A range is inside when this is absent.
    ///   - unit: The type of unit for the shape range.
    public init(
        type: ShapeType,
        origin: Coordinate,
        width: Double? = nil,
        height: Double? = nil,
        vertices: [Coordinate]? = nil,
        inside: Bool? = nil,
        unit: UnitType
    ) {
        self.type = type
        self.origin = origin
        self.width = width
        self.height = height
        self.vertices = vertices
        self.inside = inside
        self.unit = unit
    }
}
