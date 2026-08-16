# TraceFence Quota Monitor

这是 TraceFence 官网版的独立额度监控插件。宿主继续拥有并渲染原有任务栏弹窗，插件只负责
读取 Codex、Claude、Grok 等 Provider 的额度、重置时间与诊断结果。因此插件未安装时不会
启动额度读取进程；安装后 Provider 适配器可以独立于 TraceFence 主程序更新。

## 边界

- 不改变任务栏弹窗尺寸、圆角、标签页和额度卡片布局。
- 插件缺失时，原额度区域显示前往插件商城的安装入口。
- 额度读取仅在本机进行，凭据和原始响应不上传。
- 插件内置并显式调用自己的 `codexbar` Helper；官网版宿主不再携带该 Helper。
- App Store 渠道暂时保留原有内置实现，不安装可下载代码。

## 发布

插件包使用 TraceFence Developer ID 对 Helper 和内层 `.bundle` 分层签名，并发布到独立、
不可变的 GitHub Release。公开商城目录记录版本、下载地址、大小和 SHA-256。
