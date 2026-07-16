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
//  C2PA.swift
//

import C2PAC
import Foundation

/// The main entry point for C2PA operations.
///
/// `C2PA` provides static methods for reading and signing content credentials in media files.
/// It wraps the underlying C2PA Rust library with a type-safe Swift API.
///
/// ## Topics
///
/// ### Reading Manifests
/// - ``readFile(at:)``
///
/// ### Signing Files
/// - ``signFile(source:destination:manifestJSON:signerInfo:)``
public enum C2PA {

    public static var version: String {
        let p = c2pa_version()!
        defer { _ = c2pa_free(p) }
        return String(cString: p)
    }

    /// Reads the C2PA manifest from a file and returns it as JSON.
    ///
    /// Opens the file as a stream, infers its MIME type from the file extension,
    /// and returns the embedded manifest as a JSON string.
    ///
    /// - Parameter url: The URL of the file to read the manifest from.
    ///
    /// - Returns: A JSON string containing the C2PA manifest data.
    ///
    /// - Throws: ``C2PAError`` if the file cannot be read, the type is unknown,
    ///   or it contains no valid manifest.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let manifestJSON = try C2PA.readFile(at: imageURL)
    /// ```
    public static func readFile(at url: URL) throws -> String {
        let stream = try Stream(readFrom: url)
        let format = try inferredMIMEType(for: url)
        let reader = try Reader(format: format, stream: stream)
        return try reader.json()
    }

    /// Signs a media file with a C2PA manifest using PEM-encoded certificates and keys.
    ///
    /// Streams the source through a context-based ``Builder`` and writes the signed
    /// result to `destination`. The media format is inferred from the source extension.
    ///
    /// - Parameters:
    ///   - source: The URL of the source file to sign.
    ///   - destination: The URL where the signed file will be written.
    ///   - manifestJSON: A JSON string defining the C2PA manifest structure and assertions.
    ///   - signerInfo: The signing credentials including certificate chain and private key.
    ///
    /// - Throws: ``C2PAError`` if signing fails due to invalid inputs, I/O errors,
    ///   an unknown file type, or cryptographic issues.
    ///
    /// - Note: For advanced scenarios (hardware-backed keys, streaming), use
    ///   ``Builder`` with a ``Signer`` instance directly.
    ///
    /// - SeeAlso: ``Builder``, ``Signer``, ``SignerInfo``, ``C2PAContext``
    public static func signFile(
        source: URL,
        destination: URL,
        manifestJSON: String,
        signerInfo: SignerInfo
    ) throws {
        let format = try inferredMIMEType(for: source)
        let sourceStream = try Stream(readFrom: source)
        let destStream = try Stream(writeTo: destination)
        let signer = try Signer(info: signerInfo)
        let builder = try Builder(context: C2PAContext(), manifestJSON: manifestJSON)
        _ = try builder.sign(
            format: format,
            source: sourceStream,
            destination: destStream,
            signer: signer
        )
    }
}
