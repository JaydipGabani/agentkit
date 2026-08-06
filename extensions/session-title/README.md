# Agentkit Session Titles

Renames a VS Code local chat or supported Agent Host session when a prompt
contains an explicit GitHub pull request or Issue link.

```text
Prompt: Review https://github.com/open-policy-agent/gatekeeper/pull/4816
Title:  Add per-constraint VAP generation

Prompt: Fix https://github.com/orka-agents/orka/issues/356
Title:  Improve agent context handling
```

The title is fetched with `gh` and used as-is. If a prompt contains multiple
supported links, the first one is used. Prompts without a full
`github.com/<owner>/<repo>/pull/<number>` or
`github.com/<owner>/<repo>/issues/<number>` link are ignored. Bare numbers,
repository names, active editors, and worktree branches do not trigger a rename.

The extension receives `UserPromptSubmit` events through the companion
`agentkit-session-title-hook`. It passes only the linked repository and number
to `gh`; it does not persist prompts or title history. If lookup fails, the
provider-generated title is left unchanged.

Automatic rename adapters are validated with VS Code 1.132 for:

- Local chat
- Copilot CLI sessions

Claude's rename command is interactive, while Cloud and Codex expose no
programmatic rename adapter. Those providers keep their generated titles.

Stable VS Code does not expose the submitting local chat resource. Resolving the
linked item adds a short delay, so switching chats before the title appears can
target the newly focused local chat. Copilot CLI sessions are targeted directly
and do not have this limitation.

Run `scripts/install-session-titles.sh` from the agentkit checkout, then reload
every VS Code window. The hook and extension run on the remote/workspace host,
so install them separately on each SSH, WSL, container, or Codespaces host.