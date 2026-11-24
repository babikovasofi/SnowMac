# Mini Dev-Loop Harness

Project skills and hooks for a Codex
development loop: **$plan → $build → $review → $debug**.

It is *files*, not a CLI. There is no `harness do "build X"`. Install it into another project with `$setup`; the harness activates
through skills, subagents and hooks. Read `.memory-bank/index.md` first.

## The loop

1. `$plan "<feature>"` — design before code. planner + skeptic read your Memory Bank,
   argue, and write a plan to `swarm-report/`, every file mapped to its exec agent.
2. `$build <slug>` — the executing agents that own the touched files implement the approved
   plan and run the tests. Multi-layer feature → several exec agents in parallel.
3. `$review <slug>` — the reviewer checks the diff against the plan and reports ship/rework.
4. `$debug "<error>"` — when a test fails, a build is blocked, or something breaks: the
   debugger reproduces, ladders hypotheses, isolates on evidence, applies the minimal fix.

Feature broke on test or review said `rework` → `$debug` → back to `$build`. The **Stop
test-gate hook** blocks "done" until the project's tests actually run and their output is
cited — testing after every feature is enforced, not optional.

Around the loop:
- `$research "<topic>"` — two levels. **Basic** by default («ресеч», «найди в интернете»):
  built-in Codex web search, 2–4 queries, numbered findings with links, no Tavily.
  **Deep** only when the user says «глубокий ресерч» / «Tavily»: Tavily MCP, every claim
  checked, report in `swarm-report/research-<slug>-<date>.md` that `$plan` can read. Never
  upgrade to deep on your own. Tavily key lives only in `.env` (see `.env.example`).
- `$mutation [slug]` — mutation testing of the changed lines; runs inside every `$review`.
- `$new-agent <stack>` — onboard a stack-specific executing agent (see "Agents").
- `$memory-bank` (Steward), `$memory-bank-defrag` — keep `.memory-bank/` current.
- `$transcribe <file>` — local meeting transcript with speaker labels.
- `$anti-ai-slop-writing` — rules for every text a human reads, chat included.

## Skills fire by themselves

The user talks normally; nobody has to type a skill mention. Match the request to a skill
and read its SKILL.md without being asked. The `prompt-router.sh` hook repeats this map
on every prompt and names the likely skill when the words clearly match.

| User says / situation | Skill |
|---|---|
| Any task with no mode word: «сделай», «добавь», «исправь», «переделай» | `$day` → `$plan` → `$build` → `$review` |
| «ночь», «работаем ночью», «пока я сплю» | `$night` |
| «стоп ночь», «я проснулась», «что сделал за ночь» | `$night-stop` |
| «не работает», «ошибка», «упал тест», a stack trace | `$debug` |
| «проверь код», «ревью», «готово к мержу?» | `$review` (includes `$mutation`) |
| «проверь тесты», «мутационное тестирование» | `$mutation` |
| «ресеч», «найди в интернете», «поищи», «сравни» | `$research` basic (web search, no Tavily) |
| «глубокий ресерч», «с Tavily», «deep research» | `$research` deep (Tavily) |
| An audio / video file, «расшифруй запись» | `$transcribe` |
| «агент под <стек>», unowned files, a new manifest in the repo | `$new-agent` |
| «почисти memory bank», end of every night | `$memory-bank-defrag` |
| «поставь харнесс в проект <путь>» (source is this Codex installation) | `$setup` |
| Writing any text for people | `$anti-ai-slop-writing` (always on) |
| End of every reply | Memory Bank Steward check |

## Modes: day and night

Two work modes. Pick by the user's words:

- **"день"** / **"day"** → `$day` (`.agents/skills/day/SKILL.md`).
- **"ночь"** / **"работаем ночью"** / **"night"** → `$night` (`.agents/skills/night/SKILL.md`).
- Neither said → **day** is the default.

| | Day | Night |
|---|---|---|
| Questions | Only at checkpoints: start, after plan, end | All before going autonomous; leftovers in the morning report |
| Before `$build` | Short numbered plan → "всё устраивает?" | Short numbered night brief → "всё верно? что изменить/добавить?" |
| User edits the plan | Edits go through skeptic, plan re-shown, until "ок" | Same |
| Loop | `$plan → $build → $review → $debug` | Same loop per task, skeptic stands in for the user |
| Git | Current branch | Worktree `.codex/worktrees/night-<ts>`, branch `night/<slug>-<ts>` from `main`, local commits, no push (except the defrag PR) |
| End | Summary + questions (checkpoint 3) | `$memory-bank-defrag`, authorized PR if applicable, then `swarm-report/night-<date>.md`; `$night-stop` stops early |

## Commits, PRs, push

- **English only** — commit messages, PR titles and bodies, branch names.
- **Conventional Commits** (https://www.conventionalcommits.org):
  `<type>(<optional scope>): <description>`
  - types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`,
    `chore`, `revert`.
  - description: imperative, lowercase start, no trailing period, ≤72 chars for the line.
  - body (optional): blank line after the subject, explains *why*.
  - breaking change: `!` after type/scope (`feat(api)!: ...`) + `BREAKING CHANGE:` footer.
- **PR title** = a Conventional Commit subject. PR body: what changed, why, how tested.
- Commit bodies and PR text follow `$anti-ai-slop-writing` (see Working agreement).
- **Before every push** (incl. opening a PR, which pushes the branch) — show a short,
  clear list and ask right away, in the same message:
  ```
  Push: <branch> → <remote>/<branch>
  Commits:
  - <hash> <subject>
  - ...
  Files: <N changed, +X / −Y>
  ```
  Then use the checkpoint form: "Пушить?" — options "Да, пушить" / "Нет, не пушить".
  Push only after an explicit yes. Force-push is blocked by the `guard.sh` hook — the user
  runs it themselves after a separate yes.
- **One exception:** `$memory-bank-defrag` run unattended at the end of `$night` may push
  its own `memory-defrag/<YYYY-MM-DD>` branch and open a PR without asking. Never `main`,
  never another branch, never force. Enable publication explicitly in the night brief. The PR link goes into the morning report.

## Agents

Use GPT-6.2 Sol (`gpt-6.2-sol`) with `medium` reasoning for planning and plan
critique, and `low` reasoning for code changes, debugger fixes and code review.
The main session defaults to `low` in `.codex/config.toml`.

Use Codex custom agent roles from `.codex/agents/*.toml` when the host exposes
them through `spawn_agent`. Planner, skeptic and reviewer are read-only. Debugger may
apply the minimal fix. Exec agents own disjoint paths and return
`.codex/harness/exec-contract.md` YAML. If a host exposes only generic roles,
pass the role's developer instructions with the task and explicitly select the
required model and reasoning effort. If delegation is unavailable, use the
main session when it has the required settings and validate the same return
contract. If the host cannot select the required settings, report that limit.
When the host supports it, wait for agents and inspect results
before moving to the next stage.

### Executing agents

| Agent | Scope (globs) | Test command | Signal files |
|---|---|---|---|
| _none yet. Add with `$new-agent <stack>`._ | | | |

The planner maps every affected file. For uncovered scopes, offer a stack agent
or the main agent with the execution contract at the plan checkpoint.

### Caveman activation

Prefix each agent prompt with both lines:

```
CAVEMAN MODE ACTIVE (full). Respond terse like smart caveman. All technical substance stay. Only fluff die.
Drop articles, filler, pleasantries, hedging. Fragments OK. Technical terms, code, paths, errors exact. Code, commits, PRs: write normal.
```

## Tests and hooks

The planner designs given/when/then tests. Exec agents implement them and run
the applicable suites. Review checks each case and runs mutation testing when
supported. Verify and lint hooks run for detected code edits. The Stop hook
asks for test evidence before completion. Configure command, timeouts and
thresholds in `.codex/harness/quality.json`. `HARNESS_VERIFY=0` and
`HARNESS_LINT=0` disable the corresponding automatic check for the session.

Read the Memory Bank index and applicable decisions at session start. For code
search use the ast-index workflow in `.codex/harness/code-index.md`, falling
back to rg and file reads. `.codex/hooks.json` registers Codex hooks.

## Checkpoint forms

At checkpoints use a native question form first. Use
`request_user_input_async` on hosts that expose it and wait for the answer
before work that depends on it. Use `request_user_input` when available in
the current mode. When the host provides neither tool, show numbered options
in chat and wait at a required checkpoint. Use only the supported option count
(2–3 for `request_user_input`), recommend one first, and put the concrete step,
`Плюсы` and `Минусы` in each description. Keep free-text correction available.
Use Codex's separate approval flow for sandbox permissions. Run independent
work while waiting when possible.

## Working agreement (every agent respects)

- **Accuracy > speed.** Verify before claiming done. Tests pass ≠ feature works.
- **Read the Memory Bank first.** `.memory-bank/index.md` is the source of truth for what
  the project is (the SessionStart hook loads it). Missing → say so, do not invent facts.
- **Disagree loudly.** Request wrong, scope bloated, plan flawed → say it, offer one
  alternative with плюсы / минусы. Do not play along.
- **Stay in your scope.** An exec agent touches only its layer. Cross-layer impact →
  note it in the return for the sibling agent, do not reach across.
- **Edit > Write.** Change existing files; add new ones only when the plan calls for them.
- **No comments that narrate code.** Only *why* comments for a non-obvious invariant.
- **Test ratchet.** Never delete, skip, or weaken a test to make it pass. Red test → fix
  the code, or report it red.
- **Security by default.** No injection, no hardcoded secrets. Validate external input at
  the boundary. Never read `.env` or print keys (the guard catches common shell invocations; keep secrets out of prompts and file tools).
- **Ask before risky actions:** deleting files/branches, force push, dropping deps,
  anything visible outside the repo.
- **Proposals show плюсы / минусы.** Any proposal — in chat or as a question option — lists
  its плюсы and минусы when it has them. One-sided proposals are not allowed.
- **Questions: only at checkpoints, to the point, with options.**
  - **When:** at the **start** (before planning), **after the plan** (before `$build`), or
    at the **end** (after review / report). Never in the middle of work — the user must not
    have to sit at the screen waiting. A doubt mid-work → take the safest reasonable
    option, note it, bring it to the next checkpoint. Work cannot continue at all → stop
    the run; that stop is the end checkpoint.
  - **What:** only what changes the next step and cannot be found in the repo / Memory
    Bank. Always one form with 2–3 reasonable options — real, true to
    this project, never invented, no filler choices, recommended first.
  - **Context first, then questions.** Before asking, read `.memory-bank/` (incl.
    `decisions.md`), `AGENTS.md`, `README*`, manifests, recent commits; draft your best
    answer — then ask only about the gaps. Options come from what you read.
  - **Each option = concrete step + плюсы + минусы** (in its description). Where it is a
    real choice, include a "nothing / leave as is" option.
  - **Decision log.** Every user answer that settles something goes to
    `.memory-bank/decisions.md`: `<YYYY-MM-DD> · context · choice · why`. Create the file on
    first use. Already decided there → do not ask again, follow it.
- **Memory Bank Steward after every reply.** The main agent ends every reply with the
  `$memory-bank` check (`.agents/skills/memory-bank/SKILL.md`): importance ≥ 2 →
  `MEMORY_SUGGESTION` block; otherwise one line `NO_MEMORY_UPDATE` with the reason. The
  "Применить?" question goes into the next checkpoint form, not mid-work. Apply only after
  yes. Never write secrets. Night: do not touch `.memory-bank/`, suggestions go into the
  morning report.
- **Anti-AI-slop, always on.** Every text a person reads follows
  `.agents/skills/anti-ai-slop-writing/SKILL.md` — nobody has to ask for it.
  - **Chat replies:** caveman compression stays; on top, the skill's bans (banned words and
    phrases, AI openers / closers, fake balance, hedging stacks, em dash at most 1 per 500
    words, emoji bullets, канцелярит, invented specifics). Rhythm rules do not apply to
    caveman.
  - **Prose** — reports (`swarm-report/night-<date>.md`, summaries), README / docs, commit
    bodies, PR text, bot copy, UI strings: the whole skill; Russian → also
    `references/ru-checklist.md`.
  - **Text inside code** — comments, docstrings, error / log messages, UI strings: the whole
    skill + `references/code-text.md`.
  - Not prose: identifiers, YAML agent returns, raw logs.
  - The Stop hook `slop-gate.sh` sends an answer with AI markers back for one rewrite.
- **Caveman always.** Every agent and every subagent answers in `/caveman` (full) — terse
  output, fewer tokens. Three layers, so one failing does not matter: the activation lines
  open every agent declaration, open every spawn prompt, and the SubagentStart greeting
  repeats them. See "Caveman activation".
