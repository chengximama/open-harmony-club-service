<p align="center">
  <img src="logo.svg" alt="QingZhou 轻舟" width="128" height="128">
</p>

# QingZhou (轻舟) — Koa 风格 Web 框架 for Cangjie

> 面向仓颉语言的轻量级、类型安全 Web 框架，采用可组合的洋葱式中间件模型。

**v0.4.0** · 仓颉 1.0.5 · stdx 1.0.5.1 · 109 单测 · 核心微秒级

---

## 特性

- **洋葱中间件** — 可组合的 `(Context, () -> Unit) -> Unit` 模型 + 框架级错误链
- **Trie 路由** — 静态段 / `:param` / `*` 通配 + method 分发 + 404/405 + Allow 头
- **请求体** — bodyBytes / JSON / 表单懒读取，InputStream 只消费一次
- **静态资源** — MIME 查表 + Range/206 + ETag/304 + Last-Modified + 内存缓存
- **中间件套件** — bodyParser / requestId / logger / timeout / CORS / cookies 全选项
- **安全** — 密码哈希（加盐迭代）+ 签名 cookie（HMAC-SHA256）+ 服务端 session
- **HTTPS/TLS** — `serveTls` / `listenTls` 一行启用 TLSv1.3，证书链 + 私钥 PEM 直传
- **进阶** — gzip 压缩 / multipart 上传 / 配置加载 / 优雅关闭 / 性能基准

## 快速上手（5 分钟）

```cangjie
let router = Router()
    .get("/", { ctx: Context, _: () -> Unit => ctx.status(200).body("hello") })
    .post("/users", { ctx: Context, _: () -> Unit => ctx.status(201).json("{\"ok\":true}") })

let app = QingZhouApp()
    .use(requestId())
    .use(logger())
    .use(bodyParser())
    .use(router.middleware())
    .onError(jsonErrorHandler())

app.listen(3000)
```

### 作为库使用（推荐）

QingZhou 也能「安装库 → import 使用」，不需要框架源码。

> **一键安装 `qz` 命令**（已独立成 CLI 工具仓库 [qingzhou-cli](https://gitcode.com/xuguowei/qingzhou-cli)）：
>
> ```bash
> # macOS / Linux / Git Bash
> curl -fsSL 'https://api.gitcode.com/api/v5/repos/xuguowei/qingzhou-cli/raw/install.sh?ref=main' | sh
> ```
>
> ```powershell
> # Windows PowerShell
> irm 'https://api.gitcode.com/api/v5/repos/xuguowei/qingzhou-cli/raw/install.ps1?ref=main' | iex
> ```
>
> 装好后任意目录可用全局 `qz`。

```bash
qz install                      # 1. 拉取框架并编译为库（等价 npm i）
qz run my-app.cj 3000           # 2. 编译并运行你的应用
```

```cangjie
// my-app.cj —— 只需 import qingzhou.*，其余由 qz 自动补齐
import qingzhou.*

main() {
    let router = Router()
        .get("/", { ctx: Context, _: () -> Unit =>
            ctx.status(200).header("content-type", "text/plain; charset=utf-8").body("hello") })
    let app = QingZhouApp().use(router.middleware())
    app.listen(3000)
}
```

`qz` 自动处理 `--import-path` / `-L` / `-l` 与 stdx 依赖。示例见 `examples/lib_hello.cj`。若在框架仓库内开发，用 `./build.sh` 源码直编。

### 源码构建（框架开发者）

若需要构建框架本体 / 跑单测 / 启动演示服务，用 `build.sh` 源码直编（Linux / macOS / Windows Git Bash，详见 `build.cmd.txt`；cjpm 在本机不稳定，走 cjc 直编）：

```bash
./build.sh build          # 编译主程序
./build.sh test           # 编译并运行 109 项单测
./build.sh serve 3000     # 启动演示服务
curl http://127.0.0.1:3000/
```

`build.sh` 自动探测平台与 stdx 路径；Windows 下编译前需先杀旧进程（老 exe 锁文件导致 lld Permission denied）。

## 目录结构

```
qingzhou/
├── src/                 # 框架源码（25 个 .cj，单包）
│   ├── compose.cj       # 洋葱调度 + 错误链
│   ├── context.cj       # Context：请求代理 + 响应缓冲
│   ├── app.cj           # QingZhouApp + 优雅关闭（ServerHandle）
│   ├── router.cj        # Trie 路由
│   ├── cookies.cj       # Cookie 读写 + RFC 6265 选项
│   ├── static.cj        # 静态资源（Range/ETag/Last-Modified/缓存）
│   ├── mime.cj          # MIME 查表
│   ├── range.cj         # Range 解析（单段 + 多段 multipart）
│   ├── etag.cj          # ETag 生成/匹配 + HTTP date
│   ├── bodyparser.cj    # bodyParser 中间件
│   ├── requestid.cj     # requestId 中间件
│   ├── logger.cj        # logger 中间件
│   ├── cors.cj          # CORS 中间件
│   ├── timeout.cj       # timeout 中间件
│   ├── compress.cj      # gzip 压缩中间件
│   ├── multipart.cj     # multipart/form-data 解析
│   ├── config.cj        # 配置容器 + key=value 加载
│   ├── jsonx.cj         # JSON 序列化 + 安全访问器
│   ├── security.cj      # 密码哈希 + 签名 cookie
│   ├── session.cj       # 服务端 session
│   ├── util.cj          # 内置解析器
│   ├── middleware.cj    # jsonErrorHandler + respond 助手
│   ├── unit_tests.cj    # std.unittest 场景
│   └── manual_runner.cj # 手动断言 runner（cjc 直编入口）
├── examples/            # 6 个独立示例（hello/REST API/静态站/中间件/博客/HTTPS）
├── public/              # 静态资源 demo（PNG/SVG/CSS/JS/250KB bin）
├── public_blog/         # 博客示例前端静态资源
├── docs/                # 7 份文档（见下表）
├── build.sh             # 跨平台构建脚本（build/test/serve/examples/clean）
├── build.cmd.txt        # Windows 下已验证的 cjc 编译命令 + curl 验证手册
├── deploy.sh            # 部署脚本（启停 / 健康检查 / 优雅关闭）
├── benchmark.cj         # 性能压测（微基准 + 端到端吞吐）
├── blog.env             # 博客示例环境配置
├── cjpm.toml            # 备用（Windows cjpm 不稳定，见文件内说明）
├── CHANGELOG.md         # 版本变更记录
├── LICENSE              # MIT 许可证
└── README.md
```

## 文档

| 文档 | 说明 |
|------|------|
| [API.md](docs/API.md) | 全量 API 参考（签名 / 默认值 / 示例） |
| [CAVEATS.md](docs/CAVEATS.md) | 仓颉语言坑 + stdx API 反直觉点 |
| [GAPS.md](docs/GAPS.md) | 框架能力缺口与解决记录 |
| [PACKAGING.md](docs/PACKAGING.md) | 包拆分与发布方案 |
| [BENCHMARK.md](docs/BENCHMARK.md) | 性能基准（微基准 + 端到端吞吐） |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | 部署指南（启停 / 健康检查 / 优雅关闭） |
| [CODE_STYLE.md](docs/CODE_STYLE.md) | 编码规范与仓颉注释避坑 |

## 示例

[examples/](examples/README.md) 六个独立可跑示例：

- `hello.cj` — 最小应用
- `rest_api.cj` — 内存 todo CRUD（bodyParser / requestId / 分页）
- `static_site.cj` — 静态站 + Range/ETag/CORS
- `middlewares.cj` — 中间件组合（reflect CORS / JSON 日志 / 超时）
- `blog.cj` — 完整博客（用户系统 + 文章 CRUD + 鉴权 + 静态前端）
- `https.cj` — HTTPS 服务（`serveTls` / TLSv1.3 / 自签证书）

## 测试

```text
$ build\qingzhou.exe test
...
All 109 unit-test scenarios PASSED
```

`src/unit_tests.cj`（`std.unittest` 的 `@Test`/`@Expect`）与 `src/manual_runner.cj`（手动断言）
维护同一份场景，cjc 直编跑手动版，无需依赖 `cjpm test`。

## 已知边界

详见 [docs/CAVEATS.md](docs/CAVEATS.md)，关键几条：

- **仓颉块注释支持嵌套** — 注释里写 `/*`（如 `text/*`）会开新嵌套吞掉后续代码，**铁律：块注释里绝不写 `/*` 字面量**
- **stdx `ResponseBuilder` 是不可变链** — `b.body(bytes)` 不接返回值则 body 改动丢失（content-length: 0）
- **仓颉 1.0.5 std 无环境变量 API、无 Windows OS 信号** — 配置从文件读，优雅关闭走 HTTP 端点
- **Windows 下编译前需先杀旧进程** — 老 exe 锁文件导致 lld Permission denied

## 编码规范

注释风格与仓颉注释避坑见 [docs/CODE_STYLE.md](docs/CODE_STYLE.md)。

## License

[MIT](LICENSE) © 2026 guowei, BIT Foundational Software And Systems Lab
