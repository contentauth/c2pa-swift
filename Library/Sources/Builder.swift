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
//  Builder.swift
//

import C2PAC
import Foundation

/// A builder for constructing and signing C2PA manifests with advanced options.
///
/// `Builder` provides fine-grained control over the creation of C2PA manifests,
/// including adding ingredients, resources, and configuring embedding options.
/// Use this class when you need more control than the convenience methods
/// in ``C2PA`` provide.
///
/// ## Topics
///
/// ### Creating a Builder
/// - ``init(manifest:)``
/// - ``init(manifestJSON:)``
/// - ``init(archiveStream:)``
/// - ``init(context:manifest:)``
/// - ``init(context:manifestJSON:)``
/// - ``init(context:archiveStream:)``
///
/// ### Configuring the Manifest
/// - ``setIntent(_:)``
/// - ``addAction(_:)``
/// - ``setNoEmbed()``
/// - ``setRemote(url:)``
/// - ``setBasePath(_:)``
///
/// ### Introspection
/// - ``supportedMimeTypes``
///
/// ### Adding Content
/// - ``addResource(uri:stream:)``
/// - ``addIngredient(json:format:from:)``
/// - ``addIngredient(fromArchive:)``
/// - ``writeIngredientArchive(id:to:)``
///
/// ### Signing and Output
/// - ``sign(format:source:destination:signer:)``
/// - ``writeArchive(to:)``
///
/// ### Embeddable & Data-Hash Signing
/// - ``needsPlaceholder(format:)``
/// - ``placeholder(format:)``
/// - ``dataHashedPlaceholder(reservedSize:format:)``
/// - ``setDataHashExclusions(_:)``
/// - ``updateHashFromStream(format:stream:)``
/// - ``signEmbeddable(format:)``
/// - ``signDataHashedEmbeddable(signer:dataHash:format:asset:)``
/// - ``formatEmbeddable(_:format:)``
///
/// ### Fragmented (BMFF) Hashing
/// - ``setFixedSizeMerkle(_:)``
/// - ``hashMdatBytes(mdatId:data:largeSize:)``
/// - ``hashType(format:)``
///
/// ## Example
///
/// ```swift
/// let builder = try Builder(manifestJSON: manifestJSON)
/// try builder.setIntent(.edit)
/// builder.setNoEmbed()
/// try builder.setRemote(url: URL(string: "https://example.com/manifest.c2pa")!)
/// try builder.addIngredient(
///     json: ingredientJSON,
///     format: "image/jpeg",
///     from: ingredientStream
/// )
///
/// let signer = try Signer(info: signerInfo)
/// try builder.sign(
///     format: "image/jpeg",
///     source: sourceStream,
///     destination: destStream,
///     signer: signer
/// )
/// ```
public final class Builder {
    private let ptr: UnsafeMutablePointer<C2paBuilder>

    // The native builder keeps a clone of the context alive, so the Swift wrapper
    // must live at least as long or state it owns for the native layer dangles.
    private let context: C2PAContext?

    /// Internal initializer that skips validation.
    private init(validatedJSON: String) throws {
        ptr = try guardNotNull(c2pa_builder_from_json(validatedJSON))
        context = nil
    }

    /// Internal initializer that adopts an already-configured native builder.
    private init(adopting ptr: UnsafeMutablePointer<C2paBuilder>, context: C2PAContext?) {
        self.ptr = ptr
        self.context = context
    }

    /// Validates a ``ManifestValidationResult``, logging warnings and throwing on errors.
    private static func enforce(_ result: ManifestValidationResult) throws {
        for warning in result.warnings {
            NSLog("[C2PA] Manifest validation warning: %@", warning)
        }
        if result.hasErrors {
            throw C2PAError.manifestValidationFailed(result)
        }
    }

    /// Creates a new builder from a ``ManifestDefinition``.
    ///
    /// Validates the manifest before construction. Errors cause a throw;
    /// warnings are logged via `NSLog`.
    ///
    /// - Parameter manifest: The manifest definition to build.
    ///
    /// - Throws: ``C2PAError/manifestValidationFailed(_:)`` if validation finds errors,
    ///   or ``C2PAError`` if the JSON cannot be parsed by the C layer.
    public convenience init(manifest: ManifestDefinition) throws {
        try Self.enforce(ManifestValidator.validate(manifest))
        try self.init(validatedJSON: manifest.toJSON())
    }

    /// Creates a new builder from a manifest JSON definition.
    ///
    /// This is a low-level initializer that passes the JSON directly to the C layer.
    /// Use ``init(manifest:)`` for automatic validation before construction.
    ///
    /// - Parameter manifestJSON: A JSON string defining the C2PA manifest structure.
    ///
    /// - Throws: ``C2PAError`` if the JSON is invalid or cannot be parsed.
    public convenience init(manifestJSON: String) throws {
        try self.init(validatedJSON: manifestJSON)
    }

    /// Creates a new builder from a ``C2PAContext`` and a previously created C2PA archive stream.
    ///
    /// The builder inherits the context's configuration (settings), so values
    /// such as created-assertion labels and trust configuration flow into the
    /// signed manifest.
    ///
    /// - Parameters:
    ///   - context: The ``C2PAContext`` providing shared configuration.
    ///   - archiveStream: A ``Stream`` containing a C2PA archive.
    ///
    /// - Throws: ``C2PAError`` if the archive is invalid or cannot be read.
    ///
    /// - SeeAlso: ``C2PAContext``
    public convenience init(context: C2PAContext, archiveStream: Stream) throws {
        let base = try guardNotNull(c2pa_builder_from_context(context.ptr))
        let configured = try guardNotNull(c2pa_builder_with_archive(base, archiveStream.rawPtr))
        self.init(adopting: configured, context: context)
    }

    /// Creates a new builder from a previously created C2PA archive stream, using a default context.
    ///
    /// - Parameter archiveStream: A ``Stream`` containing a C2PA archive.
    ///
    /// - Throws: ``C2PAError`` if the archive is invalid or cannot be read.
    public convenience init(archiveStream: Stream) throws {
        try self.init(context: C2PAContext(), archiveStream: archiveStream)
    }

    /// Creates a new builder from a ``C2PAContext`` and a manifest JSON definition.
    ///
    /// The builder inherits the context's configuration (settings), so values
    /// such as created-assertion labels and trust configuration flow into the
    /// signed manifest.
    ///
    /// - Parameters:
    ///   - context: The ``C2PAContext`` providing shared configuration.
    ///   - manifestJSON: A JSON string defining the C2PA manifest structure.
    ///
    /// - Throws: ``C2PAError`` if the builder cannot be created or the JSON is invalid.
    ///
    /// - SeeAlso: ``C2PAContext``
    public convenience init(context: C2PAContext, manifestJSON: String) throws {
        let base = try guardNotNull(c2pa_builder_from_context(context.ptr))
        let configured = try guardNotNull(c2pa_builder_with_definition(base, manifestJSON))
        self.init(adopting: configured, context: context)
    }

    /// Creates a new builder from a ``C2PAContext`` and a ``ManifestDefinition``.
    ///
    /// Validates the manifest before construction. Errors cause a throw;
    /// warnings are logged via `NSLog`.
    ///
    /// - Parameters:
    ///   - context: The ``C2PAContext`` providing shared configuration.
    ///   - manifest: The manifest definition to build.
    ///
    /// - Throws: ``C2PAError/manifestValidationFailed(_:)`` if validation finds errors,
    ///   or ``C2PAError`` if the JSON cannot be parsed by the C layer.
    ///
    /// - SeeAlso: ``C2PAContext``, ``ManifestDefinition``
    public convenience init(context: C2PAContext, manifest: ManifestDefinition) throws {
        try Self.enforce(ManifestValidator.validate(manifest))
        try self.init(context: context, manifestJSON: manifest.toJSON())
    }

    deinit { _ = c2pa_free(ptr) }

    /// Sets the builder intent, specifying what kind of manifest to create.
    ///
    /// The intent determines whether this is a new creation, an edit of existing content,
    /// or a metadata-only update. This affects what assertions are automatically added
    /// and what ingredients are required.
    ///
    /// - Parameter intent: The ``BuilderIntent`` specifying the type of manifest.
    ///
    /// - Throws: ``C2PAError`` if the intent cannot be set.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let builder = try Builder(manifestJSON: manifestJSON)
    /// try builder.setIntent(.create(.digitalCapture))
    /// ```
    ///
    /// ```swift
    /// let builder = try Builder(manifestJSON: manifestJSON)
    /// try builder.setIntent(.edit)
    /// ```
    ///
    /// - SeeAlso: ``BuilderIntent``, ``DigitalSourceType``
    public func setIntent(_ intent: BuilderIntent) throws {
        let (cIntent, cSourceType) = intent.toCIntent()
        _ = try guardNonNegative(
            Int64(c2pa_builder_set_intent(ptr, cIntent, cSourceType))
        )
    }

    /// Adds an action to the manifest being constructed.
    ///
    /// Actions describe operations performed on the content, such as editing,
    /// cropping, or applying filters. Multiple actions can be added to a single
    /// manifest to document the complete editing history.
    ///
    /// - Parameter action: The ``Action`` to add to the manifest.
    ///
    /// - Throws: ``C2PAError`` if the action cannot be added.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let builder = try Builder(manifestJSON: manifestJSON)
    /// try builder.addAction(Action(action: .edited, digitalSourceType: .digitalCapture))
    /// try builder.addAction(Action(action: .cropped, digitalSourceType: .digitalCapture))
    /// ```
    ///
    /// - SeeAlso: ``Action``, ``PredefinedAction``
    public func addAction(_ action: Action) throws {
        let actionJSON = try C2PAJson.encode(action)
        _ = try guardNonNegative(
            Int64(c2pa_builder_add_action(ptr, actionJSON))
        )
    }

    /// Configures the builder to not embed the manifest in the output file.
    ///
    /// When enabled, the manifest will be stored separately and referenced
    /// via a remote URL. You must call ``setRemote(url:)`` to specify
    /// where the manifest will be hosted.
    ///
    /// - SeeAlso: ``setRemote(url:)``
    public func setNoEmbed() { c2pa_builder_set_no_embed(ptr) }

    /// Sets the remote URL where the manifest will be hosted.
    ///
    /// This URL is embedded in the output file when ``setNoEmbed()`` is enabled,
    /// allowing the manifest to be retrieved separately from the media file.
    ///
    /// - Parameter url: The HTTPS URL where the manifest will be accessible.
    ///
    /// - Throws: ``C2PAError`` if the URL is invalid or cannot be set.
    ///
    /// - Note: The URL should be accessible via HTTPS for security.
    ///
    /// - SeeAlso: ``setNoEmbed()``
    public func setRemote(url: URL) throws {
        _ = try guardNonNegative(
            Int64(c2pa_builder_set_remote_url(ptr, url.absoluteString))
        )
    }

    /// Sets the base directory used to resolve relative resource paths in the manifest.
    ///
    /// - Parameter url: A directory URL used as the base path for resolving resources.
    ///
    /// - Throws: ``C2PAError`` if the base path cannot be set.
    public func setBasePath(_ url: URL) throws {
        _ = try guardNonNegative(
            Int64(c2pa_builder_set_base_path(ptr, url.path))
        )
    }

    /// The MIME types supported by the builder for signing.
    ///
    /// - Returns: An array of supported MIME type strings (e.g. `"image/jpeg"`).
    public static var supportedMimeTypes: [String] {
        var count: UInt = 0
        let ptr = c2pa_builder_supported_mime_types(&count)
        return stringArrayFromC(ptr, count: Int(count))
    }

    /// Adds a resource to the manifest.
    ///
    /// Resources are auxiliary files (like thumbnails or metadata) that are
    /// referenced by the manifest and embedded in the signed output.
    ///
    /// - Parameters:
    ///   - uri: The URI identifier for the resource within the manifest.
    ///   - stream: A ``Stream`` containing the resource data.
    ///
    /// - Throws: ``C2PAError`` if the resource cannot be added.
    public func addResource(uri: String, stream: Stream) throws {
        _ = try guardNonNegative(
            Int64(c2pa_builder_add_resource(ptr, uri, stream.rawPtr))
        )
    }

    /// Adds an ingredient (source material) to the manifest.
    ///
    /// Ingredients represent the original or modified content used to create
    /// the new asset. Each ingredient should have its own metadata describing
    /// its provenance.
    ///
    /// - Parameters:
    ///   - json: A JSON string describing the ingredient's assertions and metadata.
    ///   - format: The MIME type of the ingredient (e.g., "image/jpeg").
    ///   - stream: A ``Stream`` containing the ingredient file data.
    ///
    /// - Throws: ``C2PAError`` if the ingredient cannot be added.
    public func addIngredient(json: String, format: String, from stream: Stream) throws {
        _ = try guardNonNegative(
            Int64(c2pa_builder_add_ingredient_from_stream(ptr, json, format, stream.rawPtr))
        )
    }

    /// Adds an ingredient previously exported as a C2PA ingredient archive.
    ///
    /// - Parameter stream: A ``Stream`` containing a C2PA ingredient archive.
    ///
    /// - Throws: ``C2PAError`` if the archive cannot be read or added.
    ///
    /// - SeeAlso: ``writeIngredientArchive(id:to:)``
    public func addIngredient(fromArchive stream: Stream) throws {
        _ = try guardNonNegative(
            Int64(c2pa_builder_add_ingredient_from_archive(ptr, stream.rawPtr))
        )
    }

    /// Writes a previously added ingredient out as a standalone C2PA ingredient archive.
    ///
    /// - Parameters:
    ///   - id: The identifier of the ingredient to export.
    ///   - stream: A ``Stream`` where the ingredient archive will be written.
    ///
    /// - Throws: ``C2PAError`` if the ingredient cannot be written.
    ///
    /// - SeeAlso: ``addIngredient(fromArchive:)``
    public func writeIngredientArchive(id: String, to stream: Stream) throws {
        _ = try guardNonNegative(
            Int64(c2pa_builder_write_ingredient_archive(ptr, id, stream.rawPtr))
        )
    }

    /// Writes the manifest as a C2PA archive to a stream.
    ///
    /// This creates a standalone archive file containing the manifest and
    /// all associated resources, which can be stored separately or embedded later.
    ///
    /// - Parameter dest: A ``Stream`` where the archive will be written.
    ///
    /// - Throws: ``C2PAError`` if the archive cannot be written.
    public func writeArchive(to dest: Stream) throws {
        _ = try guardNonNegative(
            Int64(c2pa_builder_to_archive(ptr, dest.rawPtr))
        )
    }

    /// Signs the source file and writes the signed result with an embedded manifest.
    ///
    /// This method performs the complete signing operation: it reads the source media,
    /// embeds the configured manifest with all resources and ingredients, signs it
    /// using the provided signer, and writes the result to the destination stream.
    ///
    /// - Parameters:
    ///   - format: The MIME type of the media file (e.g., "image/jpeg", "video/mp4").
    ///   - source: A ``Stream`` containing the source media file.
    ///   - destination: A ``Stream`` where the signed file will be written.
    ///   - signer: A ``Signer`` instance configured with signing credentials.
    ///
    /// - Returns: The raw manifest bytes as `Data`.
    ///
    /// - Throws: ``C2PAError`` if signing fails due to invalid inputs, I/O errors,
    ///   or cryptographic issues.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let builder = try Builder(manifestJSON: manifestJSON)
    /// let signer = try Signer(info: signerInfo)
    /// let sourceStream = try Stream(readFrom: sourceURL)
    /// let destStream = try Stream(writeTo: destURL)
    ///
    /// let manifestData = try builder.sign(
    ///     format: "image/jpeg",
    ///     source: sourceStream,
    ///     destination: destStream,
    ///     signer: signer
    /// )
    /// ```
    ///
    /// - SeeAlso: ``Signer``, ``Stream``
    @discardableResult
    public func sign(
        format: String,
        source: Stream,
        destination: Stream,
        signer: Signer
    ) throws -> Data {
        var manifestPtr: UnsafePointer<UInt8>?
        let size = try guardNonNegative(
            c2pa_builder_sign(
                ptr,
                format,
                source.rawPtr,
                destination.rawPtr,
                try signer.livePtr(),
                &manifestPtr)
        )
        return manifestData(length: size, pointer: manifestPtr)
    }

    // MARK: - Embeddable & Data-Hash Signing

    /// Returns whether the given format requires a placeholder manifest before signing.
    ///
    /// Call this before ``placeholder(format:)`` to determine whether the two-pass
    /// embeddable workflow is required for the target format.
    ///
    /// - Parameter format: The MIME type of the target asset (e.g. `"image/jpeg"`).
    ///
    /// - Returns: `true` if a placeholder is required; `false` otherwise.
    ///
    /// - Throws: ``C2PAError`` if the check fails or the format is unknown.
    public func needsPlaceholder(format: String) throws -> Bool {
        try guardNonNegative(Int64(c2pa_builder_needs_placeholder(ptr, format))) == 1
    }

    /// Generates a placeholder manifest of the exact final size for the given format.
    ///
    /// The placeholder must be embedded into the asset at the offset that will hold
    /// the final manifest, before hashing and signing. Call ``setDataHashExclusions(_:)``
    /// with the embedded range, then ``updateHashFromStream(format:stream:)`` over the
    /// asset, then ``signEmbeddable(format:)`` to produce the final manifest bytes.
    ///
    /// - Parameter format: The MIME type of the target asset (e.g. `"image/jpeg"`).
    ///
    /// - Returns: The placeholder manifest bytes as `Data`.
    ///
    /// - Throws: ``C2PAError`` if placeholder generation fails.
    public func placeholder(format: String) throws -> Data {
        var out: UnsafePointer<UInt8>?
        let len = try guardNonNegative(c2pa_builder_placeholder(ptr, format, &out))
        return manifestData(length: len, pointer: out)
    }

    /// Generates a data-hash placeholder manifest with a caller-specified reserved size.
    ///
    /// Use this variant when you need to pre-reserve a fixed-size slot in the asset
    /// before you know the exact placeholder content. The `reservedSize` must be at
    /// least as large as the final signed manifest.
    ///
    /// - Parameters:
    ///   - reservedSize: The number of bytes to reserve in the asset for the manifest.
    ///   - format: The MIME type of the target asset (e.g. `"image/jpeg"`).
    ///
    /// - Returns: The placeholder manifest bytes as `Data`.
    ///
    /// - Throws: ``C2PAError`` if placeholder generation fails.
    public func dataHashedPlaceholder(reservedSize: Int, format: String) throws -> Data {
        var out: UnsafePointer<UInt8>?
        let len = try guardNonNegative(
            c2pa_builder_data_hashed_placeholder(ptr, UInt(reservedSize), format, &out))
        return manifestData(length: len, pointer: out)
    }

    /// Registers the byte ranges that must be excluded from the data hash.
    ///
    /// Call this after embedding the placeholder into the asset to tell the hasher
    /// which regions (i.e. the placeholder slot) should be skipped. Must be called
    /// before ``updateHashFromStream(format:stream:)``.
    ///
    /// - Parameter exclusions: An array of `(start, length)` pairs identifying the
    ///   byte ranges to exclude from hashing, expressed as absolute offsets into the asset.
    ///
    /// - Throws: ``C2PAError`` if the exclusions cannot be set.
    public func setDataHashExclusions(_ exclusions: [(start: UInt64, length: UInt64)]) throws {
        var flat: [UInt64] = []
        flat.reserveCapacity(exclusions.count * 2)
        for e in exclusions { flat.append(e.start); flat.append(e.length) }
        try flat.withUnsafeBufferPointer { buf in
            _ = try guardNonNegative(Int64(
                c2pa_builder_set_data_hash_exclusions(ptr, buf.baseAddress, UInt(exclusions.count))))
        }
    }

    /// Hashes the asset stream and records the result in the builder's data-hash assertion.
    ///
    /// Call this after ``setDataHashExclusions(_:)`` and before ``signEmbeddable(format:)``
    /// to hash the full asset (minus the excluded placeholder range).
    ///
    /// - Parameters:
    ///   - format: The MIME type of the asset (e.g. `"image/jpeg"`).
    ///   - stream: A ``Stream`` positioned at the start of the asset to hash.
    ///
    /// - Throws: ``C2PAError`` if hashing fails.
    public func updateHashFromStream(format: String, stream: Stream) throws {
        _ = try guardNonNegative(Int64(
            c2pa_builder_update_hash_from_stream(ptr, format, stream.rawPtr)))
    }

    /// Signs the manifest and returns the composed bytes ready for embedding into an asset.
    ///
    /// Operates in placeholder mode (after calling ``placeholder(format:)``) or in
    /// data-hash mode (after ``setDataHashExclusions(_:)`` and
    /// ``updateHashFromStream(format:stream:)``). The returned bytes are exactly the
    /// same size as the placeholder, so they can be spliced into the asset at the
    /// previously reserved offset.
    ///
    /// - Parameter format: The MIME type of the target asset (e.g. `"image/jpeg"`).
    ///
    /// - Returns: The signed embeddable manifest bytes as `Data`.
    ///
    /// - Throws: ``C2PAError`` if signing fails.
    ///
    /// - Note: This method requires the builder to have been configured with a signer
    ///   via a ``C2PAContext`` — the context must carry the signing credentials.
    @discardableResult
    public func signEmbeddable(format: String) throws -> Data {
        var out: UnsafePointer<UInt8>?
        let len = try guardNonNegative(c2pa_builder_sign_embeddable(ptr, format, &out))
        return manifestData(length: len, pointer: out)
    }

    /// Signs the manifest using a data hash and returns the composed embeddable bytes.
    ///
    /// This is the low-level data-hash signing path: the caller provides a pre-computed
    /// `dataHash` JSON string and the original asset stream. The returned bytes are
    /// suitable for direct embedding into the asset.
    ///
    /// - Parameters:
    ///   - signer: The ``Signer`` instance providing the signing credentials.
    ///   - dataHash: A JSON string containing `DataHash` information for the asset.
    ///   - format: The MIME type of the asset (e.g. `"image/jpeg"`).
    ///   - asset: A ``Stream`` containing the asset to be signed.
    ///
    /// - Returns: The signed embeddable manifest bytes as `Data`.
    ///
    /// - Throws: ``C2PAError`` if signing fails.
    @discardableResult
    public func signDataHashedEmbeddable(
        signer: Signer, dataHash: String, format: String, asset: Stream
    ) throws -> Data {
        var out: UnsafePointer<UInt8>?
        let len = try guardNonNegative(c2pa_builder_sign_data_hashed_embeddable(
            ptr, try signer.livePtr(), dataHash, format, asset.rawPtr, &out))
        return manifestData(length: len, pointer: out)
    }

    /// Converts a raw C2PA manifest into an embeddable version for the given format.
    ///
    /// A raw manifest (in `application/c2pa` format) can be stored in the cloud but
    /// cannot be embedded directly into an asset without format-specific framing.
    /// This static method wraps the manifest bytes in the correct container for embedding.
    ///
    /// - Parameters:
    ///   - manifest: The raw C2PA manifest bytes.
    ///   - format: The MIME type of the target asset (e.g. `"image/jpeg"`).
    ///
    /// - Returns: The format-wrapped embeddable manifest bytes as `Data`.
    ///
    /// - Throws: ``C2PAError`` if the conversion fails.
    public static func formatEmbeddable(_ manifest: Data, format: String) throws -> Data {
        var out: UnsafePointer<UInt8>?
        let len = try manifest.withUnsafeBytes { buf -> Int64 in
            try guardNonNegative(c2pa_format_embeddable(
                format, buf.bindMemory(to: UInt8.self).baseAddress, UInt(manifest.count), &out))
        }
        return manifestData(length: len, pointer: out)
    }

    // MARK: - Fragmented (BMFF) Hashing

    /// Enables fixed-size Merkle-tree hashing for fragmented (BMFF) assets.
    ///
    /// Produces a Merkle tree per `mdat` with fixed-size leaves, for efficient
    /// hashing of large or streamed media. Call before hashing mdat bytes.
    ///
    /// - Parameter fixedSizeKB: Leaf size in kilobytes.
    /// - Throws: ``C2PAError`` if the option cannot be set.
    public func setFixedSizeMerkle(_ fixedSizeKB: Int) throws {
        _ = try guardNonNegative(
            Int64(c2pa_builder_set_fixed_size_merkle(ptr, UInt(fixedSizeKB)))
        )
    }

    /// Generates `mdat` leaf hashes for a chunk of fragmented-media data.
    ///
    /// Supply chunks in the order they are written to the `mdat`. `mdatId` starts
    /// at 0 and increments for each `mdat` in the asset.
    ///
    /// - Parameters:
    ///   - mdatId: The mdat index (0-based).
    ///   - data: The mdat chunk bytes.
    ///   - largeSize: Whether the mdat uses 64-bit (large) box sizing.
    /// - Throws: ``C2PAError`` if the bytes cannot be hashed.
    public func hashMdatBytes(mdatId: Int, data: Data, largeSize: Bool) throws {
        _ = try data.withUnsafeBytes { buf in
            try guardNonNegative(
                Int64(c2pa_builder_hash_mdat_bytes(
                    ptr,
                    UInt(mdatId),
                    buf.bindMemory(to: UInt8.self).baseAddress,
                    UInt(data.count),
                    largeSize))
            )
        }
    }

    /// Returns the hard-binding hash type the builder uses for the given format.
    ///
    /// - Parameter format: The MIME type (e.g. "image/jpeg", "video/mp4").
    /// - Returns: The ``HashType`` for the format.
    /// - Throws: ``C2PAError`` if the type cannot be resolved.
    public func hashType(format: String) throws -> HashType {
        var out = DataHash
        _ = try guardNonNegative(
            Int64(c2pa_builder_hash_type(ptr, format, &out))
        )
        guard let type = HashType(c: out) else {
            throw C2PAError.api("Unknown hash type value: \(out.rawValue)")
        }
        return type
    }
}
