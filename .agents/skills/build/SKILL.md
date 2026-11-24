---
name: build
description: "Implement an already-approved plan from swarm-report/<slug>-plan.md. Routes each file to the exec agent that owns it (AGENTS.md registry), runs them in parallel per layer, checks their exec-contract returns and test results, writes an implementation report. Use AFTER $plan, never before."
---

# Skill: $build

ORCHESTRATOR. You route work to executing agents by file scope. No code edits in the
main loop. No questions to the user mid-build (see "Questions" in `AGENTS.md`).

## Invocation
`$build <slug>`

## Steps
1. **Find the plan**: `swarm-report/<slug>-plan.md`. Missing → abort:
   "Run `$plan \"<feature>\"` first."
2. **Check Blockers** in the plan. Any unresolved → abort and name it: the user resolves it
   at the after-plan checkpoint, not here.
3. **Route by owner**: group the plan's affected files by their `owner` (exec agent from
   the "Executing agents" registry in `AGENTS.md`). A file still without an owner (the user
   chose `general-purpose` at the checkpoint) → `general-purpose`.
4. **Spawn the exec agents** — one `spawn_agent` call each, in parallel when the feature spans
   several layers (single message, N calls, `agent_type: <owner agent name>`). Prompt:
   > CAVEMAN MODE ACTIVE (full). Respond terse like smart caveman. All technical substance stay. Only fluff die.
   > Drop articles, filler, pleasantries, hedging. Fragments OK. Technical terms, code, paths, errors exact. Code, commits, PRs: write normal.
   > Plan: swarm-report/<slug>-plan.md. Your scope: <the files for this agent>.

   Use the registered role where available and run code-writing agents on
   `gpt-6.2-sol` with `low` reasoning, including the generic fallback.
   For the generic fallback and every
   executing agent, include the greeting and the execution contract. Validate the
   YAML when collecting the reply, regardless of hook support.
   If one agent's output changes a contract another needs (`cross_layer_notes`), pass that
   note into the dependent agent's prompt — or run the provider first, then the consumer.
5. **Verify**: read each return's `status` and `tests_result`. Any `blocked`, `fail` or
   `not_run` → do NOT claim success. Report the failures verbatim and stop; route to
   `$debug` (day: at the end checkpoint; night: per rails).
6. **Write** `swarm-report/<slug>-build.md`: per-agent changed files, test commands +
   real results, cross-layer notes, assumptions.
7. **Report** to user: status per scope + test results. Quote real output — no "done"
   without proof.
