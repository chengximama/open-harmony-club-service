package qingzhou

import std.collection.*
import std.fs.*
import std.time.*

/*
 * SPDX-License-Identifier: MIT
 *
 * QingZhou - ETag generation and If-None-Match matching.
 *
 * Copyright (c) 2026 guowei
 * BIT Foundational Software And Systems Lab
 *
 * ETag is a strong validator (RFC 7232 section 2.3): the byte sequence
 * enclosed in double quotes. We derive it from the file size only:
 *
 *   ETag: "<size>"
 *
 * Caveats (documented; would be improved in a later version):
 *   - Two distinct files with identical sizes share an ETag, but the
 *     chance of that being observed in a single static directory is
 *     negligible. Real fingerprints (size + mtime, or content hash)
 *     need stdx crypto.digest hashing on every served file which is
 *     overkill for the  minimum.
 *   - std.fs.File on cangjie 1.0 (patch 5) does not expose
 *     `lastModified`, so we cannot include mtime cheaply. (We
 *     explored this during  design — see MEMORY.md / README.)
 *
 * The shape (with quotes) is required by the spec. RFC 7232
 * section 2.3:
 *   ETag = entity-tag, where entity-tag = [ weak ] opaque-tag
 *                       and opaque-tag = DQUOTE *etagc DQUOTE
 *
 * If-None-Match is the request header that triggers a 304:
 *   - "*" matches any current representation
 *   - A comma-separated list of opaque-tags matches if ANY tag equals
 *     the current ETag
 *   - Comparison is byte-wise on the opaque-tag (after stripping
 *     surrounding whitespace and the leading "W/" weak prefix)
 */

/*
 * Build a strong ETag for a resource of `size` bytes. Always returns
 * `"<size>"` including the surrounding double quotes.
 */
public func makeETag(size: Int64): String {
    return "\"" + size.toString() + "\""
}

/*
 * Check whether the client's `If-None-Match` value matches our
 * `currentETag`. Returns true if the server should respond 304.
 *
 * Rules (RFC 7232 section 3.2):
 *   - "*"  -> match (always true)
 *   - comma-separated list -> match if any tag (after stripping W/
 *     and DQUOTE) equals currentETag
 *   - whitespace around tags is permitted
 */
public func etagMatches(ifNoneMatch: String, currentETag: String): Bool {
    if (ifNoneMatch.size == 0) {
        return false
    }
    // Wildcard matches everything.
    if (ifNoneMatch.trimAscii() == "*") {
        return true
    }
    // Split on comma (maxSplits = piece count; -1 = no cap).
    let parts = ifNoneMatch.split(",", -1, removeEmpty: true)
    for (p in parts) {
        var t = p.trimAscii()
        if (t.size >= 2 && t[0] == UInt8(0x57) && t[1] == UInt8(0x2F)) {  // "W/"
            t = t[2..]
        }
        if (t == currentETag) {
            return true
        }
    }
    return false
}

/*
 * Parse a comma-separated list of ETag values into a List<String>.
 * Used by tests to inspect the parsed tags. Strips W/ weak prefix.
 */
public func parseIfNoneMatchTags(ifNoneMatch: String): ArrayList<String> {
    let out = ArrayList<String>()
    if (ifNoneMatch.size == 0) {
        return out
    }
    let parts = ifNoneMatch.split(",", -1, removeEmpty: true)
    for (p in parts) {
        var t = p.trimAscii()
        if (t.size >= 2 && t[0] == UInt8(0x57) && t[1] == UInt8(0x2F)) {
            t = t[2..]
        }
        out.add(t)
    }
    return out
}

/* ===================== Last-Modified（v0.2） ===================== */

/*
 * 读文件的最后修改时间（UTC DateTime）。文件不存在/不可读返回 None。
 *
 * 关键事实（v0.2 才发现，纠正  的误判）：
 *   std.fs.File.info -> FileInfo.lastModificationTime 是存在的，且返回
 *   UTC 时间（带 Z 后缀），不是本地时间。 探测时漏掉了 File.info
 *   这个入口，误以为 std.fs 无 mtime。
 */
public func fileLastModified(path: String): ?DateTime {
    try {
        let f = File(path, Read)
        let info = f.info
        let mt = info.lastModificationTime
        f.close()
        return Some(mt)
    } catch (e: Exception) {
        return None
    }
}

/* 星期序号（ISO 1=Mon..7=Sun）-> 英文缩写。 */
func dayOfWeekName(d: Int64): String {
    if (d == 1) { return "Mon" }
    if (d == 2) { return "Tue" }
    if (d == 3) { return "Wed" }
    if (d == 4) { return "Thu" }
    if (d == 5) { return "Fri" }
    if (d == 6) { return "Sat" }
    return "Sun"
}

/* 月份序号（1..12）-> 英文缩写。 */
func monthName(m: Int64): String {
    if (m == 1) { return "Jan" }
    if (m == 2) { return "Feb" }
    if (m == 3) { return "Mar" }
    if (m == 4) { return "Apr" }
    if (m == 5) { return "May" }
    if (m == 6) { return "Jun" }
    if (m == 7) { return "Jul" }
    if (m == 8) { return "Aug" }
    if (m == 9) { return "Sep" }
    if (m == 10) { return "Oct" }
    if (m == 11) { return "Nov" }
    return "Dec"
}

/* 个位数补零（9 -> "09"）。 */
func pad2(n: Int64): String {
    if (n < 10) {
        return "0" + n.toString()
    }
    return n.toString()
}

/*
 * 格式化 HTTP date（RFC 7231 IMF-fixdate）：
 *   "Wed, 09 Sep 2026 19:33:49 GMT"
 */
public func formatHttpDate(dt: DateTime): String {
    let dow = dayOfWeekName(dt.dayOfWeek.toInteger())
    let mon = monthName(dt.month.toInteger())
    return dow + ", " + pad2(dt.dayOfMonth) + " " + mon + " " +
        dt.year.toString() + " " + pad2(dt.hour) + ":" + pad2(dt.minute) +
        ":" + pad2(dt.second) + " GMT"
}

/*
 * 判断 If-Modified-Since 是否匹配文件的 mtime（字符串精确比较）。
 * 客户端通常回传服务器发出的 Last-Modified 值，精确比较即可工作。
 */
public func lastModifiedMatches(ifModifiedSince: String, lastModified: String): Bool {
    return ifModifiedSince.trimAscii() == lastModified
}