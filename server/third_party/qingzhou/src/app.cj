package qingzhou

import std.collection.*
import std.env.*
import stdx.net.http.*
import stdx.net.tls.*
import stdx.crypto.x509.*
import stdx.crypto.keys.*
import stdx.log.*
import stdx.logger.*

/*
 * SPDX-License-Identifier: MIT
 *
 * QingZhou - Application.
 *
 * Copyright (c) 2026 guowei
 * BIT Foundational Software And Systems Lab
 *
 *  - use(mw): register business middleware (chainable)
 *  - onError(mw): register error handler (called only when business chain throws)
 *  - listen(port): boot stdx server with a custom catch-all distributor
 *    that forwards every request to the QingZhouApp handler. The stdx
 *    built-in `DirectDistributor` is exact-match only (one entry per
 *    literal path) and would otherwise fall back to its own NotFoundHandler
 *    for /hello, /users/42, etc. Our router middleware then decides
 *    200/404/405 internally.
 */
public class QingZhouApp {
    private let stack: ArrayList<Middleware> = ArrayList<Middleware>()
    private let errorStack: ArrayList<Middleware> = ArrayList<Middleware>()

    public init() {}

    public func use(mw: Middleware): QingZhouApp {
        stack.add(mw)
        return this
    }

    public func onError(mw: Middleware): QingZhouApp {
        errorStack.add(mw)
        return this
    }

    public func handler(): AppHandler {
        return AppHandler(stack, errorStack)
    }

    /* Blocking: boot the server and block until it is shut down.
     * Equivalent to serve(port).wait(). Kept for the common demo use. */
    public func listen(port: UInt16): Unit {
        let handle = serve(port)
        handle.wait()
    }

    /* v0.3: non-blocking boot. Spawns the blocking server.serve() onto a
     * background CJThread and returns a handle. Call shutdown() to stop
     * accepting new connections and drain in-flight requests (graceful
     * shutdown); call wait() to simply block until the server exits. */
    public func serve(port: UInt16): ServerHandle {
        bootServer(port, None)
    }

    /* HTTPS: boot a TLS server. certPem / keyPem are PEM-encoded strings —
     * the X.509 certificate chain and its matching private key. */
    public func serveTls(port: UInt16, certPem: String, keyPem: String): ServerHandle {
        let certs = X509Certificate.decodeFromPem(certPem)
        // RSAPrivateKey.decodeFromPem 在 stdx 1.0.5.1 与 1.1.3.1 均实现；
        // PrivateKey 接口上的 decodeFromPem 在 1.1.x 已移除，故走具体类型。
        let key = RSAPrivateKey.decodeFromPem(keyPem)
        bootServer(port, Some(TlsServerConfig(certs, key)))
    }

    /* Blocking HTTPS boot, equivalent to serveTls(port, cert, key).wait(). */
    public func listenTls(port: UInt16, certPem: String, keyPem: String): Unit {
        let handle = serveTls(port, certPem, keyPem)
        handle.wait()
    }

    /* Shared boot path for HTTP (tls=None) and HTTPS (tls=Some(config)).
     * Builds the catch-all distributor, optional TLS layer, logger and
     * spawns the blocking server.serve() onto a background thread. */
    private func bootServer(port: UInt16, tls: ?TlsServerConfig): ServerHandle {
        let app = handler()
        // Build server with our custom distributor before .build().
        let dispatcher = CatchAllDistributor({ httpCtx: HttpContext =>
            let ctx = Context(httpCtx)
            app.handle(ctx)
        })
        // 抑制 stdx 服务器内部日志噪音（如客户端断开连接的 WARN），只保留 ERROR。
        // 框架自己的请求日志由 logger() 中间件负责，不受此设置影响。
        let serverLog = SimpleLogger(getStdOut())
        serverLog.level = LogLevel.ERROR
        var builder = ServerBuilder()
            .addr("0.0.0.0").port(port)
        match (tls) {
            case Some(cfg) => builder = builder.tlsConfig(cfg)
            case None => ()
        }
        let server = builder
            .distributor(dispatcher)
            .logger(serverLog)
            .build()
        println("QingZhou listening on :${port}")
        let fut = spawn {
            server.serve()
        }
        return ServerHandle(server, fut)
    }
}

/*
 * v0.3: handle to a running server, returned by QingZhouApp.serve().
 * shutdown() is the graceful path: close() stops the accept loop and
 * drains in-flight requests before serve() returns; wait() just blocks
 * until the server thread finishes. Both are safe to call once.
 *
 * NOTE on signals: Cangjie's std.runtime.Signal is not supported on
 * Windows, so there is no portable Ctrl+C -> shutdown() hook here. On
 * POSIX targets the app can wire Signal.SIGINT to a shutdown flag; on
 * Windows, trigger shutdown() from an admin endpoint or a second thread.
 */
public class ServerHandle {
    private let server: Server
    private let fut: Future<Unit>

    init(server: Server, fut: Future<Unit>) {
        this.server = server
        this.fut = fut
    }

    public func shutdown(): Unit {
        server.close()
        fut.get()
    }

    public func wait(): Unit {
        fut.get()
    }
}

/*
 * Custom distributor: register() is a no-op (the framework does its own
 * routing inside the Koa chain); distribute(path) always returns the
 * same root handler so stdx never falls through to its own NotFoundHandler.
 */
class CatchAllDistributor <: HttpRequestDistributor {
    private let root: HttpRequestHandler

    init(root: (HttpContext) -> Unit) {
        this.root = LambdaHandler(root)
    }

    public func register(path: String, handler: (HttpContext) -> Unit): Unit {
        // intentional no-op: paths are handled by the framework's router
    }

    public func register(path: String, handler: HttpRequestHandler): Unit {
        // intentional no-op
    }

    public func distribute(path: String): HttpRequestHandler {
        return root
    }
}

/*
 * Adapt a (HttpContext) -> Unit lambda into a HttpRequestHandler.
 * HttpRequestHandler is an interface, so we need a concrete class.
 */
class LambdaHandler <: HttpRequestHandler {
    private let f: (HttpContext) -> Unit

    init(f: (HttpContext) -> Unit) {
        this.f = f
    }

    public func handle(ctx: HttpContext): Unit {
        f(ctx)
    }
}
