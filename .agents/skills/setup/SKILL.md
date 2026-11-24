---
name: setup
description: "Install or update this Codex Harness in another repository. Use when asked to install, transfer, or update the Harness."
---

# Install the Harness

1. Locate this Harness root and the target Git checkout. Inspect the target
   instructions, config, skills, agents, hooks and ignored paths.
2. Preview `python3 .codex/scripts/setup-merge.py <source> <target>`.
   For conflicts ask once at the start checkpoint. Offer merge, keep or replace
   per conflict with плюсы / минусы. Preserve unrelated config, settings, user
   Memory Bank, reports, and tuned quality thresholds. Keep backups when replacing.
3. Merge the reported conflicts surgically. Apply the nonconflicting install with
   `--apply`. Rerun the preview and verify discovered skills, TOML, JSON and hooks.
4. Read or initialize the target Memory Bank index from verified project facts.
   Open a new session in the target project so Codex discovers the files.
   Verify a checkpoint question and hook trust in that host.
