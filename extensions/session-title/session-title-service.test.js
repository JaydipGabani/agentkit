'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  SessionTitleService,
  adapterForResource,
  parseGitHubWorkItemLink,
  renameResource,
  resourceFromHookInput,
  resolveGitHubWorkItemTitle,
} = require('./session-title-service');

function vscodeStub(calls = []) {
  return {
    Uri: {
      parse: (value) => ({ scheme: value.split(':')[0], value }),
      from: (value) => value,
    },
    commands: {
      getCommands: async () => [
        'workbench.action.chat.open',
        'github.copilot.cli.sessions.setTitle',
      ],
      executeCommand: async (...args) => calls.push(args),
    },
  };
}

test('parses explicit GitHub pull request and issue links', () => {
  assert.deepEqual(
    parseGitHubWorkItemLink('review https://github.com/open-policy-agent/gatekeeper/pull/4816'),
    { kind: 'pr', number: 4816, repository: 'open-policy-agent/gatekeeper' },
  );
  assert.deepEqual(
    parseGitHubWorkItemLink('fix [the issue](https://github.com/orka-agents/orka/issues/356)'),
    { kind: 'issue', number: 356, repository: 'orka-agents/orka' },
  );
});

test('uses the first linked work item and ignores non-links', () => {
  assert.deepEqual(parseGitHubWorkItemLink([
    'https://github.com/orka-agents/orka/issues/356',
    'https://github.com/open-policy-agent/gatekeeper/pull/4816',
  ].join(' ')), {
    kind: 'issue',
    number: 356,
    repository: 'orka-agents/orka',
  });
  assert.equal(parseGitHubWorkItemLink('review PR #4816'), undefined);
  assert.equal(parseGitHubWorkItemLink('review open-policy-agent/gatekeeper#4816'), undefined);
  assert.equal(parseGitHubWorkItemLink('https://github.com/owner/repo/issues/0'), undefined);
  assert.equal(parseGitHubWorkItemLink('https://github.com.example/owner/repo/pull/1'), undefined);
});

test('resolves the exact title with the matching gh command', async () => {
  for (const reference of [
    { kind: 'pr', number: 4816, repository: 'open-policy-agent/gatekeeper' },
    { kind: 'issue', number: 356, repository: 'orka-agents/orka' },
  ]) {
    const calls = [];
    const title = await resolveGitHubWorkItemTitle(reference, async (command, args) => {
      calls.push([command, ...args]);
      return { stdout: JSON.stringify({ title: 'Fix admission audit behavior' }) };
    });

    assert.equal(title, 'Fix admission audit behavior');
    assert.deepEqual(calls, [[
      'gh', reference.kind, 'view', String(reference.number),
      '--repo', reference.repository, '--json', 'title',
    ]]);
  }
});

test('derives supported resources without a proposed VS Code API', () => {
  const vscode = vscodeStub();
  assert.equal(resourceFromHookInput(vscode, {
    session_id: 'local-session',
    transcript_path: '/home/user/GitHub.copilot-chat/transcripts/local-session.jsonl',
  }).scheme, 'agentkit-local');
  assert.equal(resourceFromHookInput(vscode, {
    session_id: 'cli-session',
    transcript_path: '/home/user/.copilot/session-state/cli-session/events.jsonl',
  }).scheme, 'agent-host-copilotcli');
  assert.equal(resourceFromHookInput(vscode, {
    session_id: 'agent-host-copilotcli:/session',
  }).scheme, 'agent-host-copilotcli');
  assert.equal(resourceFromHookInput(vscode, { session_id: 'unknown' }), undefined);
});

test('selects only noninteractive rename adapters', () => {
  assert.equal(adapterForResource({ scheme: 'agentkit-local' }), 'local');
  assert.equal(adapterForResource({ scheme: 'agent-host-copilotcli' }), 'copilot-cli');
  assert.equal(adapterForResource({ scheme: 'agent-host-claude' }), undefined);
  assert.equal(adapterForResource({ scheme: 'agent-host-codex' }), undefined);
});

test('uses the provider-specific rename command', async () => {
  const calls = [];
  const vscode = vscodeStub(calls);

  await renameResource(vscode, { scheme: 'agentkit-local' }, 'Fix admission audit behavior');
  await renameResource(vscode, { scheme: 'agent-host-copilotcli' }, 'Fix agent context');

  assert.deepEqual(calls[0], [
    'workbench.action.chat.open',
    { query: '/rename Fix admission audit behavior', preserveInput: true },
  ]);
  assert.deepEqual(calls[1], [
    'github.copilot.cli.sessions.setTitle',
    { resource: { scheme: 'agent-host-copilotcli' } },
    'Fix agent context',
  ]);
});

test('renames a local chat to the exact linked PR title', async () => {
  const commandCalls = [];
  const ghCalls = [];
  const service = new SessionTitleService(vscodeStub(commandCalls), {
    runCommand: async (command, args) => {
      ghCalls.push([command, ...args]);
      return { stdout: JSON.stringify({ title: 'Add per-constraint VAP generation' }) };
    },
  });

  const result = await service.handleHook({
    session_id: 'local-session',
    prompt: 'review https://github.com/open-policy-agent/gatekeeper/pull/4816',
    transcript_path: '/home/user/GitHub.copilot-chat/transcripts/local-session.jsonl',
  });

  assert.deepEqual(result, {
    status: 'renamed',
    title: 'Add per-constraint VAP generation',
  });
  assert.deepEqual(ghCalls[0], [
    'gh', 'pr', 'view', '4816', '--repo', 'open-policy-agent/gatekeeper',
    '--json', 'title',
  ]);
  assert.equal(
    commandCalls[0][1].query,
    '/rename Add per-constraint VAP generation',
  );
});

test('renames a Copilot CLI session to the exact linked Issue title', async () => {
  const commandCalls = [];
  const service = new SessionTitleService(vscodeStub(commandCalls), {
    runCommand: async () => ({ stdout: JSON.stringify({ title: 'Improve agent context handling' }) }),
  });

  const result = await service.handleHook({
    session_id: 'agent-host-copilotcli:/session',
    prompt: 'investigate https://github.com/orka-agents/orka/issues/356',
  });

  assert.equal(result.title, 'Improve agent context handling');
  assert.deepEqual(commandCalls[0], [
    'github.copilot.cli.sessions.setTitle',
    { resource: { scheme: 'agent-host-copilotcli', value: 'agent-host-copilotcli:/session' } },
    'Improve agent context handling',
  ]);
});

test('does nothing when the prompt has no linked PR or Issue', async () => {
  const commandCalls = [];
  let lookupCount = 0;
  const service = new SessionTitleService(vscodeStub(commandCalls), {
    runCommand: async () => {
      lookupCount += 1;
      throw new Error('must not run');
    },
  });

  const result = await service.handleHook({
    session_id: 'local-session',
    prompt: 'investigate admission audit behavior',
    transcript_path: '/home/user/GitHub.copilot-chat/transcripts/local-session.jsonl',
  });

  assert.deepEqual(result, { status: 'ignored' });
  assert.equal(lookupCount, 0);
  assert.deepEqual(commandCalls, []);
});

test('leaves the title unchanged when lookup fails or the provider is unsupported', async () => {
  const commandCalls = [];
  let lookupCount = 0;
  const service = new SessionTitleService(vscodeStub(commandCalls), {
    runCommand: async () => {
      lookupCount += 1;
      throw new Error('not found');
    },
  });

  assert.deepEqual(await service.handleHook({
    session_id: 'local-session',
    prompt: 'review https://github.com/open-policy-agent/gatekeeper/pull/4816',
    transcript_path: '/home/user/GitHub.copilot-chat/transcripts/local-session.jsonl',
  }), { status: 'unresolved' });
  assert.deepEqual(await service.handleHook({
    session_id: 'agent-host-claude:/session',
    prompt: 'review https://github.com/open-policy-agent/gatekeeper/pull/4816',
  }), { status: 'unsupported' });

  assert.equal(lookupCount, 1);
  assert.deepEqual(commandCalls, []);
});

test('ignores internal rename prompts', async () => {
  const service = new SessionTitleService(vscodeStub(), {
    runCommand: async () => { throw new Error('must not run'); },
  });
  assert.deepEqual(await service.handleHook({
    session_id: 'local-session',
    prompt: '/rename https://github.com/open-policy-agent/gatekeeper/pull/4816',
  }), { status: 'ignored' });
});