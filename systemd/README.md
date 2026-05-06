# systemd/

User-scope systemd unit pair that runs `session-log-compile.sh` once a
day so the next morning's `daily-brief` agent has fresh signal to read.

## Files

- `session-log-compile.service` — `Type=oneshot` unit invoking
  `%h/.local/bin/session-log-compile.sh` with `ProtectSystem=strict` and
  `ProtectHome=read-only` (only `~/.local/state/session-logs` is
  writable).
- `session-log-compile.timer` — fires daily; defaults to 17:00 local
  (00:00 UTC) with `Persistent=true` so it catches up after a reboot.

## Install (Linux with systemd user instance)

```sh
mkdir -p ~/.config/systemd/user
install -m644 systemd/session-log-compile.service ~/.config/systemd/user/
install -m644 systemd/session-log-compile.timer   ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now session-log-compile.timer
```

Verify:

```sh
systemctl --user list-timers session-log-compile.timer
journalctl --user -u session-log-compile.service -n 50
ls -l ~/.local/state/session-logs/
```

## Customizing the schedule

Edit `OnCalendar=` in the timer file, then:

```sh
systemctl --user daemon-reload
systemctl --user restart session-log-compile.timer
```

Examples:
- `OnCalendar=*-*-* 17:00:00` — daily at 17:00 local.
- `OnCalendar=Mon..Fri 18:00 America/Los_Angeles` — weekdays only.

## No systemd?

- **macOS**: convert to a `launchd` plist (`StartCalendarInterval`).
- **Anywhere with cron**: `0 17 * * * $HOME/.local/bin/session-log-compile.sh >>$HOME/.local/state/session-logs/.cron.log 2>&1`.
- **Manual**: just run the script when you want; the agents will read
  whatever's most recent in `~/.local/state/session-logs/`.

## Re-reading the script

Because the unit is `Type=oneshot` with `ExecStart=` pointing at the
script, every fire re-reads the script. **No `daemon-reload` needed**
when you edit the script itself — only when you edit the unit files.
