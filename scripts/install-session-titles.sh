#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
extension_dir="$repo_root/extensions/session-title"
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

command -v node >/dev/null || { echo "node is required" >&2; exit 1; }
command -v npx >/dev/null || { echo "npx is required" >&2; exit 1; }
command -v code >/dev/null || { echo "code is required" >&2; exit 1; }

hook_path="$HOME/.local/bin/agentkit-session-title-hook"
hook_config="$HOME/.copilot/hooks/agentkit-session-title.json"
install -Dm755 "$repo_root/scripts/session-title-hook" \
  "$hook_path"
install -Dm644 "$extension_dir/hooks.json" \
  "$hook_config"
node - "$hook_config" "$hook_path" <<'NODE'
const fs = require('node:fs');
const [configPath, hookPath] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
config.hooks.UserPromptSubmit[0].command = hookPath;
fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
NODE
chmod 600 "$hook_config"

(
  cd "$extension_dir"
  npx --yes @vscode/vsce@3.9.2 package --no-dependencies \
    --out "$build_dir/agentkit-session-titles.vsix"
)
code --install-extension "$build_dir/agentkit-session-titles.vsix" --force

printf '%s\n' \
  "Installed Agentkit Session Titles." \
  "Reload each VS Code window to activate the extension and hook."