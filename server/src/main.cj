package qingzhou

/*
 * SPDX-License-Identifier: MIT
 *
 * 社团管理工具 · 服务端
 * 入口：serve / init-admin / test
 *
 * 构建：server/build.ps1（cjc 1.1.3 + stdx 1.1.3.1 + 轻舟源码同包编译）
 *
 * 部署约束（..\docs\deploy-windows-verify.md §3）：
 *   · **cwd 必须是 exe 所在目录**——数据目录与证书都按相对路径读
 *   · 4 个 DLL 必须与 exe 同目录（含两个 OpenSSL 3 DLL，缺失时 crypto 运行时才报错）
 */

import std.collection.*
import std.convert.*
import std.fs.*
import std.time.*
import stdx.encoding.json.*


/* 用对象持有 ServerHandle：闭包捕获 var 的语义不可靠，这里显式放进盒子里。 */
class HandleBox {
    public var handle: ?ServerHandle = None

    init() {}
}

func usage(): Unit {
    println("社团管理工具 · 服务端 v${APP_VERSION}")
    println("")
    println("用法:")
    println("  club-server init-admin <手机号> <初始密码> [数据目录] [姓名选项]")
    println("                                                         初始化首任会长与 4 个组织（仅空库可执行）")
    println("  club-server init-ops <手机号> <口令> [数据目录]         创建/重设运维账号（角色 ops；除移交会长外与会长同权）")
    println("  club-server retire-ops <手机号> [数据目录]              停用运维账号（保留记录）")
    println("  club-server serve [端口] [数据目录]                    启动 HTTP 服务（默认 8080 / data）")
    println("  club-server serve-tls [端口] [数据目录] [证书] [私钥]  启动 HTTPS（默认 8443 / data / certs/cert.pem / certs/key.pem）")
    println("  club-server test                                       运行单测")
    println("")
    println("数据目录默认 data/（相对当前工作目录）。冒烟测试用独立目录，避免碰正式数据。")
    println("证书必须是**带 SAN** 的自签证书（现代客户端只看 subjectAltName，完全忽略 CN）。")
    println("密码：8-32 位，只能用数字 / 英文 / 符号（如 ._/\\-!@#）。")
    println("⚠ 所有命令行参数只支持 ASCII —— 中文参数会让仓颉的 argv 解析直接抛异常（见 docs/API-NOTES.md 坑 11）。")
    println("  所以**中文姓名不能写进 --name**（写进去会在 main 之前就崩）：把姓名存成一个")
    println("  **UTF-8 文本文件**（内容就是姓名，可带 BOM 与结尾换行），用 --name-file <文件> 传入。")
    println("  不传姓名选项时，首任会长的姓名默认是「会长」。例：")
    println("    club-server init-admin 13800000000 <口令> data --name-file president-name.txt")
    println("    club-server init-admin 13800000000 <口令> data --name LiSi        （仅 ASCII 姓名）")
}

/* 加载数据；失败就退出——绝不带着空库继续跑。 */
func loadOrExit(dir: String): ?Store {
    try {
        return Some(storeLoad(dir))
    } catch (e: Exception) {
        println("[FATAL] ${e.message}")
        return None
    }
}

/* 预置 4 个组织（v1-scope §5，可改名） */
func seedDepartments(s: Store): Unit {
    let names = ["主席团", "课题部", "运营部", "宣传部"]
    var i: Int64 = 0
    while (i < names.size) {
        let d = Department()
        d.id = s.next_dept
        s.next_dept += 1
        d.name = names[i]
        d.sort = i
        s.departments[d.id] = d
        i += 1
    }
}

func deptIdByName(s: Store, name: String): Int64 {
    for ((_k, d) in s.departments) {
        if (d.name == name) {
            return d.id
        }
    }
    return 0
}

/* ===================== 会长姓名的输入通道（2026-09-17） =====================
 *
 * 为什么姓名不能直接当第 4 个命令行参数：**中文参数会让程序在 main 之前就崩**。
 * 实测 `club-server.exe init-admin 13700000001 TestPass2026 nametest 张三` →
 * 无输出、exit 1，只有 `IllegalArgumentException: Invalid unicode scalar value.`；
 * 中文放在手机号 / 口令 / 数据目录任一位置都一样，切代码页（936 / 65001）也不行 ——
 * 它抛在仓颉把 argv 拼成 String 那一步，早于本文件里的任何代码（docs/API-NOTES.md 坑 11）。
 * 所以中文姓名只能**绕开 argv**：写进一个 UTF-8 文本文件，用 `--name-file` 传路径。
 * （也评估过环境变量：仓颉 std 没有 `getEnv` / `envVars`，见 third_party/qingzhou/src/config.cj
 *   的说明 —— 不适合拿一个未验证的 API 去搭功能，所以不采用。）
 */

/* ASCII 空白：空格 / 制表 / LF / CR / VT / FF。姓名文件多半带一个结尾换行。 */
func isAsciiSpaceByte(c: UInt8): Bool {
    return c == UInt8(0x20) || c == UInt8(0x09) || c == UInt8(0x0A) ||
        c == UInt8(0x0D) || c == UInt8(0x0B) || c == UInt8(0x0C)
}

/*
 * 去掉首尾 ASCII 空白。只切**空白字节**，所以边界一定落在字符边界上，
 * 不会把一个多字节汉字切开（这也是不按"字符"裁剪的原因）。
 */
func trimAsciiBlank(s: String): String {
    let a = s.toArray()
    var b: Int64 = 0
    var e: Int64 = a.size
    while (b < e && isAsciiSpaceByte(a[b])) {
        b += 1
    }
    while (e > b && isAsciiSpaceByte(a[e - 1])) {
        e -= 1
    }
    if (b == 0 && e == a.size) {
        return s
    }
    return String.fromUtf8(a[b..e])
}

/* 从 UTF-8 文本文件读一个姓名；任何问题都打印人话并返回 None。 */
func readNameFile(path: String): ?String {
    var bytes: Array<UInt8>
    try {
        bytes = File.readFrom(path)
    } catch (e: Exception) {
        println("读不到姓名文件：${path}（${e.message}）")
        return None
    }
    /* PowerShell 5.1 的 `Set-Content -Encoding UTF8` 写出来是**带 BOM** 的，这里替用户剥掉 */
    if (bytes.size >= 3 && bytes[0] == UInt8(0xEF) && bytes[1] == UInt8(0xBB) && bytes[2] == UInt8(0xBF)) {
        bytes = bytes[3..]
    }
    var text = ""
    try {
        text = String.fromUtf8(bytes)
    } catch (e: Exception) {
        println("姓名文件不是合法的 UTF-8：${path}")
        return None
    }
    let name = trimAsciiBlank(text)
    if (isBlank(name)) {
        println("姓名文件是空的：${path}（文件内容应当就是这个人的姓名）")
        return None
    }
    return Some(name)
}

/*
 * 首任会长用**初始化命令**预置（api-design §2.8 决策 8），
 * 不采用"首个注册者自动成为会长"——那等于把社团管理权交给第一个扫码的人。
 *
 * name：首任会长的姓名；调用方已保证非空白（默认「会长」）。
 * 与 HTTP 的 `PATCH /api/v1/members/{id}` 同一口径 —— 那边也只要求姓名非空白（见 h_member.cj）。
 */
func cmdInitAdmin(phone: String, pw: String, dir: String, name: String): Int64 {
    if (!isPhone(phone)) {
        println("手机号格式不正确（11 位，以 1 开头）")
        return 1
    }
    /* 与注册 / 改密同一口径（D-6：8–32 字节 + 只用数字/英文/符号），别让初始化命令成为第三条规则 */
    let pwErr = passwordError(pw)
    if (pwErr.size > 0) {
        println(pwErr)
        return 1
    }
    let loaded = loadOrExit(dir)
    let s = match (loaded) {
        case Some(x) => x
        case None => return 1
    }
    s.lock.lock()
    try {
        if (presidentCount(s) > 0) {
            println("已存在会长账号：init-admin 只能对空库执行一次")
            return 1
        }
        if (memberByPhone(s, phone).isSome()) {
            println("该手机号已存在，不能重复初始化")
            return 1
        }
        if (s.departments.size == 0) {
            seedDepartments(s)
        }
        let now = nowEpoch()
        let m = Member()
        m.id = s.next_member
        s.next_member += 1
        m.name = name
        m.phone = phone
        let rec = newPasswordRecord(pw)
        m.pw_salt = rec[0]
        m.pw_hash = rec[1]
        m.pw_iter = rec[2]
        m.role = "president"
        m.dept_id = deptIdByName(s, "主席团")
        m.status = "active"
        m.joined_at = now
        s.members[m.id] = m

        if (s.register_code.size == 0) {
            s.register_code = newRegisterCode()
            s.register_code_by = m.id
            s.register_code_at = now
        }
        /* 命令行路径，不在 HTTP 请求里，没有刷盘中间件可依赖 → 用同步落盘。 */
        storeSaveNow(s)

        println("已创建首任会长：${name}（${phone}，成员 id=${m.id}，部门=${m.dept_id}）")
        println("当前注册口令：${s.register_code}")
        println("数据目录：${s.dir}（db.json）")
    } finally {
        s.lock.unlock()
    }
    return 0
}

/*
 * 运维账号（`role = "ops"`）的建号 / 重设口令 —— 2026-09-16 新增。
 *
 * 为什么要专门的账号：运维不该由会长本人做（职责分离）。运维人员用后台自己的账号
 * （admin/admin123）登录运维台，运维台再用这个账号去调 club-server ——
 * 于是审计里 actor 是"运维"，而不是会长。
 *
 * 为什么只能用命令行建（API 不给分配这一档，见 views.cj 的 isKnownRole）：
 * 运维的权限是"除移交会长外与会长同权"，比副会长大；若 API 能分配它，
 * 会长就能造出权限略高于自己的账号，绕过"会长只能通过移交产生"这条约束。
 * 本机命令 = 需要有这台机器的访问权，与 /admin/shutdown 的本机信任同一档。
 *
 * 幂等：手机号已存在就**重设口令 + 把角色校准回 ops**（人员轮换时重新发凭据就是这个用法）。
 */
func cmdInitOps(phone: String, pw: String, dir: String): Int64 {
    if (!isPhone(phone)) {
        println("手机号格式不正确（11 位，以 1 开头）")
        return 1
    }
    let pwErr = passwordError(pw)
    if (pwErr.size > 0) {
        println(pwErr)
        return 1
    }
    let loaded = loadOrExit(dir)
    let s = match (loaded) {
        case Some(x) => x
        case None => return 1
    }
    s.lock.lock()
    try {
        let rec = newPasswordRecord(pw)
        let now = nowEpoch()
        match (memberByPhone(s, phone)) {
            case Some(m) =>
                m.pw_salt = rec[0]
                m.pw_hash = rec[1]
                m.pw_iter = rec[2]
                m.role = "ops"
                m.status = "active"
                revokeOtherTokens(s, m.id, "")
                storeSaveNow(s)
                println("已重设运维账号口令：${phone}（成员 id=${m.id}，角色已校准为 ops）")
            case None =>
                let m = Member()
                m.id = s.next_member
                s.next_member += 1
                m.name = "运维"
                m.phone = phone
                m.pw_salt = rec[0]
                m.pw_hash = rec[1]
                m.pw_iter = rec[2]
                m.role = "ops"
                /* 运维不属于任何部门：dept_id = 0（它不是社团干部，名录里会排在最后） */
                m.dept_id = 0
                m.status = "active"
                m.joined_at = now
                s.members[m.id] = m
                storeSaveNow(s)
                println("已创建运维账号：${phone}（成员 id=${m.id}，角色 ops）")
        }
        println("权限：除「移交会长」外与会长同权；不可由 API 分配，只能用本命令创建")
        println("下一步：用这个手机号 + 口令直接登录运维台（http://127.0.0.1:3000/）就行")
        println("        （也可以把凭据填进 build\\admin\\admin.env 的 club_user / club_pass 让后台代持，二选一）")
        println("数据目录：${s.dir}（db.json）")
        /*
         * 2026-09-17 加这段告警：本命令改的是 **db.json 文件**，而 club-server 只在**启动时**
         * 把它读进内存一次。所以"服务已经起着"时执行本命令，账号只落到磁盘、内存里没有 ——
         * 表现为**登录一直 401**；更坑的是运维台「成员名录」是直读文件的，
         * 页面里**看得见**这个「运维」账号，于是极易被误判成"口令填错了"。
         * 这条实测复现过（先起服务再 init-ops → 401；重启服务 → 200）。
         */
        println("")
        println("⚠ 如果 club-server **正在运行**，它内存里还是旧的库 —— 必须**重启 club-server**，")
        println("  上面这个账号才能登录（否则登录一直 401，而运维页的名录里却看得见它）。")
        println("  正确顺序：先 init-ops，再启动 club-server；已经起了就先停掉再起。")
    } finally {
        s.lock.unlock()
    }
    return 0
}

/* 运维账号退役：停用它（保留记录，审计里仍能查到它做过什么）。 */
func cmdRetireOps(phone: String, dir: String): Int64 {
    if (!isPhone(phone)) {
        println("手机号格式不正确（11 位，以 1 开头）")
        return 1
    }
    let loaded = loadOrExit(dir)
    let s = match (loaded) {
        case Some(x) => x
        case None => return 1
    }
    s.lock.lock()
    try {
        let m = match (memberByPhone(s, phone)) {
            case Some(x) => x
            case None =>
                println("没有这个手机号的成员：${phone}")
                return 1
        }
        if (m.role != "ops") {
            /* 只退役运维账号：误把普通成员（尤其会长）停用掉是没法接受的副作用 */
            println("该账号的角色是 ${m.role}，不是运维账号；retire-ops 只处理 ops")
            return 1
        }
        m.status = "disabled"
        revokeOtherTokens(s, m.id, "")
        storeSaveNow(s)
        println("已停用运维账号：${phone}（成员 id=${m.id}）")
        println("若要彻底删除，直接在数据目录的 db.json 里去掉该成员（或换个手机号重建）")
        /* 同 init-ops：club-server 只在启动时读库一次，运行中改文件不会生效（见 init-ops 那段注释）。 */
        println("⚠ 若 club-server 正在运行，**必须重启它**这次停用才会生效（否则旧令牌仍可用）。")
    } finally {
        s.lock.unlock()
    }
    return 0
}

/* 优雅关闭端点：仅本机可访问。 */
func handleShutdown(ctx: Context, box: HandleBox): Unit {
    if (!isLocalPeer(ctx)) {
        throw apiErrMsg("FORBIDDEN_ROLE", "该端点仅允许本机访问（来自 ${peerOf(ctx)}）")
    }
    let data = JsonObject()
    jPutStr(data, "status", "shutting-down")
    sendOk(ctx, data)
    /* 不能在请求线程里直接 shutdown()——那会等待本请求自己结束，形成死锁。
     * 交给后台线程，请求正常返回后再关。 */
    match (box.handle) {
        case Some(h) => spawn {
            /*
             * 先等 1 秒再关：`shutdown()` 里的 `server.close()` 会停止 accept 并收尾，
             * 但它**不等本请求的响应写出去**。实测（2026-09-16，8 次里 6 次）客户端会拿到
             * `HTTP 200` + **空 body** —— 本端点是 Windows 上唯一的关停入口，
             * 回执照样丢失就很难判断"到底关没关"。宁可晚 1 秒关，也要让回执可靠。
             * 回归闸门：tests/ops-check.ps1 断言关停响应体是 ok:true。
             */
            sleep(Duration.second * 1)
            h.shutdown()
        }
        case None => ()
    }
}

func buildApp(s: Store, box: HandleBox): QingZhouApp {
    let router = Router()
        /* 运维 */
        .get("/health", { ctx: Context, _: () -> Unit =>
            handleHealth(ctx)
        })
        .post("/admin/shutdown", { ctx: Context, _: () -> Unit =>
            handleShutdown(ctx, box)
        })
        /* 招募链接落地页（无需登录，L-2）。链接是发到群里的，点开必须有内容。 */
        .get("/join/:token", { ctx: Context, _: () -> Unit =>
            handleJoinLanding(ctx, s)
        })
        /* Part 2 · 认证与注册 */
        .post("/api/v1/auth/register", { ctx: Context, _: () -> Unit =>
            handleRegister(ctx, s)
        })
        .post("/api/v1/auth/login", { ctx: Context, _: () -> Unit =>
            handleLogin(ctx, s)
        })
        .post("/api/v1/auth/logout", { ctx: Context, _: () -> Unit =>
            handleLogout(ctx, s)
        })
        .get("/api/v1/auth/me", { ctx: Context, _: () -> Unit =>
            handleMe(ctx, s)
        })
        .put("/api/v1/auth/password", { ctx: Context, _: () -> Unit =>
            handleChangePassword(ctx, s)
        })
        /* Part 3 · 组织与成员（19） */
        .get("/api/v1/depts", { ctx: Context, _: () -> Unit =>
            handleDeptList(ctx, s)
        })
        .post("/api/v1/depts", { ctx: Context, _: () -> Unit =>
            handleDeptCreate(ctx, s)
        })
        .patch("/api/v1/depts/:id", { ctx: Context, _: () -> Unit =>
            handleDeptUpdate(ctx, s)
        })
        .delete("/api/v1/depts/:id", { ctx: Context, _: () -> Unit =>
            handleDeptDelete(ctx, s)
        })
        .get("/api/v1/members", { ctx: Context, _: () -> Unit =>
            handleMemberList(ctx, s)
        })
        /* 静态段优先（router.cj 的 walk 先查 Static 再查 Param），
         * 但仍显式排在 :id 之前，避免将来换路由实现时踩坑。 */
        .get("/api/v1/members/pending", { ctx: Context, _: () -> Unit =>
            handleMemberPending(ctx, s)
        })
        .post("/api/v1/members/assign-batch", { ctx: Context, _: () -> Unit =>
            handleMemberAssignBatch(ctx, s)
        })
        .get("/api/v1/members/:id", { ctx: Context, _: () -> Unit =>
            handleMemberDetail(ctx, s)
        })
        .patch("/api/v1/members/:id", { ctx: Context, _: () -> Unit =>
            handleMemberUpdate(ctx, s)
        })
        .post("/api/v1/members/:id/disable", { ctx: Context, _: () -> Unit =>
            handleMemberDisable(ctx, s)
        })
        .post("/api/v1/members/:id/assign", { ctx: Context, _: () -> Unit =>
            handleMemberAssign(ctx, s)
        })
        .post("/api/v1/members/:id/transfer-presidency", { ctx: Context, _: () -> Unit =>
            handleTransferPresidency(ctx, s)
        })
        .post("/api/v1/members/:id/reset-password", { ctx: Context, _: () -> Unit =>
            handleResetPassword(ctx, s)
        })
        .get("/api/v1/register-config", { ctx: Context, _: () -> Unit =>
            handleRegisterConfigGet(ctx, s)
        })
        .put("/api/v1/register-config/code", { ctx: Context, _: () -> Unit =>
            handleRegisterConfigPut(ctx, s)
        })
        .post("/api/v1/register-config/rotate", { ctx: Context, _: () -> Unit =>
            handleRegisterConfigRotate(ctx, s)
        })
        .get("/api/v1/dept-invite-links", { ctx: Context, _: () -> Unit =>
            handleInviteLinkList(ctx, s)
        })
        .post("/api/v1/dept-invite-links", { ctx: Context, _: () -> Unit =>
            handleInviteLinkCreate(ctx, s)
        })
        .delete("/api/v1/dept-invite-links/:token", { ctx: Context, _: () -> Unit =>
            handleInviteLinkDisable(ctx, s)
        })
        /* 招募链接的公开 JSON 解析（D-16，2026-09-16）：App 用它把 token 换成 dept_id。
         * 免认证 —— 与上面那个 HTML 落地页同源，只暴露部门名与启停状态。 */
        .get("/api/v1/join/:token", { ctx: Context, _: () -> Unit =>
            handleJoinResolve(ctx, s)
        })
        /* Part 4 · 任务（8） */
        .get("/api/v1/tasks/mine", { ctx: Context, _: () -> Unit =>
            handleTasksMine(ctx, s)
        })
        .post("/api/v1/tasks/lookup", { ctx: Context, _: () -> Unit =>
            handleTaskLookup(ctx, s)
        })
        .get("/api/v1/tasks", { ctx: Context, _: () -> Unit =>
            handleTaskList(ctx, s)
        })
        .post("/api/v1/tasks", { ctx: Context, _: () -> Unit =>
            handleTaskCreate(ctx, s)
        })
        .get("/api/v1/tasks/:id", { ctx: Context, _: () -> Unit =>
            handleTaskDetail(ctx, s)
        })
        .patch("/api/v1/tasks/:id", { ctx: Context, _: () -> Unit =>
            handleTaskUpdate(ctx, s)
        })
        .put("/api/v1/tasks/:id/status", { ctx: Context, _: () -> Unit =>
            handleTaskStatus(ctx, s)
        })
        .delete("/api/v1/tasks/:id", { ctx: Context, _: () -> Unit =>
            handleTaskDelete(ctx, s)
        })
        /* Part 5 · 课题（6） */
        .get("/api/v1/plans", { ctx: Context, _: () -> Unit =>
            handlePlanTree(ctx, s)
        })
        .post("/api/v1/plans", { ctx: Context, _: () -> Unit =>
            handlePlanCreate(ctx, s)
        })
        .get("/api/v1/plans/:id", { ctx: Context, _: () -> Unit =>
            handlePlanDetail(ctx, s)
        })
        .patch("/api/v1/plans/:id", { ctx: Context, _: () -> Unit =>
            handlePlanUpdate(ctx, s)
        })
        .post("/api/v1/plans/:id/move", { ctx: Context, _: () -> Unit =>
            handlePlanMove(ctx, s)
        })
        .delete("/api/v1/plans/:id", { ctx: Context, _: () -> Unit =>
            handlePlanDelete(ctx, s)
        })

    /*
     * 统一错误出口：
     *   ApiError → 按错误码表落状态码与 {ok:false,error:{code,message,fields}}
     *   其它异常 → 记日志 + 500 INTERNAL，**不向客户端暴露堆栈**（api-design §1.3）
     */
    let errHandler: Middleware = { ctx: Context, _: () -> Unit =>
        match (ctx.err()) {
            case Some(e: ApiError) => sendError(ctx, e)
            case Some(e) =>
                println("[ERROR] ${ctx.method()} ${ctx.path()} -> ${e.message}")
                sendError(ctx, apiErr("INTERNAL"))
            case None => ()
        }
    }

    /*
     * 中间件顺序说明（P1 M-5）：timeout 原先写在 router.middleware() **之后**，
     * 那是错的位置。轻舟的 use() 按注册顺序串成洋葱，先注册的在**外层**；
     * 而 router 命中路由后是直接 `h(ctx, next)` 调用 handler，我们的 handler 从不调 next()，
     * 因此排在 router 后面的 timeout 中间件**一次都没有被执行过**——
     * 它既没计时，也没机会发 408。
     * 移到 router 之前（外层）才会真正参与：dispatch 前后各计一次时。
     *
     * 即便如此也要说清楚它的能力边界（读 timeout.cj 的实现）：它是"事后软超时"，
     * 只能在 handler 返回后判断是否超时，**无法中断**已经跑起来的同步 handler。
     * 真正的防线是 handler 里不做慢操作；这一层是给将来不留神写出的慢路径兜底。
     *
     * 中间件顺序说明 2（容量基准动作 4）：snapshotFlush 也**必须**在 router 之前。
     *   顺序是「handler 改内存 → finally 解锁 → 本中间件写盘 → dispatch 返回 → ctx.commit() 发响应」。
     *   写盘因此落在锁外（不再阻塞其他请求），又仍然早于响应 ——
     *   「响应 200 ⇒ 数据已落盘」这条语义没有打折，见 store.cj 的 storeSave/flushPending。
     *   它同时兼顾了"没命中路由/没改数据"的请求：此时 pending 为空，flushPending 是空操作。
     */
    return QingZhouApp()
        .use(requestId())
        .use(logger())
        .use(bodyParser())
        .use(cors())
        .use(timeout(15000))
        .use(snapshotFlush(s))
        .use(router.middleware())
        .onError(errHandler)
}

func cmdServe(port: UInt16, dir: String): Int64 {
    let loaded = loadOrExit(dir)
    let s = match (loaded) {
        case Some(x) => x
        case None => return 1
    }
    if (presidentCount(s) == 0) {
        println("[WARN] 当前没有任何会长账号，请先执行：club-server init-admin <手机号> <初始密码>")
    }
    let box = HandleBox()
    let app = buildApp(s, box)
    println("社团管理工具 · 服务端 v${APP_VERSION}")
    println("监听 :${port}  数据目录 ${s.dir}  成员 ${s.members.size} 人  课题 ${s.plans.size} 个  任务 ${s.tasks.size} 个")
    let handle = app.serve(port)
    box.handle = Some(handle)
    handle.wait()
    println("服务已停止")
    return 0
}

/*
 * HTTPS 启动。
 *
 * 轻舟的 serveTls(port, certPem, keyPem) 收的是 **PEM 字符串**而不是文件路径，
 * 因此读文件、异常处理都在调用方（见上层 cangjie-upstream\qingzhou-tls-verification.md 第 3 节的责任转移）。
 *
 * ⚠ 绝不静默降级：证书或私钥读不到、解析失败时**直接退出**，
 * 不允许 catch 之后回退到明文 serve()——那会让"HTTPS 没起来"变成静默的明文服务。
 */
func cmdServeTls(port: UInt16, dir: String, certPath: String, keyPath: String): Int64 {
    let loaded = loadOrExit(dir)
    let s = match (loaded) {
        case Some(x) => x
        case None => return 1
    }
    if (presidentCount(s) == 0) {
        println("[WARN] 当前没有任何会长账号，请先执行：club-server init-admin <手机号> <初始密码>")
    }
    if (!exists(certPath)) {
        println("[FATAL] 找不到证书：${certPath}")
        return 1
    }
    if (!exists(keyPath)) {
        println("[FATAL] 找不到私钥：${keyPath}")
        return 1
    }
    var certPem = ""
    var keyPem = ""
    try {
        certPem = String.fromUtf8(File.readFrom(certPath))
        keyPem = String.fromUtf8(File.readFrom(keyPath))
    } catch (e: Exception) {
        println("[FATAL] 证书或私钥读取失败：${e.message}")
        return 1
    }

    let box = HandleBox()
    let app = buildApp(s, box)
    println("社团管理工具 · 服务端 v${APP_VERSION}  (HTTPS)")
    println("监听 :${port}  数据目录 ${s.dir}  成员 ${s.members.size} 人")
    println("证书 ${certPath}")
    println("私钥 ${keyPath}（内容不会写入日志）")

    var handle: ?ServerHandle = None
    try {
        handle = Some(app.serveTls(port, certPem, keyPem))
    } catch (e: Exception) {
        println("[FATAL] TLS 启动失败：${e.message}")
        println("        （PEM 无法解析时框架会抛异常；这里不做任何明文回退）")
        return 1
    }
    match (handle) {
        case Some(h) =>
            box.handle = Some(h)
            h.wait()
        case None => return 1
    }
    println("服务已停止")
    return 0
}

main(args: Array<String>): Int64 {
    if (args.size == 0) {
        usage()
        return 1
    }
    if (args[0] == "test") {
        return runTests()
    }
    if (args[0] == "init-admin") {
        if (args.size < 3) {
            println("用法: club-server init-admin <手机号> <初始密码> [数据目录] [姓名选项]")
            println("  姓名选项：--name <ASCII 姓名>  或  --name-file <UTF-8 文本文件>")
            println("  ⚠ 中文姓名**只能**走 --name-file —— 中文命令行参数会让程序在 main 之前就崩（API-NOTES 坑 11）")
            println("  两个都不给时，首任会长的姓名是「会长」")
            return 1
        }
        /*
         * 参数形态：<手机号> <口令> [数据目录] [姓名选项…]
         *
         * · 数据目录是**可选**的，所以用"第 4 个参数是不是 -- 开头"来判断它是目录还是选项 ——
         *   于是 `init-admin P W --name-file f.txt`（省掉目录、用默认 data）也能正常工作。
         * · 选项只认 --name / --name-file；**不认识的参数明确报错**，而不是像以前那样静默忽略
         *   （静默忽略正是"以为传了名字、其实没传"的来源）。
         * · 兼容性：`init-admin P W data` 这种老的三参数调用行为一字不变。
         */
        var dir = "data"
        var i = 3
        if (args.size > 3 && !startsWithAscii(args[3], "--")) {
            dir = args[3]
            i = 4
        }
        var name = ""
        var nameFile = ""
        while (i < args.size) {
            if (args[i] == "--name") {
                if (i + 1 >= args.size) {
                    println("--name 后面要跟姓名")
                    return 1
                }
                name = args[i + 1]
                i += 2
            } else if (args[i] == "--name-file") {
                if (i + 1 >= args.size) {
                    println("--name-file 后面要跟文件路径")
                    return 1
                }
                nameFile = args[i + 1]
                i += 2
            } else {
                println("不认识的参数：${args[i]}")
                println("用法: club-server init-admin <手机号> <初始密码> [数据目录] [--name <姓名> | --name-file <文件>]")
                return 1
            }
        }
        if (name.size > 0 && nameFile.size > 0) {
            println("--name 与 --name-file 只能给一个（--name 只支持 ASCII，中文请用 --name-file）")
            return 1
        }
        if (nameFile.size > 0) {
            let fromFile = match (readNameFile(nameFile)) {
                case Some(n) => n
                case None => return 1
            }
            name = fromFile
        }
        if (name.size == 0) {
            name = "会长"
        }
        /* 与 HTTP 的 PATCH /members 同口径：姓名非空白即可（见 h_member.cj） */
        if (isBlank(name)) {
            println("姓名不能是空白")
            return 1
        }
        return cmdInitAdmin(args[1], args[2], dir, trimAsciiBlank(name))
    }
    if (args[0] == "init-ops") {
        if (args.size < 3) {
            println("用法: club-server init-ops <手机号> <口令> [数据目录]")
            println("  创建/重设**运维账号**（角色 ops：除「移交会长」外与会长同权）")
            return 1
        }
        let dir = if (args.size > 3) {
            args[3]
        } else {
            "data"
        }
        return cmdInitOps(args[1], args[2], dir)
    }
    if (args[0] == "retire-ops") {
        if (args.size < 2) {
            println("用法: club-server retire-ops <手机号> [数据目录]")
            return 1
        }
        let dir = if (args.size > 2) {
            args[2]
        } else {
            "data"
        }
        return cmdRetireOps(args[1], dir)
    }
    if (args[0] == "serve") {
        var port: UInt16 = 8080
        if (args.size > 1) {
            try {
                port = UInt16.parse(args[1])
            } catch (e: Exception) {
                println("端口不合法: ${args[1]}")
                return 1
            }
        }
        let dir = if (args.size > 2) {
            args[2]
        } else {
            "data"
        }
        return cmdServe(port, dir)
    }
    if (args[0] == "serve-tls") {
        var port: UInt16 = 8443
        if (args.size > 1) {
            try {
                port = UInt16.parse(args[1])
            } catch (e: Exception) {
                println("端口不合法: ${args[1]}")
                return 1
            }
        }
        let dir = if (args.size > 2) {
            args[2]
        } else {
            "data"
        }
        let certPath = if (args.size > 3) {
            args[3]
        } else {
            "certs/cert.pem"
        }
        let keyPath = if (args.size > 4) {
            args[4]
        } else {
            "certs/key.pem"
        }
        return cmdServeTls(port, dir, certPath, keyPath)
    }
    usage()
    return 1
}
