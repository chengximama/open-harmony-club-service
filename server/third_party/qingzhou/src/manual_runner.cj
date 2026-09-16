package qingzhou

import std.collection.*
import stdx.encoding.json.*
import stdx.crypto.x509.*
import stdx.crypto.keys.*

// 已运行的场景总数（动态计数，避免与 @Test 版场景数硬编码不同步）
var g_total: Int64 = 0

/*
 * SPDX-License-Identifier: MIT
 *
 * Manual runner used by `qingzhou.exe test`.
 * Re-executes each unit-test scenario without @Test / @Expect macros so that
 * the same scenarios stay runnable under cjc-direct builds (where cjpm test
 * may be unstable on Windows).
 *
 * Each scenario must throw to fail; the runner converts that to a FAIL line.
 */
public func runAllUnitTests(): Int64 {
    var failed: Int64 = 0

    failed += runCase("compose_single_mw_runs", { =>
        let stack = ArrayList<Middleware>()
        stack.add({ ctx: Context, _: () -> Unit =>
            ctx.trace("only")
        })
        let ctx = Context()
        compose(stack)(ctx)
        checkEq(ctx.dump(), "only")
    })

    failed += runCase("compose_order_is_onion", { =>
        let stack = ArrayList<Middleware>()
        stack.add({ ctx: Context, next: () -> Unit =>
            ctx.trace("a-in"); next(); ctx.trace("a-out")
        })
        stack.add({ ctx: Context, next: () -> Unit =>
            ctx.trace("b-in"); next(); ctx.trace("b-out")
        })
        stack.add({ ctx: Context, _: () -> Unit =>
            ctx.trace("h")
        })
        let ctx = Context()
        compose(stack)(ctx)
        checkEq(ctx.dump(), "a-in -> b-in -> h -> b-out -> a-out")
    })

    failed += runCase("compose_skipped_next_still_safe", { =>
        // koa-compose semantics: dispatch advances unconditionally;
        // a middleware that ignores `next` is still invoked once,
        // then returns to the caller. No crash, no infinite loop.
        let stack = ArrayList<Middleware>()
        stack.add({ ctx: Context, next: () -> Unit =>
            ctx.trace("before"); next(); ctx.trace("after")
        })
        stack.add({ ctx: Context, _: () -> Unit =>
            ctx.trace("skipped")
        })
        let ctx = Context()
        compose(stack)(ctx)
        checkEq(ctx.dump(), "before -> skipped -> after")
    })

    failed += runCase("context_default_response_is_200_empty", { =>
        let ctx = Context()
        checkEq(ctx._peekStatus(), 200)
        checkEq(ctx._peekBody(), "")
    })

    failed += runCase("context_chainable_status_body_header", { =>
        let ctx = Context()
        ctx.status(201).body("hi").header("x", "y")
        checkEq(ctx._peekStatus(), 201)
        checkEq(ctx._peekBody(), "hi")
        checkEq(ctx._peekHeaders()["x"], "y")
    })

    failed += runCase("context_json_sets_content_type", { =>
        let ctx = Context()
        ctx.json("{\"ok\":true}")
        checkEq(ctx._peekHeaders()["content-type"], "application/json; charset=utf-8")
        checkEq(ctx._peekBody(), "{\"ok\":true}")
    })

    failed += runCase("apphandler_default_500_when_no_error_mw", { =>
        let stack = ArrayList<Middleware>()
        stack.add({ ctx: Context, _: () -> Unit =>
            throw Boom2()
        })
        let h = AppHandler(stack, ArrayList<Middleware>())
        let ctx = Context()
        h.handle(ctx)
        checkEq(ctx._peekStatus(), 500)
        checkEq(ctx._peekBody(), "Internal Error: boom!")
    })

    failed += runCase("apphandler_invokes_error_chain_and_preserves_status", { =>
        let stack = ArrayList<Middleware>()
        stack.add({ ctx: Context, _: () -> Unit =>
            throw Boom2()
        })
        let errStack = ArrayList<Middleware>()
        errStack.add({ ctx: Context, _: () -> Unit =>
            ctx.status(418).body("teapot")
        })
        let h = AppHandler(stack, errStack)
        let ctx = Context()
        h.handle(ctx)
        checkEq(ctx._peekStatus(), 418)
        checkEq(ctx._peekBody(), "teapot")
        checkTrue(ctx.err().isSome())
    })

    failed += runCase("apphandler_commit_idempotent_default_200", { =>
        let stack = ArrayList<Middleware>()
        stack.add({ ctx: Context, _: () -> Unit => () })
        let h = AppHandler(stack, ArrayList<Middleware>())
        let ctx = Context()
        h.handle(ctx)
        checkEq(ctx._peekStatus(), 200)
    })

    // ============  Router scenarios ============

    failed += runCase("router_static_match", { =>
        let r = Router().get("/users", { ctx, _ => () })
        let ctx = Context()
        let res = r.lookup("GET", "/users", ctx)
        checkTrue(match (res) { case DispatchResult.Matched(_) => true; case _ => false })
    })

    failed += runCase("router_param_match_injects_param", { =>
        let r = Router().get("/users/:id", { ctx, _ => () })
        let ctx = Context()
        let _ = r.lookup("GET", "/users/42", ctx)
        checkEq(ctx.paramOr("id", ""), "42")
    })

    failed += runCase("router_multi_param", { =>
        let r = Router().get("/users/:uid/posts/:pid", { ctx, _ => () })
        let ctx = Context()
        let _ = r.lookup("GET", "/users/7/posts/99", ctx)
        checkEq(ctx.paramOr("uid", ""), "7")
        checkEq(ctx.paramOr("pid", ""), "99")
    })

    failed += runCase("router_wildcard_captures_tail", { =>
        let r = Router().get("/files/*", { ctx, _ => () })
        let ctx = Context()
        let _ = r.lookup("GET", "/files/a/b/c.txt", ctx)
        checkEq(ctx.paramOr("tail", ""), "a/b/c.txt")
    })

    failed += runCase("router_not_found", { =>
        let r = Router().get("/users", { ctx, _ => () })
        let ctx = Context()
        let _ = r.lookup("GET", "/nope", ctx)
        checkEq(ctx._peekStatus(), 404)
    })

    failed += runCase("router_method_not_allowed_405_allow", { =>
        let r = Router().get("/hello", { ctx, _ => () })
        let ctx = Context()
        let _ = r.lookup("DELETE", "/hello", ctx)
        checkEq(ctx._peekStatus(), 405)
        checkEq(ctx._peekHeaders()["allow"], "GET")
    })

    failed += runCase("router_method_dispatch_same_path", { =>
        let r = Router()
            .get("/users", { ctx, _ => ctx.body("list") })
            .post("/users", { ctx, _ => ctx.body("create") })
        let gctx = Context()
        let gres = r.lookup("GET", "/users", gctx)
        checkTrue(match (gres) { case DispatchResult.Matched(_) => true; case _ => false })
        match (gres) {
            case DispatchResult.Matched(h) => h(gctx, { => () })
            case _ => ()
        }
        checkEq(gctx._peekBody(), "list")
        let pctx = Context()
        let pres = r.lookup("POST", "/users", pctx)
        match (pres) {
            case DispatchResult.Matched(h) => h(pctx, { => () })
            case _ => ()
        }
        checkEq(pctx._peekBody(), "create")
    })

    failed += runCase("router_static_priority_over_param", { =>
        let r = Router()
            .get("/users/me", { ctx, _ => ctx.body("me-static") })
            .get("/users/:id", { ctx, _ => ctx.body("me-param") })
        let ctx = Context()
        let res = r.lookup("GET", "/users/me", ctx)
        match (res) {
            case DispatchResult.Matched(h) => h(ctx, { => () })
            case _ => ()
        }
        checkEq(ctx._peekBody(), "me-static")
        checkTrue(ctx.param("id").isNone())
    })

    // ============  urldecode / cookies ============

    failed += runCase("urldecode_basic", { =>
        checkEq(urlDecode("hello"), "hello")
        checkEq(urlDecode("hello+world"), "hello world")
        checkEq(urlDecode("a%20b"), "a b")
    })

    failed += runCase("urldecode_percent_encoded_unicode", { =>
        checkEq(urlDecode("%E4%B8%AD%E6%96%87"), "中文")
    })

    failed += runCase("urldecode_invalid_percent_passes_through", { =>
        checkEq(urlDecode("abc%"), "abc%")
        checkEq(urlDecode("abc%ZZ"), "abc%ZZ")
    })

    failed += runCase("urldecode_empty", { =>
        checkEq(urlDecode(""), "")
    })

    failed += runCase("cookies_get_returns_none_without_http", { =>
        let ctx = Context()
        checkTrue(ctx.cookies.get("sid").isNone())
    })

    failed += runCase("cookies_set_writes_header", { =>
        let ctx = Context()
        ctx.cookies.set("sid", "abc123")
        // : legacy set() defaults to CookieOptions() -> adds Path=/
        checkEq(ctx._peekHeaders()["Set-Cookie"], "sid=abc123; Path=/")
    })

    failed += runCase("cookies_set_multiple_accumulates", { =>
        let ctx = Context()
        ctx.cookies.set("a", "1")
        ctx.cookies.set("b", "2")
        // stdx overwrites same-named headers; we accumulate into a
        // comma-separated single Set-Cookie line.  adds Path=/ to each.
        checkEq(ctx._peekHeaders()["Set-Cookie"], "a=1; Path=/, b=2; Path=/")
    })

    failed += runCase("context_body_bytes_empty_when_no_http", { =>
        let ctx = Context()
        checkEq(ctx.bodyBytes().size, 0)
        checkEq(ctx._peekRawBody().size, 0)
    })

    // ============  mimeOf ============

    failed += runCase("mime_known_image", { =>
        checkEq(mimeOf("a.png"), "image/png")
        checkEq(mimeOf("a.jpg"), "image/jpeg")
        checkEq(mimeOf("a.jpeg"), "image/jpeg")
        checkEq(mimeOf("a.gif"), "image/gif")
        checkEq(mimeOf("a.webp"), "image/webp")
        checkEq(mimeOf("a.svg"), "image/svg+xml")
    })

    failed += runCase("mime_known_video_audio_text", { =>
        checkEq(mimeOf("clip.mp4"), "video/mp4")
        checkEq(mimeOf("clip.webm"), "video/webm")
        checkEq(mimeOf("song.mp3"), "audio/mpeg")
        checkEq(mimeOf("page.html"), "text/html; charset=utf-8")
        checkEq(mimeOf("page.css"), "text/css; charset=utf-8")
        checkEq(mimeOf("page.js"), "application/javascript; charset=utf-8")
    })

    failed += runCase("mime_case_insensitive_and_fallback", { =>
        checkEq(mimeOf("PIC.PNG"), "image/png")
        checkEq(mimeOf("PIC.Jpeg"), "image/jpeg")
        checkEq(mimeOf("data.xyz123"), "application/octet-stream")
        checkEq(mimeOf("README"), "application/octet-stream")
        checkEq(mimeOf("foo."), "application/octet-stream")
        checkEq(mimeOf(".gitignore"), "application/octet-stream")
    })

    failed += runCase("mime_strips_dirs", { =>
        checkEq(mimeOf("path/to/pic.png"), "image/png")
        checkEq(mimeOf("v1.2/file"), "application/octet-stream")
    })

    // ============  Context binary body ============

    failed += runCase("context_body_bytes_kind_dispatch", { =>
        let ctx = Context()
        checkEq(ctx._peekBodyKind(), 0)
        ctx.body("hello")
        checkEq(ctx._peekBodyKind(), 0)
        let payload = Array<UInt8>(3, { i => UInt8(i + 1) })
        ctx.body(payload)
        checkEq(ctx._peekBodyKind(), 1)
        checkEq(ctx._peekBodyBytes().size, 3)
        ctx.body("goodbye")
        checkEq(ctx._peekBodyKind(), 0)
    })

    failed += runCase("context_body_bytes_overrides_text", { =>
        let ctx = Context()
        ctx.body("never sent")
        let payload = Array<UInt8>(5, { _ => UInt8(0xFF) })
        ctx.body(payload)
        checkEq(ctx._peekBodyKind(), 1)
    })

    // ============  hasTraversal ============

    failed += runCase("traversal_blocks_dotdot_segments", { =>
        checkTrue(hasTraversal("../etc/passwd"))
        checkTrue(hasTraversal("a/../../b"))
        checkTrue(hasTraversal("a/.."))
        checkTrue(hasTraversal(".."))
    })

    failed += runCase("traversal_blocks_backslashes", { =>
        checkTrue(hasTraversal("a\\b"))
        checkTrue(hasTraversal("\\foo"))
    })

    failed += runCase("traversal_allows_normal_paths", { =>
        checkTrue(!hasTraversal("a/b/c.png"))
        checkTrue(!hasTraversal("logo.svg"))
        checkTrue(!hasTraversal("path.with.dots/file"))
        checkTrue(!hasTraversal(""))
    })

    failed += runCase("mime_video_types_present", { =>
        checkEq(mimeOf("movie.mp4"), "video/mp4")
        checkEq(mimeOf("movie.mov"), "video/quicktime")
    })

    // ============  Range parser ============

    failed += runCase("range_closed_form", { =>
        let r = parseRange("bytes=0-499", 1000)
        checkTrue(match (r) { case RangeResult.Satisfiable(s) => s.start == 0 && s.end == 499; case _ => false })
    })

    failed += runCase("range_open_end", { =>
        let r = parseRange("bytes=500-", 1000)
        checkTrue(match (r) { case RangeResult.Satisfiable(s) => s.start == 500 && s.end == 999; case _ => false })
    })

    failed += runCase("range_suffix_form", { =>
        let r = parseRange("bytes=-500", 1000)
        checkTrue(match (r) { case RangeResult.Satisfiable(s) => s.start == 500 && s.end == 999; case _ => false })
        let r2 = parseRange("bytes=-1500", 1000)
        checkTrue(match (r2) { case RangeResult.Satisfiable(s) => s.start == 0 && s.end == 999; case _ => false })
    })

    failed += runCase("range_end_clipped_to_size", { =>
        let r = parseRange("bytes=0-9999", 1000)
        checkTrue(match (r) { case RangeResult.Satisfiable(s) => s.start == 0 && s.end == 999; case _ => false })
    })

    failed += runCase("range_unsatisfiable_start_past_end", { =>
        let r = parseRange("bytes=1000-", 1000)
        checkTrue(match (r) { case RangeResult.Unsatisfiable => true; case _ => false })
    })

    failed += runCase("range_malformed_reversed_bounds", { =>
        let r = parseRange("bytes=200-100", 1000)
        checkTrue(match (r) { case RangeResult.Malformed => true; case _ => false })
    })

    failed += runCase("range_malformed_multi_range", { =>
        let r = parseRange("bytes=0-100,200-300", 1000)
        checkTrue(match (r) { case RangeResult.Malformed => true; case _ => false })
    })

    failed += runCase("range_malformed_no_unit", { =>
        let r = parseRange("0-499", 1000)
        checkTrue(match (r) { case RangeResult.Malformed => true; case _ => false })
    })

    failed += runCase("range_zero_byte_resource", { =>
        let r = parseRange("bytes=0-0", 0)
        checkTrue(match (r) { case RangeResult.Unsatisfiable => true; case _ => false })
    })

    failed += runCase("range_length_helper", { =>
        let s = RangeSpec(10, 19)
        checkEq(s.length(), 10)
    })

    failed += runCase("format_content_range_normal", { =>
        let s = RangeSpec(0, 499)
        checkEq(formatContentRange(s, 1000), "bytes 0-499/1000")
    })

    failed += runCase("format_content_range_unsatisfiable", { =>
        checkEq(formatUnsatisfiableContentRange(1000), "bytes */1000")
    })

    // ============  ETag ============

    failed += runCase("etag_make_quoted_size", { =>
        checkEq(makeETag(0), "\"0\"")
        checkEq(makeETag(1024), "\"1024\"")
        checkEq(makeETag(123456789), "\"123456789\"")
    })

    failed += runCase("etag_matches_exact", { =>
        let et = makeETag(1024)
        checkTrue(etagMatches("\"1024\"", et))
    })

    failed += runCase("etag_matches_wildcard", { =>
        checkTrue(etagMatches("*", makeETag(1024)))
        checkTrue(etagMatches("  *  ", makeETag(7)))
    })

    failed += runCase("etag_matches_in_list", { =>
        let et = makeETag(1024)
        checkTrue(etagMatches("\"old1\", \"1024\", \"old2\"", et))
        checkTrue(etagMatches("\"999\", W/\"1024\"", et))
    })

    failed += runCase("etag_does_not_match_other_size", { =>
        let et = makeETag(1024)
        checkTrue(!etagMatches("\"2048\"", et))
        checkTrue(!etagMatches("", et))
    })

    failed += runCase("etag_parse_tags_strips_weak_prefix", { =>
        let tags = parseIfNoneMatchTags("W/\"42\", \"43\"")
        checkEq(tags.size, 2)
        checkEq(tags[0], "\"42\"")
        checkEq(tags[1], "\"43\"")
    })

    // ---------- : Cookies full options ----------
    failed += runCase("cookies_set_with_full_options", { =>
        let ctx = Context()
        let opts = CookieOptions()
        opts.maxAge = 3600
        opts.path = "/admin"
        opts.domain = "example.com"
        opts.httpOnly = true
        opts.secure = true
        opts.sameSite = "Strict"
        ctx.cookies.set("sid", "x", opts)
        let hdr = ctx._peekHeaders()["Set-Cookie"]
        checkTrue(hdr.contains("sid=x"))
        checkTrue(hdr.contains("Max-Age=3600"))
        checkTrue(hdr.contains("Path=/admin"))
        checkTrue(hdr.contains("Domain=example.com"))
        checkTrue(hdr.contains("HttpOnly"))
        checkTrue(hdr.contains("Secure"))
        checkTrue(hdr.contains("SameSite=Strict"))
    })

    failed += runCase("cookies_set_default_options_omit_attrs", { =>
        let ctx = Context()
        let opts = CookieOptions()
        ctx.cookies.set("k", "v", opts)
        checkEq(ctx._peekHeaders()["Set-Cookie"], "k=v; Path=/")
    })

    // ---------- : bodyParser smoke ----------
    failed += runCase("bodyparser_runs_next_with_no_http", { =>
        // Without an http context, the parser cannot read the request
        // stream but should still call next() so the chain continues.
        let ctx = Context()
        let mw = bodyParser()
        let called = Array<Bool>(1, { _ => false })
        mw(ctx, { => called[0] = true })
        checkEq(called[0], true)
    })

    // ---------- : logger formatter ----------
    failed += runCase("logger_formatter_with_id", { =>
        let ctx = Context()
        ctx._id = "abc123"
        ctx.status(404)
        let line = defaultLoggerFormatter(ctx, 12)
        checkTrue(line.contains("abc123"))
        checkTrue(line.contains("404"))
        checkTrue(line.contains("12ms"))
    })

    failed += runCase("logger_formatter_dash_when_no_id", { =>
        let ctx = Context()
        let line = defaultLoggerFormatter(ctx, 1)
        checkTrue(line.startsWith("- "))
    })

    // ---------- : requestId helper ----------
    failed += runCase("random_id_is_hex_of_requested_length", { =>
        let id = randomId(8)
        checkEq(id.size, 16)
        for (c in id) {
            let ok = (c >= UInt8(0x30) && c <= UInt8(0x39)) || (c >= UInt8(0x61) && c <= UInt8(0x66))
            if (!ok) { checkTrue(false) }
        }
    })

    // ---------- : CORS resolveOrigin ----------
    failed += runCase("cors_resolve_origin_wildcard", { =>
        let ctx = Context()
        checkEq(resolveOrigin(ctx, "*"), "*")
    })

    failed += runCase("cors_resolve_origin_fixed", { =>
        let ctx = Context()
        checkEq(resolveOrigin(ctx, "https://app.example.com"), "https://app.example.com")
    })

    // ---------- v0.2: jsonx 安全访问器 + JsonBuilder ----------
    failed += runCase("jsonx_getStr_hit", { =>
        let o = JsonObject()
        o.put("name", JsonString("alice"))
        match (jsonGetStr(o, "name")) {
            case Some(s) => checkEq(s, "alice")
            case None => checkTrue(false)
        }
    })

    failed += runCase("jsonx_getStr_missing", { =>
        let o = JsonObject()
        match (jsonGetStr(o, "nope")) {
            case Some(_) => checkTrue(false)
            case None => checkTrue(true)
        }
    })

    failed += runCase("jsonx_getStr_wrong_type", { =>
        let o = JsonObject()
        o.put("age", JsonInt(30))
        match (jsonGetStr(o, "age")) {
            case Some(_) => checkTrue(false)
            case None => checkTrue(true)
        }
    })

    failed += runCase("jsonx_getInt64_hit", { =>
        let o = JsonObject()
        o.put("age", JsonInt(30))
        match (jsonGetInt64(o, "age")) {
            case Some(n) => checkEq(n, 30)
            case None => checkTrue(false)
        }
    })

    failed += runCase("jsonx_getInt64_wrong_type", { =>
        let o = JsonObject()
        o.put("name", JsonString("x"))
        match (jsonGetInt64(o, "name")) {
            case Some(_) => checkTrue(false)
            case None => checkTrue(true)
        }
    })

    failed += runCase("jsonx_getBool_hit", { =>
        let o = JsonObject()
        o.put("ok", JsonBool(true))
        match (jsonGetBool(o, "ok")) {
            case Some(b) => checkEq(b, true)
            case None => checkTrue(false)
        }
    })

    failed += runCase("jsonx_getArray_hit", { =>
        let o = JsonObject()
        o.put("tags", JsonArray())
        match (jsonGetArray(o, "tags")) {
            case Some(a) => checkEq(a.size(), 0)
            case None => checkTrue(false)
        }
    })

    failed += runCase("jsonx_jsonMissing_reports_first", { =>
        let o = JsonObject()
        o.put("a", JsonString("1"))
        match (jsonMissing(o, ["a", "b", "c"])) {
            case Some(m) => checkEq(m, "b")
            case None => checkTrue(false)
        }
    })

    failed += runCase("jsonx_jsonMissing_none_when_all_present", { =>
        let o = JsonObject()
        o.put("a", JsonString("1"))
        o.put("b", JsonString("2"))
        match (jsonMissing(o, ["a", "b"])) {
            case Some(_) => checkTrue(false)
            case None => checkTrue(true)
        }
    })

    failed += runCase("jsonx_builder_escapes_and_serializes", { =>
        let j = JsonBuilder()
            .put("title", "he said \"hi\"")
            .putInt("count", 3)
            .putBool("ok", true)
            .build()
        checkTrue(j.contains("\\\""))
        checkTrue(j.contains("\"count\":3"))
        checkTrue(j.contains("\"ok\":true"))
    })

    failed += runCase("jsonx_builder_nested_object", { =>
        let inner = JsonObject()
        inner.put("x", JsonInt(1))
        let j = JsonBuilder().putObject("meta", inner).build()
        checkTrue(j.contains("\"meta\":{\"x\":1}"))
    })

    // ---------- v0.2 P1: security 密码哈希 + 签名 ----------
    failed += runCase("security_hash_verify_success", { =>
        let stored = hashPassword("secret123", "abc", 10)
        checkEq(verifyPassword("secret123", stored), true)
    })

    failed += runCase("security_hash_verify_wrong_password", { =>
        let stored = hashPassword("secret123", "abc", 10)
        checkEq(verifyPassword("wrong", stored), false)
    })

    failed += runCase("security_hash_self_describing_format", { =>
        let stored = hashPassword("pw", "salt", 5)
        let parts = stored.split("$", 3, removeEmpty: false)
        checkEq(parts.size, 3)
        checkEq(parts[0], "salt")
        checkEq(parts[1], "5")
    })

    failed += runCase("security_sign_roundtrip", { =>
        let signed = signValue("session-123", "secret")
        match (verifySigned(signed, "secret")) {
            case Some(v) => checkEq(v, "session-123")
            case None => checkTrue(false)
        }
    })

    failed += runCase("security_sign_tampered_rejected", { =>
        let signed = signValue("session-123", "secret")
        match (signed.lastIndexOf(".")) {
            case Some(dot) =>
                let tampered = "session-999" + signed[dot..]
                match (verifySigned(tampered, "secret")) {
                    case Some(_) => checkTrue(false)
                    case None => checkTrue(true)
                }
            case None => checkTrue(false)
        }
    })

    failed += runCase("security_sign_wrong_secret_rejected", { =>
        let signed = signValue("v", "secret-a")
        match (verifySigned(signed, "secret-b")) {
            case Some(_) => checkTrue(false)
            case None => checkTrue(true)
        }
    })

    failed += runCase("security_randomHex_length", { =>
        checkEq(randomHex(16).size, 32)
    })

    // ---------- v0.2 P1: session ----------
    failed += runCase("session_create_exists", { =>
        let store = SessionStore()
        let id = store.create()
        checkEq(store.exists(id), true)
    })

    failed += runCase("session_set_get_roundtrip", { =>
        let store = SessionStore()
        let id = store.create()
        store.set(id, "user", "alice")
        match (store.get(id, "user")) {
            case Some(v) => checkEq(v, "alice")
            case None => checkTrue(false)
        }
    })

    failed += runCase("session_destroy", { =>
        let store = SessionStore()
        let id = store.create()
        store.destroy(id)
        checkEq(store.exists(id), false)
    })

    // ---------- v0.2 P2: util 内置解析器 ----------
    failed += runCase("util_parseInt64OrNone_valid", { =>
        match (parseInt64OrNone("42")) {
            case Some(n) => checkEq(n, 42)
            case None => checkTrue(false)
        }
    })

    failed += runCase("util_parseInt64OrNone_invalid", { =>
        match (parseInt64OrNone("abc")) {
            case Some(_) => checkTrue(false)
            case None => checkTrue(true)
        }
    })

    failed += runCase("util_parseInt64Or_default", { =>
        checkEq(parseInt64Or("abc", 7), 7)
        checkEq(parseInt64Or("12", 7), 12)
    })

    failed += runCase("util_parseUInt16OrNone_valid", { =>
        match (parseUInt16OrNone("8080")) {
            case Some(n) => checkEq(n, 8080)
            case None => checkTrue(false)
        }
    })

    failed += runCase("util_parseBoolOrNone", { =>
        checkEq(parseBoolOrNone("true"), Some(true))
        checkEq(parseBoolOrNone("FALSE"), Some(false))
        match (parseBoolOrNone("yes")) {
            case Some(_) => checkTrue(false)
            case None => checkTrue(true)
        }
    })

    // ---------- v0.2: 多 Range ----------
    failed += runCase("range_multi_satisfiable", { =>
        match (parseRanges("bytes=0-1,4-5", 100)) {
            case RangesResult.Satisfiable(specs) => checkEq(specs.size, 2)
            case _ => checkTrue(false)
        }
    })

    failed += runCase("range_multi_single_still_works", { =>
        match (parseRanges("bytes=0-1", 100)) {
            case RangesResult.Satisfiable(specs) => checkEq(specs.size, 1)
            case _ => checkTrue(false)
        }
    })

    failed += runCase("range_multi_unsatisfiable", { =>
        match (parseRanges("bytes=999-1000", 100)) {
            case RangesResult.Unsatisfiable => checkTrue(true)
            case _ => checkTrue(false)
        }
    })

    failed += runCase("range_multi_malformed", { =>
        match (parseRanges("bytes=abc", 100)) {
            case RangesResult.Malformed => checkTrue(true)
            case _ => checkTrue(false)
        }
    })

    failed += runCase("range_multipart_body_contains_boundary_and_range", { =>
        let bytes = Array<UInt8>(10, { i => UInt8(i) })
        let specs = Array<RangeSpec>(2, { _ => RangeSpec(0, 1) })
        specs[0] = RangeSpec(0, 1)
        specs[1] = RangeSpec(4, 5)
        let body = formatMultipartBody(specs, bytes, "text/plain", "BND", 10)
        let s = String.fromUtf8(body)
        checkTrue(s.contains("--BND"))
        checkTrue(s.contains("Content-Range: bytes 0-1/10"))
        checkTrue(s.contains("Content-Range: bytes 4-5/10"))
        checkTrue(s.contains("--BND--"))
    })

    // ---------- v0.2: compress (gzip) ----------
    failed += runCase("compress_gzip_compresses_repetitive_data", { =>
        let big = Array<UInt8>(1000, { _ => UInt8(0x61) })
        let gz = gzipCompress(big)
        checkTrue(gz.size > 0)
        checkTrue(gz.size < big.size)
    })

    failed += runCase("compress_gzip_empty_input", { =>
        checkEq(gzipCompress(Array<UInt8>()).size, 0)
    })

    failed += runCase("compress_isCompressibleType", { =>
        checkEq(isCompressibleType("text/html; charset=utf-8"), true)
        checkEq(isCompressibleType("application/json"), true)
        checkEq(isCompressibleType("image/png"), false)
    })

    // ---------- v0.2: multipart ----------
    failed += runCase("multipart_extract_boundary", { =>
        checkEq(extractBoundary("multipart/form-data; boundary=abc123"), "abc123")
        checkEq(extractBoundary("multipart/form-data; boundary=\"xyz\""), "xyz")
    })

    failed += runCase("multipart_parse_text_field", { =>
        let body = "--BND\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nhello world\r\n--BND--\r\n"
        let parts = parseMultipart(body.toArray(), "BND")
        checkEq(parts.size, 1)
        checkEq(parts[0].name, "title")
        checkEq(parts[0].text(), "hello world")
    })

    failed += runCase("multipart_parse_file_field", { =>
        let body = "--BND\r\nContent-Disposition: form-data; name=\"upload\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nfile bytes here\r\n--BND--\r\n"
        let parts = parseMultipart(body.toArray(), "BND")
        checkEq(parts.size, 1)
        checkEq(parts[0].name, "upload")
        checkEq(parts[0].filename, "a.txt")
        checkEq(parts[0].text(), "file bytes here")
    })

    failed += runCase("multipart_parse_multiple_parts", { =>
        let body = "--BND\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--BND\r\nContent-Disposition: form-data; name=\"b\"\r\n\r\n2\r\n--BND--\r\n"
        let parts = parseMultipart(body.toArray(), "BND")
        checkEq(parts.size, 2)
        checkEq(parts[0].name, "a")
        checkEq(parts[1].name, "b")
    })

    // ---------- v0.2: Last-Modified ----------
    failed += runCase("lastmod_fileLastModified_returns_some", { =>
        match (fileLastModified("./public_blog/index.html")) {
            case Some(_) => checkTrue(true)
            case None => checkTrue(false)
        }
    })

    failed += runCase("lastmod_fileLastModified_missing_returns_none", { =>
        match (fileLastModified("./public_blog/does_not_exist.xyz")) {
            case Some(_) => checkTrue(false)
            case None => checkTrue(true)
        }
    })

    failed += runCase("lastmod_formatHttpDate_contains_gmt", { =>
        match (fileLastModified("./public_blog/index.html")) {
            case Some(mt) =>
                let s = formatHttpDate(mt)
                checkTrue(s.contains(" GMT"))
                checkTrue(s.contains(", "))
            case None => checkTrue(false)
        }
    })

    failed += runCase("lastmod_lastModifiedMatches_exact", { =>
        checkEq(lastModifiedMatches("Wed, 09 Sep 2026 19:33:49 GMT", "Wed, 09 Sep 2026 19:33:49 GMT"), true)
        checkEq(lastModifiedMatches("Thu, 10 Sep 2026 00:00:00 GMT", "Wed, 09 Sep 2026 19:33:49 GMT"), false)
    })

    failed += runCase("config_parse_key_value", { =>
        let c = parseConfigText("port=3000\nhost=localhost")
        checkEq(c.getOr("port", ""), "3000")
        checkEq(c.getOr("host", ""), "localhost")
    })

    failed += runCase("config_parse_ignores_comment_and_blank", { =>
        let c = parseConfigText("# comment\n\nport=8080\n   \n# another\nname=app")
        checkEq(c.has("comment"), false)
        checkEq(c.size(), 2)
        checkEq(c.getOr("port", ""), "8080")
        checkEq(c.getOr("name", ""), "app")
    })

    failed += runCase("config_value_with_equals", { =>
        let c = parseConfigText("url=http://x.com?a=1&b=2")
        checkEq(c.getOr("url", ""), "http://x.com?a=1&b=2")
    })

    failed += runCase("config_typed_accessors", { =>
        let c = Config()
        c.set("port", "3000")
        c.set("debug", "true")
        c.set("ratio", "1.5")
        checkEq(c.getIntOr("port", 0), 3000)
        checkEq(c.getBoolOr("debug", false), true)
        match (c.getFloat("ratio")) {
            case Some(f) => checkTrue(f > 1.4)
            case None => throw Exception("expected ratio")
        }
    })

    failed += runCase("config_get_or_default", { =>
        let c = Config()
        checkEq(c.getOr("missing", "fallback"), "fallback")
        checkEq(c.getIntOr("missing", 42), 42)
        checkEq(c.getBoolOr("missing", true), true)
    })

    failed += runCase("static_cache_put_get", { =>
        let cache = StaticCache()
        let bytes = Array<UInt8>(3, { i => UInt8(i + 1) })
        cache.put("/a/b.txt", bytes)
        match (cache.get("/a/b.txt")) {
            case Some(cached) => checkEq(cached.size, 3)
            case None => throw Exception("expected cached")
        }
        match (cache.get("/missing")) {
            case Some(_) => throw Exception("expected miss")
            case None => checkTrue(true)
        }
    })

    // ============  TLS scenarios ============
    failed += runCase("serveTls_rejects_garbage_pem_no_silent_fallback", { =>
        // 核心要求：PEM 无法解析时必须抛异常，绝不静默降级为明文 HTTP
        let app = QingZhouApp()
        var threw = false
        try {
            app.serveTls(65530, "not-a-cert", "not-a-key")
        } catch (e: Exception) {
            threw = true
        }
        checkTrue(threw)
    })

    failed += runCase("x509_cert_decode_rejects_garbage", { =>
        var threw = false
        try {
            X509Certificate.decodeFromPem("not-a-pem")
        } catch (e: Exception) {
            threw = true
        }
        checkTrue(threw)
    })

    failed += runCase("rsa_privatekey_decode_rejects_garbage", { =>
        var threw = false
        try {
            RSAPrivateKey.decodeFromPem("not-a-pem")
        } catch (e: Exception) {
            threw = true
        }
        checkTrue(threw)
    })

    println("---")
    if (failed == 0) {
        println("All ${g_total} unit-test scenarios PASSED")
        return 0
    }
    println("${failed} unit-test scenario(s) FAILED")
    return 1
}

/*
 * Concrete exception subclass used by manual runner scenarios.
 * Lives here so that unit_tests.cj (which declares `Boom <: Exception` for the
 * @Test macros) does not collide.
 */
class Boom2 <: Exception {
    init() { super("boom!") }
}

func runCase(name: String, body: () -> Unit): Int64 {
    g_total += 1
    try {
        body()
        println("  PASS  ${name}")
        return 0
    } catch (e: Exception) {
        println("  FAIL  ${name}: ${e.message}")
        return 1
    }
}

func checkEq<T>(actual: T, expected: T): Unit where T <: Equatable<T> & ToString {
    if (actual != expected) {
        throw Exception("expected <${expected}> got <${actual}>")
    }
}

func checkTrue(b: Bool): Unit {
    if (!b) {
        throw Exception("expected true")
    }
}
