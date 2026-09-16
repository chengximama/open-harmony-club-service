# 本机部署服务端（Windows）· 一页上手

> **给第一次在本机把服务端跑起来的人**：照抄命令即可。全流程已在 **2026-09-16 本机实测通过**
> （下面的输出都是当次真实结果）。
>
> 本文只给「最短能跑通的路 + 最容易踩的坑」。细节与权威定义在别处：
> `server-guide.md`（构建/运行/测试全貌）· `deploy-windows-verify.md`（拷到服务器那一步）·
> `API-NOTES.md` §5（会让**所有**仓颉 exe 启动即崩的 Windows 更新）· `client-build.md`（客户端构建）·
> `api-design.md`（接口唯一权威）。

---

## 0. 两个形态，先选一个

| 形态 | 用途 | 怎么做 |
| --- | --- | --- |
| **① 在 `server\build\` 里直接跑** | 本机联调（客户端连它） | §2 的五步 |
| **② 产出 `server\dist\club-server\`** | 可整体拷走（换机器 / 上服务器） | §4 |

---

## 1. 前置体检（三条，缺一条就白折腾）

```powershell
# ① 仓颉 SDK + stdx：build.ps1 会自己找（显式传参 > 常见安装位置 > CANGJIE_HOME > PATH），
#    并**按版本优先挑 1.1.x** —— 所以不要求装在 D:\Cangjie 这种固定位置。
#    要知道它到底挑了哪套：跑一次 §2.1，看开头的 [build] 工具链： 两行。
#    本项目基线：cjc 1.1.3 + stdx 1.1.3.1（版本不符会显著警告，见 §2.1 与 §7 坑表）

# ② 那个会让所有仓颉 exe 启动即崩的 Windows 更新必须不在
Get-CimInstance Win32_QuickFixEngineering | Where-Object HotFixID -eq 'KB5124010'
#    有输出 → 先卸载它（完整证据见 docs/API-NOTES.md §5）；本次实测结果是「已卸载 ✓」

# ③ PowerShell 5.1 默认禁止跑脚本：调用 .ps1 一律带 -ExecutionPolicy Bypass
#    （嫌麻烦就用 server\build.cmd —— 包装脚本，已带好该参数，双击也能跑）
```

> ⚠️ 第 ② 条**必须先过**：KB5124010 装着时服务端 exe 一启动就 `exit=-1073741819`（`0xC0000005`），
> 看着像代码崩了，其实与代码无关。本项目已经踩过两次（§5.1 / §5.5）。

---

## 2. 五步跑起来

### 2.1 编译

```powershell
cd E:\harmonyOS\cangjie_web\server
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
# 等价写法（免记 Bypass、可双击）：.\build.cmd
```

真实输出（**开头三行是工具链 —— 先看清它挑了哪套 SDK**）：

```
[build] 工具链：cjc=D:\Cangjie
[build]          stdx=E:\cangjie\stdx\windows_x86_64_cjnative\static\stdx
[build]          cjc 版本：Cangjie Compiler: 1.1.3 (cjnative)
[build] 框架：轻舟 3ea387e（内置 third_party\qingzhou，24 个文件参与编译）
[build] 服务端 23 个文件 -> ...\server\build\club-server.exe
[build] 编译通过
[build] OpenSSL DLL 来源：D:\Program Files\Git\mingw64\bin
[build]   libcrypto-3-x64.dll  3.5.7  0330b5f558996f29…  与 EXPECTED 一致
[build]   libssl-3-x64.dll  3.5.7  feb5b300e0b3a021…  与 EXPECTED 一致
[build] 已复制 4 个依赖 DLL 到 build\
```

- **不需要仓库外的轻舟**：框架已内置在 `server\third_party\qingzhou`，构建时逐字节校验内容清单；
  上游版本记在其中的 `UPSTREAM_COMMIT`，每次构建都会打印。
- **4 个 DLL 自动就位**（2 个来自仓颉 SDK、2 个 OpenSSL 由脚本按
  「内置目录 → `-OpenSslDir` → Git for Windows」解析），**不用手工拷**。
- 只要编译、不拷 DLL：加 `-NoDll`。
- **换一台机器不用改脚本**：`cjc` 与 `stdx` 的位置**不再写死**。探测顺序是
  显式 `-CangjieHome` / `-Stdx` → 常见安装位置（`D:\Cangjie`、`C:\Cangjie`、`E:\Cangjie`、
  `%USERPROFILE%\Cangjie`…）→ `CANGJIE_HOME` / `CANGJIE_STDX` → `PATH`，且**按版本优先 1.1.x**。
- **装了 cjenv 之类版本管理器的人注意**：它会把全局 `CANGJIE_HOME` 改写成它自己的 SDK
  （本机是 1.0.5）。挑到非 1.1.x 时脚本会先打 `WARNING` —— cjc 与 stdx 版本串台的症状是
  编译中途 `LLVM ERROR: Broken module found`，看着像编译器 bug，其实只是环境串台。
  显式传了错路径也会被明确告知，**不会静默忽略**。
- **上一个服务端没停干净**：`ld.lld: error: failed to write the output file: Permission denied`
  —— 这不是权限/SDK 问题，而是 exe 还在运行。脚本会先自查，并直接给出处置命令。

### 2.2 初始化数据库（**只对空库可执行**）

```powershell
cd build        # ← ⚠️ 必须进到 exe 所在目录：data\ 与 certs\ 都按**相对路径**读
.\club-server.exe init-admin 13800000000 你的密码123 data
```

真实输出：

```
已创建首任会长：13800000000（成员 id=1，部门=1）
当前注册口令：DYMRXD          ← 随机 6 位，发给社团成员注册用，会长可随时更换
数据目录：data（db.json）
```

同时预置 4 个组织：**主席团 / 课题部 / 运营部 / 宣传部**。

### 2.3 起服务

```powershell
# HTTP（本机联调最省事）
.\club-server.exe serve 8080 data

# HTTPS（手机端正式使用走这条，见 §3）
.\club-server.exe serve-tls 8443 data certs\cert.pem certs\key.pem
```

前台运行日志直接打控制台；要后台跑（联调时常用）：

```powershell
$p = Start-Process .\club-server.exe -ArgumentList @("serve","8080","data") -PassThru -WindowStyle Hidden `
       -RedirectStandardOutput server.out.log -RedirectStandardError server.err.log
```

端口被占用先查：`netstat -ano | findstr :8080`。

### 2.4 验证它真的活着

> ⚠️ **别用浏览器打开 `http://127.0.0.1:8080/`** —— 根路径没有页面，会返回 **404**
> （浏览器还会顺带请求 `/favicon.ico`，同样是 404）。**这不是故障**：服务端是 API 服务，
> 非 API 的入口只有三个 —— `/health`（免认证，浏览器打开会看到 JSON）· `/join/{token}`
> （招募链接落地页，免认证、HTML）· `/admin/shutdown`（仅本机）；其余全部在 `/api/v1/` 下。
> 看到那两行 404，恰恰说明**服务端已经起来并且在记请求日志**。
> 想在浏览器里确认"活着"，请打开 **`http://127.0.0.1:8080/health`**。
```powershell
curl.exe -s http://127.0.0.1:8080/health
# {"ok":true,"data":{"status":"ok","version":"0.1.0","time":"2026-09-16T13:20:08+08:00"}}

# 再登录一次，确认接口链路通（拿令牌）
'{"phone":"13800000000","password":"你的密码123"}' | Set-Content body.json -Encoding ASCII
curl.exe -s -X POST http://127.0.0.1:8080/api/v1/auth/login -H "Content-Type: application/json" --data-binary "@body.json"
# {"ok":true,"data":{"token":"1c207a3c…","expires_at":"2026-10-16T13:20:08+08:00","member":{…}}}
Remove-Item body.json
```

> ⚠️ **用 `curl.exe`，不要用 `curl`** —— PowerShell 里 `curl` 是 `Invoke-WebRequest` 的别名，参数不通用。

数据落在 exe 目录下（就是「一个文件 + 一份备份 + 一份审计」）：

```
build\data\db.json        821 B    全库（每次写变更原子重写整个文件）
build\data\db.json.bak    683 B    上一版，防写坏
build\data\audit.log               敏感操作审计（重置密码 / 换口令 / 移出成员 / 会长移交 …）
```

### 2.5 停止服务

```powershell
curl.exe -s -X POST http://127.0.0.1:8080/admin/shutdown
# {"ok":true,"data":{"status":"shutting-down"}}      ← 进程随后自行退出
```

这是**仅本机可访问**的端点（Windows 没有信号机制，只能靠它优雅关闭）；远程打会 403。

---

### 2.6 注册第一个新账号（两步：**凭口令注册 → 会长分配**）

**① 注册口令在哪** —— `init-admin` 的输出里（如 `当前注册口令：DYMRXD`）。忘了就问服务端要（会长令牌）：

```powershell
curl.exe -s http://127.0.0.1:8080/api/v1/register-config -H "Authorization: Bearer <会长令牌>"
# {"ok":true,"data":{"code":"DJ6EA4","updated_at":"...","updated_by":{...}}}
```

换口令也是会长权限：`PUT /api/v1/register-config/code`（自定义）· `POST /api/v1/register-config/rotate`（随机换）。

**② 注册**（字段规则：`register_code` 必填 · `phone` 必须是合法手机号 · `password` **至少 8 位** · `name` 必填）：

```powershell
# 注意：中文姓名要用 **UTF-8 无 BOM** 的文件体，别用 Set-Content（ASCII 会变 ???，UTF8 会带 BOM）
[IO.File]::WriteAllText("$PWD\b.json", '{"register_code":"DJ6EA4","phone":"13900000002","name":"新同学","password":"newmember123"}', [Text.UTF8Encoding]::new($false))
curl.exe -s -X POST http://127.0.0.1:8080/api/v1/auth/register -H "Content-Type: application/json" --data-binary "@b.json"
# {"ok":true,"data":{"token":"...","member":{"id":2,"role":null,"dept":null,"status":"pending",...}}}
```

> 注册即登录，但账号是 **`pending`**、权限全 `false` —— 客户端会跳到「等待管理员分配」页。
> 这一步**不是 bug**：角色只能由会长授予（v1-scope 的权限设计）。

**③ 会长分配部门 + 角色** —— 分配后账号才 `active`、才有权限：

```powershell
curl.exe -s http://127.0.0.1:8080/api/v1/members/pending -H "Authorization: Bearer <会长令牌>"
curl.exe -s -X POST http://127.0.0.1:8080/api/v1/members/2/assign -H "Authorization: Bearer <会长令牌>" `
  -H "Content-Type: application/json" --data-binary "@b2.json"      # {"dept_id":2,"role":"member"}
# {"ok":true,"data":{"id":2,"role":"member","dept":{"id":2,"name":"课题部"},"status":"active",...}}
```

App 里对应「**待分配审批**」页（会长/副会长可见），两步都在界面上点得到。

**招募链接（可选，招新时更好用）**：会长 `POST /api/v1/dept-invite-links {"dept_id":3}` 拿到 token →
把 `http://<服务端地址>/join/<token>` 发到群里 → 新同学打开看到部门名，注册时带上 `dept_id` →
待分配列表里会带 **`dept_hint`**（会长一眼看出他想进哪个部门）。
> **链接不免除注册口令** —— 链接是便利，口令才是准入。

> ⚠️ **注册口令试错是按客户端 IP 节流的**（15 分钟内错 10 次 → 锁 5 分钟起、逐次翻倍，
> 见 `API-NOTES.md` N-6）。它是**内存态**：被自己锁住时，**重启服务即可清零**。
## 3. HTTPS（手机端正式使用要走这条）

自签证书**必须带 SAN**（现代客户端完全忽略 CN，只看 `subjectAltName`）：

```powershell
$openssl = "D:\Program Files\Git\usr\bin\openssl.exe"
cd E:\harmonyOS\cangjie_web\server
& $openssl req -x509 -newkey rsa:2048 -nodes `
  -keyout certs\key.pem -out certs\cert.pem -days 3650 `
  -subj "/C=CN/O=Club/CN=127.0.0.1" `
  -addext "subjectAltName=IP:127.0.0.1,DNS:localhost"

cd build
..\club-server.exe serve-tls 8443 data ..\certs\cert.pem ..\certs\key.pem

# 一条命令验完：协议版本（1.2/1.3 通、1.0/1.1 拒）+ SAN + 真证书校验下走一遍登录
powershell -NoProfile -ExecutionPolicy Bypass -File ..\tests\tls-check.ps1     # 期望 PASS 22 / FAIL 0
```

换真实公网 IP 部署时：把 SAN 里的 `127.0.0.1` 换成该 IP，并用
`openssl verify -CAfile certs\cert.pem -verify_ip <IP> certs\cert.pem` 自检。
**私钥绝不入库**：`server\certs` 与 `server\dist` 都在 `.gitignore`。

---

## 4. 部署包（可整体拷走）

```powershell
cd E:\harmonyOS\cangjie_web\server
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-package.ps1            # 带证书
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-package.ps1 -SkipCert   # 不带
```

产出 `server\dist\club-server\`（约 **19 MB**）：

```
club-server.exe  + 4 个 DLL        制品 5 个
certs\cert.pem   certs\key.pem     证书 2
start-http.cmd   start-https.cmd   启动脚本 2（脚本内已 cd + chcp 65001，双击即可，中文不乱码）
README.txt       dll-versions.txt  说明 + **实际打包进去**的 DLL 版本与 sha256（便于追溯）
```

整个目录拷到目标机即可运行 —— **同平台（Windows x64），目标机不需要装编译器**。

发包给队友可以直接用压缩包：`server\dist\club-server-<日期>.zip`（约 **6.8 MB**，
`build-package.ps1` 之后用 `Compress-Archive` 打一次即可）。因为是二进制，**不进 git**，
只能这样发过去 —— 队友 `git clone` 是拿不到 exe 的。
拷过去之后按 `README.txt` 走：`club-server.exe init-admin …` → 双击 `start-https.cmd`。

> **给不装编译器的队友**：这个目录就是给他们用的（同平台、免编译）。只要不动 Cangjie / 轻舟源码，
> 换掉 exe + 4 个 DLL 即可；改了服务端源码才需要 SDK 自己编（§2.1）。
>
> 上公网服务器还要采集 4 件事（本机替代不了）：架构是 x64 还是 ARM64 · 公网 IP 与端口可达性 ·
> **防火墙与云安全组是两层都要放行** · 服务器上已有什么服务。详见 `deploy-windows-verify.md` §3。

---

## 5. 让客户端的 App 连上它

| 客户端跑在哪 | 服务端地址 | 说明 |
| --- | --- | --- |
| **模拟器** | `http://10.0.2.2:8080/api/v1` | 模拟器里 `127.0.0.1` 指它自己，宿主机要用 `10.0.2.2`（`Env.ets` 里默认就是这个） |
| **真机（同一局域网）** | `http://<本机局域网IP>:8080/api/v1` | 改 `entry/src/main/ets/config/Env.ets` 的 `DEV_BASE_URL`；本机当前 IP 是 `10.75.84.132` |
| 真机走 HTTPS | `https://<IP>:8443/api/v1` | 需先在 App 里内置自签 CA（`docs/HANDOFF.md` D 段） |

真机联调要**放行防火墙**（只在本机访问则不需要）：

```powershell
New-NetFirewallRule -DisplayName "club-server 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow
```

> **明文 HTTP 会不会被系统拦？** 客户端那份 `network_config.json` 的键名在本机 SDK / hvigor 里**不存在**
> （第四轮已实测：`app.json5` / `module.json5` 内联 `network` 会被 schema 直接拒绝），属**惰性配置**。
> 想确认只能实测：登录页若报 `NETWORK_ERROR` 就是被拦了 → 改走 HTTPS + 内置 CA。

---

## 6. 数据与备份（唯一不能省的一步）

- 全库就是 `data\db.json` 一个文件，**每次写变更都整库原子重写**，并保留 `db.json.bak`。
- **把 `data\` 纳入每日备份，并至少交接给两个人** —— 这是这个项目里唯一"丢了就没了"的东西。
- 别把数据目录放在会被清理的位置：`server\build\` 是构建产物目录（`**/build` 在 `.gitignore`），
  长期使用建议放在 `dist\club-server\data\`（部署包形态）并单独备份。
- `audit.log` 与 `db.json` 在同一目录，一并备份。

---

## 7. 坑表（都是本项目真踩过的）

| 坑 | 现象 | 解法 |
| --- | --- | --- |
| **KB5124010** | 所有仓颉 exe `0xC0000005` 启动即崩 | 卸载该更新（`API-NOTES.md` §5） |
| **执行策略** | `无法加载文件 build.ps1，因为在此系统上禁止运行脚本` | 调用时带 `-ExecutionPolicy Bypass` |
| **cwd 不对** | 报错，或出现"假失败 + 假通过" | `cd` 到 exe 所在目录（部署包的启动脚本已 `cd /d "%~dp0"`） |
| **`curl` 是别名** | 参数不生效/行为诡异 | 用 `curl.exe` |
| **DLL 少了** | 缺 `libcangjie-runtime.dll` → 启动即失败；缺 OpenSSL 两个 → **编译期无警告**、运行时密码哈希/TLS 才 500 | 制品是 **exe + 4 个 DLL**，一个都不能少；`build.ps1` 会自动就位 |
| **端口占用** | 起不来 | `netstat -ano \| findstr :8080` |
| **客户端连不上** | 本机正常、外部不通 | 防火墙**与**云安全组是两层，都要放行 |
| **自签证书没 SAN** | 客户端报证书名称不匹配 | 重签证书，SAN 里写客户端实际使用的地址 |
| **cjenv 抢 `CANGJIE_HOME`** | 脚本挑了 1.0.5，编译中途 `LLVM ERROR: Broken module found` | 按版本挑 1.1.x（脚本会警告）；`-CangjieHome` 显式指定，见 §2.1 |
| **输出 exe 被占用** | `ld.lld: failed to write the output file: Permission denied` | 不是权限问题：`Get-Process club-server \| Stop-Process -Force` 后重编 |
| **机器上没装仓颉 SDK** | `找不到仓颉 SDK（cjc.exe）` | 装 SDK（§2.1），或直接用**部署包**（§4，免编译） |
| **启动脚本里中文乱码** | 双击后服务端中文日志是乱码 | 启动脚本已加 `chcp 65001 >nul`；2026-09-16 之前生成的包请重新 `build-package.ps1` |

---

## 附 · 本文的实测记录

| 项 | 值 |
| --- | --- |
| 实测时间 | 2026-09-16（本机） |
| 结论 | §2 五步 + §4 部署包 + §3 TLS 全部通过；服务端四套测试基线 单测 **398** / 冒烟 **362** / TLS **22** / 跨仓契约 **30** |
| 演示数据 | 本次实测在 `server\build\data` 留下演示库（会长 `13800000000` / 口令 `demo12345`）——正式用前删掉该目录重新 `init-admin` |
| 队友视角复现 | 全新 `git clone` + 清空 `CANGJIE_HOME`/cjenv 的 PATH 后 `build.ps1` 自动挑到 `D:\Cangjie` 1.1.3 并**编译通过**；部署包解压后 `cmd /c start-http.cmd` → `/health` **200**、`init-admin` → `data\db.json` **683 字节** |
| 未覆盖 | 公网部署（缺服务器信息）、真机/模拟器上的客户端联调（本机无设备） |
