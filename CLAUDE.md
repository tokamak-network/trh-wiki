# trh-wiki Schema

This is the schema document for the TRH Platform Wiki. Read this before any wiki operation.

The wiki captures accumulated knowledge about the TRH Platform ecosystem:
- **trh-platform** — Electron desktop app (TypeScript/React)
- **trh-sdk** — Go CLI deployment engine
- **trh-backend** — Go REST API (Gin + GORM)
- **trh-platform-ui** — Next.js web frontend
- **crossTrade** — DeFi cross-chain protocol integration

---

## Directory Layout

```
trh-wiki/
├── CLAUDE.md          # This file — the schema (you are reading it now)
├── raw/               # Source materials — NEVER edit these files
│   ├── inbox/         # Drop zone for new documents (unclassified)
│   ├── architecture/  # Architecture docs, design docs
│   ├── decisions/     # Architecture Decision Records (ADR)
│   └── assets/        # HTML diagrams, screenshots (referenced by wiki pages)
├── wiki/              # LLM-maintained markdown — humans read, LLM writes
│   ├── index.md       # Master index — update on every ingest
│   ├── log.md         # Append-only operation log
│   ├── overview/      # High-level architecture maps
│   ├── components/    # Per-repository deep-dives
│   │   ├── core/      # Core repos (trh-platform, trh-sdk, trh-backend, etc.)
│   │   └── integration/ # Integration repos (cross-trade, thanos-bridge, etc.)
│   ├── concepts/      # Core technical concepts
│   ├── workflows/     # Step-by-step operational guides
│   ├── decisions/     # ADR summaries with rationale
│   └── troubleshooting/ # Known issues and resolutions
└── ref/               # External reference links and API specs
```

**raw/ is a drop zone — no classification needed.**
New documents go into `raw/inbox/`. The ingest agent reads the content and determines which wiki pages to create or update.

**Rule**: `raw/` is read-only. If a source needs correction, add a new file noting the correction — do not edit the original.

---

## Page Format

Every wiki page must start with this frontmatter:

```yaml
---
updated: YYYY-MM-DD
sources:
  - raw/path/to/source.md
related:
  - "[[other-page]]"
  - "[[another-page]]"
tags: [component|concept|workflow|decision|troubleshooting]
---
```

Then the page body:
- One-paragraph summary at the top (what this page is about)
- Sections as needed
- **Always link to related pages** using `[[page-name]]` syntax
- **Always cite sources** — every factual claim should trace to a `raw/` file

---

## Operations

### `ingest [filename]`

When the user says "ingest [file]" or drops a new file into `raw/inbox/`:

1. Read the source file fully
2. Identify key facts, decisions, concepts, and components it touches
3. Determine which wiki section the content belongs to (component / concept / workflow / decision / troubleshooting)
4. Check `wiki/index.md` to find all pages that should be updated
5. Update each affected page — revise summaries, add new facts, note contradictions
6. If a new concept appears with no existing page, create one
7. Update `wiki/index.md` with any new pages created
8. Append an entry to `wiki/log.md`:
   ```
   ## [YYYY-MM-DD] ingest | <source filename>
   Pages updated: [[page1]], [[page2]], ...
   New pages: [[new-page]] (if any)
   Key additions: <one sentence>
   ```

A single source typically touches 5–15 wiki pages. Do not skip cross-references.

### `query [question]`

When the user asks a question:

1. Read `wiki/index.md` to find relevant pages
2. Read those pages in full
3. Synthesize an answer with inline citations `[[page-name]]`
4. If the answer is valuable and non-trivial, ask the user: "Should I file this as a wiki page?"
5. If yes, create the page and log it:
   ```
   ## [YYYY-MM-DD] query | <question summary>
   Answer filed as: [[page-name]] (if saved)
   ```

### `lint`

When the user says "lint":

1. Read all pages in `wiki/`
2. Check for:
   - **Broken links** — `[[page]]` references that point to non-existent files
   - **Orphan pages** — pages with no inbound links
   - **Unsourced claims** — facts with no `raw/` citation
   - **Stale pages** — `updated` date older than 60 days (flag, don't auto-update)
   - **Missing concept pages** — concepts mentioned across multiple pages but lacking their own page
   - **Contradictions** — conflicting facts across pages
3. Report findings as a list. Do not auto-fix — present findings and ask the user which to address.
4. Log the lint pass:
   ```
   ## [YYYY-MM-DD] lint
   Issues found: <N>
   Critical: <list>
   ```

---

## Conventions

### Linking
- Always use `[[page-name]]` for internal links (Obsidian wiki-link format)
- The page name is the filename without `.md` and without the path prefix
- Example: link to `wiki/concepts/presets.md` as `[[presets]]`

### Component names (canonical)

**Core**
- `trh-platform` — the Electron desktop app
- `trh-sdk` — the Go deployment CLI
- `trh-backend` — the Go API server
- `trh-platform-ui` — the Next.js web UI
- `tokamak-thanos` — OP Stack v1.7.7 fork (op-node, op-batcher, op-proposer)
- `tokamak-thanos-stack` — Terraform + Helm IaC for EKS
- `tokamak-thanos-geth` — go-ethereum OP Stack fork
- `tokamak-rollup-hub-v2` — Rollup Hub marketing website

**Integration**
- `cross-trade` — the CrossTrade DeFi integration module
- `thanos-bridge` — L1↔L2 asset bridge DApp
- `commit-reveal2` — Distributed Random Beacon smart contracts
- `drb-node` — DRB Go node (Leader/Regular architecture)

### Preset names (canonical)
- `General` — base L2, no DeFi modules
- `DeFi` — includes CrossTrade
- `Gaming` — gaming-optimized stack
- `Full` — all modules including CrossTrade

### Deployment targets (canonical)
- `local` — Docker Compose on developer machine
- `ec2` — AWS EC2 via Terraform

### Writing style
- English only in wiki pages
- Present tense for current state ("The backend exposes...")
- Past tense for historical decisions ("We chose X because...")
- Avoid "we" in concept pages — use component names directly

---

## What NOT to capture

Do not create wiki pages for:
- Things already derivable by reading the current code
- Git history (use `git log` instead)
- Debugging steps for resolved bugs (the fix is in the code; the ADR is in `decisions/`)
- Temporary state or in-progress work

Capture in wiki:
- **Why** decisions were made, not just what they are
- **Non-obvious constraints** that aren't apparent from the code
- **Cross-repo interactions** that span multiple repositories
- **Known failure modes** and their resolutions
- **Operational knowledge** that only exists in someone's head
