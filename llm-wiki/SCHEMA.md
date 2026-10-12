# llm-wiki SCHEMA — how the agent maintains this wiki

This project follows the **LLM wiki pattern** (raw source: [[sources/llm-wiki-pattern]] — the
karpathy gist, stored verbatim in `sources/`). The wiki is a persistent, compounding artifact:
the LLM writes and maintains all of it; the human sources, explores, and asks.

## Layers

1. **Raw sources** (`sources/`) — immutable. Copies of gists, docs, run reports. Never edited.
2. **The wiki** (everything else in `llm-wiki/`) — LLM-owned. Summaries, architecture, runbooks,
   reference pages. Kept consistent, cross-linked, current.
3. **This schema** — the operating manual. Co-evolve it with the human.

## Page map

| Page | Purpose |
|---|---|
| [[index]] | catalog of every page, one line each — read FIRST when answering queries |
| [[log]] | append-only chronological record (ingests, builds, restores, lint passes) |
| [[overview]] | what this system is, the thesis, current state |
| [[components/ollama]] | Ollama layout, paths, quirks on this machine |
| [[components/pi]] | Pi managed install, launcher resolution, config files |
| [[components/node-runtime]] | how node is installed, why brew chains must be captured |
| [[components/seven-zip]] | 7zz acquisition, switch quirks, SIGPIPE traps |
| [[architecture/backup-archive-layout]] | the .7z contents, byte-for-byte contract |
| [[architecture/backup-flow]] | staging → compression → sidecars, options |
| [[architecture/restore-flow]] | extract → rename-aside → reinstall → verify |
| [[architecture/webapp]] | zero-dep server, API surface, job runner |
| [[runbooks/offline-restore]] | the actual procedure when the internet is gone |
| [[runbooks/fresh-os-reload]] | full walkthrough incl. release bundle bootstrapping |
| [[reference/paths]] | every path this tool touches + the OBD_* override table |
| [[reference/decisions]] | ADRs: what we chose and why |
| [[reference/troubleshooting]] | failure modes seen so far + fixes |

## Operations

### Ingest (after any source lands: plan doc, new code, a restore run, a gist)
1. Read the source fully.
2. Update the relevant topic pages (a source typically touches 2–5 pages).
3. Update [[index]] one-liners for every page touched.
4. Append to [[log]]: `## [YYYY-MM-DD] ingest | <title>` followed by 1–3 bullets.
5. If the source contradicts existing claims — fix the claim, note the contradiction in [[log]].

### Query (human asks a question)
1. Read [[index]] → open the relevant pages → synthesize an answer with page references.
2. If the answer is valuable and reusable, file it as a new page (then index + log it).

### Lint (periodic health check)
- Orphan pages (no inbound links), stale claims vs. current code, missing cross-links,
  contradictions between pages, facts that could be verified by running a command.
- Record lint passes in [[log]] (`## [date] lint | scope`).

## Conventions

- Wiki-links `[[page-slug]]`; page files are lowercase-kebab `.md`.
- Every page starts with a one-line purpose sentence (used verbatim in [[index]]).
- Facts about the machine (paths, versions) always carry an "as of" date.
- Commands are shown as runnable blocks; expected output noted when it matters.
- Code behavior claims must match `scripts/` — when scripts change, the wiki changes same-session.
