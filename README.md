# ModelTap（模探）

> 一键发现、验证和管理 LLM API。

ModelTap 是一款使用 SwiftUI 编写的 macOS 原生工具，用于发现、测试和管理 OpenAI 兼容的 LLM API。最低支持 macOS 14。

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
- 日志和错误展示不输出 Authorization 请求头；UI 需要展示密钥时使用脱敏格式。
- 示例数据使用虚构地址和密钥，不包含真实凭据。

## 已实现

- 配置新增、编辑、删除、复制。
- Base URL 规范化，并保留用户实际 API 前缀。
- `/models` 查询、模型搜索、复制模型 ID。
- Chat Completions 测试及明确不支持时的 Responses API 回退。
- 单模型与串行批量测试、取消、进度和结果详情。
- 最近 100 条测试记录限制。
- XCTest 覆盖 URL、解析、错误映射、Keychain 模拟和批量执行。

## 已知限制

第一阶段不包含流式聊天、并发压测、价格统计、专用协议、自定义请求头、云同步和自动更新。真实接口测试需要用户自行配置服务地址；Preview 和 XCTest 不依赖真实 API。
