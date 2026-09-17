package qingzhou

/*
 * SPDX-License-Identifier: MIT
 *
 * 社团管理工具 · 运维台（admin 构建）专用
 * —— 社团库的**只读**视图层：概览 / 名录 / 部门 / 任务 / 课题 / 招募链接 / 审计日志。
 *
 * 定位（很重要）
 *   运维台**只读**社团库文件，一切**写**操作都转发给 club-server 的真实 API
 *   （由前端带会长令牌直接调用，见 ops/admin_main.cj 的文件头与 docs/HANDOFF.md）。
 *   理由：club-server 与运维台是两个进程，若都直接写同一个 db.json，就是 last-writer-wins，
 *   会静默丢数据，而且绕过 N-7 / N-15 那些已修的权限与原子性约束。
 *
 * 安全
 *   本文件**绝不**序列化 Member 的口令材料（pw_salt / pw_hash / pw_iter / pw_algo）。
 *   store.cj 里的 memberToJson 是"整库落盘"用的，会把那 4 个字段一起写出去，
 *   所以这里另写白名单视图 clubMemberRow()，不复用它。改这个文件时请守住这条。
 *
 * 时间
 *   库里的时间戳是 epoch 秒；对外一律用 timex.cj 的 isoLocal()（+08:00）格式化，
 *   与 club-server 的接口口径一致。
 */

import std.collection.*
import std.convert.*
import std.fs.*
import stdx.encoding.json.*

/* ===================== 小工具 ===================== */

/* epoch 秒 → ISO8601（本地时区）；0 / 负数 → null（与 api-design §1.8 一致）。 */
func clubPutTime(o: JsonObject, k: String, epoch: Int64): Unit {
    if (epoch > 0) {
        o.put(k, JsonString(isoLocal(epoch)))
    } else {
        o.put(k, JsonNull())
    }
}

/* 宽松取整：空串 / 非法 / 越界 → 默认值。运维台的 query 参数坏掉不该让页面白屏。 */
func clubIntOr(s: String, d: Int64): Int64 {
    let t = s.trimAscii()
    if (t.size == 0) {
        return d
    }
    try {
        return Int64.parse(t)
    } catch (e: Exception) {
        return d
    }
}

func clubDeptName(s: Store, id: Int64): String {
    if (id <= 0) {
        return ""
    }
    match (s.departments.get(id)) {
        case Some(d) => return d.name
        case None => return ""
    }
}

func clubMemberName(s: Store, id: Int64): String {
    if (id <= 0) {
        return ""
    }
    match (s.members.get(id)) {
        case Some(m) => return m.name
        case None => return ""
    }
}

func clubPlanTitle(s: Store, id: Int64): String {
    if (id <= 0) {
        return ""
    }
    match (s.plans.get(id)) {
        case Some(p) => return p.title
        case None => return ""
    }
}

/*
 * 角色代号 → 中文。代号必须与 club-server 一致：
 *   president / ops / vice_president / lead / vice_lead / member
 * ⚠ 中间两档是 **lead / vice_lead**（不是 minister）—— 2026-09-16 这里写错过一次，
 *   结果是运维页把"部长"显示成空白、下拉框发出去的代号还会被服务端拒。
 *   闸门：tests/ops-check.ps1 会分配 lead / vice_lead 并回读中文标签。
 */
func clubRoleLabel(role: String): String {
    if (role == "president") { return "会长" }
    if (role == "ops") { return "运维" }
    if (role == "vice_president") { return "副会长" }
    if (role == "lead") { return "部长" }
    if (role == "vice_lead") { return "副部长" }
    if (role == "member") { return "成员" }
    return ""
}

func clubMemberStatusLabel(st: String): String {
    if (st == "active") { return "在册" }
    if (st == "pending") { return "待分配" }
    if (st == "disabled") { return "已停用" }
    return st
}

func clubTaskStatusLabel(st: String): String {
    if (st == "todo") { return "待办" }
    if (st == "doing") { return "进行中" }
    if (st == "blocked") { return "受阻" }
    if (st == "done") { return "已完成" }
    return st
}

/* 文件字节数；读不到返回 0（不存在也算 0）。 */
func clubFileSize(path: String): Int64 {
    if (!exists(path)) {
        return 0
    }
    try {
        return File.readFrom(path).size
    } catch (e: Exception) {
        return 0
    }
}

/* 文件最后修改时间（epoch 秒）；读不到返回 0。用框架 etag.cj 的 fileLastModified（UTC DateTime）。 */
func clubFileMtime(path: String): Int64 {
    match (fileLastModified(path)) {
        case Some(dt) =>
            return dt.toUnixTimeStamp().toSeconds()
        case None => return 0
    }
}

/* ===================== 单行视图（白名单字段） ===================== */

/*
 * 成员一行。**不含任何口令材料**（见文件头"安全"一节）。
 * has_password 只说明"有没有设过口令"，运维排查"登不上"时够用且不泄露材料。
 */
func clubMemberRow(s: Store, m: Member, now: Int64): JsonObject {
    let o = JsonObject()
    jPutInt(o, "id", m.id)
    jPutStr(o, "name", m.name)
    jPutStr(o, "phone", m.phone)
    jPutStr(o, "role", m.role)
    jPutStr(o, "role_label", clubRoleLabel(m.role))
    jPutInt(o, "dept_id", m.dept_id)
    jPutStr(o, "dept_name", clubDeptName(s, m.dept_id))
    jPutInt(o, "dept_hint", m.dept_hint)
    jPutStr(o, "dept_hint_name", clubDeptName(s, m.dept_hint))
    jPutStr(o, "status", m.status)
    jPutStr(o, "status_label", clubMemberStatusLabel(m.status))
    jPutBool(o, "is_president", m.role == "president")
    jPutBool(o, "has_password", m.pw_hash.size > 0)
    jPutInt(o, "open_tasks", openTasksOf(s, m.id).size)
    clubPutTime(o, "joined_at", m.joined_at)
    /* now 目前只用于"账号是否在册"这类派生展示，保留参数以便后续加派生字段 */
    if (m.status == "active" && m.role != "president" && now > 0) {
        jPutBool(o, "can_disable", true)
    } else {
        jPutBool(o, "can_disable", false)
    }
    return o
}

/* 部门一行：带在用人数与顶层课题数（运维最常问的两个数）。 */
func clubDeptRow(s: Store, d: Department): JsonObject {
    let o = JsonObject()
    jPutInt(o, "id", d.id)
    jPutStr(o, "name", d.name)
    jPutInt(o, "sort", d.sort)
    jPutInt(o, "active_members", activeMemberCountOfDept(s, d.id))
    jPutInt(o, "top_plans", topPlanCountOfDept(s, d.id))
    return o
}

/* 任务一行。 */
func clubTaskRow(s: Store, t: Task, now: Int64): JsonObject {
    let o = JsonObject()
    jPutInt(o, "id", t.id)
    jPutStr(o, "title", t.title)
    jPutInt(o, "owner_id", t.owner_id)
    jPutStr(o, "owner_name", clubMemberName(s, t.owner_id))
    jPutInt(o, "dept_id", t.dept_id)
    jPutStr(o, "dept_name", clubDeptName(s, t.dept_id))
    jPutInt(o, "plan_id", t.plan_id)
    jPutStr(o, "plan_title", clubPlanTitle(s, t.plan_id))
    jPutStr(o, "status", t.status)
    jPutStr(o, "status_label", clubTaskStatusLabel(t.status))
    jPutBool(o, "overdue", isTaskOverdue(t, now))
    jPutBool(o, "deleted", t.deleted_at > 0)
    clubPutTime(o, "due_at", t.due_at)
    clubPutTime(o, "updated_at", t.updated_at)
    clubPutTime(o, "completed_at", t.completed_at)
    /* 阻塞信息只在 blocked 时有意义（与 club-server 的口径一致） */
    if (t.status == "blocked") {
        jPutStr(o, "blocker", t.blocker)
        jPutInt(o, "help_dept_id", t.help_dept_id)
        jPutStr(o, "help_dept_name", clubDeptName(s, t.help_dept_id))
        jPutInt(o, "help_member_id", t.help_member_id)
        jPutStr(o, "help_member_name", clubMemberName(s, t.help_member_id))
    }
    return o
}

/* 课题一行（进度来自 planStatsAll 的一次性聚合，避免 O(n²)）。 */
func clubPlanRow(s: Store, p: Plan, stats: ?PlanStats): JsonObject {
    let o = JsonObject()
    jPutInt(o, "id", p.id)
    jPutStr(o, "title", p.title)
    jPutInt(o, "parent_id", p.parent_id)
    jPutInt(o, "dept_id", p.dept_id)
    jPutStr(o, "dept_name", clubDeptName(s, p.dept_id))
    jPutInt(o, "owner_id", p.owner_id)
    jPutStr(o, "owner_name", clubMemberName(s, p.owner_id))
    jPutInt(o, "depth", planDepthOf(s, p.id))
    clubPutTime(o, "due_at", p.due_at)
    clubPutTime(o, "updated_at", p.updated_at)
    match (stats) {
        case Some(x) =>
            jPutInt(o, "child_count", x.child_count)
            jPutInt(o, "tasks_total", x.total)
            jPutInt(o, "tasks_done", x.done)
            jPutInt(o, "own_tasks", x.task_count)
        case None =>
            jPutInt(o, "child_count", 0)
            jPutInt(o, "tasks_total", 0)
            jPutInt(o, "tasks_done", 0)
            jPutInt(o, "own_tasks", 0)
    }
    return o
}

/* 招募链接一行。token 对运维要可见（要发给新同学），所以不截断。 */
func clubLinkRow(s: Store, l: DeptInviteLink): JsonObject {
    let o = JsonObject()
    jPutStr(o, "token", l.token)
    jPutInt(o, "dept_id", l.dept_id)
    jPutStr(o, "dept_name", clubDeptName(s, l.dept_id))
    jPutBool(o, "enabled", l.enabled)
    jPutInt(o, "created_by", l.created_by)
    jPutStr(o, "created_by_name", clubMemberName(s, l.created_by))
    clubPutTime(o, "created_at", l.created_at)
    jPutStr(o, "path", "/join/${l.token}")
    return o
}

/* ===================== 概览 ===================== */

func clubOverview(s: Store): JsonObject {
    let now = nowEpoch()
    let o = JsonObject()
    jPutStr(o, "data_dir", s.dir)
    jPutStr(o, "db_file", s.dbFile())

    let dbFile = s.dbFile()
    jPutBool(o, "db_exists", exists(dbFile))
    jPutInt(o, "db_bytes", clubFileSize(dbFile))
    clubPutTime(o, "db_mtime", clubFileMtime(dbFile))

    var active: Int64 = 0
    var pending: Int64 = 0
    var disabled: Int64 = 0
    var president: Int64 = 0
    var vicePresident: Int64 = 0
    var minister: Int64 = 0
    var viceMinister: Int64 = 0
    var plainMember: Int64 = 0
    for ((_k, m) in s.members) {
        if (m.status == "active") { active += 1 }
        if (m.status == "pending") { pending += 1 }
        if (m.status == "disabled") { disabled += 1 }
        if (m.role == "president") { president += 1 }
        if (m.role == "vice_president") { vicePresident += 1 }
        if (m.role == "minister") { minister += 1 }
        if (m.role == "vice_minister") { viceMinister += 1 }
        if (m.role == "member") { plainMember += 1 }
    }
    let mj = JsonObject()
    jPutInt(mj, "total", s.members.size)
    jPutInt(mj, "active", active)
    jPutInt(mj, "pending", pending)
    jPutInt(mj, "disabled", disabled)
    jPutInt(mj, "president", president)
    jPutInt(mj, "vice_president", vicePresident)
    jPutInt(mj, "minister", minister)
    jPutInt(mj, "vice_minister", viceMinister)
    jPutInt(mj, "member", plainMember)
    o.put("members", mj)

    var tOpen: Int64 = 0
    var tDone: Int64 = 0
    var tBlocked: Int64 = 0
    var tOverdue: Int64 = 0
    var tDeleted: Int64 = 0
    for ((_k, t) in s.tasks) {
        if (t.deleted_at > 0) {
            tDeleted += 1
            continue
        }
        if (t.status == "done") {
            tDone += 1
        } else {
            tOpen += 1
        }
        if (t.status == "blocked") { tBlocked += 1 }
        if (isTaskOverdue(t, now)) { tOverdue += 1 }
    }
    let tj = JsonObject()
    jPutInt(tj, "total", s.tasks.size)
    jPutInt(tj, "open", tOpen)
    jPutInt(tj, "done", tDone)
    jPutInt(tj, "blocked", tBlocked)
    jPutInt(tj, "overdue", tOverdue)
    jPutInt(tj, "deleted", tDeleted)
    o.put("tasks", tj)

    var linksOn: Int64 = 0
    for ((_k, l) in s.invite_links) {
        if (l.enabled) { linksOn += 1 }
    }
    let lj = JsonObject()
    jPutInt(lj, "total", s.invite_links.size)
    jPutInt(lj, "enabled", linksOn)
    o.put("links", lj)

    var tokActive: Int64 = 0
    for ((_k, t) in s.tokens) {
        if (t.expires_at > now) { tokActive += 1 }
    }
    let kj = JsonObject()
    jPutInt(kj, "total", s.tokens.size)
    jPutInt(kj, "active", tokActive)
    o.put("tokens", kj)

    jPutInt(o, "depts", s.departments.size)
    jPutInt(o, "plans", s.plans.size)
    jPutInt(o, "idem", s.idem.size)

    /* 注册口令：只有会长/副会长能看（api-design §3.6），运维台本身又只放给 admin 角色，
     * 所以这里直接给出，省得运维再去客户端翻。 */
    let rj = JsonObject()
    jPutBool(rj, "has_code", s.register_code.size > 0)
    jPutStr(rj, "code", s.register_code)
    jPutInt(rj, "by_member_id", s.register_code_by)
    jPutStr(rj, "by_name", clubMemberName(s, s.register_code_by))
    clubPutTime(rj, "at", s.register_code_at)
    o.put("register", rj)

    let auditFile = "${s.dir}/audit.log"
    let aj = JsonObject()
    jPutStr(aj, "file", auditFile)
    jPutInt(aj, "bytes", clubFileSize(auditFile))
    jPutInt(aj, "lines", clubAuditLines(s, 0).size())
    o.put("audit", aj)

    return o
}

/* ===================== 列表 ===================== */

/* 分页：默认 50，最多 500（运维台不做无限拉取）。 */
func clubPaging(ctx: Context): (Int64, Int64) {
    var page = clubIntOr(ctx.queryParamOr("page", "1"), 1)
    var size = clubIntOr(ctx.queryParamOr("size", "50"), 50)
    if (page < 1) { page = 1 }
    if (size < 1) { size = 50 }
    if (size > 500) { size = 500 }
    return (page, size)
}

func clubMembers(s: Store, ctx: Context): JsonObject {
    let now = nowEpoch()
    let q = ctx.queryParamOr("q", "").trimAscii().toAsciiLower()
    let deptId = clubIntOr(ctx.queryParamOr("dept_id", "0"), 0)
    let role = ctx.queryParamOr("role", "").trimAscii()
    let statusFilter = ctx.queryParamOr("status", "").trimAscii()
    let (page, size) = clubPaging(ctx)

    let all = ArrayList<Member>()
    for ((_k, m) in s.members) {
        all.add(m)
    }
    let sorted = all.toArray()
    sortByKey<Member>(sorted, { m: Member => m.id })

    let hit = ArrayList<Member>()
    for (m in sorted) {
        if (q.size > 0) {
            let byName = containsAscii(m.name.toAsciiLower(), q)
            let byPhone = containsAscii(m.phone, q)
            if (!byName && !byPhone) { continue }
        }
        if (deptId > 0 && m.dept_id != deptId) { continue }
        if (role.size > 0 && m.role != role) { continue }
        if (statusFilter.size > 0 && m.status != statusFilter) { continue }
        hit.add(m)
    }

    let items = JsonArray()
    let total = hit.size
    let from = (page - 1) * size
    var i: Int64 = 0
    for (m in hit.toArray()) {
        if (i >= from && i < from + size) {
            items.add(clubMemberRow(s, m, now))
        }
        i += 1
    }
    let o = JsonObject()
    o.put("items", items)
    jPutInt(o, "total", total)
    jPutInt(o, "page", page)
    jPutInt(o, "size", size)
    return o
}

func clubDepts(s: Store): JsonObject {
    let all = ArrayList<Department>()
    for ((_k, d) in s.departments) {
        all.add(d)
    }
    let sorted = all.toArray()
    sortByKey<Department>(sorted, { d: Department => d.sort * 1000 + d.id })
    let items = JsonArray()
    for (d in sorted) {
        items.add(clubDeptRow(s, d))
    }
    let o = JsonObject()
    o.put("items", items)
    jPutInt(o, "total", sorted.size)
    return o
}

func clubTasks(s: Store, ctx: Context): JsonObject {
    let now = nowEpoch()
    let q = ctx.queryParamOr("q", "").trimAscii().toAsciiLower()
    let statusFilter = ctx.queryParamOr("status", "").trimAscii()
    let deptId = clubIntOr(ctx.queryParamOr("dept_id", "0"), 0)
    let ownerId = clubIntOr(ctx.queryParamOr("owner_id", "0"), 0)
    let planId = clubIntOr(ctx.queryParamOr("plan_id", "0"), 0)
    let overdueOnly = ctx.queryParamOr("overdue", "") == "1"
    let withDeleted = ctx.queryParamOr("deleted", "") == "1"
    let (page, size) = clubPaging(ctx)

    let all = ArrayList<Task>()
    for ((_k, t) in s.tasks) {
        all.add(t)
    }
    let sorted = all.toArray()
    /* 按截止时间倒序不方便（sortByKey 只有升序），这里按 id 升序，前端自己排。 */
    sortByKey<Task>(sorted, { t: Task => t.id })

    let hit = ArrayList<Task>()
    for (t in sorted) {
        if (!withDeleted && t.deleted_at > 0) { continue }
        if (q.size > 0 && !containsAscii(t.title.toAsciiLower(), q)) { continue }
        if (statusFilter.size > 0 && t.status != statusFilter) { continue }
        if (deptId > 0 && t.dept_id != deptId) { continue }
        if (ownerId > 0 && t.owner_id != ownerId) { continue }
        if (planId > 0 && t.plan_id != planId) { continue }
        if (overdueOnly && !isTaskOverdue(t, now)) { continue }
        hit.add(t)
    }

    let items = JsonArray()
    let total = hit.size
    let from = (page - 1) * size
    var i: Int64 = 0
    for (t in hit.toArray()) {
        if (i >= from && i < from + size) {
            items.add(clubTaskRow(s, t, now))
        }
        i += 1
    }
    let o = JsonObject()
    o.put("items", items)
    jPutInt(o, "total", total)
    jPutInt(o, "page", page)
    jPutInt(o, "size", size)
    return o
}

func clubPlans(s: Store): JsonObject {
    let ids = HashSet<Int64>()
    for ((_k, p) in s.plans) {
        ids.add(p.id)
    }
    /* 一次性自底向上聚合（O(n)），不要在每个节点上再递归（那会变 O(n²)）。 */
    let stats = planStatsAll(s, ids)

    let all = ArrayList<Plan>()
    for ((_k, p) in s.plans) {
        all.add(p)
    }
    let sorted = all.toArray()
    sortByKey<Plan>(sorted, { p: Plan => p.id })

    let items = JsonArray()
    for (p in sorted) {
        items.add(clubPlanRow(s, p, stats.get(p.id)))
    }
    let o = JsonObject()
    o.put("items", items)
    jPutInt(o, "total", sorted.size)
    return o
}

func clubLinks(s: Store): JsonObject {
    let all = ArrayList<DeptInviteLink>()
    for ((_k, l) in s.invite_links) {
        all.add(l)
    }
    let sorted = all.toArray()
    sortByKey<DeptInviteLink>(sorted, { l: DeptInviteLink => l.created_at })
    let items = JsonArray()
    /* 新→旧：反着放，运维最关心最近生成的 */
    var i = sorted.size - 1
    while (i >= 0) {
        items.add(clubLinkRow(s, sorted[i]))
        i -= 1
    }
    let o = JsonObject()
    o.put("items", items)
    jPutInt(o, "total", sorted.size)
    return o
}

/* ===================== 审计日志 ===================== */

/*
 * 读 <数据目录>/audit.log 的尾部。limit = 0 表示"只要总行数"（概览用）。
 *
 * 行格式（audit.cj 写入口，制表符分隔，note 里的制表符已被替换成空格，所以恒为 5 段）：
 *   <iso本地时间>\tactor=<id>\t<动作>\ttarget=<id>\t<备注>
 * 解析失败的行走"原始行"分支，绝不丢——运维日志里出现看不懂的行本身就是线索。
 */
func clubAuditLines(s: Store, limit: Int64): JsonArray {
    let path = "${s.dir}/audit.log"
    let out = JsonArray()
    if (!exists(path)) {
        return out
    }
    var text = ""
    try {
        text = String.fromUtf8(File.readFrom(path))
    } catch (e: Exception) {
        return out
    }
    let lines = text.split("\n", -1, removeEmpty: true)
    let n = lines.size
    var start: Int64 = 0
    if (limit > 0 && n > limit) {
        start = n - limit
    }
    /* 新→旧输出 */
    var i = n - 1
    while (i >= start) {
        let line = lines[i]
        let o = JsonObject()
        let parts = line.split("\t", -1, removeEmpty: false)
        if (parts.size >= 5) {
            jPutStr(o, "at", parts[0])
            jPutInt(o, "actor_id", clubIntOr(clubStripPrefix(parts[1], "actor="), 0))
            jPutStr(o, "actor_name", clubMemberName(s, clubIntOr(clubStripPrefix(parts[1], "actor="), 0)))
            jPutStr(o, "action", parts[2])
            jPutInt(o, "target_id", clubIntOr(clubStripPrefix(parts[3], "target="), 0))
            jPutStr(o, "target_name", clubMemberName(s, clubIntOr(clubStripPrefix(parts[3], "target="), 0)))
            jPutStr(o, "note", parts[4])
            jPutBool(o, "parsed", true)
        } else {
            jPutStr(o, "at", "")
            jPutInt(o, "actor_id", 0)
            jPutStr(o, "actor_name", "")
            jPutStr(o, "action", "?")
            jPutInt(o, "target_id", 0)
            jPutStr(o, "target_name", "")
            jPutStr(o, "note", line)
            jPutBool(o, "parsed", false)
        }
        out.add(o)
        i -= 1
    }
    return out
}

func clubStripPrefix(v: String, pfx: String): String {
    if (v.size >= pfx.size && v[0..pfx.size] == pfx) {
        return v[pfx.size..]
    }
    return v
}
