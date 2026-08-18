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
//  C2PAContext.swift
//

import C2PAC
import Foundation

/// A phase of a C2PA signing or reading operation. Maps the native `C2paProgressPhase`.
public enum ProgressPhase: Sendable {
    case reading, verifyingManifest, verifyingSignature, verifyingIngredient,
         verifyingAssetHash, addingIngredient, thumbnail, hashing, signing,
         embedding, fetchingRemoteManifest, writing, fetchingOCSP, fetchingTimestamp

    /// A phase value not known to this version of the wrapper.
    case unknown

    init(_ phase: C2paProgressPhase) {
        switch phase {
        case Reading: self = .reading
        case VerifyingManifest: self = .verifyingManifest
        case VerifyingSignature: self = .verifyingSignature
        case VerifyingIngredient: self = .verifyingIngredient
        case VerifyingAssetHash: self = .verifyingAssetHash
        case AddingIngredient: self = .addingIngredient
        case Thumbnail: self = .thumbnail
        case Hashing: self = .hashing
        case Signing: self = .signing
        case Embedding: self = .embedding
        case FetchingRemoteManifest: self = .fetchingRemoteManifest
        case Writing: self = .writing
        case FetchingOCSP: self = .fetchingOCSP
        case FetchingTimestamp: self = .fetchingTimestamp
        default: self = .unknown
        }
    }
}

/// A progress update delivered during a signing or reading operation.
public struct ProgressUpdate: Sendable {
    /// The current operation phase.
    public let phase: ProgressPhase

    /// Monotonically increasing within a phase (starts at 1); rising values indicate liveness.
    public let step: UInt32

    /// `0` = indeterminate, `1` = single-shot, `> 1` = determinate (`step` of `total`).
    public let total: UInt32
}

/// An HTTP request the SDK needs resolved (remote manifest, OCSP, or timestamp fetch).
public struct HTTPRequest: Sendable {
    /// The request URL.
    public let url: URL

    /// The HTTP method (e.g. `"GET"`).
    public let method: String

    /// Request headers.
    public let headers: [String: String]

    /// The request body, if any.
    public let body: Data?
}

/// The HTTP response a resolver returns.
public struct HTTPResponse: Sendable {
    /// The HTTP status code.
    public let status: Int

    /// The response body.
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

private final class ProgressCallbackBox {
    let onProgress: (ProgressUpdate) -> Void

    init(_ onProgress: @escaping (ProgressUpdate) -> Void) {
        self.onProgress = onProgress
    }
}

/// Carries a resolver result across the `URLSession` completion boundary.
///
/// The completion handler is `@Sendable`, so the result cannot be written into captured
/// local state. Mirrors the pattern already used by ``WebServiceSigner``.
private final class HTTPResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<HTTPResponse, Error>?

    func set(_ value: Result<HTTPResponse, Error>) {
        lock.lock()
        defer { lock.unlock() }
        result = value
    }

    func get() -> Result<HTTPResponse, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

private final class HTTPResolverBox {
    let resolve: (HTTPRequest) throws -> HTTPResponse

    init(_ resolve: @escaping (HTTPRequest) throws -> HTTPResponse) {
        self.resolve = resolve
    }
}

/// Observes progress and always continues; cancellation is via ``C2PAContext/cancel()``.
private let progressTrampoline: ProgressCCallback = { context, phase, step, total in
    guard let context else { return 1 }
    let box = Unmanaged<ProgressCallbackBox>.fromOpaque(context).takeUnretainedValue()
    box.onProgress(ProgressUpdate(phase: ProgressPhase(phase), step: step, total: total))
    return 1
}

/// Resolves one request. May run on any thread, so the boxed closure must be thread-safe.
private let httpResolverTrampoline: C2paHttpResolverCallback = { context, request, response in
    guard let context, let request, let response else { return 1 }
    let box = Unmanaged<HTTPResolverBox>.fromOpaque(context).takeUnretainedValue()
    let incoming = request.pointee

    guard let urlPtr = incoming.url, let url = URL(string: String(cString: urlPtr)) else {
        _ = "Invalid request URL".withCString { c2pa_error_set_last($0) }
        return 1
    }

    let method = incoming.method.map { String(cString: $0) } ?? "GET"
    var headers: [String: String] = [:]
    if let rawHeaders = incoming.headers {
        for line in String(cString: rawHeaders).split(separator: "\n") {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { headers[name] = value }
        }
    }
    let body: Data? = (incoming.body != nil && incoming.body_len > 0)
        ? Data(bytes: incoming.body!, count: Int(incoming.body_len)) : nil

    do {
        let result = try box.resolve(
            HTTPRequest(url: url, method: method, headers: headers, body: body))
        response.pointee.status = Int32(result.status)
        if result.body.isEmpty {
            response.pointee.body = nil
            response.pointee.body_len = 0
        } else {
            // Rust takes ownership of this allocation and frees it.
            guard let buffer = malloc(result.body.count)?.assumingMemoryBound(to: UInt8.self) else {
                _ = "Failed to allocate response body".withCString { c2pa_error_set_last($0) }
                return 1
            }
            result.body.copyBytes(to: buffer, count: result.body.count)
            response.pointee.body = buffer
            response.pointee.body_len = UInt(result.body.count)
        }
        return 0
    } catch {
        _ = String(describing: error).withCString { c2pa_error_set_last($0) }
        return 1
    }
}

/// An immutable, shareable configuration context for creating builders.
///
/// A `C2PAContext` captures configuration — settings such as created-assertion
/// labels, trust configuration, and CAWG signer settings — and can be used to
/// create one or more ``Builder`` instances that share it. Once created, a
/// context is immutable.
///
/// ## Topics
///
/// ### Creating a Context
/// - ``init(settings:onProgress:httpResolver:)``
/// - ``init(settings:onProgress:urlSession:)``
///
/// ### Controlling Operations
/// - ``cancel()``
///
/// ## Example
///
/// ```swift
/// let settings = try C2PASettings(json: settingsJSON)
/// let context = try C2PAContext(settings: settings)
/// let builder = try Builder(context: context, manifestJSON: manifestJSON)
/// ```
///
/// - SeeAlso: ``C2PASettings``, ``Builder``
public final class C2PAContext {
    let ptr: UnsafeMutablePointer<C2paContext>

    /// Boxes holding the callback closures the native context may invoke.
    ///
    /// The C layer keeps only unretained pointers to these, so they must outlive the
    /// context. Holding them here ties their lifetime to it exactly.
    private let callbackBoxes: [AnyObject]

    /// Internal initializer that adopts an already-built native context.
    init(ptr: UnsafeMutablePointer<C2paContext>, callbackBoxes: [AnyObject] = []) {
        self.ptr = ptr
        self.callbackBoxes = callbackBoxes
    }

    /// Creates a context, optionally configured with settings and callbacks.
    ///
    /// The settings are cloned by the C layer, so the caller retains ownership of
    /// `settings`. The callbacks are retained by the context and may be invoked for as
    /// long as it is alive.
    ///
    /// - Parameters:
    ///   - settings: The ``C2PASettings`` to configure this context with.
    ///   - onProgress: Observes operation progress. Called synchronously at checkpoints;
    ///     to stop an operation call ``cancel()`` rather than returning from here.
    ///   - httpResolver: Resolves HTTP requests the SDK makes (remote manifests, OCSP,
    ///     timestamps). Called synchronously and possibly from any thread, so it must be
    ///     thread-safe. Throwing fails the request.
    ///
    /// - Throws: ``C2PAError`` if the context cannot be created.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let context = try C2PAContext(settings: settings) { update in
    ///     print("\(update.phase) \(update.step)/\(update.total)")
    /// }
    /// ```
    public convenience init(
        settings: C2PASettings? = nil,
        onProgress: ((ProgressUpdate) -> Void)? = nil,
        httpResolver: ((HTTPRequest) throws -> HTTPResponse)? = nil
    ) throws {
        guard settings != nil || onProgress != nil || httpResolver != nil else {
            self.init(ptr: try guardNotNull(c2pa_context_new()))
            return
        }

        let builder = try guardNotNull(c2pa_context_builder_new())
        var boxes: [AnyObject] = []
        do {
            if let settings {
                _ = try guardNonNegative(
                    Int64(c2pa_context_builder_set_settings(builder, settings.rawPtr)))
            }

            if let onProgress {
                let box = ProgressCallbackBox(onProgress)
                boxes.append(box)
                _ = try guardNonNegative(Int64(c2pa_context_builder_set_progress_callback(
                    builder, Unmanaged.passUnretained(box).toOpaque(), progressTrampoline)))
            }

            if let httpResolver {
                let box = HTTPResolverBox(httpResolver)
                boxes.append(box)
                let resolver = try guardNotNull(c2pa_http_resolver_create(
                    Unmanaged.passUnretained(box).toOpaque(), httpResolverTrampoline))
                do {
                    _ = try guardNonNegative(
                        Int64(c2pa_context_builder_set_http_resolver(builder, resolver)))
                } catch {
                    // The resolver is only consumed on success, so release it ourselves.
                    _ = c2pa_free(resolver)
                    throw error
                }
            }
        } catch {
            _ = c2pa_free(builder)
            throw error
        }

        // c2pa_context_builder_build consumes the builder, even on failure.
        self.init(
            ptr: try guardNotNull(c2pa_context_builder_build(builder)), callbackBoxes: boxes)
    }

    /// Creates a context whose HTTP requests are resolved by a `URLSession`.
    ///
    /// A separate initializer rather than a defaulted parameter, so a caller cannot pass
    /// both this and a custom `httpResolver`.
    ///
    /// - Parameters:
    ///   - settings: The ``C2PASettings`` to configure this context with.
    ///   - onProgress: Observes operation progress. See ``init(settings:onProgress:httpResolver:)``.
    ///   - urlSession: The session used to perform each request.
    ///
    /// - Throws: ``C2PAError`` if the context cannot be created.
    public convenience init(
        settings: C2PASettings? = nil,
        onProgress: ((ProgressUpdate) -> Void)? = nil,
        urlSession: URLSession
    ) throws {
        try self.init(
            settings: settings,
            onProgress: onProgress,
            httpResolver: { request in
                var urlRequest = URLRequest(url: request.url)
                urlRequest.httpMethod = request.method
                for (name, value) in request.headers {
                    urlRequest.setValue(value, forHTTPHeaderField: name)
                }
                urlRequest.httpBody = request.body

                // The native resolver call is synchronous, so block until the task lands.
                // URLSession delivers on its own queue, so waiting here cannot deadlock it.
                let resultBox = HTTPResultBox()
                let semaphore = DispatchSemaphore(value: 0)
                let task = urlSession.dataTask(with: urlRequest) { data, response, error in
                    if let error {
                        resultBox.set(.failure(
                            C2PAError.api("HTTP resolver request failed: \(error)")))
                    } else {
                        resultBox.set(.success(HTTPResponse(
                            status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                            body: data ?? Data())))
                    }
                    semaphore.signal()
                }
                task.resume()
                semaphore.wait()

                switch resultBox.get() {
                case .success(let response):
                    return response
                case .failure(let error):
                    throw error
                case .none:
                    throw C2PAError.api("HTTP resolver produced no response")
                }
            })
    }

    deinit { _ = c2pa_free(ptr) }

    /// Requests cancellation of any in-progress signing or reading operation
    /// running on this context.
    ///
    /// - Throws: ``C2PAError`` if the cancellation request fails.
    public func cancel() throws {
        guard c2pa_context_cancel(ptr) == 0 else {
            throw C2PAError.api(lastC2PAError())
        }
    }
}
