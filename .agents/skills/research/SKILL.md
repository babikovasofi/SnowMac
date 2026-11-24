---
name: research
description: "Web research in two levels. Default (basic) — plain web search with the built-in Codex web search tools, a few queries, numbered findings with links, no Tavily tokens spent. Deep — only when the user explicitly asks for deep research or Tavily («глубокий ресерч», «с Tavily», «deep research»): Tavily MCP `tavily-research` with the key from .env, multi-source search, every claim checked on its page, full report in swarm-report/. Every finding carries the link it came from."
---

# Skill: $research

ORCHESTRATOR. Two levels, chosen by the user's words — never upgrade to the deep level on
your own, it costs Tavily credits and many more tokens.

| | Basic (default) | Deep |
|---|---|---|
| Trigger | «ресеч», «сделай ресерч», «найди в интернете», «поищи» | «глубокий ресерч», «с Tavily», «deep research» |
| Tools | `web search` + `open the source page` (built-in) | Tavily MCP: `tavily_research`, `tavily_search`, `tavily_extract` |
| Budget | 2–4 searches, open ≤ 3 pages | 3–6 sub-questions, extract 3–8 pages |
| Output | Numbered findings with links in chat | Same in chat + report file in `swarm-report/` |
| Key | none | `TAVILY_API_KEY` in `.env` |

Basic not enough (sources thin, contradictory, topic wide)? Do not switch silently: say so
at the end and offer the deep level as an option (плюсы / минусы).

## Invocation
`$research "<topic>"` → basic. `$research глубокий "<topic>"` or words like «глубокий ресерч
с Tavily» → deep.

## Step 1 — Clarify (only if unclear, start checkpoint)

Topic clear → skip. Unclear or too broad → follow the question rules in `AGENTS.md`:
read `.memory-bank/` first, then one the checkpoint form with 2–3 reasonable options
(scope, region, time range), плюсы / минусы each, recommended first. This is the only
question point before the answer — none during the search.

## Basic level

0. Use the host's built-in web search and page reading. If browsing is unavailable,
   report it at the checkpoint.
1. Turn the topic into 2–4 precise queries (names, versions, year when freshness matters).
2. `web search` each query. Pick the strongest results: official docs, repos, primary
   sources over reposts.
3. `open the source page` at most 3 pages where a claim needs checking or a number needs the source.
4. Answer in chat (format below). No report file unless the user asks or `$plan` needs it.

## Deep level (Tavily)

1. Prefer an already connected Tavily tool. Otherwise configure the project MCP
   using README.md. Check the key with `.codex/scripts/env-has-key.sh TAVILY_API_KEY`
   without reading or printing the secret. If Tavily is unavailable, say so and
   offer basic research. Never repeat a key pasted into chat.
2. Split the topic into 3–6 concrete sub-questions.
3. `tavily_research` on the main question for the overview.
4. `tavily_search` per sub-question, `search_depth: "advanced"`, recent results where
   freshness matters.
5. `tavily_extract` on the 3–8 strongest URLs to check each claim is really there.
6. Answer in chat and write the report file (below).

## Rules for both levels
- Every finding needs ≥ 1 URL that a search actually returned. No URL → not a finding.
  Never invent or "fix up" links.
- Sources disagree → say so, cite both.
- Prefer primary sources (docs, official sites, papers, repos).
- Date time-sensitive facts (prices, versions, limits).
- Comparing options (libraries, APIs, vendors) → each gets плюсы / минусы with sources.

## Answer in chat

Short, numbered, caveman:
```
Ресеч (<basic | deep>): <topic>
1. <finding> — [source](url)
2. <finding> — [source](url), [source](url)
...
Расходятся: <conflict + both links, or "нет">
Не нашёл: <open gaps>
Отчёт: swarm-report/research-<slug>-<YYYY-MM-DD>.md   (deep only)
```

## Report file (deep level)

Write `swarm-report/research-<slug>-<YYYY-MM-DD>.md` (human-facing → follow
`.agents/skills/anti-ai-slop-writing/SKILL.md`, + `references/ru-checklist.md` if in Russian):
```
# Research: <topic>
Date: <YYYY-MM-DD> · Tool: Tavily (tavily-research MCP)
## Question
## Short answer
## Findings          — numbered, each with inline source links
## Conflicts
## Open questions
## Sources           — every URL used, with title
```
`$plan` can use this file as input.

## Rules
- The key lives only in `.env`. Never in chat, commits, reports, logs or URLs.
- Only facts backed by returned sources; unknown stays unknown.
- End with the Memory Bank Steward check (as every reply).
