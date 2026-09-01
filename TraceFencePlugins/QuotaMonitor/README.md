# TraceFence Quota Monitor

这是独立的额度监控插件。额度读取、前台 Agent 识别、手动切换和 Touch Bar 渲染都由插件自身完成；
它不修改 TraceFence 的菜单栏、任务栏、窗口布局或发布包。

## 原生 Touch Bar

`1.0.9` 在插件内注册原生 Touch Bar 主显示区，不依赖 BetterTouchTool、Node、Shell Script
Widget 或自动化权限。额度条固定在左侧主区域，不会藏进右侧键盘 / Control Strip；它只显示一个 Agent，
而不是把所有 Provider 合并成一条红色长条：

`‹  CX  ›  ↺  5h [油量] 72%  周 [油量] 44%  ×`

- `CX`、`CL`、`GR` 等是当前 Agent 的明确缩写；前台 Agent 改变时默认自动跟随。
- `‹` 和 `›` 切换上一个或下一个 Agent，切换后进入手动查看状态。
- `↺` 立即恢复自动跟随前台 Agent。
- `×` 立即隐藏并记住关闭状态；可在额度监控插件面板重新显示。
- `5h`、`周`各有独立会缩短的油量条：低于 20% 红色、20–49% 橙色、50–69% 黄色、70% 及以上绿色。

升级自 `1.0.8` 且仍有旧 BTT 控件时，插件会尝试做一次清理；若系统不允许该迁移，插件面板会显示
“清理旧版”操作。它只会删除此插件曾写入且仍记录在本机状态文件中的 UUID，不读取、更改或导出
用户的其他 BTT 自动化规则。日常运行完全不需要 BTT。

## 边界

- 不改变 TraceFence 宿主的菜单栏、任务栏、窗口或 DMG。
- 额度读取仅在本机进行，凭据和原始响应不上传。
- 插件内置并显式调用自己的 `codexbar` Helper；官网版宿主不再携带该 Helper。
- App Store 渠道暂时保留原有内置实现，不安装可下载代码。

## 发布

插件包使用 TraceFence Developer ID 对 Helper 和内层 `.bundle` 分层签名，并发布到独立、
不可变的 GitHub Release。公开商城目录记录版本、下载地址、大小和 SHA-256。
