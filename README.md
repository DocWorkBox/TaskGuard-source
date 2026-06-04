# Codex Process Manager

macOS menu bar companion app for inspecting Codex-related background services and common local development servers.

## Run

```bash
./script/build_and_run.sh
```

The app scans current-user processes with `ps` and listening ports with `lsof`, groups likely Codex/dev services, and only suggests cleanup for high-confidence stale groups.

It does not use `sudo` and does not automatically kill processes without confirmation.
