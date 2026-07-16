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
| Codex / Claude Runtime 切换 | 并入 | 为用量洞察提供 Codex、Claude、合计三个口径 |
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
- Codex 与 Claude 缓存必须版本化、有界、原子写入并使用仅当前用户可读权限。
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
