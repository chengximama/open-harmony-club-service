package qingzhou

import std.collection.*
import std.io.*
import stdx.net.http.*
import stdx.encoding.json.*

/*
 * SPDX-License-Identifier: MIT
 *
 * QingZhou v0.6 — 出站 HTTP 客户端薄封装（helper）。
 *
 * Copyright (c) 2026 guowei
 * BIT Foundational Software And Systems Lab
 *
 * 只封装出站调用最常用的「GET/POST + 文本/JSON + 错误处理」样板，
 * 减少业务代码重复。需要完整能力（自定义 header、TLS、代理、重定向、
 * 连接复用等）请直接用 stdx.net.http.Client，本模块不重复实现。
 *
 * 语义约定：非 2xx 状态码、网络错误、JSON 解析失败一律返回 None（不抛异常），
 * 由调用方决定如何处理。
 */

/* 读 InputStream 全部内容并转为字符串（UTF-8）。 */
func readBodyText(body: InputStream): String {
    let buf = Array<UInt8>(4096, { _ => UInt8(0) })
    let out = ArrayList<UInt8>()
    while (true) {
        let n = body.read(buf)
        if (n <= 0) {
            break
        }
        var i: Int64 = 0
        while (i < n) {
            out.add(buf[i])
            i += 1
        }
        if (n < buf.size) {
            break
        }
    }
    return String.fromUtf8(out.toArray())
}

/* 判断状态码是否为成功（2xx）。 */
func isSuccess(status: UInt16): Bool {
    return Int64(status) >= 200 && Int64(status) < 300
}

/* GET，返回响应文本 body；非 2xx 或网络错误返回 None。 */
public func httpGetText(url: String): ?String {
    let client = ClientBuilder().build()
    var result: ?String = None
    try {
        let resp = client.get(url)
        if (isSuccess(resp.status)) {
            result = Some(readBodyText(resp.body))
        }
    } catch (e: Exception) {
        result = None
    }
    client.close()
    return result
}

/* GET，返回解析后的 JSON；非 2xx / 非 JSON / 网络错误返回 None。 */
public func httpGetJson(url: String): ?JsonValue {
    match (httpGetText(url)) {
        case Some(text) =>
            return try { Some(JsonValue.fromStr(text)) } catch (e: Exception) { None }
        case None => return None
    }
}

/* POST JSON 字符串，返回响应文本 body；非 2xx 或网络错误返回 None。 */
public func httpPostJson(url: String, jsonBody: String): ?String {
    let client = ClientBuilder().build()
    var result: ?String = None
    try {
        let resp = client.post(url, jsonBody)
        if (isSuccess(resp.status)) {
            result = Some(readBodyText(resp.body))
        }
    } catch (e: Exception) {
        result = None
    }
    client.close()
    return result
}
