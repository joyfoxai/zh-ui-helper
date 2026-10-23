// Exact, case-sensitive UI labels only. Unknown strings remain untouched.
// These dictionaries are never applied to prompts, messages, or tool data.
export const SPINNER_LABELS = Object.freeze({
  Thinking: '思考中',
  Working: '处理中',
  Processing: '处理中',
  Reasoning: '推理中',
  Planning: '规划中',
  Searching: '搜索中',
  Reading: '读取中',
  Writing: '编写中',
  Editing: '编辑中',
  Running: '运行中',
  Testing: '测试中',
  Analyzing: '分析中',
  Computing: '计算中',
  Generating: '生成中',
  Reviewing: '检查中',
  Summarizing: '总结中',
  Compacting: '压缩上下文中',
  Connecting: '连接中',
  Waiting: '等待中',
  Sauteing: '处理中',
});

export const PROMPT_HINT_LABELS = Object.freeze({
  '? for shortcuts': '按 ? 查看快捷键',
  'esc to interrupt': '按 Esc 中断',
  'Esc to interrupt': '按 Esc 中断',
  'shift+tab to cycle modes': '按 Shift+Tab 切换模式',
  'shift+Tab to cycle modes': '按 Shift+Tab 切换模式',
  'Shift+Tab to cycle modes': '按 Shift+Tab 切换模式',
  'shift+tab to accept edits': '按 Shift+Tab 切换为自动接受编辑',
  'enter to send': '按 Enter 发送',
  'Enter to send': '按 Enter 发送',
  'ctrl+c to exit': '按 Ctrl+C 退出',
  'Ctrl+C to exit': '按 Ctrl+C 退出',
});

export const SESSION_MODE_LABELS = Object.freeze({
  focus: '专注',
  Focus: '专注',
  'memory paused': '记忆已暂停',
  'Memory paused': '记忆已暂停',
  Manual: '手动模式',
  Auto: '自动模式',
  Plan: '计划模式',
  'plan mode': '计划模式',
  'Plan mode': '计划模式',
  'plan mode on': '计划模式已开启',
  'accept edits': '自动接受编辑',
  'Accept edits': '自动接受编辑',
  'accept edits on': '自动接受编辑已开启',
  'auto-accept edits': '自动接受编辑',
  'auto-accept edits on': '自动接受编辑已开启',
  'bypass permissions': '跳过权限检查',
  'bypass permissions on': '跳过权限检查已开启',
});

// A reading aid inside our own pane, not additional translation targets.
export const GLOSSARY = Object.freeze([
  Object.freeze(['Code', '代码工作区']),
  Object.freeze(['New session', '新建会话']),
  Object.freeze(['Settings', '设置']),
  Object.freeze(['General', '通用']),
  Object.freeze(['Language', '语言']),
  Object.freeze(['Appearance', '外观']),
  Object.freeze(['Model', '模型']),
  Object.freeze(['Provider', '服务提供商']),
  Object.freeze(['API key', 'API 密钥']),
  Object.freeze(['Base URL', '接口地址']),
  Object.freeze(['Plugins', '插件']),
  Object.freeze(['Permissions', '权限']),
  Object.freeze(['Allow once', '仅允许这一次']),
  Object.freeze(['Always allow', '始终允许']),
  Object.freeze(['Deny', '拒绝']),
  Object.freeze(['Thinking', '思考中']),
  Object.freeze(['? for shortcuts', '按 ? 查看快捷键']),
  Object.freeze(['esc to interrupt', '按 Esc 中断']),
  Object.freeze(['focus', '专注']),
  Object.freeze(['memory paused', '记忆已暂停']),
]);

function exactLabel(value, labels) {
  if (typeof value !== 'string') return value;
  return Object.prototype.hasOwnProperty.call(labels, value) ? labels[value] : value;
}

function withTranslatedField(event, field, labels) {
  const previous = event.props[field];
  const translated = exactLabel(previous, labels);
  return translated === previous
    ? event
    : { ...event, props: { ...event.props, [field]: translated } };
}

/**
 * Rewrite only three documented display fields while retaining engine rendering.
 * SessionMode.modes is documented as readonly string[]; a different shape is
 * deliberately ignored, including arrays containing objects or non-strings.
 */
export function translateRenderEvent(event, enabled = true) {
  if (!enabled || !event || typeof event !== 'object') return event;
  if (!event.props || typeof event.props !== 'object' || Array.isArray(event.props)) return event;

  if (event.component === 'Spinner') {
    return withTranslatedField(event, 'word', SPINNER_LABELS);
  }
  if (event.component === 'PromptHint') {
    return withTranslatedField(event, 'hint', PROMPT_HINT_LABELS);
  }
  if (event.component === 'SessionMode') {
    const previous = event.props.modes;
    if (!Array.isArray(previous) || !previous.every((mode) => typeof mode === 'string')) return event;
    const translated = previous.map((mode) => exactLabel(mode, SESSION_MODE_LABELS));
    if (translated.every((mode, index) => mode === previous[index])) return event;
    return { ...event, props: { ...event.props, modes: translated } };
  }
  return event;
}
