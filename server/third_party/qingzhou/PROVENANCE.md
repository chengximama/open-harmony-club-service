# 内置的轻舟（QingZhou）框架源码 —— 出处与维护说明

本目录是**上游轻舟框架的一份快照**，随本仓库一起提交，目的是让服务端构建**不再依赖机器本地的
`E:\cangjie\qingzhou`**（对应 `docs/code-review.md` 的 **N-20「构建不自包含」**）。

## 出处（唯一真相）

| 项 | 值 |
| --- | --- |
| 上游仓库 | <https://gitcode.com/BIT-FSSLab/QingZhou> |
| 上游 commit | 见同目录 **`UPSTREAM_COMMIT`**（当前 `3ea387eee77a20103ffdaf02aef6c662857859c0`，短号 `3ea387e`） |
| 取快照时间 | 2026-09-15（本机 `E:\cangjie\qingzhou` 的 checkout，`git rev-parse HEAD` 与上面一致） |
| 许可证 | 见同目录 `LICENSE`（随源码一起保留） |

> **版本号只写一处**：`UPSTREAM_COMMIT`。`build.ps1` 每次构建都会把它打印出来；
> `README.md` / `docs/HANDOFF.md` / `docs/API-NOTES.md` 只引用它，不再各自复述 commit ——
> 避免重新变成"同一个数字在三个文件里各写各的"（那正是 N-4 的模式）。

## 装了什么 / 故意没装什么

| 装了 | 说明 |
| --- | --- |
| `src/*.cj` | **全 29 个文件，一个不裁**。虽然我们构建时排除 5 个（见下），但保留完整源码才能对照"上游原本长什么样" |
| `LICENSE` / `README.md` / `CHANGELOG.md` / `cjpm.toml` / `cjpm.lock` | 出处与许可材料；`cjpm.*` 只作记录（我们不使用 cjpm 构建） |
| `deps/openssl/*.dll` | `libcrypto-3-x64.dll` + `libssl-3-x64.dll`（6.52 MB）。运行时必需，且原先是从轻舟目录里拷的 —— 不一起内置就仍要依赖仓库外的路径 |
| `MANIFEST.sha256` | 上述每个文件的 SHA-256；`build.ps1` 每次构建都会校验 |

| 没装 | 原因 |
| --- | --- |
| `.cache/` `build/` `target/` | 构建产物（合计约 90 MB），不是源码 |
| `admin-web/` `docs/` `examples/` `public/` `public_blog/` | 与"编译出服务端"无关；需要时去上游看 |
| `benchmark.cj` `test-run.log` `main.cj.local-stub.bak` `.vscode/` | 上游自己的临时物/个人设置 |

## 构建时的 5 个排除项（**不是**本目录的内容问题）

`server/build.ps1` 编译框架时排除这 5 个文件，原因写在脚本注释里：

| 排除 | 原因 |
| --- | --- |
| `main.cj` | 框架自带 `main()`，入口由我们的 `server/src/main.cj` 提供 |
| `unit_tests.cj` / `manual_runner.cj` | 框架自测，与本项目单测冲突 |
| `store.cj` / `rbac.cj` | 上游这两张文件 `import cangdb.*`，而 CangDB 仓库只有 README、没有代码 → 改用我们的适配版 `server/src/fw_rbac_store.cj`（数据层=文件存储）+ `fw_rbac.cj`（`requirePermission`） |

## 怎么用（一般不用管）

```powershell
cd server
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1        # 自动校验清单 + 打印上游 commit
```

- **校验失败**（内置文件被改/被删/多了源文件）→ 构建**拒绝继续**，并提示怎么办。
  这是有意的：内置框架不该被本地修改，**我们的改动一律放 `server/src/fw_rbac*.cj`**。
- 确实是有意改动（例如临时试验）→ 跑 `update-manifest.ps1` 重新生成清单，
  并在提交信息里说明为什么改了内置框架。

## 升级到更新的上游

```powershell
# 1) 在上游 checkout 里确认目标 commit，并看它改了哪些文件（尤其 store.cj / rbac.cj）
git -C E:\cangjie\qingzhou fetch --all
git -C E:\cangjie\qingzhou log --oneline -10

# 2) 用同一套文件集覆盖本目录（src 全量 + LICENSE/README/CHANGELOG/cjpm.* + deps/openssl/*.dll）
#    3) 更新 UPSTREAM_COMMIT
#    4) 重新生成清单
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-manifest.ps1

# 5) **必做**：核对 server/src/fw_rbac_store.cj / fw_rbac.cj 是否跟得上上游
#    （这两个文件是"跟着上游文件走的适配"，它自己的注释也写着会静默过期）
#    然后跑三套测试：单测 / 冒烟 / TLS
```

## 为什么这是一份"快照"而不是 submodule

submodule 需要使用者额外 `git submodule update` 且仍然要联网取码；subtree 会重写历史、
冲突处理麻烦。本项目要的是"**clone 下来就能编**"，所以直接提交快照 + 内容清单校验：
版本由 `UPSTREAM_COMMIT` 记录，内容由 `MANIFEST.sha256` 逐字节锁定 ——
比"记一个 commit 号但没人校验"更强，也符合 N-20 要求的"可复现的构建输入"。
