# Claude 桌面中文界面适配

**0.3.0-preview.1 使用独立 MSIX 资源修改包汉化正式 Claude Desktop，保留原程序及 Cowork 服务身份。** 已在中文界面下完成 Cowork 请求及真实工作区命令调用，不再使用复制整套 App 的安装方式。

- [下载 0.3.0-preview.1 客户端汉化包](https://github.com/joyfoxai/zh-ui-helper/releases/download/v0.3.0-preview.1/zh-ui-helper-client-0.3.0-preview.1.zip)
- [本次发布说明](https://github.com/joyfoxai/zh-ui-helper/releases/tag/v0.3.0-preview.1)
- [安装、更新与卸载教程](client-patch/README.md)
- [Claude 下载、DeepSeek 接入、SSH 远程连接与中文界面完整教程](docs/integration-guide.zh-CN.md)
- [Code SSH 主机白名单、连接认证及重复环境处理（第 3.5 节）](docs/integration-guide.zh-CN.md)
- [实际验证范围](docs/localization-validation.zh-CN.md)

## 安装

适用于 **Windows x64 正式 MSIX / Microsoft Store 安装的 Claude，在第三方 Gateway 本地界面下使用**。先安装 [Node.js 当前 LTS](https://nodejs.org/)与包含 MakeAppx、SignTool 的 [Windows SDK](https://learn.microsoft.com/en-us/windows/apps/windows-sdk/)。Node 兼容底线为 20，不建议为此新装已停止维护的旧版本。

1. 下载并解压汉化包，保存工作，从菜单退出 Claude。
2. 在解压目录打开 64 位 Windows PowerShell，构建本机资源包：

   ```powershell
   node .\build.cjs --output .\local-build
   ```

3. **首次创建专用测试证书并信任时**，使用同一 Windows 用户的管理员 PowerShell，切换到解压目录后运行：

   ```powershell
   .\Install.ps1 -BuildDirectory .\local-build -CreateTestCertificate -TrustCertificate
   ```

4. 从开始菜单打开 **Claude**。可选 `-CreateShortcut` 创建指向同一个正式主包的中文快捷方式。

`-TrustCertificate` 会将本工具的专用公钥证书加入本机 `TrustedPeople`，影响整台电脑的信任，脚本不会自动 UAC 提权，也不导入根证书或更改执行策略。自签名是本机测试方案，安装前请阅读[签名与信任说明](client-patch/README.md#43-确认专用签名证书)。已有专用证书时使用 `-CertificateThumbprint` 复用。请保留构建目录中的安装审计供更新和卸载使用。

## 版本兼容与覆盖

没有固定 Claude 版本白名单。安装器检测真实主包及资源结构，按当前英文原文匹配词库；新增或改写、尚未收录的文案保留英文。资源或加载机制发生较大变化时，可能需要更新安装器。

覆盖层绑定生成时的真实主包路径。**Claude 官方更新后需对当前版本重新构建、重新应用**；旧资源不会按旧路径覆盖新版本，不承诺自动适配所有未来更新。已实测基线为 Windows 11 x64 Claude Desktop 3.6556.2，ARM64、其他系统和官方账户远程网页模式尚未验证。

词库基线为 37,201 条主界面、872 条原生界面与 49 条动态提示。已实机检查侧栏、Cowork、Code 相关控件及文件 / 编辑 / 视图 / 转到 / 帮助菜单。最小任务成功不等于所有功能或操作路径已穷尽验收，详见[验证记录](docs/localization-validation.zh-CN.md)。

## 移除资源包

退出 Claude，使用自己的安装审计：

```powershell
.\Restore.ps1 -AuditPath .\local-build\lifecycle-audit.json
```

它精确移除本工具记录的修改包及自有快捷方式，保留 Claude 和用户数据。只有不再使用本工具且满足所有权检查时，才显式加 `-RemoveTestCertificate` 清理专用证书；计算机证书清理需要管理员权限。安装和移除均支持 `-WhatIf`。

## 原有 Code Mod

仓库同时保留 0.1.0 Code 局部 Mod，仅提供少量状态词和中文帮助面板；整体桌面汉化使用上面的资源包。

```text
/plugin marketplace add joyfoxai/zh-ui-helper
/plugin install zh-ui-helper@zh-ui-local
/reload-plugins
/zh-ui
```

[Mod 完整安装、启停与卸载说明](docs/code-mod.zh-CN.md)。组织版与个人版使用不同市场标识，同类 Mod 只启用一份。

## 数据、许可与项目地址

安装器不需要 API Key，不读取密钥或聊天记录，不调用翻译服务。发行包只提供安装器、译文及源文指纹；当前 App 的 HTML 和自带词库在本机合并，不随项目分发 Claude 程序、生成后的本机包或私钥。

安装器和新增译文按 MIT 提供，复用词库保留[第三方版权声明](client-patch/THIRD_PARTY_NOTICES.md)。这是社区适配，不是 Anthropic 官方语言包。

公开项目为 [joyfoxai/zh-ui-helper](https://github.com/joyfoxai/zh-ui-helper)；[starsFriday/zh-ui-helper](https://github.com/starsFriday/zh-ui-helper) 为私有个人镜像，仅获授权者可访问。
