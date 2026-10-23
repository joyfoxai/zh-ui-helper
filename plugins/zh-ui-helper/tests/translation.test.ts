import { expect, test } from 'claude-code/testing';
import { translateRenderEvent } from '../hooks/labels.js';

test('known spinner labels translate without changing dynamic details or the frozen input', async () => {
  const props = Object.freeze({ word: 'Thinking', mode: 'thinking', message: 'Retry in 2s: 429', suffix: ' · 12 tokens' });
  const event = Object.freeze({ component: 'Spinner', props, requestId: 'unit-status', surface: 'desktop' });
  const translated = translateRenderEvent(event);
  expect(translated).not.toBe(event);
  expect(translated.props.word).toMatch(/[\u4e00-\u9fff]/);
  expect(translated.props.message).toBe('Retry in 2s: 429');
  expect(translated.props.suffix).toBe(' · 12 tokens');
  expect(event.props.word).toBe('Thinking');
});

test('unrecognized labels and disabled translation are lossless', async () => {
  const event = { component: 'Spinner', props: { word: 'An unreleased label', mode: 'unknown-mode', message: null, suffix: '' } };
  expect(translateRenderEvent(event)).toBe(event);
  expect(translateRenderEvent({ component: 'Spinner', props: { word: 'Thinking' } }, false).props.word).toBe('Thinking');
});

test('session mode translation preserves unknown mode strings and metadata', async () => {
  const modes = Object.freeze(['Accept edits', 'Some future mode']);
  const event = Object.freeze({ component: 'SessionMode', props: Object.freeze({ modes, extra: 'keep' }) });
  const translated = translateRenderEvent(event);
  expect(translated.props.modes[0]).toMatch(/[\u4e00-\u9fff]/);
  expect(translated.props.modes[1]).toBe('Some future mode');
  expect(translated.props.extra).toBe('keep');
  expect(modes[0]).toBe('Accept edits');
});

test('messages, code, tools, and question text never pass through the translation dictionary', async () => {
  for (const component of ['UserMessage', 'AssistantMessage', 'ToolUse', 'ToolResult', 'ToolGroup', 'AskUserQuestion', 'PermissionPrompt']) {
    const event = { component, props: { text: 'Thinking', word: 'Thinking', hint: '? for shortcuts', modes: ['Plan mode'], input: { command: 'echo Thinking' } } };
    expect(translateRenderEvent(event)).toBe(event);
  }
});

test('unknown property shapes are left intact instead of traversed', async () => {
  const event = { component: 'SessionMode', props: { modes: [{ label: 'Accept edits', privateText: 'Thinking' }] } };
  expect(translateRenderEvent(event)).toBe(event);
  expect(translateRenderEvent({ component: 'PromptHint', props: { hint: { text: 'Thinking' } } }).props.hint).toEqual({ text: 'Thinking' });
});

test('the native mod runner draws the translated desktop spinner while preserving its engine details', async ($, on) => {
  let received: any;
  on('ui.render', (_$, event) => {
    received = event;
    return { type: 'Text', props: {}, children: [event.props.word] };
  });
  const ui = await $.ui.mount({
    plugin: 'zh-ui-helper', component: 'Spinner', requestId: 'integration-status', surface: 'desktop',
    props: { word: 'Thinking', mode: 'thinking', message: 'Retry in 2s: 429', suffix: ' · 12 tokens' },
  });
  expect(received.props.word).toMatch(/[\u4e00-\u9fff]/);
  expect(received.props.message).toBe('Retry in 2s: 429');
  expect(received.props.suffix).toBe(' · 12 tokens');
  await ui.unmount();
});

test('off and on commands affect later rendering without a model call', async ($, on) => {
  on('ui.open', () => ({ value: { isPlaced: true } }));
  on('ui.render', (_$, event) => ({ type: 'Text', props: {}, children: [event.props.word] }));
  const sample = {
    plugin: 'zh-ui-helper', component: 'Spinner', requestId: 'toggle-status', surface: 'desktop',
    props: { word: 'Thinking', mode: 'thinking', message: null, suffix: '' },
  } as const;
  await $.command.run({ command: 'zh-ui', args: 'off' });
  const english = await $.ui.mount(sample);
  expect(await english.find({ type: 'Text', text: 'Thinking' })).toBeDefined();
  await english.unmount();
  await $.command.run({ command: 'zh-ui', args: 'on' });
  const chinese = await $.ui.mount(sample);
  expect(await chinese.find({ type: 'Text', text: /[\u4e00-\u9fff]/ })).toBeDefined();
  await chinese.unmount();
});

test('the Chinese help pane renders and its toggle buttons work on desktop', async ($, on) => {
  const ui = await $.ui.mount({
    plugin: 'zh-ui-helper', component: 'Pane', requestId: 'zh-ui-helper', surface: 'desktop',
    viewport: { columns: 100, rows: 40 },
    props: { title: '中文界面助手', isFocused: true, bodyColumns: 70, placement: 'inline', scroll: { offset: 0, bodyRows: 20 }, view: {} },
  });
  expect(await ui.find({ type: 'Text', text: 'Code 会话局部中文化 · v0.1.0' })).toBeDefined();
  expect(await ui.find({ type: 'Text', text: '当前状态：已开启' })).toBeDefined();
  await ui.press({ key: 'zh-ui-off' });
  expect(await ui.find({ type: 'Text', text: '当前状态：已关闭' })).toBeDefined();
  await ui.press({ key: 'zh-ui-on' });
  expect(await ui.find({ type: 'Text', text: '当前状态：已开启' })).toBeDefined();
  await ui.unmount();
});

test('a pane from another plugin retains its original content', async ($, on) => {
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['Another plugin pane'] }));
  const ui = await $.ui.mount({
    plugin: 'zh-ui-helper', component: 'Pane', requestId: 'another-pane', surface: 'desktop',
    props: { title: 'Other', isFocused: false, bodyColumns: 60, placement: 'inline', scroll: { offset: 0, bodyRows: 10 }, view: {} },
  });
  expect(await ui.find({ type: 'Text', text: 'Another plugin pane' })).toBeDefined();
  await ui.unmount();
});
