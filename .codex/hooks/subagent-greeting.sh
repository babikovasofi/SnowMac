#!/usr/bin/env bash
# SubagentStart hook — "greets" every subagent: injects the harness greeting, plus the
# exec contract for executing agents (agent file carries the `harness:exec` marker).
# Fail-open: any error -> no injection, subagent still starts.
set -euo pipefail
trap 'exit 0' ERR
command -v jq >/dev/null 2>&1 || exit 0

ROOT="${HARNESS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
STDIN="$(cat)"
AGENT="$(printf '%s' "$STDIN" | jq -r '.agent_type // empty')"

CTX="$(cat "$ROOT/.codex/harness/greeting.md" 2>/dev/null || true)"
[ -n "$CTX" ] || exit 0

AGENT_FILE="$ROOT/.codex/agents/${AGENT}.toml"
if [ -n "$AGENT" ] && [ -f "$AGENT_FILE" ] && grep -q 'harness:exec' "$AGENT_FILE"; then
  CTX="$CTX

$(cat "$ROOT/.codex/harness/exec-contract.md" 2>/dev/null || true)"
fi

jq -nc --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"SubagentStart", additionalContext:$c}}'
