import { GLOSSARY, translateRenderEvent } from './labels.js';

const PANE = 'zh-ui-helper';

// In-memory state belongs to this loaded mod, with no saved preferences.
let enabled = true;
let notice = '';

export function register(on) {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'zh-ui',
      description: '中文界面助手：启停局部翻译，查看英文菜单词表',
      argumentHint: '[on|off|help]',
      immediate: true,
    });
    return next(e);
  });

  // Handle the command locally: no returned transcript text and no model call.
  on('command.run', { command: 'zh-ui' }, async ($, e) => {
    const mode = typeof e.args === 'string' ? e.args.trim().toLowerCase() : '';
    if (mode === 'on') {
      enabled = true;
      notice = '当前会话已开启词表内的局部翻译。';
    } else if (mode === 'off') {
      enabled = false;
      notice = '当前会话已关闭局部翻译，原界面文字照常显示。';
    } else if (mode === '' || mode === 'help') {
      notice = '';
    } else {
      notice = '未识别的参数。请使用 /zh-ui、/zh-ui on、/zh-ui off 或 /zh-ui help。';
    }
    await $.ui.open({ id: PANE, title: '中文界面助手', focus: true, closeOnEscape: true });
    $.ui.invalidate('ui.render');
    return {};
  });

  // Pass a copied event to the normal renderer; keep animation and behavior.
  on('ui.render', { component: 'Spinner' }, async ($, e, next) => {
    return next(translateRenderEvent(e, enabled));
  });

  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
    return next(translateRenderEvent(e, enabled));
  });

  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => {
    return next(translateRenderEvent(e, enabled));
  });

  on('ui.render', { component: 'Pane' }, async ($, e, next) => {
    if (e.requestId !== PANE) return next(e);
    const { Box, Text, Button } = $.ui.resolve(e);

    return Box({
      flexDirection: 'column',
      children: [
        Text({ bold: true, children: ['Code 会话局部中文化 · v0.1.0'] }),
        Text({ children: ['当前状态：' + (enabled ? '已开启' : '已关闭')] }),
        Box({
          flexDirection: 'row',
          columnGap: 2,
          children: [
            Button({
              key: 'zh-ui-on',
              label: '开启局部翻译',
              hotkey: '1',
              onPress: () => {
                enabled = true;
                notice = '当前会话已开启词表内的局部翻译。';
                $.ui.invalidate('ui.render');
              },
            }),
            Button({
              key: 'zh-ui-off',
              label: '关闭局部翻译',
              hotkey: '2',
              onPress: () => {
                enabled = false;
                notice = '当前会话已关闭局部翻译，原界面文字照常显示。';
                $.ui.invalidate('ui.render');
              },
            }),
          ],
        }),
        Text({ children: [notice || '使用 /zh-ui on 或 /zh-ui off 启停；/zh-ui help 打开本面板。'] }),
        Text({ children: [' '] }),
        Text({ bold: true, children: ['适用范围'] }),
        Text({
          wrap: 'wrap',
          children: ['仅在应用提供对应渲染事件时，翻译当前 Code 会话中词表完全匹配的状态词、输入提示与会话模式标签；未知文字保持原文。具体可见项目取决于 Claude Code 和桌面 App 的版本。'],
        }),
        Text({
          wrap: 'wrap',
          children: ['账户侧栏、全局设置、桌面菜单和权限确认框仍由原应用显示。本面板的英文菜单词表仅供阅读对照，不代表这些菜单已被翻译。'],
        }),
        Text({
          wrap: 'wrap',
          children: ['此插件不处理用户提示词、助手回复、工具参数或结果、提问或权限对话框；不修改模型、接口地址或 API 密钥。不调用网络、文件、环境变量或模型接口，也不保存偏好。新会话或重载插件后默认开启。'],
        }),
        Text({ children: [' '] }),
        Text({ bold: true, children: ['常用英文 → 中文（阅读对照）'] }),
        ...GLOSSARY.map(([english, chinese]) => Text({ children: [english + ' → ' + chinese] })),
        Text({ children: [' '] }),
        Text({ dimColor: true, children: ['按 Esc 可关闭本面板。'] }),
      ],
    });
  });
}
