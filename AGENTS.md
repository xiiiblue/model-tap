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

日常界面迭代只修改代码并按需构建`.app`交给用户验证，不主动运行XCTest或进行人工功能测试；只有用户明确要求测试时才执行测试。测试构建统一输出为`dist/ModelTap.app`，应用名称不得添加功能名、修复名或其他后缀。日常迭代不制作DMG、不创建GitHubRelease；只有用户明确要求发布、打包DMG或上传Release时，才执行完整发布流程。

## 图标与发布打包

- macOS 26主应用图标使用Icon Composer资源`ModelTap/AppIcon.icon/`，以便Dock和台前调度读取系统原生图标表示；`ModelTap/Assets.xcassets/AppIcon.appiconset/`保留旧系统兼容素材。修改图标时应同步维护两处资源。
- UniversalRelease构建命令：

```bash
xcodebuild -project ModelTap.xcodeproj -scheme ModelTap -configuration Release -sdk macosx ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
```

- DMG应使用Release产物中的`ModelTap.app`制作，镜像根目录必须同时包含应用和指向`/Applications`的`Applications`快捷入口，确保用户可以拖动安装；发布前确认应用包含`arm64`和`x86_64`架构，并通过GitHubRelease上传DMG文件。
- 当前项目没有Apple Developer Program证书，不能进行Developer ID签名和Apple公证。公开Release若暂时提供未签名二进制，必须明确标注“未签名、未公证”及Gatekeeper限制，不得让用户误认为是受Apple验证的正式安装包。

## 安全要求

- API Key使用`LocalAPIKeyCipher`执行AES-GCM加密，密文保存于SwiftData；256位本地加密密钥保存于`~/Library/Application Support/ModelTap/local-encryption.key`，目录权限为`0700`、文件权限为`0600`。不得把API Key明文写入SwiftData、源代码、日志或提交记录。
- SwiftData数据库固定保存于`~/Library/Application Support/ModelTap/ModelTap.store`。旧版通用路径`~/Library/Application Support/default.store`只在首次迁移时识别并复制，迁移后不再继续使用，也不自动删除旧文件。
- 应用不得访问macOS Keychain。`APIProfile.keychainReference`仅为旧版SwiftData结构兼容而保留，新代码不得读取或写入Keychain；旧版升级后由用户重新填写API Key，旧Keychain条目不主动迁移或删除。
- 本地密文和加密密钥位于同一用户账户下，只用于避免数据库明文，不提供Keychain级别的安全隔离；配置编辑器默认隐藏API Key，用户可通过眼睛按钮切换明文显示。
- API格式随配置持久化：`openai`对应Chat Completions、`openai-response`对应Responses、`anthropic`对应Messages。已有配置迁移时默认`openai`。
- OpenAI格式使用`Authorization: Bearer`；Anthropic格式使用`x-api-key`和`anthropic-version: 2023-06-01`，不得向Anthropic请求发送Bearer密钥。协议由用户选择，不做自动回退。
- OpenAI配置中的`gpt-image-*`模型测试按模型能力固定调用`/images/generations`，使用单张`1024x1024`、`quality=low`、JPEG图像进行最小验证；只确认响应包含图像数据，不保存或展示生成结果。该定向路由不属于协议自动回退。
- 不要提交`.env`、密钥文件、用户数据、日常`.app`/`.swiftmodule`构建产物或Xcode用户状态；用户明确要求发布时产生的DMG和ZIP只作为发布资产处理。
- 日志和错误信息不得输出Authorization请求头；界面中的API Key默认脱敏，只有用户主动点击眼睛按钮后才可在配置编辑器或连接信息中显示明文，切换配置后必须恢复隐藏。
- 复制API Key或包含API Key的环境变量时必须使用敏感剪贴板标记，并在内容未被用户覆盖的情况下于60秒后自动清除。
- 新增网络请求或持久化字段时，先确认不会扩大权限、遥测或敏感数据暴露范围。

## 修改与交接

- 保持现有SwiftUI、SwiftData和目录分层；业务逻辑优先放在对应的模型、服务或仓储中，不在视图内堆积网络和持久化代码。
- macOS`Form`会将`TextField`的标题参数渲染为左侧标签并把控件放到右侧，且SwiftUI输入框在该环境下可能继续继承右对齐；配置编辑器使用自定义`fieldRow`和AppKit`LeadingAlignedTextField`明确设置左对齐。原生输入控件必须保持无边框、透明背景且不显示焦点框，不要直接恢复为`TextField("标题", text: ...)`的表单行写法。
- `LeadingAlignedTextField`必须保持单行、禁止换行，长内容通过横向滚动编辑，避免API Key等长文本撑高表单行。
- 配置编辑器按“基本信息”“接口配置”和“备注”分区，备注使用整行多行输入区域；macOS 26使用单个`GlassEffectContainer`组织三个轻量`glassEffect`分组，macOS 14至15回退`regularMaterial`，不要给每个输入框单独叠加Glass。编辑器通过足够的窗口最小高度完整容纳内容，避免出现外层滚动条；界面不显示API Key加密实现说明，相关安全细节只保留在README和协作文档中。
- 配置编辑器的`editor`在保存或取消时会先置为`nil`，macOS关闭Sheet期间仍可能重新求值输入控件；所有字段绑定必须提供`nil`安全的默认值，禁止对`editor`强制解包，否则保存时会因Sheet退场重绘而闪退。
- 配置保存成功后直接关闭编辑窗口，不显示成功弹窗；保存失败仍通过错误弹窗反馈。备注使用带垂直滚动条的多行编辑区域，不得退回单行输入框或压缩为单行高度。
- “关于”窗口只展示产品名称、用途简介、支持的API格式和真实应用版本，不展示“中文名”“开发阶段”或单独的安全说明。
- 测试详情面板使用固定高度的顶部对齐`ScrollView`承载内容；不要让超出固定高度的详情`VStack`按默认居中方式溢出，否则状态标题会压到列表与详情之间的分隔线。
- 测试详情只显示结果状态、状态码、接口协议、耗时、Token用量和失败错误，不显示测试时间或模型输出，避免成功详情信息冗余。
- 模型列表不设置固定高度，也不使用独立的垂直`ScrollView`；查询到的模型按实际数量全部展开，跟随右侧详情页的外层滚动统一浏览。初始未查询状态只显示一个弱化的模型列表占位图标，不显示“尚无模型”标题、说明或操作按钮；未执行模型测试时不显示“暂无测试详情”。查询完成但结果为空时仍可显示空结果反馈，测试完成后再展示详情。
- 手动模型ID使用`APIProfile.manualModelIDsRaw`按行持久化。模型列表必须允许“添加”和“添加并测试”，服务端重复模型ID先去重，再与手动模型去重合并；查询失败时不得遮住已有手动模型，手动模型支持在整行任意位置右键删除。主界面不提供“测试全部”和模型搜索栏，只保留逐项测试；切换配置时只加载该配置保存的手动模型。
- 侧边栏配置条目只显示配置名称，不显示Base URL、测试状态或最后使用时间；Base URL仍参与搜索，并在右侧连接信息中完整展示。
- 侧边栏文件夹树使用Finder式紧凑列表：文件夹行使用较弱的`.subheadline`层级，配置子项统一行高并仅缩进约20pt；选中与未选中状态不得改变行尺寸。文件夹统一使用`folder`图标，“未分类”不使用特殊收纳盒图标。
- 侧边栏排序使用`ProfileFolder.sortOrder`和`APIProfile.sortOrder`持久化。文件夹可相互拖动排序；配置可拖到另一配置前完成同组或跨组排序，也可拖到文件夹标题或“未分类”末尾。拖动载荷必须使用`folder:<UUID>`和`profile:<UUID>`区分类型，避免破坏配置移动功能。
- 文件夹使用独立`ProfileFolder`模型持久化，`APIProfile.folderID`保存归属；`category`仅用于迁移上一版文本分类，不得继续作为新功能入口。侧边栏文件夹支持新建、重命名、删除、展开收起、右键移动和拖放；删除文件夹只把配置移到“未分类”，不得删除配置。复制配置时保留文件夹归属，搜索同时匹配文件夹名称、配置名称和Base URL。
- Markdown配置备份由`MarkdownBackupCodec`维护；正文按文件夹使用`##`分组、配置使用`###`标题，Base URL使用普通文本，API格式、API Key、备注和手动模型ID使用可读Markdown，便于直接存入Obsidian。当前导出不写格式版本、内部ID、时间戳、使用状态或测试历史，导入时重新生成本地ID和时间信息；必须继续兼容版本`1`的单行JSON备份、版本`2`带元数据备份以及Base URL使用Markdown链接的过渡格式。空API Key即使被编辑器清理行末空格也必须能导入；历史数据中名为“未分类”或“测试记录”的文件夹使用加粗Markdown标题转义并保持归属，新建文件夹禁止使用这两个保留名称。导出包含明文API Key，文件正文必须明确提示，但点击导出后直接进入保存位置选择，不显示额外确认警告；导入必须先校验并二次确认，确认后完整替换文件夹和配置。
- Markdown配置备份入口使用窗口右侧工具栏中的单个菜单按钮，菜单内提供“导入配置备份”和“导出配置备份”；侧边栏只保留新增配置和新建文件夹，不显示备份入口或齿轮“设置/关于”按钮。
- 主窗口未选中配置时标题栏显示`ModelTap`；选中配置后标题栏动态显示当前配置名称，正文不再重复显示配置名称。API格式标签保留在正文并与“连接信息”标题同行。
- 主界面在macOS 26及以上优先采用原生Liquid Glass：编辑和配置备份放在系统工具栏，连接信息卡片使用`glassEffect`，模型区的“查询模型”和“手动输入”使用同一个`GlassEffectContainer`组织；macOS 14至15使用`regularMaterial`回退。Liquid Glass只用于工具栏、浮层和主要操作容器，不得叠加到模型数据行等高密度内容上。
- 模型数据行属于高密度内容，复制与测试操作使用无常驻背景的`borderless`按钮，只保留系统悬停、按下和键盘焦点反馈；不得为每一行叠加Glass或灰色胶囊背景。
- 模型测试完成时间统一按本地时区显示为`yyyy-MM-dd HH:mm:ss`，不得使用随系统语言变化的本地化短日期格式。
- 主界面定位为LLM API配置管理器。选中配置后的详情页必须优先展示Base URL、默认隐藏的API Key、环境变量和备注；Base URL与API Key提供常驻复制按钮，API Key可通过眼睛按钮临时切换明文。模型查询、手动输入、模型列表和测试详情直接排列在连接信息下方，通过同一个外层滚动页面访问，不再设置“打开模型工作区”入口或次级页面。
- 主界面详情页的外层`ScrollView`和内容容器必须随详情列扩展到可用宽度，不得设置会让滚动区域停在窗口中部的固定`maxWidth`；侧边栏收起后，垂直滚动条应位于窗口右侧内容边缘。
- 复制配置、Base URL、API Key、环境变量和模型ID后使用窗口底部自动消失的轻量Toast反馈，不弹出需要用户关闭的Alert；操作错误仍使用Alert。
- 所有模型查询和测试写回前必须同时校验请求令牌和配置ID；切换配置、删除当前配置或取消请求后，旧任务不得更新当前模型列表、测试详情、状态或测试记录。
- 单模型测试成功只更新模型行状态和详情面板，不弹出成功提示。
- 模型测试发起后，正在测试的模型行左侧必须显示15点自绘旋转圆环，并在请求完成、失败或取消后恢复为对应状态图标；进入网络请求前主动让出一次主线程，确保快速接口也有机会渲染loading状态。测试按钮在该模型测试期间禁用，避免重复请求。
- 新增或修改功能时同步补充相关XCTest和README文档。
- 提交前检查`git status`，确认没有敏感文件、临时文件或无关改动。
- 重要的开发、测试、发布和已知限制变化要记录在本文件或README中，确保其他Agent或维护者可以直接接手。
