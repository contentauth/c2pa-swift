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
//  SchemaConformance.swift
//

import Foundation
import Testing

/// A Swift model paired with the c2pa-rs schema definition it stands for.
struct ModelCase: CustomTestStringConvertible, Sendable {
    /// A name in the schema's `$defs`, or ``JSONSchema/rootName`` for its root.
    let definition: String
    /// For a definition made of alternatives that are each an object with one
    /// member: the member whose schema the model stands for.
    let member: String?
    let testDescription: String
    /// Schema properties the model deliberately leaves out, each with the reason.
    let unmodelled: [String: String]
    /// Properties c2pa-rs requires although the schema does not say so.
    let alsoRequired: Set<String>

    fileprivate let encoded: @Sendable () throws -> JSONValue
    /// Decodes the model from `data`; throws when it cannot.
    fileprivate let decode: @Sendable (Data) throws -> Void
    /// Describes what a decode of the encoded sample lost, or nil when nothing.
    fileprivate let roundTripLoss: @Sendable () throws -> String?

    /// - Parameters:
    ///   - definition: The schema definition the model stands for.
    ///   - member: The member of an alternative that the model stands for,
    ///     when the definition describes it inline. See ``member``.
    ///   - variant: Tells apart several cases for one definition.
    ///   - sample: A model with every property set, so each key is encoded.
    ///   - unmodelled: Schema properties the model leaves out, with reasons.
    ///   - alsoRequired: Properties c2pa-rs requires beyond the schema's list.
    init<Model: Codable & Equatable>(
        _ definition: String,
        member: String? = nil,
        variant: String? = nil,
        sample: @escaping @Sendable () throws -> Model,
        unmodelled: [String: String] = [:],
        alsoRequired: Set<String> = []
    ) {
        self.definition = definition
        self.member = member
        self.testDescription =
            "\(definition)\(member.map { ".\($0)" } ?? "") as \(Model.self)" + (variant.map { " (\($0))" } ?? "")
        self.unmodelled = unmodelled
        self.alsoRequired = alsoRequired
        self.encoded = { try JSONValue(encoding: sample()) }
        self.decode = { _ = try JSONDecoder().decode(Model.self, from: $0) }
        self.roundTripLoss = {
            let original = try sample()
            let decoded = try JSONDecoder().decode(Model.self, from: JSONEncoder().encode(original))
            return decoded == original ? nil : "\(original) became \(decoded)"
        }
    }
}

// MARK: - Comparisons

/// Compares a model with its schema definition four ways: the encoded sample
/// is valid against the definition, it encodes every property the definition
/// has, the model decodes from the required properties alone, and a round
/// trip loses nothing.
///
/// - Returns: One message per mismatch. Empty when the model conforms.
func conformanceProblems(_ modelCase: ModelCase, in schema: JSONSchema) -> [String] {
    let definition: JSONValue
    let encoded: JSONValue
    do {
        definition =
            try modelCase.member.map { try schema.memberSchema($0, of: modelCase.definition) }
            ?? schema.definition(modelCase.definition)
        encoded = try modelCase.encoded()
    } catch {
        return ["\(modelCase.testDescription): \(error)"]
    }

    var problems = schema.validate(encoded, against: definition)

    // A definition made of alternatives has no key set of its own to compare.
    // Where its alternatives describe objects inline, a case names the member.
    if let properties = definition["properties"]?.objectValue, let members = encoded.objectValue {
        problems += coverageProblems(modelCase, properties: Set(properties.keys), members: Set(members.keys))

        let required = Set(definition["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
            .union(modelCase.alsoRequired)
        let minimal = JSONValue.object(members.filter { required.contains($0.key) })
        do {
            try modelCase.decode(try minimal.data())
        } catch {
            problems.append(
                "does not decode from the required properties alone \(required.sorted()): \(error)")
        }
    }

    do {
        if let loss = try modelCase.roundTripLoss() {
            problems.append("round trip changed the value: \(loss)")
        }
    } catch {
        problems.append("round trip failed: \(error)")
    }
    return problems
}

private func coverageProblems(_ modelCase: ModelCase, properties: Set<String>, members: Set<String>) -> [String] {
    var problems: [String] = []
    let excused = Set(modelCase.unmodelled.keys)
    for name in properties.subtracting(members).subtracting(excused).sorted() {
        problems.append(
            "schema property '\(name)' is not encoded: the model lacks it or the sample leaves it unset")
    }
    // Reported even where the definition allows further members: a sample
    // sets only what the model names, so a key outside the definition is one
    // the model writes and c2pa-rs no longer reads as such.
    for name in members.subtracting(properties).sorted() {
        problems.append("encoded key '\(name)' is not a property of the schema definition")
    }
    for name in excused.subtracting(properties).sorted() {
        problems.append("'\(name)' is listed as unmodelled but the schema definition has no such property")
    }
    for name in excused.intersection(members).sorted() {
        problems.append("'\(name)' is listed as unmodelled but the model encodes it")
    }
    return problems
}

/// Compares an enumeration's raw values with the strings a schema definition lists.
///
/// - Parameter open: Whether the definition also accepts any other string. A
///   closed definition must not, and an open one must.
/// - Returns: One message per mismatch. Empty when they agree.
func enumerationProblems<Enumeration: RawRepresentable & CaseIterable>(
    _ type: Enumeration.Type, matches definition: String, in schema: JSONSchema, open: Bool = false
) -> [String] where Enumeration.RawValue == String {
    guard let schemaDefinition = try? schema.definition(definition) else {
        return ["the schema has no definition '\(definition)'"]
    }
    var listed: Set<String> = []
    var acceptsAnyString = false
    listed.formUnion(schemaDefinition["enum"]?.arrayValue?.compactMap(\.stringValue) ?? [])
    for alternative in (schemaDefinition["oneOf"] ?? schemaDefinition["anyOf"])?.arrayValue ?? [] {
        if let value = alternative["const"]?.stringValue {
            listed.insert(value)
        } else if let values = alternative["enum"]?.arrayValue {
            listed.formUnion(values.compactMap(\.stringValue))
        } else if alternative["type"] == .string("string") {
            acceptsAnyString = true
        }
    }

    var problems: [String] = []
    let cases = Set(type.allCases.map(\.rawValue))
    for value in listed.subtracting(cases).sorted() {
        problems.append("\(type) has no case for the schema value '\(value)'")
    }
    for value in cases.subtracting(listed).sorted() {
        problems.append("\(type) has the value '\(value)', which the schema definition '\(definition)' does not list")
    }
    if acceptsAnyString != open {
        problems.append(
            open
                ? "'\(definition)' was expected to accept any string but lists a closed set"
                : "'\(definition)' accepts any string, so \(type) cannot be treated as closed")
    }
    return problems
}

/// Checks that every definition in a schema is accounted for, so a definition
/// c2pa-rs adds later cannot go unnoticed.
///
/// - Parameters:
///   - mapped: Definitions that a model or enumeration case covers.
///   - unmodelled: Definitions deliberately left without a Swift type, with reasons.
/// - Returns: One message per definition that is unclassified, classified
///   twice, or classified but gone from the schema.
func classificationProblems(in schema: JSONSchema, mapped: Set<String>, unmodelled: [String: String]) -> [String] {
    let excused = Set(unmodelled.keys)
    let names = schema.definitionNames
    var problems: [String] = []
    for name in names.subtracting(mapped).subtracting(excused).sorted() {
        problems.append("schema definition '\(name)' is neither mapped to a model nor listed as unmodelled")
    }
    for name in mapped.union(excused).subtracting(names).sorted() {
        problems.append("'\(name)' is classified but the schema has no such definition")
    }
    for name in mapped.intersection(excused).sorted() {
        problems.append("'\(name)' is both mapped and listed as unmodelled")
    }
    return problems
}

// MARK: - Expectations

private func record(_ problems: [String], about subject: String, _ sourceLocation: SourceLocation) {
    for problem in problems {
        Issue.record("\(subject): \(problem)", sourceLocation: sourceLocation)
    }
}

func expectConformance(
    _ modelCase: ModelCase, in schema: JSONSchema, sourceLocation: SourceLocation = #_sourceLocation
) {
    record(conformanceProblems(modelCase, in: schema), about: modelCase.testDescription, sourceLocation)
}

func expectEnumeration<Enumeration: RawRepresentable & CaseIterable>(
    _ type: Enumeration.Type, matches definition: String, in schema: JSONSchema, open: Bool = false,
    sourceLocation: SourceLocation = #_sourceLocation
) where Enumeration.RawValue == String {
    record(
        enumerationProblems(type, matches: definition, in: schema, open: open), about: "\(type)", sourceLocation)
}

func expectEveryDefinitionClassified(
    in schema: JSONSchema, mapped: Set<String>, unmodelled: [String: String],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    record(
        classificationProblems(in: schema, mapped: mapped, unmodelled: unmodelled),
        about: "schema definitions", sourceLocation)
}
