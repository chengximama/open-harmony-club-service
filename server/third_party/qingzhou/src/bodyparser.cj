package qingzhou

import std.collection.*

/*
 * SPDX-License-Identifier: MIT
 *
 * QingZhou - bodyParser middleware.
 *
 * Copyright (c) 2026 guowei
 * BIT Foundational Software And Systems Lab
 *
 * Wraps 's lazy body access (bodyJson / bodyForm / body) so that
 *   - The request body is read exactly once and cached (already true
 *     by construction in Context, but bodyParser additionally enforces
 *     a size limit up-front).
 *   - An unparseable JSON body yields 400 with a clear error rather than
 *     a silent None at bodyJson().
 *   - Unsupported Content-Types are passed through untouched, so the
 *     user can mount a separate multipart handler later.
 *
 * Recognised Content-Types (after parameter stripping):
 *   application/json                       -> ctx.bodyJson() is materialised
 *   application/x-www-form-urlencoded      -> ctx.bodyForm() is materialised
 *   text/<subtype>                         -> ctx.body() is materialised
 *   anything else                          -> no-op, downstream sees raw ctx
 *
 * Note: we deliberately do not consume the body for unrecognised types
 * so that streamable parsers (multipart, graphql-over-http-ws upgrades,
 * etc.) can still operate on ctx.request.body in the future.
 */

public class BodyParserOptions {
    /* Hard cap on the raw body in bytes. 1 MiB matches koa-bodyparser's
     * default jsonLimit when given as a string. */
    public var maxBytes: Int64 = 1024 * 1024

    /* Custom error reporter. Reassignable to plug a JSON-error format
     * or to send HTML error pages. */
    public var onError: (Context, Int64, String) -> Unit = defaultBodyParserError

    public init() {}
}

/*
 * Default error reporter: emits a small JSON object. Matches Koa's
 * upstream koa-bodyparser behaviour for unparseable bodies.
 */
public func defaultBodyParserError(ctx: Context, status: Int64, msg: String): Unit {
    ctx.status(status)
        .header("content-type", "application/json; charset=utf-8")
        .body("{\"error\":\"${escapeJsonString(msg)}\"}")
}

/* Convenience: bodyParser() with defaults. */
public func bodyParser(): Middleware {
    return bodyParser(BodyParserOptions())
}

public func bodyParser(opts: BodyParserOptions): Middleware {
    return { ctx: Context, next: () -> Unit =>
        let ct = ctx.contentType()
        // Branch on Content-Type. Unsupported types fall through so a
        // user-mounted multipart/raw handler can deal with them.
        // On an error the parser short-circuits (responds itself) and
        // does NOT call next(), so the error response is final.
        if (ct == "application/json") {
            if (!handleJson(ctx, opts)) {
                return
            }
        } else if (ct == "application/x-www-form-urlencoded") {
            if (!handleForm(ctx, opts)) {
                return
            }
        } else if (ct.startsWith("text/")) {
            if (!handleText(ctx, opts)) {
                return
            }
        }
        // Anything else: pass through. Don't pre-consume the stream.
        next()
    }
}

/* Internal: enforce size + parse JSON. Returns false when the error
 * reporter has taken over the response (caller must not call next). */
func handleJson(ctx: Context, opts: BodyParserOptions): Bool {
    // bodyJson() triggers the raw read + cache.
    let _ = ctx.bodyJson()
    let raw = ctx._peekRawBody()
    if (raw.size > opts.maxBytes) {
        opts.onError(ctx, 413, "Request body too large")
        return false
    }
    match (ctx.bodyJsonError()) {
        case Some(_) =>
            // bodyJsonError returned Some when raw was non-empty and parsing failed.
            if (raw.size > 0) {
                opts.onError(ctx, 400, "Invalid JSON body")
                return false
            }
            // raw.size == 0 -> empty JSON body is acceptable; treat as null.
        case None => ()
    }
    return true
}

func handleForm(ctx: Context, opts: BodyParserOptions): Bool {
    // bodyForm() triggers the raw read + cache + split.
    let m = ctx.bodyForm()
    let raw = ctx._peekRawBody()
    if (raw.size > opts.maxBytes) {
        opts.onError(ctx, 413, "Request body too large")
        return false
    }
    // Discard the unused map; the side effect of populating the cache
    // is what we wanted. (m is referenced so the optimiser keeps it.)
    let _ = m.size
    return true
}

func handleText(ctx: Context, opts: BodyParserOptions): Bool {
    let s = ctx.body()
    let raw = ctx._peekRawBody()
    if (raw.size > opts.maxBytes) {
        opts.onError(ctx, 413, "Request body too large")
        return false
    }
    let _ = s.size
    return true
}

/*
 * Minimal JSON string escape: backslash, double-quote, control chars
 * (< 0x20). Used by the default error reporter so messages stay valid
 * JSON. Not a general-purpose JSON encoder -- just safe enough for the
 * error path where the input is a fixed set of canned messages plus
 * whatever exception.message the user throws.
 */
func escapeJsonString(s: String): String {
    let out = ArrayList<UInt8>()
    var i: Int64 = 0
    let n = s.size
    while (i < n) {
        let c = s[i]
        if (c == UInt8(0x5C)) {              // backslash
            out.add(UInt8(0x5C))
            out.add(UInt8(0x5C))
        } else if (c == UInt8(0x22)) {       // double quote
            out.add(UInt8(0x5C))
            out.add(UInt8(0x22))
        } else if (c < UInt8(0x20)) {        // control chars
            out.add(UInt8(0x5C))
            out.add(UInt8(0x75))             // 'u'
            out.add(UInt8(0x30))
            out.add(UInt8(0x30))
            out.add(UInt8(0x30) + UInt8((Int64(c) >> 4) & 0x0F))
            out.add(UInt8(0x30) + UInt8(Int64(c) & 0x0F))
        } else {
            out.add(c)
        }
        i += 1
    }
    return String.fromUtf8(out.toArray())
}