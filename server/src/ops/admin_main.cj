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
    /*
     * 专用运维账号（club-server 侧的 `role = ops`，由 club-server init-ops 创建）。
     * 为什么由后台代持：运维不该由会长执行 —— 运维人员只用后台账号登录（口令见 N-29 的说明），
     * 写操作以这个运维账号的身份发出去，club-server 的审计里 actor 就是"运维"。
     *
     * ⚠ 为什么这两条要私有化 + 加锁（2026-09-17）：
     *   上面那 5 个字段只在 main() 里写一次、`serve()` 之后只读，所以裸着没有竞争；
     *   而这两条不同 —— 用**运维账号登录运维台**时（见文件上方的"运维身份"整段）
     *   opsLoginViaClub() 会在**请求线程里就地改写它们**，同时 /api/club/config、
     *   /api/club/session、clubSessionEnsure() 都在读。框架是**并发处理请求**的（每个请求一个
     *   轻量线程），而这是一对**必须一致**的值：读方若恰好插在两次赋值之间，
     *   就会拿到"新手机号 + 旧口令"这种**不可能存在**的组合，然后拿它去 club-server 登录 ——
     *   白烧一次 10 万次 PBKDF2，还会在 sess.err 里留下"凭据被拒绝"这种把人带偏的诊断
     *   （会让人以为是 club-server 或密码的问题）。
     *   所以：两个字段一起私有化，由一把 Mutex 保护，对外只暴露
     *   clubCreds()（一次取一对一致快照）与 setClubCreds()（一次写一对）。
     */
    private let credMu = Mutex()
    private var clubUser: String = ""
    private var clubPass: String = ""

    public init() {}

    /* 一致快照：返回的 user / pass 必定来自**同一次**写入（见上方注释）。 */
    public func clubCreds(): (String, String) {
        var u = ""
        var p = ""
        credMu.lock()
        try {
            u = clubUser
            p = clubPass
        } finally {
            credMu.unlock()
        }
        return (u, p)
    }

    /* 整体替换：两条一次写完。读方要么看到旧的一对、要么看到新的一对，没有中间态。 */
    public func setClubCreds(user: String, pass: String): Unit {
        credMu.lock()
        try {
            clubUser = user
            clubPass = pass
        } finally {
            credMu.unlock()
        }
    }
}

/*
 * 运维会话（内存缓存）：后台用 club_user/club_pass 登录 club-server 换到的令牌。
 * 只在后台进程内存里，不落盘；TTL 内复用，避免每次开页面都烧一次 PBKDF2（~400 ms）。
 *
 * ⚠ 为什么不直接公开 6 个 var（2026-09-17 修）：
 *   它由 main() 创建、被多个请求闭包**共享**，而框架并发处理请求。原先 6 个字段各自裸读写，
 *   于是读方可能看到"新 token 配旧 err"、"新身份配旧 token"这类**半成品组合** ——
 *   /api/club/session 是把这些字段逐个塞进 JSON 再交给前端的，前端拿到一次撕裂的组合
 *   就可能显示"身份是运维账号，但 token 是上一个账号的"。
 *   方案：字段全部私有，只留两个入口 ——
 *     · commit(...)    一次**整体替换**全部 6 个字段（登录成功时）；
 *     · markFailed(msg) 只清 token + 记 err，**身份字段保持上一次的值**（登录失败时，
 *                       与改动前的行为逐字段一致）；
 *     · view()         返回**不可变快照** ClubSessionView，读方在快照上取字段，
 *                       拿到的永远是一次完整写入的结果。
 *   没有采用"整对象引用替换"（每次 new 一个 ClubSession 换引用）的原因：那需要把
 *   ops / clubSess 再包一层可变引用并给它加锁，等于多一层间接；而这里字段少、写点只有两处，
 *   在类内加锁更直白。也没有把网络调用放进锁内（见 clubSessionEnsure 的注释）。
 */
class ClubSession {
    private let mu = Mutex()
    private var token: String = ""
    private var at: Int64 = 0
    private var name: String = ""
    private var role: String = ""
    private var phone: String = ""
    private var err: String = ""

    public init() {}

    /* 一次写完 6 个字段（读方要么看到上一次的完整会话，要么看到这一次的完整会话）。 */
    public func commit(token: String, at: Int64, name: String, role: String, phone: String,
                       err: String): Unit {
        mu.lock()
        try {
            this.token = token
            this.at = at
            this.name = name
            this.role = role
            this.phone = phone
            this.err = err
        } finally {
            mu.unlock()
        }
    }

    /*
     * 登录/续期失败：清掉 token、记下原因，**不动 at / name / role / phone**。
     * 保持"失败时身份字段还在"这一点是有意的 —— 它与改动前的逐字段行为一致，
     * 而令牌已清空，前端拿到的 error 会盖住身份展示。
     */
    public func markFailed(err: String): Unit {
        mu.lock()
        try {
            this.token = ""
            this.err = err
        } finally {
            mu.unlock()
        }
    }

    /*
     * 一致快照。与 clubCreds() / commit() / markFailed() 保持**同一种写法**（try/finally）：
     * 今天 ClubSessionView 的构造函数只做赋值、不会抛，裸 lock/unlock 也正确；
     * 但这里是全类唯一一处"往构造函数里加一行校验就会永久死锁"的写法，
     * 而重复锁定在仓颉里是直接挂住（不是抛异常），排查成本极高 —— 统一成 try/finally。
     */
    public func view(): ClubSessionView {
        mu.lock()
        var v = ClubSessionView("", 0, "", "", "", "")
        try {
            v = ClubSessionView(token, at, name, role, phone, err)
        } finally {
            mu.unlock()
        }
        return v
    }
}

/* 会话快照：view() 的返回值。字段全是 let，拿到之后怎么传都不会再变。 */
class ClubSessionView {
    public let token: String
    public let at: Int64
    public let name: String
    public let role: String
    public let phone: String
    public let err: String
    public init(token: String, at: Int64, name: String, role: String, phone: String, err: String) {
        this.token = token
        this.at = at
        this.name = name
        this.role = role
        this.phone = phone
        this.err = err
    }
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
 *
 * 线程安全（2026-09-17 复核，因为框架并发处理请求）
 *   本类**是**线程安全的，但这份保证完全依赖那把 Mutex —— 它是个 `private let`，构造期初始化，
 *   locked() / note() 两步都整体包在 lock/unlock 里（含 `tbl.get(ip) ?? OpsLoginFail()` 这条
 *   读改写），所以 HashMap 永远不会被并发改坏，也不会出现"两次失败只记了一次"的丢更新。
 *   ⚠ 因此**新增任何触碰 tbl 的方法都必须自己加锁**，或者干脆在锁内委托给已有方法；
 *   尤其是别在锁外直接读 tbl（HashMap 不是线程安全的，project 纪律见 capacity-baseline §4.4）。
 *
 * 谁在用这张表（2026-09-17 起）
 *   **两条登录分支共用一个桶**（这是本次修的缺陷之一，见 /api/login 的注释）：
 *   原先只有"转发给 club-server"的运维账号分支走节流，而"命中本地 RBAC 账号"的分支失败时
 *   直接返回 401 —— 于是一个来源可以**无限次**猜后台账号的口令（admin / user 那两个），
 *   而节流表完全没记过一笔。
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

/*
 * 按来源 IP 记登录失败的节流表（见上方整段说明）。
 * 线程安全：全部状态都在 mu 保护之下 —— 新增方法请照抄下面两个方法的形状（lock / try / finally unlock）。
 */
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
 * 节流键：把回环来源折成空串（= **不参与节流**）。
 *
 * 与 club-server 的 loginIpLocked 同口径：本机调用者本来就有更高权限，
 * 而且本项目的测试脚本都从本机打 —— 否则跑几轮测试就把自己锁 15 分钟。
 * 回环折成空串后由 OpsLoginGuard 处理：note() 忽略空键，locked() 对空键恒 false。
 *
 * 为什么要抽成函数（2026-09-17）：/api/login 的**两条分支现在共用同一张节流表**，
 * 两条分支必须用同一个键算法 —— 各算各的就会出现"同一台机器在两个分支上各有一个桶"，
 * 那"统一节流"就名不副实（换一个用户名格式就能换一个桶接着猜）。
 */
func opsThrottleKey(ctx: Context): String {
    let ip0 = opsClientIp(ctx)
    let isLoopback = (ip0 == "127.0.0.1" || ip0 == "::1" ||
        ip0 == "0:0:0:0:0:0:0:1" || ip0 == "::ffff:127.0.0.1")
    if (isLoopback) {
        return ""
    }
    return ip0
}

/* 被节流时的统一回执：两条分支共用同一句话，避免"同一件事两种说法"漂移。 */
func opsThrottleRejected(ctx: Context): Unit {
    opsErr(ctx, 429, 429, "尝试过于频繁：该来源已被临时锁定" +
        "（约 15 分钟；重启运维台立即清零）")
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

/*
 * 备份文件后缀：yyyyMMdd-HHmmss-SSS（本地时间，末尾三位是**毫秒**）。
 * 字段名按 std.time.DateTime 的实际口径：month 是枚举（要 toInteger），日期是 dayOfMonth；
 * 毫秒取 nanosecond / 1000000（DateTime 没有直接的 millisecond 属性，实测 nanosecond 可用）。
 * 为什么原来是 yyyyMMdd-HHmmss 而现在是这个（2026-09-17 修，见 opsBackupPath 的注释）。
 */
func opsStamp(): String {
    let t = DateTime.now()
    return "${t.year}${pad2(t.month.toInteger())}${pad2(t.dayOfMonth)}-${pad2(t.hour)}${pad2(t.minute)}${pad2(t.second)}-${opsPad3(t.nanosecond / 1000000)}"
}

/* 三位补零（7 -> "007"）。框架的 pad2 只补两位，毫秒要三位，所以这里自己写一个。 */
func opsPad3(n: Int64): String {
    if (n < 10) { return "00" + n.toString() }
    if (n < 100) { return "0" + n.toString() }
    return n.toString()
}

/*
 * 备份目标路径：<outDir>/<prefix>-<stamp><ext>；若该名字已被占用（或还留着它的 .tmp），
 * 就补一个递增序号 -1、-2……
 *
 * 为什么需要（2026-09-17 修）：原先文件名只到**秒**，而备份是"人可能连点两次"的操作 ——
 * 同一秒内的第二次备份会**直接覆盖**第一次的产物（同名 File.writeTo），于是"我备份了两份"
 * 悄悄变成"只剩一份"，而响应里两次返回的路径还一模一样，靠对比根本发现不了。
 * 只加毫秒还不够（同一毫秒内两次并发仍可能撞），所以这里让**文件系统判重**：只要目标名已存在
 * 就换下一个序号，名字唯一不靠时间碰运气。
 *
 * ⚠ "判重"本身是"先看后写"，两个并发请求同时看会双双选到同一个名字 —— 所以整段备份
 *   （取时间戳 → 定路径 → 写 .tmp → rename）都在全局 opsBackupMu 里串行执行。
 *   不加这道锁的话，两个并发备份可能连**同一个 .tmp 文件**都共用，把刚做完的"原子写"
 *   重新变回撕裂写（两个写者交错写同一个 tmp，再被 rename 成正式副本）。
 *   备份是低频的人工操作，串行化没有任何代价。
 */
func opsBackupPath(outDir: String, prefix: String, stamp: String, ext: String): String {
    let base = "${prefix}-${stamp}"
    var candidate = base + ext
    var n: Int64 = 1
    while (exists(opsJoin(outDir, candidate)) || exists(opsJoin(outDir, candidate + ".tmp"))) {
        candidate = "${base}-${n}${ext}"
        n += 1
    }
    return opsJoin(outDir, candidate)
}

/*
 * 原子写文件：先写同目录的 <目标>.tmp，再 rename 覆盖到目标 —— 与 store.cj / fw_rbac_store.cj
 * 的落盘口径完全一致。
 *
 * 为什么（2026-09-17 修）：原先备份是 `File.writeTo(目标, File.readFrom(源))` —— **直接往最终
 * 文件名里写**。备份的全部价值在于"出事时手上有一份完好的副本"，而直接写最终名意味着这份副本
 * 自己也可能处在"写了一半"的状态：进程被杀 / 磁盘写满 / 目标盘是移动硬盘被拔掉，
 * 留下的就是一个**残缺的 db-*.json** —— 它体积非零、文件名正常，看起来完全像一次成功的备份，
 * 而真出事的时候打开才发现是坏的（这正是"备份没验过等于没有备份"的经典形态）。
 * .tmp + rename 后：目标文件要么不存在，要么内容是完整的（同一卷上 rename 是原子的）。
 */
func opsWriteFileAtomic(dst: String, bytes: Array<UInt8>): Unit {
    let tmp = dst + ".tmp"
    File.writeTo(tmp, bytes)
    rename(tmp, to: dst, overwrite: true)
}

/*
 * 备份串行闸：见 opsBackupPath 的注释（"名字判重"是"先看后写"，必须整段串行才成立）。
 * 只有备份这一条路径用它，不参与任何其它请求，因此不会拖慢运维页的读接口。
 */
let opsBackupMu = Mutex()

/* ===================== 社团库读取（只读） ===================== */

/*
 * 确保有一个可用的 club-server 运维会话（必要时登录）。
 *
 * 登录用框架 httpclient.cj 的 httpPostJson —— 它语义上"非 2xx / 网络错误一律返回 None"，
 * 所以我们再探一次 /health 来区分"连不上"和"凭据不对"（两类问题处置完全不同）。
 *
 * 锁的边界（2026-09-17）：**HTTP 调用不在锁内**。
 *   本函数只做两件事：进门前拿一次一致快照判断"要不要登录"、出门前**整体提交**结果。
 *   中间那段网络 IO（登录一次 ~400 ms，NT 上还可能等到超时）不持锁 —— 否则一个卡住的
 *   club-server 会把 /api/club/config 这种只读配置的接口一起拖住（而它们只需要 ops.clubCreds()，
 *   根本不是同一把锁）。代价是**并发首次登录可能重复发一次**，这与改动前完全一样（原先连快照都没有），
 *   但不是新引入的问题；真要收口应该做成"单飞"（single-flight），那是独立的一轮改动。
 *   顺带一个行为改善：force 续期期间，读方看到的是**上一次的完整会话**，而不是"token 为空"的中间态。
 */
func clubSessionEnsure(cfg: OpsConfig, sess: ClubSession, force: Bool): Unit {
    let now = nowEpoch()
    if (!force) {
        let cur = sess.view()
        if (cur.token.size > 0 && now - cur.at < OPS_SESSION_TTL) {
            return
        }
    }
    /* 一致快照：手机号与口令必须成对（见 OpsConfig.clubCreds 的注释） */
    let (clubUser, clubPass) = cfg.clubCreds()
    let url = opsJoin(cfg.apiBase, "api/v1/auth/login")
    let body = JsonObject()
    jPutStr(body, "phone", clubUser)
    jPutStr(body, "password", clubPass)
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
                sess.markFailed("club-server 的登录响应看不懂（版本不匹配？）")
                return
            }
            /* 登录响应里的 member 是"简报"（不含手机号），手机号以配置为准 */
            sess.commit(token, now, name, role, clubUser, "")
        case None =>
            /* 区分"连不上"与"凭据不对" —— 两类问题的处置完全不同 */
            match (httpGetText(opsJoin(cfg.apiBase, "health"))) {
                case Some(_) => sess.markFailed("运维账号凭据被拒绝：club_user=${clubUser}（口令错？账号刚 init-ops 但 club-server 没重启？被 retire-ops 停用？）")
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
                        sess.markFailed("运维台连不上 HTTPS 的 club-server：${cfg.apiBase}。" +
                            "出站客户端没有 TLS 配置，自签证书也过不了校验 —— " +
                            "请让 club-server 另以**明文 HTTP** 起一个本机端口（如 serve 8080），" +
                            "把 club_api 指向它，并用防火墙限制该端口的来源。")
                    } else {
                        sess.markFailed("连不上 club-server：${cfg.apiBase}（没起？地址/端口在 admin.env 里改）")
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
     * 键算法统一在 opsThrottleKey()（两条登录分支共用，见那里的注释）。
     */
    let ip = opsThrottleKey(ctx)
    if (opsLoginGuard.locked(ip)) {
        opsThrottleRejected(ctx)
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
    /*
     * 这次输入的运维凭据留给运维会话用（仅内存），于是不必再手改 admin.env。
     * 两处写入都走"整体替换"入口（2026-09-17）：凭据是一对、会话是一组，读方
     * （/api/club/config、/api/club/session、clubSessionEnsure）不能看到半成品组合 ——
     * 理由见 OpsConfig / ClubSession 的注释。
     */
    ops.setClubCreds(phone, password)
    /* 登录响应里的 member 是简报、可能不含手机号，以登录时输入的手机号为准 */
    clubSess.commit(token, nowEpoch(), name, role,
        if (mphone.size > 0) { mphone } else { phone }, "")
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
    /* 一次写一对（见 OpsConfig.setClubCreds 的注释）：admin.env 里没配就是两个空串，
     * 此时运维页仍可用"运维账号登录"这条路走通（见文件上方"运维身份"整段）。 */
    ops.setClubCreds(cfg.getOr("club_user", ""), cfg.getOr("club_pass", ""))
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
     *
     * ⚠ 两条分支**共用同一张节流表**（2026-09-17 修）：
     *   原先只有分支 ② 走 OpsLoginGuard，分支 ① 失败时直接 `opsErr(401)` 走人 ——
     *   于是**本地后台账号（admin / user）可以被无限次猜口令**：登录框里打一个后台用户名，
     *   失败一万次也不会在节流表里留下任何一笔，而这张表存在的全部理由就是拦住猜口令。
     *   （分支 ② 之所以早就加了，是因为它有"未认证就能让 club-server 烧 10 万次 PBKDF2"
     *   这个更显眼的问题；分支 ① 的 verifyPassword 只有 1000 轮，看着"便宜"，但**猜口令本身就是
     *   攻击面**，便宜不等于可以对无限次尝试敞开。）
     *
     *   统一口径（逐条与分支 ② 的既有语义对齐，**只有一处例外**）：
     *     · 校验**之前**先看 locked()：锁定期内连口令都不验（否则锁只挡住了"通过"，
     *       没挡住 CPU 消耗与计时侧信道）；
     *     · 失败 → note(ip, false)（窗口内递增，达阈值锁 15 分钟）；
     *     · 成功 → 分支 ② note(ip, true)（立即清零，因为它要求先拿出**运维口令**）；
     *       分支 ① **不清零**（见 /api/login 里的长注释：只要有任意一个合法后台账号
     *       就能靠"成功一次"把计数器压回阈值以下，从而无限次猜 admin）。
     *     · 键用 opsThrottleKey()：回环来源折成空串、**不参与节流**（与分支 ② 完全一致，
     *       否则本机测试脚本跑几轮就把自己锁 15 分钟）；
     *     · 429 的回执文案也共用 opsThrottleRejected()。
     *   注意"统一"的连带影响是**有意的**：一个来源在两条分支上共用同一个桶，
     *   所以拿本地用户名刷失败次数，也会同时把这个来源的运维账号登录一起锁上 ——
     *   这正是"同一个来源的登录尝试"应有的语义（攻击者不该靠换用户名格式换一个桶）。
     */
    publicRouter.post("/api/login", { ctx: Context, _: () -> Unit =>
        let username = bodyStrOr(ctx, "username", "")
        let password = bodyStrOr(ctx, "password", "")
        match (store.findUserByUsername(username)) {
            case Some(u) =>
                let ip = opsThrottleKey(ctx)
                if (opsLoginGuard.locked(ip)) {
                    opsThrottleRejected(ctx)
                    return
                }
                if (verifyPassword(password, u.passwordHash)) {
                    /*
                     * ⚠ 成功**不清零**该来源的失败记录（2026-09-17 复核后改）。
                     *
                     * 分支 ② 成功后清零是合理的：那必须先拿出**运维口令**。
                     * 而本分支只要有一个合法后台账号就行 —— 而 `user` 那种低权账号的口令
                     * 就写在 build\admin\admin.env 里、登录页还专门提示了它的位置。
                     * 若成功即清零，任何拿到 `user` 的人都能用"4 次猜 admin + 1 次 user 成功"
                     * 的循环把计数器永远压在阈值之下，从而**无限次**猜 admin 的口令。
                     * 不清零的代价只是：管理员自己连续打错 5 次后同样被锁 15 分钟 ——
                     * 那正是这条闸门应有的语义（锁定期间 locked() 在验口令之前就返回 429）。
                     */
                    let token = issueTokenTtl(u.id.toString(), secret, ttl)
                    /* 前端 api.js 取的是 data.token（与上游一致） */
                    let o = JsonObject()
                    jPutStr(o, "token", token)
                    opsOk(ctx, o)
                } else {
                    opsLoginGuard.note(ip, false)
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
        /*
         * 重名拒绝（2026-09-17 修）。
         *
         * 原先库层 createUser() 不校验重名，而 findUserByUsername() 是在 HashMap 上取**首个匹配** ——
         * 于是"同名两个用户、登录时用的是哪一个"取决于哈希遍历顺序，是不确定的：
         * 后建的那个可能**永远登不进去**（而它明明在用户列表里、还能被单独删除），
         * 这不是"多一条脏数据"，而是"账号看起来存在但行为随机"。
         *
         * 两道：这里先拦一道，给出**明确的 400 提示**（这是用户管理页最常见的输入错误之一；
         * 若只靠库层抛异常，客户端拿到的是路由链里残留的 404 壳，见下面 /api/users/:id 的实测，
         * 那会把"你重名了"说成"没有这个接口"）；库层 createUser() 里还有一道兜底
         * （并发下预检查会漏，且将来的新调用方可能忘记预检查，见 fw_rbac_store.cj 的长注释）。
         */
        if (store.usernameTaken(username)) {
            opsErr(ctx, 400, 400, "username already exists: ${username}")
            return
        }
        let hash = hashPassword(password, "qz2026", 1000)
        /*
         * 兜底：预检查与 createUser 之间仍有并发窗口（两个请求同时建同一个用户名）。
         * 库层会抛异常，而运行时异常会穿透 handler、被链上 passOnNotFound 留下的
         * 404 壳吃掉（见下面 /api/users/:id 的实测记录）—— 于是"重名"会显示成
         * "没有这个接口"，比不兜底更误导。这里接住转成与预检查一致的 400。
         */
        var id: Int64 = 0
        try {
            id = store.createUser(username, hash, roleId)
        } catch (e: Exception) {
            opsErr(ctx, 400, 400, "username already exists: ${username}")
            return
        }
        let o = JsonObject()
        jPutInt(o, "id", id)
        jPutStr(o, "username", username)
        opsOk(ctx, o)
    })
    mgmtRouter.delete("/api/users/:id", { ctx: Context, _: () -> Unit =>
        /*
         * 路径参数必须自己 try 住（2026-09-17 修）：
         * `Int64.parse("abc")` 抛的是**运行时异常**，它会穿透 handler、一路穿到链尾的 opsErrorHandler。
         *
         * ⚠ 而 opsErrorHandler 只在"ctx.status == 200 且 body 为空"时才补我们的 `{code,message,data}` 壳 ——
         *   本链里排在 mgmtRouter **之前**的 publicRouter / authRouter 都是 passOnNotFound，它们 miss 时
         *   **已经往 ctx 写了 404 + `{"error":"Not Found","path":"..."}`**，于是那个判断为假、
         *   异常只被 ctx.trace 记一行，**那个 404 body 会原样发给客户端**。
         *   实测（修前，真机跑）：
         *     DELETE /api/users/abc -> HTTP 404  body={"error":"Not Found","path":"/api/users/abc"}
         *   所以症状不是"500 内部错误"，而是**"这条路由不存在"** —— 响应里连 `code` 字段都没有
         *   （前端 api.js 只看 json.code，会退化成一句 "request failed"），
         *   把"前端把 id 拼错了"说成"后台没有这个接口"。修后：**HTTP 400 + `{"code":400,...}`**。
         *
         * 选 **400** 而不是按 404 处理：这个 handler 里 404 的既有含义是
         * 「这个 id 的用户不存在」（deleteUser 返回 false 那一支），而"id 根本不是数字"
         * 是**请求本身**不合法。两者混成一个码之后，前端就分不清"这个人已经被删了"
         * 与"前端把 id 拼错了"—— 前者刷新列表即可自愈，后者必须改代码。
         * （与 /health 之类"宽松取默认值"不同：那些是**读**接口，坏参数不该让页面白屏；
         *   而这里是**写**接口，宁可明确拒绝。）
         */
        let rawId = ctx.paramOr("id", "")
        var id: Int64 = 0
        try {
            id = Int64.parse(rawId)
        } catch (e: Exception) {
            opsErr(ctx, 400, 400, "invalid user id: ${rawId}")
            return
        }
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
        /* 一次取一对一致的凭据快照：接口不该暴露"半次写入"的中间态（见 OpsConfig 的注释） */
        let (clubUser, clubPass) = ops.clubCreds()
        let o = JsonObject()
        jPutStr(o, "api_base", ops.apiBase)
        jPutInt(o, "club_port", ops.clubPort)
        jPutStr(o, "club_data_dir", ops.dataDir)
        jPutStr(o, "club_db_file", opsJoin(ops.dataDir, "db.json"))
        jPutStr(o, "admin_data_dir", ops.adminDataDir)
        jPutStr(o, "rbac_db", ops.rbacDb)
        jPutInt(o, "admin_port", Int64(port))
        jPutBool(o, "ops_account_configured", clubUser.size > 0 && clubPass.size > 0)
        jPutStr(o, "ops_account", clubUser)
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
        let (clubUser, clubPass) = ops.clubCreds()
        if (clubUser.size == 0 || clubPass.size == 0) {
            jPutBool(o, "configured", false)
            jPutStr(o, "hint", "未配置运维账号：先在 club-server 跑 " +
                "`club-server init-ops <手机号> <口令> <数据目录>`，" +
                "再把手机号/口令填进 admin.env 的 club_user / club_pass")
            opsOk(ctx, o)
            return
        }
        let force = ctx.queryParamOr("force", "") == "1"
        clubSessionEnsure(ops, clubSess, force)
        /* 一次取一致快照：token 与 identity 必须是**同一次**登录的结果，
         * 否则前端可能拿到"身份是运维账号、token 却是上一个账号的"这种撕裂组合（见 ClubSession 的注释） */
        let sess = clubSess.view()
        jPutBool(o, "configured", true)
        jPutStr(o, "api_base", ops.apiBase)
        jPutInt(o, "club_port", ops.clubPort)
        jPutStr(o, "token", sess.token)
        if (sess.err.size > 0) {
            jPutStr(o, "error", sess.err)
        }
        let id = JsonObject()
        jPutStr(id, "name", sess.name)
        jPutStr(id, "phone", sess.phone)
        jPutStr(id, "role", sess.role)
        jPutStr(id, "role_label", clubRoleLabel(sess.role))
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
        /*
         * limit 的默认值（200）、非法/0/负数的回退值（200）与**上界**（CLUB_AUDIT_LIMIT_MAX = 2000）
         * 全在 clubAuditLimit() 里，理由见那里的长注释。
         * 这里原先直接吃裸 limit：`?limit=99999999` 会让整份 audit.log 被切成一堆行、
         * 再为每行建一个 JsonObject（每行还两次成员名查表）—— 与 clubPaging 的 500 上界是同一类防护。
         */
        let cap = clubAuditLimit(ctx)
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
     *
     * 2026-09-17 三处修正（都是"备份本身可能不可靠"这一类）：
     *   ① 落盘改原子（opsWriteFileAtomic：先 .tmp 再 rename）—— 原先直接写最终名，
     *      中途失败会留下一个文件名正常、内容残缺的"假备份"；
     *   ② 文件名带毫秒 + 冲突自动补序号（opsBackupPath）—— 原先只到秒，同秒第二次备份
     *      会静默覆盖第一次；
     *   ③ db.json **只读一次**：原先读完写副本，末尾又 `File.readFrom(dbFile).size` 读了第二遍，
     *      于是响应里的 db_bytes 与刚写出的副本可能**不是同一个版本**（club-server 恰好在这两次读
     *      之间做了一次原子落盘就会 —— 而"运维点备份"往往正是社团库刚被写入的时候）。
     *      现在用同一份字节既写副本、又报大小，二者必然一致。
     *   另外：整段备份在 opsBackupMu 里**串行**执行 —— 见 opsBackupPath 的注释
     *   （"文件名判重"与"共用一个 .tmp"这两件事都必须串行才成立）。
     */
    clubRouter.post("/api/club/backup", { ctx: Context, _: () -> Unit =>
        let dbFile = opsJoin(ops.dataDir, "db.json")
        if (!exists(dbFile)) {
            opsErr(ctx, 404, 404, "找不到社团库文件：${dbFile}（club_data 配错？）")
            return
        }
        opsBackupMu.lock()
        try {
            let stamp = opsStamp()
            let outDir = opsJoin(ops.adminDataDir, "club-backups")
            try {
                if (!exists(outDir)) {
                    Directory.create(outDir, recursive: true)
                }
                /* 只读一次（见上方 ③）：这一份字节既用于写副本，也用于报 db_bytes */
                let dbBytes = File.readFrom(dbFile)
                let files = JsonArray()
                let dbOut = opsBackupPath(outDir, "db", stamp, ".json")
                opsWriteFileAtomic(dbOut, dbBytes)
                files.add(JsonString(dbOut))
                let auditFile = opsJoin(ops.dataDir, "audit.log")
                if (exists(auditFile)) {
                    let auditOut = opsBackupPath(outDir, "audit", stamp, ".log")
                    opsWriteFileAtomic(auditOut, File.readFrom(auditFile))
                    files.add(JsonString(auditOut))
                }
                let o = JsonObject()
                o.put("files", files)
                jPutStr(o, "stamp", stamp)
                jPutInt(o, "db_bytes", dbBytes.size)
                opsOk(ctx, o)
            } catch (e: Exception) {
                opsErr(ctx, 500, 500, "备份失败：${e.message}")
            }
        } finally {
            opsBackupMu.unlock()
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
    /*
     * 2026-09-17：**必须关掉 ETag**，否则重建前端后浏览器会卡在旧页面上（实测白屏）。
     *
     * 框架的 ETag 是"**仅按字节大小**"生成的强校验器（static.cj 的 makeETag(size) → `"<size>"`，
     * 文件头第 32 行写明），而 vite 重建时 index.html 里变的只有两个 8 位 hash 文件名 ——
     * **字节数一模一样**（实测重建前后都是 399 字节，`git cat-file -s` 两版相同）。
     * 于是 ETag 完全相同：浏览器带着 If-None-Match 回来直接拿到 **304**，继续用旧的
     * index.html，而它引用的 index-<旧hash>.js 已被 vite 删掉 → **JS 404 → 一片空白**。
     * （Last-Modified 那一路本身是对的，但它排在前面且因 mtime 已变而不匹配，
     *   于是落到 ETag 这一路命中 304，正好把这个坑踩满。）
     * 运维台只在本机/运维网内使用，每次重下发 ~115 KB 的 JS 完全可以接受 —— 正确性优先。
     */
    staticOpts.enableETag = false

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
    /* 一次取一致快照（这两条打印发生在 serve() 之前，但用法与接口侧保持一致，别再直接读字段） */
    let (bootClubUser, _bootClubPass) = ops.clubCreds()
    if (bootClubUser.size > 0) {
        println("  运维身份 ${bootClubUser}（club-server 的 role = ops：除移交会长外与会长同权）")
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
