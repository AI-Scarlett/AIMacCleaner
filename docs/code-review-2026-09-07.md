# TraceFence 性能与逻辑审查 · 2026-09-07

## 版本与范围

- 公开宿主发布：TraceFence **1.2.18 (139)**，2026-09-02 发布。
- 独立额度插件：Quota Monitor **1.0.14**。
- 本轮已重新核对公开 GitHub Releases 及私有源码远端 `main`，源码基线为 `b163a489072e8f79af0cd461ec928c8098bdf81c`。
- 修改分支：`codex/review-performance-20260907`，独立工作区 `MacCleaner-review-20260907`。原来的 `MacCleaner` 目录是旧快照分支，未在其上修改。
- 深入审查和修复范围：额度监控生命周期、旧版 Touch Bar 迁移、重复文件扫描与哈希缓存。另对更新检查、插件目录刷新、网络流量监控的主要入口做了代码抽查；不将抽查视作这些模块的完整验收。

## 已修复的问题

| 优先级 | 问题与触发条件 | 修复 | 证据 |
| --- | --- | --- | --- |
| P1 | 文件内容原位改写后，大小、inode 和 mtime 被保留，重复文件扫描继续使用旧完整哈希，可能把不同内容列为重复文件。 | 哈希缓存加入 ctime，版本升为 2；复用缓存、完成哈希、汇总结果时核验文件快照。 | 先用原代码复现：改写文件中间一个字节并恢复 mtime 后仍报告重复。修复后测试通过，且只重算变化文件。 |
| P2 | 停止额度监控后，宿主/目录/插件包的 Combine 订阅仍存活；后续事件能再次启动监控，重启又会增加订阅。 | 停止时清除订阅；通过生命周期标识丢弃已经排入主队列的旧回调。 | 回归覆盖停止后事件、停止前排队事件、连续 3 轮重新订阅，确认没有旧回调或倍增回调。 |
| P2 | 旧版 BetterTouchTool 控件迁移在主线程调用 `waitUntilExit`，无超时；AppleScript 应用 ID 的引号也被过度转义。 | 改为后台任务；AppleScript 限时 5 秒，单个辅助进程限时 8 秒；停用插件会取消迁移，超时终止辅助进程；修复脚本文字。 | 使用隔离的 sleep/true/false 进程验证取消、超时和退出码；10 秒 sleep 在约 0.11 秒被测试预算中止。未操作用户真实 BTT 控件。 |
| P2 | 重复文件扫描的 25 秒预算只在文件之间检查，单个大文件的完整哈希可以一直读到文件尾。 | 使用单调时钟，并在每个 1 MiB 读取块前检查预算与取消；超时返回不完整扫描标志，不缓存半成品哈希。 | 覆盖块间预算耗尽、零预算截断、不生成部分摘要。 |
| P2 | 硬链接在完整哈希后才按 inode 去重，同一数据可能重复读盘。 | 在快速指纹和完整哈希之前按文件系统/inode 去重。 | 同一夹具原代码完整哈希 3 次，修复后 2 次；仍正确排除硬链接，不改变重复组数量。 |

## 验证

- `DiskCleanPluginTests`：**436 项通过，0 失败**，包括新的重复文件回归。
- `QuotaMonitorPluginTests`：**5 项通过，0 失败**，包括原有额度解析/连续性自检集合。
- `scripts/verify_scan_rules.py`：**46 条唯一扫描规则通过**。
- DiskClean 与 Quota Monitor 的 Debug 测试构建通过。
- 宿主 Debug 构建：**BUILD SUCCEEDED**（arm64，`CODE_SIGNING_ALLOWED=NO`）。
- `git diff --check` 通过。

测试构建使用 `xcodebuild build-for-testing`，测试执行使用 `xcrun xctest` 直接运行已构建的 XCTest bundle。本机 `xcodebuild test` 的 runner 报测试包加载失败，但相同 bundle 可由 `xcrun xctest` 正常加载执行。未把 runner 错误计作产品测试失败或跳过测试。

DiskClean 聚合测试目标原本就排除了 `DiskCleanWorkerPoolTests.swift`：项目注释记录了 Xcode 26.6 的 region-isolation 编译器错误。本轮没有修改这一既有排除项。441 项通过不代表这些排除项或整个宿主的所有功能已经验收。

复现命令（在对应源码目录执行）：

```bash
# ThirdParty/MacTools
make generate
xcodebuild -project MacTools.xcodeproj -scheme DiskCleanPluginTests \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/ReviewDerivedData -jobs 2 \
  CODE_SIGNING_ALLOWED=NO build-for-testing
xcrun xctest build/ReviewDerivedData/Build/Products/Debug/DiskCleanPluginTests.xctest

# TraceFencePlugins
xcodegen generate
xcodebuild -project TraceFenceCodexPlugins.xcodeproj -scheme QuotaMonitorPlugin \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ../build/QuotaReviewDerivedData -jobs 2 \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build-for-testing
xcrun xctest ../build/QuotaReviewDerivedData/Build/Products/Debug/QuotaMonitorPluginTests.xctest

# 仓库根目录
xcodebuild -project AIMacCleaner.xcodeproj -scheme AIMacCleaner \
  -configuration Debug -sdk macosx -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/HostReviewDerivedData -jobs 2 \
  CODE_SIGNING_ALLOWED=NO build
python3 scripts/verify_scan_rules.py
```

## 交付边界

这些是已验证的源码修复。本轮未安装或启动宿主 UI，未签名、公证、修改线上目录或发布新版；真实 Touch Bar/BTT 迁移、真实账号长期采样仍需安装候选版本后的交互验收。宿主版本由打包参数覆盖，源码默认版本号不能单独证明公开 DMG 的构建身份。

哈希缓存升级会淘汰旧派生缓存，下一次扫描需要重新计算哈希；不会删除原始文件。扫描预算在块之间生效，不能抢占操作系统内部的一次阻塞读操作。本轮未声称整体 CPU、内存或扫描速度达到某个百分比改善。

编译器仍报告共享额度读取器已有的并发捕获警告及旧 SwiftUI API 弃用警告。对应读取器当前使用锁和 DispatchGroup/信号量同步；本轮未据此声称已经复现数据竞争，也未扩大到整个项目的 Swift 6 迁移。

本地验证日志保存在 `build/review-evidence/`，不随源码发布。

后续交付：用户授权发布后，已发布宿主 1.2.19 (140)、Quota Monitor 1.0.15、Disk Cleanup 3.5.1。详见 [正式发布记录](releases/1.2.19.md)。
