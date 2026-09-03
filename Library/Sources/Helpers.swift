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
//  Helpers.swift
//

import C2PAC
import Foundation
import UniformTypeIdentifiers

@inline(__always)
func stringFromC(_ p: UnsafeMutablePointer<CChar>?) throws -> String {
    guard let p else { throw C2PAError.api(lastC2PAError()) }
    defer { _ = c2pa_free(p) }
    guard let s = String(validatingCString: p) else { throw C2PAError.utf8 }
    return s
}

@inline(__always)
func lastC2PAError() -> String {
    guard let p = c2pa_error() else { return "Unknown C2PA error" }
    defer { _ = c2pa_free(p) }
    return String(cString: p)
}

/// Records a failure message for the native layer to read back.
///
/// The C layer parses `"ErrorType: message"`, splitting on the first `": "` only, and maps
/// an unrecognised type to `Other`. Always pass a valid type prefix: an unprefixed message
/// that happens to contain `": "` would have its first segment read as a type tag.
@inline(__always)
func setLastC2PAError(_ message: String) {
    _ = message.withCString { c2pa_error_set_last($0) }
}

@inline(__always)
func guardNotNull<T>(_ p: UnsafeMutablePointer<T>?) throws -> UnsafeMutablePointer<T> {
    if let p { return p }
    throw C2PAError.api(lastC2PAError())
}

@inline(__always)
@discardableResult
func guardNonNegative(_ v: Int64) throws -> Int64 {
    if v < 0 { throw C2PAError.api(lastC2PAError()) }
    return v
}

// Borrow 4 strings for one call (alg, cert, key, tsa)
@inline(__always)
func withSignerInfo<R>(
    algorithm: String, cert: String, key: String, tsa: URL?,
    _ body: (
        UnsafePointer<CChar>, UnsafePointer<CChar>,
        UnsafePointer<CChar>, UnsafePointer<CChar>?
    ) throws -> R
) rethrows -> R {
    try algorithm.withCString { algPtr in
        try cert.withCString { certPtr in
            try key.withCString { keyPtr in
                if let tsa = tsa?.absoluteString {
                    return try tsa.withCString { tsaPtr in
                        try body(algPtr, certPtr, keyPtr, tsaPtr)
                    }
                } else {
                    return try body(algPtr, certPtr, keyPtr, nil)
                }
            }
        }
    }
}

// Borrow optional `String` -> `char*` (NULL if nil)
@inline(__always)
func withOptionalCString<R>(
    _ s: String?, _ body: (UnsafePointer<CChar>?) throws -> R
) rethrows -> R {
    if let s {
        return try s.withCString(body)
    } else {
        return try body(nil)
    }
}

// Cast opaque pointer to requested `StreamContext*`
@inline(__always)
func asStreamCtx(_ p: UnsafeMutableRawPointer) -> UnsafeMutablePointer<StreamContext> {
    UnsafeMutablePointer<StreamContext>(OpaquePointer(p))
}

/// Converts a C string array (with its element count) to `[String]`, then frees the
/// native array with `c2pa_free_string_array`. Returns `[]` for a nil array.
func stringArrayFromC(_ ptr: UnsafePointer<UnsafePointer<CChar>?>?, count: Int) -> [String] {
    guard let ptr, count > 0 else { return [] }
    var result: [String] = []
    result.reserveCapacity(count)
    for i in 0..<count {
        if let cStr = ptr[i] { result.append(String(cString: cStr)) }
    }
    c2pa_free_string_array(ptr, UInt(count))
    return result
}

/// Builds `Data` from the `(int64 length, out **bytes)` pattern used by the embeddable
/// FFI calls, freeing the native buffer with `c2pa_free`. `length` is the guarded,
/// non-negative result; `pointer` is the out-parameter the call populated.
func manifestData(length: Int64, pointer: UnsafePointer<UInt8>?) -> Data {
    guard let pointer else { return Data() }
    defer { _ = c2pa_free(pointer) }
    guard length > 0 else { return Data() }
    return Data(bytes: pointer, count: Int(length))
}

/// Invokes `body` with a NULL-terminated C string array built from `strings`
/// (or `nil` when `strings` is empty). The array and its strings are valid only
/// for the duration of `body`.
///
/// - Throws: ``C2PAError`` if any string could not be duplicated. A failed `strdup`
///   would otherwise leave a NULL in the middle of the array, which the C layer reads
///   as the terminator and so silently truncates the list.
func withCStringArray<R>(
    _ strings: [String],
    _ body: (UnsafePointer<UnsafePointer<CChar>?>?) throws -> R
) throws -> R {
    guard !strings.isEmpty else { return try body(nil) }
    var cStrings: [UnsafePointer<CChar>?] = strings.map { UnsafePointer(strdup($0)) }
    cStrings.append(nil)
    // Installed before the allocation check so partial allocations are freed when it throws.
    defer { for p in cStrings where p != nil { free(UnsafeMutablePointer(mutating: p)) } }
    guard !cStrings.dropLast().contains(where: { $0 == nil }) else {
        throw C2PAError.api("Failed to allocate C string array")
    }
    return try cStrings.withUnsafeBufferPointer { try body($0.baseAddress) }
}

/// Infers the MIME type for a file URL from its path extension.
///
/// - Parameter url: The file URL whose extension determines the MIME type.
/// - Returns: The preferred MIME type (e.g. `"image/jpeg"`).
/// - Throws: ``C2PAError`` if the extension maps to no known type.
func inferredMIMEType(for url: URL) throws -> String {
    guard let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType else {
        throw C2PAError.api("Unsupported or unknown file type for extension '\(url.pathExtension)'")
    }
    return mime
}
