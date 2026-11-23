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
//  JSONSchema.swift
//

import Foundation

// MARK: - JSON values

/// A JSON value that keeps `true` apart from `1`, which `JSONSerialization`
/// does not do the same way on every platform.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Whole numbers go out as integers, so a model that decodes an Int
            // reads back what it wrote.
            if let integer = Int64(exactly: value) {
                try container.encode(integer)
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    init(json: String) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    /// The JSON a model encodes to.
    init(encoding value: some Encodable) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    func data() throws -> Data {
        try JSONEncoder().encode(self)
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { value } else { nil }
    }

    var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// The value as compact JSON, for failure messages.
    var text: String {
        (try? data().utf8Text) ?? "<unencodable>"
    }
}

// MARK: - Schemas

enum JSONSchemaError: Error, Equatable {
    case notAnObject(String)
    case noSuchDefinition(String)
    case noSuchMember(definition: String, member: String)
}

/// A JSON schema exported by c2pa-rs, with as much of JSON Schema 2020-12 as
/// those schemas use. A keyword outside that set is reported as a problem and
/// never skipped, so a schema cannot pass by asking for a check that is not made.
struct JSONSchema: Sendable {
    /// The name that selects the schema root in ``definition(_:)``.
    static let rootName = "#"

    let root: JSONValue

    init(_ root: JSONValue) {
        self.root = root
    }

    /// Loads a schema from the test resources, for example `Settings.schema.json`.
    init(named name: String) throws {
        let root = try JSONDecoder().decode(JSONValue.self, from: Fixtures.data(name))
        guard root.objectValue != nil else { throw JSONSchemaError.notAnObject(name) }
        self.root = root
    }

    private var definitions: [String: JSONValue] {
        root["$defs"]?.objectValue ?? [:]
    }

    var definitionNames: Set<String> {
        Set(definitions.keys)
    }

    /// The definition called `name`, or the schema root for ``rootName``.
    func definition(_ name: String) throws -> JSONValue {
        if name == Self.rootName { return root }
        guard let definition = definitions[name] else { throw JSONSchemaError.noSuchDefinition(name) }
        return definition
    }

    private func alternatives(in definition: JSONValue) -> [JSONValue] {
        (definition["oneOf"] ?? definition["anyOf"])?.arrayValue ?? []
    }

    /// What a definition made of alternatives offers: an object alternative as
    /// its member names in braces, a constant as its JSON text. Empty for a
    /// definition that is not made of alternatives.
    func alternatives(of name: String) throws -> [String] {
        alternatives(in: try definition(name)).map { alternative in
            if let properties = alternative["properties"]?.objectValue {
                "{\(properties.keys.sorted().joined(separator: ","))}"
            } else {
                (alternative["const"] ?? alternative).text
            }
        }
    }

    /// The schema of `member` in whichever alternative of the definition has it.
    func memberSchema(_ member: String, of name: String) throws -> JSONValue {
        let schemas = alternatives(in: try definition(name)).compactMap { $0["properties"]?[member] }
        guard let schema = schemas.first, schemas.count == 1 else {
            throw JSONSchemaError.noSuchMember(definition: name, member: member)
        }
        return schema
    }

    /// The definition with its descriptions and defaults removed, so two
    /// schemas can be compared for what they accept and nothing else.
    func structure(of name: String) throws -> JSONValue {
        Self.structure(try definition(name))
    }

    private static func structure(_ schema: JSONValue) -> JSONValue {
        switch schema {
        case .object(let members):
            var kept: [String: JSONValue] = [:]
            for (keyword, value) in members where !["description", "default", "title", "$comment"].contains(keyword) {
                if ["properties", "$defs"].contains(keyword), let named = value.objectValue {
                    // These map names to schemas: the names are not keywords.
                    kept[keyword] = .object(named.mapValues(structure))
                } else if ["const", "enum", "required"].contains(keyword) {
                    kept[keyword] = value
                } else {
                    kept[keyword] = structure(value)
                }
            }
            return .object(kept)
        case .array(let items):
            return .array(items.map(structure))
        default:
            return schema
        }
    }

    // MARK: Validation

    private static let annotations: Set<String> = [
        "$schema", "$defs", "$comment", "title", "description", "default", "format", "uniqueItems", "writeOnly"
    ]

    private static let checked: Set<String> = [
        "$ref", "type", "properties", "required", "additionalProperties", "items", "anyOf", "oneOf", "const",
        "enum", "minimum", "maximum"
    ]

    private static let referencePrefix = "#/$defs/"

    private func resolve(_ reference: JSONValue) -> JSONValue? {
        guard let text = reference.stringValue, text.hasPrefix(Self.referencePrefix) else { return nil }
        return definitions[String(text.dropFirst(Self.referencePrefix.count))]
    }

    /// Reads the whole schema for anything ``validate(_:against:)`` cannot
    /// check: a keyword it does not implement, or a reference to nothing.
    ///
    /// Validating a value does not find these reliably. Once one alternative
    /// of an `anyOf` matches, what the others ask for is never looked at.
    ///
    /// - Returns: One message per problem, each starting with where it is.
    func schemaProblems() -> [String] {
        schemaProblems(in: root, at: "#")
    }

    private func schemaProblems(in schema: JSONValue, at path: String) -> [String] {
        guard let keywords = schema.objectValue else { return [] }
        var problems: [String] = []
        for (keyword, argument) in keywords.sorted(by: { $0.key < $1.key }) {
            switch keyword {
            case "properties", "$defs":
                // These map names to schemas: the names are not keywords.
                for (name, named) in (argument.objectValue ?? [:]).sorted(by: { $0.key < $1.key }) {
                    problems += schemaProblems(in: named, at: "\(path)/\(keyword)/\(name)")
                }
            case "items", "additionalProperties":
                problems += schemaProblems(in: argument, at: "\(path)/\(keyword)")
            case "anyOf", "oneOf":
                for (index, alternative) in (argument.arrayValue ?? []).enumerated() {
                    problems += schemaProblems(in: alternative, at: "\(path)/\(keyword)/\(index)")
                }
            case "$ref":
                if resolve(argument) == nil {
                    problems.append("\(path): cannot resolve reference \(argument.stringValue ?? argument.text)")
                }
            default:
                if !Self.checked.contains(keyword) && !Self.annotations.contains(keyword) {
                    problems.append("\(path): schema keyword '\(keyword)' is not supported by this validator")
                }
            }
        }
        return problems
    }

    /// Checks `value` against `schema`, which may refer to this schema's definitions.
    ///
    /// - Returns: One message per violation, each starting with the JSON path
    ///   of the value it is about. Empty when the value is valid.
    func validate(_ value: JSONValue, against schema: JSONValue) -> [String] {
        validate(value, against: schema, at: "$")
    }

    private func validate(_ value: JSONValue, against schema: JSONValue, at path: String) -> [String] {
        switch schema {
        case .bool(true): return []
        case .bool(false): return ["\(path): no value is allowed here"]
        case .object(let keywords): return validate(value, keywords: keywords, at: path)
        default: return ["\(path): schema is neither an object nor a boolean: \(schema.text)"]
        }
    }

    private func validate(_ value: JSONValue, keywords: [String: JSONValue], at path: String) -> [String] {
        var problems: [String] = []
        let properties = keywords["properties"]?.objectValue ?? [:]

        for (keyword, argument) in keywords.sorted(by: { $0.key < $1.key }) where !Self.annotations.contains(keyword) {
            switch keyword {
            case "$ref":
                if let target = resolve(argument) {
                    problems += validate(value, against: target, at: path)
                } else {
                    problems.append("\(path): cannot resolve reference \(argument.stringValue ?? argument.text)")
                }
            case "type":
                let allowed = argument.arrayValue?.compactMap(\.stringValue) ?? [argument.stringValue ?? ""]
                if !allowed.contains(where: { Self.value(value, hasType: $0) }) {
                    problems.append("\(path): expected \(allowed.joined(separator: " or ")), found \(value.text)")
                }
            case "properties":
                guard let members = value.objectValue else { continue }
                for (name, member) in members.sorted(by: { $0.key < $1.key }) {
                    if let property = properties[name] {
                        problems += validate(member, against: property, at: "\(path).\(name)")
                    }
                }
            case "required":
                guard let members = value.objectValue else { continue }
                for name in argument.arrayValue?.compactMap(\.stringValue) ?? [] where members[name] == nil {
                    problems.append("\(path): required property '\(name)' is missing")
                }
            case "additionalProperties":
                guard let members = value.objectValue else { continue }
                for (name, member) in members.sorted(by: { $0.key < $1.key }) where properties[name] == nil {
                    if argument == .bool(false) {
                        problems.append("\(path): property '\(name)' is not allowed")
                    } else {
                        problems += validate(member, against: argument, at: "\(path).\(name)")
                    }
                }
            case "items":
                guard let elements = value.arrayValue else { continue }
                for (index, element) in elements.enumerated() {
                    problems += validate(element, against: argument, at: "\(path)[\(index)]")
                }
            case "anyOf", "oneOf":
                let alternatives = argument.arrayValue ?? []
                let matches = alternatives.filter { validate(value, against: $0, at: path).isEmpty }.count
                if keyword == "anyOf" ? matches == 0 : matches != 1 {
                    problems.append(
                        "\(path): \(value.text) matches \(matches) of the \(alternatives.count) \(keyword) alternatives")
                }
            case "const":
                if value != argument {
                    problems.append("\(path): expected \(argument.text), found \(value.text)")
                }
            case "enum":
                if argument.arrayValue?.contains(value) != true {
                    problems.append("\(path): \(value.text) is not one of \(argument.text)")
                }
            case "minimum", "maximum":
                guard case .number(let number) = value, case .number(let bound) = argument else { continue }
                if keyword == "minimum" ? number < bound : number > bound {
                    problems.append("\(path): \(value.text) is outside the \(keyword) \(argument.text)")
                }
            default:
                problems.append("\(path): schema keyword '\(keyword)' is not supported by this validator")
            }
        }
        return problems
    }

    private static func value(_ value: JSONValue, hasType type: String) -> Bool {
        switch (type, value) {
        case ("null", .null), ("boolean", .bool), ("number", .number), ("string", .string),
            ("array", .array), ("object", .object):
            true
        case ("integer", .number(let number)):
            number.rounded() == number
        default:
            false
        }
    }
}
