package qingzhou

import std.time.*

/*
 * SPDX-License-Identifier: MIT
 *
 * QingZhou - logger middleware.
 *
 * Copyright (c) 2026 guowei
 * BIT Foundational Software And Systems Lab
 *
 * Replaces the  trace-only logger with a stdout-oriented access log.
 * Format:
 *
 *   <id-or-dash> <ip-or-dash> METHOD path -> status (Xms)
 *
 * Where the id is ctx._id (set by requestId()) if present, or "-" if
 * the logger runs without a prior requestId() middleware; the ip is the
 * client IP (Context.remoteIp()), or "-" when unavailable.
 *
 * Plug a custom formatter/writer via LoggerOptions to ship structured
 * logs (e.g. JSON line per request, or a File output sink).
 */

public class LoggerOptions {
    public var formatter: (Context, Int64) -> String = defaultLoggerFormatter
    public var writer: (String) -> Unit = defaultLoggerWriter

    public init() {}
}

public func defaultLoggerFormatter(ctx: Context, elapsedMs: Int64): String {
    let id = if (ctx._id.size > 0) { ctx._id } else { "-" }
    let ip = if (ctx.remoteIp().size > 0) { ctx.remoteIp() } else { "-" }
    return "${id} ${ip} ${ctx.method()} ${ctx.path()} -> ${ctx._peekStatus()} (${elapsedMs}ms)"
}

public func defaultLoggerWriter(line: String): Unit {
    println(line)
}

public func logger(): Middleware {
    return loggerWith(LoggerOptions())
}

public func loggerWith(opts: LoggerOptions): Middleware {
    return { ctx: Context, next: () -> Unit =>
        let start = MonoTime.now()
        next()
        let now = MonoTime.now()
        let elapsed = (now - start).toMilliseconds()
        let line = opts.formatter(ctx, elapsed)
        opts.writer(line)
    }
}