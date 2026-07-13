# MacTools 功能迁移评估与首批落地记录

日期：2026-07-07  
目标仓库：[ggbond268/MacTools](https://github.com/ggbond268/MacTools)  
审计快照：`83e3bb3 Fix menu bar hidden permission crash`  
许可证：Apache-2.0

## 结论

MacTools 适合借鉴的是“系统工具箱的功能分层”和“卡片式状态反馈”，不适合直接把插件体系整包搬进 TraceFence。它有 38 个插件，其中相当一部分依赖 Sparkle、FinderSync、私有 framework、Accessibility/Input Monitoring、IOKit/HID、`launchctl` 写操作或 privileged helper。这些能力在官网版可以作为高级维护能力逐步做，但上架版只能做“用户授权范围内的只读巡检”和“用户明确点击触发的本机动作”。

本次已经先迁移一批两边都能接受的能力，并且没有沿用 MacTools 的名称：

- MacTools `IPOverview` -> TraceFence `本机诊断`
- MacTools `LaunchControl` 的安全子集 -> TraceFence `启动项只读巡检`
- MacTools `ClipboardClear` 的显式动作 -> TraceFence `清空剪贴板`

已落地代码：

- `AIMacCleaner/LocalSystemDiagnosticsView.swift`
- `AIMacCleaner/ContentView.swift`
- `AIMacCleaner.xcodeproj/project.pbxproj`

验证结果：

```bash
xcodebuild -project AIMacCleaner.xcodeproj -scheme AIMacCleaner -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

结果：`BUILD SUCCEEDED`。仅保留既有 `ProviderQuotaService.swift` 的 Sendable warning，本次新增页面无编译错误。

## 上架版可放

这些能力建议进上架版，前提是文案清楚、只读优先、删除/修改必须由用户明确点击。

| MacTools 参考功能 | TraceFence 建议名称 | 上架版处理方式 | 原因 |
| --- | --- | --- | --- |
| `IPOverview` IP 检测 | 本机诊断 | 已落地。读取出口 IP、本机网卡地址、关键站点连通性 | 网络诊断属于普通功能，风险低 |
| `LaunchControl` 启动项 | 启动项只读巡检 | 已落地只读扫描 `LaunchAgents/LaunchDaemons` plist，不调用 `launchctl` 修改 | 读目录和展示风险可以解释，写操作留给官网版 |
| `ClipboardClear` 清空剪贴板 | 清空剪贴板 | 已落地为明确按钮动作，只清空当前 pasteboard，不读取历史 | 用户主动动作，隐私边界清楚 |
| `SystemStatus` 系统状态 | 系统健康概览 | 可做 CPU/内存/磁盘/网络只读图表 | 系统状态读数通常可过审 |
| `DiskClean` / `XcodeClean` | 清理建议 / 开发缓存清理 | 保留扫描、大小统计、用户选择删除 | TraceFence 已有清理模块，重点是用户授权和撤销提示 |
| `EjectDisk` | 外置盘操作 | 只对用户可见挂载卷提供推出按钮 | 明确设备动作，注意失败提示 |
| `EmptyTrash` | 废纸篓检查 | 建议只提示和跳转，不默认清空 | 自动清空风险高，尤其 TraceFence 有受保护目录语义 |
| `Calendar` | 日历小组件 | 可做，但必须声明 EventKit 使用目的 | 需要隐私用途说明 |
| `DeviceBattery` | 外设电量 | 系统公开电量可做，HID/Input Monitoring 子集不要进上架版 | HID 输入监控容易触发审核问题 |

## 官网版可放

这些能力更适合官网版，原因不是代码难，而是它们天然越过了 App Store 的沙盒、动态下载或系统修改边界。

| MacTools 参考功能 | TraceFence 建议名称 | 官网版处理方式 | 原因 |
| --- | --- | --- | --- |
| `Homebrew` | 开发环境管家 | 可以做 brew 包清单、过期检查、卸载引导 | 需要执行外部 CLI，适合非沙盒官网版 |
| `ZshConfig` | Shell 配置守卫 | 可以做 diff、备份、恢复，不建议静默写入 | 修改 shell 配置属于高级维护 |
| `LaunchControl` 写操作 | 启动项控制台 | 官网版可在强确认下执行 enable/disable/unload | 需要 `launchctl`，上架版不碰 |
| `FixDamagedApp` | 应用隔离修复 | 只放官网版，必须强提示风险 | 涉及 quarantine/xattr，审核风险高 |
| `RightClick` Finder 右键 | Finder 扩展工具 | 官网版可做 FinderSync 扩展 | 需要 extension、entitlements、额外签名链 |
| `AppHotkey` / `MouseEnhancer` | 快捷动作 / 输入增强 | 官网版可做，需权限引导 | Accessibility / Input Monitoring 审核和信任成本高 |
| `MenuBarHidden` / `HideNotch` | 菜单栏空间管理 | 官网版可做，严格权限提示 | 全局事件和 Accessibility 依赖明显 |
| `DisplayBrightness` / `NightShift` / `DisplayTrueColor` | 显示器高级控制 | 官网版限定 | 使用 IOKit / CoreBrightness private framework |
| `FanControl` | 散热高级控制 | 官网版限定，最好独立开关 | privileged helper、SMC 写入、root 安装路径 |
| `BatteryChargeLimit` | 电池维护上限 | 官网版限定 | 系统级控制，可能依赖 helper 或私有路径 |
| Sparkle 更新 | 官网自动更新 | 官网版可做，但 TraceFence 已有 direct update 服务，不建议再引入 Sparkle | App Store 禁止自更新，官网版也避免双更新体系 |
| 插件市场 | 扩展中心 | 官网版可做本地白名单插件，不建议动态执行第三方代码 | 上架版动态下载/执行代码风险极高 |

## 暂不建议搬

这些功能短期不要进入 TraceFence，除非以后拆成独立 helper 或独立产品线：

- 私有 framework 强依赖：`CoreBrightness`、`MultitouchSupport`。
- SMC / 风扇 / 电池写入类能力。
- 需要安装 `/Library/PrivilegedHelperTools` 的 helper。
- 自动修复损坏 App、批量移除 quarantine。
- 动态插件下载和执行第三方插件代码。
- 全局输入监听类能力放入上架版。

## 为什么官网版和上架版会有差异

1. 上架版运行在 App Store 审核语境里，功能必须解释得清楚，数据访问必须最小化，修改系统状态必须由用户明确触发。
2. 官网版可以使用非沙盒能力、外部 CLI、helper、Sparkle 或 GitHub 更新，但也要避免“默认修改系统”的体验。
3. MacTools 是插件化系统工具箱，TraceFence 是 Agent 安全/清理/额度监控工具。TraceFence 应该吸收“诊断、审计、状态展示”这些和主线一致的能力，而不是把所有系统 tweak 都塞进去。
4. MacTools 里很多功能为系统增强类：它们的价值在官网版，但放到上架版会让审核、权限说明和用户信任成本一起上升。

## 本次落地内容

### 本机诊断

入口：工具侧栏新增 `本机诊断`。

能力：

- 读取出口 IP：`api.ipify.org`、`ifconfig.me` 双端点。
- 读取本机网卡 IPv4/IPv6：使用 `getifaddrs`，过滤 loopback 和链路本地地址。
- 连通性检查：Apple、GitHub、OpenAI API、Baidu。
- 启动项只读巡检：扫描用户和系统 LaunchAgent/LaunchDaemon plist，展示 label、command、路径、风险级别。
- 本机动作：清空当前剪贴板。

上架版边界：

- 不调用 `sudo`。
- 不安装 helper。
- 不调用 `launchctl` 修改状态。
- 不读取剪贴板内容，只清空 pasteboard。
- 不下载/执行外部插件。

### UI 借鉴点

从 MacTools 借鉴的是“工具卡片 + 状态列表 + 风险提示”的结构，但改成 TraceFence 的视觉语言：

- 顶部 `PageHeader` 保持 TraceFence 现有布局。
- 摘要卡展示出口 IP、本地地址、连通性、启动项数量。
- 网络和本机动作左右分栏。
- 启动项列表使用风险色点，而不是 MacTools 的插件页面命名。
- 侧栏工具组改成可滚动，避免新增工具后底部挤压。

## 后续建议顺序

1. 上架版下一步：把 `SystemStatus` 思路并入 TraceFence 首页，做 CPU/内存/网络/磁盘 mini chart。
2. 上架版下一步：把 `XcodeClean` 思路并入现有清理器，重点做 DerivedData、Simulator cache 的授权清理。
3. 官网版下一步：做 `开发环境管家`，只读读取 Homebrew/npm/pip/cache 体积，删除动作走 TraceFence 现有清理确认流。
4. 官网版下一步：做 `启动项控制台`，在当前只读巡检基础上加 direct-only 强确认操作。
5. 官网版最后再考虑 FinderSync、输入增强、显示器控制、风扇/电池这类需要额外签名和权限解释的能力。

