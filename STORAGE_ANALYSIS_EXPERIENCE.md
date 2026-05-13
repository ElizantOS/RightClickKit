# RightClickKit 存储/目录分析实现经验

Last updated: 2026-05-13

> 项目级 Agent、小精灵、imagegen/provider、文档维护经验已拆到
> `RIGHTCLICKKIT_EXPERIENCE.md`。本文继续聚焦 Storage Analysis 和
> Directory Tree 这类文件系统分析工具的性能与交互经验。

这份记录梳理了从最初需求到当前版本的实现过程，重点记录用过的 skills、遇到的问题、解决方式，以及后续继续做类似 native macOS 工具时值得复用的经验。

## 需求演进

最开始的需求是给右键菜单增加两个原生能力：

- 目录树展示：右键文件夹后快速生成目录结构报告。
- 存储空间分析：右键文件夹后用原生界面展示类似 DaisyDisk 的空间占用图。

后续需求逐步变得更明确：

- 不要网页，要 macOS 原生 App。
- 存储分析要有好看的玫瑰图 / sunburst 图。
- 扫描不能只有一个转圈，要立刻展示已经扫出来的内容。
- 扫描要并行、异步、持续递归，进入子目录后也要继续扫。
- hover 图块时右侧 Inspector 要立即联动。
- click 图块时要下钻，返回后不能重新 `du`。
- 进度不能假完成，后台还有任务时不能显示 complete。
- App 需要图标，需要重新安装到本机。
- 最后整体 UI 要改成 macOS 新 Liquid Glass 风格。

## 用过的 Skills

| Skill | 用途 | 结果 |
| --- | --- | --- |
| `imagegen` | 用于寻找并调用本地生成图片能力，支持 App 图标资产生成 | 生成并落地了 `assets/AppIcon.icns`、iconset 和 1024 PNG |
| `build-macos-apps:swiftpm-macos` | 处理 SwiftPM macOS package 的构建、target 组织和 CLI/App 双入口 | 项目保持 SwiftPM 结构，包含 `rck`、主 App、Storage Viewer helper |
| `build-macos-apps:appkit-interop` | SwiftUI 无法稳定处理图表 hover/click 命中时，桥接 AppKit | 用 `NSViewRepresentable` 做 sunburst 命中层，解决 hover/click 不响应 |
| `build-macos-apps:build-run-debug` | 构建、安装、启动 `.app` 包，而不是只跑裸 executable | 验证了 `/Users/echo/Applications/RightClickKit.app` 和 Storage helper 都能启动 |
| `build-macos-apps:liquid-glass` | 将主 App 和 Storage Analysis 改成现代 macOS Liquid Glass 风格 | 新增兼容封装，macOS 26 使用 `glassEffect` / `.glass`，旧系统回退到 material/bordered |
| `ralpha` | 做阶段性 review/acceptance，避免只靠单线程自测 | storage workflow 的关键切片通过 architect、code-reviewer、code-simplifier 检查 |

## 关键问题和解决方式

### 1. 扫描太慢，只显示转圈

问题：最早的扫描更像同步报告生成，用户必须等完整结果出来才能看到图。

解决：

- 引入 `LazyStorageScanner`。
- 第一层先快速枚举，尽早产出 `StorageLayerSnapshot`。
- 子目录大小用并行 `du -sk` 获取。
- 用 async stream 持续发布 snapshot，让 UI 边扫边画。

经验：存储分析工具最重要的是 first meaningful paint，不是一次性算出完美结果。

### 2. 进度显示不可信

问题：后台仍有递归扫描时，UI 曾经显示 `Scan complete`，这会让用户误判。

解决：

- 在 `StorageScanModel` 中统一管理全局 progress。
- 将 root scanning、manual expand、auto expand queue、active loading paths 都纳入进度判断。
- 只有本地扫描完成且后台队列清空时才显示 complete。

经验：异步任务的 complete 必须由统一状态机判断，不能由某一个局部 stream 自己决定。

### 3. Hover 无法稳定联动右侧 Inspector

问题：SwiftUI Canvas 上做复杂扇区 hit test 不稳定，hover 更新慢或完全没反应。

解决：

- 保留 SwiftUI `Canvas` 负责绘制。
- 覆盖一个透明 AppKit `NSViewRepresentable` 命中层。
- 在 `ChartHitTestView` 中用鼠标位置计算 ring segment。
- hover 只更新本地 `previewPath`，不触发扫描。

经验：复杂桌面交互不要硬拗 SwiftUI 手势，AppKit bridge 是合理工具。

### 4. 点击下钻后又跳回原页面

问题：点击后 selected/detail/preview 状态互相覆盖，后台 snapshot 回来时会把视图拉回旧节点。

解决：

- 区分 `selectedPath`、`detailPath`、`previewPath`。
- click 负责选择和下钻，hover 只负责 preview。
- 后台 report 更新时通过 stable path 替换节点，而不是重置用户当前选择。

经验：hover、selection、navigation 是三种状态，不要共用一个字段。

### 5. 返回后重复 `du`

问题：进入子目录、返回、再进入同一目录时会重新扫，导致卡顿。

解决：

- 在 `StorageScanModel` 中增加 `expandedCache`。
- `expandedPaths` 记录已展开目录。
- 命中缓存时直接 `publishCachedNode`，不再启动新的 `du`。

经验：文件系统扫描必须缓存已展开节点；返回路径应该是纯 UI 操作。

### 6. 后代不会持续递归扫描

问题：只扫当前层，子孙目录不会继续自动展开，玫瑰图无法逐步丰富。

解决：

- 增加 `autoExpandQueue` 和 `queuedAutoExpandPaths`。
- 根扫描完成后，把可读子目录加入后台队列。
- 限制并发、深度和 backlog，避免把磁盘打满：
  - `maxConcurrentExpansions = 2`
  - `maxAutomaticExpansionDepth = 10`
  - `maxAutomaticExpansionBacklog = 96`

经验：后台递归要“持续但克制”。默认并发太高会拖慢 UI，太低又不像 DaisyDisk。

### 7. UI 卡顿和点击无反馈

问题：图块点击、hover、右侧列表联动曾经都显得迟钝。

解决：

- 图表绘制限制最大层级和 segment 数量。
- hover 不再触发任何磁盘 I/O。
- click 立即更新 selection，再异步触发 expand。
- Inspector 的列表 hover 也只更新 preview。

经验：所有鼠标移动路径上都不能做磁盘 I/O，也不能排后台扫描。

### 8. Liquid Glass 改造时的兼容问题

问题：项目最低支持 macOS 14，但 `glassEffect` 和 `.glass` 是 macOS 26 API。

解决：

- 新增 `LiquidGlassStyle.swift`。
- 用 `#available(macOS 26.0, *)` 封装：
  - macOS 26: `glassEffect`、`GlassEffectContainer`、`.glass`、`.glassProminent`
  - 旧系统: `.regularMaterial`、`.bordered`、`.borderedProminent`
- 主 App 和 Storage helper 各自有 target-local 封装，避免跨 target 依赖。

经验：新系统视觉 API 不要散落在业务视图里，先做一层小封装，后续维护会轻很多。

### 9. 切换左侧 Action 后 Advanced 不刷新

问题：右侧 `Advanced` 展开后，切换左侧功能，生成脚本和 `service.yaml` 仍然显示上一个 action 的内容。

原因：

- `GeneratedScriptView` 和 `GeneratedYAMLView` 把传入文本存进了本地 `@State`。
- SwiftUI 在 sidebar-detail 布局中会复用 detail 子视图。
- `@State` 的初始化只在视图身份第一次创建时生效，后续传入的新参数不会自动覆盖本地 state。

解决：

- 只读派生文本不再使用 `@State`。
- 改为 `let script: String` / `let text: String`，并传给 `HighlightedTextEditor(text: .constant(...), isReadOnly: true)`。
- 真正可编辑的 raw script 仍然使用 `$action.rawScript`，保持源数据由 `EditableAction` 拥有。

经验：SwiftUI 里 `@State` 只适合视图自己拥有的临时状态，不适合缓存父级传入的派生数据。只读预览、生成脚本、生成 YAML 这类内容应该直接从当前 selection/model 派生，避免视图复用时显示旧数据。

### 10. 后台 `du` 太积极导致 UI 卡顿

问题：后台递归扫描会持续启动 `du`，并且每个子项结果回来都发布一整棵 report 给 SwiftUI，导致 Canvas、Inspector 和 progress 高频重绘。刷新太频繁不只是 UI 卡，还会抢主线程和对象复制时间，间接拖慢扫描吞吐。

解决：

- 将扫描结果收集和 SwiftUI 发布解耦。
- `StorageScanModel` 增加心跳式发布：后台可以持续收到 snapshot，但 UI 最多按固定节奏合并刷新一次。
- 完成、点击下钻、命中缓存等用户可见关键节点仍然立即 flush。
- 自动后台递归从多路并发改成单链路，降低默认深度、backlog 和 session 总量。
- 手动下钻会暂停后台自动递归，优先响应用户当前路径。
- UI 增加 `Pause/Resume Background` 和 `Stop Background` 控制。
- `du` 用 `nice -n 10` 降低系统调度优先级，并在 task cancel 后停止继续排新工作。
- expanded cache 增加上限，避免长时间递归后内存一直增长。

经验：文件扫描工具要把“磁盘工作”和“UI 发布”分开设计。`du` 结果可以频繁产生，但 SwiftUI 不应该按每个结果重画整棵视图；用心跳合并发布，通常比盲目提高并发更快也更稳。

### 11. 节流后必须明确告诉用户后台仍在扫描

问题：UI 发布改成心跳合并后，界面更顺滑了，但如果没有明显状态提示，用户会觉得“怎么一点看不出来还在扫”。

解决：

- 在 Header 的总大小旁边增加后台扫描 badge。
- 未完成时用 `arrow.triangle.2.circlepath` 持续旋转，显示 active / queued 数量。
- Inspector footer 增加完整状态条，区分 running、paused、complete。
- 保留 Pause/Resume 和 Stop 控制，让状态提示和操作入口在同一区域。

经验：节流不是隐藏进度。只要后台任务仍在运行，就必须有持续、低成本、易扫读的 activity indicator。尤其是 macOS 工具窗口，用户需要一眼知道“还在工作、暂停了、还是已经完成”。

### 12. 玫瑰图应该随扫描结果继续生长

问题：玫瑰图固定只展示 3 层时，后台已经扫出更深目录也不会在图上长出来，用户会觉得递归扫描没有价值。

解决：

- 移除固定 `maxDepth = 3`。
- 根据当前已经有 `children` 的可视树动态计算图表深度。
- 扫到更深后代时，外圈自动长出新 ring。
- 保留可读性保护：最多 8 个可读层、最多 320 个 segment、每个节点限制可见 children 数量。

经验：存储分析图应该展示“已经知道的结构”，而不是展示“预设层数”。但真正无限层会让 ring 过薄、命中困难、绘制变慢，所以要做“随扫描生长 + 可读上限”，而不是完全无上限。

### 13. Complete 状态不能继续播放扫描动画

问题：状态已经显示 `Complete`，但旋转图标仍然看起来在转，会让用户以为后台还没停。

解决：

- Running 状态才创建旋转 activity icon。
- Complete / Paused 改为静态图标。
- 用 `TimelineView(.animation)` 驱动 running 图标旋转，状态切换时直接替换成静态分支，避免 `repeatForever` 动画残留。

经验：状态视觉必须和状态文本一致。只要文本是 Complete，就不能出现任何“还在忙”的动画；否则用户会不信任进度系统。

## Tree Viewer 追加经验

### 14. Tree Text 要像终端一样轻

问题：早期 tree 文本和左侧结构视图都承担太多交互与布局责任，导致用户感觉“正常 `tree` 都不卡，你这个怎么卡”。

解决：

- Structure Map 改成更接近 `tree` 命令输出的文本方案。
- Tree text 避免复杂逐节点富 UI，优先保证滚动和复制顺畅。
- 深度不是固定 limit，而是用户可以动态调整的 level。
- 对长行保留水平阅读能力，避免为了卡片/标签排版强行换行。

经验：目录树视图不是营销页，也不是卡片流。核心是“像命令行 tree 一样快、可复制、可扫读”，再逐步加原生增强。

### 15. 左侧 Outline 和正文性能要分开看

问题：正文 tree text 已经不卡，但左侧 outline 仍然卡，说明瓶颈不在同一个地方。

解决方向：

- 左侧点击只展开当前分支，不触发大范围重算。
- 文件夹点击要能继续深入，但只加载必要子节点。
- 搜索/过滤/选择状态不要导致整棵树重建。

经验：同一个窗口里的两个视图可能有完全不同的性能瓶颈。优化时要分别测正文、outline、inspector、搜索，而不是笼统说“tree 卡”。

## 当前架构要点

- `rck` CLI 负责安装服务、启动目录树和存储分析 viewer。
- 主 App `RightClickKitApp` 负责配置 Quick Actions。
- `RightClickKitStorageView` 是独立 helper App，用原生窗口展示存储分析。
- `RightClickKitTreeView` 是独立 helper App，用原生窗口展示目录树和 tree text。
- `LazyStorageScanner` 负责异步、并行、逐层发布扫描快照。
- `StorageScanModel` 负责缓存、递归队列、进度和 UI 状态。
- `SunburstChartView` 负责图表绘制，`ChartHitTestView` 负责 AppKit 命中测试。

## 验证命令

每次改动后至少跑：

```bash
swift build --disable-sandbox --disable-build-manifest-caching --cache-path .build/cache --scratch-path .build/swiftpm
./scripts/smoke-test.sh
./scripts/install.sh
```

安装位置：

```text
/Users/echo/Applications/RightClickKit.app
/Users/echo/.rightclickkit/bin/rck
```

## 后续继续优化方向

- 继续给后台扫描调优暂停/继续和性能模式。
- 给 rose chart 增加 breadcrumb 和更明确的 hover 高亮。
- 给 Tree outline 做更细粒度的 lazy loading 和选择状态隔离。
- 给 tree text 增加更好的大目录复制/导出体验。
- 增加更真实的大目录性能测试，尤其是 100GB+、大量小文件、权限拒绝目录。

## 最重要的经验

这个项目不是“把 `du` 包一层 UI”这么简单。体验好不好，核心在四件事：

1. 先显示，再补全。
2. hover/click 必须和磁盘 I/O 解耦。
3. 后台扫描状态必须可信。
4. detail 里的只读派生内容不要用 `@State` 缓存。
5. 扫描结果和 SwiftUI 发布要解耦，用心跳节奏合并刷新。
6. 后台任务节流后仍要有明确 activity indicator。
7. 玫瑰图随已扫描结构生长，但必须保留可读性上限。
8. Complete 状态必须是静态完成视觉，不能继续播放 busy 动画。
9. 原生 macOS App 要尊重系统窗口、toolbar、material 和 AppKit 能力。

把这些事守住，RightClickKit 的存储分析就会从“能用”走向“真的顺手”。
