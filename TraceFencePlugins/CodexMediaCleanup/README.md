# TraceFence Codex Media Cleanup

这是一个 **TraceFence PluginKit 4** 原生插件。Codex 只是被扫描的数据源；插件不安装到
`~/.codex/plugins`，也不依赖 Codex skill 或 Codex 会话继续运行。

## 功能与工作流

- **扫描**：只读分析重复媒体、副本数量、预计可释放空间和无效 `image_url`。
- **清理**：只外置已被 compaction 取代的重复副本和非模型事件副本，降低会话文件占用。
- **修复**：只修复有效历史中的无效 `file://` 图片引用，避免
  `Invalid 'input[51].content[2].image_url'. Expected a valid URL, but got a value with an invalid format.`。
- **清理并修复**：在同一次安全事务中完成前两项。
- 每个阶段在页面显示文件级进度和带时间戳日志。
- 写入阶段由独立、低优先级工作进程逐文件执行。单个异常或超大会话即使触发系统内存限制，
  也只会安全跳过该文件，不会再终止 TraceFence 主程序。
- **修复备份管理**：后台统计每个回滚批次的物理占用、文件数和报告状态；默认不选择，用户确认
  历史对话正常后可逐批或批量永久删除。删除范围被限制在插件自己的 `Backups` 一级目录，
  不会触碰当前 Codex 会话和媒体对象。
- 单条 JSONL 记录的安全上限为 64MB；超限记录不会解析或改写，并会在扫描/运行报告中标记。
- 写入前提示用户暂停所有 Codex 任务并完全退出客户端；完成后必须重新启动 Codex，并打开包含图片的历史对话验证图片显示和继续发送消息。

## 安全模型

- 扫描始终只读。
- 当前有效模型历史中的图片继续保留 API 可接受的 `data:image/...;base64`。
- 仅把已被最后一次 compaction 取代的历史副本和非模型事件副本改为 SHA-256 内容寻址文件。
- 如果有效历史中已有 `file://.../.codex/media_objects/...`，会从已校验的原始文件恢复 Base64，避免
  `Expected a valid URL`。
- 写入前等待 ChatGPT/Codex 进程退出，并再次检查目标 JSONL 没有打开句柄。
- 每个被修改的 JSONL 都先建立可校验备份，再同目录原子替换；运行报告保存在插件支持目录。
- 不联网、不上传会话文本、不删除原始媒体对象。

## 包格式

构建产物遵循 TraceFence 当前采用的 `.mactoolsplugin` 目录协议：

```text
codex-media-cleanup.mactoolsplugin/
  plugin.json
  CodexMediaCleanup.bundle/
    Contents/Resources/Helpers/TraceFenceCodexMediaWorker
```

清单声明 `pluginKitVersion: 4`、工厂类、功能面板和 workspace 设置页。发布包须使用
TraceFence 团队的 Developer ID 对工作进程和外层 bundle 分层签名，并由 TraceFence 商城目录记录
不可变 GitHub URL、大小和 SHA-256。

这是 TraceFence 自研插件，不从 MacTools 仓库下载代码或运行时资源。它只在桌面端“我的插件”工作台
显示，不占用概览和任务栏插件页；商城分类为收费插件，TraceFence 全插件订阅包含使用权。

## 本地构建

先在 MacCleaner 私有工作区生成并测试独立插件工程：

```bash
cd TraceFencePlugins
xcodegen generate
xcodebuild -project TraceFenceCodexPlugins.xcodeproj \
  -scheme CodexMediaCleanupPlugin -configuration Debug test
```

再回到工作区根目录，使用固定的 TraceFence 插件打包脚本：

```bash
cd ..
ThirdParty/MacTools/scripts/plugins/build-local-plugins.sh \
  --source-dir TraceFencePlugins \
  --output-dir TraceFencePlugins/build/CodexMediaCleanupPlugin \
  --plugin codex-media-cleanup
```
