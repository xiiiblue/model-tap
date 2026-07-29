# ModelTap项目协作说明

## 项目概览

ModelTap是使用SwiftUI和SwiftData编写的macOS原生工具，用于发现、验证和管理LLM API。最低支持macOS 14，项目使用Swift 6。

## 目录约定

- `ModelTap/App/`：应用入口。
- `ModelTap/Models/`：SwiftData模型和应用状态模型。
- `ModelTap/Networking/`：API请求、模型发现和测试执行逻辑。
- `ModelTap/Persistence/`：本地数据持久化。
- `ModelTap/Security/`：API Key本地加密逻辑。
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

日常界面迭代只修改代码并按需构建`.app`交给用户验证，不主动运行XCTest或进行人工功能测试；只有用户明确要求测试时才执行测试。测试构建统一输出为`dist/ModelTap.app`，应用名称不得添加功能名、修复名或其他后缀。先在独立DerivedData或临时产品目录完成构建，再复制覆盖`dist/ModelTap.app`；不要把`CONFIGURATION_BUILD_DIR`直接设为`dist`，Xcode可能清理该目录中的其他发布文件。日常迭代不制作DMG、不创建GitHubRelease；只有用户明确要求发布、打包DMG或上传Release时，才执行完整发布流程。

## 图标与发布打包

- 应用图标资源位于`ModelTap/Assets.xcassets/AppIcon.appiconset/`，修改图标时同步维护macOS的16、32、128、256和512点位及其Retina尺寸。
- UniversalRelease构建命令：

```bash
xcodebuild -project ModelTap.xcodeproj -scheme ModelTap -configuration Release -sdk macosx ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
```

- DMG应使用Release产物中的`ModelTap.app`制作，镜像根目录必须同时包含应用和指向`/Applications`的`Applications`快捷入口，确保用户可以拖动安装；发布前确认应用包含`arm64`和`x86_64`架构，并通过GitHubRelease上传DMG文件。

## 安全要求

- API Key使用`LocalAPIKeyCipher`执行AES-GCM加密，密文保存于SwiftData；256位本地加密密钥保存于`~/Library/Application Support/ModelTap/local-encryption.key`，目录权限为`0700`、文件权限为`0600`。不得把API Key明文写入SwiftData、源代码、日志或提交记录。
- 应用不得访问macOS Keychain。`APIProfile.keychainReference`仅为旧版SwiftData结构兼容而保留，新代码不得读取或写入Keychain；旧版升级后由用户重新填写API Key，旧Keychain条目不主动迁移或删除。
- 本地密文和加密密钥位于同一用户账户下，只用于避免数据库明文，不提供Keychain级别的安全隔离；配置编辑器默认隐藏API Key，用户可通过眼睛按钮切换明文显示。
- API格式随配置持久化：`openai`对应Chat Completions、`openai-response`对应Responses、`anthropic`对应Messages。已有配置迁移时默认`openai`。
- OpenAI格式使用`Authorization: Bearer`；Anthropic格式使用`x-api-key`和`anthropic-version: 2023-06-01`，不得向Anthropic请求发送Bearer密钥。协议由用户选择，不做自动回退。
- 不要提交`.env`、密钥文件、用户数据、构建产物或Xcode用户状态。
- 日志和错误信息不得输出Authorization请求头；除配置编辑器输入框外，界面展示密钥时必须使用脱敏值。
- 新增网络请求或持久化字段时，先确认不会扩大权限、遥测或敏感数据暴露范围。

## 修改与交接

- 保持现有SwiftUI、SwiftData和目录分层；业务逻辑优先放在对应的模型、服务或仓储中，不在视图内堆积网络和持久化代码。
- macOS`Form`会将`TextField`的标题参数渲染为左侧标签并把控件放到右侧，且SwiftUI输入框在该环境下可能继续继承右对齐；配置编辑器使用自定义`fieldRow`和AppKit`LeadingAlignedTextField`明确设置左对齐。原生输入控件必须保持无边框、透明背景且不显示焦点框，不要直接恢复为`TextField("标题", text: ...)`的表单行写法。
- 配置编辑器的`editor`在保存或取消时会先置为`nil`，macOS关闭Sheet期间仍可能重新求值输入控件；所有字段绑定必须提供`nil`安全的默认值，禁止对`editor`强制解包，否则保存时会因Sheet退场重绘而闪退。
- 配置保存成功后直接关闭编辑窗口，不显示成功弹窗；保存失败仍通过错误弹窗反馈。备注使用带垂直滚动条的多行编辑区域，不得退回单行输入框或压缩为单行高度。
- “关于”窗口只展示产品名称、用途简介、支持的API格式和真实应用版本，不展示“中文名”“开发阶段”或单独的安全说明。
- 主窗口不显示`ModelTap`导航标题，并使用紧凑型统一工具栏，减少侧边栏工具按钮在右侧形成的顶部空白；不要恢复默认高度的统一工具栏。
- 测试详情面板使用固定高度的顶部对齐`ScrollView`承载内容；不要让超出固定高度的详情`VStack`按默认居中方式溢出，否则状态标题会压到列表与详情之间的分隔线。
- 测试详情只显示结果状态、状态码、接口协议、耗时、Token用量和失败错误，不显示测试时间或模型输出，避免成功详情信息冗余。
- 模型列表的初始、加载失败和加载中状态必须填满列表区剩余空间，而列表标题保持顶部对齐；空测试详情使用顶部对齐的提示，避免在高窗口中出现标题和空状态整体下沉。
- 侧边栏配置卡片只显示配置名称和Base URL，不显示测试状态或最后使用时间；Base URL使用`.callout`字号并保持单行截断，确保地址清晰可读。
- 文件夹使用独立`ProfileFolder`模型持久化，`APIProfile.folderID`保存归属；`category`仅用于迁移上一版文本分类，不得继续作为新功能入口。侧边栏文件夹支持新建、重命名、删除、展开收起、右键移动和拖放；删除文件夹只把配置移到“未分类”，不得删除配置。复制配置时保留文件夹归属，搜索同时匹配文件夹名称、配置名称和Base URL。
- 单模型测试成功只更新模型行状态和详情面板，不弹出成功提示；批量测试完成通知和其他明确操作反馈可保留。
- 模型测试发起后，正在测试的模型行左侧必须显示15点自绘旋转圆环，并在请求完成、失败或取消后恢复为对应状态图标；进入网络请求前主动让出一次主线程，确保快速接口也有机会渲染loading状态。测试按钮在该模型测试期间禁用，避免重复请求。
- 新增或修改功能时同步补充相关XCTest和README文档。
- 提交前检查`git status`，确认没有敏感文件、临时文件或无关改动。
- 重要的开发、测试、发布和已知限制变化要记录在本文件或README中，确保其他Agent或维护者可以直接接手。
