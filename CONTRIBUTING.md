# 参与贡献

感谢你帮助改进ModelTap。

## 开发环境

- macOS 14或更高版本
- Xcode 26或更高版本
- Swift 6

请使用Xcode打开`ModelTap.xcodeproj`。项目不依赖第三方包。

## 提交修改

1. 从最新主分支创建功能分支。
2. 将网络、持久化和安全逻辑放在对应目录，不要堆积到SwiftUI视图中。
3. 为新增或修改的业务逻辑补充XCTest。
4. 更新README或相关项目文档。
5. 确认提交中不包含API Key、备份文件、用户数据库、构建产物或Xcode用户状态。
6. 提交Pull Request并说明修改动机、界面影响和验证方式。

## 代码风格

- 保持现有SwiftUI、SwiftData和Swift 6并发约束。
- 用户界面优先使用macOS原生控件，并为macOS 14提供可用回退。
- 网络错误必须脱敏，不得记录Authorization、`x-api-key`或完整API Key。
- 新增网络能力前先确认权限、遥测和敏感数据暴露范围没有扩大。

## 测试

```bash
xcodebuild -project ModelTap.xcodeproj \
  -scheme ModelTap \
  -configuration Debug \
  -sdk macosx \
  test
```

真实API验证必须使用自己的测试服务，不要把凭据写入测试代码或测试资源。

## 安全问题

可利用漏洞请按[SECURITY.md](SECURITY.md)私密报告，不要提交公开Issue。
