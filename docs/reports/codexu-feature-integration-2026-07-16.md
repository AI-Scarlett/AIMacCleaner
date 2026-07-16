# codexU 非皮肤功能并入 TraceFence

日期：2026-07-16
上游：[shanggqm/codexU](https://github.com/shanggqm/codexU)
审计提交：`79511836b3e9c1d6d5b189c4e769b4f6df743c52`（v1.1.0 之后仅截图更新）
许可证：MIT，Copyright (c) 2026 Guomeiqing

## 范围

并入上游当前 `main` 已存在的非皮肤能力。明确排除配色包、主题图库、Liquid Glass 装饰、SVG 图案、粒子动画、上游 Logo 和品牌资源。

未合并的 PR 不视为上游现有功能：Team 月额度（#28）、CPA/CLI Proxy API 账号池（#27）、OpenClaw/Hermes/系统监控（#30）。

## 功能决策矩阵

| 上游能力 | TraceFence 决策 | 原因 |
| --- | --- | --- |
| 可信 Runtime 切换 | 并入并扩展 | 提供 Codex、Claude Code、OpenCode / MiniMax、OpenClaw / QClaw 与合计口径 |
| Codex 5h / 7d 额度 | 保留 TraceFence | 现有 `ProviderQuotaService` 支持更多 Provider、多账号和多来源 |
| 精确额度窗口分类 | 改进 TraceFence | Codex 按 300 / 10080 分钟严格识别，未知或重复窗口 fail-closed |
| 额度 stale 连续性 | 并入 | 临时失败保留 last-known-good，并明确标记陈旧 |
| reset credits 与到期详情 | 保留 TraceFence | 现有 UI 和模型已覆盖，并支持多账号/Spark extra windows |
| Claude 额度 | 保留 TraceFence | 现有 helper 可直接读 Provider；不采用上游不完整的外部 snapshot 链 |
| 今日/7日/月/累计 Token | 并入并重写 | 使用本机 SQLite 与授权 transcript，统一统计口径 |
| input/cache/output/reasoning 拆分 | 并入 | 采用高水位和 `last_token_usage` 优先的归一化算法 |
| API 等效价值/订阅里程碑 | 并入 | 明确标注为估算，不冒充账单或返现 |
| 180 日热力图 | 并入 | 补齐长期用量结构观察 |
| 最近 7 日趋势与前周期对比 | 并入 | 显示总量、日均、峰值和环比 |
| 项目 7 日/全部排行 | 并入 | 展示 token、估算价值、线程数、最近活跃 |
| 工具调用 TOP | 并入 | 调用次数为记录值，分摊 token/价值必须标“估算” |
| Skill TOP | 并入并收紧路径 | 只读取允许根目录下的 `SKILL.md`，不保存工具参数正文 |
| 今日任务四列 | 并入为补全层 | SQLite/automation/Claude task 补全现有 Agent Center，不替换控制与审批能力 |
| 三档菜单栏密度 | 并入语义 | 简约/经典/丰富、已用/剩余、指标选择；沿用 TraceFence 视觉 |
| Runtime 菜单卡片 | 并入 | 加入现有 520px 多页 popover，不替换捕获/产物/操作页 |
| 统计时区 | 并入 | 支持系统、UTC、固定 IANA，统一日界线和 DST |
| 刷新队列与旧数据保留 | 并入 | 前台 5 分钟、后台 15 分钟；重复刷新合并，失败不清空结果 |
| 数据源诊断 | 并入并结构化 | 显示 loading/partial/stale/failure、最后成功时间和授权建议 |
| 标准窗口/关闭后驻留 | 保留 TraceFence | 已有 Dock、关闭行为、菜单栏驻留和恢复 |
| 可自定义全局快捷键 | 改进 TraceFence | 保留四种动作，补危险组合、重复、冲突和注册回滚 |
| 中英文与外观 | 保留 TraceFence | 现有多语言和外观体系覆盖更广；皮肤不并入 |
| GitHub 更新检查 | 保留 TraceFence | 现有更新器有 SHA、签名、bundle/version 验证及自动安装 |
| JSON 探针/导出 | 并入 | 用户显式导出，默认脱敏路径、标题和会话 ID |

## 安全与性能边界

- 不读取 `~/.codex/auth.json`，不保存 prompt、回复正文、工具参数或工具输出。
- 不启动外部 `codex`、`sqlite3` 或 `grep`；SQLite 使用链接库，JSONL 使用流式逐行解析。
- SQLite 提供的 `rollout_path` 必须标准化并限制在已授权的 `~/.codex` 根目录内。
- App Store 包只使用用户选择目录和 security-scoped bookmarks；无授权时提供明确入口。
- 各可信来源的派生缓存必须版本化、有界、原子写入并使用仅当前用户可读权限。
- 缓存只保留聚合指标、时间、来源和散列标识；导出默认脱敏。
- Provider 并发读取，单个 Runtime 失败不阻塞或清空其它 Runtime。
- 首次回填有界，后续按文件指纹/游标增量读取；界面始终显示读取状态。
- 会话产物目录只呈现用户级 task：Codex 子 Agent 线程回收到父任务语义，adapter/core 别名按原生 thread ID 合并；只有同项目、同 Agent、完全相同的长提示词克隆会折叠，短标题不会猜测性去重。

## 验收门禁

- token 累计缺字段、临时回退、重复事件和真正 reset 的纯函数回归。
- 额度单窗口、反序、重复、未知窗口和 stale continuity 回归。
- 系统/UTC/固定时区、跨日和 DST 回归。
- 损坏 JSON、损坏 SQLite、越界/symlink 路径和超大文件不会读取越权或清空旧数据。
- 缓存和 JSON 导出不含 prompt、凭据、工具正文或未脱敏的会话标识。
- Debug、官网 Developer ID 包和 App Store sandbox 三种构建路径通过。

## 2026-07-16 信息架构收口

- “Token 统计”与“用量洞察”已合并为唯一的“Token 与用量”入口；概览、菜单栏和该页面共用 `AgentUsageInsightsService`。
- 旧 TokenScope 独立扫描器及其不同文件上限、时间范围和 Token 相加规则已移除；模型、最近会话和来源状态改由统一快照生成。
- 项目排行和任务板迁入 Agent 监控。现有项目看板按标准化完整路径吸收 7 天/全部时间 Token、API 等值、用量会话与任务，纯历史项目进入“最近完成”。
- 概览固定读取 `.combined` 的全部时间快照，并明确标注“全部可信 Agent · 全部时间 Token”；Token 页面切换来源筛选不会改变概览。
- 修复普通扫描授权根被注入每一个 Agent 类型的问题，并将 Agent Monitor 缓存升级为 v2；旧 v1 污染缓存和旧 TokenScope 派生缓存会删除，用户目录授权书签保留。
- 全历史汇总只提供 `total` 时，页面保留可信累计值，同时将已解析明细与“历史未拆分”分层展示；缓存输入、非缓存输入、普通输出和推理输出改为互斥分项，任何一层都可对账。
- OpenCode / MiniMax 使用各自 SQLite 原生字段并按 `turn_id` 与 `message.id` 跨库去重；OpenClaw / QClaw 只读取 assistant `message.usage`，按原生事件 ID 去重。
- 可信来源必须同时具备原生 Token 分项、稳定事件 ID、真实时间戳和可核对总量。Cursor、Trae、CodeBuddy、Qoder 等缺少这些字段时仅保留在 Agent 监控，不进入 Token 总量。
- DEBUG 真实数据探针输出每个来源的总量、明细量和事件数；OpenCode / MiniMax 与 OpenClaw / QClaw 的本机汇总已分别和源库独立查询对账，零用量记录不记为异常。
