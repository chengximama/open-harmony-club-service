# 客户端接入适配检查 · 第三轮（导航整改 / 日历同步 / UI 规则之后）

> **被检提交**：`8289500`（PR #5 / #6 / #7 合入：A 侧导航整改、任务接入系统日历、9 项 UI 规则、
> 任务/课题页改底部 Tab、4 个 API 文件修复）
> **检查方**：服务端侧 · 2026-09-16
> **一句话结论**：**接口这一层仍然全绿（契约回归 30 / 0）**，但这次更新**编译不过**
> （权限配置 + 4 个 ArkTS 错误）；而且 review-2 说的「路没修」**只修了一半** ——
> Tab 壳有了，但**三个 Tab 是占位符、三个页面成了孤儿**，于是**任务 / 课题 / 我的任务整块仍进不去**。
>
> 本文只列**仍未解决**的，按严重性排序；改完请把对应条目标 ✅。
> 上一轮提的 3 条拦路 + 10 处路径 + 错误形状（`client-integration-review.md`）、
> 以及导航与孤立页（`client-integration-review-2.md`）**已经复验过**，本文不重复。

---

## 0. 改完怎么自查

```powershell
# 1) 编译（必须用 DevEco 自带 JBR + SDK，见 docs/client-build.md）
$ds = "D:\DevEco Studio"
$env:DEVECO_SDK_HOME = "$ds\sdk"; $env:JAVA_HOME = "$ds\jbr"; $env:PATH = "$ds\jbr\bin;$ds\tools\node;$ds\tools\ohpm\bin;$env:PATH"
& "$ds\tools\hvigor\bin\hvigorw.bat" assembleHap --no-daemon
#    期望：BUILD SUCCESSFUL，且产物 entry\build\default\outputs\default\entry-default-unsigned.hap

# 2) 契约回归（服务端侧提供；只看 entry/src/main/ets/api/*.ets，客户端不需要能编过）
powershell -NoProfile -ExecutionPolicy Bypass -File .\server\tests\client-contract-check.ps1
#    期望：契约回归 PASS 30 / FAIL 0

# 3) 孤儿页检查（本文 §2 的方法，把名字换掉即可复用）
foreach ($pg in @("MyTasksPage","TaskListPage","PlanTreePage")) {
  $refs = Select-String -Path entry\src\main\ets\pages\*.ets,entry\src\main\ets\components\*.ets `
            -Pattern $pg -Encoding UTF8 | Where-Object { $_.Filename -ne "$pg.ets" }
  "{0,-14} 被引用于：{1}" -f $pg, $(if ($refs) { ($refs | ForEach-Object { $_.Filename }) -join ", " } else { "没有任何引用（孤儿）" })
}
```

> **编译通过 + 契约回归全绿 ≠ App 能用**：本文 §2 正是这种「都绿但点不进去」的问题。

---

## 1. 🔴 P0 · 构建阻塞（两条，第一条在构建第一步就挂）

### 1.1 `READ_CALENDAR` / `WRITE_CALENDAR` 缺 `reason` 与 `usedScene`

**现状**（`entry/src/main/module.json5:17-22`）：两个权限只写了 `name`。
**实测报错**（`hvigorw assembleHap` 第一条就失败）：

```
00303218 Configuration Error
Error Message: The reason and usedScene attributes are mandatory for user_grant permissions.
  > For the har/hsp module, add the reason field to the permission of the error information in the preceding file.
```

**为什么**：`ohos.permission.INTERNET` 是 **normal** 级，声明即可；而日历这两个是 **user_grant** 级
（要弹窗向用户申请），所以必须给出「为什么需要」与「在什么场景用」—— 系统要用这两项向用户展示申请理由。
**改法**（照抄即可）：

```json5
// entry/src/main/module.json5
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },
  {
    "name": "ohos.permission.READ_CALENDAR",
    "reason": "$string:permission_calendar_reason",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
  },
  {
    "name": "ohos.permission.WRITE_CALENDAR",
    "reason": "$string:permission_calendar_reason",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
  }
],
```

```json
// entry/src/main/resources/base/element/string.json —— 在 "string" 数组里加一条
{ "name": "permission_calendar_reason", "value": "用于把任务同步到系统日历（可随时在系统设置里关闭）" }
```

> 复验时我在本地**临时**补过这两处（只为把检查做完），**未提交、事后已还原** ——
> 这一条请你们改，不要依赖我这边的工作区。

### 1.2 四个 ArkTS 编译错误（补上权限后立刻暴露）

| # | 位置 | 报错原文 | 怎么改 |
| --- | --- | --- | --- |
| 1 | `entry/src/main/ets/util/CalendarSync.ets:168:46` | `Property 'getCalendars' does not exist on type 'CalendarManager'. Did you mean 'getCalendar'?` | API 名写错了：`CalendarManager` 上没有 `getCalendars`，改成 `getCalendar(...)`（拿单个日历），或按官方接口取「所有日历」的入口 |
| 2 | `util/CalendarSync.ets:168:11` | `Use explicit types instead of "any", "unknown" (arkts-no-any-unknown)` | ArkTS 禁止 `any`/`unknown`：给变量显式类型（这里是日历对象的接口） |
| 3 | `util/CalendarSync.ets:170:13` | 同上 | 同上 |
| 4 | `entry/src/main/ets/pages/MemberDetailPage.ets:140:7` | `Type 'string' is not assignable to type '"active" \| "pending" \| "disabled"'` | 成员状态是联合类型：赋值前收敛（用字面量/类型守卫，或把类型放宽为 `string` 再在渲染处判分支） |

> 这四条都是**编译期**错误，本地一跑 `assembleHap` 就会列出来（`COMPILE RESULT:FAIL {ERROR:4 …}`）。
> 日历同步是**新功能**，它把这两类问题一起带进来了；`MemberDetailPage` 那条是这次改动引入的回归。

---

## 2. 🔴 P1 · 导航：壳有了，但三个 Tab 还是占位符，三个页面成了孤儿

`entry/src/main/ets/pages/Index.ets` 现在**有**底部 5 个 Tab（`Tabs({ barPosition: BarPosition.End })`）✓，
方向是对的；但三个最关键的 Tab 内容是**占位符**：

| Tab | 现在的内容 | 应该有 |
| --- | --- | --- |
| 我的任务 | `this.placeholderTab('我的任务', '任务分组与进度将在这里展示')` | `MyTasksPage` |
| 任务 | `this.placeholderTab('任务', '任务列表与新建入口将在这里展示')` | `TaskListPage` |
| 课题 | `this.placeholderTab('课题', '课题树与进度将在这里展示')` | `PlanTreePage` |
| 名录 | `MemberListPage` ✓ | — |
| 我的 | `ProfilePage` ✓ | — |

而这三个页面文件**已经没有任何引用了**（它们同时被从 `main_pages.json` 里移除，这在「改成 Tab 组件」的
方向上是**对的**：组件不需要登记路由；但既然改成了组件，就必须被 Tab 引用）：

```
MyTasksPage    被引用于：没有任何引用（孤儿）
TaskListPage   被引用于：没有任何引用（孤儿）
PlanTreePage   被引用于：没有任何引用（孤儿）
```

**连锁后果（比"少三个页面"更严重）**：`TaskDetailPage` / `CreateTaskPage` / `PlanDetailPage` /
`CreatePlanPage` 这四页**在路由表里**，但唯一会跳到它们的入口就是 `TaskListPage` / `PlanTreePage` ——
入口成了孤儿，于是这四页**实际同样不可达**。也就是说：**任务与课题模块在 App 里整块进不去。**

**改法**：把三个 `placeholderTab(...)` 换成真组件（与 `MemberListPage` 同样的用法）：

```ts
// Index.ets 顶部
import { MyTasksPage } from './MyTasksPage';     // 注意各页的导出形式（default / 具名）要与文件一致
import { TaskListPage } from './TaskListPage';
import { PlanTreePage } from './PlanTreePage';

// Tab 内容
TabContent() { MyTasksPage() }.tabBar(this.tabBarBuilder('我的\n任务', 0))
TabContent() { TaskListPage() }.tabBar(this.tabBarBuilder('任务', 1))
TabContent() { PlanTreePage() }.tabBar(this.tabBarBuilder('课题', 2))
```

> 注意：这三页从「路由页」改成「组件」后，**页面内原来的 `router.pushUrl` 到自己的跳转都应当删掉**
> （组件不是路由目标），而它们内部跳去 `TaskDetailPage` / `CreateTaskPage` 等的**仍然保留**（那几页还在路由表里 ✓）。

---

## 3. 🟡 P2 · 两条非阻塞、但建议一并处理

### 3.1 `BuildProfile` 的导入写法（能用，但脆）

`entry/src/main/ets/config/Env.ets` 现在是：

```ts
import BuildProfile from '../../../../../entry/build/default/generated/profile/default/BuildProfile';
```

**实测能解析**（`entry/build/default/generated/profile/default/BuildProfile.ets` 确实在编译前生成 ✓），
但这个相对路径依赖：① product 名恰好是 `default`；② 先构建过、产物目录还在；③ 目录层级不被人动。
建议改成 hvigor 提供的虚拟模块写法：

```ts
import BuildProfile from 'BuildProfile';
```

> `Env.ets` 里「调试走 HTTP、发布走 HTTPS，且发布地址故意写成 `replace-before-release.invalid` 做失败保护」
> 这个设计**很好**，保留。

### 3.2 明文配置那份文件目前是**惰性**的

`resources/base/profile/network_config.json` 这次改成了「默认禁明文 + 只给 `10.0.2.2` / `127.0.0.1` /
`localhost` 放行」——**概念上完全正确**，但**这套键名在本机 SDK / hvigor 里不存在**：

- 第四轮我们**实测过**：把 `network` 写进 `AppScope/app.json5` 或 `entry/src/main/module.json5`，
  `hvigorw` 会直接报 `00303038 Configuration Error / Schema validate failed, propertyName: 'network'`；
- 而 `network-security-config` / `base-config` / `cleartext-traffic-permitted` 这些键名，
  在整个 DevEco 安装目录里**搜不到**（hvigor 的类型定义 `NetworkObj` 只出现在旧 FA 模型的
  `config.json → deviceConfig` 里）。

结论：**这份文件写什么都不会生效**（`metadata` 引用本身合法，所以构建不报错，属于"静默无效"）。
真正要确认「HTTP 是否被拦」只能**真机/模拟器实测**：

- 起 `serve 8080` → 模拟器里若登录页报 `NETWORK_ERROR`，说明明文被拦 → 改走
  `serve-tls 8443` + **App 内内置自签 CA**（步骤见 `docs/HANDOFF.md` D 段）；
- 若能连通，那这份文件就是纯冗余，可以删掉（留着会误导下一个人）。

---

## 4. ✅ 已经对得上的（**别改**）

| 项 | 证据 |
| --- | --- |
| **接口契约** | 你们改了 4 个 API 文件（`DeptApi` / `MemberApi` / `PlanApi` / `TaskApi`）之后，**契约回归仍然 PASS 30 / FAIL 0** —— 客户端声明的每条 (方法, 路径) 服务端都认得 |
| **没有绕过 api 层** | `util/` `store/` `core/` 下**没有** `createHttp` / `/api/v1` / `HttpClient` 直连，全部走 `api/*.ets` —— 所以契约回归的覆盖面是完整的（新功能日历同步也干净） |
| **路由登记完整** | 代码里出现的每个跳转目标都已在 `main_pages.json` 登记（`CreatePlanPage` / `CreateTaskPage` / `PlanDetailPage` / `TaskDetailPage` … 都在）；`TaskListPage` / `PlanTreePage` 从路由表移除是**对的**（它们要当组件） |
| **`_commit_msg.txt` 已删** | 第一轮清单 §6 的那条误提交文件已经清掉了 ✓ |
| **INTERNET 权限仍在** | `module.json5` 里还在（这次只是在它旁边加了两个日历权限） |
| **发布地址保护** | `Env.ets` 的 `replace-before-release.invalid` + `BuildProfile.DEBUG` 分支（见 §3.1，写法建议改，设计保留） |

---

## 5. 服务端侧这次做了什么

- **只做复验，没有改任何产品文件**：服务端源码与脚本本次**零改动**，四套基线不变 ——
  单测 **398** / 冒烟 **362** / TLS **22** / 跨仓契约 **30**（全绿）。
- 为了把检查做完（否则构建第一步就挂），我在本地**临时**补了 §1.1 的权限配置，
  **未提交、事后已还原**；请以你们自己的修改为准。
- 本轮结论：**接口层没问题，问题在"能不能编出来"与"点不点得进去"** 这两件事上。

---

## 附 · 本次复验环境

| 项 | 值 |
| --- | --- |
| 被检提交 | `8289500`（PR #5 / #6 / #7） |
| 构建 | DevEco **6.1.1.300** 自带 JBR 21 + SDK API 24；`hvigorw assembleHap --no-daemon` |
| 构建结果 | **FAIL**（§1.1 → 补权限后 §1.2 的 4 个 ArkTS 错误） |
| 契约回归 | **PASS 30 / FAIL 0**（`server/tests/client-contract-check.ps1`） |
| 未覆盖 | 本机**无设备**，未在真机/模拟器上跑 App；§2、§3.2 的运行时结论以真机实测为准 |
