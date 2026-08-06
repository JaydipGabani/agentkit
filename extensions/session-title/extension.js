'use strict';

const vscode = require('vscode');

const { startBridge } = require('./bridge');
const { SessionTitleService } = require('./session-title-service');

function workspaceFolderPaths() {
  return (vscode.workspace.workspaceFolders ?? [])
    .map((folder) => folder.uri.fsPath)
    .filter(Boolean);
}

async function activate(context) {
  const output = vscode.window.createOutputChannel('Agentkit Session Titles');
  const log = (message) => output.appendLine(`[${new Date().toISOString()}] ${message}`);
  const service = new SessionTitleService(vscode, { log });

  const bridge = await startBridge({
    workspaceFolders: workspaceFolderPaths(),
    focused: vscode.window.state.focused,
    log,
    handleHook: async (input) => {
      const enabled = vscode.workspace
        .getConfiguration('agentkit.sessionTitles')
        .get('enabled', true);
      if (!enabled) {
        return { status: 'disabled' };
      }

      return service.handleHook(input);
    },
  });

  context.subscriptions.push(
    output,
    bridge,
    vscode.commands.registerCommand('agentkit.sessionTitles.showOutput', () => output.show()),
    vscode.workspace.onDidChangeWorkspaceFolders(() => {
      void bridge.updateWorkspaceFolders(workspaceFolderPaths())
        .catch((error) => log(`Workspace context refresh failed: ${error.message}`));
    }),
    vscode.window.onDidChangeWindowState((state) => {
      bridge.updateWindowFocus(state.focused).catch((error) => log(String(error)));
    }),
  );

  log(`Bridge ready for ${workspaceFolderPaths().join(', ') || 'this window'}`);
}

function deactivate() {}

module.exports = {
  activate,
  deactivate,
};