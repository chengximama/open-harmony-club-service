package qingzhou

/*
 * SPDX-License-Identifier: MIT
 *
 * 社团管理工具 · 运维台（admin 构建）入口
 *
 * 这一份是**我们自己的入口**，基线是上游 examples/admin.cj（轻舟快照里的后台示例），
 * 做三件事：
 *   1) 原样保留上游那套（登录 / me / dashboard / users / roles / perms / health /
 *      /admin/shutdown + 静态托管 SPA），因为上游预构建的 admin-web 前端就按这套接口写。
 *   2) 加一组「/api/club/…」运维接口：直接读社团库文件（只读），
 *      一切**写**操作由前端带会长令牌直接打 club-server 的真实 API（见下）。
 *   3) 修掉上游那处 HTTP 状态码问题：上游 `respondOk/respondErr` 只写 body 的 code，
 *      而 `passOnNotFound` 的路由 miss 时会先把 ctx.status 置成 404，于是"成功响应带 404"。
 *      现在入口是我们的代码，加一个链尾的 statusNormalizer() 按 body.code 回写状态码。
 *      （归属证据见 docs/API-NOTES.md 坑 34；上游 examples/admin.cj 仍留在快照里作对照。）
 *
 * 为什么写操作不直连社团库
 *   club-server 与运维台是两个进程。若都直接写同一个 db.json，就是 last-writer-wins，
 *   会静默丢数据，还会绕过 club-server 里的权限判定（N-7）、两阶段赋值（N-15）、
 *   部门一致性（N-18）等约束。所以：
 *     读 = 运维台直接读文件（club-server 不在跑也能用，且读的是原子落盘的完整文件）
 *     写 = 前端 fetch club-server 的「/api/v1/…」（CORS 已开、方法与 Authorization 头都在白名单里），
 *          用会长手机号+口令现场登录拿令牌，令牌只存在浏览器 localStorage
 *  运维台自己的 RBAC 只负责"谁能打开这个页面"（默认仅角色 1 = admin）。
 *
 * 编译：build.ps1 -Target admin（框架 32 个文件 + 我们这 6 个：store / timex / strx /
 *       fw_rbac_store / ops/club_json / ops/club_view / ops/admin_main）
 * 运行：cd build\admin ; .\admin.exe   ->  http://127.0.0.1:3000/（运维页 /club）
 */

import std.collection.*
import std.convert.*
import std.fs.*
import std.time.*
import stdx.encoding.json.*

/* 优雅关闭触发器：闭包捕获 this，POST /admin/shutdown 置 true。 */
class OpsShutdownFlag {
    public var requested: Bool = false
    init() {}
}

/* 运维台配置（来自 admin.env，缺省值见 main 里）。 */
class OpsConfig {
    public var dataDir: String = "../data"        /* 社团库目录（含 db.json / audit.log） */
    public var apiBase: String = "http://127.0.0.1:8080"  /* 服务端自己探测用 */
    public var clubPort: Int64 = 8080             /* 前端拼 club-server 地址用 */
    public var adminDataDir: String = "admin-data" /* 备份落这里 */
    public var rbacDb: String = "admin-data/rbac.json"
    /* 专用运维账号（club-server 侧的 `role = ops`，由 club-server init-ops 创建）。
     * 为什么由后台代持：运维不该由会长执行 —— 运维人员只用后台账号登录（口令见 N-29 的说明），
     * 写操作以这个运维账号的身份发出去，club-server 的审计里 actor 就是"运维"。 */
    public var clubUser: String = ""
    public var clubPass: String = ""
    public init() {}
}

/*
 * 运维会话（内存缓存）：后台用 club_user/club_pass 登录 club-server 换到的令牌。
 * 只在后台进程内存里，不落盘；TTL 内复用，避免每次开页面都烧一次 PBKDF2（~400 ms）。
 */
class ClubSession {
    public var token: String = ""
    public var at: Int64 = 0
    public var name: String = ""
    public var role: String = ""
    public var phone: String = ""
    public var err: String = ""
    public init() {}
}

/* 缓存有效期（秒）：club-server 的令牌本身是 30 天，这里只是别把登录做得太频繁。 */
let OPS_SESSION_TTL: Int64 = 6 * 3600

/* ===================== 响应壳（与上游 admin 前端约定一致：{code,message,data}） ===================== */

func opsOk(ctx: Context, data: JsonValue): Unit {
    let o = JsonObject()
    jPutInt(o, "code", 0)
    jPutStr(o, "message", "ok")
    o.put("data", data)
    ctx.status(200).json(o.toString())
}

func opsErr(ctx: Context, status: Int64, code: Int64, message: String): Unit {
    let o = JsonObject()
    jPutInt(o, "code", code)
    /* 用 JsonObject 序列化，转义交给 toString()（手拼字符串会在中文/引号/路径上翻车） */
    jPutStr(o, "message", message)
    o.put("data", JsonNull())
    ctx.status(status).json(o.toString())
}

/*
 * 链尾修状态码：跑完后面的中间件后，若 body 是统一响应壳（以 {"code": 开头），
 * 就按 code 回写 HTTP 状态（0 → 200，其余取 code 本身）。
 *
 * 为什么需要：上游 authRequired / requirePermission / respondErr 只写 body.code 不设 status，
 * 而 passOnNotFound 的路由在 miss 时会先把 status 置成 404 —— 于是 /api/me 拿到的是
 * "HTTP 404 + body code=0"。静态文件的 body 不以 {"code": 开头，因此不受影响。
 */
func statusNormalizer(): Middleware {
    return { ctx: Context, next: () -> Unit =>
        next()
        let body = ctx._peekBody()
        if (body.size < 9) { return }
        if (body[0..8] != "{\"code\":") { return }
        var code: ?Int64 = None
        try {
            code = jsonGetInt64(JsonValue.fromStr(body).asObject(), "code")
        } catch (e: Exception) {
            code = None
        }
        match (code) {
            case Some(n) => ctx.status(statusForCode(n))
            case None => ()
        }
    }
}

func statusForCode(n: Int64): Int64 {
    if (n == 0) { return 200 }
    if (n >= 100 && n <= 599) { return n }
    return 500
}

/* 错误兜底：上游用 jsonErrorHandler（body 是 {"error":...}），这里换成响应壳，前端才认。 */
func opsErrorHandler(): Middleware {
    return { ctx: Context, _: () -> Unit =>
        match (ctx.err()) {
            case Some(e) =>
                if (ctx._peekStatus() == 200 && ctx._peekBody().size == 0) {
                    opsErr(ctx, 500, 500, "运维台内部错误：${e.message}")
                }
                ctx.trace("[err] ${e.message}")
            case None => ()
        }
    }
}

/* ===================== 路径工具 ===================== */

func opsDirOf(p: String): String {
    var i = p.size - 1
    while (i >= 0) {
        let c = p[i]
        if (c == UInt8(0x2F) || c == UInt8(0x5C)) {   /* / 或 \ */
            if (i == 0) { return p[0..1] }
            return p[0..i]
        }
        i -= 1
    }
    return "."
}

func opsJoin(a: String, b: String): String {
    if (a.size == 0) { return b }
    let last = a[a.size - 1]
    if (last == UInt8(0x2F) || last == UInt8(0x5C)) {
        return a + b
    }
    return a + "/" + b
}

/*
 * 把首次生成的种子口令追加到 admin.env（N-29，2026-09-17）。
 *
 * 只在**刚建库、且口令是本次随机生成**时调用。此时 admin.env 里本来就没有
 * `admin_pass` / `user_pass` 两行（build.ps1 的模板已不再写死它们），
 * 所以直接追加不会产生重复键。
 *
 * 写不进去不致命（口令已经打印在控制台），但必须**显式告警**，绝不静默。
 */
func persistSeedCreds(envPath: String, adminPass: String, userPass: String): Unit {
    try {
        let block = "\n# ── 首次启动自动生成的后台账号口令（N-29：不再使用写死的默认值）──\n" +
            "admin_pass=${adminPass}\n" +
            "user_pass=${userPass}\n"
        File.appendTo(envPath, block.toArray())
    } catch (e: Exception) {
        println("[admin] ⚠ 口令未能写回 ${envPath}（${e.message}）—— 请立即手工记下上面的口令！")
    }
}

/* 备份文件后缀：yyyyMMdd-HHmmss（本地时间，够用且不会有非法字符）。
 * 字段名按 std.time.DateTime 的实际口径：month 是枚举（要 toInteger），日期是 dayOfMonth。 */
func opsStamp(): String {
    let t = DateTime.now()
    return "${t.year}${pad2(t.month.toInteger())}${pad2(t.dayOfMonth)}-${pad2(t.hour)}${pad2(t.minute)}${pad2(t.second)}"
}

/* ===================== 社团库读取（只读） ===================== */

/*
 * 确保有一个可用的 club-server 运维会话（必要时登录）。
 *
 * 登录用框架 httpclient.cj 的 httpPostJson —— 它语义上"非 2xx / 网络错误一律返回 None"，
 * 所以我们再探一次 /health 来区分"连不上"和"凭据不对"（两类问题处置完全不同）。
 */
func clubSessionEnsure(cfg: OpsConfig, sess: ClubSession, force: Bool): Unit {
    let now = nowEpoch()
    if (!force && sess.token.size > 0 && now - sess.at < OPS_SESSION_TTL) {
        return
    }
    let url = opsJoin(cfg.apiBase, "api/v1/auth/login")
    let body = JsonObject()
    jPutStr(body, "phone", cfg.clubUser)
    jPutStr(body, "password", cfg.clubPass)
    sess.token = ""
    sess.err = ""
    match (httpPostJson(url, body.toString())) {
        case Some(text) =>
            var token = ""
            var name = ""
            var role = ""
            var phone = ""
            try {
                let root = JsonValue.fromStr(text).asObject()
                match (jsonGetObject(root, "data")) {
                    case Some(d) =>
                        token = jsonGetStr(d, "token") ?? ""
                        match (jsonGetObject(d, "member")) {
                            case Some(m) =>
                                name = jsonGetStr(m, "name") ?? ""
                                role = jsonGetStr(m, "role") ?? ""
                                phone = jsonGetStr(m, "phone") ?? ""
                            case None => ()
                        }
                    case None => ()
                }
            } catch (e: Exception) {
                token = ""
            }
            if (token.size == 0) {
                sess.err = "club-server 的登录响应看不懂（版本不匹配？）"
                return
            }
            sess.token = token
            sess.at = now
            sess.name = name
            sess.role = role
            /* 登录响应里的 member 是"简报"（不含手机号），手机号以配置为准 */
            sess.phone = cfg.clubUser
        case None =>
            /* 区分"连不上"与"凭据不对" —— 两类问题的处置完全不同 */
            match (httpGetText(opsJoin(cfg.apiBase, "health"))) {
                case Some(_) => sess.err = "运维账号凭据被拒绝：club_user=${cfg.clubUser}（口令错？账号刚 init-ops 但 club-server 没重启？被 retire-ops 停用？）"
                case None =>
                    /*
                     * 2026-09-17：https:// 必须单独说清楚，否则会把人带到完全错误的方向。
                     *
                     * 框架的 httpPostJson / httpGetText 用的是默认 ClientBuilder，**没有 TLS 配置**
                     * （httpclient.cj 的文件头就写着"需要 TLS 请直接用 stdx.net.http.Client"），
                     * 而 club-server 用的又是自签证书 —— 两者叠加必然连不上。
                     * 实测：club_api=https://127.0.0.1:8443 时落到这里，但服务其实**好好起着**，
                     * 原先那句"没起？"是错的诊断。
                     */
                    if (startsWithAscii(cfg.apiBase.toAsciiLower(), "https://")) {
                        sess.err = "运维台连不上 HTTPS 的 club-server：${cfg.apiBase}。" +
                            "出站客户端没有 TLS 配置，自签证书也过不了校验 —— " +
                            "请让 club-server 另以**明文 HTTP** 起一个本机端口（如 serve 8080），" +
                            "把 club_api 指向它，并用防火墙限制该端口的来源。"
                    } else {
                        sess.err = "连不上 club-server：${cfg.apiBase}（没起？地址/端口在 admin.env 里改）"
                    }
            }
    }
}

/*
 * 每个请求现读现解析（社团库是 KB~MB 级、运维台访问频率极低），换取"永远最新"，
 * 且不需要缓存失效逻辑。读的是原子落盘后的完整文件（club-server 写 .tmp 再 rename）。
 */
func withClub(ctx: Context, dataDir: String, f: (Store) -> JsonValue): Unit {
    var st: ?Store = None
    try {
        st = Some(storeLoad(dataDir))
    } catch (e: Exception) {
        /* storeLoad 对损坏数据是 fail closed（宁可起不来也不覆盖），这里如实回报。 */
        opsErr(ctx, 500, 500, "社团库无法解析：${e.message}")
        return
    }
    match (st) {
        case Some(s) => opsOk(ctx, f(s))
        case None => opsErr(ctx, 500, 500, "社团库未加载")
    }
}

/* ===================== 运维台自己的权限闸门 ===================== */

/*
 * 「/api/club/…」只放给 admin 角色（roleId == 1）。
 * 上游的 requirePermission 是按"路径 → 权限码"配的，运维接口不在它的表里，
 * 所以这里按角色判定；登录态已由 authRequired 保证（userId 在 ctx.state）。
 */
func requireClubOps(store: RbacStore): Middleware {
    return { ctx: Context, next: () -> Unit =>
        let p = ctx.path()
        let isClub = p.size >= 10 && p[0..10] == "/api/club/"
        if (!isClub) {
            next()
            return
        }
        var uid: Int64 = 0
        try {
            uid = Int64.parse(ctx.getStateOr("userId", "0"))
        } catch (e: Exception) {
            uid = 0
        }
        match (store.findUserById(uid)) {
            case Some(u) =>
                if (u.roleId == 1) {
                    next()
                } else {
                    opsErr(ctx, 403, 403, "forbidden: 运维页仅限 admin 角色")
                }
            case None =>
                opsErr(ctx, 401, 401, "unauthorized")
        }
    }
}

/* ===================== 入口 ===================== */

main(): Int64 {
    /* ---------- 配置外置（复用 config.cj 的 .env 加载） ---------- */
    let envPath = "./admin.env"
    let cfg = loadConfigFile(envPath)
    let port = parseUInt16Or(cfg.getOr("port", "3000"), 3000)
    let dbPath = cfg.getOr("db", "admin-data/rbac.json")
    let ttl = cfg.getIntOr("ttl", 7200)
    let secret = match (cfg.get("secret")) {
        case Some(s) => s
        case None =>
            let r = randomHex(32)
            println("[admin] 警告：admin.env 未配置 secret，使用随机值（重启后所有 token 失效）")
            r
    }

    let ops = OpsConfig()
    ops.dataDir = cfg.getOr("club_data", "../data")
    ops.apiBase = cfg.getOr("club_api", "http://127.0.0.1:8080")
    ops.clubPort = cfg.getIntOr("club_port", 8080)
    ops.rbacDb = dbPath
    ops.adminDataDir = opsDirOf(dbPath)
    ops.clubUser = cfg.getOr("club_user", "")
    ops.clubPass = cfg.getOr("club_pass", "")
    /* 运维会话（内存缓存）：后台用它以**运维账号**的身份调 club-server */
    let clubSess = ClubSession()

    /* ---------- 后台自己的 RBAC 库（JSON 文件，见 src/fw_rbac_store.cj） ----------
     * N-29（2026-09-17）：种子口令**不再写死 admin123 / user123**。
     *   · admin.env 给了 admin_pass / user_pass → 用给的；
     *   · 没给 → 首次建库时随机生成，**写回 admin.env** 并在下面醒目打印一次。
     * 改动原因与完整复现见 docs/code-review.md 的 N-29：
     * 写死的默认口令 + 运维台监听 0.0.0.0 = 同网段任何人可拿到 ops 令牌接管会长账号。
     */
    let creds = SeedCreds()
    creds.adminPass = cfg.getOr("admin_pass", "")
    creds.userPass = cfg.getOr("user_pass", "")
    let passFromConfig = creds.adminPass
    let store = RbacStore(dbPath, creds)
    if (passFromConfig.size == 0 && creds.adminPass.size > 0) {
        /* 刚建库、且口令是本次随机生成的 —— 落盘 + 只打印这一次 */
        persistSeedCreds(envPath, creds.adminPass, creds.userPass)
        println("")
        println("========================================================")
        println("  首次启动：已为后台账号生成随机口令（只显示这一次）")
        println("    admin  口令  ${creds.adminPass}")
        println("    user   口令  ${creds.userPass}")
        println("  已写入 ${envPath} 的 admin_pass / user_pass，请妥善保管。")
        println("========================================================")
        println("")
    }

    let shutdownFlag = OpsShutdownFlag()
    let bootEpoch = nowEpoch()

    /* ---------- 公开路由：登录，签发标准 JWT（带 exp） ---------- */
    let publicRouter = Router()
    publicRouter.passOnNotFound = true
    publicRouter.post("/api/login", { ctx: Context, _: () -> Unit =>
        let username = bodyStrOr(ctx, "username", "")
        let password = bodyStrOr(ctx, "password", "")
        match (store.findUserByUsername(username)) {
            case Some(u) =>
                if (verifyPassword(password, u.passwordHash)) {
                    let token = issueTokenTtl(u.id.toString(), secret, ttl)
                    /* 前端 api.js 取的是 data.token（与上游一致） */
                    let o = JsonObject()
                    jPutStr(o, "token", token)
                    opsOk(ctx, o)
                } else {
                    opsErr(ctx, 401, 401, "invalid credentials")
                }
            case None =>
                opsErr(ctx, 401, 401, "invalid credentials")
        }
    })

    /* ---------- 登录即可访问 ---------- */
    let authRouter = Router()
    authRouter.passOnNotFound = true
    authRouter.get("/api/me", { ctx: Context, _: () -> Unit =>
        let userId = Int64.parse(ctx.getStateOr("userId", "0"))
        match (store.findUserById(userId)) {
            case Some(u) =>
                let o = JsonObject()
                jPutInt(o, "id", u.id)
                jPutStr(o, "username", u.username)
                jPutStr(o, "role", store.roleNameOf(u.roleId))
                jPutBool(o, "can_ops", u.roleId == 1)
                opsOk(ctx, o)
            case None =>
                opsErr(ctx, 401, 401, "unauthorized")
        }
    })
    authRouter.get("/api/dashboard", { ctx: Context, _: () -> Unit =>
        let o = JsonObject()
        let stats = JsonObject()
        jPutInt(stats, "users", store.listUsers().size)
        jPutInt(stats, "roles", store.listRoles().size)
        o.put("stats", stats)
        opsOk(ctx, o)
    })

    /* ---------- 管理路由：后台用户 / 角色 / 权限（上游那套，保持不动） ---------- */
    let mgmtRouter = Router()
    mgmtRouter.passOnNotFound = true
    mgmtRouter.get("/api/users", { ctx: Context, _: () -> Unit =>
        let arr = JsonArray()
        for (u in store.listUsers()) {
            let o = JsonObject()
            jPutInt(o, "id", u.id)
            jPutStr(o, "username", u.username)
            jPutStr(o, "role", store.roleNameOf(u.roleId))
            arr.add(o)
        }
        opsOk(ctx, arr)
    })
    mgmtRouter.post("/api/users", { ctx: Context, _: () -> Unit =>
        let username = bodyStrOr(ctx, "username", "")
        let password = bodyStrOr(ctx, "password", "")
        let roleId = match (bodyInt64(ctx, "roleId")) {
            case Some(r) => r
            case None => Int64(2)
        }
        if (username.size == 0 || password.size == 0) {
            opsErr(ctx, 400, 400, "username and password required")
            return
        }
        let hash = hashPassword(password, "qz2026", 1000)
        let id = store.createUser(username, hash, roleId)
        let o = JsonObject()
        jPutInt(o, "id", id)
        jPutStr(o, "username", username)
        opsOk(ctx, o)
    })
    mgmtRouter.delete("/api/users/:id", { ctx: Context, _: () -> Unit =>
        let id = Int64.parse(ctx.paramOr("id", "0"))
        if (store.deleteUser(id)) {
            opsOk(ctx, JsonNull())
        } else {
            opsErr(ctx, 404, 404, "user not found")
        }
    })
    mgmtRouter.get("/api/roles", { ctx: Context, _: () -> Unit =>
        let arr = JsonArray()
        for (r in store.listRoles()) {
            let o = JsonObject()
            jPutInt(o, "id", r.id)
            jPutStr(o, "name", r.name)
            arr.add(o)
        }
        opsOk(ctx, arr)
    })
    mgmtRouter.get("/api/perms", { ctx: Context, _: () -> Unit =>
        let arr = JsonArray()
        for (pm in store.listPermissions()) {
            let o = JsonObject()
            jPutInt(o, "id", pm.id)
            jPutStr(o, "code", pm.code)
            jPutStr(o, "name", pm.name)
            arr.add(o)
        }
        opsOk(ctx, arr)
    })

    /* ---------- 运维路由：社团管理（只读；写走 club-server，见文件头） ---------- */
    let clubRouter = Router()
    clubRouter.passOnNotFound = true

    /* 前端拿这些去拼 club-server 的地址（浏览器所在的机器可能不是服务端那台）。 */
    clubRouter.get("/api/club/config", { ctx: Context, _: () -> Unit =>
        let o = JsonObject()
        jPutStr(o, "api_base", ops.apiBase)
        jPutInt(o, "club_port", ops.clubPort)
        jPutStr(o, "club_data_dir", ops.dataDir)
        jPutStr(o, "club_db_file", opsJoin(ops.dataDir, "db.json"))
        jPutStr(o, "admin_data_dir", ops.adminDataDir)
        jPutStr(o, "rbac_db", ops.rbacDb)
        jPutInt(o, "admin_port", Int64(port))
        jPutBool(o, "ops_account_configured", ops.clubUser.size > 0 && ops.clubPass.size > 0)
        jPutStr(o, "ops_account", ops.clubUser)
        clubPutTime(o, "boot_at", bootEpoch)
        opsOk(ctx, o)
    })

    /*
     * 运维会话：后台用 admin.env 里的**专用运维账号**（club-server 的 role = ops）
     * 登录 club-server，把令牌交给前端。
     *
     * 为什么这样做（而不是让运维人员自己输会长口令，也不是后台逐条代理写）：
     *   · 运维人员只登录后台一次（口令见 N-29 的说明），不需要知道任何社团账号的口令；
     *   · 写操作的**身份**是运维账号 —— club-server 的审计里 actor 就是"运维"，
     *     与会长做的操作分得清清楚楚（职责分离）；
     *   · 前端仍然直连 club-server（CORS 已开），因此 PATCH/DELETE 这些方法都能用，
     *     后台不必自己实现一套 HTTP 转发。
     * 令牌只在本进程内存里缓存（TTL 6 小时），前端拿到的也只是这个运维令牌。
     */
    clubRouter.get("/api/club/session", { ctx: Context, _: () -> Unit =>
        let o = JsonObject()
        if (ops.clubUser.size == 0 || ops.clubPass.size == 0) {
            jPutBool(o, "configured", false)
            jPutStr(o, "hint", "未配置运维账号：先在 club-server 跑 " +
                "`club-server init-ops <手机号> <口令> <数据目录>`，" +
                "再把手机号/口令填进 admin.env 的 club_user / club_pass")
            opsOk(ctx, o)
            return
        }
        let force = ctx.queryParamOr("force", "") == "1"
        clubSessionEnsure(ops, clubSess, force)
        jPutBool(o, "configured", true)
        jPutStr(o, "api_base", ops.apiBase)
        jPutInt(o, "club_port", ops.clubPort)
        jPutStr(o, "token", clubSess.token)
        if (clubSess.err.size > 0) {
            jPutStr(o, "error", clubSess.err)
        }
        let id = JsonObject()
        jPutStr(id, "name", clubSess.name)
        jPutStr(id, "phone", clubSess.phone)
        jPutStr(id, "role", clubSess.role)
        jPutStr(id, "role_label", clubRoleLabel(clubSess.role))
        o.put("identity", id)
        opsOk(ctx, o)
    })

    clubRouter.get("/api/club/overview", { ctx: Context, _: () -> Unit =>
        withClub(ctx, ops.dataDir, { s: Store => clubOverview(s) })
    })
    clubRouter.get("/api/club/members", { ctx: Context, _: () -> Unit =>
        withClub(ctx, ops.dataDir, { s: Store => clubMembers(s, ctx) })
    })
    clubRouter.get("/api/club/depts", { ctx: Context, _: () -> Unit =>
        withClub(ctx, ops.dataDir, { s: Store => clubDepts(s) })
    })
    clubRouter.get("/api/club/tasks", { ctx: Context, _: () -> Unit =>
        withClub(ctx, ops.dataDir, { s: Store => clubTasks(s, ctx) })
    })
    clubRouter.get("/api/club/plans", { ctx: Context, _: () -> Unit =>
        withClub(ctx, ops.dataDir, { s: Store => clubPlans(s) })
    })
    clubRouter.get("/api/club/links", { ctx: Context, _: () -> Unit =>
        withClub(ctx, ops.dataDir, { s: Store => clubLinks(s) })
    })
    clubRouter.get("/api/club/audit", { ctx: Context, _: () -> Unit =>
        let limit = clubIntOr(ctx.queryParamOr("limit", "200"), 200)
        let cap = if (limit > 0) { limit } else { 200 }
        withClub(ctx, ops.dataDir, { s: Store =>
            let o = JsonObject()
            let items = clubAuditLines(s, cap)
            o.put("items", items)
            jPutInt(o, "shown", items.size())
            o
        })
    })

    /*
     * 服务端侧探测 club-server（前端在别的机器上时，localhost 指的不是服务端）。
     * 只用 GET，因此走框架 httpclient.cj 的 httpGetText 就够。
     */
    clubRouter.get("/api/club/server-health", { ctx: Context, _: () -> Unit =>
        let url = opsJoin(ops.apiBase, "health")
        let t0 = MonoTime.now()
        let o = JsonObject()
        match (httpGetText(url)) {
            case Some(text) =>
                let ms = (MonoTime.now() - t0).toMilliseconds()
                jPutBool(o, "up", true)
                jPutInt(o, "ms", ms)
                jPutStr(o, "body", text)
                jPutStr(o, "url", url)
            case None =>
                jPutBool(o, "up", false)
                jPutInt(o, "ms", 0)
                jPutStr(o, "body", "")
                jPutStr(o, "url", url)
        }
        opsOk(ctx, o)
    })

    /*
     * 备份：把社团库（db.json + audit.log）复制到 <admin 数据目录>/club-backups/。
     * 纯文件复制、不动社团库本身，因此不存在双写风险。
     */
    clubRouter.post("/api/club/backup", { ctx: Context, _: () -> Unit =>
        let dbFile = opsJoin(ops.dataDir, "db.json")
        if (!exists(dbFile)) {
            opsErr(ctx, 404, 404, "找不到社团库文件：${dbFile}（club_data 配错？）")
            return
        }
        let stamp = opsStamp()
        let outDir = opsJoin(ops.adminDataDir, "club-backups")
        try {
            if (!exists(outDir)) {
                Directory.create(outDir, recursive: true)
            }
            let files = JsonArray()
            let dbOut = opsJoin(outDir, "db-${stamp}.json")
            File.writeTo(dbOut, File.readFrom(dbFile))
            files.add(JsonString(dbOut))
            let auditFile = opsJoin(ops.dataDir, "audit.log")
            if (exists(auditFile)) {
                let auditOut = opsJoin(outDir, "audit-${stamp}.log")
                File.writeTo(auditOut, File.readFrom(auditFile))
                files.add(JsonString(auditOut))
            }
            let o = JsonObject()
            o.put("files", files)
            jPutStr(o, "stamp", stamp)
            jPutInt(o, "db_bytes", File.readFrom(dbFile).size)
            opsOk(ctx, o)
        } catch (e: Exception) {
            opsErr(ctx, 500, 500, "备份失败：${e.message}")
        }
    })

    /* ---------- 运维路由：健康检查 + 优雅关闭（admin 角色保护） ---------- */
    let opsRouter = Router()
    opsRouter.passOnNotFound = true
    opsRouter.get("/health", { ctx: Context, _: () -> Unit =>
        ctx.status(200).header("content-type", "application/json")
            .body("{\"status\":\"ok\"}")
    })
    opsRouter.post("/admin/shutdown", { ctx: Context, _: () -> Unit =>
        let userId = try {
            Int64.parse(ctx.getStateOr("userId", "0"))
        } catch (e: Exception) {
            Int64(0)
        }
        match (store.findUserById(userId)) {
            case Some(u) =>
                if (u.roleId == 1) {
                    shutdownFlag.requested = true
                    opsOk(ctx, JsonNull())
                } else {
                    opsErr(ctx, 403, 403, "forbidden: admin only")
                }
            case None =>
                opsErr(ctx, 401, 401, "unauthorized")
        }
    })

    /* ---------- 静态托管 + SPA fallback ---------- */
    let staticOpts = StaticOptions()
    staticOpts.spaFallback = true
    staticOpts.enableCache = false   /* 运维台改前端要立即生效，不缓存 */

    let app = QingZhouApp()
        .use(securityHeaders())
        /* 运维页一次进来会并发拉 6~8 个接口，上游的 100/分钟太紧；这里放宽并写明理由 */
        .use(rateLimit(600, 60))
        .use(cors())
        .use(bodyParser())
        .use(statusNormalizer())
        .use(publicRouter.middleware())
        .use(authRequired(secret))
        .use(authRouter.middleware())
        .use(requirePermission(store, "GET", "/api/users", "user:list"))
        .use(requirePermission(store, "POST", "/api/users", "user:create"))
        .use(requirePermission(store, "DELETE", "/api/users", "user:delete"))
        .use(requirePermission(store, "GET", "/api/roles", "role:list"))
        .use(requirePermission(store, "GET", "/api/perms", "perm:list"))
        .use(mgmtRouter.middleware())
        .use(requireClubOps(store))
        .use(clubRouter.middleware())
        .use(opsRouter.middleware())
        .use(serveWithOpts("./admin-web/dist", staticOpts))
        .onError(opsErrorHandler())

    println("QingZhou RBAC admin · listening on :${port}")
    println("  GET  /health              健康检查")
    println("  POST /admin/shutdown      优雅关闭（需 admin 角色）")
    println("  GET  /api/club/overview   社团运维台（读社团库；写走 club-server）")
    println("  运维页 http://127.0.0.1:${port}/club")
    println("  社团库 ${ops.dataDir}　club-server ${ops.apiBase}")
    if (ops.clubUser.size > 0) {
        println("  运维身份 ${ops.clubUser}（club-server 的 role = ops：除移交会长外与会长同权）")
    } else {
        println("  ⚠ 未配置运维账号（admin.env 的 club_user / club_pass）→ 运维页只能看、不能改")
        println("    先在 club-server 跑：club-server init-ops <手机号> <口令> <数据目录>")
    }
    /*
     * N-29（2026-09-17）：两处必须显式可见的东西 —— 口令来源、以及**实际监听地址**。
     *
     * 原先这里打印的是"账号 admin/admin123"：既把公开默认口令再复述一遍，
     * 又完全没提框架把端口绑在 **0.0.0.0**（`app.cj` 的 `.addr("0.0.0.0")` 写死、
     * 无 host 参数），而文档只写 127.0.0.1 —— 读者会以为只有本机能连。
     */
    if (creds.adminPass == "admin123" || creds.userPass == "user123") {
        println("  ⚠ 后台仍在用**公开的默认口令**（admin123 / user123）。请立刻处置（任选其一）：")
        println("      · 删掉 ${dbPath} 后重启 —— 会重新生成随机口令并写回 admin.env；")
        println("      · 或把 admin.env 的 admin_pass / user_pass 改成自己的值，再同样删库重建。")
    } else {
        println("  后台口令见 admin.env 的 admin_pass / user_pass（首次启动时打印过一次，不再回显）")
    }
    println("  ⚠ 监听 0.0.0.0:${port} —— 框架固定绑全网卡，没有「只绑本机」的开关。")
    println("      运维台能看到整个社团库，请用防火墙只对运维机放行 ${port}，")
    println("      不要把它暴露到公网或整个校园网。")

    /* ---------- 优雅关闭：主线程轮询关闭标志 ---------- */
    let handle = app.serve(port)
    while (!shutdownFlag.requested) {
        sleep(Duration.second * 1)
    }
    println("shutdown requested, draining in-flight requests...")
    handle.shutdown()
    println("graceful shutdown complete")
    store.close()
    return 0
}
