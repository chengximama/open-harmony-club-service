# 内置的轻舟（QingZhou）框架源码 —— 出处与维护说明

本目录是**上游轻舟框架的一份快照**，随本仓库一起提交，目的是让服务端构建**不再依赖机器本地的
`E:\cangjie\qingzhou`**（对应 `docs/code-review.md` 的 **N-20「构建不自包含」**）。

## 出处（唯一真相）

| 项 | 值 |
| --- | --- |
| 上游仓库 | <https://gitcode.com/BIT-FSSLab/QingZhou> |
| 上游 commit | 见同目录 **`UPSTREAM_COMMIT`**（当前 `e072980721528c4fe1127bd3a6fac60781ae81f1`，短号 `e072980`；**就是上游 HEAD**，2026-09-16 用 `api.gitcode.com/v5/repos/BIT-FSSLab/QingZhou/commits` 核过） |
| 取快照时间 | 2026-09-16 |
| 许可证 | 见同目录 `LICENSE`（随源码一起保留） |

> **版本号只写一处**：`UPSTREAM_COMMIT`。`build.ps1` 每次构建都会把它打印出来；
> `README.md` / `docs/HANDOFF.md` / `docs/API-NOTES.md` 只引用它，不再各自复述 commit ——
> 避免重新变成"同一个数字在三个文件里各写各的"（那正是 N-4 的模式）。

## 装了什么 / 故意没装什么

| 装了 | 说明 |
| --- | --- |
| `src/*.cj` | **全 36 个文件，一个不裁**。虽然两种构建各排除几个（见下），但保留完整源码才能对照"上游原本长什么样" |
| `examples/admin.cj` + `admin.env` | **后台管理界面**的服务端示例与配置模板。`build.ps1 -Target admin` 直接拿它当入口（见下节），所以必须随仓库进来 |
| `admin-web/` | 后台前端（Vue 3 源码 + **上游预构建的 `dist/`**）。`dist/` 已随快照提交 → **部署机不需要 Node/npm**，直接静态托管；`src/` 保留是为了改前端时能对照 |
| `LICENSE` / `README.md` / `CHANGELOG.md` / `cjpm.toml` | 出处与许可材料；`cjpm.*` 只作记录（我们不使用 cjpm 构建）。**上游在本次快照里删掉了 `cjpm.lock`**，我们也跟着删 |
| `deps/openssl/*.dll` | **不提交**（6.5 MB 二进制）。`build.ps1` 按 **本目录 → `-OpenSslDir` → Git for Windows 的 `mingw64\bin`** 顺序找，并**打印实际用的是哪一份**；详见 `deps/openssl/README.md`。本机实测：Git 自带的那两个与原先从轻舟 `deps` 拷的**逐字节相同**（3.5.7） |
| `MANIFEST.sha256` | 上述每个文件的 SHA-256（本次 **61** 个文件）；`build.ps1` 每次构建都会校验 |

| 没装 | 原因 |
| --- | --- |
| `.cache/` `build/` `target/` | 构建产物（合计约 90 MB），不是源码 |
| `docs/` `public/` `public_blog/` | 与"编译出服务端/后台"无关；需要时去上游看 |
| `benchmark.cj` `test-run.log` `main.cj.local-stub.bak` `.vscode/` | 上游自己的临时物/个人设置 |

## 构建时的排除项（**不是**本目录的内容问题）

`server/build.ps1` 有**两个目标**，排除的框架文件不一样：

| 目标 | 排除 | 原因 |
| --- | --- | --- |
| 默认（`club-server`，我们的俱乐部服务端） | `main.cj` | 框架自带 `main()`，入口由我们的 `server/src/main.cj` 提供 |
| | `unit_tests.cj` / `manual_runner.cj` | 框架自测，与本项目单测冲突 |
| | `store.cj` / `rbac.cj` | 上游这两张文件 `import cangdb.*`，而 CangDB 仓库只有 README、没有代码 → 改用我们的适配版 `server/src/fw_rbac_store.cj`（数据层=文件存储）+ `fw_rbac.cj`（`requirePermission`，我们的错误格式） |
| `-Target admin`（轻舟自带后台） | `main.cj` / `unit_tests.cj` / `manual_runner.cj` | 同上 |
| | `store.cj` | 只有它 `import cangdb.*`；入口是上游 `examples/admin.cj`，数据层换成 **`server/src/fw_rbac_store.cj`（JSON 文件）** |
| | （**保留** `rbac.cj`） | 后台示例用的是框架自带的响应格式，`rbac.cj` 正好配套 |

## 后台（admin）这份构建：怎么跑

```powershell
cd server
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Target admin
cd build\admin
.\admin.exe                      # 浏览器打开 http://127.0.0.1:3000/
```

- 产物目录**自包含**：`admin.exe` + `admin-web\dist` + `admin.env`（+ 4 个运行时 DLL）。
  上游 `examples/admin.cj` 是按 **cwd** 找资源和配置的（`serveWithOpts("./admin-web/dist")`、
  `loadConfigFile("./admin.env")`），所以**必须在 `build\admin` 里启动**。
- `admin.env` 首次构建时生成（随机 64 位十六进制 `secret`），**已存在就不覆盖**；
  端口 3000、数据文件 `admin-data/rbac.json`、token 有效期 7200 秒。
- 种子账号：`admin / admin123`（角色 1）、`user / user123`（角色 2）。
  ⚠ **这两条属于轻舟 RBAC 那套口令**（`security.cj` 的 `hashPassword`，迭代 SHA-256，存在
  `rbac.json` 里），与本项目 `club-server` 的会长/成员账号（`auth.cj` 的 PBKDF2-HMAC-SHA256，
  存在 `data/db.json` 里）**不是一套**：两边账号不能互用，`verifyPw` 也验不了这里的哈希。
- 数据层是 **JSON 文件**（沧海 CangDB 尚未公开）：`server/src/fw_rbac_store.cj`，
  内存 `Store` + 写时原子落盘（先写 `.tmp` 再 `rename`），**200 ⇒ 已落盘**。
- 端到端验证：`server/tests/admin-check.ps1`（**29 / 0**），覆盖静态托管、JWT 登录、
  鉴权/RBAC、用户增删写路径、JSON 落盘、优雅关闭。

> **一个上游特性要知道**：上游统一响应壳把业务码放在 **body 的 `code` 字段**（0=成功），
> HTTP 状态不承载业务语义；而且 `passOnNotFound` 的路由在 miss 时会先把 `ctx.status` 置成 404，
> 后续匹配上的处理器用 `respondOk/respondErr` 时并不重设 status —— 于是**成功响应也可能带 404**。
> 前端 `admin-web` 只 `fetch(...).json()` 后看 `code`，所以界面一切正常；用 curl 看就要看 body。
> 这是上游 `e072980` 本身的行为（已逐字节比对 `src/api.cj` / `src/router.cj` / `src/auth.cj`），
> **我们没有改框架来"修"它**。详见 `docs/API-NOTES.md`「坑 34」。

## 怎么用（一般不用管）

```powershell
cd server
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1                 # 我们的服务端
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Target admin   # 轻舟后台
```

- **校验失败**（内置文件被改/被删/多了源文件）→ 构建**拒绝继续**，并提示怎么办。
  这是有意的：内置框架不该被本地修改，**我们的改动一律放 `server/src/fw_rbac*.cj`**。
- 确实是有意改动（例如临时试验）→ 跑 `update-manifest.ps1` 重新生成清单，
  并在提交信息里说明为什么改了内置框架。

## 升级到更新的上游

```powershell
# 1) 确认上游目标 commit（本机没有 checkout 也能查）：
#    curl https://api.gitcode.com/api/v5/repos/BIT-FSSLab/QingZhou/commits?per_page=5
#    git -C E:\cangjie\qingzhou fetch --all ; git -C E:\cangjie\qingzhou log --oneline -10

# 2) 用**同一套文件集**覆盖本目录：
#      src/*.cj（全量） + examples/admin.cj + admin.env + admin-web/（含 dist/）
#      + LICENSE/README.md/CHANGELOG.md/cjpm.toml
#    `deps/openssl` 的两个 DLL **不进仓库**（构建时自动找，见 deps/openssl/README.md）
#    注意上游若删/增文件（本次删了 cjpm.lock），本目录要同步删/增

# 3) 更新 UPSTREAM_COMMIT

# 4) 重新生成清单
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-manifest.ps1

# 5) **必做**：核对 server/src/fw_rbac_store.cj / fw_rbac.cj 是否跟得上上游
#    （这两个文件是"跟着上游文件走的适配"，它自己的注释也写着会静默过期）
#    然后跑全部测试：单测 / 冒烟 / TLS / 跨仓契约 / 后台端到端
```

## 为什么这是一份"快照"而不是 submodule

submodule 需要使用者额外 `git submodule update` 且仍然要联网取码；subtree 会重写历史、
冲突处理麻烦。本项目要的是"**clone 下来就能编**"，所以直接提交快照 + 内容清单校验：
版本由 `UPSTREAM_COMMIT` 记录，内容由 `MANIFEST.sha256` 逐字节锁定 ——
比"记一个 commit 号但没人校验"更强，也符合 N-20 要求的"可复现的构建输入"。
