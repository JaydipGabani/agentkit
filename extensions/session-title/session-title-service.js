'use strict';

const { execFile } = require('node:child_process');
const { promisify } = require('node:util');

const execFileAsync = promisify(execFile);
const LOCAL_SCHEMES = new Set([
  'agentkit-local',
  'local',
  'vscode-chat-editor',
  'vscode-local-chat-session',
  'vscodechateditor',
  'vscodelocalchatsession',
]);

function normalizeText(value) {
  return String(value ?? '').replace(/[\r\n\t]+/g, ' ').trim();
}

function parseGitHubWorkItemLink(prompt) {
  const match = /https?:\/\/(?:www\.)?github\.com\/([A-Za-z0-9][A-Za-z0-9-]*)\/([A-Za-z0-9._-]+)\/(pull|issues)\/([1-9]\d*)\b/i
    .exec(String(prompt ?? ''));
  if (!match) {
    return undefined;
  }

  const number = Number(match[4]);
  if (!Number.isSafeInteger(number)) {
    return undefined;
  }

  return {
    kind: match[3].toLowerCase() === 'pull' ? 'pr' : 'issue',
    number,
    repository: `${match[1]}/${match[2]}`,
  };
}

async function run(command, args) {
  return execFileAsync(command, args, {
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
    timeout: 7_000,
  });
}

async function resolveGitHubWorkItemTitle(reference, runCommand = run) {
  const { stdout } = await runCommand('gh', [
    reference.kind,
    'view',
    String(reference.number),
    '--repo',
    reference.repository,
    '--json',
    'title',
  ]);
  const title = normalizeText(JSON.parse(stdout)?.title);
  return title || undefined;
}

function resourceScheme(resource) {
  return String(resource?.scheme ?? '').toLowerCase();
}

function adapterForResource(resource) {
  const scheme = resourceScheme(resource);
  if (LOCAL_SCHEMES.has(scheme)) {
    return 'local';
  }
  if (scheme === 'background' || scheme === 'copilotcli' || scheme.endsWith('-copilotcli')) {
    return 'copilot-cli';
  }
  return undefined;
}

function resourceFromHookInput(vscode, input) {
  const sessionId = normalizeText(input?.session_id);
  if (!sessionId) {
    return undefined;
  }

  if (/^[a-z][a-z0-9+.-]*:/i.test(sessionId)) {
    try {
      return vscode.Uri.parse(sessionId);
    } catch {
      return undefined;
    }
  }

  const transcriptPath = String(input?.transcript_path ?? '');
  if (/[\\/]\.copilot[\\/]session-state[\\/]/i.test(transcriptPath)) {
    return vscode.Uri.from({ scheme: 'agent-host-copilotcli', path: `/${sessionId}` });
  }
  if (/[\\/]GitHub\.copilot-chat[\\/]transcripts[\\/]/i.test(transcriptPath)) {
    return vscode.Uri.from({ scheme: 'agentkit-local', path: `/${sessionId}` });
  }
  return undefined;
}

async function commandAvailable(vscode, command) {
  if (typeof vscode.commands.getCommands !== 'function') {
    return false;
  }
  return (await vscode.commands.getCommands(true)).includes(command);
}

async function renameResource(vscode, resource, title) {
  const adapter = adapterForResource(resource);
  const command = {
    local: 'workbench.action.chat.open',
    'copilot-cli': 'github.copilot.cli.sessions.setTitle',
  }[adapter];
  if (!command || !await commandAvailable(vscode, command)) {
    return undefined;
  }

  if (adapter === 'local') {
    await vscode.commands.executeCommand(command, {
      query: `/rename ${title}`,
      preserveInput: true,
    });
  } else {
    await vscode.commands.executeCommand(command, { resource }, title);
  }
  return adapter;
}

class SessionTitleService {
  constructor(vscode, options = {}) {
    this.vscode = vscode;
    this.runCommand = options.runCommand ?? run;
    this.log = options.log ?? (() => {});
  }

  async handleHook(input) {
    const prompt = normalizeText(input?.prompt);
    const sessionId = normalizeText(input?.session_id);
    if (!prompt || !sessionId || /^\/rename(?:\s|$)/i.test(prompt)) {
      return { status: 'ignored' };
    }

    const reference = parseGitHubWorkItemLink(prompt);
    if (!reference) {
      return { status: 'ignored' };
    }

    const resource = resourceFromHookInput(this.vscode, input);
    if (!adapterForResource(resource)) {
      return { status: 'unsupported' };
    }

    let title;
    try {
      title = await resolveGitHubWorkItemTitle(reference, this.runCommand);
    } catch {
      this.log('Could not resolve linked GitHub item title.');
      return { status: 'unresolved' };
    }
    if (!title) {
      return { status: 'unresolved' };
    }

    try {
      const adapter = await renameResource(this.vscode, resource, title);
      if (!adapter) {
        return { status: 'unsupported' };
      }
      this.log(`Renamed session with ${adapter}.`);
      return { status: 'renamed', title };
    } catch {
      this.log('Session rename failed.');
      return { status: 'deferred', title };
    }
  }
}

module.exports = {
  SessionTitleService,
  adapterForResource,
  commandAvailable,
  parseGitHubWorkItemLink,
  renameResource,
  resourceFromHookInput,
  resolveGitHubWorkItemTitle,
};