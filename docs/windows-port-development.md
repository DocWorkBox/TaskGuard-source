# Codex TaskGuard Windows 端开发文档

本文档用于指导 `Codex TaskGuard` 的 Windows 端实现。当前仓库里的 macOS 版本是 SwiftPM + SwiftUI/AppKit 实现，Windows 端不应尝试直接移植 UI 或系统调用，而应复用产品概念、数据模型和风险规则，重新实现 Windows 平台适配层。

## 目标

Windows 端目标和 macOS 端保持一致：

- 提供托盘常驻入口，打开后展示类似菜单栏 Popover 的快速面板。
- 提供完整主窗口，按服务组、Codex 线程、开发服务、疑似残留、监听端口、白名单分组查看。
- 扫描当前用户相关进程，识别 Codex Desktop 支撑进程、插件 MCP、开发服务和疑似残留进程。
- 展示每组和每个进程的 PID、父进程、命令行、CPU、内存、监听端口、运行时长和关闭建议。
- 默认不提权、不跨用户杀进程；先走温和关闭，再人工确认强制关闭。
- 常驻资源占用接近 macOS 端优化后的策略：启动快、扫描慢一点没问题，但不能长时间高 CPU。

## 推荐技术路线

推荐采用：

```text
Tauri v2 + Rust 后端 + React/Vue/Svelte 前端
```

原因：

- UI 可高度复刻现有 macOS 面板和主窗口，前端布局效率高。
- Rust 后端适合调用 Win32 API，常驻开销明显低于 Electron。
- Tauri v2 官方支持系统托盘，适合 TaskGuard 这种常驻工具形态。
- 后续如果要做 Linux 端，可继续复用前端和一部分 Rust 规则层。

备选方案：

```text
WinUI 3 + C#/.NET
```

适合只做 Windows 原生体验的版本。WinUI 3 是 Windows App SDK 下的现代 Windows 桌面 UI 框架，但复刻现有 macOS UI 和后续跨平台复用的效率不如 Tauri。

不推荐 Electron 作为首选。Electron 能实现相同功能，但常驻内存和后台资源占用通常会高于 Tauri/Rust，不符合 TaskGuard 的低占用目标。

## 官方文档参考

- Tauri v2 System Tray：<https://v2.tauri.app/learn/system-tray/>
- Windows App SDK / WinUI：<https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/>
- Win32_Process WMI class：<https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-process>
- GetExtendedTcpTable：<https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-getextendedtcptable>

## 总体架构

建议拆成三层：

```text
taskguard-windows/
  src/                         # 前端 UI
  src-tauri/
    src/
      main.rs                  # Tauri 启动、托盘、窗口管理
      scanner/
        mod.rs
        process.rs             # Windows 进程采集
        tcp.rs                 # 监听端口采集
        usage.rs               # CPU/内存采样
      classifier/
        mod.rs                 # Codex/开发服务/白名单分类规则
      terminator/
        mod.rs                 # 温和关闭与强制关闭
      model/
        mod.rs                 # Snapshot/ServiceGroup/ManagedProcess
      settings/
        mod.rs                 # 扫描间隔、白名单、端口范围
```

逻辑分层：

- `UI layer`：托盘面板、主窗口、设置窗口。
- `platform adapter`：Windows 进程、端口、CPU、内存、关闭动作。
- `core rules`：服务分组、风险评分、关闭建议、白名单。

macOS 端 Swift core 不直接复用代码，但要复用以下概念：

- `ManagedProcess`
- `ServiceGroup`
- `ProcessSnapshot`
- `ServiceOwnership`
- `ServiceRisk`
- `KillPlan`
- `ScanConfiguration`

## UI 设计要求

### 托盘入口

Windows 托盘只显示盾牌图标。

托盘图标状态：

- 绿色点：无建议清理项。
- 橙色点：存在建议清理项或需确认项。

点击托盘图标打开快速面板。面板结构复刻 macOS 菜单栏 UI：

- 顶部：图标、`Codex TaskGuard`、最近扫描状态；右侧独立显示当前快照的总 CPU/内存。
- 指标卡：服务、建议、端口、高 CPU。
- 告警行：疑似残留、高 CPU、长运行、暂停扫描。
- 操作区：打开详情、刷新、暂停扫描、清理建议项。
- 最近服务组：每组显示标题、进程数；行右侧独立显示该组 CPU/内存，再显示风险标签。
- 底部：打开、设置、退出。

资源占用显示位置必须和新版 macOS 端保持一致：

- 快速面板标题栏右侧显示总 CPU/内存，占用数据来自当前快照所有进程汇总。
- 快速面板最近服务组列表中，每个服务组行右侧显示该组 CPU/内存。
- 主窗口中间服务组列表中，每个服务组行右侧显示该组 CPU/内存，位置在风险标签之前。
- 主窗口右侧详情的进程树中，每个进程行右侧独立显示该进程 CPU/内存。
- 右侧详情顶部的 CPU/内存统计继续显示当前选中服务组的汇总值。

### 主窗口

主窗口保持三栏结构：

- 左侧：分类导航。
- 中间：服务组列表。
- 右侧：详情、关闭建议、关联依据、进程树。

底部状态栏：

- 左侧显示版本号，例如 `V1.0.0`。
- 中间显示扫描状态。
- 右侧显示服务、建议、端口计数。

### 设置窗口

设置项至少包含：

- 自动扫描间隔。
- 开发端口范围。
- 开发命令关键字。
- 白名单规则。
- 是否显示 Codex 内部支撑进程。
- 关闭等待时间。

## Windows 进程采集方案

Windows 端不要照搬 macOS 的 `ps/lsof/cwd` 思路。推荐组合如下。

### 进程基础信息

采集字段：

- PID
- PPID
- 用户
- 状态
- 运行时长
- CPU
- 内存
- 可执行路径
- 命令行

可选实现：

- Win32 API：用于低成本枚举 PID、进程句柄、内存。
- WMI `Win32_Process`：用于 `CommandLine`、`ParentProcessId`、`ExecutablePath`。

注意：WMI 查询相对重，不能每轮对所有 PID 无脑全量查询。应当缓存并设置冷却。

### 命令行

命令行是 Windows 端归因的核心字段。优先用 WMI `Win32_Process.CommandLine`。

用途：

- 判断是否是 Codex Desktop 支撑进程。
- 判断是否来自 Codex 插件缓存。
- 判断是否是 `node`、`python`、`vite`、`next`、`pnpm`、`npm` 等开发服务。
- 从 `--cwd`、`--working-directory`、路径参数、项目路径中提取归属。

### cwd

Windows 端不应把 cwd 当成强依赖。

原因：

- Windows 没有类似 macOS `lsof -d cwd` 的稳定低成本公开接口。
- 可通过底层 NT API 或句柄枚举推断部分进程 cwd，但成本和权限风险较高。
- 某些进程已经退出或权限不足时，cwd 获取会失败。

替代策略：

- 命令行路径。
- 父子进程链。
- 监听端口。
- 可执行路径。
- Codex 配置、插件缓存路径和 workspace 路径规则。

如果后续确实需要 cwd：

- 只对高价值候选 PID 按需查询。
- 设置 60 秒以上冷却。
- 查询失败不降级成错误，只作为缺失证据处理。

### 监听端口

使用 Windows IP Helper API `GetExtendedTcpTable`。

采集字段：

- PID
- 本地地址
- 本地端口
- TCP 状态

建议只关注 `LISTEN` 状态，并映射到进程 PID。端口扫描要和进程扫描分开缓存，避免每次 UI 刷新都触发完整系统调用。

### CPU 与内存

CPU 不要只取单次瞬时值。推荐：

- 第一次扫描记录进程累计 CPU 时间。
- 第二次扫描用 delta / elapsed 计算近似 CPU 百分比。
- UI 上显示最近一次有效采样值。

内存可用：

- working set
- private bytes

UI 使用百分比或 MB 均可。为保持和 macOS 端一致，第一版优先显示百分比；详情页可补 MB。

## 服务分组规则

Windows 端分组规则和 macOS 端保持语义一致：

### Codex 主进程

识别依据：

- 可执行名或安装路径包含 Codex Desktop。
- 命令行包含 Codex Desktop 主进程特征。

风险：

- 永远受保护。

### Codex 支撑进程

识别依据：

- Codex Desktop 子进程。
- 插件 MCP server。
- Computer Use / Data Analytics 等插件路径。
- 命令行包含 Codex app-server、plugin cache、stdio server 等特征。

风险：

- 默认需确认。
- 如果父进程仍活动，降低风险。
- 如果脱离父进程且长时间运行，可升为建议清理。

### Codex 线程 / workspace

识别依据：

- 命令行包含 Codex thread/session 信息。
- 命令行或参数包含 workspace 路径。
- 父子进程链连接到 Codex 启动的 shell、node、powershell、cmd。

风险：

- 有活动父进程时需确认。
- 脱离父进程且长时间运行时建议清理。

### 开发服务

识别依据：

- `node`、`npm`、`pnpm`、`yarn`、`vite`、`next`、`webpack`。
- `python -m http.server`、`uvicorn`、`flask`、`django`。
- `dotnet watch`、`cargo run` 等可配置关键词。
- 存在开发端口监听。

风险：

- 如果能归属到 Codex workspace，可作为 Codex 工作区服务。
- 如果不能归属，只标记为需确认，不应默认建议清理。

### 非开发 App 误报过滤

必须维护一份内置排除规则，避免把普通 Windows 应用监听端口误判为开发服务。

候选排除：

- 浏览器 helper。
- 同步盘客户端。
- 云盘。
- 聊天软件。
- IDE 自身后台服务。

排除规则必须低风险：只有在明显属于普通安装路径、普通 App 子进程，且没有 Codex/workspace 证据时才排除。

## 关闭策略

Windows 没有 SIGTERM/SIGKILL。建议分两级：

### 温和关闭

优先顺序：

1. 如果是 GUI 进程，尝试发送窗口关闭。
2. 如果是控制台进程，尝试向进程组发送 `CTRL_BREAK_EVENT`。
3. 等待配置的秒数。
4. 重新扫描确认是否退出。

### 强制关闭

仅在用户二次确认后执行：

- `TerminateProcess`
- 或使用系统命令等价能力

强制关闭前必须展示：

- PID
- 命令行
- 归属组
- 风险原因

默认限制：

- 不跨用户。
- 不关闭受保护进程。
- 不关闭白名单进程。
- 不自动强杀。

## 低占用策略

必须从第一版就按低占用设计。Windows 端应采用和新版 macOS 架构一致的“两层刷新”：

- 低频全量扫描：发现服务组、端口、命令行、父子关系、风险和关闭建议。
- 实时资源采样：只针对当前快照里已经识别出来的 PID 更新 CPU/内存，不重新扫描、不重新分组。

UI 上的 CPU/内存数字来自资源采样层；服务组增删、端口、cwd/路径归因和建议项来自全量扫描层。

### 启动扫描

启动后 2 秒执行快速扫描，用来让 UI 尽快有内容：

- 枚举进程基础信息。
- 只读取低成本字段。
- 不跑全量 WMI。
- 不跑昂贵 cwd。
- 建立第一批资源采样目标 PID。

快速扫描完成后，资源采样器开始对这些已知 PID 做轻量轮询。第一帧只建立 CPU 时间基线，第二帧开始更新 CPU 百分比，避免把全量扫描拿到的 CPU 值短暂刷成 0。

### 实时资源采样

资源采样默认每 2 秒一次，只处理当前 `ProcessSnapshot` 里的 PID。

采样内容：

- CPU：读取进程累计 user/system 时间，使用两次采样的 delta / elapsed 计算百分比。
- 内存：读取 resident / working set，再换算成百分比或 MB。

采样规则：

- 不跑 WMI 全量查询。
- 不读取监听端口。
- 不查 cwd。
- 不改变服务组、风险、端口、证据和关闭建议。
- PID 消失时从采样缓存移除。
- 暂停扫描时资源采样也暂停，避免用户以为后台还在工作。

Windows 端可用实现：

- CPU：`GetProcessTimes` 或等价的 per-process kernel/user time。
- 内存：`GetProcessMemoryInfo` / working set / private bytes。
- PID 集合：只来自当前快照，不主动扩展范围。

### 完整扫描

完整扫描用于：

- 手动刷新。
- 自动扫描间隔到期。
- 用户打开详情页时按需补全。
- 关闭动作结束后的重新确认。

完整扫描包括：

- WMI 命令行。
- TCP 监听端口。
- 父子进程链。
- 高价值候选的额外字段。

完整扫描完成后必须重建 `ProcessSnapshot`，并把新的 PID 集合作为后续资源采样目标。资源采样更新时只替换快照里的 CPU/内存字段，不能改变快照结构。

### 冷却与缓存

建议默认值：

- 自动扫描间隔：120 秒。
- 资源采样间隔：2 秒。
- WMI 命令行缓存：60 秒。
- TCP 端口缓存：30 秒。
- cwd / 高成本补全：60 秒以上。
- UI 刷新不触发系统扫描，只消费 snapshot。
- UI 中 CPU/内存刷新只触发资源采样，不触发完整扫描。

### 预算

目标预算：

- 空闲常驻 CPU：接近 0%。
- 资源采样瞬时 CPU：接近不可感知，目标低于 1%。
- 自动完整扫描瞬时 CPU：尽量低于 1%-2%。
- 启动前 5 秒不出现长时间高 CPU。
- 常驻内存：优先低于 Electron 级别；Tauri/Rust 方案应明显更轻。

## MVP 阶段

### Phase 0：可运行骨架

- 建 Tauri v2 项目。
- 托盘图标。
- 主窗口。
- 设置窗口占位。
- 前端主题复刻 macOS 端。

验收：

- Windows 11 上可启动、可退出。
- 托盘点击能打开快速面板。

### Phase 1：只读扫描

- 枚举当前用户进程。
- 展示 PID、PPID、命令行、CPU、内存、运行时长。
- 采集 TCP listening ports。
- 实现基础分组。

验收：

- 能识别 Codex Desktop 主进程。
- 能识别 `node` / `powershell` / `cmd` 启动的开发服务。
- 不误报明显普通 App helper。

### Phase 1.5：实时资源采样

- 增加独立资源采样器。
- 每 2 秒只采样当前快照里的 PID。
- CPU 用两次累计时间差计算。
- 内存用 working set / resident memory 计算。
- 采样结果只替换 CPU/内存，不改变服务组结构。
- UI 同步更新标题栏总占用、服务组行占用和进程行占用，不触发重新分组。

验收：

- 顶部总 CPU/内存和每组 CPU/内存接近实时更新。
- 详情进程树中每个进程行右侧能看到该进程自己的 CPU/内存。
- 资源采样不会触发 WMI、端口扫描或 cwd 查询。
- 第一次采样只建立 CPU 基线，不把已有 CPU 值刷成 0。
- 暂停扫描后资源采样也暂停。

### Phase 2：Codex 归因

- 插件 MCP 识别。
- 父子进程链。
- 命令行路径归因。
- 风险评分。
- 受保护、需确认、建议清理。

验收：

- Codex 相关服务能聚合成可读组。
- 详情页能说明关联依据。

### Phase 3：关闭动作

- 温和关闭。
- 强制关闭二次确认。
- 操作审计日志。
- 关闭后重新扫描。

验收：

- 不关闭受保护进程。
- 不自动强杀。
- 关闭动作可追溯。

### Phase 4：性能和打包

- 缓存和冷却。
- 启动快速扫描。
- 完整扫描降频。
- 2 秒资源采样。
- 安装包。
- 自启动配置。

验收：

- 空闲 CPU 接近 0%。
- 资源数字可接近实时更新。
- 资源采样不会长时间高占用。
- 自动完整扫描不会长时间高占用。
- 普通用户安装后可运行。

## 和 macOS 端的差异

| 维度 | macOS 端 | Windows 端 |
| --- | --- | --- |
| UI | SwiftUI/AppKit | Tauri 前端或 WinUI |
| 托盘 | `NSStatusItem` | Tauri tray / Windows tray |
| 进程枚举 | `ps` | Win32 API / WMI |
| 端口 | `lsof -iTCP` | `GetExtendedTcpTable` |
| cwd | `lsof -d cwd` | 不作为强依赖 |
| 温和关闭 | SIGTERM | close window / CTRL_BREAK |
| 强制关闭 | SIGKILL | TerminateProcess |
| 打包 | `.app` + `.dmg` | `.msi` / `.msix` / `.exe` installer |

## 风险清单

- WMI 过频会造成明显 CPU 和延迟，需要缓存。
- Windows cwd 获取不稳定，不要把它作为核心判断依据。
- 控制台进程温和关闭需要进程组和控制台事件处理，不能假设每个进程都支持。
- 端口监听并不等于开发服务，必须结合命令行和进程路径。
- Windows Defender 或企业安全软件可能影响进程查询和关闭动作。
- 未签名安装包会被 SmartScreen 拦截，正式分发需要代码签名证书。

## 建议决策

第一版 Windows 端建议采用：

```text
Tauri v2 + React + Rust scanner
```

暂不做：

- 高成本 cwd 追踪。
- 后台实时进程事件订阅。
- 跨用户进程管理。
- 自动强制关闭。

先把“看清楚、分组准、低占用、可安全关闭”做稳定，再补更深的 Windows 原生能力。
