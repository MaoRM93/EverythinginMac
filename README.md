<p align="center">
  <img src="assets/copyright-banner.svg" alt="版权所有 © 2024–2026 武见（joshua-wu），MIT License；本仓库为个人非商业性质的修改版本，修改部分 © 2026 MaoRM93" width="100%" />
</p>

> **版权归属**：本项目原始代码与设计版权归原作者 **武见（joshua-wu）** 所有，遵循 [MIT 许可证](LICENSE)。本仓库是基于原项目的个人非商业性质修改版本，修改部分版权归 **MaoRM93** 所有，同样以 MIT 许可证公开。本版本不代表原作者，也与原作者无隶属关系，属于独立的分支。非常感谢原作者的贡献！！

**更新提示**：从167版本之前的版本升级到167及之后的版本，需要使用卸载脚本彻底清理掉旧版本的安装和授权信息，否则会因为权限冲突无法打开！！**

<p align="center">
  <img src="MacEverything/Assets.xcassets/AppIcon.appiconset/icon_256.png" alt="MacEverything" width="128" />
</p>

<h1 align="center">MacEverything</h1>

<p align="center">
  <b>macOS 极速文件搜索工具</b> — 在数百万文件中毫秒级定位任意文件。<br/>
  灵感源自 Windows 上的 <a href="https://www.voidtools.com/">Everything</a>，Mac 上无出其右。
</p>

<p align="center">
  <b>中文</b> | <a href="README_EN.md">English</a>
</p>

<p align="center">
  <a href="#安装"><img src="https://img.shields.io/badge/macOS-13%2B-blue?logo=apple" alt="macOS 13+" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License" /></a>
  <a href="#测试体系"><img src="https://img.shields.io/badge/tests-79%20modules-brightgreen" alt="79 test modules" /></a>
  <a href="#ai-工具集成-mcp"><img src="https://img.shields.io/badge/MCP-compatible-blueviolet" alt="MCP Compatible" /></a>
</p>

---

## 本分支版本更新内容（10x.x.x.xxx 版本）
<img width="1600" height="1200" alt="image" src="https://github.com/user-attachments/assets/05d7d188-22e8-4a10-bb03-cbe64e79e077" />



本仓库基于 [joshua-wu/MacEverything](https://github.com/joshua-wu/MacEverything) 修改，版本 **101.0.0.110**。相对原项目的主要变更：

### 界面与交互

- **全新首页**：隐藏标题栏，自上而下为标题、搜索框、权限提示、结果列表、底部状态栏
- **首次启动引导页**：先说明建立索引的必要性与数据安全性（全程本地、不上传），用户确认后才请求“完全磁盘访问权限”，不再一启动就连环弹窗
- **权限流程简化**：欢迎页仅保留一个“请求权限”按钮，点击后打开系统设置并直接进入主页
- **全局快捷键 `⌘↑F`**：唤起即聚焦搜索框，旧版默认 `⌥Space` 会自动迁移，用户自定义的快捷键保持不变
- **全量汉化**：主菜单、状态栏菜单、右键菜单、快捷键设置、内容设置、搜索语法帮助、权限提示全部中文化

### 输入与索引

- **修复索引期间输入法不可用**：首次建索引与 FSEvents 增量同步时，中文输入法不再闪烁或被中断，可正常候选上屏
- **底栏状态提示**：索引或同步进行时，底栏显示“正在更新数据，搜索结果可能不全或有延迟”，不再用弹窗或大面积进度条打扰输入
- **增量索引** ：修复开机再次索引的问题

## 功能亮点

### 极速搜索

索引整块磁盘 **500 万+ 文件只需 14 秒**，之后每次搜索 **不到 5ms** 返回结果。比 Spotlight 快两个数量级。

| 对比项 | MacEverything | Spotlight | `find` |
|--------|:---:|:---:|:---:|
| 索引 500 万文件 | ~14 秒 | 数分钟以上 | 无索引 |
| 搜索延迟 | **< 5ms** | 200ms–2s | 5–30s |
| 实时文件监控 | FSEvents | FSEvents | 无 |
| 内容搜索 | Trigram 索引 | 侧重元数据 | `grep` |
| AI 工具集成 | 内置 MCP | 不支持 | 不支持 |

### 随叫随到

按 **`⌘⇧F`** 随时唤出搜索窗口（快捷键可自定义），搜索栏自动获得焦点 — 唤起即输入，搜完即走。支持开机自启（最小化后台运行），不打扰你的工作流。

### 智能输入体验

- **Ghost 文本自动补全** — 输入时自动显示半透明建议文字，来自搜索历史（按频率排序）或系统关键词（如输入 `ex` 提示 `ext:`）。按 **Tab** 一键接受
- **搜索栏语法高亮** — 实时彩色标注：过滤器名紫色、参数蓝色、引号字符串橙色、运算符红色
- **搜索选项徽章** — 搜索栏旁的彩色徽章，一键切换 Regex / Case Sensitive / Whole Word / Match Filename

### Everything 风格查询语法

完整的 AST 解析器，支持 15+ 过滤器、布尔运算、glob 通配符、正则表达式。内置语法帮助窗口（**Cmd+?**）。

| 查询 | 说明 |
|------|------|
| `readme` | 文件名包含 "readme" |
| `*.swift` | 所有 Swift 源文件 |
| `ext:py size:>1mb` | 大于 1MB 的 Python 文件 |
| `dm:today` | 今天修改过的文件 |
| `config path:/usr` | `/usr` 下包含 "config" 的文件 |
| `"exact phrase"` | 精确短语匹配 |
| `foo OR bar` | 布尔 OR 运算 |
| `case:Makefile` | 区分大小写搜索 |
| `regex:^test_.*\.py$` | 正则表达式搜索 |
| `type:folder node_modules` | 仅搜索目录 |
| `~/Documents/*.pdf` | Tilde 展开 + glob |
| `infile:TODO ext:cpp` | C++ 文件中搜索 "TODO" |

<details>
<summary><b>全部过滤器列表</b></summary>

| 过滤器 | 说明 | 示例 |
|--------|------|------|
| `ext:` | 文件扩展名 | `ext:swift,h` |
| `size:` | 文件大小 | `size:>1mb`, `size:100kb-5mb` |
| `type:` | 文件/目录 | `type:folder` |
| `path:` | 路径包含 | `path:Downloads` |
| `nopath:` | 路径排除 | `nopath:node_modules` |
| `parent:` | 直接父目录 | `parent:src` |
| `depth:` | 目录深度 | `depth:<3` |
| `dm:` | 修改日期 | `dm:today`, `dm:>2024-01-01` |
| `dc:` | 创建日期 | `dc:thisweek` |
| `da:` | 访问日期 | `da:last7days` |
| `len:` | 文件名长度 | `len:>50` |
| `case:` | 区分大小写 | `case:README` |
| `regex:` | 正则表达式 | `regex:^test_` |
| `ww:` | 全词匹配 | `ww:test` |
| `wfn:` | 全文件名匹配 | `wfn:Makefile` |
| `content:` / `infile:` | 内容搜索 | `infile:TODO` |
| `audio:` `video:` `pic:` `doc:` `zip:` | 文件类型宏 | `audio:` = 所有音频文件 |

</details>

### 全文内容搜索

输入 `infile:关键词` 搜索文件内容，结果附带关键词高亮上下文片段。基于 Trigram 索引加速，仅重新索引变更文件。可在「内容设置」中配置索引的文件类型和最大文件大小。

### 实时同步，永不过时

- **文件监控** — 基于 FSEvents 实时监听文件系统变更，新建、重命名、删除的文件立即出现在搜索结果中
- **两阶段即时启动** — 启动时先加载磁盘缓存（立即可搜），后台通过 FSEvents 增量追赶变更，搜索零等待
- **焦点感知省电** — 窗口不在前台时暂停刷新，回到前台时批量追赶，几乎零后台 CPU 占用

### 交互细节

- **智能高亮** — 搜索结果中匹配部分高亮标记，基于 AST 感知：正确处理 glob 通配符、正则、大小写、NOT 排除等复杂场景
- **拖放** — 直接从搜索结果拖放文件到 Finder、VS Code、Xcode 等任意应用
- **右键菜单** — 打开 / 在 Finder 中显示 / 复制路径
- **Cmd+Click** — 快速在 Finder 中定位文件
- **最近文件** — 搜索栏为空时自动展示最近修改的文件

### AI 工具集成 (MCP)

内置 [Model Context Protocol](https://modelcontextprotocol.io/) 服务器，让 AI 编程工具即时搜索你的文件系统。在菜单栏一键开启，支持 **Claude Code**、**Cursor**、**Claude Desktop**。

```
Claude Code / Cursor / Claude Desktop
       │
       ▼  (stdio JSON-RPC 2.0)
  MacEverythingMCP
       │
       ▼  (HTTP localhost:19860)
  MacEverything.app
```

| 工具 | 说明 |
|------|------|
| `search_files` | 文件名搜索（Trigram 加速） |
| `search_content` | 全文内容搜索 |
| `recent_files` | 最近修改的文件 |
| `index_status` | 索引统计与健康状态 |

### HTTP API

本地 REST API 监听 `localhost:19860`，方便脚本调用和自动化：

```bash
curl "http://localhost:19860/api/search?q=readme&limit=10"       # 搜索文件
curl "http://localhost:19860/api/search/content?q=TODO"           # 内容搜索
curl "http://localhost:19860/api/recent?limit=20"                 # 最近文件
curl "http://localhost:19860/api/status"                          # 索引状态
```

### 安装

#### 下载 DMG（推荐）

1. 从 [Releases](../../releases) 下载 `MacEverything.dmg`
2. 将 `MacEverything.app` 拖入「应用程序」文件夹
3. 启动后按提示授予 **完全磁盘访问权限**
4. 等待初始扫描完成（约 14 秒）
5. 按 `⌘⇧F` 开始搜索

#### 从源码构建

**环境要求：** macOS 13+，Xcode 15+

```bash
git clone https://github.com/user/MacEverything.git && cd MacEverything

xcodebuild -project MacEverything.xcodeproj -scheme MacEverything \
  -configuration Release build SYMROOT=build

hdiutil create -volname MacEverything \
  -srcfolder build/Release/MacEverything.app \
  -ov -format UDZO MacEverything.dmg
```

#### CLI 守护进程

无头模式，适用于服务器或自动化环境：

```bash
make daemon
./maceverything-daemon --port 19860 --root /
```

---

<h2 align="center">开发者篇：技术深度</h2>

<p align="center">
  以下内容面向对实现细节感兴趣的开发者。
</p>

### 架构总览

```
┌─────────────────────────────────────┐
│       SwiftUI 应用层                │  界面 · ViewModel · MVVM
├─────────────────────────────────────┤
│    Objective-C++ 桥接层             │  零开销互操作
├─────────────────────────────────────┤
│       C++20 核心引擎                │  扫盘 · 索引 · 搜索 · 持久化
└─────────────────────────────────────┘
```

同一套 C++20 核心引擎驱动三种部署模式：

| 模式 | 说明 |
|------|------|
| **GUI 应用** | SwiftUI 菜单栏应用，`⌘⇧F` 全局快捷键 |
| **CLI 守护进程** | 无头 `maceverything-daemon` — 相同引擎，无 UI |
| **MCP 服务器** | `MacEverythingMCP` — stdio JSON-RPC 代理，供 AI 工具调用 |

### 核心引擎

| 组件 | 关键设计 |
|------|---------|
| **DirectoryScanner** | 多线程工作窃取 + `getattrlistbulk` 单次系统调用批量获取文件属性，4–32 线程自适应 |
| **SearchEngine** | Trigram 倒排索引（name + path 双索引）+ 竞争选择最优候选集 + SoA 列式过滤 |
| **ContentIndex** | Trigram 全文倒排索引，FNV-1a 哈希增量更新，仅重新索引变更文件 |
| **SIMDSearch** | ARM NEON 128-bit first-last byte 向量化匹配 + 2x 循环展开，单线程 11.5 GB/s |
| **IndexPersistence** | WAL + CRC32 + 分页脏页刷写 + 原子 rename，COW 无阻塞压缩（锁持有 < 100ms） |
| **FileSystemWatcher** | FSEvents + eventId 增量回放 + 日志截断检测自动子树重扫 |
| **PathTable** | 路径字符串 intern 化 — 目录路径仅存 `uint32` 索引，百万文件节省 ~550MB |
| **QueryParser** | 完整 AST 管线：Tokenizer → FilterParser → Parser → QueryAST，30+ 过滤器关键词 |

### 基准测试

测试环境：macOS Darwin 24.3.0，**540 万索引文件**，48 种查询类型：

#### 搜索延迟

| 查询类型 | 平均延迟 | 示例 |
|----------|:---------:|------|
| 长关键词 (7+ 字符) | **0.1–1ms** | `screenshot` 0.1ms, `dockerfile` 0.1ms |
| 中等关键词 (4–6 字符) | **1–5ms** | `readme` 1.2ms, `config` 4.7ms |
| Glob 模式 | **0.7–18ms** | `*.cpp` 0.7ms, `*.swift` 1.5ms |
| 路径查询 | **3–32ms** | `package.json` 2.9ms |
| 全部 48 种查询 (均值) | **10.5ms** | SoA 优化后最新结果 |

#### Trigram vs 线性扫描

| 查询 | Trigram | 线性扫描 | 加速比 |
|------|:------:|:------:|:------:|
| `node_modules` | 0.5ms | 154ms | **308x** |
| `application` | 2.1ms | 175ms | **83x** |
| `readme` | 1.2ms | 49ms | **41x** |

#### SIMD 字符串搜索 (Apple M3 Pro)

| 方法 | 吞吐量 | 对比 `std::string::find` |
|------|:------:|:------------------------:|
| `std::string::find` | 1.2 GB/s | 基准线 |
| **NEON 128-bit（单线程）** | **11.5 GB/s** | **9.5x** |
| **NEON 128-bit（12 线程）** | **74.3 GB/s** | **60.7x** |

### 关键技术

| 技术 | 效果 |
|------|------|
| `getattrlistbulk` | 单次系统调用批量获取文件属性 — 避免逐文件 `stat` |
| Trigram 倒排索引 | 亚线性搜索：比线性扫描快 33x–308x |
| SoA 列式布局 | 缓存友好的内存访问模式，纯过滤查询 SIMD 批量判断 16 条记录 |
| `__builtin_prefetch` | 预取距离 8，隐藏候选验证阶段的随机内存访问延迟 |
| ARM NEON SIMD | 128-bit 向量化字符串匹配，2x 循环展开，逼近内存带宽上限 |
| GCD 并行扫描 | Trigram 无法加速时启用多核线性扫描 |
| StringPool 连续内存 | 文件名紧凑排列在单一 `char` 缓冲区，SIMD 友好 |
| PathTable intern 化 | 目录路径仅存 `uint32` 索引 — 百万文件节省 ~550MB |
| Generation 计数器 | 每 1024 次迭代检查，快速输入时零开销取消过时查询 |
| APFS Firmlink 去重 | inode + devid 检测，正确处理 macOS Data/System 卷合并环路 |
| Regex Trigram 预过滤 | 从正则中提取字面量生成 trigram 候选，~7s → <100ms |
| 自适应 Trigram 旁路 | 候选集过大时自动回退并行扫描，避免无效索引查找 |
| COW 无阻塞压缩 | 写时复制，压缩期间独占锁持有 < 100ms（原 30–60s） |
| 分页增量持久化 | 仅写入脏页，典型 flush I/O 从 ~112MB 降至 KB 级 |

### 测试体系

79 个测试模块覆盖完整技术栈，支持 AddressSanitizer 和 ThreadSanitizer：

```bash
make test          # 快速单元测试 + 桥接层 lint
make test-slow     # 集成测试（全盘扫描、FSEvents、端到端）
make test-all      # 全部测试
make test-asan     # AddressSanitizer
make test-tsan     # ThreadSanitizer
```

覆盖范围：
- **核心引擎**：扫描、查询、变更、压缩、排序、路径搜索
- **持久化**：WAL CRC 完整性、批量回放、竞态条件、分页持久化 v5
- **内容索引**：Trigram、压缩、修改时间跟踪、WAL 跟踪
- **搜索/查询**：分词器、解析器、过滤器、日期过滤、结构化查询、正则 Trigram、高亮提示
- **性能**：SIMD 搜索、千万条记录合成基准、Trigram 竞争测试
- **集成**：线程安全、端到端、HTTP 引擎热替换、MCP 协议
- **内存安全**：ASan + TSan 构建

### 项目结构

```
MacEverything/
├── Core/                  # C++20 核心引擎
│   ├── SearchEngine       # Trigram 索引 + 并行查询（5 个 .cpp 文件）
│   ├── DirectoryScanner   # 多线程批量扫描器
│   ├── ContentIndex       # 全文倒排索引
│   ├── IndexPersistence   # WAL + 分页持久化
│   ├── FileSystemWatcher  # FSEvents 实时监控
│   ├── HttpServer         # 内嵌 REST API 服务器
│   ├── SIMDSearch         # ARM NEON 向量化搜索
│   ├── QueryAST/Parser    # 完整查询语言管线
│   ├── PathTable          # 字符串 intern 表
│   └── ServiceEngine      # 生命周期编排
├── Bridge/                # Objective-C++ 桥接层
│   └── MacSearchBridge    # C++ ↔ Swift 零开销互操作
├── App/                   # SwiftUI 应用层
│   ├── ContentView        # 主搜索界面
│   ├── SearchViewModel    # MVVM + 分级防抖
│   ├── HotkeyManager      # 全局快捷键注册
│   └── MCPConfigManager   # MCP 一键配置
├── CLI/                   # 命令行工具
│   ├── daemon_main        # 无头守护进程
│   └── mcp_main           # MCP 服务器（stdio JSON-RPC）
└── tests/                 # 79 个测试模块
```

## 参与贡献

欢迎贡献代码！请遵循以下流程：

1. Fork 本仓库
2. 创建功能分支 (`feat/...`) 或修复分支 (`fix/...`)
3. 为新功能编写测试
4. 确保 `make test-all` 通过
5. 提交 Pull Request

## 许可证

本项目基于 MIT 许可证开源 — 详见 [LICENSE](LICENSE) 文件。

---

<p align="center">
  <b>如果 MacEverything 让你找文件更快了，请给一颗 Star 支持！</b>
</p>
