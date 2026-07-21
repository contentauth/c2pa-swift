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
//  Reader.swift
//

import C2PAC
import Foundation

/// A reader for extracting C2PA manifest data and resources from media files.
///
/// `Reader` provides low-level access to C2PA manifests and associated resources
/// embedded in media files. Use this class when you need fine-grained control
/// over reading operations or when working with stream-based I/O.
///
/// For simple file-based reading, consider using ``C2PA/readFile(at:)`` instead.
///
/// ## Topics
///
/// ### Creating a Reader
/// - ``init(context:format:stream:)``
/// - ``init(format:stream:)``
/// - ``init(context:format:stream:manifest:)``
/// - ``init(format:stream:manifest:)``
///
/// ### Reading Manifest Data
/// - ``json()``
/// - ``detailedJSON()``
/// - ``crJSON()``
/// - ``remote()``
/// - ``isEmbedded()``
///
/// ### Extracting Resources
/// - ``resource(uri:to:)``
///
/// ### Introspection
/// - ``supportedMimeTypes``
///
/// ## Example
///
/// ```swift
/// let stream = try Stream(readFrom: imageURL)
/// let reader = try Reader(format: "image/jpeg", stream: stream)
/// let manifestJSON = try reader.json()
/// print("Manifest: \(manifestJSON)")
/// ```
///
/// - SeeAlso: ``Stream``, ``C2PA/readFile(at:)``
public final class Reader {
    private let ptr: UnsafeMutablePointer<C2paReader>

    // The native reader keeps a clone of the context alive, so the Swift wrapper
    // must live at least as long or state it owns for the native layer dangles.
    private let context: C2PAContext?

    /// Adopts an already-built native reader.
    private init(adopting reader: UnsafeMutablePointer<C2paReader>, context: C2PAContext?) {
        self.ptr = reader
        self.context = context
    }

    /// Creates a reader for a media file stream using a configured context.
    ///
    /// The reader inherits the context's configuration (settings such as verify
    /// and trust options, and any HTTP resolver), so they apply while reading.
    ///
    /// - Parameters:
    ///   - context: The ``C2PAContext`` providing shared configuration.
    ///   - format: The MIME type of the media file (e.g., "image/jpeg", "video/mp4").
    ///   - stream: A ``Stream`` containing the media file data.
    ///
    /// - Throws: ``C2PAError`` if the stream cannot be read or contains no valid manifest.
    ///
    /// - SeeAlso: ``C2PAContext``
    public convenience init(context: C2PAContext, format: String, stream: Stream) throws {
        let base = try guardNotNull(c2pa_reader_from_context(context.ptr))
        self.init(
            adopting: try guardNotNull(c2pa_reader_with_stream(base, format, stream.rawPtr)),
            context: context
        )
    }

    /// Creates a reader for a media file stream.
    ///
    /// This initializer reads the manifest embedded in the media file itself,
    /// using a default context.
    ///
    /// - Parameters:
    ///   - format: The MIME type of the media file (e.g., "image/jpeg", "video/mp4").
    ///   - stream: A ``Stream`` containing the media file data.
    ///
    /// - Throws: ``C2PAError`` if the stream cannot be read or contains no valid manifest.
    public convenience init(format: String, stream: Stream) throws {
        try self.init(context: C2PAContext(), format: format, stream: stream)
    }

    /// Creates a reader from separate manifest data and media stream using a configured context.
    ///
    /// - Parameters:
    ///   - context: The ``C2PAContext`` providing shared configuration.
    ///   - format: The MIME type of the media file.
    ///   - stream: A ``Stream`` containing the media file data.
    ///   - manifest: The raw manifest bytes.
    ///
    /// - Throws: ``C2PAError`` if the manifest or stream cannot be processed.
    ///
    /// - SeeAlso: ``C2PAContext``
    public convenience init(context: C2PAContext, format: String, stream: Stream, manifest: Data) throws {
        let base = try guardNotNull(c2pa_reader_from_context(context.ptr))
        let reader = try manifest.withUnsafeBytes { buf in
            try guardNotNull(
                c2pa_reader_with_manifest_data_and_stream(
                    base,
                    format,
                    stream.rawPtr,
                    buf.bindMemory(to: UInt8.self).baseAddress,
                    UInt(manifest.count)
                )
            )
        }
        self.init(adopting: reader, context: context)
    }

    /// Creates a reader from separate manifest data and media stream.
    ///
    /// This initializer is used when the manifest is stored separately from the
    /// media file (e.g., when using remote manifests with ``Builder/setNoEmbed()``).
    /// It uses a default context.
    ///
    /// - Parameters:
    ///   - format: The MIME type of the media file.
    ///   - stream: A ``Stream`` containing the media file data.
    ///   - manifest: The raw manifest bytes.
    ///
    /// - Throws: ``C2PAError`` if the manifest or stream cannot be processed.
    public convenience init(format: String, stream: Stream, manifest: Data) throws {
        try self.init(context: C2PAContext(), format: format, stream: stream, manifest: manifest)
    }

    deinit { _ = c2pa_free(ptr) }

    /// Returns the manifest data as a JSON string.
    ///
    /// This method extracts and validates the complete C2PA manifest,
    /// returning it as formatted JSON.
    ///
    /// - Returns: A JSON string containing the manifest data.
    ///
    /// - Throws: ``C2PAError`` if the manifest cannot be read or is invalid.
    ///
    /// - SeeAlso: ``detailedJSON()``
    public func json() throws -> String {
        try stringFromC(c2pa_reader_json(ptr))
    }

    /// Returns detailed manifest data as a JSON string.
    ///
    /// This method returns a more comprehensive JSON representation of the manifest
    /// that includes additional internal fields not present in the standard ``json()``
    /// output. Use this when you need access to all manifest details for debugging
    /// or advanced processing.
    ///
    /// - Returns: A JSON string containing the detailed manifest data.
    ///
    /// - Throws: ``C2PAError`` if the manifest cannot be read or is invalid.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let stream = try Stream(readFrom: imageURL)
    /// let reader = try Reader(format: "image/jpeg", stream: stream)
    ///
    /// // Standard JSON for typical use
    /// let standardJSON = try reader.json()
    ///
    /// // Detailed JSON for debugging or advanced analysis
    /// let detailedJSON = try reader.detailedJSON()
    /// ```
    ///
    /// - SeeAlso: ``json()``
    public func detailedJSON() throws -> String {
        try stringFromC(c2pa_reader_detailed_json(ptr))
    }

    /// Returns the manifest as a crJSON string.
    ///
    /// crJSON is the CBOR-rendered JSON form of the manifest store.
    ///
    /// - Returns: A crJSON string for the manifest.
    ///
    /// - Throws: ``C2PAError`` if the manifest cannot be read or is invalid.
    ///
    /// - SeeAlso: ``json()``, ``detailedJSON()``
    public func crJSON() throws -> String {
        try stringFromC(c2pa_reader_crjson(ptr))
    }

    /// Returns the remote URL where the manifest is hosted, if available.
    ///
    /// This method returns the URL specified when the manifest was created with
    /// ``Builder/setNoEmbed()`` and ``Builder/setRemote(url:)``. The URL indicates
    /// where the manifest can be retrieved separately from the media file.
    ///
    /// - Returns: The remote URL, or `nil` if the manifest is embedded.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let stream = try Stream(readFrom: imageURL)
    /// let reader = try Reader(format: "image/jpeg", stream: stream)
    /// if let remote = reader.remote() {
    ///     print("Manifest hosted at: \(remote.absoluteString)")
    /// } else {
    ///     print("Manifest is embedded")
    /// }
    /// ```
    ///
    /// - SeeAlso: ``isEmbedded()``
    public func remote() -> URL? {
        guard let cString = c2pa_reader_remote_url(ptr) else {
            return nil
        }
        defer { _ = c2pa_free(cString) }
        return URL(string: String(cString: cString))
    }

    /// Returns whether the manifest is embedded in the media file.
    ///
    /// This method checks if the manifest data is stored directly within the
    /// media file or if it is stored remotely and referenced via URL.
    ///
    /// - Returns: `true` if the manifest is embedded, `false` if it is remote.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let stream = try Stream(readFrom: imageURL)
    /// let reader = try Reader(format: "image/jpeg", stream: stream)
    /// if reader.isEmbedded() {
    ///     print("Manifest is embedded in the file")
    /// } else {
    ///     print("Manifest is stored remotely at: \(reader.remoteURL() ?? "unknown")")
    /// }
    /// ```
    ///
    /// - SeeAlso: ``remote()``
    public func isEmbedded() -> Bool {
        c2pa_reader_is_embedded(ptr)
    }

    /// Extracts a resource from the manifest to a stream.
    ///
    /// Resources are auxiliary files embedded in the C2PA manifest, such as
    /// thumbnails or additional metadata files.
    ///
    /// - Parameters:
    ///   - uri: The URI of the resource within the manifest.
    ///   - dest: A ``Stream`` where the resource data will be written.
    ///
    /// - Throws: ``C2PAError`` if the resource cannot be found or extracted.
    public func resource(uri: String, to dest: Stream) throws {
        _ = try guardNonNegative(
            c2pa_reader_resource_to_stream(ptr, uri, dest.rawPtr)
        )
    }

    /// The MIME types supported by the reader for reading manifests.
    ///
    /// - Returns: An array of supported MIME type strings (e.g. `"image/jpeg"`).
    public static var supportedMimeTypes: [String] {
        var count: UInt = 0
        let ptr = c2pa_reader_supported_mime_types(&count)
        return stringArrayFromC(ptr, count: Int(count))
    }
}
