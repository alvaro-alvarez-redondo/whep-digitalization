# Claude layer

Everything in this repository that configures or guides Claude sessions. Start at the
top-level [CLAUDE.md](../CLAUDE.md) — it is loaded automatically; the files here are
referenced from it on demand.

## Map

| Path | What it is | When it's used |
|------|-----------|----------------|
| [`../CLAUDE.md`](../CLAUDE.md) | Project memory: standards + how to work | Auto-loaded every session |
| [`docs/`](docs/) | Repo knowledge base (read instead of rescanning) | Before editing pipeline code |
| [`commands/`](commands/) | Slash commands / workflows | Invoked with `/<name>` |
| [`guidelines/`](guidelines/) | Task playbooks (reusable prompts) | Read when doing that kind of task |

## Knowledge base (`docs/`)

Durable notes that let a session understand the repo by reading, not rescanning. Read
`architecture.md` first; the rest are references.

| File | Purpose |
|------|---------|
| [`docs/architecture.md`](docs/architecture.md) | Mental model: stages, data flow, canonical schema, entry points, contracts |
| [`docs/codebase-map.md`](docs/codebase-map.md) | Every file and function by stage — lookup index instead of grepping |
| [`docs/constants-and-options.md`](docs/constants-and-options.md) | Full `get_pipeline_constants()` surface + `whep.*` option flags |
| [`docs/conventions.md`](docs/conventions.md) | How to run & test, load order, determinism, parallelism, gotchas |
| [`docs/common-changes.md`](docs/common-changes.md) | Touch-point recipes for frequent edits (column, rule, constant, export, test) |

## Commands

- [`commands/autocode.md`](commands/autocode.md) — `/autocode`: autonomous optimization
  loop. Configured by `autocode.toml` (repo root); writes run state to
  [`progress.md`](progress.md) and [`results.tsv`](results.tsv) (in this `.claude/` folder).

## Guidelines (task playbooks)

| File | Use for |
|------|---------|
| [`guidelines/refactoring.md`](guidelines/refactoring.md) | Auditing and modernizing R scripts; iterative refactor passes |
| [`guidelines/performance.md`](guidelines/performance.md) | Profiling and optimizing hot paths |
| [`guidelines/testing.md`](guidelines/testing.md) | Writing/updating `testthat` tests |
| [`guidelines/constants.md`](guidelines/constants.md) | Centralizing hard-coded literals into `01-constants.R` |
| [`guidelines/readme-generation.md`](guidelines/readme-generation.md) | Regenerating the project `README.md` |

## Conventions

- Files use plain Markdown with optional `name` / `description` frontmatter.
- This layer is Claude Code-native: project memory is `CLAUDE.md`, commands live in
  `commands/`. Do **not** reintroduce the GitHub Copilot `*.instructions.md` convention.
- There are no project-specific skills yet. If one is added, create `.claude/skills/` and
  list it here.
