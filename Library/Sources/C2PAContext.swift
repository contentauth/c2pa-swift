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

private final class ProgressCallbackBox: Sendable {
    let onProgress: @Sendable (ProgressUpdate) -> Void

    init(_ onProgress: @escaping @Sendable (ProgressUpdate) -> Void) {
        self.onProgress = onProgress
    }
}

private final class HTTPResolverBox: Sendable {
    let resolve: @Sendable (HTTPRequest) throws -> HTTPResponse

    init(_ resolve: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse) {
        self.resolve = resolve
    }
}

/// `ProgressCCallback` returns non-zero to continue the operation and zero to cancel.
private let progressContinue: Int32 = 1

/// `C2paHttpResolverCallback` returns zero for success and non-zero for failure, the opposite
/// polarity to ``progressContinue``. The two trampolines sit side by side, so both use names
/// rather than bare literals: `1` means "carry on" in one and "gave up" in the other.
private let resolverSucceeded: Int32 = 0
private let resolverFailed: Int32 = 1

/// Observes progress and always continues; cancellation is via ``C2PAContext/cancel()``.
private let progressTrampoline: ProgressCCallback = { context, phase, step, total in
    guard let context else { return progressContinue }
    let box = Unmanaged<ProgressCallbackBox>.fromOpaque(context).takeUnretainedValue()
    box.onProgress(ProgressUpdate(phase: ProgressPhase(phase), step: step, total: total))
    return progressContinue
}

/// Resolves one request. May run on any thread, which is why the boxed closure is `@Sendable`.
///
/// Returning non-zero signals failure, and the contract requires setting the error message
/// first: the native side reads it on this same thread as soon as the callback returns.
private let httpResolverTrampoline: C2paHttpResolverCallback = { context, request, response in
    guard let context, let request, let response else {
        setLastC2PAError("NullParameter: HTTP resolver received a null pointer")
        return resolverFailed
    }
    let box = Unmanaged<HTTPResolverBox>.fromOpaque(context).takeUnretainedValue()
    let incoming = request.pointee

    guard let urlPtr = incoming.url, let url = URL(string: String(cString: urlPtr)) else {
        setLastC2PAError("Other: invalid HTTP request URL")
        return resolverFailed
    }

    // The native side always sends a method, so this refuses rather than guessing: a silent
    // fallback to GET would turn a POST (OCSP, timestamping) into a request the server
    // rejects, surfacing far from the cause.
    guard let methodPtr = incoming.method else {
        setLastC2PAError("NullParameter: HTTP request has no method")
        return resolverFailed
    }
    let method = String(cString: methodPtr)
    var headers: [String: String] = [:]
    if let rawHeaders = incoming.headers {
        for line in String(cString: rawHeaders).split(separator: "\n") {
            guard let separator = line.firstIndex(of: ":") else { continue }
            // Newlines are in the trim set too: the C layer documents "\n"-delimited headers,
            // but CRLF would otherwise leave a trailing "\r" on every value.
            let name = String(line[..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { headers[name] = value }
        }
    }
    let body: Data? = incoming.body.flatMap { bytes in
        incoming.body_len > 0 ? Data(bytes: bytes, count: Int(incoming.body_len)) : nil
    }

    do {
        let result = try box.resolve(
            HTTPRequest(url: url, method: method, headers: headers, body: body))
        // Int32(_:) would trap here, killing the process from inside a C callback where no
        // Swift frame can catch it. The status is caller-supplied, so refuse it instead.
        guard let status = Int32(exactly: result.status) else {
            setLastC2PAError("Other: HTTP response status \(result.status) is out of range")
            return resolverFailed
        }
        response.pointee.status = status
        if result.body.isEmpty {
            // Both fields must move together. Rust skips its free when body_len is zero, so a
            // non-null pointer paired with a zero length would leak the allocation.
            response.pointee.body = nil
            response.pointee.body_len = 0
        } else {
            // Rust takes ownership of this allocation and frees it.
            guard let buffer = malloc(result.body.count)?.assumingMemoryBound(to: UInt8.self) else {
                setLastC2PAError("Other: failed to allocate the HTTP response body")
                return resolverFailed
            }
            result.body.copyBytes(to: buffer, count: result.body.count)
            response.pointee.body = buffer
            response.pointee.body_len = UInt(result.body.count)
        }
        return resolverSucceeded
    } catch {
        setLastC2PAError("Other: \(error.localizedDescription)")
        return resolverFailed
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
    ///   - onProgress: Observes operation progress. Called synchronously at checkpoints,
    ///     on whichever thread runs the operation; to stop an operation call ``cancel()``
    ///     rather than returning from here.
    ///   - httpResolver: Resolves HTTP requests the SDK makes (remote manifests, OCSP,
    ///     timestamps). Called synchronously and possibly from any thread, so it must be
    ///     thread-safe; the `@Sendable` requirement enforces that under strict
    ///     concurrency checking. Throwing fails the request.
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
        onProgress: (@Sendable (ProgressUpdate) -> Void)? = nil,
        httpResolver: (@Sendable (HTTPRequest) throws -> HTTPResponse)? = nil
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
                    // Ownership passes only once the native call's own pointer checks have
                    // passed, so a failure here means the resolver was not taken and is ours
                    // to release. Note the header states consumption unconditionally, which is
                    // stricter than the implementation: verified against c2pa-c-ffi-v0.90.0,
                    // and worth re-checking whenever C2PA_VERSION moves.
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
    /// Each request blocks the calling thread until the session's completion handler
    /// fires. That cannot deadlock against a session using the default delegate queue,
    /// but a session created with `delegateQueue: .main` (or whose delegate does work on
    /// the main thread) will deadlock if the operation runs on the main thread. Pass a
    /// session whose delegate queue is a background queue.
    ///
    /// A session delivering on `OperationQueue.main` is rejected here rather than left to
    /// hang at first use. A delegate that merely hops to the main thread itself cannot be
    /// detected, so the caller still owns that half of the requirement.
    ///
    /// - Parameters:
    ///   - settings: The ``C2PASettings`` to configure this context with.
    ///   - onProgress: Observes operation progress. See ``init(settings:onProgress:httpResolver:)``.
    ///   - urlSession: The session used to perform each request. Must not deliver its
    ///     callbacks on the main queue, and must stay valid for as long as this context
    ///     does: an invalidated session hands back tasks whose completion handler never
    ///     runs, which would block a resolving thread indefinitely. Request timeouts are
    ///     taken from the session's own configuration; nothing is imposed on top.
    ///
    /// - Throws: ``C2PAError`` if `urlSession` delivers on the main queue, or if the context
    ///   cannot be created.
    public convenience init(
        settings: C2PASettings? = nil,
        onProgress: (@Sendable (ProgressUpdate) -> Void)? = nil,
        urlSession: URLSession
    ) throws {
        guard urlSession.delegateQueue !== OperationQueue.main else {
            throw C2PAError.api(
                "URLSession delivers on the main queue, which would deadlock the resolver")
        }
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
                //
                // The wait is deliberately unbounded. Timeout policy belongs to the caller's
                // URLSessionConfiguration, which already carries both knobs, and this has no
                // basis for overriding them: timeoutIntervalForRequest is an idle timeout, so
                // a slow but progressing transfer legitimately outlives it.
                //
                // The signal/wait pair orders every access to `result`, which is what makes
                // the unchecked capture below sound.
                let semaphore = DispatchSemaphore(value: 0)
                nonisolated(unsafe) var result: Result<HTTPResponse, Error>?
                let task = urlSession.dataTask(with: urlRequest) { data, response, error in
                    if let error {
                        result = .failure(
                            C2PAError.api("HTTP resolver request failed: \(error)"))
                    } else if let http = response as? HTTPURLResponse {
                        result = .success(HTTPResponse(
                            status: http.statusCode, body: data ?? Data()))
                    } else {
                        // Every request the SDK makes here is HTTP. Reporting status 0 for
                        // anything else would look like a successful fetch of nothing.
                        result = .failure(C2PAError.api(
                            "HTTP resolver got a non-HTTP response for \(request.url)"))
                    }
                    semaphore.signal()
                }
                task.resume()
                semaphore.wait()

                // Unreachable: the semaphore is only signalled after `result` is set. Present
                // because the compiler cannot see that.
                guard let result else {
                    throw C2PAError.api("HTTP resolver produced no response")
                }
                return try result.get()
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
