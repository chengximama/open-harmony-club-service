# 社团管理工具

社团内部管理工具，解决两个问题：**① 社团里有哪些人 ② 每件事由谁负责、做到什么程度。**

首页是「我的任务」，不是组织架构图。名录只是任务的目录——真正让人每天打开 App 的是"我负责什么"。

| 项 | 值 |
| --- | --- |
| 客户端 | 鸿蒙 App（**ArkTS**）—— 见 `entry/`、`AppScope/`，页面在 `entry/src/main/ets/pages/`。**本机已实测可编译打包**（见 `docs/client-build.md`）；尚未接接口 |
| 服务端 | 仓颉 **1.1.3** + [轻舟 QingZhou](https://gitcode.com/BIT-FSSLab/QingZhou) 框架，Windows 部署 |
| 持久化 | 文件存储（内存 Store + 写时原子落盘 JSON），不用数据库 |
| 传输 | **框架原生 TLS**（不用 Nginx），自签证书必须带 SAN |
| 第一版目标 | 社团内部试用 2 周 |

---

## 当前进度

| 模块 | 内容 | 状态 |
| --- | --- | --- |
| **服务端 M1 骨架** | 构建链路 · Store 与原子落盘 · 统一响应/错误码 · 时间与时区 · **`can()` 权限函数** · 认证 5 接口 | ✅ 完成并验证 |
| **服务端 M2 组织与成员** | 部门增删改（会长独占）· 名录/详情/编辑 · 移出社团 · 待分配与**批量分配** · **会长移交（原子）** · 重置密码 · 注册口令 · 招募链接 | ✅ 完成并验证 |
| **服务端 M3 任务** | 我的任务（服务端分组）· 列表筛选 · 详情 · 创建（`client_token` 幂等）· 编辑/转交 · 状态流转与阻塞原因 · 软删除 · 日历同步 `lookup` | ✅ 完成并验证 |
| **服务端 M4 课题** | 课题树（递归进度）· 详情（面包屑）· 创建 · 编辑 · 移动（**环形校验** + 深度 6 + 禁止跨部门）· 删除（**子节点上提，绝不级联**） | ✅ 完成并验证 |
| **服务端 M5 部署** | 带 SAN 自签证书 · TLS 1.2/1.3 通过、1.0/1.1 被拒 · 部署包 18.8 MB · 从部署目录端到端跑通 | 🟡 本机完成；**公网部署待服务器信息** |
| **服务端代码评审修复（第一轮）** | 按 `docs/code-review.md` 修完 3 个 P0 权限漏洞 + 8 个 P1 + 13 个 P2，并补上会真正失败的回归测试 | ✅ 完成并验证 |
| **服务端代码评审（第二轮）** | `docs/code-review.md` 的 9 条新发现：文档类 N-2 / N-3 / N-4 · **N-1**（落地页 HTML 转义）+ **N-9**（CSP）· **N-7**（不可作用于同权/更高权的人，已从"重置密码"推广到改角色 / 禁用 / 改名）· **N-5**（`idem` 补校验）· **N-6**（注册节流改**按客户端 IP + 递增退避**，因此无需新增接口）—— **全部处理完毕**（N-8 按约定不改），每条都补了会因回退而变红的断言 | ✅ 完成并验证 |
| **服务端代码评审（第三轮）** | `docs/code-review.md` 第三轮复验：第二轮 9 条**全部确认修复**；新发现 4 条（**N-10** `assign`/`assign-batch` 漏在同权保护之外 · N-11 文档限定词 · N-12 裸 IPv6 退化 · N-13 分布式尝试）—— **已全部处理**。N-10 的两个面（降级同权者、用 `assign` 推翻会长对同权者的移出决定）都已堵住 | ✅ 完成并验证 |
| **轻舟升级与 CangDB 适配** | 升级轻舟到 **`e072980`**（= 上游 HEAD；上游 `141a735` 修好 DEF-1，本地补丁撤销）；新版 `store.cj` / `rbac.cj` 依赖的 **CangDB 上游仓只有 README、没有代码** → 用 `server/src/fw_rbac_store.cj`（文件存储的数据层）+ `fw_rbac.cj`（`requirePermission` 中间件）替代，`build.ps1` 排除框架原版 | ✅ 完成并验证（单测 471 / 冒烟 421 / TLS 22 / 契约 30） |
| **轻舟后台管理界面（新增）** | 随 `e072980` 快照带进上游的**后台管理界面**，并新增 `build.ps1 -Target admin` → `build\admin\admin.exe`（自包含：exe + 前端 + `admin.env`）。它的数据层**路由到本地 JSON 文件**（复用 `fw_rbac_store.cj`，沧海 CangDB 未公开）。端到端验证 `server/tests/admin-check.ps1` | ✅ 完成并验证（后台端到端 **29 / 0**） |
| **「社团管理」运维页（新增）** | 后台里加一页 `/club`：**读**直接读社团库文件（`server/src/ops/*`，club-server 不在跑也能看），**写**由后台以**专用运维账号**（club-server 的 `role = ops`）的身份调用 club-server 真实 API（分配/停用/重置口令/换注册口令/部门增删/优雅停服），另带概览、任务/课题/招募链接查询、**审计日志**与**一键备份**。入口是我们自己的 `src/ops/admin_main.cj`（上游 `examples/admin.cj` 只作对照、逐字节原样）；顺手修掉上游"成功响应也可能带 404"的状态码问题。端到端验证 `server/tests/ops-check.ps1` | ✅ 完成并验证（运维页端到端 **64 / 0**） |
| **运维身份独立于会长（新增）** | 运维**不该由会长执行**：新增内置身份 **`ops`**（权限 = 会长去掉「移交会长」，**不可由 API 分配**，只能 `club-server init-ops <手机号> <口令>` 创建、`retire-ops` 停用）。运维人员只登录后台（口令由 `admin.exe` 首次启动随机生成），后台代持运维账号去调 club-server → **审计里 actor 是运维**，与会长做的操作分得清清楚楚。顺带补齐部门新增/改名的审计（原先只有删除记了） | ✅ 完成并验证（单测 490 / 冒烟 422 全绿） |
| **服务端容量基准与四项性能改造** | 按"接近千人"的容量问题做了可复现基准（`server/tests/bench.ps1`，真实 HTTP + 旧版本 worktree 对比），并落地四项改造：① 列表排序插入排序→**堆排序** ② **PBKDF2 移出全局锁**（三阶段加锁）③ 过期**令牌回收** ④ 整库落盘移出锁（请求链末端刷盘）。实测只有 ② 有量级收益（**4 并发登录 1574 → 867 ms**），①④ 在千人档落在噪声内、价值是最坏情况下界 —— 见 `docs/capacity-baseline.md` | ✅ 完成并验证（单测 349 / 冒烟 347 / TLS 22） |
| **服务端第四轮复验修复** | 按 `docs/code-review.md` **第四轮**的 6 条新发现修：**N-14**（本机判定用子串匹配 `::1` → 远程 IPv6 可远程关停服务，改成按地址相等比白名单）· **N-15**（4 个 handler 被 4xx 拒绝却留下半改状态并落盘，改成两阶段赋值）· **N-16**（登录时序侧信道可枚举手机号，改成两条路径等价 PBKDF2）· **N-17**（审计 IO 移出锁）· **N-18**（任务可挂任意部门课题，补部门一致性）· **N-19**（招募 token 32 位 → 32 字节） | ✅ 完成并验证（单测 387 / 冒烟 360 / TLS 22） |
| **按 UI 设计规格对齐服务端** | 拿《鸿蒙俱乐部-全场景UI设计规格》13 页逐条对服务端，8 条按设计稿落地（含队友复验补的 2 条）：**D-1** 权限摘要补 5 个管理布尔（由 `can()` 推导）· **D-2** 名录 `?q=` 搜索姓名或部门 · **D-3** 任务/课题**读**范围放开到全社团（写不变）· **D-4** 阻塞任务的**求助对象** `needs_help` + 部长首页带出本部门阻塞项 · **D-5** 任务**逾期天数** `overdue_days` · **D-7** 成员详情补 `done_tasks` / `overdue_tasks`。另**定稿密码口径**（D-6：8–32 字节 + 只允许数字/英文/符号，有意偏离设计稿的 6 位下限）；其余按决定保留原版本。逐条证据见 `docs/ui-spec-conformance-review.md` | ✅ 完成并验证（单测 471 / 冒烟 421 / TLS 22 / 契约 30） |
| **客户端（ArkTS）** | 技术栈定为 **ArkTS**（2026-09-14）；已接入组内上传的成员模块 **3 页**（成员名录 / 待分配审批 / 管理），`hvigorw assembleHap` 实测 **BUILD SUCCESSFUL**（未签名）。**页面仍是假数据，未接任何接口** | 🟡 可构建；待签名 + 待接接口 |

**接口进度 40 / 40**（认证 5 · 组织与成员 20 · 任务 8 · 课题 6 = 39 个业务接口，另加运维 `/health` 1 个）。
> 口径说明 1：早期写「38 / 39」是把 `docs/api-design.md` §6.1「接口总清单」里的 `/health` 漏算了。
> 口径说明 2：2026-09-16 新增 `GET /api/v1/join/{token}`（招募链接的公开 JSON 解析，D-16）后为 **40 / 40**。
> 此外还有一个**不在接口清单里**的公开 HTML 页面 `GET /join/{token}`（招募链接落地页，给浏览器看的）。

**四套测试全部通过**（每次改动都要跑）：

```powershell
cd server
.\build\club-server.exe test                                              # 单测 505 项
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1     # HTTP 冒烟 427 项
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\tls-check.ps1 # TLS 22 项
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\client-contract-check.ps1  # 前后端契约 33 项
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\init-name-check.ps1        # init-admin 的会长姓名选项 40 项
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\bench.ps1     # 容量基准（按需，见 docs/capacity-baseline.md）
```

> 冒烟里有一条**会因机器而异**：N-21 的"按 IP 节流"反证需要一块**非回环网卡**才能造出"远程来源"。
> 取不到时它打印 `skip` 并**计为通过**（不是失败，见 `code-review.md` N-30）——
> 所以**项数可能在 427 上下浮动一两条，判据是 `FAIL 0`，不是那个总数**。
> （本机无网卡时实测连跑两次都是 **PASS 427 / FAIL 0**。）

**后台 / 运维页另有几套**（改了 `build.ps1 -Target admin`、`fw_rbac_store.cj`、`src/ops/*`、轻舟快照或前端后都要跑）：

```powershell
cd server
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Target admin   # 编运维台（会带上 server\admin-web\dist）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\admin-check.ps1     # 后台自身（RBAC + JSON 数据层）29 项
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ops-check.ps1       # 「社团管理」运维页 64 项（含运维账号登录 / 写路径）
node .\tests\web-logic-check.mjs                                                 # 前端逻辑 17 项（401 不该整页跳转，见 code-review N-32）
```

> 改了前端源码（`server\admin-web\src`）要重建 `dist`（需要 Node）：
> `cd server\admin-web ; npm install ; npm run build` —— 部署机不需要 Node，`dist` 随仓库提交。
> 本机没装 npm 时可直接用仓库里已有的 vite：`node node_modules\vite\bin\vite.js build`。
> ⚠️ 运维台**关闭了 ETag**（`admin_main.cj` 的 `staticOpts.enableETag = false`）：轻舟的 ETag 只按
> 文件字节大小生成，而 vite 重建后 `index.html` 字节数不变（只有 hash 文件名变）→ 浏览器会拿到
> 304 卡在旧 HTML 上、而它引用的旧 JS 已被删除 → **白屏**。见 code-review N-33。

---

## 目录结构

```
README.md                    本文件：唯一入口，看这一个就能了解项目状态
docs/                        所有文档（设计、验证、报告、指南）
server/                      服务端（仓颉）
  build.cmd                  build.ps1 的包装（免记 -ExecutionPolicy Bypass；双击也行）
  build.ps1                  编译（cjc + stdx + 轻舟同包编译；工具链自动探测）
  build-package.ps1          生成部署包 dist\club-server\（exe + 4 DLL + 证书 + 说明）
  src/                       23 个源文件，按职责分层（见下）
  src/ops/                   运维台（`-Target admin`）专用源码：入口 + 社团库只读视图 + JSON 小工具替身
  admin-web/                 运维台前端（Vue 3 源码 + **预构建 dist**，在上游版本上加了「社团管理」页）
  tests/                     冒烟、TLS、前后端契约、容量基准、后台与运维页端到端脚本
  build/                     构建输出（每次编译重建，不入库）；build\admin\ 是运维台那份
  dist/                      部署包（含私钥，不入库）
  certs/                     自签证书与私钥（不入库）
  third_party/qingzhou/      内置的轻舟框架快照（出处与维护见其中的 PROVENANCE.md）
entry/  AppScope/  hvigor/   鸿蒙客户端工程（ArkTS；DevEco 要求这些在根目录）
  entry/src/main/ets/pages/           页面：Index / MemberList / MemberDetail / PendingApproval / Manage
  entry/src/main/ets/entryability/    EntryAbility.ets（UIAbility，loadContent('pages/Index')）
  entry/src/main/resources/base/profile/main_pages.json   页面路由登记（ArkTS 必需）
docs/                        见下方「文档索引」
```

### 服务端源码分层（`server/src/`）

| 文件 | 职责 |
| --- | --- |
| `main.cj` | 入口：`serve` / `serve-tls` / `init-admin` / **`init-ops`** / **`retire-ops`** / `test` + 全部路由注册 |
| `store.cj` | 6 张表的数据模型 + 内存 Store + 原子落盘（**快照在锁内、写盘在锁外**）+ 查询/堆排序/课题树辅助 |
| **`perms.cj`** | ★ **`can(member, action, target)`——全项目唯一的权限判定点** |
| `auth.cj` | 口令哈希（PBKDF2-HMAC-SHA256）· 令牌 · 认证辅助 |
| `errors.cj` / `jsonw.cj` / `views.cj` | 错误码表 · 响应包装与取参 · 对外 JSON 视图 |
| `timex.cj` / `ids.cj` / `strx.cj` / `paging.cj` / `audit.cj` | 时间与时区 · ID 与随机口令 · 字符串工具 · 分页 · 敏感操作审计 |
| `h_auth.cj` `h_dept.cj` `h_member.cj` `h_secret.cj` `h_link.cj` `h_task.cj` `h_plan.cj` `h_ops.cj` | 各模块的 HTTP handler（按 api-design 的 Part 分组） |
| `fw_rbac_store.cj` / `fw_rbac.cj` | 轻舟 RBAC 的**本地适配层**（上游版依赖 CangDB，而该仓库暂无代码）：文件存储的数据层 + `requirePermission` 中间件 |
| `tests.cj` | 单测（`club-server.exe test`）；容量基准见 `server/tests/bench.ps1` |

### 运维台源码（`server/src/ops/`，只参与 `-Target admin`）

| 文件 | 职责 |
| --- | --- |
| `admin_main.cj` | 运维台入口：上游那套后台路由（登录/用户/角色/权限/健康/关停）+ **`/api/club/**`** 运维接口（含 `/api/club/session`：用专用运维账号换 club-server 令牌）+ 状态码修正（`statusNormalizer`） |
| `club_view.cj` | 社团库**只读**视图：概览 / 名录 / 部门 / 任务 / 课题 / 招募链接 / 审计日志（**白名单字段，绝不带 `pw_*`**） |
| `club_json.cj` | `jsonw.cj` 里 6 个小工具的自包含替身 —— 让 `store.cj` 能单独编进运维台 |

> 这三张文件**不参与**服务端构建（`build.ps1` 取的是 `server/src/*.cj`，不递归子目录），
> 因此不会和 `jsonw.cj` 的同名函数撞车（轻舟"同包同名"是本项目记录过的坑）。

---

## 5 分钟上手（服务端）

```powershell
cd server

# 1. 编译（并把 4 个依赖 DLL 复制到 build\）
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
#    不想记 -ExecutionPolicy Bypass 就用包装脚本：.\build.cmd（参数相同，双击亦可）
#    没有仓颉 SDK 的机器请直接用部署包（见 docs\local-deploy.md §4），**不需要编译**

# 2. 到 exe 所在目录操作（与部署形态一致：一切按相对路径）
cd build
.\club-server.exe init-admin 13800000000 ClubPass2026 data   # 预置首任会长 + 4 个组织
#    会长姓名（不给则默认「会长」）：ASCII 用 --name LiSi；
#    **中文必须走文件**（中文当命令行参数会让程序在 main 之前就崩，见 docs\API-NOTES.md 坑 11）：
#    [IO.File]::WriteAllText("$PWD\n.txt","张三",[Text.UTF8Encoding]::new($false))
#    .\club-server.exe init-admin 13800000000 ClubPass2026 data --name-file n.txt
.\club-server.exe serve 8080 data                           # HTTP 起服务
# 或者 HTTPS（先用 openssl 生成带 SAN 的证书，见 docs\server-guide.md）
.\club-server.exe serve-tls 8443 data ..\certs\cert.pem ..\certs\key.pem
```

> **`cwd` 必须是 exe 所在目录**——数据目录与证书都按相对路径读。
> 部署包里的 `start-https.cmd` 已经做了 `cd /d "%~dp0"`。

### 后台管理界面 + 「社团管理」运维页（可选）

后台这份现在有**两个页面**：上游那套（仪表盘 / 用户管理，管的是**后台自己的账号**），
以及我们加的 **「社团管理」运维页 `/club`**（管的是**社团的真实数据**）。
前端产物已随仓库提交，**部署机不需要 Node/npm**：

```powershell
cd server
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Target admin   # -> build\admin\admin.exe
cd build\admin
.\admin.exe        # http://127.0.0.1:3000/  （运维页：http://127.0.0.1:3000/club）
```

- 后台账号 `admin`（角色 1）、`user`（角色 2）；**口令首次启动（建库）时随机生成**（各 16 个
  十六进制字符），控制台**打印一次**并写入 `build\admin\admin.env` 的 `admin_pass` / `user_pass`，
  之后不再回显 —— 想自己指定就把这两行取消注释填值（**别用 `admin123` 这类公开默认值**，
  2026-09-17 前它就是默认值，见 `code-review.md` N-29）。端口/密钥/令牌时长也在
  `build\admin\admin.env`（首次构建生成随机 64 位 `secret`，之后不覆盖）。
  ⚠ 这两条是**轻舟 RBAC 那套口令**（存在 `rbac.json`），与 `club-server` 的会长/成员账号
  （PBKDF2，存在 `data\db.json`）**不是一套**，两边不能互用。
- **后台自身的数据层是本地 JSON 文件**（`build\admin\admin-data\rbac.json`）：沧海 CangDB 尚未公开，
  所以复用我们的 `server/src/fw_rbac_store.cj` —— 内存 `Store` + 写时原子落盘（先 `.tmp` 再 `rename`）。
- 运维页 `/club` 放给**后台的 admin 角色**，或**直接用运维账号登录进来的身份**
  （后端 `/api/club/**` 同口径；后台的 `user` 角色拿到 403）。
  它**读**社团库文件（`admin.env` 的 `club_data`，默认 `../data`），club-server 不在跑也能看；
  **写**在 club-server 侧的身份是**专用运维账号**（`role = ops`）—— 所以运维人员
  **不需要知道任何会长口令**，页面上也不出现任何社团账号的口令：
  1. 先在 club-server 建运维账号（一次性）：`club-server init-ops <手机号> <口令> [数据目录]`
     → 权限 = **除「移交会长」外与会长同权**；退役用 `club-server retire-ops <手机号>`。
     它**不可由 API 分配**（否则会长能造出权限略高于自己的账号），只能这样建。
  2. **直接用这个手机号 + 口令登录运维台**（2026-09-17 起登录框两种凭据都认）——
     不用改任何配置文件，写操作就是该账号的身份。
     也可以改用「后台代持」：把手机号/口令填进 `admin.env` 的 `club_user` / `club_pass`
     （留空 = 运维页只能看不能改，页面会提示），但**改完必须重启 `admin.exe`**。
  3. 页面直连 club-server 做写操作（令牌由后台代持，内存缓存 6 小时）。
  → 于是 club-server 的**审计里 actor 是"运维"**，与会长做的操作分得清清楚楚（职责分离）。
     会长 / 成员账号登运维台会被 **403**（运维不该由会长执行）。
- 运维页能做的写操作：分配/改派、停用、重置口令（含**会长的**口令）、换注册口令、
  **部门增删改**、优雅停服 club-server；**移交会长是会长专属，运维不参与**（按钮会明确提示）。
  另带概览、任务/课题/招募链接、**审计日志**（解析 `audit.log`）与**一键备份**。
- 验证：`tests\admin-check.ps1`（**29 / 0**，后台自身）+ `tests\ops-check.ps1`（**64 / 0**，运维页含运维账号登录与写路径）。
- **上游那个状态码特性已在我们自己的入口修掉**：上游 `respondOk/respondErr` 只写 body 的 `code`，
  而 `passOnNotFound` 路由 miss 时会先把 `ctx.status` 置成 404 → "成功响应带 404"。
  我们的 `src/ops/admin_main.cj` 加了一个链尾 `statusNormalizer()` 按 `code` 回写状态码
  （现在 `/api/me`、`/api/club/**` 都是 200，拒绝是 401/403）。**内置框架没动**，
  归属证据与细节见 `docs/API-NOTES.md`「坑 34」。

---

## 文档索引（全部在 `docs/`）

| 文档 | 用途 | 什么时候看 |
| --- | --- | --- |
| **`docs/HANDOFF.md`** | **交接说明**：项目现状、已冻结设计、验证过的技术事实、未决事项 | **接手项目先看这个** |
| `docs/server-guide.md` | 服务端指南：构建/运行/测试、进度、两条实现纪律 | 动服务端代码前看 |
| **`docs/local-deploy.md`** | **本机部署一页上手**：前置体检 · **部署顺序**（编译 → 一次性初始化〔会长 + 运维账号〕 → 起服务 → 验证 → 停止 → 注册 → 可选运维台）· HTTPS · 部署包 · 让客户端连上 · 数据与备份 · 坑表 | **第一次在本机跑服务端看这个** |
| **`docs/API-NOTES.md`** | 编译期 API 事实清单 + **38 条踩坑记录**（含"轻舟成功响应也可能带 HTTP 404"「坑 34」、"关停端点回执可能丢失"「坑 36」、"仓颉枚举不能用 `==`"「坑 38」） | 加新函数前先查（避让框架同名符号） |
| `docs/api-design.md` | **接口设计的唯一权威**：40 个接口逐条定义 | 写服务端时全程对照 |
| **`docs/code-review.md`** | **代码评审报告（六轮）**：一 24 条 · 二 9 条 · 三 4 条（N-1…N-13）· 四 6 条 + N-20 · 五 4 条（N-21 登录 CPU 放大 / N-22 构建脚本陷阱…）· 六 3 条（**N-29 运维台默认口令** / N-30 测试环境依赖…）—— 前五轮已修并复验，**第六轮见文末** | 想了解"哪些坑已经踩过、为什么这样写" |
| `docs/v1-scope.md` | 范围基准：11 页面、6 张表、19 条业务规则、权限矩阵 | 想知道"这个要不要做" |
| **`docs/ui-spec-conformance-review.md`** | **UI 设计规格 ↔ 服务端一致性审计**：13 页逐条对照、15 条差异（含 4 条设计稿自相矛盾）+ 已对齐清单 + 处置口径 | **改服务端契约前先看这个**（尤其是"读范围全社团、写不变"这条边界） |
| `docs/frontend-brief.md` | 前端对接精简版 | 客户端同事看 |
| **`docs/client-build.md`** | **客户端构建与现状**：构建命令、两个环境坑（JBR / SDK 路径）、ArkTS 迁移记录、剩余 TODO | **动客户端前先看这个** |
| **`docs/client-integration-review{,-2,-3}.md`** | **客户端接入适配检查（三轮）**：第一轮（PR #2）3 条拦路 + 10 处接口；第二轮（PR #3/#4）导航与孤立页；第三轮（PR #5/#6/#7）**构建阻塞 + 三个 Tab 占位 / 三个孤儿页** | 客户端同学接接口、改导航前先看 |
| **`docs/client-integration-review.md`** | **客户端接入适配检查（给写客户端的同学）**：PR #2 的 **3 条拦路问题**（缺 INTERNET 权限 / baseUrl 是相对路径 / 响应信封少剥一层）+ **10 处接口路径·方法对不上**，每条带实测状态码与改法 | 接接口前先对一遍，改完按 §8 验收 |
| **`docs/capacity-baseline.md`** | **容量基准与四项性能改造**：可复现的实测矩阵（改造前/后 × 1000/3000）、每项改造的真实收益与**没测出收益的地方**、容量阈值 | 想知道"近千人扛不扛得住""哪项优化真有用" |
| `docs/deploy-windows-verify.md` | 部署与验证步骤、目标配置基线 | 部署时看 |
| **`docs/d-member-module.md`** | **客户端 D 模块（成员名录 P06 + 成员详情 P07）交付说明**：功能概览 · 需求逐项核对（已实现/未实现+原因）· 权限矩阵 · 逐项验证步骤（含期望文字）· 待决策清单。**附带记录本次修掉的全工程编译阻塞（`MemberApi.ets` 重复 `disable()`）** | 看/改「名录」「成员详情」两页时；以及**任何人构建客户端失败时** |
| *（对外材料已移出仓库）* | 仓颉运行时缺陷报告 + Issue 稿件 + 最小复现（`repro.cj`）、轻舟 TLS 需求与实测 —— 都在仓库上层 `cangjie-upstream\`（完整路径 `E:\harmonyOS\cangjie-upstream\`） | 追溯上游问题来源时 |

---

## 环境事实（本机已验证）

| 项 | 位置 / 值 |
| --- | --- |
| 编译器 | **1.1.3** (cjnative, x86_64-w64-mingw32)。本机装在 `D:\Cangjie\bin\cjc.exe`，但 `build.ps1` **自动探测**（显式传参 > 常见位置 > `CANGJIE_HOME` > `PATH`，且**按版本优先 1.1.x**），换机器不用改脚本 |
| stdx | **1.1.3.1**。注意 `stdx` 与编译器是**两个包**，要分别安装；本机在 `E:\cangjie\stdx\windows_x86_64_cjnative\static\stdx` |
| 轻舟框架 | **已内置在本仓库**：`server/third_party/qingzhou`（上游 commit **`e072980`** = 上游 HEAD，记在其中的 `UPSTREAM_COMMIT`；内容由 `MANIFEST.sha256` 逐字节校验、`build.ps1` 每次构建都验）。2026-09-15 迁移 —— 原先指仓库外 `E:\cangjie\qingzhou`，换台机器就编不了、或静默编到别的版本（`docs/code-review.md` N-20）。快照里同时带 `examples/admin.cj` + 预构建的 `admin-web/`（轻舟后台）。DEF-1 已由上游 `141a735` 修复，我们的本地补丁已撤 |
| OpenSSL 3 | **不随仓库提交**（6.5 MB 二进制）：`build.ps1` 按 **`third_party/qingzhou/deps/openssl` → `-OpenSslDir` → Git for Windows 的 `mingw64\bin`** 顺序找，并打印实际来源；详见 `server/third_party/qingzhou/deps/openssl/README.md` |
| 仓颉运行时 | `D:\Cangjie\runtime\lib\windows_x86_64_cjnative` |
| openssl CLI | `D:\Program Files\Git\usr\bin\openssl.exe`（生成证书、TLS 验证用） |
| **DevEco Studio** | **6.1.1.300**（`D:\DevEco Studio`）—— 自带 SDK **API 24 / 6.1.1.125**、hvigor 6.24.4、JBR **21**。构建客户端见 `docs/client-build.md` |

### 六条最容易踩的坑

1. **4 个 DLL 必须与 exe 同目录**：`libcangjie-runtime.dll`、`libboundscheck.dll`、`libcrypto-3-x64.dll`、`libssl-3-x64.dll`。缺 OpenSSL 两个时**编译期无警告**，运行时才报错。
2. **`cwd` 必须是 exe 所在目录**，否则配置与证书读不到，会出现"假失败 + 假通过"。
3. **同包编译会撞名字**：我们与轻舟同一个 `package qingzhou`，框架已占用 `pad2`、`verifyPassword`、`randomHex`、`bodyStr` 等。加顶层函数前先查 `docs/API-NOTES.md`。
4. **轻舟新版的 `store.cj` / `rbac.cj` 依赖外部 CangDB**（`gitcode.com/BIT-FSSLab/CangDB` 上游只有 README、没有代码）。我们用适配版代替：`server/src/fw_rbac_store.cj`（数据层换成文件存储）+ `fw_rbac.cj`（响应用我们的错误格式），`build.ps1` 里排除框架原版；**轻舟自带的后台（`-Target admin`）也复用同一个 `fw_rbac_store.cj` 把数据落到 JSON 文件**。**升级轻舟后必须重跑全部测试（单测/冒烟/TLS/契约/后台端到端）。**
5. **证书必须带 SAN**：现代客户端完全忽略 CN，只看 `subjectAltName`。按真实公网 IP 重签后再部署。
6. **私钥绝不入库**：`server/certs` 与 `server/dist` 都已在 `.gitignore`；用 `git check-ignore -v <路径>` 自检。

> 完整的 38 条踩坑记录（含 PowerShell 5.1 的七个坑、cjenv 切换 SDK 打断构建等）见 **`docs/API-NOTES.md` 第 3 节**。

---

## 未决事项

| # | 事项 | 卡住什么 |
| --- | --- | --- |
| 1 | **服务器步骤 0 未跑**：架构是否 x64、公网 IP、可用端口、防火墙 + 云安全组 | 卡 M5 的公网部署验证 |
| 2 | **CangDB 上游无代码**（老师给的仓库只有 README）：轻舟新版的 RBAC 数据层用不了 | 已用文件存储的适配版顶上（`fw_rbac_store.cj`）：**我们的服务端**和**轻舟自带的后台**都走它 —— 后者的数据落在 `build\admin\admin-data\rbac.json`；拿到可用 CangDB 后替换回上游实现 |
| 3 | 给轻舟的需求文档已更正（去掉 Linux 前提） | 需补发一份更正 |
| 4 | 忘记密码：v1 由会长重置，不做自助找回 | 已定 |
| 5 | 服务器可用期限、备份交接人（至少两人） | 需向老师确认 |
| 6 | 鸿蒙侧载分发（AGC 内部测试轨道、签名证书） | 流程耗时可能超过开发本身，**建议尽早启动** |
| 7 | **客户端三项待办**：① **签名未配**（产出 `entry-default-unsigned.hap`，装不上设备）② 只做了 **3 / 11** 页，缺**首页「我的任务」** ③ 页面全是假数据、**未接任何接口**。另：如需换 `bundleName`（现为 `com.club.manager`）趁现在改 | 见 `docs/client-build.md` §3 |
| 8 | ~~轻舟后台的成功响应也可能带 HTTP 404~~ | ✅ **已在我们的入口修掉**（`src/ops/admin_main.cj` 的 `statusNormalizer()`；内置框架未动）。见 `API-NOTES` 坑 34 |
| 9 | **运维账号的口令要换**：本机开发数据目录里建的是 `13800000009 / admin123`（按甲方指定的口令） | 生产上必须换强口令（`club-server init-ops` 可重设）；它等价于"会长权限减移交" |
| 10 | ~~客户端不认识 `ops` 角色~~ | ✅ **已按"隐藏系统账号"解决（服务端侧）**：`GET /members` 名录与 `?q=` 搜索都**不返回** `role = ops` 的账号（它不是社团成员），客户端不需要任何改动。要看/管这个账号用运维台（它直读库文件，仍然显示「运维」）。按 id 查详情仍可达（是隐藏不是丢失，smoke 有闸门盯着） |
| 11 | **改运维页前端需要 Node** | `dist` 随仓库提交，部署机不需要 Node；改 `server\admin-web\src` 的人要 `npm install && npm run build`（本机用 DevEco 自带 node 18 + npm 10 实测通过） |

---

## 设计原则（违反会导致返工）

| 原则 | 具体体现 |
| --- | --- |
| **同一事实只存一份** | 删了 `Department.lead_id`；课题不设 status；逾期不设状态；`Plan.dept_id` 只在顶层 |
| **能从事实推导的就不存** | 逾期由 `due_at` 算；课题进度由整棵子树的任务聚合 |
| **绝不级联删除** | 删课题子节点上提；任务软删除 |
| **权限判定收敛到一个函数** | `can(member, action, target)`；**禁止在每个 handler 里手写 if** |
| **服务端权威** | `updated_at`、逾期、分组、`is_overdue` 全部服务端生成 |
