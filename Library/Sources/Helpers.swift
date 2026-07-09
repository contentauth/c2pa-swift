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

@inline(__always)
func stringFromC(_ p: UnsafeMutablePointer<CChar>?) throws -> String {
    guard let p else { throw C2PAError.api(lastC2PAError()) }
    defer { c2pa_string_free(p) }
    guard let s = String(validatingCString: p) else { throw C2PAError.utf8 }
    return s
}

@inline(__always)
func lastC2PAError() -> String {
    guard let p = c2pa_error() else { return "Unknown C2PA error" }
    defer { c2pa_string_free(p) }
    return String(cString: p)
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

/// Builds `Data` from the `(int64 length, out **bytes)` pattern used by the embeddable
/// FFI calls, freeing the native buffer with `c2pa_free`. `length` is the guarded,
/// non-negative result; `pointer` is the out-parameter the call populated.
func manifestData(length: Int64, pointer: UnsafePointer<UInt8>?) -> Data {
    guard let pointer else { return Data() }
    defer { _ = c2pa_free(pointer) }
    guard length > 0 else { return Data() }
    return Data(bytes: pointer, count: Int(length))
}
