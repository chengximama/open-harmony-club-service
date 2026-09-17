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
 *      一切**写**操作由前端带**运维账号**的令牌直接打 club-server 的真实 API（见下）。
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
 *          用**运维账号**换到的令牌（后台代持，见 /api/club/session），令牌只存在浏览器 localStorage
 *  运维台自己的 RBAC 只负责"谁能打开这个页面"：后台的 admin 角色，或者**直接用 club-server
 *  的运维账号登录**（2026-09-17 起，见下方"运维身份"整段）。
 *
 * 编译：build.ps1 -Target admin（框架 32 个文件 + 我们这 8 个：store / audit / timex / strx /
 *       fw_rbac_store / ops/club_json / ops/club_view / ops/admin_main）
 * 运行：cd build\admin ; .\admin.exe   ->  http://127.0.0.1:3000/（运维页 /club）
 */

import std.collection.*
import std.convert.*
import std.fs.*
import std.sync.*
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

/* ===================== 运维身份：运维账号直接登录运维台（2026-09-17） =====================
 *
 * 登录框现在接受**两种**凭据：
 *   ① 后台自己的账号（轻舟 RBAC：admin / user）—— 管后台自身，与上游一致；
 *   ② club-server 的**运维账号**（`role = ops`，由 `club-server init-ops` 创建）——
 *      也就是把手机号与运维口令直接填进登录框。
 *
 * 为什么加这条（原先的设计是"运维人员必须先拿到另一个后台口令，再把运维账号手填进
 * admin.env 的 club_user/club_pass"）：两套凭据、两道手工配置，而运维人员真正拥有的
 * 只有 init-ops 建的那一个。实测里这一步正是最容易被跳过、跳过之后现象最迷惑人的地方
 * （登录恒 401，而运维页名录读文件、照样看得见那个账号），见 local-deploy §2.2 / §2.7。
 *
 * 身份怎么表达：JWT 主体写成 **`ops:<手机号>`**，与后台自己的数字 userId 天然区分开。
 *   · 不必新增角色、也不必迁移 rbac.json；
 *   · framework 的 requirePermission 把非数字主体判成 userId = -1 → 后台管理接口
 *     （用户 / 角色 / 权限）对运维身份**自然关闭**，无需额外写闸门；
 *   · 运维接口的闸门在 requireClubOps() 里显式放行这一形态。
 *
 * 口令**由 club-server 校验**（不在这里离线核对 db.json）。理由：写路径本来就走
 * club-server，两边用同一个权威才不会出现"登录成功了但写操作说凭据被拒"这种分裂状态；
 * 而且 club-server 只在启动时读一次库，"刚 init-ops 但没重启"这类问题能在登录这一步
 * 就被诊断出来（见 opsLoginDiagnosis）。
 */
let OPS_SUBJECT_PREFIX: String = "ops:"

func opsSubjectOf(phone: String): String {
    return OPS_SUBJECT_PREFIX + phone
}

/* 是运维身份则返回其中的手机号；后台自己的数字主体返回 None。 */
func opsPhoneOfSubject(subject: String): ?String {
    if (subject.size > OPS_SUBJECT_PREFIX.size &&
        subject[0..OPS_SUBJECT_PREFIX.size] == OPS_SUBJECT_PREFIX) {
        return Some(subject[OPS_SUBJECT_PREFIX.size..])
    }
    return None
}

/*
 * 运维账号登录的按 IP 节流表。
 *
 * 为什么必须有：登录框会把"非后台账号"的输入**转发**给 club-server 校验，而那边每次
 * 校验都是 10 万次 PBKDF2 —— 于是运维台多了一条"未认证就能让 club-server 烧 CPU"的路径
 * （与 N-21 同一类问题）。更要紧的是 **club-server 的登录节流是按 IP 记的，而所有转发
 * 都来自运维台这一个 IP**：局域网里有人刷运维台登录，就可能把社团服务端的登录桶刷满，
 * 把真正的运维人员一起锁在门外。
 *
 * 所以这里在**转发之前**按客户端 IP 先拦一道，阈值取 club-server 的一半
 * （那边是 15 分钟 10 次，见 h_auth.cj 的 LOGIN_FAIL_LIMIT=5/两个桶），
 * 保证**单个来源**打不满 club-server 的桶。递增退避与清理策略与 h_auth.cj 同构。
 */
let OPS_LOGIN_WINDOW: Int64 = 900         /* 统计窗口（秒） */
let OPS_LOGIN_FAIL_LIMIT: Int64 = 5       /* 窗口内失败次数达到它就锁 */
let OPS_LOGIN_LOCK: Int64 = 900           /* 锁定时长（秒） */

class OpsLoginFail {
    public var count: Int64 = 0
    public var first_at: Int64 = 0
    public var locked_until: Int64 = 0
    public init() {}
}

class OpsLoginGuard {
    private let mu = Mutex()
    private var tbl: HashMap<String, OpsLoginFail> = HashMap<String, OpsLoginFail>()

    public init() {}

    public func locked(ip: String): Bool {
        mu.lock()
        var out = false
        try {
            let now = nowEpoch()
            match (tbl.get(ip)) {
                case Some(st) => out = st.locked_until > now
                case None => out = false
            }
        } finally {
            mu.unlock()
        }
        return out
    }

    /* ok = true 表示这次尝试"凭据确实有效"，成功即清空该 IP 的记录。 */
    public func note(ip: String, ok: Bool): Unit {
        /* 空键 = 回环等不参与节流的来源（见 opsLoginViaClub 里的说明） */
        if (ip.size == 0) {
            return
        }
        mu.lock()
        try {
            let now = nowEpoch()
            if (ok) {
                tbl.remove(ip)
            } else {
                let st = tbl.get(ip) ?? OpsLoginFail()
                if (st.first_at == 0 || now - st.first_at > OPS_LOGIN_WINDOW) {
                    st.first_at = now
                    st.count = 0
                }
                st.count += 1
                if (st.count >= OPS_LOGIN_FAIL_LIMIT) {
                    st.locked_until = now + OPS_LOGIN_LOCK
                    st.count = 0
                    st.first_at = now
                }
                tbl[ip] = st
                if (tbl.size > 500) {
                    let doomed = ArrayList<String>()
                    for ((k, v) in tbl) {
                        if (v.locked_until <= now && now - v.first_at > OPS_LOGIN_WINDOW) {
                            doomed.add(k)
                        }
                    }
                    for (k in doomed) {
                        tbl.remove(k)
                    }
                }
            }
        } finally {
            mu.unlock()
        }
    }
}

/* 进程内单例：登录路由是闭包，用全局量比多穿一层参数清楚。 */
let opsLoginGuard = OpsLoginGuard()

/*
 * 从 ctx.remoteAddr()（"ip:port" / "[v6]:port" / 裸 IPv6）里剥出地址，只当作**节流键**用。
 * 因此这里不需要 N-14 那种严格判定：即使切错也只是几个来源共用同一个桶（偏保守，不是绕过）。
 */
func opsClientIp(ctx: Context): String {
    let raw = ctx.remoteAddr()
    let a = raw.toArray()
    let n = a.size
    if (n == 0) {
        return ""
    }
    if (a[0] == 91) {   /* '[' → [v6]:port */
        var i: Int64 = 1
        while (i < n) {
            if (a[i] == 93) {   /* ']' */
                return String.fromUtf8(a[1..i])
            }
            i += 1
        }
        return raw
    }
    var colons: Int64 = 0
    var last: Int64 = -1
    var j: Int64 = 0
    while (j < n) {
        if (a[j] == 58) {   /* ':' */
            colons += 1
            last = j
        }
        j += 1
    }
    if (colons == 1) {
        return String.fromUtf8(a[0..last])
    }
    return raw
}

/*
 * 运维账号登录失败时的**分类诊断**（与 clubSessionEnsure 同一套口径）：
 * "连不上 club-server" 与 "凭据不对" 处置完全不同，答错方向比不答更费时间。
 */
func opsLoginDiagnosis(ops: OpsConfig, phone: String): String {
    match (httpGetText(opsJoin(ops.apiBase, "health"))) {
        case Some(_) =>
            return "登录失败：手机号 ${phone} 或口令不对。" +
                "若这是刚用 init-ops 建的账号，注意 club-server **只在启动时读一次库** —— " +
                "必须在建完账号**之后**再启动它（边跑边改不生效，见 local-deploy §2.2 ②）"
        case None =>
            if (startsWithAscii(ops.apiBase.toAsciiLower(), "https://")) {
                return "登录失败：连不上 HTTPS 的 club-server（${ops.apiBase}）。" +
                    "运维台的出站客户端没有 TLS 配置，自签证书也过不了校验 —— " +
                    "请让 club-server 另以**明文 HTTP** 起一个本机端口，并把 club_api 指向它。"
            }
            return "登录失败：连不上 club-server（${ops.apiBase}）。" +
                "运维账号的口令由 club-server 校验，所以它必须在跑 —— " +
                "先在 server\\build 下跑 `club-server serve 8080 data`，再回来登录。" +
                "（club-server 没起时，仍可用后台自己的账号 admin/user 登录，运维页只能看不能改。）"
    }
}

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
 * ② 运维账号登录：把手机号 + 口令转发给 club-server 校验（它才是口令的权威）。
 *
 * 通过且 `role = ops` → 签发主体为 **`ops:<手机号>`** 的 JWT，并把**这次输入的凭据留在
 * 内存里**（ops.clubUser / ops.clubPass），于是 /api/club/session 当场就能换到令牌 ——
 * 不必再手工往 admin.env 填 club_user / club_pass。
 * admin.env 里若配了凭据，则作为"没用运维账号登录时"的回退，行为与之前完全一致（向后兼容）。
 *
 * 凭据只在本进程内存里，不落盘、不回显；进程重启后需要重新登录一次
 * （admin.env 里配了的话则不受影响）。
 */
func opsLoginViaClub(ctx: Context, phone: String, password: String,
                     ops: OpsConfig, clubSess: ClubSession, secret: String, ttl: Int64): Unit {
    /*
     * 回环不参与节流（与 club-server 的 loginIpLocked 同口径）：本机调用者本来就有更高权限，
     * 而且本项目的测试脚本都从本机打 —— 否则跑几轮测试就把自己锁 15 分钟。
     * 实现上把回环折成空串，再由 OpsLoginGuard.note 忽略空键 / locked 对空键恒 false。
     */
    let ip0 = opsClientIp(ctx)
    let isLoopback = (ip0 == "127.0.0.1" || ip0 == "::1" ||
        ip0 == "0:0:0:0:0:0:0:1" || ip0 == "::ffff:127.0.0.1")
    let ip = if (isLoopback) { "" } else { ip0 }
    if (opsLoginGuard.locked(ip)) {
        opsErr(ctx, 429, 429, "尝试过于频繁：该来源已被临时锁定" +
            "（约 15 分钟；重启运维台立即清零）")
        return
    }
    let url = opsJoin(ops.apiBase, "api/v1/auth/login")
    let body = JsonObject()
    jPutStr(body, "phone", phone)
    jPutStr(body, "password", password)
    var token = ""
    var name = ""
    var role = ""
    var mphone = ""
    match (httpPostJson(url, body.toString())) {
        case Some(text) =>
            try {
                let root = JsonValue.fromStr(text).asObject()
                match (jsonGetObject(root, "data")) {
                    case Some(d) =>
                        token = jsonGetStr(d, "token") ?? ""
                        match (jsonGetObject(d, "member")) {
                            case Some(m) =>
                                name = jsonGetStr(m, "name") ?? ""
                                role = jsonGetStr(m, "role") ?? ""
                                mphone = jsonGetStr(m, "phone") ?? ""
                            case None => ()
                        }
                    case None => ()
                }
            } catch (e: Exception) {
                token = ""
            }
        case None => ()
    }
    if (token.size == 0) {
        opsLoginGuard.note(ip, false)
        opsErr(ctx, 401, 401, opsLoginDiagnosis(ops, phone))
        return
    }
    if (role != "ops") {
        /* 口令是对的、只是这一档身份不对 —— 不算暴力破解，清掉该 IP 的失败记录。 */
        opsLoginGuard.note(ip, true)
        opsErr(ctx, 403, 403, "该账号的角色是「${clubRoleLabel(role)}」，不是运维账号。" +
            "运维台只接受 `club-server init-ops` 建的运维账号（运维不该由会长执行）；" +
            "会长 / 成员账号请在 App 里登录。")
        return
    }
    opsLoginGuard.note(ip, true)
    /* 这次输入的运维凭据留给运维会话用（仅内存），于是不必再手改 admin.env */
    ops.clubUser = phone
    ops.clubPass = password
    clubSess.token = token
    clubSess.at = nowEpoch()
    clubSess.name = name
    clubSess.role = role
    /* 登录响应里的 member 是简报、可能不含手机号，以登录时输入的手机号为准 */
    clubSess.phone = if (mphone.size > 0) { mphone } else { phone }
    clubSess.err = ""
    println("[ops] 运维账号 ${phone} 已登录运维台（后续写操作以它的身份发出）")
    let o = JsonObject()
    jPutStr(o, "token", issueTokenTtl(opsSubjectOf(phone), secret, ttl))
    opsOk(ctx, o)
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
 * 「/api/club/…」放给两种身份：
 *   · 后台的 admin 角色（roleId == 1）—— 上游那套；
 *   · **运维账号登录**的身份（JWT 主体 `ops:<手机号>`，2026-09-17 起）—— 它本来就是
 *     这个页面的主人，用 init-ops 建的账号直接登进来时走这一支。
 * 上游的 requirePermission 是按"路径 → 权限码"配的，运维接口不在它的表里，
 * 所以这里按角色 / 主体形态判定；登录态已由 authRequired 保证（主体在 ctx.state）。
 */
func requireClubOps(store: RbacStore): Middleware {
    return { ctx: Context, next: () -> Unit =>
        let p = ctx.path()
        let isClub = p.size >= 10 && p[0..10] == "/api/club/"
        if (!isClub) {
            next()
            return
        }
        match (opsPhoneOfSubject(ctx.getStateOr("userId", ""))) {
            case Some(_) =>
                next()
                return
            case None => ()
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
                    opsErr(ctx, 403, 403, "forbidden: 运维页仅限 admin 角色或运维账号")
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
    /*
     * 登录：两种凭据都接受（见文件上方"运维身份"整段说明）。
     *   ① 后台自己的账号（轻舟 RBAC）—— 与上游一致；
     *   ② 不是后台账号时，当作 club-server 的**运维账号**（手机号）转发过去校验。
     * ① 与 ② 的失败信息分开写，避免把"用户名打错了"和"club-server 没起"混成一句。
     */
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
                opsLoginViaClub(ctx, username, password, ops, clubSess, secret, ttl)
        }
    })

    /* ---------- 登录即可访问 ---------- */
    let authRouter = Router()
    authRouter.passOnNotFound = true
    authRouter.get("/api/me", { ctx: Context, _: () -> Unit =>
        let subject = ctx.getStateOr("userId", "")
        /*
         * 运维账号登录：身份不在后台的 rbac.json 里，所以 id 恒为 0。
         * can_ops = true 让前端放行运维页；后台管理接口（用户 / 角色 / 权限）由 framework 的
         * requirePermission 按数字 userId 判定 —— 运维身份拿不到权限，因此仍是 admin 专属。
         */
        match (opsPhoneOfSubject(subject)) {
            case Some(phone) =>
                let oo = JsonObject()
                jPutInt(oo, "id", 0)
                jPutStr(oo, "username", phone)
                jPutStr(oo, "role", "ops")
                jPutBool(oo, "can_ops", true)
                jPutBool(oo, "is_ops_account", true)
                opsOk(ctx, oo)
                return
            case None => ()
        }
        var userId: Int64 = 0
        try {
            userId = Int64.parse(subject)
        } catch (e: Exception) {
            userId = 0
        }
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
        println("    （也可以直接用运维账号登录本后台，那样就不必在这里配 club_user / club_pass）")
    } else {
        println("  运维页的写操作需要一个运维账号（club-server 的 role = ops）。")
        println("    最简单的做法：直接用运维账号登录本后台（手机号 + init-ops 的口令）。")
        println("    也可以把手机号/口令填进 admin.env 的 club_user / club_pass（两种都行）。")
        println("    还没有运维账号就先建一个（**在 club-server 未运行时**执行）：")
        println("      cd server\\build ; .\\club-server.exe init-ops <手机号> <口令> data")
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
