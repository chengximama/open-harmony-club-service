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
# ① 编译器与 stdx（本机固定位置）
D:\Cangjie\bin\cjc.exe                                  # cjc 1.1.3
E:\cangjie\stdx\windows_x86_64_cjnative\static\stdx      # stdx 1.1.3.1

# ② 那个会让所有仓颉 exe 启动即崩的 Windows 更新必须不在
Get-CimInstance Win32_QuickFixEngineering | Where-Object HotFixID -eq 'KB5124010'
#    有输出 → 先卸载它（完整证据见 docs/API-NOTES.md §5）；本次实测结果是「已卸载 ✓」

# ③ PowerShell 5.1 默认禁止跑脚本：调用 .ps1 一律带 -ExecutionPolicy Bypass
```

> ⚠️ 第 ② 条**必须先过**：KB5124010 装着时服务端 exe 一启动就 `exit=-1073741819`（`0xC0000005`），
> 看着像代码崩了，其实与代码无关。本项目已经踩过两次（§5.1 / §5.5）。

---

## 2. 五步跑起来

### 2.1 编译

```powershell
cd E:\harmonyOS\cangjie_web\server
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

真实输出：

```
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
start-http.cmd   start-https.cmd   启动脚本 2（脚本内已 cd，双击即可）
README.txt       dll-versions.txt  说明 + **实际打包进去**的 DLL 版本与 sha256（便于追溯）
```

整个目录拷到目标机即可运行 —— **同平台（Windows x64），目标机不需要装编译器**。
拷过去之后按 `README.txt` 走：`club-server.exe init-admin …` → 双击 `start-https.cmd`。

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

---

## 附 · 本文的实测记录

| 项 | 值 |
| --- | --- |
| 实测时间 | 2026-09-16（本机） |
| 结论 | §2 五步 + §4 部署包 + §3 TLS 全部通过；服务端四套测试基线 单测 **398** / 冒烟 **362** / TLS **22** / 跨仓契约 **30** |
| 演示数据 | 本次实测在 `server\build\data` 留下演示库（会长 `13800000000` / 口令 `demo12345`）——正式用前删掉该目录重新 `init-admin` |
| 未覆盖 | 公网部署（缺服务器信息）、真机/模拟器上的客户端联调（本机无设备） |
