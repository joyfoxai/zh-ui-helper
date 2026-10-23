# Claude 桌面版中文界面、DeepSeek 接入与 SSH 连接教程

版本：0.3.0-preview.1，更新日期：2026-10-23。新版采用正式 Claude 主包上的独立资源覆盖层，替换早期普通目录副本方案；中文界面下已完成 Cowork 最小实际任务验证。

本文面向第一次配置 Claude Desktop 的 Windows 用户，包含官方下载、DeepSeek 模型接入、Code 的 SSH 远程连接、中文界面安装、更新与卸载。密钥及 SSH 连接示例均使用占位符，使用时换成自己的值；不包含个人服务器或本机路径。

## 1. 这次的汉化方式

本项目通过独立的 **MSIX 修改包（modification package）** 叠加界面资源。启动的仍是 Windows 正式安装的 Claude，保留其原有程序、包身份、签名和 Cowork 服务。

资源包只包含四份界面资源、包清单及项目自制的展示图片。它不复制 Claude 程序，不修改 `WindowsApps` 权限，不改写原安装包的 EXE、ASAR 或服务文件。Microsoft 将这类包作为主应用的独立定制层；移除修改包时，定制层随之移除。参见 [Microsoft 修改包说明](https://learn.microsoft.com/en-us/windows/msix/modification-packages)。

本项目是社区汉化，**不是 Anthropic 官方语言包**。它覆盖本地第三方网关模式下的桌面界面资源，包括已收录的侧栏、设置、原生菜单、Cowork 与 Code 控件。模型回答的语言由请求决定；远程网页、第三方连接器和未收录的新文案可能仍显示英文。

## 2. 适用范围与准备工作

| 项目 | 要求或边界 |
| --- | --- |
| 操作系统 | Windows x64；当前实机验证为 Windows 11 x64 |
| Claude 安装方式 | Windows 正式注册的 MSIX / Microsoft Store 安装包；普通目录复制版不适用 |
| Claude 版本 | 没有固定版本白名单；安装器读取当前安装包身份并检查实际资源结构 |
| 界面模式 | 当前验证为第三方 Gateway 本地界面；官方账户远程网页模式尚未完成验证 |
| Node.js | 推荐官网当前 LTS；兼容底线为 20，但不建议为此新装已停止维护的旧版本 |
| Windows SDK | 本地打包和签名需要 `MakeAppx.exe`、`SignTool.exe`；当前安装器不会自动下载安装 SDK |
| 管理员权限 | 首次将专用本机签名证书加入计算机 `TrustedPeople` 时需要管理员确认 |

请先确认 Claude 的 Cowork 和 Code 在自己的环境中可以正常使用，再添加汉化层。补丁不负责新增账号、组织策略、虚拟化或模型服务本身没有提供的功能。

从 [Node.js 官网](https://nodejs.org/) 下载当前 LTS。从 [Microsoft Windows SDK 下载页](https://learn.microsoft.com/en-us/windows/apps/windows-sdk/) 获取 SDK。SDK 安装时保留包含 App 打包与签名工具的组件；具体组件名称可能随 SDK 版本变化。安装完成后重新打开命令窗口。

资源包体积与原来复制整套 App 的方案不同：它只生成界面覆盖文件。SDK 是单独的开发工具依赖，所需空间以 Microsoft 安装器显示为准，本文不再要求为 Claude 副本预留约 1 GB。

## 3. 下载并配置 Claude

### 3.1 从官方下载

打开 [Claude 官方下载页面](https://claude.com/download)。普通 Intel / AMD 电脑选择 Windows；也可使用页面中的 Microsoft Store 入口。Windows ARM64 电脑有独立下载项，但本汉化方案的 ARM64 行为尚未完成实机验证。

完成安装并启动 Claude。要使用 DeepSeek，应进入第三方推理配置；不要把 DeepSeek Key 填进普通的 Claude 账号或 Anthropic API Key 登录入口。

### 3.2 准备 DeepSeek Key

在 [DeepSeek 开放平台](https://platform.deepseek.com/) 创建自己的 API Key，并确认账户有可用额度。本教程统一使用以下占位符：

```text
YOUR_DEEPSEEK_API_KEY
```

DeepSeek 的 Anthropic 兼容基础地址为：

```text
https://api.deepseek.com/anthropic
```

这里只填基础地址，不追加 `/v1/messages` 或 `/chat/completions`。依据：[DeepSeek Anthropic API 说明](https://api-docs.deepseek.com/guides/anthropic_api/)。

### 3.3 打开第三方推理配置

从 Claude 应用菜单进入：

```text
Help（帮助）
  → Troubleshooting（故障排查）
  → Enable Developer Mode（启用开发者模式）
```

如果提示重启，按提示完成。然后打开：

```text
Developer（开发者）
  → Configure Third-Party Inference…（配置第三方推理）
```

菜单可能随 App 版本变化，以实际界面为准。组织管理的设备可能不允许个人修改配置，参见 [Claude 官方界面配置说明](https://claude.com/docs/third-party/claude-desktop/in-app-configuration)。

### 3.4 填写连接与模型

| 界面字段 | 填写值 |
| --- | --- |
| Inference provider | Gateway |
| Credential kind | Static API key |
| Gateway base URL | `https://api.deepseek.com/anthropic` |
| Gateway API key | 自己的 DeepSeek API Key |
| Gateway auth scheme | Bearer |
| Model discovery | 关闭 |
| Allow Code | 开启 |

在模型列表中添加两项：

| 字段 | Flash | Pro |
| --- | --- | --- |
| Model ID / name | `claude-sonnet-4-6` | `claude-opus-4-7` |
| Display label / labelOverride | `deepseek-flash` | `deepseek-v4-pro` |
| Family tier / anthropicFamilyTier | `sonnet` | `opus` |
| Family default / isFamilyDefault | `true` | `true` |

把 Flash 放在列表第一项，作为初始默认模型。App 可能记住你后续手动选择的模型。

这里保留 Claude 模型 ID，是为了适配桌面 App 的模型校验；菜单显示名使用 DeepSeek 名称。DeepSeek 官方将 `claude-sonnet*` / `claude-haiku*` 映射到 `deepseek-flash`，将 `claude-opus*` 映射到 `deepseek-v4-pro`。显示名本身不会决定后端路由。参见 [DeepSeek 官方桌面版模型映射](https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code/#model-mapping-when-using-claude-code-or-claude-desktop-app)。

如 App 提供 JSON 导入，可使用以下模板；密钥必须自行替换：

```json
{
  "inferenceProvider": "gateway",
  "inferenceCredentialKind": "static",
  "inferenceGatewayBaseUrl": "https://api.deepseek.com/anthropic",
  "inferenceGatewayAuthScheme": "bearer",
  "inferenceGatewayApiKey": "YOUR_DEEPSEEK_API_KEY",
  "modelDiscoveryEnabled": false,
  "isClaudeCodeForDesktopEnabled": true,
  "inferenceModels": [
    {
      "name": "claude-sonnet-4-6",
      "labelOverride": "deepseek-flash",
      "anthropicFamilyTier": "sonnet",
      "isFamilyDefault": true
    },
    {
      "name": "claude-opus-4-7",
      "labelOverride": "deepseek-v4-pro",
      "anthropicFamilyTier": "opus",
      "isFamilyDefault": true
    }
  ]
}
```

保存为 UTF-8 JSON，不添加注释。只导入或编辑需要的连接字段；不要用本模板覆盖原本已配置的全部组织策略或工作区设置。完整字段参见 [Claude 配置参考](https://claude.com/docs/third-party/claude-desktop/configuration)。

点击 **Apply Changes → Save & Restart**。重启后选用刚配置的第三方 Gateway。分别选择 Flash 和 Pro，发送简单请求确认连接成功；测试会产生少量 API 用量。

### 3.5 在 Code 中连接 SSH 服务器

SSH 会话让 Claude Code 在服务器上读取文件、执行命令，本机 Claude Desktop 显示界面。以下是配置步骤，汉化包本身不创建 SSH 连接。字段以实际版本为准，参见 [Claude Code 官方 SSH 操作说明](https://code.claude.com/docs/en/desktop#ssh-sessions)。

**准备连接信息**

以下大写文本都是占位符，必须替换后才能使用：`SSH_USER` 为服务器用户名，`SSH_HOST` 为主机名或 IP，`SSH_PORT` 为端口，`PATH_TO_PRIVATE_KEY` 为本机私钥文件路径，`REMOTE_PROJECT_PATH` 为服务器上的项目目录。

1. 确认本机有 OpenSSH 工具，服务器 SSH 端口可达，远端账户能使用 SFTP、写入并执行所需程序；远端需满足 Claude Code 的系统要求，预留约 1 GB 的用户目录空间。
2. 先在终端验证登录；核对服务商或管理员提供的主机指纹后，再接受主机密钥，将它记入 `known_hosts`。不要跳过校验或直接删除冲突记录：

   ```text
   ssh -p SSH_PORT SSH_USER@SSH_HOST
   ```

   使用私钥时，命令形式为：

   ```text
   ssh -i "PATH_TO_PRIVATE_KEY" -p SSH_PORT SSH_USER@SSH_HOST
   ```

3. 确认服务器能独立访问配置的 Gateway。SSH 登录成功不代表模型接口可用；本机代理和 CA 证书不会自动传到远端。

**允许指定主机**

第三方 Gateway 模式需要单独启用 SSH。在第 3.3 节的推理配置窗口搜索 `sshHostAllowlist`，向“SSH 主机允许列表”加入自己的精确主机名或 IP。填写 `SSH_HOST` 替换后的值，**不包含用户名、协议、端口或目录**；SSH 别名应填写其实际解析到的主机名。对应配置片段如下，它不是可覆盖全部配置的完整文件：

```json
{
  "sshHostAllowlist": ["SSH_HOST"]
}
```

保留原有白名单项、Gateway 地址、API Key、模型及其他设置，只增加需要的主机，然后 **保存更改并重启**。第三方模式默认不启用 SSH，空列表表示禁用；受管理设备还需核对实际生效的策略。无需为单台服务器开放所有主机。

静态 Gateway API Key 支持 SSH 会话。Claude 会把推理端点与凭据传给远端引擎，远端同一账户或有足够权限的管理员可能读取进程中的凭据；只添加自己信任的服务器，无需另外把 DeepSeek Key 粘贴到 SSH 字段。允许列表、凭据和联网行为详见 [Claude 第三方平台 SSH 说明](https://claude.com/docs/third-party/claude-desktop/ssh-remote-sessions)。

**添加连接并保存工作环境**

1. 在 **Code → 新建** 中，打开输入框下方的环境选择器，点击 **新环境**。
2. 找到 **SSH**。部分版本在“运行位置”下拉菜单中选择，另一些版本使用独立 SSH 标签；打开主机列表，选择 **添加 SSH 连接**。
3. 根据自己的连接信息填写：

   | 字段 | 填写方式 |
   | --- | --- |
   | 名称 | 自定义易辨认名称，例如占位符 `SSH_CONNECTION_NAME` |
   | SSH 主机 | `SSH_USER@SSH_HOST`，替换为自己的用户名与主机 |
   | SSH 端口 | `SSH_PORT`，替换为服务商提供的实际端口 |
   | SSH 密钥（可选） | `PATH_TO_PRIVATE_KEY`；使用密码或已有 SSH 配置、agent 时可留空 |
   | Worktree folder（如有） | 远端新建 worktree 的存放位置，可留空使用默认值；它与下面选择的项目目录用途不同 |

4. 点击 **添加 SSH 连接**。首次连接时 Claude 会部署远端组件。密码、动态验证码、私钥口令等由本人在认证提示中输入；不要写进文档、截图或 Git 仓库。
5. 选择服务器上的 `REMOTE_PROJECT_PATH`，填写环境名称，点击 **创建环境**。出现“信任这个工作区？”时，先核对主机和目录，再由本人决定是否信任。
6. 确认输入框下方已选中该远端环境，再发送任务。对远程代码的读写及命令在服务器上执行；正常模型请求会消耗 API 额度。

**Windows 连接方式与重复条目**

Windows 默认使用内置 SSH 客户端：主机密钥需事先记入 `known_hosts`；加密私钥通常需先加载到 SSH agent；不支持 `ProxyJump`。有跳板等需求时再按官方说明评估 `sshTransport=system-openssh`。Microsoft Store 安装的 Claude 使用该方式时无法展示密码、动态验证码、私钥口令或首次主机密钥提示，应先准备好无需提示的认证与已核验的主机记录。不要为普通密码登录随意切换客户端。具体限制见 [官方 Windows SSH 要求](https://claude.com/docs/third-party/claude-desktop/ssh-remote-sessions#host-requirements)。

环境列表可能同时出现 **SSH 主机入口** 和 **已保存环境**：前者保存连接方式，后者保存主机与项目目录的组合，两类入口并存正常。恢复误删环境前先检查是否仍有同一目录的已保存环境；优先复用，缺少时再基于原主机创建。只有重复的环境才需要整理，不要因名称相近就删除主机连接。

| 现象 | 优先检查 |
| --- | --- |
| 没有 SSH 选项，或提示组织不允许连接 | Code 已启用、精确主机已加入允许列表、配置保存重启；受管理策略限制时联系管理员 |
| 超时或认证失败 | 地址、端口、网络及密码／私钥；先用终端确认同一组参数可以登录 |
| 主机密钥校验失败 | 向服务器管理员核对当前指纹，再维护 `known_hosts`；不要关闭主机密钥检查 |
| 登录后远端初始化失败 | SFTP、可用空间、目录执行权限及系统要求；查看错误详情 |
| 已连接但模型请求失败 | 远端到 Gateway 的网络与证书、API Key 额度及模型配置；本机接口正常不能代替远端检查 |
| 出现多条相似名称 | 区分主机入口与保存环境，核对目录后复用已有项，避免重复新建 |

## 4. 安装中文界面资源包

### 4.1 下载项目

从公开仓库 [joyfoxai/zh-ui-helper](https://github.com/joyfoxai/zh-ui-helper) 的 [0.3.0-preview.1 发布页](https://github.com/joyfoxai/zh-ui-helper/releases/tag/v0.3.0-preview.1) 下载并解压 [zh-ui-helper-client-0.3.0-preview.1.zip](https://github.com/joyfoxai/zh-ui-helper/releases/download/v0.3.0-preview.1/zh-ui-helper-client-0.3.0-preview.1.zip)。这是 **MSIX 资源覆盖版**；不要混用早期普通目录副本预览包中的命令。

个人镜像 [starsFriday/zh-ui-helper](https://github.com/starsFriday/zh-ui-helper) 是私有仓库，只有有权访问的人才能下载；公开分享使用前面的 joyfoxai 地址。

### 4.2 检测与本地构建

1. 保存 Claude 中的工作，等待正在进行的任务结束，从应用菜单退出 Claude。
2. 在解压目录中打开 64 位 Windows PowerShell。当前目录应能看到 `build.cjs`、`Install.ps1` 和 `Restore.ps1`。
3. 运行以下命令，`local-build` 是用于保存本机生成内容的目录名，可以保留：

   ```powershell
   node .\build.cjs --output .\local-build
   ```

4. 检查检测结果：Claude 真实安装包、架构、当前版本、找到的 SDK 工具、翻译匹配及未匹配数量。
5. 结构检查通过后，构建目录中会生成 `candidate.msix`、`build-audit.json`、`payload` 及 `makeappx-validation.log`。

默认会从 Windows 注册信息中查找正式安装的 Claude。高级用户可使用 `--app-dir` 指定已经注册的主包内部 `app` 目录；它不能让普通复制目录获得正式安装身份。

检测到不支持的安装方式、多个无法确定的主包或变化过大的资源结构时，安装器应停止并说明原因。请按错误提示处理，不要通过修改 WindowsApps 权限或手动复制 App 来绕过检查。

### 4.3 确认专用签名证书

当前本地构建方式使用为本工具生成的专用测试签名证书。证书发布者是本工具，不能把它当作 Anthropic 官方签名。首次安装会显示证书信息与指纹，并请求将该证书加入计算机的 **TrustedPeople（受信任的人）** 存储。这会为整台电脑增加对该证书的信任，需要管理员确认。

安装与证书步骤由下一节的命令完成。`-TrustCertificate` 明确请求增加本机信任，必须在管理员 PowerShell 中运行；脚本不会自动发起 UAC 提权。它创建专用、不可导出的代码签名私钥，只将公钥证书加入 `LocalMachine\TrustedPeople`，不导入受信任根。请保留构建目录和安装记录，以便后续核对与精确移除。

自签名证书适合本机测试；面向大量用户发布的成品应使用合适的正式签名方式。参见 [Microsoft MSIX 签名说明](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)。本项目不会分发自己的测试私钥，也不要求 Anthropic 私钥。

### 4.4 安装并打开

1. 在开始菜单搜索 Windows PowerShell，选择“以管理员身份运行”。使用与安装 Claude 相同的 Windows 用户，切换到补丁解压目录。路径占位符需换成自己的目录：

   ```powershell
   Set-Location "<汉化包解压目录>"
   ```

2. 首次使用、尚无本工具专用证书时，运行：

   ```powershell
   .\Install.ps1 -BuildDirectory .\local-build -CreateTestCertificate -TrustCertificate
   ```

3. 等待签名、签名验证与修改包注册完成。需要先预览计划时，可在命令末尾加 `-WhatIf`；预览不会代替实际安装。
4. 查看成功结果与当前已应用的主包版本。安装过程的本机记录保存为 `lifecycle-audit.json`。
5. 从开始菜单原有的 **Claude** 入口打开 App，检查侧栏、设置、Cowork 与 Code 的界面文字。

可在安装命令末尾加 `-CreateShortcut`，创建指向同一个正式 Claude 主包的中文快捷方式。已有同名快捷方式时，工具会停止并保留它；可不加该选项，直接使用开始菜单。

如果已创建过专用证书，请从自己的旧安装记录中核对指纹，使用以下形式复用，不要再次创建同名证书：

```powershell
.\Install.ps1 -BuildDirectory .\local-build -CertificateThumbprint YOUR_CERTIFICATE_THUMBPRINT
```

`YOUR_CERTIFICATE_THUMBPRINT` 是占位符，需替换为自己已有专用证书的指纹。若该证书尚未在本机受信任，再显式加 `-TrustCertificate` 并使用管理员窗口。安装器只接受与本工具发布者一致且用途有效的代码签名证书。

不再建立普通目录中的 Claude 副本。首次本地界面加载会将语言保存为简体中文并刷新一次，随后使用 App 正常的语言机制。DeepSeek 配置继续由 Claude 自己管理，汉化安装器不需要 API Key，不读取或上传密钥、聊天记录和用户文件。

## 5. 验证中文与功能

建议完成以下小范围验证：

1. **文字**：查看侧栏、设置与常用菜单，确认已匹配文案显示中文。
2. **Code**：选择测试文件夹，发送“只回复连接成功，不要修改文件或运行命令”，确认能正常得到回复。
3. **Cowork**：进入 Cowork，确认能新建并完成一个简单任务。仅仅看到入口可点击，不能证明任务执行正常。
4. **模型**：分别选择 `deepseek-flash` 与 `deepseek-v4-pro` 检查连接；必要时结合 DeepSeek 用量记录确认路由。

验证请求会消耗少量 API 额度。请使用不含私人资料的测试任务，不要为测试授予整个硬盘访问权限。

如果原有配置隐藏了某个功能，汉化不会替你开启。Cowork 的服务、虚拟化、网络、运行组件及推理服务能力仍由 Claude 与当前环境决定。

## 6. App 更新与汉化更新

**无需锁定某个 Claude 版本。** 安装器根据当前 App 的真实安装包和英文资源生成覆盖层。仍匹配词库的文案显示中文；新增、改写或未收录的文案保留英文。资源目录、加载机制发生变化时，可能需要更新安装器才能继续应用。

每份资源覆盖层针对生成时的真实 `PackageFullName` 路径。Claude 官方更新后，安装包版本和完整包名可能改变；旧覆盖层不会写入新版本对应路径。此时先让官方更新正常完成，再用新版安装器对当前版本重新检测与应用。**当前没有承诺自动随所有未来版本更新。**

更新汉化或官方 App 后，先退出 Claude，保留旧构建目录及记录。先用旧记录运行第 7 节的资源包移除命令，再用新版文件生成新的构建目录，例如 `local-build-new`，并重新安装。构建目录必须为空，不能直接覆盖原审计文件。继续使用时保留专用证书，按上一节的 `-CertificateThumbprint` 方式复用；只允许一个本工具资源包生效。

## 7. 卸载与证书清理

先退出 Claude，在原解压目录打开 PowerShell，使用与安装时相同的构建目录：

```powershell
.\Restore.ps1 -AuditPath .\local-build\lifecycle-audit.json
```

它应只移除本工具拥有的资源修改包，不卸载 Claude，不删除 Claude 用户配置、API Key、聊天记录或工作文件。

如果不再使用本工具，并希望一并清理本工具创建的专用证书，可使用：

```powershell
.\Restore.ps1 -AuditPath .\local-build\lifecycle-audit.json -RemoveTestCertificate
```

清理前核对已记录的证书指纹。移除计算机证书时需使用管理员 PowerShell。只清理该安装记录确认由工具创建或导入、且未被其他包使用的证书；已有证书不会被当作本次新建证书删除。不要按“名称相似”批量删除其他证书，也不要删除 Anthropic、Microsoft 或组织管理的证书。不要删除构建目录后再尝试凭证书名称猜测清理对象。两条恢复命令均支持 `-WhatIf` 预览。

卸载是移除界面定制层的正常维护操作，不代表通过卸载来证明中文状态下的 Cowork 已修复。功能验证以第 9 节记录为准。

## 8. 常见问题

| 现象 | 处理方法 |
| --- | --- |
| 找不到 MakeAppx 或 SignTool | 安装包含打包与签名工具的 Windows SDK，再重新打开命令窗口 |
| 安装器找不到正式 Claude 主包 | 从官方下载或 Microsoft Store 正式安装；不要选择复制目录 |
| Windows 不信任签名 | 核对专用证书与指纹，确认管理员信任步骤是否完成；不要把证书导入受信任根 |
| PowerShell 拒绝运行脚本 | 检查脚本来源、文件属性中的下载阻止状态及组织脚本策略；受管理设备请联系管理员，不要关闭系统安全策略 |
| App 更新后部分或全部恢复英文 | 对当前正式包重新检测和应用；若资源结构改变，等待适配新版安装器 |
| 某些新按钮仍为英文 | 词库还未匹配该版本文案，可提交不含隐私的英文原文和 App 版本 |
| 仍提示 Cowork 需要更新的安装 | 确认打开的是开始菜单正式 Claude，并查看当前资源包及主包检测报告；提交错误信息以继续排查，不把入口可点击视为任务验证完成 |
| 菜单有模型名，调用却失败 | 检查 Base URL、自己的 Key、额度、模型 ID 与 Gateway 配置是否真正应用 |
| 左下角显示自己的用户名 | 第三方本地模式可能用操作系统身份显示名称；这不决定 DeepSeek 路由。需要隐藏时通过 Claude 的 `endUserAttribution` 配置处理 |

提问时可以提供 Windows 版本、Claude 版本、安装器版本、错误代码及脱敏后的审计结果。不要上传真实 API Key、个人完整路径或完整聊天记录。

## 9. 实测记录与未完成验证

本节由维护者在发布前填写，每项结论只对应记录的环境，不能代替所有未来版本的测试。

| 检查项 | 当前证据 |
| --- | --- |
| 实测平台 | Windows 11 x64，Claude Desktop 3.6556.2 |
| 独立 MSIX 修改包安装 | 已在本机安装签名资源包并验证资源映射 |
| 界面覆盖 | 侧栏及 Cowork 页面中文已实机显示 |
| 正式主包启动身份 | 已确认使用官方 MSIX 主包身份运行；新版资源修改包为 0.3.0.1 |
| EXE / ASAR / 主包资源原始哈希 | 已核对七个原始文件，摘要未改变 |
| Cowork 实际任务完成 | 0.2.0.5 验证资源下两次请求均成功；其中一次调用工作区命令工具执行简单 `printf`，取得预期结果且无工具错误；新版 0.3.0.1 的四份覆盖资源与该验证包逐字节相同，重启后 Cowork 中文正常 |
| Code 页面 | 已核验新建、自定义、输入框、本机及模型选择相关界面中文与切换；未重复发送模型请求 |
| 原生菜单中文 | 文件、编辑、视图、转到、帮助均已实机显示中文 |
| 新版安装生命周期 | 以已创建并信任的专用证书，通过 `-CertificateThumbprint` 完成真实签名、签名校验、注册与快捷方式创建；恢复 `-WhatIf` 已验证 |
| 新建证书及信任一体流程 | 参数、所有权与信任操作使用模拟及 `-WhatIf` 检查；本轮未完整实跑 `-CreateTestCertificate -TrustCertificate` 分支 |
| 官方更新后的重新应用 | 动态检测与资源匹配已有检查；尚未代表已对未来官方版本实机验证 |
| ARM64 / macOS / Linux | 本资源包方案尚未完成实机验证 |
| 官方账户远程网页模式 | 尚未完成验证 |

Cowork 上述检查验证了实际请求、一次工具调用与返回结果，证明该场景不再因普通目录副本失去正式包身份而被阻止。它仍是最小功能测试，没有穷尽验证所有功能、连接器、任务类型或操作路径。

翻译基线包含主界面 37,201 条、原生界面 872 条、动态提示 49 条资源。数字描述的是词库覆盖，不表示所有操作路径、嵌入内容或第三方功能都已逐项验收。不同版本会报告不同匹配数量。

安装器另通过 27 项离线检查：6 项 Node 构建测试、17 项 PowerShell 静态 / 模拟生命周期检查、4 项真实 .NET 证书 EKU 内存检查。离线测试不创建系统证书或修改信任，不能替代上述实际部署记录。

## 10. 数据与许可

补丁源代码、新增译文按 MIT 提供；部分中文词库来自 javaht 的 MIT 项目并保留版权声明。安装不调用翻译服务。

发行 ZIP 仅包含安装器、译文、源文指纹和说明。当前 App 的 HTML 与自带词库在用户本机构建时读取合并，不把 Claude 程序、生成后的本机包、个人状态、API Key 或私钥上传到仓库。请保留本地审计供更新与精确卸载使用；对外分享前应脱敏。
