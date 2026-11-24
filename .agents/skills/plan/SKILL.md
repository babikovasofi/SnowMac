---
name: plan
description: "Design a feature before writing code. Spawns the planner + skeptic subagents that read the Memory Bank, argue, and write a plan to swarm-report/ with every file mapped to its exec agent. Use BEFORE $build, for any feature touching 2+ files or with unclear scope. Skip for typos and one-line fixes."
---

# Skill: $plan

You are the ORCHESTRATOR. Run the planner and skeptic and merge their output. Follow the delegation fallback in AGENTS.md. No code edits here.

## Invocation
`$plan "<one-sentence feature>"`

## Steps

1. **Slugify** the feature → `<slug>` (kebab-case, short).
2. **Read context yourself** (cheap, keeps subagents focused): `.memory-bank/index.md`
   if it exists. If it does not, note: "No Memory Bank found — plan rests only on the
   description." and continue.
3. **Spawn 2 subagents in parallel** — one message, two `spawn_agent` calls,
   `agent_type: planner` and `agent_type: skeptic`. Both use `gpt-6.2-sol`
   with `medium` reasoning. Prompt both:
   > CAVEMAN MODE ACTIVE (full). Respond terse like smart caveman. All technical substance stay. Only fluff die.
   > Drop articles, filler, pleasantries, hedging. Fragments OK. Technical terms, code, paths, errors exact. Code, commits, PRs: write normal.
   > Feature: <verbatim>.

   (Sharper, slightly pricier variant: run planner first, then pass its YAML into the
   skeptic prompt so it critiques the concrete plan. One extra round-trip. Use it when
   the feature is risky.) The two caveman lines open every spawn prompt (AGENTS.md →
   "Caveman activation"); the SubagentStart hook adds the rest of the greeting.
4. **Merge** (orchestrator only): take the planner's plan, apply the skeptic's HIGH/MED
   fixes. Unresolved HIGH and every `unowned_files` entry → **Blockers**. For an unowned
   file the blocker offers: `$new-agent <stack>` or `general-purpose` (плюсы / минусы).
5. **Write** `swarm-report/<slug>-plan.md`:
   ```
   # Plan: <feature>   (slug: <slug>)
   ## TL;DR
   ## Acceptance criteria  — observable "done" conditions; $review checks these
   ## Plan                 — merged steps + affected files (with owner agent)
   ## Test cases           — planner's given / when / then list; exec agents write them as is
   ## Blockers             — skeptic HIGH not yet resolved, unowned files (human decides)
   ## Out of scope
   ## Assumptions
   ```
6. **Report to user** (after-plan checkpoint): TL;DR + Blockers. Blockers go to the user
   here, as one form, before `$build` — never later.
