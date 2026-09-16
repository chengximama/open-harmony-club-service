package qingzhou

import std.collection.*

/*
 * SPDX-License-Identifier: MIT
 *
 * QingZhou - trie router.
 *
 * Copyright (c) 2026 guowei
 * BIT Foundational Software And Systems Lab
 *
 * Pattern syntax:
 *   /users             static
 *   /users/:id         :param  -> ctx.params["id"]
 *   /static/{star}     wildcard -> ctx.params["tail"] = "remaining/path"
 *
 * Lookup returns DispatchResult:
 *   Matched(h)              -> run handler, params injected into ctx
 *   MethodNotAllowed(allow) -> ctx already set to 405 + Allow header
 *   NotFound                -> ctx already set to 404 + JSON
 *
 * Use as a Middleware via `router.middleware()` so that it sits inside the
 * normal Koa-style chain (anything before/after runs naturally).
 *
 * Cangjie enum note: enum does not provide == by default, so we extend
 * SegmentKind with Equatable<SegmentKind> below to enable `c.kind == Static`.
 */

enum SegmentKind {
    | Static
    | Param
    | Wildcard
}

extend SegmentKind <: Equatable<SegmentKind> {
    public operator func ==(right: SegmentKind): Bool {
        var s: Bool = false
        match (this) {
            case SegmentKind.Static => s = match (right) { case SegmentKind.Static => true; case _ => false }
            case SegmentKind.Param => s = match (right) { case SegmentKind.Param => true; case _ => false }
            case SegmentKind.Wildcard => s = match (right) { case SegmentKind.Wildcard => true; case _ => false }
        }
        return s
    }
    public operator func !=(right: SegmentKind): Bool {
        var s: Bool = false
        match (this) {
            case SegmentKind.Static => s = match (right) { case SegmentKind.Static => false; case _ => true }
            case SegmentKind.Param => s = match (right) { case SegmentKind.Param => false; case _ => true }
            case SegmentKind.Wildcard => s = match (right) { case SegmentKind.Wildcard => false; case _ => true }
        }
        return s
    }
}

class TrieNode {
    var kind: SegmentKind = SegmentKind.Static
    var segment: String = ""
    var paramName: String = ""
    let children: ArrayList<TrieNode> = ArrayList<TrieNode>()
    let handlers: HashMap<String, Middleware> = HashMap<String, Middleware>()
    var anyHandler: Bool = false
}

public enum DispatchResult {
    | Matched(Middleware)
    | MethodNotAllowed(String)
    | NotFound
}

public class Router {
    private let root: TrieNode = TrieNode()
    /* 透传模式：NotFound 时调 next() 而非短路，支持多个 Router 串联
     * （例如公开路由 + 鉴权路由 + 静态兜底）。默认 false 保持向后兼容。 */
    public var passOnNotFound: Bool = false

    public init() {}

    /*
     * Add a (method, pattern) -> handler entry. method is normalised to upper case.
     */
    public func add(method: String, pattern: String, h: Middleware): Router {
        let segs = splitPath(pattern)
        var node = root
        for (seg in segs) {
            if (seg == "*") {
                node = findOrCreate(node, SegmentKind.Wildcard, "*", "tail")
            } else if (seg.size > 0 && seg[0] == 0x3A) { // ":"
                node = findOrCreate(node, SegmentKind.Param, ":", seg[1..])
            } else {
                node = findOrCreate(node, SegmentKind.Static, seg, "")
            }
        }
        node.handlers[method.toAsciiUpper()] = h
        node.anyHandler = true
        return this
    }

    public func get(p: String, h: Middleware): Router { add("GET", p, h) }
    public func post(p: String, h: Middleware): Router { add("POST", p, h) }
    public func put(p: String, h: Middleware): Router { add("PUT", p, h) }
    public func delete(p: String, h: Middleware): Router { add("DELETE", p, h) }
    public func patch(p: String, h: Middleware): Router { add("PATCH", p, h) }
    public func all(p: String, h: Middleware): Router { add("*", p, h) }

    /*
     * Resolve method+path against the trie. Side-effects the ctx on
     * non-match: 404 JSON for NotFound, 405 + Allow for MethodNotAllowed.
     * (This lets unit tests assert directly against ctx without going
     * through middleware().)
     */
    public func lookup(method: String, path: String, ctx: Context): DispatchResult {
        let segs = splitPath(path)
        let params = HashMap<String, String>()
        let final = walk(root, segs, 0, params)
        match (final) {
            case Some(node) =>
                let m = method.toAsciiUpper()
                match (node.handlers.get(m)) {
                    case Some(h) =>
                        for ((k, v) in params) {
                            ctx.setParam(k, v)
                        }
                        return DispatchResult.Matched(h)
                    case None =>
                        if (node.anyHandler) {
                            let allow = String.join(collectKeys(node.handlers), delimiter: ", ")
                            ctx.status(405)
                                .header("allow", allow)
                                .header("content-type", "application/json")
                                .body("{\"error\":\"Method Not Allowed\",\"allow\":\"${allow}\"}")
                            return DispatchResult.MethodNotAllowed(allow)
                        } else {
                            ctx.status(404)
                                .header("content-type", "application/json")
                                .body("{\"error\":\"Not Found\",\"path\":\"${path}\"}")
                            return DispatchResult.NotFound
                        }
                }
            case None =>
                ctx.status(404)
                    .header("content-type", "application/json")
                    .body("{\"error\":\"Not Found\",\"path\":\"${path}\"}")
                return DispatchResult.NotFound
        }
    }

    /*
     * Wrap the router as a Middleware. On Matched, run the handler;
     * on MethodNotAllowed/NotFound, respond directly so 405/404 still
     * pass through ctx.commit() and the onError chain untouched.
     */
    public func middleware(): Middleware {
        let r = this
        return { ctx: Context, next: () -> Unit =>
            let result = r.lookup(ctx.method(), ctx.path(), ctx)
            match (result) {
                case DispatchResult.Matched(h) => h(ctx, next)
                case DispatchResult.MethodNotAllowed(allow) =>
                    ctx.status(405)
                        .header("allow", allow)
                        .header("content-type", "application/json")
                        .body("{\"error\":\"Method Not Allowed\",\"allow\":\"${allow}\"}")
                case DispatchResult.NotFound =>
                    if (r.passOnNotFound) {
                        // 透传：让后续中间件/路由/静态服务继续处理
                        next()
                    } else {
                        ctx.status(404)
                            .header("content-type", "application/json")
                            .body("{\"error\":\"Not Found\",\"path\":\"${ctx.path()}\"}")
                    }
            }
        }
    }

    // ---------- internals ----------

    func findOrCreate(parent: TrieNode, k: SegmentKind, seg: String, name: String): TrieNode {
        for (c in parent.children) {
            if (c.kind == k && c.segment == seg && (k != SegmentKind.Param || c.paramName == name)) {
                return c
            }
        }
        let nn = TrieNode()
        nn.kind = k
        nn.segment = seg
        nn.paramName = name
        parent.children.add(nn)
        return nn
    }

    func walk(node: TrieNode, segs: Array<String>, idx: Int64, params: HashMap<String, String>): ?TrieNode {
        if (idx == segs.size) {
            return if (node.anyHandler) { Some(node) } else { None }
        }
        let seg = segs[idx]
        for (c in node.children) {
            if (c.kind == SegmentKind.Static && c.segment == seg) {
                return walk(c, segs, idx + 1, params)
            }
        }
        for (c in node.children) {
            if (c.kind == SegmentKind.Param) {
                params[c.paramName] = seg
                return walk(c, segs, idx + 1, params)
            }
        }
        for (c in node.children) {
            if (c.kind == SegmentKind.Wildcard) {
                let tail = String.join(segs[idx..], delimiter: "/")
                params[c.paramName] = tail
                return walk(c, segs, segs.size, params)
            }
        }
        return None
    }
}

func collectKeys(m: HashMap<String, Middleware>): Array<String> {
    let out = ArrayList<String>()
    for (k in m.keys()) {
        out.add(k)
    }
    return out.toArray()
}

/*
 * Split a URL path into segments.
 *   "/"          -> []
 *   ""           -> []
 *   "/users/42"  -> ["users", "42"]
 *   "/a/b/"      -> ["a", "b"]
 */
func splitPath(p: String): Array<String> {
    var s = p
    if (s.size > 0 && s[0] == 0x2F) { // "/"
        s = s[1..]
    }
    if (s.size > 1 && s[s.size - 1] == 0x2F) {
        s = s[0..(s.size - 1)]
    }
    if (s.size == 0) {
        return Array<String>()
    }
    return s.split("/", removeEmpty: true)
}
