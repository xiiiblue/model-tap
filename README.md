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
- API Key 只保存于 macOS Keychain；SwiftData 仅保存随机 Keychain 引用标识。
- 应用不会上传遥测、同步数据或请求无关权限。
- 日志和错误展示不输出 Authorization 请求头；配置编辑器默认隐藏密钥，用户可手动切换明文显示。
- 本地重新构建的临时签名App首次读取已有API Key时，macOS可能弹出钥匙串授权；授权成功后应用会自动重试并继续原操作。正式发布应使用稳定的Developer ID签名，避免每次构建因`cdhash`变化而重新授权。
- 示例数据使用虚构地址和密钥，不包含真实凭据。

## 已实现

- 配置新增、编辑、删除、复制。
- 配置级 API 格式选择：OpenAI Chat Completions、OpenAI Responses、Anthropic Messages。
- Base URL 规范化，并保留用户实际 API 前缀；可直接填写`/models`、`/chat/completions`、`/responses`或`/messages`完整地址。
- 按所选格式查询`/models`、模型搜索、复制模型 ID；Anthropic 使用`x-api-key`与`anthropic-version`请求头。
- 按所选格式测试模型：OpenAI Chat Completions、OpenAI Responses或Anthropic Messages；不再自动切换协议。
- 单模型与串行批量测试、取消、进度和结果详情。
- 最近 100 条测试记录限制。
- XCTest 覆盖 URL、解析、错误映射、Keychain 模拟和批量执行。

## 已知限制

第一阶段不包含流式聊天、并发压测、价格统计、其他专用协议、自定义请求头、云同步和自动更新。真实接口测试需要用户自行配置服务地址；Preview 和 XCTest 不依赖真实 API。
