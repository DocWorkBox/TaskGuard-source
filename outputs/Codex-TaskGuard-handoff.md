# Codex TaskGuard 项目接续记录

生成时间：2026-06-04  
当前临时工作区：`/Users/zhaoke/Documents/Codex/2026-06-04/codex-node-bash-powershell`

## 1. 项目目标

开发一款 macOS 原生辅助 App，用来管理 Codex Desktop 在不同对话线程/项目中启动的后台服务和开发进程。

核心定位：

- 显示当前用户下 Codex 相关支撑进程、插件 MCP 进程、本地开发服务、监听端口。
- 按线程线索、工作目录、插件目录、进程树、端口进行分组。
- 区分 `建议清理`、`需确认`、`受保护`。
- 默认不使用 `sudo`，只管理当前用户进程。
- 关闭进程前必须确认；优先 `SIGTERM`，必要时再人工确认 `SIGKILL`。
- 做成 Codex Desktop 的伴生菜单栏工具：主窗口可关闭，菜单栏常驻，只有菜单栏里的“退出”才真正退出。

当前用户可见软件名已改为：`Codex TaskGuard`

## 2. 当前技术栈

- macOS SwiftUI + AppKit
- SwiftPM 项目，最低 macOS 14
- AppKit 用于：
  - `NSStatusItem` 菜单栏常驻项
  - `NSPopover` 菜单栏小面板
  - `NSWindow` 主窗口
  - Dock/启动栏生命周期切换
- SwiftUI 用于：
  - 主窗口三栏界面
  - 设置窗口
  - 菜单栏 Popover 内容
  - 即时 tooltip
- 进程扫描：
  - `ps -axo pid=,ppid=,user=,stat=,etime=,pcpu=,pmem=,command=`
  - `lsof -nP -iTCP -sTCP:LISTEN`
  - 对候选进程再用 `lsof -a -p <pid> -d cwd -Fn` 读取 cwd

## 3. 关键文件

### SwiftPM / 打包

- `Package.swift`
- `script/build_and_run.sh`
- `script/make_icon_from_raster.swift`
- `.codex/environments/environment.toml`

### 核心扫描和分组逻辑

- `Sources/CodexProcessManagerCore/Models.swift`
- `Sources/CodexProcessManagerCore/ProcessParser.swift`
- `Sources/CodexProcessManagerCore/ProcessSnapshotProvider.swift`
- `Sources/CodexProcessManagerCore/ProcessClassifier.swift`
- `Sources/CodexProcessManagerCore/ServiceGrouper.swift`
- `Sources/CodexProcessManagerCore/ThreadHintExtractor.swift`
- `Sources/CodexProcessManagerCore/CodexSessionIndex.swift`
- `Sources/CodexProcessManagerCore/DisplayNameResolver.swift`
- `Sources/CodexProcessManagerCore/KillPlanner.swift`
- `Sources/CodexProcessManagerCore/ProcessTerminator.swift`
- `Sources/CodexProcessManagerCore/AuditLogger.swift`

### App/UI

- `Sources/CodexProcessManager/App/CodexProcessManagerApp.swift`
- `Sources/CodexProcessManager/App/AppDelegate.swift`
- `Sources/CodexProcessManager/App/ApplicationController.swift`
- `Sources/CodexProcessManager/Stores/ProcessMonitor.swift`
- `Sources/CodexProcessManager/Stores/AppPreferences.swift`
- `Sources/CodexProcessManager/Views/ContentView.swift`
- `Sources/CodexProcessManager/Views/SidebarView.swift`
- `Sources/CodexProcessManager/Views/GroupListView.swift`
- `Sources/CodexProcessManager/Views/DetailView.swift`
- `Sources/CodexProcessManager/Views/MenuBarContentView.swift`
- `Sources/CodexProcessManager/Views/SettingsView.swift`
- `Sources/CodexProcessManager/Views/ImmediateTooltip.swift`

### 测试

- `Tests/CodexProcessManagerCoreTestRunner/main.swift`

因为当前本机 CommandLineTools 环境里 XCTest/Testing 不稳定，项目使用自定义 test runner。

## 4. 当前已实现功能

### 4.1 主窗口

三栏 macOS 工具型界面：

- 左侧范围：
  - 全部
  - Codex 线程
  - 开发服务
  - 疑似残留
  - 监听端口
  - 白名单/受保护
- 中间服务组列表：
  - 标题
  - 风险 badge
  - 所属类型
  - 进程数
  - 监听端口
  - cwd/命令摘要
- 右侧详情：
  - 组标题
  - 风险
  - 进程数、端口、CPU、内存、最长运行时间、置信度
  - 线程/会话来源
  - 关闭建议
  - 关联依据
  - 进程树和完整命令行

### 4.2 工具栏按钮

主窗口顶部右侧按钮从左到右：

- 刷新：立即重新扫描 Codex 相关进程、开发服务和监听端口。
- 暂停/恢复：暂停或恢复自动扫描，手动刷新仍可用。
- 清理建议项：关闭高置信建议清理项，执行前确认。
- 关闭当前组：关闭当前选中的非保护服务组，执行前确认。

已加 `ImmediateTooltip`，悬停约 0.12 秒显示自定义提示；系统 `.help` 仍保留作兜底。此前出现过中文 tooltip 被压成一列的问题，已通过固定 tooltip 气泡宽度修复。

### 4.3 菜单栏和 Dock 生命周期

当前设计：

- App 打开主窗口时：Dock/启动栏显示 `Codex TaskGuard`。
- 点击红色关闭按钮关闭主窗口：App 不退出，后台继续运行，Dock/启动栏图标隐藏。
- 菜单栏入口继续常驻。
- 菜单栏 UI 里有：
  - 打开详情
  - 刷新
  - 暂停/恢复扫描
  - 清理建议项
  - 最近服务组
  - 设置
  - 退出
- 点击菜单栏里的 `退出` 才真正退出软件。

实现位置：

- `ApplicationController.launch()`
- `ApplicationController.showMainWindow()`
- `ApplicationController.windowWillClose(_:)`
- `AppDelegate.applicationShouldTerminateAfterLastWindowClosed(_:)`
- `MenuBarContentView.footer`

注意：菜单栏显示曾出现用户反馈“看不到图标”。目前做了双保险：

- `ApplicationController` 创建 AppKit `NSStatusItem`，显示 `checkmark.shield` + `TG <count>`。
- `CodexProcessManagerApp` 同时声明 SwiftUI `MenuBarExtra("TaskGuard", systemImage: "checkmark.shield")`。

后续正式项目里建议二选一统一实现，避免重复菜单栏入口。用户当前更关心“菜单栏一定要有入口”，所以临时版保留双实现。

### 4.4 扫描和分组规则

已支持：

- 当前用户进程过滤。
- 非当前用户进程忽略。
- 系统/App helper 过滤，避免误报 Chrome/WebKit/Adobe/微信/网盘/音乐等。
- `node` 不再作为裸关键词泛匹配，只有在 Codex 工作区、监听开发端口、路径指向项目时才算开发服务。
- Codex 主进程保护。
- 当前 App 自身保护。
- 白名单保护。
- 插件 MCP 进程识别。
- Codex 工作区进程识别。
- 监听端口识别。
- 孤立旧 helper / 父进程消失的 Codex 支撑进程可被标为 `建议清理`。

### 4.5 显示名修复

已经修过以下显示名问题：

- `.codex/plugins/cache/.../data-analytics/0.1.35...` 显示成 `Data Analytics 插件`。
- `.codex/plugins/cache/.../computer-use/1.0.799` 显示成 `Computer Use 插件`。
- `--working-dir /Users/.../New project` 不再因空格截断成 `/Users/.../New`。
- `--session-id` 进程如果能查到 `~/.codex/session_index.jsonl`，显示 Codex 线程名；查不到则显示 `项目名 · 会话 <短 ID>`。
- Codex 主进程显示为 `Codex Desktop 主进程`。
- Codex 支撑进程显示为 `Codex Desktop 支撑进程`。
- App 自身显示为 `Codex TaskGuard`。

相关文件：

- `ThreadHintExtractor.swift`
- `CodexSessionIndex.swift`
- `DisplayNameResolver.swift`

## 5. 图标当前状态

用户不满意最初的蓝底白框勾图标，要求使用 imagegen 生成的 8 款图标里的 1 号。

当前图标流程：

- 原 imagegen 8 款设计板保存于：
  - `/Users/zhaoke/.codex/generated_images/019e90ef-e52f-72a2-baa8-42bb75e95afe/ig_05469e7c94431d62016a211911eb488191ba8316fa5b0b98dc.png`
- 已复制到项目：
  - `Assets/IconSources/taskguard-options-board.png`
- 使用 `script/make_icon_from_raster.swift` 从 4x2 设计板裁剪左上角 1 号图标。
- 不使用 SVG。
- 流程是：
  - 从 imagegen 原始 raster PNG 裁剪 1 号区域。
  - 从边缘 flood fill 扣除浅色背景。
  - 输出阶段用圆角矩形 alpha mask 裁掉外圈灰色投影。
  - 生成各尺寸 PNG。
  - 使用 `iconutil` 生成 `TaskGuardIcon.icns`。
- 打包后资源在：
  - `dist/Codex TaskGuard.app/Contents/Resources/TaskGuardIcon.icns`
  - `dist/Codex TaskGuard.app/Contents/Resources/TaskGuardIcon-preview.png`

用户最后要求“外圈灰色阴影也去掉”，已在 `make_icon_from_raster.swift` 里通过 `removeOuterShadow(in:size:)` 实现。

## 6. 构建和运行命令

推荐构建：

```bash
env CLANG_MODULE_CACHE_PATH=/Users/zhaoke/Documents/Codex/2026-06-04/codex-node-bash-powershell/.build/clang-module-cache \
SWIFTPM_HOME=/Users/zhaoke/Documents/Codex/2026-06-04/codex-node-bash-powershell/.build/swiftpm-home \
swift build --scratch-path /Users/zhaoke/Documents/Codex/2026-06-04/codex-node-bash-powershell/.build
```

推荐测试：

```bash
env CLANG_MODULE_CACHE_PATH=/Users/zhaoke/Documents/Codex/2026-06-04/codex-node-bash-powershell/.build/clang-module-cache \
SWIFTPM_HOME=/Users/zhaoke/Documents/Codex/2026-06-04/codex-node-bash-powershell/.build/swiftpm-home \
swift run --scratch-path /Users/zhaoke/Documents/Codex/2026-06-04/codex-node-bash-powershell/.build CodexProcessManagerCoreTestRunner
```

真实扫描一次：

```bash
env CLANG_MODULE_CACHE_PATH=/Users/zhaoke/Documents/Codex/2026-06-04/codex-node-bash-powershell/.build/clang-module-cache \
SWIFTPM_HOME=/Users/zhaoke/Documents/Codex/2026-06-04/codex-node-bash-powershell/.build/swiftpm-home \
swift run --scratch-path /Users/zhaoke/Documents/Codex/2026-06-04/codex-node-bash-powershell/.build CodexProcessManagerCoreTestRunner --scan-once
```

打包并启动：

```bash
./script/build_and_run.sh --verify
```

注意：

- 在 Codex sandbox 内运行 SwiftPM 可能遇到 `sandbox-exec: sandbox_apply: Operation not permitted`，需要使用已授权的沙盒外执行。
- `script/build_and_run.sh` 会杀掉旧的 `CodexProcessManager` 进程，再打包 `dist/Codex TaskGuard.app` 并启动。

## 7. 最近验证结果

最近一次核心测试输出：

```text
All core behavior tests passed
```

最近一次真实扫描曾出现类似结果：

```text
groups=6
suggested=0
ports=5
需确认    Codex 支撑进程    codex-node-bash-powershell
需确认    Codex 支撑进程    Computer Use 插件
需确认    Codex 支撑进程    Data Analytics 插件
受保护    受保护           Codex Desktop 支撑进程
受保护    受保护           Codex Desktop 主进程
受保护    受保护           Codex TaskGuard
```

实际数字会随当前 Codex/Desktop 进程变化。

## 8. 当前 git 状态

当前仓库处于未提交初始状态，`git status --short` 显示项目文件基本都是 untracked：

```text
?? .codex/
?? .gitignore
?? Assets/
?? Package.swift
?? README.md
?? Sources/
?? Tests/
?? script/
```

正式项目迁移时建议：

1. 在正式目录初始化干净仓库。
2. 复制以下目录和文件：
   - `Package.swift`
   - `.gitignore`
   - `.codex/environments/environment.toml`
   - `README.md`
   - `Sources/`
   - `Tests/`
   - `script/`
   - `Assets/IconSources/taskguard-options-board.png`
3. 不复制：
   - `.build/`
   - `dist/`
   - 临时输出和系统缓存
4. 迁移后先运行测试，再运行打包脚本。

## 9. 已知问题和后续建议

### 9.1 菜单栏入口重复风险

当前为了修复“菜单栏看不到图标”，同时保留了：

- AppKit `NSStatusItem`
- SwiftUI `MenuBarExtra`

正式项目建议实际观察稳定性后只保留一种：

- 如果 `MenuBarExtra` 稳定显示，优先保留它，代码更原生。
- 如果需要更强控制、动态标题、Popover 行为，保留 AppKit `NSStatusItem`。

### 9.2 Dock 图标缓存

macOS 可能缓存旧图标。当前 bundle 已带 `TaskGuardIcon.icns`，运行时也设置了 `NSApp.applicationIconImage`。如果 Dock 上仍短暂显示旧图标，可能需要：

- 重新打开 app。
- 从 Dock 移除旧固定项后再打开。
- 必要时刷新 LaunchServices 缓存。

### 9.3 线程名映射仍有限

目前线程映射来自：

- 进程命令行里的 `thread-id` / `turn-id` / `cwd`
- Codex turn payload 里的 `last-assistant-message.title`
- `~/.codex/session_index.jsonl`

如果 Codex 未来提供官方线程-进程元数据，应接入官方接口，替换现在的启发式匹配。

### 9.4 图标源仍来自 8 款设计板裁剪

用户要求“用 1 号图标，不用 SVG 转 PNG，直接用 imagegen 画最大尺寸再缩放”。由于后续单独 imagegen 曾触发限流，目前实际使用的是上一轮 imagegen 生成的 8 款设计板中裁出的 1 号图标。它仍是 imagegen raster 位图来源，不是 SVG。

如果后续 imagegen 可用，建议再单独生成一张 1024 或更高分辨率的 1 号图标源图，替换 `Assets/IconSources/taskguard-options-board.png`，并把裁剪逻辑改成直接读取单图。

### 9.5 正式项目可补的能力

- 给每个服务组加复选框，多选关闭。
- 对“需确认”项提供更明确的理由和风险解释。
- 加审计日志查看界面。
- 加“白名单路径/命令”编辑 UI。
- 加端口占用视图，按端口排序。
- 对关闭失败、PID 复用、权限不足做更细提示。
- 为菜单栏入口写单独的 UI/行为测试或手工验收清单。

## 10. 给新对话线程的接续提示

如果新线程继续开发，可以直接给它这段任务说明：

```text
这是一个 SwiftPM macOS App 项目，名字 Codex TaskGuard，路径在正式项目目录中。它是 Codex Desktop 的菜单栏伴生进程管理器，用 ps/lsof 扫描当前用户进程，按 Codex 线程/项目 cwd/插件 MCP/开发端口分组，并安全关闭疑似残留进程。请先阅读 outputs/Codex-TaskGuard-handoff.md 和 README.md，然后运行 CodexProcessManagerCoreTestRunner 确认当前状态，再继续开发。
```

