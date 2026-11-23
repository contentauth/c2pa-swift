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
//  JSONSchemaTests.swift
//

import C2PA
import Foundation
import Testing

/// The schema conformance suites are only as good as the validator and the
/// comparisons under them, so both are checked here against small schemas
/// whose right answers are obvious.
@Suite struct JSONSchemaTests {

    private func schema(_ json: String) throws -> JSONSchema {
        JSONSchema(try JSONValue(json: json))
    }

    private func problems(_ value: String, against schema: String) throws -> [String] {
        let schema = try self.schema(schema)
        return schema.validate(try JSONValue(json: value), against: schema.root)
    }

    // MARK: - Types

    @Test(arguments: [
        ("\"text\"", "string"), ("1", "integer"), ("1", "number"), ("1.5", "number"),
        ("true", "boolean"), ("null", "null"), ("[]", "array"), ("{}", "object")
    ])
    func typeAccepts(value: String, type: String) throws {
        #expect(try problems(value, against: #"{"type": "\#(type)"}"#).isEmpty)
    }

    @Test(arguments: [
        ("1.5", "integer"), ("true", "number"), ("true", "integer"), ("1", "boolean"),
        ("1", "string"), ("\"1\"", "number"), ("null", "string"), ("{}", "array"), ("[]", "object")
    ])
    func typeRejects(value: String, type: String) throws {
        let found = try problems(value, against: #"{"type": "\#(type)"}"#)
        #expect(found.count == 1, "\(found)")
    }

    @Test func typeListAllowsNull() throws {
        let nullable = #"{"type": ["string", "null"]}"#
        #expect(try problems("null", against: nullable).isEmpty)
        #expect(try problems("\"text\"", against: nullable).isEmpty)
        #expect(try problems("1", against: nullable).count == 1)
    }

    // MARK: - Objects and arrays

    @Test func requiredNamesTheMissingKey() throws {
        let found = try problems(
            #"{"name": "n"}"#,
            against: #"{"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name", "format"]}"#)
        #expect(found.count == 1)
        #expect(found.first?.contains("format") == true, "\(found)")
    }

    @Test func propertiesAreValidatedWithTheirPath() throws {
        let found = try problems(
            #"{"outer": {"inner": 1}}"#,
            against: #"{"properties": {"outer": {"properties": {"inner": {"type": "string"}}}}}"#)
        #expect(found.count == 1)
        #expect(found.first?.hasPrefix("$.outer.inner") == true, "\(found)")
    }

    @Test func additionalProperties() throws {
        let value = #"{"known": 1, "extra": "x"}"#
        let known = #""properties": {"known": {"type": "integer"}}"#
        #expect(try problems(value, against: "{\(known)}").isEmpty)
        #expect(try problems(value, against: "{\(known), \"additionalProperties\": true}").isEmpty)
        #expect(try problems(value, against: "{\(known), \"additionalProperties\": {\"type\": \"string\"}}").isEmpty)

        let closed = try problems(value, against: "{\(known), \"additionalProperties\": false}")
        #expect(closed.count == 1)
        #expect(closed.first?.contains("extra") == true, "\(closed)")
        #expect(try problems(value, against: "{\(known), \"additionalProperties\": {\"type\": \"integer\"}}").count == 1)
    }

    @Test func itemsAreValidatedWithTheirIndex() throws {
        let found = try problems(#"["a", 2]"#, against: #"{"type": "array", "items": {"type": "string"}}"#)
        #expect(found.count == 1)
        #expect(found.first?.hasPrefix("$[1]") == true, "\(found)")
    }

    // MARK: - References and combinators

    @Test func referencesResolveIntoDefinitions() throws {
        let schema = ##"{"$ref": "#/$defs/Name", "$defs": {"Name": {"type": "string"}}}"##
        #expect(try problems("\"n\"", against: schema).isEmpty)
        #expect(try problems("1", against: schema).count == 1)
    }

    @Test func unresolvableReferenceIsReported() throws {
        let found = try problems("1", against: ##"{"$ref": "#/$defs/Missing", "$defs": {}}"##)
        #expect(found.count == 1)
        #expect(found.first?.contains("#/$defs/Missing") == true, "\(found)")
    }

    @Test func anyOfNeedsOneMatch() throws {
        let schema = #"{"anyOf": [{"type": "string"}, {"type": "null"}]}"#
        #expect(try problems("null", against: schema).isEmpty)
        #expect(try problems("1", against: schema).count == 1)
    }

    @Test func oneOfNeedsExactlyOneMatch() throws {
        let schema = #"{"oneOf": [{"type": "number"}, {"type": "integer"}, {"type": "string"}]}"#
        #expect(try problems("1.5", against: schema).isEmpty)
        #expect(try problems("1", against: schema).count == 1)
        #expect(try problems("true", against: schema).count == 1)
    }

    @Test func constAndEnum() throws {
        #expect(try problems("\"edit\"", against: #"{"const": "edit"}"#).isEmpty)
        #expect(try problems("\"Edit\"", against: #"{"const": "edit"}"#).count == 1)
        #expect(try problems("\"tsa\"", against: #"{"enum": ["manifest", "tsa"]}"#).isEmpty)
        #expect(try problems("\"TSA\"", against: #"{"enum": ["manifest", "tsa"]}"#).count == 1)
    }

    @Test func minimumAndMaximum() throws {
        let byte = #"{"type": "integer", "minimum": 0, "maximum": 255}"#
        #expect(try problems("0", against: byte).isEmpty)
        #expect(try problems("255", against: byte).isEmpty)
        #expect(try problems("-1", against: byte).count == 1)
        #expect(try problems("256", against: byte).count == 1)
    }

    @Test func booleanSchemas() throws {
        #expect(try problems("1", against: #"{"properties": {"a": true}}"#).isEmpty)
        #expect(try problems(#"{"a": 1}"#, against: #"{"properties": {"a": true}}"#).isEmpty)
        #expect(try problems(#"{"a": 1}"#, against: #"{"properties": {"a": false}}"#).count == 1)
    }

    // MARK: - Keywords

    @Test func annotationsAreIgnored() throws {
        let schema = #"""
            {"$schema": "https://json-schema.org/draft/2020-12/schema", "$comment": "c", "$defs": {},
             "title": "T", "description": "d", "default": 1, "format": "uint8", "uniqueItems": true,
             "writeOnly": true, "type": "string"}
            """#
        #expect(try problems("\"text\"", against: schema).isEmpty)
    }

    /// A keyword the validator does not implement must fail loudly: skipping it
    /// would let a future schema pass while checking less than it says.
    @Test func unknownKeywordIsReported() throws {
        let found = try problems("\"text\"", against: #"{"type": "string", "patternProperties": {}}"#)
        #expect(found.count == 1)
        #expect(found.first?.contains("patternProperties") == true, "\(found)")
    }

    /// Validation stops looking inside an alternative once another one matches,
    /// so a keyword there has to be found by reading the schema itself.
    @Test func unsupportedKeywordInsideAnAlternativeIsReported() throws {
        let schema = try self.schema(#"""
            {"$defs": {"Open": {"anyOf": [{"const": "a"}, {"type": "string", "pattern": "^b"}]},
                       "Nested": {"properties": {"list": {"items": {"oneOf": [{"minLength": 1}]}}}},
                       "Dangling": {"additionalProperties": {"$ref": "#/$defs/Missing"}}}}
            """#)
        #expect(schema.validate(.string("a"), against: try schema.definition("Open")).isEmpty)

        let found = schema.schemaProblems()
        #expect(found.count == 3, "\(found)")
        #expect(found.contains { $0.contains("pattern") && $0.contains("Open") }, "\(found)")
        #expect(found.contains { $0.contains("minLength") && $0.contains("Nested") }, "\(found)")
        #expect(found.contains { $0.contains("#/$defs/Missing") && $0.contains("Dangling") }, "\(found)")
    }

    /// Property and definition names are not keywords, whatever they are called.
    @Test func namesThatLookLikeKeywordsAreNotReported() throws {
        let schema = try self.schema(#"""
            {"properties": {"pattern": {"type": "string"}, "default": {"type": "string"}},
             "required": ["pattern"], "default": {"pattern": {"minLength": 1}},
             "$defs": {"minLength": {"enum": [{"pattern": 1}], "const": {"pattern": 1}}}}
            """#)
        #expect(schema.schemaProblems().isEmpty, "\(schema.schemaProblems())")
    }

    // MARK: - Conformance comparisons

    private struct Sample: Codable, Equatable {
        var name: String
        var count: Int?
        var note: String?
    }

    private static let sampleSchema = #"""
        {"$defs": {"Sample": {"type": "object", "required": ["name"], "properties": {
            "name": {"type": "string"}, "count": {"type": ["integer", "null"]}, "note": {"type": ["string", "null"]}}}}}
        """#

    private func conformance(
        _ definition: String = "Sample", schema: String = sampleSchema,
        unmodelled: [String: String] = [:], alsoRequired: Set<String> = [],
        sample: @escaping @Sendable () -> some Codable & Equatable
    ) throws -> [String] {
        conformanceProblems(
            ModelCase(definition, sample: sample, unmodelled: unmodelled, alsoRequired: alsoRequired),
            in: try self.schema(schema))
    }

    @Test func conformingModelHasNoProblems() throws {
        #expect(try conformance { Sample(name: "n", count: 1, note: "x") }.isEmpty)
    }

    @Test func propertyTheSampleLeavesOutIsReported() throws {
        let found = try conformance { Sample(name: "n", count: 1, note: nil) }
        #expect(found.count == 1)
        #expect(found.first?.contains("note") == true, "\(found)")
    }

    @Test func unmodelledPropertyIsExcused() throws {
        #expect(try conformance(unmodelled: ["note": "not modelled yet"]) { Sample(name: "n", count: 1) }.isEmpty)
    }

    @Test func staleUnmodelledEntryIsReported() throws {
        let found = try conformance(unmodelled: ["gone": "no longer in the schema"]) {
            Sample(name: "n", count: 1, note: "x")
        }
        #expect(found.count == 1)
        #expect(found.first?.contains("gone") == true, "\(found)")
    }

    @Test func unmodelledEntryTheModelNowEncodesIsReported() throws {
        let found = try conformance(unmodelled: ["note": "not modelled yet"]) {
            Sample(name: "n", count: 1, note: "x")
        }
        #expect(found.count == 1)
        #expect(found.first?.contains("note") == true, "\(found)")
    }

    private struct Extra: Codable, Equatable {
        var name: String
        var count: Int?
        var note: String?
        var surplus: String?
    }

    @Test func keyTheSchemaLacksIsReported() throws {
        let found = try conformance { Extra(name: "n", count: 1, note: "x", surplus: "s") }
        #expect(found.count == 1)
        #expect(found.first?.contains("surplus") == true, "\(found)")
    }

    /// A definition that allows further members says nothing about a key the
    /// model itself writes: samples carry none of the free-form ones.
    @Test func keyTheSchemaLacksIsReportedOnAnOpenDefinition() throws {
        let open = Self.sampleSchema.replacingOccurrences(
            of: #""type": "object","#, with: #""type": "object", "additionalProperties": true,"#)
        let found = try conformance(schema: open) { Extra(name: "n", count: 1, note: "x", surplus: "s") }
        #expect(found.count == 1)
        #expect(found.first?.contains("surplus") == true, "\(found)")
    }

    private static let variantSchema = #"""
        {"$defs": {"Variants": {"oneOf": [
            {"type": "object", "required": ["first"], "properties": {"first": {"type": "object", "required": ["name"],
                "properties": {"name": {"type": "string"}, "count": {"type": ["integer", "null"]},
                               "note": {"type": ["string", "null"]}}}}},
            {"type": "object", "required": ["second"], "properties": {"second": {"type": "object"}}}]}}}
        """#

    private func memberConformance(
        _ member: String, sample: @escaping @Sendable () -> some Codable & Equatable
    ) throws -> [String] {
        conformanceProblems(
            ModelCase("Variants", member: member, sample: sample), in: try self.schema(Self.variantSchema))
    }

    /// A definition made of alternatives, each an object with one member,
    /// still has key sets: those of the members.
    @Test func memberOfAnAlternativeIsCompared() throws {
        #expect(try memberConformance("first") { Sample(name: "n", count: 1, note: "x") }.isEmpty)

        let missing = try memberConformance("first") { Sample(name: "n", count: 1, note: nil) }
        #expect(missing.count == 1)
        #expect(missing.first?.contains("note") == true, "\(missing)")

        let surplus = try memberConformance("first") { Extra(name: "n", count: 1, note: "x", surplus: "s") }
        #expect(surplus.count == 1)
        #expect(surplus.first?.contains("surplus") == true, "\(surplus)")

        let unknown = try memberConformance("third") { Sample(name: "n", count: 1, note: "x") }
        #expect(unknown.count == 1)
        #expect(unknown.first?.contains("third") == true, "\(unknown)")
    }

    @Test func alternativesAreListed() throws {
        let schema = try self.schema(##"""
            {"$defs": {"Variants": {"oneOf": [
                {"type": "object", "properties": {"create": {"type": "string"}}}, {"const": "edit"}, {"const": "update"}]},
              "Plain": {"type": "string"}}}
            """##)
        #expect(try schema.alternatives(of: "Variants") == ["{create}", "\"edit\"", "\"update\""])
        #expect(try schema.alternatives(of: "Plain").isEmpty)
    }

    private struct Strict: Codable, Equatable {
        var name: String
        var count: Int
        var note: String?
    }

    @Test func modelStricterThanTheSchemaIsReported() throws {
        let found = try conformance { Strict(name: "n", count: 1, note: "x") }
        #expect(found.count == 1)
        #expect(found.first?.contains("count") == true, "\(found)")
    }

    @Test func alsoRequiredKeepsAMemberTheSchemaUnderReports() throws {
        #expect(try conformance(alsoRequired: ["count"]) { Strict(name: "n", count: 1, note: "x") }.isEmpty)
    }

    private struct WrongType: Codable, Equatable {
        var name: String
        var count: String?
        var note: String?
    }

    @Test func valueOfTheWrongTypeIsReported() throws {
        let found = try conformance { WrongType(name: "n", count: "1", note: "x") }
        #expect(found.count == 1)
        #expect(found.first?.hasPrefix("$.count") == true, "\(found)")
    }

    private struct Lossy: Codable, Equatable {
        var name: String
        var count: Int?
        var note: String?

        init(name: String, count: Int?, note: String?) {
            self.name = name
            self.count = count
            self.note = note
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            count = try container.decodeIfPresent(Int.self, forKey: .count)
            note = nil
        }
    }

    @Test func valueLostInARoundTripIsReported() throws {
        let found = try conformance { Lossy(name: "n", count: 1, note: "x") }
        #expect(found.count == 1)
        #expect(found.first?.contains("round trip") == true, "\(found)")
    }

    // MARK: - Enumerations

    private enum Kind: String, CaseIterable {
        case manifest, tsa
    }

    @Test func enumerationFormsAreRead() throws {
        let schema = try self.schema(#"""
            {"$defs": {
                "Listed": {"type": "string", "enum": ["manifest", "tsa"]},
                "Variants": {"oneOf": [{"type": "string", "const": "manifest"}, {"type": "string", "const": "tsa"}]},
                "Open": {"anyOf": [{"type": "string", "const": "manifest"}, {"const": "tsa"}, {"type": "string"}]},
                "Wider": {"enum": ["manifest", "tsa", "cawg"]},
                "Narrower": {"enum": ["manifest"]}}}
            """#)
        #expect(enumerationProblems(Kind.self, matches: "Listed", in: schema).isEmpty)
        #expect(enumerationProblems(Kind.self, matches: "Variants", in: schema).isEmpty)
        #expect(enumerationProblems(Kind.self, matches: "Open", in: schema, open: true).isEmpty)

        // A schema that allows any string is not a closed enumeration, and the reverse.
        #expect(enumerationProblems(Kind.self, matches: "Open", in: schema).count == 1)
        #expect(enumerationProblems(Kind.self, matches: "Listed", in: schema, open: true).count == 1)

        let wider = enumerationProblems(Kind.self, matches: "Wider", in: schema)
        #expect(wider.count == 1)
        #expect(wider.first?.contains("cawg") == true, "\(wider)")
        let narrower = enumerationProblems(Kind.self, matches: "Narrower", in: schema)
        #expect(narrower.count == 1)
        #expect(narrower.first?.contains("tsa") == true, "\(narrower)")
    }

    // MARK: - Definition coverage

    @Test func everyDefinitionMustBeClassified() throws {
        let schema = try self.schema(#"{"$defs": {"A": {}, "B": {}, "C": {}}}"#)
        #expect(classificationProblems(in: schema, mapped: ["A", "B"], unmodelled: ["C": "reason"]).isEmpty)

        let unclassified = classificationProblems(in: schema, mapped: ["A"], unmodelled: ["C": "reason"])
        #expect(unclassified.count == 1)
        #expect(unclassified.first?.contains("B") == true, "\(unclassified)")

        let stale = classificationProblems(in: schema, mapped: ["A", "B", "Gone"], unmodelled: ["C": "reason"])
        #expect(stale.count == 1)
        #expect(stale.first?.contains("Gone") == true, "\(stale)")

        let both = classificationProblems(in: schema, mapped: ["A", "B", "C"], unmodelled: ["C": "reason"])
        #expect(both.count == 1)
        #expect(both.first?.contains("C") == true, "\(both)")
    }

    // MARK: - Snapshot

    @Test(arguments: ["Builder", "ManifestDefinition", "Reader", "Settings"])
    func snapshotLoads(name: String) throws {
        let schema = try JSONSchema(named: "\(name).schema.json")
        #expect(schema.root["title"] == .string(name))
        #expect(schema.root["$comment"]?.stringValue?.hasPrefix("Generated from c2pa-rs v") == true)
        #expect(!schema.definitionNames.isEmpty)
        #expect(throws: JSONSchemaError.self) { try schema.definition("NoSuchDefinition") }
    }

    /// Checked on the schemas themselves, not through samples: see
    /// unsupportedKeywordInsideAnAlternativeIsReported.
    @Test(arguments: ["Builder", "ManifestDefinition", "Reader", "Settings"])
    func snapshotUsesOnlySupportedKeywords(name: String) throws {
        let found = try JSONSchema(named: "\(name).schema.json").schemaProblems()
        #expect(found.isEmpty, "\(found)")
    }

    /// c2pa-rs writes a new random instance_id default on every export. The
    /// snapshot replaces it, so regenerating an unchanged schema changes nothing.
    @Test(arguments: ["Builder", "ManifestDefinition", "Reader"])
    func snapshotHasNoGeneratedInstanceID(name: String) throws {
        let text = try Fixtures.text("\(name).schema.json")
        let defaults = text.components(separatedBy: "\"xmp.iid:").dropFirst().map { $0.prefix(36) }
        #expect(!defaults.isEmpty)
        #expect(defaults.allSatisfy { $0 == "00000000-0000-0000-0000-000000000000" }, "\(defaults)")
    }
}
