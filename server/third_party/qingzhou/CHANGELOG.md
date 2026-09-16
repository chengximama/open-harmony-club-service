# Changelog

本文件记录 QingZhou（轻舟）各版本的功能变化。格式参考 Keep a Changelog，
版本号遵循语义化版本（SemVer）。

## [0.4.0] — 2026-09-10

库分发：从「源码分发」升级为「库分发」，对齐 Koa 的开发体验。

### 新增
- **库编译**：框架 22 个源文件可编译为 `qingzhou.cjo`（编译期）+ `libqingzhou.a`
  （链接期）——这正是 stdx 的发布方式，无需 cjpm build
- **`qz` 构建工具**：`qz lib`（编译框架库）/ `qz build app.cj` / `qz run app.cj`，
  自动补齐 `--import-path` / `-L` / `-l` 与 stdx 依赖
- **`examples/lib_hello.cj`**：`import qingzhou.*` 的最小库用法示例

### 变更
- 用户项目从「框架源码一起编译」改为「`import qingzhou.*` + 链接库」

## [0.3.0] — 2026-09-10

生产化加固：从「功能完整」走向「生产可用」。

### 新增
- **静态资源内存缓存**（`static.cj`）：`StaticCache` + `StaticOptions.enableCache`，
 文件字节读一次后跨请求复用（热资源命中后 0ms），ETag/Range/304 逻辑不变
- **优雅关闭**（`app.cj`）：`QingZhouApp.serve(port)` 非阻塞启动返回
 `ServerHandle`，`shutdown()` 停止接新连接 + 排空在途请求，`wait()` 阻塞等待；
 原有 `listen(port)` 保持阻塞语义（等价 `serve().wait()`）
- **配置加载**（`config.cj`）：`Config` 键值容器 + 类型访问器
 （`get/getOr/getInt/getIntOr/getBool/getBoolOr/getFloat`）+
 `loadConfigFile`（key=value 文件，.env 风格）+ `parseConfigText`

### 变更
- `listen()` 内部重构为 `serve().wait()`，行为向后兼容

### 已知边界
- 环境变量 API：Cangjie 1.0.5 std 无 `getEnv/envVars`（`std.env` 仅进程控制），
 配置暂只能从文件/参数加载，需环境变量可走 CFFI
- OS 信号：`std.runtime.Signal` 不支持 Windows，优雅关闭在 Windows 上需程序化
 触发（管理端点 / 第二线程），POSIX 可接 SIGINT

## [0.2.0] — 2026-09-10

基于实战 demo（轻舟博客）暴露的缺口，补齐类型安全与生产化能力。

### 新增
- **JSON 工具层**（`jsonx.cj`）：`JsonBuilder` 序列化 + 安全访问器
 `jsonGetStr/jsonGetInt64/...` + `bodyStr/bodyStrOr` body 读取
- **结构化 state**：`ctx.state` 从 String 改为 `HashMap<String,String>` +
 `setState/getState/getStateOr`
- **安全原语**（`security.cj`）：`hashPassword/verifyPassword`（加盐迭代哈希）
 + `signValue/verifySigned`（HMAC-SHA256 签名）+ `randomHex`
- **服务端 session**（`session.cj`）：`SessionStore` + `session` 中间件
- **query 解析**：`ctx.query/queryParam/queryParamOr/queryParams`
- **内置解析器**（`util.cj`）：`parseInt64OrNone/parseUInt16OrNone/...`
- **多 Range**（`range.cj`）：`parseRanges` + multipart/byteranges 响应
- **gzip 压缩**（`compress.cj`）：`gzipCompress` + `compress` 中间件
- **multipart 上传**（`multipart.cj`）：手写 boundary 解析 + `multipart` 中间件
- **Last-Modified**（`etag.cj`）：`fileLastModified` + `formatHttpDate` +
 If-Modified-Since → 304

### 文档
- `docs/GAPS.md`：缺口清单（P0/P1/P2 + 功能缺口全部解决）
- `docs/CAVEATS.md`：15 条仓颉语言坑
- `docs/PACKAGING.md`：qingzhou + qingzhou-middlewares 两包拆分方案

### 测试
- 单测 63 → **107**（+44），端到端回归全绿

## [0.1.0] — 2026-09-10

首个完整版本。Koa 风格的仓颉 Web 框架，功能全部完成。

### 技术验证
- 洋葱模型中间件调度（`Dispatcher` + `compose`）
- stdx.net.http 集成：`CatchAllDistributor` 接管全部分发
- `QingZhouApp.use()` / `listen()` 最小应用闭环

### 内核
- `Context` 响应缓冲（status / body / header / json 链式 API）
- 错误通道：业务链异常 → `onError` 链 → 兜底 500
- `commit()` 幂等写出；std.unittest 测试基建

### 路由
- Trie 路由：静态段 / `:param` / `*` 通配
- GET/POST/PUT/DELETE/PATCH/ALL 方法分发
- 404（JSON body）与 405（+ `Allow` 头）自动响应
- 路由以中间件形态挂载（`router.middleware()`）

### 请求体 / JSON / Cookie
- 惰性 body 读取 + 缓存（InputStream 只消费一次）
- `bodyBytes()` / `body()` / `bodyJson()` / `bodyJsonError()` / `bodyForm()`
- URL-decode（手写，多字节 UTF-8 安全）
- `contentType()` 参数剥离；基础 Cookie get/set

### 静态资源
- `serve` / `serveAt` / `serveWithOpts` 静态中间件
- MIME 查表（40+ 扩展名），二进制 body 响应通路
- 路径穿越防护（403）；目录 index.html；前缀段匹配

### 视频 / 缓存友好
- Range（RFC 7233）：`bytes=start-end` / `start-` / `-N` 后缀
- 206 Partial Content + Content-Range；416 + `bytes */size`
- 多区间 / 不可解析 Range 按规范忽略（回退 200）
- ETag（RFC 7232）：size 指纹强校验器；If-None-Match → 304（含 `*` 与 `W/` 弱前缀）
- HEAD 头-only 响应；`Accept-Ranges: bytes` 全响应携带

### 中间件套件
- `bodyParser`：JSON/form/text 预解析，400 坏 JSON（短路，不进 handler）、
 413 超限（默认 1 MiB）、未知 Content-Type 透传
- `cookies`：完整 RFC 6265 `CookieOptions`
 （maxAge/expires/path/domain/secure/httpOnly/sameSite）
- `cors`：预检 OPTIONS 204 短路；origin 支持 `*` / `reflect` / 固定域；
 credentials 守护
- `logger`：access log（MonoTime 计时），可定制 formatter/writer
- `requestId`：入站头透传 / 16 字节 hex 生成；响应头回写
- `timeout`：软超时（408 覆盖 或 `X-Timeout-Ms` 标注）

### 文档与发布
- `docs/API.md`：全量 API 参考（8 章 + 已知边界）
- `examples/`：hello / rest_api / static_site / middlewares 四个独立示例
 （全部编译 + 端到端验证）
- `cjpm.toml`（备用，含 Windows cjpm 不稳定说明）；README 快速上手
- 测试总计：63 单测场景 + 11 静态端到端 + 10 中间件端到端 + 示例端到端全绿

### 已知边界
- 无 Last-Modified / If-Modified-Since（std.fs 无 mtime、std.time 无 UTC 工厂）
- ETag 仅 size 指纹（单目录内碰撞可忽略）
- timeout 为软超时（std 无线程调度器，无法硬中断）
- 同名响应头覆盖语义（stdx ResponseBuilder 限制；多 Set-Cookie 内部合并）

## [Unreleased]

### 计划
- compress（gzip）中间件（待 stdx 压缩库探测）
- multipart/form-data 解析
- qingzhou / qingzhou-middlewares 包拆分，争取上架仓颉包管理生态
- Last-Modified（若后续工具链暴露 mtime / UTC 能力）
- 结构化日志 + 日志文件 sink
