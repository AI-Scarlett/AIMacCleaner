# TraceFence Codex Media Cleanup

这是一个 **TraceFence PluginKit 4** 原生插件。Codex 只是被扫描的数据源；插件不安装到
`~/.codex/plugins`，也不依赖 Codex skill 或 Codex 会话继续运行。

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
tracefence.codex-media-cleanup.mactoolsplugin/
  plugin.json
  CodexMediaCleanup.bundle/
```

清单声明 `pluginKitVersion: 4`、工厂类、功能面板和 workspace 设置页。发布包须使用
TraceFence 团队的 Developer ID 签名，并由 TraceFence 商城目录记录不可变 GitHub URL、大小和 SHA-256。

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
  --plugin tracefence.codex-media-cleanup
```
