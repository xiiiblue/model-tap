# ModelTap项目协作说明

## 项目概览

ModelTap是使用SwiftUI和SwiftData编写的macOS原生工具，用于发现、验证和管理OpenAI兼容的LLM API。最低支持macOS 14，项目使用Swift 6。

## 目录约定

- `ModelTap/App/`：应用入口。
- `ModelTap/Models/`：SwiftData模型和应用状态模型。
- `ModelTap/Networking/`：API请求、模型发现和测试执行逻辑。
- `ModelTap/Persistence/`：本地数据持久化。
- `ModelTap/Security/`：Keychain相关逻辑。
- `ModelTap/Views/`和`ModelTap/ViewModels/`：SwiftUI界面及其视图模型。
- `ModelTapTests/`：XCTest测试。

## 开发与验证

使用Xcode 26或更高版本打开`ModelTap.xcodeproj`，选择`ModelTap`scheme运行。命令行构建：

```bash
xcodebuild -project ModelTap.xcodeproj -scheme ModelTap -configuration Debug -sdk macosx build
```

命令行测试：

```bash
xcodebuild -project ModelTap.xcodeproj -scheme ModelTap -configuration Debug -sdk macosx test
```

如需避免使用默认DerivedData目录，可增加`-derivedDataPath /tmp/modeltap-deriveddata`。真实接口测试需要本地配置服务地址；Preview和单元测试不得依赖真实API。

## 图标与发布打包

- 应用图标资源位于`ModelTap/Assets.xcassets/AppIcon.appiconset/`，修改图标时同步维护macOS的16、32、128、256和512点位及其Retina尺寸。
- UniversalRelease构建命令：

```bash
xcodebuild -project ModelTap.xcodeproj -scheme ModelTap -configuration Release -sdk macosx ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
```

- DMG应使用Release产物中的`ModelTap.app`制作，镜像根目录必须同时包含应用和指向`/Applications`的`Applications`快捷入口，确保用户可以拖动安装；发布前确认应用包含`arm64`和`x86_64`架构，并通过GitHubRelease上传DMG文件。

## 安全要求

- API Key只能保存于macOS Keychain，不得写入SwiftData、源代码、日志或提交记录；配置编辑器默认明文显示，用户可通过眼睛按钮切换隐藏。
- 不要提交`.env`、密钥文件、用户数据、构建产物或Xcode用户状态。
- 日志和错误信息不得输出Authorization请求头；除配置编辑器输入框外，界面展示密钥时必须使用脱敏值。
- 新增网络请求或持久化字段时，先确认不会扩大权限、遥测或敏感数据暴露范围。

## 修改与交接

- 保持现有SwiftUI、SwiftData和目录分层；业务逻辑优先放在对应的模型、服务或仓储中，不在视图内堆积网络和持久化代码。
- 新增或修改功能时同步补充相关XCTest和README文档。
- 提交前检查`git status`，确认没有敏感文件、临时文件或无关改动。
- 重要的开发、测试、发布和已知限制变化要记录在本文件或README中，确保其他Agent或维护者可以直接接手。
