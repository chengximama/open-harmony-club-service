package qingzhou

import std.collection.*

/*
 * SPDX-License-Identifier: MIT
 *
 * QingZhou v0.2 — multipart/form-data 解析。
 *
 * Copyright (c) 2026 guowei
 * BIT Foundational Software And Systems Lab
 *
 * 解决 GAPS.md 功能缺口「multipart/form-data」。
 * stdx 无 multipart 包，这里手写 boundary 解析（RFC 7578 子集）。
 *
 * 支持文本字段与二进制文件字段。用法：
 *   app.use(multipart())     // 解析 multipart body 到 ctx
 *   // handler 里：
 *   multipartField(ctx, "title")    // -> ?String
 *   multipartFile(ctx, "upload")    // -> ?MultipartPart
 */

/* 单个 multipart part（字段或文件）。 */
public class MultipartPart {
    public var name: String = ""
    public var filename: String = ""
    public var contentType: String = ""
    public var data: Array<UInt8> = Array<UInt8>()

    init() {}

    /* 文本值（data 按 UTF-8 解码）。 */
    public func text(): String {
        return String.fromUtf8(data)
    }
}

/* 从 Content-Type 头提取 boundary（去掉可选引号）。 */
func extractBoundary(contentType: String): String {
    for (p in contentType.split(";", -1, removeEmpty: false)) {
        let t = p.trimAscii()
        if (t.startsWith("boundary=")) {
            let v = t["boundary=".size..].trimAscii()
            if (v.size >= 2 && v[0] == UInt8(0x22) && v[v.size - 1] == UInt8(0x22)) {
                return v[1..(v.size - 1)]
            }
            return v
        }
    }
    return ""
}

/* 从 Content-Disposition 提取 name 或 filename 属性。 */
func extractAttr(disposition: String, attr: String): ?String {
    for (p in disposition.split(";", -1, removeEmpty: false)) {
        let t = p.trimAscii()
        if (t.startsWith(attr + "=")) {
            let v = t[(attr.size + 1)..].trimAscii()
            if (v.size >= 2 && v[0] == UInt8(0x22) && v[v.size - 1] == UInt8(0x22)) {
                return Some(v[1..(v.size - 1)])
            }
            return Some(v)
        }
    }
    return None
}

/* 解析 part 头部块（每行 "Name: value"）。 */
func parsePartHeaders(block: String, part: MultipartPart): Unit {
    for (line in block.split("\r\n", -1, removeEmpty: true)) {
        let kv = line.split(":", 2, removeEmpty: false)
        if (kv.size < 2) {
            continue
        }
        let name = kv[0].trimAscii().toAsciiLower()
        let value = kv[1].trimAscii()
        if (name == "content-disposition") {
            match (extractAttr(value, "name")) {
                case Some(v) => part.name = v
                case None => ()
            }
            match (extractAttr(value, "filename")) {
                case Some(v) => part.filename = v
                case None => ()
            }
        } else if (name == "content-type") {
            part.contentType = value
        }
    }
}

/*
 * 解析 multipart body。返回 part 列表（字段/文件）。
 * 文本字段可直接 .text()；文件字段用 .data（原始字节）。
 */
public func parseMultipart(body: Array<UInt8>, boundary: String): ArrayList<MultipartPart> {
    let parts = ArrayList<MultipartPart>()
    if (boundary.size == 0 || body.size == 0) {
        return parts
    }
    let text = String.fromUtf8(body)
    let delim = "--" + boundary
    let chunks = text.split(delim, -1, removeEmpty: true)
    for (chunk in chunks) {
        var seg = chunk
        // 去掉开头的 "\r\n"
        if (seg.size >= 2 && seg[0] == UInt8(0x0D) && seg[1] == UInt8(0x0A)) {
            seg = seg[2..]
        }
        // 结尾 boundary 的 "--" 或空内容跳过
        if (seg.size == 0 || seg.startsWith("--")) {
            continue
        }
        // headers 与 content 用 "\r\n\r\n" 分隔
        let hp = seg.split("\r\n\r\n", 2, removeEmpty: false)
        if (hp.size < 2) {
            continue
        }
        let headerBlock = hp[0]
        var content = hp[1]
        // content 去掉末尾的 "\r\n"
        if (content.size >= 2 && content[content.size - 2] == UInt8(0x0D) && content[content.size - 1] == UInt8(0x0A)) {
            content = content[0..(content.size - 2)]
        }
        let part = MultipartPart()
        parsePartHeaders(headerBlock, part)
        part.data = content.toArray()
        parts.add(part)
    }
    return parts
}

/* multipart 中间件：解析 multipart/form-data body，存入 ctx。 */
public func multipart(): Middleware {
    return { ctx: Context, next: () -> Unit =>
        let ctFull = match (ctx.requestHeader("content-type")) {
            case Some(v) => v
            case None => ""
        }
        if (ctFull.toAsciiLower().startsWith("multipart/form-data")) {
            let boundary = extractBoundary(ctFull)
            let parts = parseMultipart(ctx.bodyBytes(), boundary)
            ctx.setMultipartParts(parts)
        }
        next()
    }
}

/* 读文本字段值（第一个匹配 name 的 part）。 */
public func multipartField(ctx: Context, name: String): ?String {
    for (p in ctx.multipartParts()) {
        if (p.name == name) {
            return Some(p.text())
        }
    }
    return None
}

/* 读文件字段（第一个匹配 name 且带 filename 的 part）。 */
public func multipartFile(ctx: Context, name: String): ?MultipartPart {
    for (p in ctx.multipartParts()) {
        if (p.name == name && p.filename.size > 0) {
            return Some(p)
        }
    }
    return None
}
