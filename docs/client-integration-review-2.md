# 客户端接入适配检查 · 第二轮（PR #3 / PR #4 之后）

> **被检提交**：`ac6dfc9`（含 PR #3 契约对齐 `f5b4af7`、PR #4 任务+课题模块 `e72fe94`）
> **检查方**：服务端侧 · 2026-09-16
> **一句话结论**：接口这一层**已经对得很干净**（契约回归 **PASS 30 / FAIL 0**，客户端声明的每条路径与方法服务端都认得），
> 但**新做的任务 / 课题 / 个人页在 App 里一个都点不进去** —— 导航壳还停在最早那版三 Tab，而**首页「我的任务」是彻底孤立的**。
> 换句话说：**接口通了，路没修**。
>
> 本文是 [`client-integration-review.md`](./client-integration-review.md)（PR #2）的**续篇**。
> 上一轮提的 3 条拦路问题 + 10 处路径/方法 + 错误形状，**已全部复验通过**，不再重复。
> 本文只列**仍未解决**的，按严重性排序。改完请把对应条目标 ✅。

---

## 0. 改完怎么自查

```powershell
# 1) 编译（必须用 DevEco 自带 JBR + SDK，否则报 UnsupportedClassVersionError，见 docs/client-build.md）
$ds = "D:\DevEco Studio"
$env:DEVECO_SDK_HOME = "$ds\sdk"
$env:JAVA_HOME       = "$ds\jbr"
$env:PATH            = "$ds\jbr\bin;$ds\tools\node;$ds\tools\ohpm\bin;$env:PATH"
& "$ds\tools\hvigor\bin\hvigorw.bat" assembleHap --no-daemon

# 2) 起一个真服务端（联调期用 HTTP，省掉自签证书信任的麻烦）
cd server
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
cd build
.\club-server.exe init-admin 13800000000 ClubPass2026 dev-data
.\club-server.exe serve 8080 dev-data

# 3) 契约回归：把 entry/src/main/ets/api/*.ets 里声明的每条 (方法, 路径) 都打一遍
cd ..\..
powershell -NoProfile -ExecutionPolicy Bypass -File .\server\tests\client-contract-check.ps1
#    期望：契约回归 PASS 30 / FAIL 0
```

**编译通过 + 契约回归全绿 ≠ App 能用。** 本轮 §1 正是这类"全绿但点不进去"的问题——
所以下面每条都给了**设备上的验证动作**，请以真机/模拟器实测为准。

---

## 1. 🔴 三个新模块在 App 里一个都点不进去（导航壳没跟着改）

### 现象

登录成功后落到 `pages/Index`，而 `Index.ets` 仍然是最初那版**三 Tab 壳**：

```
成员名录  |  待分配  |  管理        ← 都是早期页面，且仍是硬编码假数据
```

App 里**没有任何入口**能走到任务 / 课题 / 个人页。`MyTasksPage.ets`（190 行，已接 `GET /tasks/mine`）
连路由都没登记、也没人 import 它 —— 它是一个**孤岛**。

### 证据：从入口把跳转图走一遍

入口是 `entryability/EntryAbility.ets:33` 的 `windowStage.loadContent('pages/SplashPage')`。
把它之后所有跳转都列出来（`replaceTo` / `pushTo` / `router.pushUrl` 三种写法全查了）：

| 页面 | `main_pages.json` 登记 | 被谁跳转 | 可达？ |
| --- | --- | --- | --- |
| `SplashPage` | ✅ | `EntryAbility:33`（入口） | ✅ |
| `LoginPage` | ✅ | Splash / `HttpClient:174`(401) / `PendingWaitPage:216` | ✅ |
| `RegisterPage` | ✅ | `LoginPage:210` | ✅ |
| `PendingWaitPage` | ✅ | Splash:164 / `LoginPage:256` / `RegisterPage:334` | ✅ |
| `Index` | ✅ | Splash:166 / `LoginPage:258` / `PendingWaitPage:73` | ✅ |
| `ProfilePage` | ✅ | **（无人跳转）** | ❌ |
| `TaskListPage` | ✅ | **（无人跳转）** | ❌ |
| `TaskDetailPage` | ✅ | `TaskCard:48`（而 TaskCard 只在 TaskListPage 里用） | ❌ |
| `PlanTreePage` | ✅ | `MyTasksPage:164`（而 MyTasksPage 本身不可达） | ❌ |
| `PlanDetailPage` | ✅ | `PlanTreePage:37`、自跳转`:176` | ❌ |
| `CreateTaskPage` | ✅ | `TaskListPage:178` | ❌ |
| `CreatePlanPage` | ✅ | `PlanTreePage:112` | ❌ |
| `MyTasksPage` | **❌ 未登记** | **（无人 import、无人跳转）** | ❌ |
| `MemberListPage` | ❌（当组件用，正常） | `Index:39` | ✅ |
| `MemberDetailPage` | ❌（当组件用，正常） | `Index:30` | ✅ |
| `PendingApprovalPage` | ❌（当组件用，正常） | `Index:47` | ✅ |
| `ManagePage` | ❌（当组件用，正常） | `Index:52` | ✅ |

`MemberListPage` / `MemberDetailPage` / `PendingApprovalPage` / `ManagePage` 没登记是**对的**
（它们是被 `Index` 直接 import 的组件，不走路由）。**问题只出在上面 8 个 ❌**。

### 为什么该重视

- 设计里写明「**首页是「我的任务」，不是组织架构图**」，`GET /tasks/mine` 被称为 **v1 最重要的接口** ——
  而现在真机上打开 App 只能看到组织架构图，**且那三个页面还是假数据**。
- 你们这两轮的工作量（约 1000 行、接口全对得上、契约回归 30/0）在真机上**完全体现不出来**。
- 这属于"两个分支并行落地、壳没跟着改"的典型缺口，**改动很小但影响最大**。

### 怎么改

1. **`MyTasksPage` 要登进路由**：加进 `entry/src/main/resources/base/profile/main_pages.json` 的 `src` 数组。
   （`@Entry` 页面必须登记，否则 `router` 跳过去会失败。）
2. **把 `Index.ets` 换成新壳**：至少让首页是「我的任务」，并能进任务列表 / 课题树 / 个人页。
   两个方向二选一：
   - **A（改动最小）**：`Index.ets` 直接 import 这四个页面做 Tab，替掉/扩充现在的三个 Tab；
   - **B（更贴设计）**：`Index` 只做壳，用 `Tabs` 承载「我的任务 / 任务 / 课题 / 我的」，
     把现在的 `MemberListPage` 等挪到「我的 → 成员名录」二级入口。
3. 顺手把可达性做进验收（见 §0 的自查 + 下面的 30 秒验证）。

> ⚠️ 只做第 1 步**不够** —— 登记了路由但没人跳转，页面照样进不去（`ProfilePage` 现在就是这个状态）。

### 30 秒验证（请务必在设备上做一遍）

起服务端 + 装 App，登录后：

- 首页能不能看到**「我的任务」**（逾期 / 阻塞 / 今天到期 / 本周 / 以后 / 无截止）？
- 能不能从首页走到**课题树**、从任务列表走到**任务详情**、从「我的」走到**个人资料**？
- 退一次登录再进一次，仍然进得去？

### 诚实说明（本条的验证强度）

**本条是静态推导**（读导航图 + import 关系 + 路由登记表），**没有在设备/模拟器上实跑 App**（本机无设备），
与上一轮 §附 的局限相同。之所以仍按 🔴 报：**三条证据同时成立**——
`MyTasksPage` 无 import、无路由登记、无任何跳转指向它；其余 7 个页面无任何跳转指向它们。
但请以你们真机实测为准；若实际能进去（例如别处有我没搜到的动态跳转），**请直接反驳我**并告诉我路径。

---

## 2. 🟠 默认走明文 HTTP，且 cleartext 是**全局**放开

### 位置

| 文件 | 内容 |
| --- | --- |
| `entry/src/main/ets/config/Env.ets:7` | `export const BASE_URL: string = 'http://10.0.2.2:8080/api/v1';` |
| `entry/src/main/resources/base/profile/network_config.json` | `base-config.cleartext-traffic-permitted: true`（**base-config → 全局**，不是按域名） |
| `entry/src/main/module.json5:18-23` | `metadata: network_security_config` 引用上面那份 |
| `entry/src/main/ets/entryability/EntryAbility.ets:17` | `HttpClient.getInstance().setBaseUrl(BASE_URL)` ← 启动即生效 |

### 影响

- 登录请求带**手机号 + 密码**；之后每个请求带 **30 天有效的 Bearer token**（`TOKEN_TTL = 30 * 86400`）。
- 联调走模拟器/局域网没问题，但**这份默认值会被打成正式包**：校园网里就是明文凭据传输。
- 服务端本来就有**框架原生 TLS**，项目和 `README.md` 也把 TLS 列为必须。

### 口径提醒

`docs/api-design.md:123` 早就把这条点名过：

> 登录密码、token **以明文经过校园网/公网**……如果你认为社团内部试用阶段可以接受明文，
> 请在评审时明确记录这个决定 —— **我不会默认帮你跳过它。**

所以现在缺的不是"发现"，而是一个**明确的决定**。请在 PR 描述里写明选哪一档。

### 怎么改（三档，至少做第 1 档）

1. **发布构建走 HTTPS**：`BASE_URL` 改 `https://<host>:8443/api/v1`，并在 App 里**内置自签 CA**
   （服务端 `serve-tls 8443`；步骤见 `docs/HANDOFF.md` 的 D 段）。
   若不想维护两套地址，用构建期变量区分 debug / release。
2. **把明文收窄**：如果 SDK 支持按域名放开，只对开发机那个地址开 cleartext，其余一律禁止。
3. **最低限度**：把 `network_config.json` 的 `cleartext-traffic-permitted` 置 `false`，
   按上一轮 §9 的判定法实测一次——**登录页报 `NETWORK_ERROR` 就说明明文确实被拦**，那就只能走第 1 档。

> ⚠️ **别把开关写进 `AppScope/app.json5` 或 `entry/src/main/module.json5`** —— 会直接构建失败
> （`00303038 Configuration Error / Schema validate failed`）。这条上一轮已用真实构建输出验证过两次。
> 另：那份 `network_config.json` **是否真的被运行时采纳，目前没有实测证据**（上一轮 §9 的结论），
> 别默认"写了就一定生效"——请用第 3 档的实测确认。

---

## 3. ⚠️ 勘误：上一份文档里有一条**会让构建失败**的建议，请忽略

`docs/client-integration-review.md` **§1.2（第 78-80 行）** 现在写着：

> **用 HTTP 明文时**：HarmonyOS 默认可能拦明文流量，需要在 `module.json5` 里加
> `"cleartextTraffic": true`（**已在本机 SDK 的 `configSchema_rich.json` 里确认这个键存在**）。

**这条是错的，请不要照做。** 同一份文档的 **§9（第 298-299 行）** 已经用真实构建输出推翻了它：

```
AppScope/app.json5        → app.network.cleartextTraffic        ❌ 00303038 Configuration Error
entry/src/main/module.json5 → module.network.cleartextTraffic   ❌ 同上
```

根因：`network` 那个键属于**旧 FA 模型**（`config.json → deviceConfig`），
Stage 模型（`app.json5` + `module.json5`）里没有它。

**这是我们的文档问题，不是你们的代码问题**（上一轮的纠正只写进了 §9，没回头改 §1.2 的正文），
我们已经记下来会去修。发这份文档的目的是**先止损**：在 §1.2 改掉之前，请以 §9 为准。

---

## 4. 🧹 仓库卫生：`_commit_msg.txt` 还在，而且**已被 git 跟踪**

- 位置：仓库根 `_commit_msg.txt`（356 字节，7 行，内容是 PR #2 的提交信息本身）。
- 上一轮 §6 已经提过一次（"请删掉"），**至今仍在，而且进了版本库**——也就是说每次 clone 都会带上它。
- `.gitignore` 里只有 `.commitmsg*.tmp` 这条规则，**挡不住这个名字**。

```powershell
git rm --cached _commit_msg.txt
Remove-Item _commit_msg.txt
```

以后提交前 `git status` 看一眼，或 `git add <具体文件>` 而不是 `git add -A`（服务端这边也踩过，见 `docs/API-NOTES.md`）。

---

## 5. 🟡 上一轮 §7 的非阻塞项：逐条**仍未处理**

这些我们复核过，还是原样。不阻塞联调，按你们的排期走即可，但别再当成"已经做完了"：

| 项 | 位置 | 说明 | 状态 |
| --- | --- | --- | --- |
| `router` API 已 deprecated | `utils/RouterUtils.ets:9,14,18` | `replaceUrl` / `pushUrl` / `back` 在 API 24 都标了 deprecated（编译期警告）；后续迁 `Navigation` + `NavPathStack` | ⏳ 未动 |
| 死代码 | `store/TokenStore.ets:33` | `const dataDir = context.preferencesDir;` 声明后未使用 | ⏳ 未动 |
| `Preferences` 旧签名 | `store/TokenStore.ets:34` | `getPreferences(context, 'app_preferences')` 是旧签名（新 API 用 options 对象）；当前能编过 | ⏳ 未动 |
| 未捕获异常 | `TokenStore.ets:65,76,77`、`RouterUtils.ets:9,14` | 编译警告 "Function may throw exceptions. Special handling is required."，建议包 `try/catch` | ⏳ 未动 |
| 仍是不签名 HAP | 构建配置 | 产出 `entry-default-unsigned.hap`，装不上真机；配置步骤见 `docs/client-build.md` §2 | ⏳ 未动 |

### 另外两条我们新注意到、但**不打算让你们改**的（仅供知悉）

- **令牌存在 `Preferences` 里是明文**。`auth_token` 是 30 天有效的凭据，鸿蒙另有
  `@ohos.security.asset`（Asset Store Kit）专门存凭据。当前做法不算错（很多 App 都这样），
  但如果之后要提升安全等级，这是首选改造点。
- **`util/ClientToken.ets` 的 `genClientToken()` 用 `Math.random()`**。这里**不是安全问题**：
  服务端的幂等键是 `kind:actorId:token`（带提交者本人），猜到别人的 token 也越权不了。
  仅记录它不是密码学随机源，无需改动。

---

## 6. 改完的验收标准

1. 编译 `BUILD SUCCESSFUL`；
2. `server/tests/client-contract-check.ps1` → **PASS 30 / FAIL 0**；
3. **真机/模拟器上**（这是本轮新增的重点，上两轮都缺这一步）：
   - 启动 → 登录 → **首页是「我的任务」**，能看到逾期 / 阻塞 / 今天到期 / 本周 / 以后 / 无截止六组；
   - 首页 → 课题树 → 课题详情 → 任务详情，全链路能走通；
   - 「我的」→ 个人资料 → 退出登录 → 回登录页；
   - 杀掉 App 重开**仍保持登录**；
4. 负例：错口令时提示来自服务端（不是"请求失败"）；未登录访问受保护接口跳登录页；
5. 明文 HTTP 的处置**写进 PR 描述**（选 §2 的哪一档）。

---

## 附：本次检查的方法与局限

| 项 | 值 |
| --- | --- |
| 被检提交 | `ac6dfc9`（含 `f5b4af7` PR #3、`e72fe94` PR #4） |
| 服务端侧 | 同一提交，**未改动任何客户端文件** |
| 静态检查 | 客户端 34 个 `.ets` 逐个扫描了 import 关系、路由跳转与 API 声明；其中 `HttpClient` / `Env` / `TokenStore` / `ClientToken` / `EntryAbility` / `Index` / `SplashPage` / `MyTasksPage` 按行读过。把 `replaceTo` / `pushTo` / `router.pushUrl` / `router.back` 四种写法**全部抽出**（第一遍正则漏了 `pushTo`，已重跑），重建跳转图；`main_pages.json` 与 `pages/*.ets` 做双向核对 |
| 实测 | 服务端重编译 + 四套测试实跑（单测 387 / 冒烟 360 / 契约 30 / TLS 见下）；契约回归逐条打真实 HTTP |
| 未覆盖 | **没在设备/模拟器上跑过 App（本机无设备）** —— §1 与 §2 的运行时结论来自静态推导，请以真机实测为准 |
| TLS 套件 | 本机沙箱内 `tls-check.ps1` 得 3/3，与 `docs/code-review.md` 附录 B 记录的是**同一个沙箱假阴性**（`openssl` 起不来、Schannel 挡住 .NET 客户端），**不是服务端问题**；服务端 TLS 已另证正常 |
| 对照依据 | `docs/api-design.md`（接口权威）· `server/src/views.cj`（字段形状）· `server/src/jsonw.cj`（信封/错误）· `server/src/perms.cj`（权限） |
