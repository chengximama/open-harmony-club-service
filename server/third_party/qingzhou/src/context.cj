package qingzhou

import std.collection.*
import std.time.*
import std.convert.*
import stdx.net.http.*
import stdx.encoding.json.*

/*
 * SPDX-License-Identifier: MIT
 *
 * QingZhou - Context.
 *
 * Copyright (c) 2026 guowei
 * BIT Foundational Software And Systems Lab
 *
 * trace + state + path()/method() read-only proxy to stdx HttpContext.
 * chainable response tools (status/body/header/json) buffered into ctx;
 *      commit() at the end of the chain writes them to responseBuilder.
 *      Error channel (throw_err / err()) for the framework error chain.
 * params: HashMap for router-extracted path params; param(name) reader.
 * lazy body access (bodyBytes/body), JSON (bodyJson) and form (bodyForm)
 *      with internal caches so InputStream is consumed exactly once.
 *      contentType() with parameter stripping.
 *      cookies sub-object (Cookie: get + Set-Cookie: set).
 */
public class Context {
    private let traces: ArrayList<String> = ArrayList<String>()
    private let _headers: HashMap<String, String> = HashMap<String, String>()
    private let _params: HashMap<String, String> = HashMap<String, String>()

    /* mutable state shared across middlewares (analog to Koa ctx.state).
     * v0.2: structured as HashMap<String,String> so middlewares can pass
     * multiple fields (e.g. username + userId + role) instead of a single
     * string. Use setState/getState/getStateOr for ergonomic access. */
    public var state: HashMap<String, String> = HashMap<String, String>()

    /* v0.2: multipart 解析结果（由 multipart() 中间件填充）。 */
    private var _multipartParts: ?ArrayList<MultipartPart> = None

    /* response buffer; default: 200 + "" */
    public var _statusCode: Int64 = 200
    public var _body: String = ""

    /* error channel */
    public var _err: ?Exception = None

    /* committed flag to avoid double-commit */
    public var _committed: Bool = false

    /* request id (set by requestId() middleware; empty if none) */
    public var _id: String = ""

    /* timeout bookkeeping. _startMonotonic captures MonoTime.now()
     * at the start of the chain (set by timeout() middleware). We use
     * MonoTime rather than DateTime because it is monotonic -- immune
     * to wall-clock jumps (NTP adjustments, manual clock changes)
     * which would otherwise cause timeout misfires. */
    public var _startMonotonic: ?MonoTime = None
    public var _timeoutMs: Int64 = 0

    public let http: ?HttpContext
    public var cookies: Cookies = Cookies()  // re-bound in init via _attachCookies

    /* body caches (so InputStream is read once) */
    private var _rawBodyBytes: ?Array<UInt8> = None
    private var _bodyJsonParsed: Bool = false
    private var _bodyJsonValue: ?JsonValue = None
    private var _bodyJsonError: ?Exception = None
    private var _bodyFormParsed: Bool = false
    private var _bodyFormValue: HashMap<String, String> = HashMap<String, String>()

    /* response body kind selector. _bodyKind = 0 -> use _body (String);
     *  _bodyKind = 1 -> use _bodyBytes (raw). Decides commit() dispatch. */
    private var _bodyKind: Int64 = 0
    private var _bodyBytes: Array<UInt8> = Array<UInt8>()

    public init() {
        http = None
        _attachCookies()
    }

    public init(httpCtx: HttpContext) {
        http = Some(httpCtx)
        _attachCookies()
    }

    /*
     * Late-binding for cookies. We declare `cookies: Cookies` as `var`
     * because Cangjie forbids `this` in `init` before all fields are
     * initialised, and Cookies needs a back-reference to this Context.
     * The placeholder default (Cookies()) is rebound here.
     */
    private func _attachCookies(): Unit {
        cookies.rebind(this)
    }

    /* ---------- params ---------- */
    public func setParam(k: String, v: String): Unit {
        _params[k] = v
    }

    public func param(name: String): ?String {
        return _params.get(name)
    }

    public func paramOr(name: String, default_: String): String {
        return match (_params.get(name)) {
            case Some(v) => v
            case None => default_
        }
    }

    public func _peekParams(): HashMap<String, String> {
        return _params
    }

    /* ---------- state bag (v0.2) ---------- */
    public func setState(k: String, v: String): Context {
        state[k] = v
        return this
    }

    public func getState(k: String): ?String {
        return state.get(k)
    }

    public func getStateOr(k: String, default_: String): String {
        return match (state.get(k)) {
            case Some(v) => v
            case None => default_
        }
    }

    /* ---------- multipart (v0.2) ---------- */
    public func setMultipartParts(parts: ArrayList<MultipartPart>): Unit {
        _multipartParts = Some(parts)
    }

    public func multipartParts(): ArrayList<MultipartPart> {
        return match (_multipartParts) {
            case Some(p) => p
            case None => ArrayList<MultipartPart>()
        }
    }

    /* ---------- tracing ---------- */
    public func trace(tag: String): Unit {
        traces.add(tag)
    }

    public func dump(): String {
        return String.join(traces.toArray(), delimiter: " -> ")
    }

    /* ---------- request proxy ---------- */
    public func path(): String {
        match (http) {
            case Some(h) => h.request.url.path
            case None => ""
        }
    }

    public func method(): String {
        match (http) {
            case Some(h) => h.request.method
            case None => ""
        }
    }

    /*
     * 客户端地址（stdx HttpRequest.remoteAddr，格式 "ip:port"）。
     * 无 http ctx 时返回 ""。限流等场景可用 remoteIp() 取纯 IP。
     */
    public func remoteAddr(): String {
        match (http) {
            case Some(h) => h.request.remoteAddr
            case None => ""
        }
    }

    /*
     * 客户端 IP（从 "ip:port" 中剥离端口）。处理可能的 "ip: port" 空格
     * 与 IPv6（取最后一个 ':' 之前的部分）。无地址时返回 ""。
     */
    public func remoteIp(): String {
        let addr = remoteAddr()
        match (addr.lastIndexOf(":")) {
            case Some(i) => return addr[0..i].trimAscii()
            case None => return addr.trimAscii()
        }
    }

    /* ---------- query string (v0.2 P1) ---------- */

    /*
     * Raw query string (everything after the first '?'), without the
     * leading '?'. Empty when absent / no http ctx.
     */
    public func query(): String {
        match (http) {
            case Some(h) =>
                match (h.request.url.query) {
                    case Some(q) => q
                    case None => ""
                }
            case None => ""
        }
    }

    /*
     * First value of a query parameter, URL-decoded. Returns None when
     * the parameter is absent. (Last-write-wins semantics match bodyForm.)
     */
    public func queryParam(name: String): ?String {
        let q = query()
        if (q.size == 0) {
            return None
        }
        var found: ?String = None
        for (pair in q.split("&", -1, removeEmpty: true)) {
            let kv = pair.split("=", 2, removeEmpty: false)
            if (kv[0] == name) {
                found = Some(if (kv.size > 1) { urlDecode(kv[1]) } else { "" })
            }
        }
        return found
    }

    public func queryParamOr(name: String, default_: String): String {
        return match (queryParam(name)) {
            case Some(v) => v
            case None => default_
        }
    }

    /* All query parameters as a map (URL-decoded, last write wins). */
    public func queryParams(): HashMap<String, String> {
        let m = HashMap<String, String>()
        let q = query()
        if (q.size == 0) {
            return m
        }
        for (pair in q.split("&", -1, removeEmpty: true)) {
            let kv = pair.split("=", 2, removeEmpty: false)
            let k = urlDecode(kv[0])
            let v = if (kv.size > 1) { urlDecode(kv[1]) } else { "" }
            m[k] = v
        }
        return m
    }

    /* ---------- chainable response tools (Koa style) ---------- */
    public func status(code: Int64): Context {
        _statusCode = code
        return this
    }

    public func body(s: String): Context {
        _body = s
        _bodyKind = 0
        return this
    }

    /*
     * write a raw byte response body (images, video, arbitrary
     * binary). Sets _bodyKind = 1 so commit() sends bytes instead of
     * the String body even if body(s) was called earlier.
     */
    public func body(bytes: Array<UInt8>): Context {
        _bodyBytes = bytes
        _bodyKind = 1
        return this
    }

    public func header(k: String, v: String): Context {
        _headers[k] = v
        return this
    }

    public func json(payload: String): Context {
        _headers["content-type"] = "application/json; charset=utf-8"
        _body = payload
        return this
    }

    /* ---------- error channel ---------- */
    public func throw_err(e: Exception): Unit {
        _err = Some(e)
    }

    public func err(): ?Exception {
        return _err
    }

    /* ---------- body ---------- */

    /*
     * Raw request body bytes. Lazy: consumes the underlying InputStream
     * on first call and caches the result for the lifetime of this ctx.
     * Returns empty array when the request has no body or no http ctx.
     */
    public func bodyBytes(): Array<UInt8> {
        match (_rawBodyBytes) {
            case Some(b) => return b
            case None => ()
        }
        let buf = ArrayList<UInt8>()
        match (http) {
            case Some(h) =>
                let bs = h.request.body
                var loop = true
                while (loop) {
                    let chunk = Array<UInt8>(1024, { _ => UInt8(0) })
                    let n = try { bs.read(chunk) } catch (e: Exception) { Int64(0) }
                    if (n <= 0) {
                        loop = false
                    } else {
                        for (i in 0..n) {
                            buf.add(chunk[i])
                        }
                        if (n < 1024) {
                            loop = false
                        }
                    }
                }
            case None => ()
        }
        let arr = buf.toArray()
        _rawBodyBytes = Some(arr)
        return arr
    }

    public func body(): String {
        return String.fromUtf8(bodyBytes())
    }

    /*
     * Parse the body as JSON. Returns the JsonValue or None when the
     * body is empty / not JSON / parse errored. The parsed value is
     * cached.
     *
     * Callers who want to distinguish "no body" from "bad JSON" can
     * branch on body().isEmpty() first.
     */
    public func bodyJson(): ?JsonValue {
        if (_bodyJsonParsed) {
            return _bodyJsonValue
        }
        _bodyJsonParsed = true
        let raw = body()
        if (raw.size == 0) {
            _bodyJsonValue = None
            return None
        }
        try {
            _bodyJsonValue = Some(JsonValue.fromStr(raw))
            return _bodyJsonValue
        } catch (e: Exception) {
            _bodyJsonError = Some(e)
            _bodyJsonValue = None
            return None
        }
    }

    /*
     * Last JSON parse error (or None if parse succeeded / no body).
     * Useful for surfacing 400 messages.
     */
    public func bodyJsonError(): ?Exception {
        // Ensure parsed so the error is materialised
        let _ = bodyJson()
        return _bodyJsonError
    }

    /*
     * Parse the body as application/x-www-form-urlencoded.
     * Last write wins on duplicate keys (Koa behaviour).
     */
    public func bodyForm(): HashMap<String, String> {
        if (_bodyFormParsed) {
            return _bodyFormValue
        }
        _bodyFormParsed = true
        let raw = body()
        if (raw.size > 0) {
            for (pair in raw.split("&", -1, removeEmpty: true)) {
                // maxSplits is the maximum number of PIECES (not splits),
                // so 2 = one split at the first '='. Values containing '='
                // (rare but valid) survive intact in kv[1].
                let kv = pair.split("=", 2, removeEmpty: false)
                let k = urlDecode(kv[0])
                let v = if (kv.size > 1) { urlDecode(kv[1]) } else { "" }
                _bodyFormValue[k] = v
            }
        }
        return _bodyFormValue
    }

    /*
     * Content-Type without parameters (e.g. "application/json").
     * Empty string when absent / no http ctx.
     */
    public func contentType(): String {
        match (http) {
            case Some(h) =>
                for (entry in h.request.headers) {
                    if (entry[0].toAsciiLower() == "content-type") {
                        for (v in entry[1]) {
                            let stripped = stripContentTypeParams(v)
                            return stripped
                        }
                    }
                }
            case None => ()
        }
        return ""
    }

    /*
     * read a request header by name. Case-insensitive on the
     * lookup key (HTTP headers are case-insensitive). Returns the
     * first value associated with the header, or None when the header
     * is absent or there is no http ctx.
     *
     * Used by static.cj for Range: / If-None-Match: lookup.
     */
    public func requestHeader(name: String): ?String {
        let want = name.toAsciiLower()
        match (http) {
            case Some(h) =>
                for (entry in h.request.headers) {
                    if (entry[0].toAsciiLower() == want) {
                        for (v in entry[1]) {
                            return Some(v)
                        }
                    }
                }
            case None => ()
        }
        return None
    }

    /* ---------- commit ---------- */
    /*
     * Write buffered response to the underlying HttpContext.
     * Idempotent and safe to call multiple times (only first takes effect).
     */
    public func commit(): Unit {
        if (_committed) {
            return
        }
        _committed = true
        match (http) {
            case Some(h) =>
                // StdResponse expects UInt16 status code
                let code: UInt16 = UInt16(_statusCode)
                var b = h.responseBuilder.status(code)
                for ((k, v) in _headers) {
                    b = b.header(k, v)
                }
                // : bytes take priority over the String body. CRITICAL:
                // stdx's response builder is immutable-chain style; the
                // result of body(...) MUST be reassigned back into b or
                // the body change is lost. (We hit this exact bug at the
                // end of  verification: content-length 0 because the
                // b.body(bytes) value was discarded.)
                b = if (_bodyKind == 1 && _bodyBytes.size > 0) {
                    b.body(_bodyBytes)
                } else {
                    b.body(_body)
                }
            case None => ()
        }
    }

    /* ---------- self-test helpers ---------- */
    public func _peekStatus(): Int64 { return _statusCode }
    public func _peekBody(): String { return _body }
    public func _peekHeaders(): HashMap<String, String> { return _headers }
    public func _peekRawBody(): Array<UInt8> { return bodyBytes() }
    public func _peekBodyJsonParsed(): Bool { return _bodyJsonParsed }
    public func _peekBodyFormParsed(): Bool { return _bodyFormParsed }
    /*  test helpers */
    public func _peekBodyKind(): Int64 { return _bodyKind }
    public func _peekBodyBytes(): Array<UInt8> { return _bodyBytes }

    /*
     * Read the current response body as bytes, regardless of whether it
     * was set via body(String) or body(Array<UInt8>). String bodies are
     * encoded as UTF-8. Used by the compress middleware.
     */
    public func _bodyAsBytes(): Array<UInt8> {
        if (_bodyKind == 1 && _bodyBytes.size > 0) {
            return _bodyBytes
        }
        return _body.toArray()
    }
}

/*
 * Strip "; charset=utf-8" etc. from a Content-Type header value.
 * Returns the trimmed media type (case preserved as the header was).
 * maxSplits=2 means "up to two pieces": the type + everything after
 * the first ';' (which we discard).
 */
func stripContentTypeParams(v: String): String {
    let parts = v.split(";", 2, removeEmpty: false)
    return parts[0].trimAscii()
}

/*
 * application/x-www-form-urlencoded decoder.
 *   +      -> space
 *   %XX    -> hex byte
 *
 * We accumulate raw bytes (no per-char String conversions) and run
 * String.fromUtf8 once at the end so multi-byte UTF-8 sequences
 * (e.g. %E4%B8%AD%E6%96%87 -> "中文") decode correctly. Earlier we tried
 * to call c.toString() / fromUtf8 per byte, which both wasted work and
 * produced "Invalid utf8 byte sequence" for non-ASCII input.
 *
 * stdx.encoding.url in 1.0.5.1 does not export a free-form URL decode
 * function (only the URL class itself), so we hand-roll it here.
 */
func urlDecode(s: String): String {
    let outBytes = ArrayList<UInt8>()
    var i: Int64 = 0
    let n = s.size
    while (i < n) {
        let c = s[i]
        if (c == UInt8(0x2B)) {            // '+'
            outBytes.add(UInt8(0x20))
            i += 1
        } else if (c == UInt8(0x25) && i + 2 < n) {  // '%XX'
            let hi = hexNibble(s[i + 1])
            let lo = hexNibble(s[i + 2])
            match (hi) {
                case Some(hv) =>
                    match (lo) {
                        case Some(lv) =>
                            outBytes.add(UInt8((hv << 4) | lv))
                            i += 3
                        case None =>
                            outBytes.add(c)
                            i += 1
                    }
                case None =>
                    outBytes.add(c)
                    i += 1
            }
        } else {
            outBytes.add(c)
            i += 1
        }
    }
    return String.fromUtf8(outBytes.toArray())
}

func hexNibble(c: UInt8): ?Int64 {
    if (c >= UInt8(0x30) && c <= UInt8(0x39)) {       // 0..9
        return Some(Int64(c) - 0x30)
    }
    if (c >= UInt8(0x41) && c <= UInt8(0x46)) {       // A..F
        return Some(Int64(c) - 0x41 + 10)
    }
    if (c >= UInt8(0x61) && c <= UInt8(0x66)) {       // a..f
        return Some(Int64(c) - 0x61 + 10)
    }
    return None
}