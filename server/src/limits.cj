package qingzhou

/*
 * SPDX-License-Identifier: MIT
 *
 * 社团管理工具 · 服务端
 * 输入上限：请求体大小闸门 + 文本字段长度口径（2026-09-17 新增）。
 *
 * 为什么要在应用侧自己拦一道（框架的 bodyParser 已经有 maxBytes = 1 MiB）：
 *   · 轻舟的 bodyParser 是**先把整个 body 读进内存、再比 maxBytes**
 *     （third_party/qingzhou/src/bodyparser.cj 的 handleJson：`ctx.bodyJson()` 先执行，
 *      之后才 `if (raw.size > opts.maxBytes)`）——所以 1 MiB 那道闸**挡不住**
 *     "发一个 1 GB 的 body 把内存打满"，它只是事后报 413；
 *   · 而且它对**非** json / x-www-form-urlencoded / text 的 Content-Type 直接透传、
 *     不读也不判（同文件 67-80），而 handler 里的 `reqObj(ctx)` 照样会把整个 body
 *     读完（context.cj 的 bodyBytes：按 1024 字节往 ArrayList 里堆，没有任何上限）。
 *   框架源码是**上游快照**：build.ps1 用 MANIFEST.sha256 逐字节校验，改动会被拒绝构建
 *   （N-20 的教训）。所以按"我们的改动一律落 server/src"的既定做法，在**最外层**加一道：
 *     ① 写方法（POST/PUT/PATCH/DELETE）：Content-Length 超上限 → 413；
 *     ② Content-Type 不在我们认识的三类里 → 415（否则它正好绕过 ①）。
 *   两者都排在 bodyParser **之前**（见 main.cj 的装配顺序），所以大 body 进不了内存。
 *
 * ⚠ 能力边界（写清楚，别高估）：`Content-Length` 缺失时（chunked 编码）本闸门看不出来，
 *   那种情况只能靠框架那道"先读后判"兜底。要彻底解决得改框架或换服务器，不在本轮范围。
 *
 * 文本字段长度口径也集中在这里：这些字段最终整份进 db.json，而**每次写都要重写整个库**
 * （约 3 倍文件大小的 IO）。不设上限时，一条 1 MiB 的 desc 会被反复重写，而且它一条就顶
 * 上千条正常任务 —— 上限本身就是"库别被单条记录撑爆"的保险丝。
 */

import std.convert.*
import stdx.encoding.json.*

/* 请求体上限。本项目最大的合法请求体是批量分配（200 个 id ≈ 3 KB），64 KiB 留足余量。 */
public let MAX_BODY_BYTES: Int64 = 64 * 1024

/* 文本字段上限（单位**字节**：Cangjie 的 String.size 就是字节数，一个中文约 3 字节）。 */
public let MAX_TITLE_BYTES: Int64 = 200
public let MAX_DESC_BYTES: Int64 = 4000
public let MAX_BLOCKER_BYTES: Int64 = 1000
public let MAX_NAME_BYTES: Int64 = 64
public let MAX_CLIENT_TOKEN_BYTES: Int64 = 64

/*
 * 字段长度校验（**收集器版**）：与别的字段问题一起收齐再抛，让表单能一次性逐字段提示
 * —— 与 jsonw.cj 的 `V` 同一口径，所以走 V 的 handler 用它。
 */
public func lenCheck(v: V, field: String, label: String, value: String, limit: Int64): Unit {
    v.check(field, value.size <= limit, "${label}最多 ${limit} 字节（一个中文约 3 字节）")
}

/*
 * 字段长度校验（**立即版**）：给不走 V 的 handler 用（它们本来就是"逐条校验 + 立即抛"的形状）。
 */
public func requireLen(field: String, label: String, value: String, limit: Int64): Unit {
    if (value.size > limit) {
        throw apiErrFields("VALIDATION_FAILED", "参数校验失败",
            oneField(field, "${label}最多 ${limit} 字节（一个中文约 3 字节）"))
    }
}

/*
 * 请求体闸门。挂在 bodyParser **之前**（main.cj 的 buildApp），见文件头注释。
 *
 * 为什么不直接 throw ApiError 交给 onError：本中间件在 router 之外，直接构造标准错误响应
 * 更短、也少一次异常穿越（错误响应形状与 sendError 完全一致，客户端不用写特例）。
 */
public func bodyLimit(): Middleware {
    return { ctx: Context, next: () -> Unit =>
        let m = ctx.method()
        let writes = (m == "POST" || m == "PUT" || m == "PATCH" || m == "DELETE")
        if (writes) {
            match (ctx.requestHeader("content-length")) {
                case Some(raw) =>
                    /* 只认纯数字（isDigits 见 strx.cj）；非数字的 Content-Length 交给下游处理，
                     * 本闸门不替服务器判断报文合法性。
                     *
                     * ⚠ 先判位数再 parse：`Int64.parse` 遇到 20 位以上的数字会**抛异常**
                     *   （溢出），而这里是中间件最外层，异常会变成 500 —— 一个"报 413"的闸门
                     *   反被超长 Content-Length 打成 500。15 位十进制（10^15）早就远超 64 KiB，
                     *   直接按"过大"处理即可，不必解析。 */
                    if (isDigits(raw)) {
                        var over = (raw.size > 15)
                        if (!over && Int64.parse(raw) > MAX_BODY_BYTES) {
                            over = true
                        }
                        if (over) {
                            sendError(ctx, apiErrMsg("PAYLOAD_TOO_LARGE",
                                "请求体过大（上限 ${MAX_BODY_BYTES} 字节）"))
                            return
                        }
                    }
                case None => ()
            }
            let ct = ctx.contentType()
            /* 空 Content-Type 视为"没有 body"（例如 DELETE），放行。
             * 其余只认文本/表单/JSON 三类 —— 框架的 bodyParser 认它们，
             * 而这之外的类型会绕过它的读取路径（见文件头）。 */
            if (ct.size > 0 && ct != "application/json" &&
                ct != "application/x-www-form-urlencoded" && !startsWithAscii(ct, "text/")) {
                sendError(ctx, apiErrMsg("UNSUPPORTED_MEDIA_TYPE",
                    "请求体格式不受支持，请使用 application/json"))
                return
            }
        }
        next()
    }
}
