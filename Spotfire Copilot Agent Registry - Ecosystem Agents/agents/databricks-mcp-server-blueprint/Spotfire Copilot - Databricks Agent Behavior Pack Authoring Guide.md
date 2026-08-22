# Databricks Agent — Domain Behavior Pack Authoring Guide

**Audience:** a domain expert who wants to turn the generic **Databricks Agent**
into an assistant for *their* domain (petroleum, semiconductor, energy ops,
retail, logistics, …) **without writing any code**.

**The idea:** the agent's *logic* is fixed. What makes it a *your‑domain* agent is
a small folder of text files — the **behavior pack** — that you author and hand
to whoever deploys the agent. They mount your folder, point four URLs at your
Databricks resources, and the agent becomes your domain expert. No rebuild, no
Python.

> If you are building a *baked* internal flavor (a new `databricks_<domain>_agent`
> package that ships in the image), that is a code change and is out of scope
> here. This guide covers the **mount‑a‑pack** model against the shared
> `databricks_agent`.

---

## Table of contents

- [1. How the agent uses your pack](#1-how-the-agent-uses-your-pack)
- [2. What you must provide (at a glance)](#2-what-you-must-provide-at-a-glance)
- [3. Folder structure](#3-folder-structure)
- [4. File-by-file reference](#4-file-by-file-reference)
  - [4.1 `pack.yaml`](#41-packyaml)
  - [4.2 `system_prompt.md`](#42-system_promptmd)
  - [4.3 `AGENTS.md`](#43-agentsmd)
  - [4.4 `help.md`](#44-helpmd)
  - [4.5 The `skills/` folder](#45-the-skills-folder)
- [5. Skill format in depth (`SKILL.md`)](#5-skill-format-in-depth-skillmd)
- [6. The four capabilities & their tool names](#6-the-four-capabilities--their-tool-names)
- [7. Databricks prerequisites (what must exist)](#7-databricks-prerequisites-what-must-exist)
- [8. Validation checklist (before you hand it off)](#8-validation-checklist-before-you-hand-it-off)
- [9. Deploy hand-off (what the platform team needs)](#9-deploy-hand-off-what-the-platform-team-needs)
- [10. Common mistakes](#10-common-mistakes)
- [11. Complete example pack](#11-complete-example-pack)

---

## 1. How the agent uses your pack

The Databricks Agent connects to up to **four** Databricks‑managed capabilities:

| Capability | What it's for |
| --- | --- |
| **Genie** | Natural‑language **data retrieval** over your tables (the primary data path). |
| **Unity Catalog (UC) functions** | Your domain's **computations** (diagnostics, scoring, forecasting…), exposed as callable tools. |
| **AI Search (Vector Search)** | **Document retrieval** (RAG) over your indexed reference material. |
| **SQL (DBSQL)** | Catalog **discovery** (`SHOW`/`DESCRIBE`) and a complex‑SQL **fallback**. |

The agent already knows *how* to route a question to the right capability. Your
pack supplies the **domain voice and knowledge**:

- **`system_prompt.md`** — the agent's persona + routing/tone for your domain.
- **`AGENTS.md`** — durable domain knowledge (terms, thresholds, formulas).
- **`help.md`** — the exact text shown when a user types “help”.
- **`skills/`** — one folder per capability with a `SKILL.md` telling the agent
  when and how to use it (and which tool names to expect).
- **`pack.yaml`** — a manifest that becomes the agent's public “card”
  (name/description/skills).

At deploy time the operator sets four URLs (Genie space, functions
catalog/schema, indexes, SQL) so the agent talks to *your* Databricks resources.

---

## 2. What you must provide (at a glance)

**Five things, all required:**

1. `pack.yaml`
2. `system_prompt.md`
3. `AGENTS.md`
4. `help.md`
5. a `skills/` folder containing your capability skills

Plus, to the platform team (not files in the pack): the **four Databricks
resource URLs** and a **service principal** (see §7 and §9).

---

## 3. Folder structure

Your pack is a single folder. Name it after your domain (e.g. `retail_pack/`).
The exact tree:

```
retail_pack/                         ← your pack folder (any name)
├── pack.yaml                        ← manifest (agent card)
├── system_prompt.md                 ← system prompt (persona + routing)
├── AGENTS.md                        ← domain knowledge (memory)
├── help.md                          ← "help / what can you do" text
└── skills/                          ← one sub-folder per skill
    ├── genie-data-questions/
    │   └── SKILL.md
    ├── uc-functions/
    │   └── SKILL.md
    ├── vector-search-retrieval/
    │   └── SKILL.md
    └── sql-execution/
        └── SKILL.md
```

**Rules for the `skills/` folder (important):**

- Each skill is its **own sub‑folder** containing a file named exactly
  **`SKILL.md`** (uppercase).
- The **sub‑folder name must equal the skill's `name:`** in its `SKILL.md`
  frontmatter. If they differ, the skill is **silently skipped**.
- Folder/skill names must be **lowercase letters, digits, and hyphens** only
  (1–64 chars), must not start/end with `-`, and must not contain `--`.
- A skill folder may include **extra supporting files** (e.g. a reference
  `.md`), but only `SKILL.md` is parsed as the skill definition.

---

## 4. File-by-file reference

### 4.1 `pack.yaml`

The manifest. It becomes the agent's **card** (the name/description/skills other
systems see) — it does **not** change behavior by itself; it advertises it.

```yaml
name: "Retail Store Operations Agent"     # display name in the agent picker
description: >-                            # one paragraph: what the agent does
  A retail store-operations assistant on Databricks. Answers sales and
  inventory questions via Genie, runs demand/stockout diagnostics with Unity
  Catalog functions, searches merchandising playbooks via AI Search, and
  discovers the catalog with SQL.
version: "0.1.0"                          # your pack version (free-form string)

# One entry per skill you want advertised on the card. `id` should match a
# skills/<id>/ folder (except help-and-capabilities, which is built-in).
skills:
  - id: genie-data-questions
    name: Genie data questions
    description: >-
      Retrieve sales, inventory, and store-event data with natural-language
      questions. Primary data-retrieval path.
    tags: [databricks, genie, data, retail]
  - id: uc-functions
    name: Unity Catalog functions
    description: >-
      Demand forecasting, stockout diagnosis, shrink classification, reorder
      recommendations.
    tags: [databricks, unity-catalog, functions, retail]
  - id: vector-search-retrieval
    name: AI Search retrieval
    description: >-
      Semantic search over merchandising and store-ops playbooks.
    tags: [databricks, vector-search, rag, retail]
  - id: sql-execution
    name: SQL discovery & fallback
    description: >-
      Catalog/schema/table discovery and a complex-SQL fallback; read-only by
      default.
    tags: [databricks, sql, discovery]
  - id: help-and-capabilities            # handled by built-in middleware
    name: Help and capabilities
    description: >-
      Onboarding and 'what can you do' — returns starter prompts.
    tags: [help, onboarding]
```

**Fields** (the `pack.yaml` **file** is required; individual fields fall back to
safe defaults if omitted, but supply them all so the card isn’t blank):

| Field | Recommended | Notes |
| --- | --- | --- |
| `name` | ✔ | Shown in the agent picker (defaults to “Databricks Agent”). |
| `description` | ✔ | One paragraph; what the agent does and for whom. |
| `version` | ✔ | Any string (e.g. `0.1.0`). Bump when you change the pack. |
| `skills[].id` | ✔ | Should match a `skills/<id>/` folder. Advertised on the card. |
| `skills[].name` | ✔ | Human‑readable label. |
| `skills[].description` | ✔ | Short blurb (routing/marketing). |
| `skills[].tags` | optional | Free‑form keywords. |

> `help-and-capabilities` is a special skill handled **by the agent’s built‑in
> middleware** using your `help.md`. Advertise it in `pack.yaml` but do **not**
> create a `skills/help-and-capabilities/` folder.

### 4.2 `system_prompt.md`

The agent's persona + how to route questions in your domain. Plain Markdown
(no frontmatter). This is loaded verbatim as the system prompt. Include:

1. **Identity** — one or two sentences: who the agent is and the domain.
2. **The four capabilities** — one bullet each, named for your domain (what your
   Genie space holds, what your functions do, what your indexes cover).
3. **Routing rules** — the decision order (discovery → data → documents →
   computation → SQL fallback). Copy the pattern from the example and adjust the
   wording to your domain.
4. **Guardrails** — “never invent tool output”, “retrieve real data before
   calling a function”, “read‑only by default; confirm before any write”.
5. **A table‑output policy** — tell the agent not to truncate tables with “…”
   and to relay all rows (the client parses these tables). See the example.
6. A pointer to `AGENTS.md` for domain knowledge.

Keep it focused on *routing and tone*. Put facts/thresholds in `AGENTS.md`.

### 4.3 `AGENTS.md`

Durable **domain knowledge** the agent should always have available (its
“memory”). Plain Markdown. Good things to include:

- **Key terms / entities** and how they’re named (e.g. equipment keys, SKUs,
  store ids, well names).
- **Formulas / thresholds** (e.g. “reorder when days‑of‑supply < 7”, “ISO 10816
  vibration Unacceptable > 18 mm/s”).
- **Categories / enumerations** (event types, bin definitions, plant types).
- **Composition patterns** — worked “retrieve‑then‑compute” chains for common
  questions (Genie → function → synthesize).
- **Response guidelines** — what to include in each kind of answer, rounding,
  units, and what to flag as urgent/safety‑critical.
- **Error handling** — cold‑start retry, Genie‑fails‑fall‑back‑to‑SQL, etc.

This file can be long — it is the agent’s reference sheet.

### 4.4 `help.md`

The exact text returned when a user types **“help”** or **“what can you do?”**.
It’s shown **verbatim** by the agent’s help middleware (the model isn’t even
invoked). Write it as a friendly capability summary with **concrete starter
prompts** grouped by capability. See the example.

### 4.5 The `skills/` folder

One sub‑folder per capability. For the Databricks Agent, provide these four
(names are the convention the routing expects):

| Skill folder | Capability it documents |
| --- | --- |
| `genie-data-questions/` | Genie (data retrieval) |
| `uc-functions/` | Unity Catalog functions (computation) |
| `vector-search-retrieval/` | AI Search (documents) |
| `sql-execution/` | DBSQL (discovery + fallback) |

You *may* add more skills, but these four map to the four capabilities the agent
routes to. The `sql-execution` skill is generic and can be copied almost as‑is
between domains; the other three should describe *your* data, functions, and
indexes.

---

## 5. Skill format in depth (`SKILL.md`)

Each `SKILL.md` has **YAML frontmatter** (between `---` fences) followed by
**Markdown instructions**.

```markdown
---
name: genie-data-questions
description: Retrieve retail sales and inventory data from the scoped Genie space using natural language. PRIMARY path for any question needing rows from the database — sales, inventory, store events, "which stores…".
allowed-tools: query_space_<SPACE_ID> poll_response_<SPACE_ID>
---

# Genie — Sales & Inventory (scoped space)

... Markdown instructions: when to use, workflow, fallback, output ...
```

### Frontmatter keys

| Key | Required | Rules |
| --- | --- | --- |
| `name` | ✔ | 1–64 chars, **lowercase letters/digits/hyphens** only, no leading/trailing `-`, no `--`. **Must equal the folder name.** |
| `description` | ✔ | 1–1024 chars. **This is the routing surface** — say *what it does and when to use it*, with domain keywords (see below). |
| `allowed-tools` | optional | **Space‑separated** list of the tool names this skill uses. See the warning below. |
| `license` | optional | Free‑form. |
| `compatibility` | optional | ≤500 chars; only if there are special requirements. |
| `metadata` | optional | Arbitrary `key: value` map. |

> ⚠️ **`allowed-tools` is whitespace‑separated, not comma‑separated.** The loader
> splits the value on spaces. If you write `allowed-tools: a, b, c` the parser
> reads the tokens `a,` and `b,` (with the commas attached), which won’t match
> real tool names. Write `allowed-tools: a b c`.

> **Progressive disclosure.** Only each skill’s `name` + `description` are placed
> in the model’s context up front. The **body** of `SKILL.md` is loaded **on
> demand** when the agent decides the skill is relevant. That is why the
> `description` must be strong and keyword‑rich — it is what triggers the skill.

### Writing a good `description`

- Lead with the **capability** and the **trigger intent**:
  *“Retrieve … data … PRIMARY path for any question needing rows … sales,
  inventory, ‘which stores…’.”*
- Include **domain nouns and verbs** users will actually say (SKU, stockout,
  reorder, shrink; or trip, vibration, ESD; or well, water cut, GOR).
- Distinguish it from the other skills (data → Genie; computation → functions;
  documents → AI Search; discovery → SQL).

### Writing the body

A useful body has these sections (see the example pack for full text):

- **What it is** — one paragraph naming your resource (the Genie space and its
  tables / the functions catalog / the index).
- **Tools** — the tool names (see §6) and what each does.
- **When to use** — 3–6 example questions that should trigger this skill.
- **Workflow** — the steps (ask → poll if needed → read result; or fetch inputs
  → call function → synthesize).
- **Fallback** — what to do when it fails (usually: fall back to `sql-execution`).
- **Output** — how to present the result (relay all rows, cite the tool/index).

---

## 6. The four capabilities & their tool names

The tool names the agent sees are **derived from your Databricks resources**.
Pin them in each skill’s `allowed-tools` (space‑separated) so the skill is
explicit:

| Capability | Tool name pattern | Example |
| --- | --- | --- |
| **Genie** | `query_space_<SPACE_ID>` and `poll_response_<SPACE_ID>` | `query_space_01f1…` `poll_response_01f1…` |
| **UC functions** | `<catalog>__<schema>__<function>` (dots → double underscore) | `acme_retail__store_ops__forecast_demand` |
| **AI Search** | `<catalog>__<schema>__<index>` | `acme_retail__store_ops__retail_playbook_index` |
| **SQL (DBSQL)** | generic, fixed names | `execute_sql` `execute_sql_read_only` `poll_sql_result` |

- **`<SPACE_ID>`** is the id in the Genie URL
  `…/api/2.0/mcp/genie/{space_id}` (the operator sets that URL).
- **`<catalog>__<schema>`** come from the functions/AI‑Search URLs
  `…/functions/{catalog}/{schema}` and `…/ai-search/{catalog}/{schema}`.

If you don’t yet know the space id, you can omit `allowed-tools` from the Genie
skill and add it later, or use a clearly‑marked placeholder like
`query_space_<SPACE_ID>` and tell the operator to replace it. The `sql-execution`
tool names are always the three fixed ones above.

---

## 7. Databricks prerequisites (what must exist)

Your pack only supplies words. Someone must build the **resources** the words
point at. Before the agent is useful, this must exist in your Databricks
workspace:

- [ ] A **Genie space** scoped to your domain tables → gives the
      `…/api/2.0/mcp/genie/{space_id}` URL.
- [ ] **Unity Catalog functions** registered under one `{catalog}.{schema}` →
      gives the `…/api/2.0/mcp/functions/{catalog}/{schema}` URL.
- [ ] One or more **Vector Search (AI Search) indexes** →
      `…/api/2.0/mcp/ai-search/{catalog}/{schema}` URL.
- [ ] A **DBSQL** endpoint → `…/api/2.0/mcp/sql` URL.
- [ ] A **service principal (OAuth M2M)** with permission to use the space,
      functions, indexes, and warehouse.

You don’t have to configure all four — the agent works with whatever is
connected — but Genie + SQL are the practical minimum. For how these map to the
agent and how to create/point them, see the [Databricks Agent User Guide](../Spotfire%20Copilot%20-%20Databricks%20Agent%20User%20Guide.md) and
the [LangGraph DeepAgents Server (OSS) Deployment Guide](../../agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md#databricks-agent).

---

## 8. Validation checklist (before you hand it off)

- [ ] The pack folder contains **`pack.yaml`, `system_prompt.md`, `AGENTS.md`,
      `help.md`, and `skills/`**.
- [ ] Every `skills/<id>/` has a **`SKILL.md`**, and each `SKILL.md`’s `name:`
      **exactly equals** its folder name.
- [ ] Skill/folder names are **lowercase‑hyphen** only.
- [ ] Each `SKILL.md` has a **`description`** rich with domain keywords.
- [ ] `allowed-tools` values are **space‑separated** (no commas).
- [ ] `pack.yaml` is **valid YAML** and lists the skills you shipped.
- [ ] `system_prompt.md` includes a **no‑ellipsis table policy** and the
      read‑only‑by‑default rule.
- [ ] No made‑up tool outputs or numbers anywhere in the text.
- [ ] You’ve written down the **four resource URLs** + the **service principal**
      to hand to the operator (see §9).

> Quick YAML sanity check (optional): open `pack.yaml` and each `SKILL.md` in an
> editor with a YAML linter, or ask whoever deploys to run the server’s pack
> loader against the folder before rollout.

---

## 9. Deploy hand-off (what the platform team needs)

Give the operator **two things**: your **pack folder** and the **connection
details**. They do the rest.

**1. The pack folder** — mounted into the server and selected via one env var:

```
DATABRICKS_AGENT_PACK_DIR=/config/databricks_agent      # path to your mounted pack
# (or just mount the pack at /config/databricks_agent and omit the var)
```

> Mounting note: a pack with a nested `skills/<id>/SKILL.md` subtree must be
> mounted from a **volume/PVC** (or baked into an image). A Kubernetes ConfigMap
> is flat and **cannot** hold the `skills/` subtree, so ConfigMap‑only works
> just for a single‑level pack. Use a volume for a full pack.

**2. The connection details** — the operator sets these (names shown for the
shared `databricks_agent`; a per‑domain deployment may use a prefixed form):

```
DATABRICKS_GENIE_MCP_SERVER_URL=https://<host>/api/2.0/mcp/genie/<SPACE_ID>
DATABRICKS_FUNCTIONS_MCP_SERVER_URL=https://<host>/api/2.0/mcp/functions/<catalog>/<schema>
DATABRICKS_VECTORSEARCH_MCP_SERVER_URL=https://<host>/api/2.0/mcp/ai-search/<catalog>/<schema>
DATABRICKS_DBSQL_MCP_SERVER_URL=https://<host>/api/2.0/mcp/sql
DATABRICKS_OAUTH_CLIENT_ID=<service-principal-app-id>
DATABRICKS_OAUTH_CLIENT_SECRET=<secret>     # kept as a secret, never in the pack
```

**Verify after deploy:**

- The agent card at `…/a2a/databricks_agent/.well-known/agent-card.json` shows
  **your** `name`/`description` (from `pack.yaml`).
- Typing **“help”** returns **your** `help.md` text.
- A data question triggers a Genie call; a computation triggers a UC function.

---

## 10. Common mistakes

| Symptom | Cause / fix |
| --- | --- |
| A skill is ignored | The folder name ≠ the `name:` in its `SKILL.md`. Make them identical. |
| A skill is ignored | `SKILL.md` has no `---` YAML frontmatter, or it isn’t valid YAML. |
| `allowed-tools` seems wrong | You used commas. Use **spaces**: `allowed-tools: a b c`. |
| Agent never picks a skill | The `description` is vague. Add concrete domain keywords and trigger intents. |
| Card shows the default (petroleum) name | Your pack wasn’t mounted/selected. Check `DATABRICKS_AGENT_PACK_DIR` / the mount. |
| `skills/` missing after mount | Mounted via a flat ConfigMap. Use a volume/PVC for the nested subtree. |
| Tables come back truncated with “…” | Add the no‑ellipsis table policy to `system_prompt.md` (see example). |
| Function called with made‑up numbers | Strengthen the “retrieve real data first; never invent inputs” rule in `system_prompt.md` and the `uc-functions` skill. |
| Genie tools don’t match | The `<SPACE_ID>` in `allowed-tools` doesn’t match the deployed Genie URL. Align them. |

---

## 11. Complete example pack

A minimal but complete pack for a fictional **Retail Store Operations** domain.
Copy the tree, then replace the **`<…>` placeholders** (space id, catalog,
schema, index/function names) with your real resources.

```
retail_pack/
├── pack.yaml
├── system_prompt.md
├── AGENTS.md
├── help.md
└── skills/
    ├── genie-data-questions/SKILL.md
    ├── uc-functions/SKILL.md
    ├── vector-search-retrieval/SKILL.md
    └── sql-execution/SKILL.md
```

### `pack.yaml`

```yaml
name: "Retail Store Operations Agent"
description: >-
  A retail store-operations assistant on Databricks. Answers sales and
  inventory questions via Genie, runs demand/stockout diagnostics with Unity
  Catalog functions, searches merchandising playbooks via AI Search, and
  discovers the catalog with SQL.
version: "0.1.0"

skills:
  - id: genie-data-questions
    name: Genie data questions
    description: >-
      Retrieve sales, inventory, and store-event data with natural-language
      questions. Primary data-retrieval path.
    tags: [databricks, genie, data, retail]
  - id: uc-functions
    name: Unity Catalog functions
    description: >-
      Demand forecasting, stockout diagnosis, shrink classification, and reorder
      recommendations.
    tags: [databricks, unity-catalog, functions, retail]
  - id: vector-search-retrieval
    name: AI Search retrieval
    description: >-
      Semantic search over merchandising and store-operations playbooks.
    tags: [databricks, vector-search, rag, retail]
  - id: sql-execution
    name: SQL discovery & fallback
    description: >-
      Catalog/schema/table discovery and a complex-SQL fallback; read-only by
      default.
    tags: [databricks, sql, discovery]
  - id: help-and-capabilities
    name: Help and capabilities
    description: >-
      Onboarding and 'what can you do' — returns starter prompts.
    tags: [help, onboarding]
```

### `system_prompt.md`

```markdown
You are a retail store-operations assistant. You connect to several
Databricks-managed MCP servers:

- **Genie** — a scoped Genie space over sales, inventory, and store events.
  **Your primary tool for retrieving data** with natural-language questions.
- **UC functions** — retail computations: `forecast_demand`, `diagnose_stockout`,
  `classify_shrink`, `recommend_reorder`.
- **AI Search (Vector Search)** — semantic search over merchandising and
  store-operations playbooks.
- **SQL** — catalog/schema/table discovery (SHOW/DESCRIBE) and a fallback for
  complex queries or when Genie fails.

## Routing (decision order)

1. Metadata / discovery (tables, columns, functions) → **SQL**.
2. Data from the database (sales, inventory, "which stores…") → **Genie first**;
   if the user also wants a computation, pass the values to a **UC function**.
3. Best practices / playbooks / policy → **AI Search**.
4. Computation / diagnosis / forecast:
   - values provided → call the **UC function directly**;
   - no values → **Genie to get the data**, then the **UC function**.
5. Genie failed or complex SQL needed → fall back to **SQL**.

Prefer Genie over hand-written SQL for data. Never call a function with guessed
values; retrieve real data first. Never invent tool outputs, function results,
retrieved passages, or table/column names — call a tool and relay its output.
Default to read-only; before any data-modifying SQL, restate the change and get
explicit confirmation. See AGENTS.md for domain knowledge and patterns.

Table output policy:
- Never use ellipsis markers ("...", "…", "etc.") or placeholder rows.
- Relay ALL rows the tool returned. If genuinely too large, show a clean subset
  of real, complete rows and put any truncation note AFTER the table.
- Never drop a row because a value is zero, null, or missing.
```

### `AGENTS.md`

```markdown
# Retail Store Operations — Agent Instructions

You help store-operations users work with a Databricks workspace through Genie,
Unity Catalog functions, AI Search, and SQL.

## Capability map
- **Genie** (`DATABRICKS_GENIE_MCP_SERVER_URL`) — sales/inventory/event data.
- **UC functions** (`DATABRICKS_FUNCTIONS_MCP_SERVER_URL`) — forecast_demand,
  diagnose_stockout, classify_shrink, recommend_reorder.
- **AI Search** (`DATABRICKS_VECTORSEARCH_MCP_SERVER_URL`) — playbooks.
- **DBSQL** (`DATABRICKS_DBSQL_MCP_SERVER_URL`) — discovery + fallback.

## Domain knowledge
- **Store id** format: `<REGION>-<NNN>` (e.g. `WEST-014`).
- **Days of supply** = on_hand_units / avg_daily_sales.
- **Stockout risk:** days_of_supply < 7 = WATCH; < 3 = CRITICAL.
- **Shrink** = (expected_inventory − actual_inventory) / expected_inventory.
- **Reorder point** = lead_time_days × avg_daily_sales + safety_stock.
- **Categories:** Grocery, Apparel, Electronics, Home, Seasonal.

## Composition patterns
- **Stockout triage** ("Which stores will stock out of SKU X?"): Genie → current
  on-hand + sell-through per store → `diagnose_stockout` → rank by risk.
- **Reorder planning** ("How much of SKU X should WEST-014 reorder?"): Genie →
  sales trend + lead time → `forecast_demand` → `recommend_reorder`.
- **Policy question** ("What's our markdown cadence for seasonal?"): AI Search.
- **Discovery** ("what tables exist?"): SQL SHOW/DESCRIBE.

## Response guidelines
- Cite which tools you used and what data was retrieved.
- Round money to whole currency units and rates to 1 decimal.
- Flag CRITICAL stockout risk and negative shrink prominently.
- Never fabricate sales or inventory numbers — always retrieve them.

## Error handling
- First call may cold-start (>30s) — retry once.
- Genie error/no results → fall back to `sql-execution` with explicit SQL.
- One SQL statement per call — split multi-statement scripts.
```

### `help.md`

```markdown
I'm a retail store-operations assistant. I can answer sales and inventory data
questions (Genie), run demand/stockout diagnostics (Unity Catalog functions),
search merchandising playbooks (AI Search), and explore the catalog (SQL).

### Ask data questions (Genie)
- "What were unit sales of SKU 12345 at WEST-014 last week?"
- "Which stores are lowest on days-of-supply for Electronics?"

### Compute & diagnose (functions)
- "Which stores will stock out of SKU 12345 in the next 7 days?"
- "How much of SKU 12345 should WEST-014 reorder?"

### Playbooks & policy (AI Search)
- "What's our markdown cadence for seasonal items?"

### Discover the catalog (SQL)
- "What tables are available?" / "Describe store_inventory"

Type "help" or "what can you do?" any time to see this again.
```

### `skills/genie-data-questions/SKILL.md`

```markdown
---
name: genie-data-questions
description: Retrieve retail sales, inventory, and store-event data from the scoped Databricks Genie space using natural language. PRIMARY path for any question needing rows from the database — unit sales, on-hand inventory, days-of-supply, store events, "which stores…". Genie writes and runs the SQL for you.
allowed-tools: query_space_<SPACE_ID> poll_response_<SPACE_ID>
---

# Genie — Sales & Inventory (scoped space)

A scoped Databricks Genie space (`/api/2.0/mcp/genie/{space_id}`) over the retail
tables. The primary way to retrieve data for this agent.

Data available:
- `store_sales` — daily unit/revenue sales by store and SKU.
- `store_inventory` — on-hand units, days-of-supply by store and SKU.
- `store_events` — operational events (stockouts, markdowns, resets).

> Tool names are space-scoped: `query_space_<SPACE_ID>` and
> `poll_response_<SPACE_ID>`, where `<SPACE_ID>` is the id in
> `DATABRICKS_GENIE_MCP_SERVER_URL`. Replace `<SPACE_ID>` with your real id.

## When to use
- "Unit sales of SKU 12345 at WEST-014 last week."
- "Which stores are lowest on days-of-supply for Electronics?"
- Any question needing rows from the database. Also use Genie to fetch the inputs
  a UC function needs when the user gives none (see `uc-functions`).

## Workflow
1. Ask with `query_space_...`; resolve vague windows into explicit dates first.
   Omit `conversation_id` on a new question.
2. If the response is in-progress, `poll_response_...` until complete.
3. Relay the result faithfully.

## Fallback
On error / no results / complex SQL, fall back to `sql-execution`. For
"what tables exist / describe X", use `sql-execution` directly.

## Output
Present the result table (all rows — no ellipsis) and the SQL when provided.
Never fabricate sales or inventory numbers.
```

### `skills/uc-functions/SKILL.md`

```markdown
---
name: uc-functions
description: Call Databricks Unity Catalog functions for retail computations (demand forecasting, stockout diagnosis, shrink classification, reorder recommendation). Use when the user needs a computation, diagnosis, forecast, or recommendation beyond SQL.
allowed-tools: <catalog>__<schema>__forecast_demand <catalog>__<schema>__diagnose_stockout <catalog>__<schema>__classify_shrink <catalog>__<schema>__recommend_reorder
---

# Unity Catalog Functions

The Functions MCP server exposes each UC function under `<catalog>.<schema>` as a
tool named `<catalog>__<schema>__<function>` (dots → double underscore).

## Available functions
- `..forecast_demand` — projected demand for a SKU/store over a horizon.
- `..diagnose_stockout` — stockout risk from on-hand + sell-through.
- `..classify_shrink` — categorize a shrink event.
- `..recommend_reorder` — reorder quantity from forecast + lead time.

## When to use
- "Which stores will stock out of SKU 12345?" (diagnose_stockout — retrieve data
  first; see Retrieve-then-compute)
- "How much should WEST-014 reorder of SKU 12345?" (forecast_demand → recommend_reorder)

## Retrieve-then-compute
When the user names a SKU/store/window instead of giving raw numbers:
1. Retrieve the values with Genie (`genie-data-questions`).
2. Call the function per entity (per store/SKU), not one aggregate.
3. Rank/synthesize and show the evidence.
Never feed a function guessed values.

## Output
State which function you called and the arguments. Relay the result verbatim;
add a one-line interpretation only if it helps the user act.
```

### `skills/vector-search-retrieval/SKILL.md`

```markdown
---
name: vector-search-retrieval
description: AI Search (Databricks Vector Search) over retail merchandising and store-operations playbooks. Use for policy, best-practice, and procedure questions — grounded in indexed documents rather than the sales/inventory database.
allowed-tools: <catalog>__<schema>__retail_playbook_index
---

# AI Search — Retail Playbooks (RAG)

The Vector Search server exposes each configured index as a retrieval tool.
Use it for document/knowledge questions, not for sales/inventory data (use Genie
for data).

## Available index
- `..retail_playbook_index` — merchandising and store-operations playbooks
  (markdown cadence, planogram resets, safety-stock policy).

## When to use
- "What's our markdown cadence for seasonal items?"
- "What's the policy for a planogram reset?"

## Workflow
1. Query the index with the user's question (or a focused rephrasing).
2. Ground your answer in the returned chunks only; cite them.
3. If nothing relevant is returned, say so — don't use unsupported knowledge.

## Output
A grounded answer citing the passages; note which index you queried.
```

### `skills/sql-execution/SKILL.md`

```markdown
---
name: sql-execution
description: Databricks SQL for (1) catalog/schema/table/function DISCOVERY via SHOW/DESCRIBE, and (2) a FALLBACK for complex queries or when Genie fails. For ordinary data retrieval prefer genie-data-questions; use this for metadata, user-provided SQL, or when Genie can't answer.
allowed-tools: execute_sql execute_sql_read_only poll_sql_result
---

# SQL Execution & Discovery (DBSQL)

The DBSQL MCP server executes SQL against Unity Catalog. Two roles here:
metadata/discovery and a fallback for data retrieval (Genie is primary).

## Tools
- `execute_sql_read_only` — read-only query. **Default choice.**
- `execute_sql` — may modify data/state. Use only on explicit request; confirm first.
- `poll_sql_result` — poll a long-running statement by id.

## When to use
- Discovery: `SHOW CATALOGS` / `SHOW SCHEMAS IN <catalog>` /
  `SHOW TABLES IN <catalog>.<schema>` / `DESCRIBE TABLE <catalog>.<schema>.<table>`.
- User-provided SQL, or a fallback when Genie errors / needs complex SQL.

## Workflow
1. Default to `execute_sql_read_only`.
2. Guard mutations — restate the change and confirm before any non-read-only SQL.
3. Fully qualify names as `catalog.schema.table`; backtick-quote identifiers with
   spaces. One statement per call.

## Output
Show the SQL, then the result as a complete Markdown table (all rows — no
ellipsis; truncation notes go after the table).
```

---

*That’s the whole recipe: author these files, point the four URLs at your
Databricks resources, mount the folder, and the Databricks Agent becomes your
domain’s agent — no code changes.*
