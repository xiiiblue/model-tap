# ModelTap

ModelTap是一款使用SwiftUI和SwiftData编写的macOS原生LLM API管理工具，用于集中保存连接信息、查询模型并验证接口可用性。

## 功能

- 使用文件夹组织LLM API配置，并支持拖动排序和跨文件夹移动。
- 一键复制Base URL、API Key和Shell环境变量。
- 支持OpenAI Chat Completions、OpenAI Responses和Anthropic Messages。
- 支持查询服务端模型，也可手动保存无法查询的模型ID。
- 逐项测试模型接口；`gpt-image-*`模型使用`/images/generations`进行最小验证。
- 使用便于Obsidian阅读的Markdown格式完整导入和导出配置。
- 不使用macOS Keychain，不包含遥测、云同步或第三方依赖。

## 系统要求

- macOS 14或更高版本
- Xcode 26或更高版本
- Swift 6

## 从源码运行

使用Xcode打开`ModelTap.xcodeproj`，选择`ModelTap`scheme后运行，或执行：

```bash
xcodebuild -project ModelTap.xcodeproj \
  -scheme ModelTap \
  -configuration Debug \
  -sdk macosx \
  build
```

执行单元测试：

```bash
xcodebuild -project ModelTap.xcodeproj \
  -scheme ModelTap \
  -configuration Debug \
  -sdk macosx \
  test
```

项目当前没有Apple Developer Program证书，暂不提供Developer ID签名或Apple公证版本。建议从源码构建，不要安装来源不明的重新打包版本。若以后提供未签名二进制，Release说明必须明确标注其未签名、未公证状态和macOS Gatekeeper限制。

## 数据存储

应用数据只保存在当前macOS用户目录：

- SwiftData数据库：`~/Library/Application Support/ModelTap/ModelTap.store`
- 本地加密密钥：`~/Library/Application Support/ModelTap/local-encryption.key`

旧版本曾使用`~/Library/Application Support/default.store`。首次运行新版时，如果该数据库可识别为ModelTap数据，应用会复制到独立目录；旧文件会保留，不会自动删除。

## 安全说明

API Key使用AES-GCM加密后写入SwiftData，256位本地密钥与数据库分开保存，目录权限为`0700`，文件权限为`0600`。这种方案用于避免数据库明文，不提供macOS Keychain级别的安全隔离；能够读取当前用户应用数据的攻击者仍可能同时取得密文和密钥。

API Key默认隐藏。复制API Key或包含API Key的环境变量时，ModelTap会把内容标记为临时、敏感剪贴板数据，并在剪贴板内容未被覆盖的情况下于60秒后清除。部分剪贴板管理器可能不遵循敏感标记。

Markdown备份包含明文API Key。请将备份保存在可信位置，不要提交到公开仓库或发送给不受信任的第三方。

安全问题请参阅[SECURITY.md](SECURITY.md)，不要在公开Issue中披露有效密钥或可利用漏洞。

## 导入导出格式

导出内容以文件夹为二级标题、配置为三级标题，适合直接放入Obsidian：

```markdown
## 分类A
### CPA阿里云
BASE_URL: http://10.90.23.169:8317/v1
API_KEY: sk-example
API格式: OpenAI Chat Completions
备注: 示例说明
```

导入前会校验内容并二次确认，确认后完整替换当前配置。应用兼容旧版ModelTap Markdown备份。

## 项目结构

- `ModelTap/App/`：应用入口和存储启动逻辑
- `ModelTap/Models/`：SwiftData模型和状态模型
- `ModelTap/Networking/`：模型查询与接口测试
- `ModelTap/Persistence/`：本地仓储和Markdown备份
- `ModelTap/Security/`：API Key本地加密
- `ModelTap/Views/`和`ModelTap/ViewModels/`：SwiftUI界面
- `ModelTapTests/`：XCTest测试

## 已知限制

- 不提供流式聊天、并发压测、价格统计、云同步和自动更新。
- 不支持自定义请求头；协议由用户明确选择，不进行自动回退。
- 图像模型测试只验证接口响应，不保存或展示生成图片。
- 真实接口兼容性取决于服务端对相应协议的实现。

## 参与贡献

提交代码前请阅读[CONTRIBUTING.md](CONTRIBUTING.md)。功能建议和普通缺陷可以提交Issue；请勿在Issue、日志或截图中包含真实API Key。

## 许可证

ModelTap使用[MIT许可证](LICENSE)开源。
