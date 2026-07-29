# ModelTap（模探）

> 一键发现、验证和管理 LLM API。

ModelTap 是一款使用 SwiftUI 编写的 macOS 原生工具，用于发现、测试和管理 LLM API。最低支持 macOS 14。

## 运行

使用 Xcode 26 或更高版本打开 `ModelTap.xcodeproj`，选择 `ModelTap` scheme 后运行。也可以使用命令行：

```bash
xcodebuild -project ModelTap.xcodeproj -scheme ModelTap -configuration Debug -sdk macosx build
xcodebuild -project ModelTap.xcodeproj -scheme ModelTapTests -configuration Debug -sdk macosx test
```

## 数据与安全

- 配置名称、Base URL、备注、时间和测试记录保存在 SwiftData 本地存储。
- API Key使用AES-GCM加密后保存于SwiftData，加密密钥单独保存在`~/Library/Application Support/ModelTap/local-encryption.key`并限制为当前用户读写。
- 应用不再访问macOS Keychain；从旧版升级后需要重新填写一次API Key，旧Keychain条目不会被应用主动读取或删除。
- 应用不会上传遥测、同步数据或请求无关权限。
- 日志和错误展示不输出 Authorization 请求头；配置编辑器默认隐藏密钥，用户可手动切换明文显示。
- 这种本地加密主要避免数据库中出现API Key明文；能读取当前用户应用数据的攻击者仍可能同时取得密文和加密密钥，其安全性低于macOS Keychain。
- 示例数据使用虚构地址和密钥，不包含真实凭据。

## 已实现

- 配置新增、编辑、删除、复制，并支持文件夹管理；文件夹可新建、重命名、删除和展开收起，配置可通过右键菜单或拖放移动，未归档配置显示在“未分类”。
- 配置级 API 格式选择：OpenAI Chat Completions、OpenAI Responses、Anthropic Messages。
- Base URL 规范化，并保留用户实际 API 前缀；可直接填写`/models`、`/chat/completions`、`/responses`或`/messages`完整地址。
- 按所选格式查询`/models`、模型搜索、复制模型 ID；Anthropic 使用`x-api-key`与`anthropic-version`请求头。
- 按所选格式测试模型：OpenAI Chat Completions、OpenAI Responses或Anthropic Messages；不再自动切换协议。
- 单模型与串行批量测试、取消、进度和结果详情。
- 最近 100 条测试记录限制。
- XCTest覆盖URL、解析、错误映射、本地加密和批量执行。

## 已知限制

第一阶段不包含流式聊天、并发压测、价格统计、其他专用协议、自定义请求头、云同步和自动更新。真实接口测试需要用户自行配置服务地址；Preview 和 XCTest 不依赖真实 API。

## 全量导入导出

窗口右侧工具栏的导入导出菜单支持Markdown全量备份。备份按文件夹使用二级标题分组，配置使用三级标题展示，并以可点击链接显示Base URL，API格式、API Key和多行备注均为适合直接放入Obsidian阅读的普通Markdown。测试历史放在独立章节，内部ID和时间戳使用阅读视图不可见的HTML注释保存，确保导入时可以完整还原。导入前会校验文件并显示数据数量，确认后完整替换当前数据；旧版单行JSON格式仍可导入。

Markdown备份中的API Key为明文，仅用于用户主动迁移和备份。请妥善保管备份文件，不要提交到公开仓库或发送给不受信任的第三方。
