# Code 局部中文界面助手

版本：0.1.0 · Claude Code 官方 Mod 插件格式 · MIT

- 项目：[joyfoxai/zh-ui-helper](https://github.com/joyfoxai/zh-ui-helper)
- 教程：[Claude 桌面版接入 DeepSeek 完整教程](https://github.com/joyfoxai/zh-ui-helper/blob/main/docs/integration-guide.zh-CN.md)
- 下载：[源码 ZIP](https://github.com/joyfoxai/zh-ui-helper/archive/refs/heads/main.zip) · [版本发布页](https://github.com/joyfoxai/zh-ui-helper/releases)

## 功能范围

这个插件为 Claude Desktop 的 **Code 会话区域**提供局部中文显示。它通过官方 `ui.render` 扩展点处理词表中完全匹配的状态词、会话模式标签和输入提示，并提供可开关的中文帮助面板。

**它无法把整个 Claude 桌面 App 汉化。** 全局菜单、设置页、账户侧边栏、工具栏和权限确认框没有被本插件替换。帮助面板里的这些菜单名称是中英文对照说明。

| 范围 | 行为 |
| --- | --- |
| Spinner 的已知状态词 | 例如 `Thinking` → `思考中`；保留动态错误、重试信息与后缀 |
| SessionMode 的已知模式标签 | 仅替换词表中的显示文字 |
| PromptHint 的已知提示 | 保留键位，例如 `esc to interrupt` → `按 Esc 中断` |
| `/zh-ui` 面板 | 中文范围说明、启停按钮、常见菜单词表 |
| 未知文字或新组件 | 保留原文 |
| 用户输入、助手回复、代码、工具内容、提问和权限框 | 不处理 |

不同桌面版本可能只触发其中一部分渲染事件。因此，插件覆盖范围也会随 App 版本变化；不能把它当作完整中文语言包。

This is a partial Chinese UI helper implemented with the official Claude Code Mods interface. It only rewrites exact known display labels at selected render sites and adds its own optional help pane. It does not translate conversations, change tools or permissions, access credentials, modify application packages, or call a model. Unknown labels remain unchanged. The desktop application shell is outside this plugin's coverage.

## 使用要求

- 支持 Mods 的 Claude Code，建议使用 2.1.287 或更新版本。桌面 App 使用自己内置的 Claude Code；可在 Code 会话里用 `/status` 查看版本。
- 使用桌面 Code 的本地会话。WSL 会话可能不支持插件，参见官方文档。
- App 或组织策略允许加载该插件。
- 插件本身没有 npm 依赖，不需要填写 API Key，也不需要单独安装 Node.js。

## 从 GitHub 安装（推荐）

电脑需要安装 [Git](https://git-scm.com/downloads)，并能访问 GitHub。在 Claude Desktop 的 **Code 本地会话输入框**中逐条执行：

```text
/plugin marketplace add joyfoxai/zh-ui-helper
```

```text
/plugin install zh-ui-helper@zh-ui-local
```

在插件详情页按提示点击 **Install（安装）**。完成后执行：

```text
/reload-plugins
```

```text
/zh-ui
```

看到中文帮助面板，表示插件已加载。如果当前版本要求新会话，安装后新建 Code 会话再输入 `/zh-ui`。

也可以用完整 Git 地址注册市场：

```text
/plugin marketplace add https://github.com/joyfoxai/zh-ui-helper.git
```

`zh-ui-local` 是项目沿用的市场标识；安装 ID 保持为 `zh-ui-helper@zh-ui-local`，与电脑文件夹名称无关。

这些是 Code 会话的斜杠命令，填写在会话输入框中。如果没有对应插件管理入口，先检查 App 版本、会话类型和组织策略。

## 下载 ZIP 后安装

1. 下载 [源码 ZIP](https://github.com/joyfoxai/zh-ui-helper/archive/refs/heads/main.zip)，或从 [Releases](https://github.com/joyfoxai/zh-ui-helper/releases) 选择可用的版本包。
2. 解压到长期保留的目录，找到同时包含 `.claude-plugin/marketplace.json` 和 `plugins/zh-ui-helper/` 的市场根目录。
3. 在 Code 会话输入框中执行，路径替换为自己的实际目录：

   ```text
   /plugin marketplace add "<解压后的市场根目录>"
   ```

4. 执行 `/plugin install zh-ui-helper@zh-ui-local`，按提示安装，然后 `/reload-plugins` 或新建会话。
5. 输入 `/zh-ui` 验证。

路径含空格时使用引号。指定市场根目录，不要指定 ZIP 文件或内层 `plugins/zh-ui-helper`。通过目录注册后请保留该目录，App 可能直接从中加载文件。

## 启停

| 命令 | 用途 |
| --- | --- |
| `/zh-ui` | 打开中文帮助面板 |
| `/zh-ui help` | 打开说明与词表 |
| `/zh-ui on` | 开启当前加载实例的局部翻译 |
| `/zh-ui off` | 关闭当前加载实例的局部翻译 |

也可以点击面板里的中文按钮。按 Esc 关闭面板。

开关只保存在当前插件实例的内存中，新会话或重载后默认开启。关闭翻译仍可使用帮助面板。

## 更新

通过 GitHub 注册市场的用户，可在 Code 会话输入框中执行：

```text
/plugin marketplace update zh-ui-local
/reload-plugins
```

也可以在 `/plugin` → Marketplaces 中为本市场开启自动更新。是否启用自动更新，由用户或组织策略决定。

通过解压目录安装的用户，下载新包并更新对应目录，再重载插件。维护者发布新代码版本时，应递增 `plugins/zh-ui-helper/.claude-plugin/plugin.json` 中的 `version`。

## 禁用与卸载

在 `/plugin` 的 Installed 页面禁用或卸载 `zh-ui-helper`。支持对应斜杠子命令的版本也可以使用：

```text
/plugin disable zh-ui-helper@zh-ui-local
/plugin uninstall zh-ui-helper@zh-ui-local
```

执行后按提示重载插件或新建会话。卸载该插件不会移除其他插件或 Claude 的会话数据。

## 实现与数据使用

实现仅注册 `session.start`、自己的 `command.run` 和四个 `ui.render` 处理器。插件调用的 API 只有命令注册、打开面板、界面刷新与元素绘制。

固定词表保存在 `hooks/labels.js`，可以自行补充。匹配区分大小写；不要将词表应用到会话消息或工具数据。

代码不读取文件、环境变量、聊天历史或密钥，不发起网络或模型请求，不修改 App 安装文件。它也不包含任何人的个人配置。

## 验证方式与限制

插件提供原生离线测试，覆盖冻结输入不可变性、未知值保留、敏感内容不参与翻译、桌面渲染树、开关和面板交互。

如果有可用的 Claude Code CLI，可以运行：

```text
claude plugin validate <插件目录>
claude plugin test <插件目录>
```

这里的插件目录指 `plugins/zh-ui-helper`。测试只验证插件逻辑和界面树，不调用模型；真实桌面版本的实际绘制效果仍需安装后确认。此发行包没有自动安装到任何用户的 App 中。

## 官方参考

- [Mods 概览与适用环境](https://code.claude.com/docs/en/plugins/mods/overview)
- [界面扩展点](https://code.claude.com/docs/en/plugins/mods/interface)
- [渲染组件参考](https://code.claude.com/docs/en/plugins/mods/reference#render-sites)
- [插件测试](https://code.claude.com/docs/en/plugins/mods/test)
- [本地市场与安装](https://code.claude.com/docs/en/plugin-marketplaces)
- [GitHub 市场托管与更新](https://code.claude.com/docs/en/plugins/host-marketplace)

这是独立编写的社区插件，不代表 Anthropic 官方提供中文语言包。
