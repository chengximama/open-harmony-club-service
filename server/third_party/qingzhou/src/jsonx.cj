package qingzhou

import std.collection.*
import stdx.encoding.json.*

/*
 * SPDX-License-Identifier: MIT
 *
 * QingZhou v0.2 P0 — JSON 工具层。
 *
 * Copyright (c) 2026 guowei
 * BIT Foundational Software And Systems Lab
 *
 * 解决 GAPS.md 的两个 P0：
 *   1) 无安全访问器（stdx asString/asInt/asFloat 类型不符会抛异常）
 *   2) 无序列化 helper（手写 JSON 拼接 + 手动转义）
 *
 * 关键事实（stdx 1.0.5.1 encoding.json）：
 *   - 数字方法是 asInt() / asFloat()（不是 asNumber）
 *   - JsonObject.put(key, JsonValue) + toString() 可直接构建并序列化 JSON，
 *     toString() 会自动转义字符串，无需手写 escapeJson
 *   - JsonObject.get(key) 返回 ?JsonValue；asXxx() 返回子类（非 Option），
 *     类型不符抛 JsonException，故安全访问器内部用 try/catch 消化
 */

/* ===================== 安全访问器（P0-3） ===================== */

public func jsonGetStr(obj: JsonObject, key: String): ?String {
    match (obj.get(key)) {
        case Some(v) => return try { Some(v.asString().getValue()) } catch (e: Exception) { None }
        case None => return None
    }
}

public func jsonGetInt64(obj: JsonObject, key: String): ?Int64 {
    match (obj.get(key)) {
        case Some(v) => return try { Some(v.asInt().getValue()) } catch (e: Exception) { None }
        case None => return None
    }
}

public func jsonGetFloat64(obj: JsonObject, key: String): ?Float64 {
    match (obj.get(key)) {
        case Some(v) => return try { Some(v.asFloat().getValue()) } catch (e: Exception) { None }
        case None => return None
    }
}

public func jsonGetBool(obj: JsonObject, key: String): ?Bool {
    match (obj.get(key)) {
        case Some(v) => return try { Some(v.asBool().getValue()) } catch (e: Exception) { None }
        case None => return None
    }
}

public func jsonGetObject(obj: JsonObject, key: String): ?JsonObject {
    match (obj.get(key)) {
        case Some(v) => return try { Some(v.asObject()) } catch (e: Exception) { None }
        case None => return None
    }
}

public func jsonGetArray(obj: JsonObject, key: String): ?JsonArray {
    match (obj.get(key)) {
        case Some(v) => return try { Some(v.asArray()) } catch (e: Exception) { None }
        case None => return None
    }
}

/*
 * 返回第一个缺失的字段名；全部存在则返回 None。
 * 用于 body 字段校验（P0-4 的「判空」样板）。
 */
public func jsonMissing(obj: JsonObject, keys: Array<String>): ?String {
    for (k in keys) {
        if (!obj.containsKey(k)) {
            return Some(k)
        }
    }
    return None
}

/* ===================== JSON 构建器（P0-2） ===================== */

/*
 * 流畅的 JSON 对象构建器。示例：
 *
 *   let body = JsonBuilder()
 *       .put("id", id.toString())        // 字符串自动转义
 *       .putInt("count", 3)
 *       .putBool("ok", true)
 *       .build()                          // -> {"id":"...","count":3,"ok":true}
 *
 * 比手写 "{\"id\":${id},...}" 更安全（自动转义、类型正确）。
 */
public class JsonBuilder {
    private let obj: JsonObject

    public init() {
        obj = JsonObject()
    }

    public func put(key: String, value: String): JsonBuilder {
        obj.put(key, JsonString(value))
        return this
    }

    public func putInt(key: String, value: Int64): JsonBuilder {
        obj.put(key, JsonInt(value))
        return this
    }

    public func putFloat(key: String, value: Float64): JsonBuilder {
        obj.put(key, JsonFloat(value))
        return this
    }

    public func putBool(key: String, value: Bool): JsonBuilder {
        obj.put(key, JsonBool(value))
        return this
    }

    public func putObject(key: String, value: JsonObject): JsonBuilder {
        obj.put(key, value)
        return this
    }

    public func putArray(key: String, value: JsonArray): JsonBuilder {
        obj.put(key, value)
        return this
    }

    /* 输出紧凑 JSON 字符串（自动转义）。 */
    public func build(): String {
        return obj.toString()
    }

    /* 拿到底层 JsonObject（供嵌套/进一步处理）。 */
    public func toObject(): JsonObject {
        return obj
    }
}

/* ===================== body 便捷读取（P0-4） ===================== */

/*
 * 从请求 body 的 JSON 对象读字符串字段。封装了
 * bodyJson() -> asObject() -> get() 的样板 + 异常守护。
 * 返回 None 表示「无 body / 非对象 / 字段缺失 / 类型不符」。
 */
public func bodyStr(ctx: Context, key: String): ?String {
    match (ctx.bodyJson()) {
        case Some(v) =>
            return try { jsonGetStr(v.asObject(), key) } catch (e: Exception) { None }
        case None => return None
    }
}

/*
 * 从请求 body 的 JSON 对象读整数字段。语义同 bodyStr。
 */
public func bodyInt64(ctx: Context, key: String): ?Int64 {
    match (ctx.bodyJson()) {
        case Some(v) =>
            return try { jsonGetInt64(v.asObject(), key) } catch (e: Exception) { None }
        case None => return None
    }
}

/*
 * 从请求 body 读字符串字段，缺失/类型不符时返回 default_。
 * 用于必填字段的「读 + 判空」一步到位。
 */
public func bodyStrOr(ctx: Context, key: String, default_: String): String {
    match (bodyStr(ctx, key)) {
        case Some(s) => return s
        case None => return default_
    }
}
