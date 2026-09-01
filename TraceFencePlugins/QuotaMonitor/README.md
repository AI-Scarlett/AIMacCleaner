# TraceFence Quota Monitor

这是 TraceFence 官网版的独立额度监控插件。宿主继续拥有并渲染原有菜单栏界面，插件读取
Codex、Claude、Grok 等 Provider 的额度、重置时间与诊断结果。因此插件未安装时不会启动
额度读取进程；安装后 Provider 适配器可以独立于 TraceFence 主程序更新。

## 当前 Agent 额度

- 默认不依赖 BetterTouchTool，也不会请求自动化权限。
- 默认显示前台 Agent 的 `5h` 与 `周`剩余额度；没有前台匹配时保留最近的可用 Agent。
- 在额度监控面板可查看上一个/下一个 Agent，随后随时恢复自动跟随。
- 5h 和周额度各是一条会缩短的“油量条”：填充部分表示仍可使用的额度，暗色部分表示已消耗；菜单栏本体以双轨微型油量计同时显示这两项。
- 剩余额度统一分级：低于 20% 为红色、20–49% 为橙色、50–69% 为黄色、70% 及以上为绿色；颜色和条的长度表达同一份余量，悬停可查看精确百分比。
- BetterTouchTool 仅是可选的 Touch Bar 渲染器：用户明确启用后，插件才创建自己拥有的三个控件
  （上一个、当前额度/恢复自动、下一个），并且只更新这三个控件。

macOS 没有公开 API 可以在其它 Agent 位于前台时让 TraceFence 的原生 Touch Bar 常驻。为避免
macOS 26 上已确认的渲染损坏，插件不会使用私有 Control Strip API；未安装 BetterTouchTool 时，
自动跟随和手动切换仍在 TraceFence 的菜单栏额度面板中完整可用。

`1.0.8` 要求 TraceFence `1.2.18` 或更高版本，以确保宿主菜单栏使用单 Agent 卡片、双轨油量计和同一套颜色规则。

## 边界

- 不改变任务栏弹窗尺寸、圆角、标签页和额度卡片布局。
- 插件缺失时，原额度区域显示前往插件商城的安装入口。
- 额度读取仅在本机进行，凭据和原始响应不上传。
- 插件内置并显式调用自己的 `codexbar` Helper；官网版宿主不再携带该 Helper。
- App Store 渠道暂时保留原有内置实现，不安装可下载代码。
- 旧版 BTT Shell Script Widget 仅为已安装用户的兼容路径；新功能不要求安装 Node、复制脚本或
  在 BetterTouchTool 中手工创建组件。

## 发布

插件包使用 TraceFence Developer ID 对 Helper 和内层 `.bundle` 分层签名，并发布到独立、
不可变的 GitHub Release。公开商城目录记录版本、下载地址、大小和 SHA-256。
