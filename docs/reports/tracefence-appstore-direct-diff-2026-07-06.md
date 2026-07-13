# TraceFence 上架包与官网包差异分析报告

日期：2026-07-06

## 结论摘要

这不是一个简单的 UI 未同步问题。当前“官网包”和“上架/TestFlight 包”已经是两条发行线：

- 官网包：`com.tracefence.app`，版本 `1.0.38` build `38`，Developer ID / 直发路线，非 App Sandbox，保留 Lemon Squeezy 购买、GitHub Release 更新、DMG 打包和更宽的本地读取能力。
- 上架包：`com.aimaccleaner.app`，版本 `3.1.6` build `61`，App Store / TestFlight 路线，启用 `com.apple.security.app-sandbox`，删除直发购买和自更新，新增 App Store workflow、sandbox helper 和 App Store Connect 提交流程。

Spark 额度缺失有两个层次：

1. UI 层 bug：早先上架包把 Codex Spark 拆成了单独卡片，并显示授权提示；这已经在 build 61 源码中修掉，Spark 不再被单独拆卡。
2. 运行环境层限制：上架包主 app 和 helper 都在 sandbox 策略下运行，不能等同于官网包在普通用户 HOME 环境里读取 Codex 数据。实测官网包 helper 能读出 `Codex Spark 5-hour` 和 `Codex Spark Weekly`，而上架包内的 `codexbar` / `CodexBarHelper.app` 在 Terminal 直接运行返回 `-5`，无 JSON 输出。所以上架包即使抄了官网 UI 和 reader 逻辑，也可能拿不到 Spark 数据。

## 本次已合并的共享修复

我没有做粗暴的分支覆盖，而是把上架包里适合两条线共享的 quota 读取改动合回官网分支：

- `AIMacCleaner/Services/ProviderQuotaService.swift`
  - 合并 helper 进程退出诊断：区分超时、非正常退出、正常退出但无输出。
  - 合并真实 HOME 路径展开：`~/.codex` 等路径使用 `SandboxPaths.realHomeDirectory`，避免 sandbox/container HOME 干扰。
  - 将登录会话缺失提示从“给完全磁盘访问权限”调整为“在 TraceFence 中授权对应数据目录”，更贴近两条发行线共同的授权模型。
- `AIMacCleaner/MenuBarMonitor.swift`
  - 增加空错误字符串兜底，避免 helper 没输出时 UI 静默。
  - 增加“额度监控引擎启动失败，请更新或重新安装 TraceFence。”本地化。
  - 同步 Cursor / Provider 登录会话缺失的授权提示。

校验结果：`xcodebuild -project AIMacCleaner.xcodeproj -scheme AIMacCleaner -configuration Debug CODE_SIGNING_ALLOWED=NO build` 通过，仅剩既有 Swift 6 `Sendable` warning。

## 分支和代码差异

对比基准：

- 官网分支：`codex/direct-download-payments-research`，HEAD `f997193`。
- 上架分支：`codex/appstore-tracefence-brand`，HEAD `6c42891`，本地 ahead 4。

分支级 diff：`42 files changed, 2562 insertions(+), 6458 deletions(-)`。主要不是一两个 quota 文件，而是发行模式整体不同。

关键差异：

| 领域 | 官网包分支 | 上架包分支 | 差异原因 |
| --- | --- | --- | --- |
| Bundle ID | `com.tracefence.app` | `com.aimaccleaner.app` | 官网直发和 App Store 历史包使用不同应用身份，不能随意统一，否则影响更新、签名、App Store 记录。 |
| 版本线 | `1.0.38` build `38` | `3.1.6` build `61` | 官网按 GitHub Release/DMG 走直发版本；上架包沿 App Store 版本线走。 |
| Sandbox | 无 `com.apple.security.app-sandbox` | 主 app 和 helper 都启用 sandbox | App Store 上架必须走 sandbox/entitlement 合规路线。 |
| helper | `Contents/Resources/codexbar` | `Contents/Resources/codexbar` + `Contents/Helpers/CodexBarHelper.app` | 上架包需要额外 helper 包装、签名、entitlement 和 dSYM；官网包可直接放 resource helper。 |
| 支付 | `DirectLicenseService.swift` + Lemon Squeezy checkout | 删除直发支付服务 | App Store 不应内置外部购买解锁链路。 |
| 更新 | `DirectUpdateService.swift` + GitHub Release manifest | 删除自更新服务 | App Store 包不能走自更新下载替换 app。 |
| 打包 | `scripts/build_tracefence_dmg.sh`、`upload_dmg.py` | `.github/workflows/appstore-release.yml`、`scripts/build_codexbar_helper.sh` | 官网是 Developer ID notarized DMG；上架是 archive/export/upload ASC。 |
| quota 文案 | 可强调本地 provider API / 官网完整能力 | 更强调用户授权数据目录 | App Store sandbox 不能承诺无授权读取本地私有数据。 |
| Spark UI | Spark 窗口在 Codex 卡片里展示 | build 60 曾拆成独立卡；build 61 已改回不拆卡 | 这是 UI 合并遗漏，已修源码，但不等于突破 sandbox 数据可见性。 |

## 已安装包实测差异

本机已安装包检测：

| 项目 | 官网包 | 上架/TestFlight 包 |
| --- | --- | --- |
| 路径 | `/Applications/TraceFence.app` | `/Applications/TraceFence.localized/TraceFence.app` |
| Bundle ID | `com.tracefence.app` | `com.aimaccleaner.app` |
| 版本 | `1.0.38` build `38` | `3.1.6` build `61` |
| sandbox entitlement | 无 | 有 `com.apple.security.app-sandbox = true` |
| helper 文件 | `Contents/Resources/codexbar` | `Contents/Resources/codexbar` 和 `Contents/Helpers/CodexBarHelper.app` |
| helper 终端测试 | 能输出 Codex Spark 窗口 | resource/helper 都返回 `-5`，无 JSON 输出 |

官网 helper 输出摘要：

```text
provider=codex
source=oauth
account=zhou76462245@gmail.com
extra=["Codex Spark 5-hour", "Codex Spark Weekly"]
```

上架包 helper 输出摘要：

```text
returncode=-5
stdout=""
stderr=""
```

这说明官网包能展示 Spark 的直接原因是 helper 在非 sandbox 直发环境下能读到包含 Spark 的 Codex quota payload；上架包缺失 Spark 的核心原因不是 SwiftUI 没画，而是上架包运行环境读不到同一份完整 payload。

## 为什么两边 UI 也不一样

图一和图二 UI 不一致，原因有三类：

1. 发行线分叉后，UI 改动没有双向同步。上架分支早先为了处理 Spark 数据不可读，额外插入了 “Codex Spark 需要 Codex 数据目录授权” 的 setup notice，导致 Spark 变成独立卡片。
2. 上架包必须用更保守的文案。官网包可以说“使用官方 provider API 读取”；上架包更需要提示“用户授权的本地 Agent 状态/数据目录授权”，否则和 sandbox 行为不一致。
3. build 60 之前只是把数据失败包装成 UI 提示，没有真正解决数据源差异。build 61 已经把“拆 Spark 卡片”的 UI 逻辑移除，但 sandbox 读取能力仍然不同。

## Spark 缺失根因

根因链路如下：

1. `ProviderQuotaService` 调用 `codexbar usage --provider codex --format json --source auto --all-accounts`。
2. `codexbar` 会尝试合并 auto / oauth / web source，Spark 额度来自额外的 `extraRateWindows`。
3. 官网包的 helper 在普通用户 HOME 环境下执行，能够访问所需 Codex 登录/缓存数据，因此返回 `Codex Spark 5-hour` 和 `Codex Spark Weekly`。
4. 上架包是 sandbox app。即使代码把 HOME 设置为真实用户目录、也尝试恢复 security-scoped bookmark，子进程依旧受 app sandbox、签名和可访问文件范围影响。
5. 上架包内 helper 实测 `returncode=-5`，没有 stdout/stderr，这与“helper 在上架签名/运行环境下被系统中止或触发运行时保护”一致。
6. 因此，照抄官网包 UI 和 provider 合并逻辑，只能修掉“分开展示”的 UI 问题，不能保证上架包读取到 Spark 窗口。

## 为什么不能直接全量抄官网包

不能把官网分支全量覆盖到上架分支，原因很具体：

- 官网分支包含 `DirectLicenseService`、`DirectUpdateService`、Lemon Squeezy checkout 和 GitHub Release 自更新，这些不适合 App Store 包。
- 官网分支没有 App Sandbox entitlement；上架包如果取消 sandbox，无法按当前 App Store 合规路径提交。
- 上架分支有 App Store workflow、build number 注入、helper entitlements、`CodexBarHelper.app` 构建脚本，这些官网包不需要，强行合并会污染直发包。
- 两边 Bundle ID 和版本线不同，粗暴统一会破坏用户升级链路、ASC 版本记录或直发更新 manifest。

## 建议的后续处理

短期：

- 上架包里把 Spark 作为 best effort：如果 payload 有 `extraRateWindows` 就显示在 Codex 卡片内；如果没有，不再插入单独 Spark 授权卡。
- 上架包文案不要承诺一定显示 Spark，避免用户看到官网包/上架包能力差异后认为 UI 坏了。
- 给 quota reader 加一条内部诊断日志：记录 helper return code、termination reason、stdout/stderr 长度，不记录账号 token 或原始 cookie。

中期：

- 把 quota provider 合并逻辑抽成共享模块，两个 target 只保留 `DistributionCapabilities` 差异，例如：
  - `canUseExternalPurchase`
  - `canSelfUpdate`
  - `isAppStoreSandboxed`
  - `canUseDirectDistributionCodexBar`
- 建立 UI 截图回归：至少比较 Codex 主卡是否包含 primary/secondary/extra windows，避免再次把 Spark 拆成独立 setup 卡。
- 上架线继续保留 sandbox helper；官网线继续保留直发 helper，不要互相覆盖。

长期：

- 如果必须让 App Store 包也稳定显示 Spark，需要把 Spark 所需数据源改造成 App Store sandbox 可授权读取的明确目录或官方 API，而不是依赖 helper 在用户 HOME 里自由扫数据。
- 如果 Apple sandbox 无法授权到对应私有数据，就应把 Spark 能力作为官网包专属能力处理。

## 当前状态

- 共享 quota 修复已合入官网工作区源码。
- 上架包 build 61 源码已修复“Spark 独立卡片”UI 逻辑，但已安装上架包仍受 sandbox/helper 运行限制。
- 本次没有提交 git commit，也没有重新上传 build 62；报告只反映当前本地源码和本机已安装包状态。

