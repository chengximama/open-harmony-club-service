package qingzhou

/*
 * SPDX-License-Identifier: MIT
 *
 * QingZhou - token-based authentication middleware.
 *
 * Copyright (c) 2026 guowei
 * BIT Foundational Software And Systems Lab
 *
 * 无状态 token 鉴权（前后端分离友好）：
 *   - issueToken(userId, secret)  签发 HMAC-SHA256 签名的 token（"userId.sig"）
 *   - verifyToken(token, secret)  校验并取回 userId（防篡改）
 *   - authRequired(secret)        中间件：校验 Authorization: Bearer <token>
 *
 * 依赖 security.cj 的 signValue / verifySigned（HMAC-SHA256）。
 * 校验通过后把 userId 写入 ctx.state["userId"]，业务代码用
 * ctx.getStateOr("userId", "") 读取。
 */

/* 签发 token。userId 建议不含 "."（signValue 用最后一个 "." 分割签名）。 */
public func issueToken(userId: String, secret: String): String {
    return signValue(userId, secret)
}

/* 校验 token，签名匹配返回原始 userId，否则返回 None。 */
public func verifyToken(token: String, secret: String): ?String {
    return verifySigned(token, secret)
}

/*
 * 鉴权中间件：要求 Authorization: Bearer <token>。
 * 只保护 /api 开头的路径（静态资源、SPA 页面直接放行），
 * 校验通过 -> ctx.state["userId"] 写入并放行；否则 401 并短路（不调 next）。
 */
public func authRequired(secret: String): Middleware {
    return { ctx: Context, next: () -> Unit =>
        // 仅对 /api 路径做鉴权，其余（静态/页面）放行。
        let p = ctx.path()
        if (!(p.size >= 4 && p[0..4] == "/api")) {
            next()
            return
        }
        match (ctx.requestHeader("Authorization")) {
            case Some(h) =>
                match (extractBearer(h)) {
                    case Some(t) =>
                        match (verifyToken(t, secret)) {
                            case Some(userId) =>
                                ctx.setState("userId", userId)
                                next()
                            case None =>
                                respondErr(ctx, 401, "invalid token")
                        }
                    case None =>
                        respondErr(ctx, 401, "invalid authorization header")
                }
            case None =>
                respondErr(ctx, 401, "missing authorization")
        }
    }
}

/* 从 "Bearer <token>" 中提取 token；格式不符返回 None。 */
func extractBearer(header: String): ?String {
    if (header.size > 7 && header[0..7] == "Bearer ") {
        return Some(header[7..])
    }
    return None
}
