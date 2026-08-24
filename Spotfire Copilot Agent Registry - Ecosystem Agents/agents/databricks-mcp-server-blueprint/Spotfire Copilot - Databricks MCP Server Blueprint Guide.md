# MCP Server Blueprint — Build Your Own Domain Agent

A step-by-step Databricks notebook that creates **4 production-ready MCP servers** powering a domain-specific AI agent through the Spotfire Agent harness.

> **Companion to the [Databricks Agent User Guide](../Spotfire%20Copilot%20-%20Databricks%20Agent%20User%20Guide.md).** That guide explains the agent; this notebook builds the Databricks resources it points at and generates a starter behavior pack. The notebook lives beside this guide: [`mcp_server_blueprint.ipynb`](./mcp_server_blueprint.ipynb).

---

## What This Notebook Builds

```
┌────────────────────────────────────────────────────────────────────┐
│                     YOUR DOMAIN AGENT                               │
│         (powered by Spotfire Agent + Behavior Pack)                 │
└────────────────────────────┬───────────────────────────────────────┘
                             │ MCP Protocol (Streamable HTTP)
          ┌──────────────────┼──────────────────┐
          │                  │                  │
          ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ UC Functions │  │ Genie Space  │  │  AI Search   │  │Databricks SQL│
│  MCP Server  │  │  MCP Server  │  │  MCP Server  │  │  MCP Server  │
│              │  │              │  │              │  │              │
│ AI-powered   │  │ Natural lang │  │ Semantic     │  │ Schema disc- │
│ domain       │  │ queries over │  │ search over  │  │ overy + SQL  │
│ functions    │  │ your tables  │  │ reference    │  │ fallback     │
│ (5-10 tools) │  │              │  │ documents    │  │              │
└──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘
```

By the end, you'll have:

| MCP Server | What It Does | Endpoint Pattern |
|------------|-------------|------------------|
| **UC Functions** | AI-powered domain expertise (diagnosis, assessment, forecasting) | `/api/2.0/mcp/functions/{catalog}/{schema}` |
| **Genie Space** | Natural language queries over your data tables | `/api/2.0/mcp/genie/{space_id}` |
| **AI Search** | Semantic retrieval over reference documents | `/api/2.0/mcp/ai-search/{catalog}/{schema}` |
| **Databricks SQL** | Schema discovery and complex SQL fallback | `/api/2.0/mcp/sql` |

Plus a **behavior pack** (folder of plain-text files) that configures the Spotfire Agent to route user questions to the right server.

---

## Prerequisites

Before starting, ensure you have:

- [ ] A **Databricks workspace** with Unity Catalog enabled
- [ ] At least **1-3 domain tables** loaded in Unity Catalog
- [ ] A **catalog and schema** where you can create functions, tables, and volumes
- [ ] A **Vector Search endpoint** (or permissions to create one)
- [ ] A **service principal** (or admin access to create one)
- [ ] Access to an **AI model endpoint** (e.g., `databricks-claude-sonnet-4` or `databricks-meta-llama-3-3-70b-instruct`)

### Recommended Knowledge

- Basic familiarity with Unity Catalog (catalogs, schemas, tables)
- Understanding of your domain — what questions do your experts answer daily?
- No MCP, Vector Search, or Genie experience required (the notebook guides you)

---

## How to Load the Notebook

The notebook ([`mcp_server_blueprint.ipynb`](./mcp_server_blueprint.ipynb)) lives in this folder of the **spotfire-copilot-docs** repository:
`Spotfire Copilot Agent Registry - Ecosystem Agents/agents/databricks-mcp-server-blueprint/`.

### Option A: Import from File (simplest)

1. Download [`mcp_server_blueprint.ipynb`](./mcp_server_blueprint.ipynb) from this folder
2. In your Databricks workspace, click **Workspace** in the left sidebar
3. Navigate to your user folder (or any folder you prefer)
4. Click **⋮** (kebab menu) → **Import**
5. Upload the `.ipynb` file
6. The notebook opens automatically — you're ready to start

### Option B: Import from URL

1. Copy the **raw URL** of `mcp_server_blueprint.ipynb` from the spotfire-copilot-docs repository
2. In Databricks: **Workspace** → **Import** → **URL**
3. Paste the URL and click **Import**

### Option C: Clone the Repository (recommended for teams)

1. In Databricks: **Workspace** → **Repos** → **Add Repo**
2. Paste the **spotfire-copilot-docs** repository URL
3. Click **Create Repo**
4. Open the notebook at `Spotfire Copilot Agent Registry - Ecosystem Agents/agents/databricks-mcp-server-blueprint/mcp_server_blueprint.ipynb`

> **Note:** The notebook runs on **serverless compute** — no cluster configuration needed.

---

## How to Use the Notebook

### Quick Start (5 steps)

1. **Edit Cell 3** — Set your configuration variables:
   ```python
   CATALOG = "your_catalog"          # Your Unity Catalog name
   SCHEMA = "your_schema"            # Schema for functions + indexes
   DOMAIN_TABLES = ["catalog.schema.table1", ...]  # Your data tables
   DOMAIN_NAME = "Your Domain"       # e.g., "Energy Operations"
   ```

2. **Run Cell 4** — Verify prerequisites (checks catalog, schema, tables exist)

3. **Run cells top to bottom** — Each step builds on the previous one:
   - Cells 5-7: Create UC Functions (the agent's domain expertise)
   - Cells 8-9: Create a Genie Space (natural language data access)
   - Cells 10-13: Generate and index reference documents (semantic search)
   - Cells 14-16: Grant permissions to the service principal
   - Cells 17-18: Generate the behavior pack (agent configuration)
   - Cells 20-21: Test connectivity and get your endpoint URLs

4. **Customize the behavior pack** — Review and edit the generated files:
   - `AGENTS.md`: Add your real domain thresholds, formulas, and patterns
   - `uc-functions/SKILL.md`: Verify all function names are listed
   - `genie-data-questions/SKILL.md`: Confirm table schemas are accurate

5. **Export and hand off** — Download the pack from the UC Volume (see below), then provide it + environment variables to the deployment team

> For the exact behavior-pack folder structure and the `SKILL.md` format (frontmatter, the rule that a skill's folder name must match its `name`, and space-separated `allowed-tools`), see the [Databricks Agent Behavior Pack Authoring Guide](./Spotfire%20Copilot%20-%20Databricks%20Agent%20Behavior%20Pack%20Authoring%20Guide.md).

### Estimated Time

| Phase | Duration | Notes |
|-------|----------|-------|
| Setup (config + prerequisites) | 5 min | Just editing variables |
| Build MCP Servers | 30-60 min | Most time is UC Function design |
| Permissions | 5 min | SQL grants + Genie space share |
| Behavior Pack | 15-30 min | Generated automatically, then customized |
| Validation | 5 min | Automated connectivity tests |
| **Total** | **1-2 hours** | Less with Databricks Assistant help |

---

## Notebook Structure (23 Cells)

| Cell | Step | What It Does |
|------|------|-------------|
| 1 | — | README: Architecture diagram and overview |
| 2 | — | Quick-Start Checklist (track your progress) |
| 3 | 1 | **Configuration** — edit your catalog, schema, tables, domain name |
| 4 | 2 | **Verify Prerequisites** — checks everything is accessible |
| 5-6 | 3 | **Create UC Functions** — guidance + SQL templates |
| 7 | 4 | **Verify Functions** — confirms COMMENTs are present |
| 8-9 | 5 | **Create Genie Space** — natural language data access |
| 10-11 | 6 | **Generate Reference Docs** — AI-generated domain documents |
| 12-13 | 7 | **Create AI Search Index** — chunk and index documents |
| 14-16 | 8 | **Grant Permissions** — service principal access |
| 17 | 9 | **Behavior Pack Guide** — structure, rules, best practices |
| 18 | 9b | **Generate Behavior Pack** — creates all 8 pack files |
| 19 | 10 | **Deploy Guide** — environment variables and verification |
| 20 | 11 | **Test Connectivity** — validates all 4 MCP servers |
| 21 | — | **Summary** — your endpoint URLs and next steps |
| 22-23 | — | **Appendices** — OAuth M2M flow and troubleshooting |

---

## Using the Databricks Assistant

Several steps can be accomplished interactively with the **Databricks Assistant** (Genie Code) instead of writing code manually. Look for the **💡 Assistant Shortcut** tips in the notebook at Steps 3, 5, 6, 7, and 9.

Example prompts:
- *"Create a UC function that diagnoses production defects based on sensor readings"*
- *"Generate reference documents about pharmaceutical manufacturing best practices"*
- *"Write a behavior pack for my supply chain domain with 8 UC functions"*

The Assistant generates the SQL/Python, creates cells, executes them, and troubleshoots issues — all within the notebook.

---

## What You'll Deliver to the Deployment Team

After running the notebook, you'll provide:

### 1. Behavior Pack (folder of files)

The notebook generates the pack into a UC Volume at:
```
/Volumes/<catalog>/<schema>/behavior_packs/<domain>_pack/
```

Structure:
```
your_domain_pack/
├── pack.yaml                        ← Agent identity and skill list
├── system_prompt.md                 ← Routing rules and guardrails
├── AGENTS.md                        ← Domain knowledge and patterns
├── help.md                          ← User-facing help text
└── skills/
    ├── genie-data-questions/SKILL.md
    ├── uc-functions/SKILL.md
    ├── vector-search-retrieval/SKILL.md
    └── sql-execution/SKILL.md
```

### 2. Export the Pack from Databricks

The pack lives in a UC Volume — it must be **exported** before it can be mounted into the agent container. Choose one method:

**Option A: Databricks CLI (recommended for automation)**
```bash
# Install: https://docs.databricks.com/dev-tools/cli/install.html
databricks fs cp -r \
  dbfs:/Volumes/<catalog>/<schema>/behavior_packs/<domain>_pack \
  ./my_domain_pack/
```

**Option B: Volumes UI (simplest for one-time download)**
1. In Databricks, navigate to **Catalog** → your catalog → schema → **Volumes**
2. Open the `behavior_packs` volume
3. Browse to `<domain>_pack/`
4. Download each file (or use the bulk download if available)

**Option C: Python (from a notebook or local script)**
```python
import subprocess
subprocess.run([
    "databricks", "fs", "cp", "-r",
    "dbfs:/Volumes/<catalog>/<schema>/behavior_packs/<domain>_pack",
    "./my_domain_pack/"
])
```

**Option D: REST API (from CI/CD pipelines)**
```bash
curl -H "Authorization: Bearer $TOKEN" \
  "https://<host>/api/2.0/fs/directories/Volumes/<catalog>/<schema>/behavior_packs/<domain>_pack" \
  | jq '.contents[].path'
# Then download each file with:
curl -H "Authorization: Bearer $TOKEN" \
  "https://<host>/api/2.0/fs/files/Volumes/<catalog>/<schema>/behavior_packs/<domain>_pack/<filename>" \
  -o ./<filename>
```

Once exported, this pack becomes one agent's behavior pack **inside an overlay bundle** — the folder the DeepAgents server layers over its baked agents at deploy time (no image rebuild). Put the exported pack under `packs/<your_agent>/` and add a one-row `agents.yaml` manifest beside it:

```
my-overlays/
  agents.yaml                    # overlay manifest (one row for your agent)
  packs/
    <your_agent>/                # the pack you exported above (pack.yaml, system_prompt.md, AGENTS.md, help.md, skills/…)
```

```yaml
# agents.yaml
agents:
  <your_agent>:                  # e.g. reservoir_agent
    template: mcp
    prefix: <PREFIX>             # e.g. RESERVOIR — the env namespace for this agent's vars (see below)
    auth: oauth                  # Databricks M2M service principal
    capabilities: databricks     # expands to the 4 managed servers (Functions / Vector Search / Genie / DBSQL)
    pack: packs/<your_agent>
```

Deliver the bundle (tarball or values) as described in the **[Adding Domain Agents via Overlay Guide](../../agent-server-deployment/Spotfire%20Copilot%20-%20Adding%20Domain%20Agents%20via%20Overlay%20Guide.md)** — the pack travels **inside** the bundle; there is no separate pack-mount volume.

### 3. Environment Variables

Supply these per agent, named by the **`prefix`** you chose in `agents.yaml`. The
examples use `<PREFIX>` — for `prefix: RESERVOIR` they become
`RESERVOIR_GENIE_MCP_SERVER_URL`, etc. (No pack-location variable is needed — the
pack travels inside the overlay bundle.)

```bash
# MCP Server URLs
<PREFIX>_GENIE_MCP_SERVER_URL=https://<host>/api/2.0/mcp/genie/<space_id>
<PREFIX>_FUNCTIONS_MCP_SERVER_URL=https://<host>/api/2.0/mcp/functions/<catalog>/<schema>
<PREFIX>_VECTORSEARCH_MCP_SERVER_URL=https://<host>/api/2.0/mcp/ai-search/<catalog>/<schema>
# ^ Schema-scoped: auto-discovers all indexes in the schema.
#   Tool name still includes the index: {catalog}__{schema}__{index_name}
<PREFIX>_DBSQL_MCP_SERVER_URL=https://<host>/api/2.0/mcp/sql

# Authentication (OAuth M2M) — secret goes in your secret store, not plain config
<PREFIX>_OAUTH_CLIENT_ID=<service-principal-app-id>
<PREFIX>_OAUTH_CLIENT_SECRET=<secret>
```

Non-secret vars go in the chart's `config.extraEnv`; `<PREFIX>_OAUTH_CLIENT_SECRET`
(and any bearer token) go in `secret.extraSecretEnv`. The overlay guide shows the
Docker Compose and GitHub Actions equivalents.

### 4. Service Principal Credentials

- Application (client) ID
- Client secret (from Entra ID / workspace SP settings)

---

## Troubleshooting

Common issues and fixes are documented in **Appendix B** (Cell 23) of the notebook. Key ones:

| Issue | Cause | Fix |
|-------|-------|-----|
| `PERMISSION_DENIED` on MCP call | Service principal missing grants | Run Cell 15 (SQL grants) + Cell 16 (Genie CAN_RUN) |
| Functions not appearing in MCP | Functions have no `COMMENT` | Add `COMMENT ON FUNCTION` with a description |
| AI Search returns no results | Index not synced | Re-run Cell 13, wait for sync to complete |
| `NameError: DOMAIN_NAME not defined` | Cell 3 not executed first | Run cells in order (Cell 3 before Cell 18) |
| Genie returns "no tables found" | Genie space not configured | Verify tables are added to the Genie space in the UI |

---

## Live Examples

This blueprint has been used to build 3 production domain agents:

| Domain | Tables | UC Functions | Reference Docs |
|--------|--------|-------------|----------------|
| Energy Operations | 3 (events, timeseries, assets) | 10 | 5 (ISO standards, safety) |
| HTM Semiconductor | 4 (yield, lots, defects, tools) | 10 | AI Search index |
| Petroleum (Oil & Gas) | 3 (wells, production, geology) | 7 | Knowledge base |

Each took approximately 1-2 hours to set up end-to-end.

---

## Support

For questions about:
- **This notebook**: Open an issue in the **spotfire-copilot-docs** repository
- **The Databricks Agent**: See the [Databricks Agent User Guide](../Spotfire%20Copilot%20-%20Databricks%20Agent%20User%20Guide.md)
- **Databricks MCP servers**: See [Databricks documentation](https://docs.databricks.com)
- **Spotfire Agent integration**: Contact the Spotfire Agent team
- **UC Function design**: The Databricks Assistant can help you design and create functions interactively

---

## Appendix: What the Notebook Must Generate (Overlay Bundle Spec)

This is the precise contract for the artifacts the notebook produces. The output is
a **self-contained overlay bundle** — a directory of plain-text files — that adds
**one** Databricks domain agent to the DeepAgents OSS server at deploy time (no image
rebuild). The **same** bundle is used two ways, unchanged: mounted as a folder for
Docker Compose, or packaged as a base64 `tar.gz` for Helm. There is **no** pack-mount
volume and **no** `DATABRICKS_AGENT_PACK_DIR` — the pack lives inside the bundle.

### Inputs the notebook collects

| Variable | Meaning | Example |
|---|---|---|
| `AGENT_ID` | snake_case, ends in `_agent` | `reservoir_agent` |
| `PREFIX` | UPPERCASE env namespace for this agent's vars | `RESERVOIR` |
| `DOMAIN_NAME` | Human-readable name | `Reservoir Engineering` |
| `WORKSPACE_HOST` | Databricks workspace host | `adb-123….azuredatabricks.net` |
| `CATALOG`, `SCHEMA` | Unity Catalog location | `main`, `reservoir` |
| `GENIE_SPACE_ID` | Scoped Genie space id | `01f1…` |
| `SP_CLIENT_ID` | Service-principal (OAuth M2M) application id | `<app-id>` |

### Directory structure (the deliverable)

```
<AGENT_ID>-overlay/
  agents.yaml                         # overlay manifest — ONE agent row
  packs/
    <AGENT_ID>/
      pack.yaml                       # agent-card: name, description, version, skills[]
      system_prompt.md                # routing rules + guardrails
      AGENTS.md                       # domain knowledge (entities, formulas, thresholds)
      help.md                         # "what can you do" text + starter prompts
      skills/
        genie-data-questions/SKILL.md
        uc-functions/SKILL.md
        vector-search-retrieval/SKILL.md
        sql-execution/SKILL.md
```

`pack:` in `agents.yaml` is resolved **relative to `agents.yaml`**, so keep them
together. Skill folder ids are **lowercase-hyphen** only. `help-and-capabilities` is
provided by middleware — list it in `pack.yaml` `skills[]` but do **not** create a
`SKILL.md` for it.

### `agents.yaml`

```yaml
agents:
  <AGENT_ID>:
    template: mcp
    prefix: <PREFIX>
    auth: oauth                 # Databricks M2M service principal
    capabilities: databricks    # expands to 4 managed servers for this prefix:
                                #   <PREFIX>_FUNCTIONS / _VECTORSEARCH / _GENIE / _DBSQL _MCP_SERVER_URL
    pack: packs/<AGENT_ID>
```

### `packs/<AGENT_ID>/pack.yaml`

```yaml
name: "<DOMAIN_NAME> Agent"
description: >-
  <2–3 sentences: what this agent does over Databricks>.
version: "0.1.0"
skills:
  - id: uc-functions
    name: Unity Catalog functions
    description: <domain-keyword-rich description of the UC functions it calls>
    tags: [databricks, unity-catalog, functions]
  - id: vector-search-retrieval
    name: AI Search retrieval
    description: <what documents/indexes it semantically searches>
    tags: [databricks, vector-search, ai-search, rag]
  - id: genie-data-questions
    name: Genie data questions
    description: <what the scoped Genie space answers; primary data path>
    tags: [databricks, genie, nl2sql, data]
  - id: sql-execution
    name: SQL discovery & fallback
    description: Catalog/schema/table discovery and read-only SQL fallback.
    tags: [databricks, sql, dbsql, discovery]
  - id: help-and-capabilities
    name: Help and capabilities
    description: Onboarding and meta questions like "help" / "what can you do".
```

Every `skills[].id` **except** `help-and-capabilities` MUST have a matching
`skills/<id>/SKILL.md` whose frontmatter `name:` **equals** `<id>`.

### `packs/<AGENT_ID>/skills/<id>/SKILL.md`

```markdown
---
name: <id>                      # MUST equal the folder name (lowercase-hyphen)
description: <rich, domain-keyword description so the router selects this skill>
allowed-tools: <tool1> <tool2>  # SPACE-separated, never commas
---
<Body: when to use this skill, how to call the tools, examples.>
```

### `system_prompt.md`, `AGENTS.md`, `help.md`

- `system_prompt.md` — routing rules, tone, and guardrails. MUST include: (1) a
  "retrieve real data first; never invent inputs/numbers" rule, (2) a
  read-only-by-default rule for SQL, (3) a no-ellipsis table policy (never truncate
  rows/columns with "…").
- `AGENTS.md` — domain knowledge the model needs (entities/tables, formulas,
  thresholds, units, conventions). No invented data.
- `help.md` — a short "what I can do" summary plus 4–6 concrete starter prompts.

### Validation the notebook runs before declaring success

- `agents.yaml` and every `pack.yaml` / `SKILL.md` parse as valid YAML.
- Every `skills[].id` (except `help-and-capabilities`) has `skills/<id>/SKILL.md`.
- Each `SKILL.md` frontmatter `name:` equals its folder name; ids are lowercase-hyphen.
- `allowed-tools` values are space-separated (no commas).
- The pack contains `pack.yaml`, `system_prompt.md`, `AGENTS.md`, `help.md`, `skills/`.

### Packaging output A — Docker Compose (folder mount)

The bundle folder is used as-is. The notebook prints these `.env` lines:

```env
OVERLAY_DIR=./<AGENT_ID>-overlay
AGENTS_OVERLAY_MANIFEST=/config/overlay/agents.yaml
```

### Packaging output B — Helm (tarball)

The notebook base64-encodes a `tar.gz` of the bundle and prints the commands.
Exclude macOS/AppleDouble junk so the in-cluster (busybox) extraction stays clean:

```bash
COPYFILE_DISABLE=1 tar --exclude='._*' --exclude='.DS_Store' \
  -czf bundle.tgz -C <AGENT_ID>-overlay .
base64 < bundle.tgz > bundle.b64

# App chart:
helm upgrade --install <release> <chart> -n <ns> \
  --set overlays.enabled=true \
  --set-file overlays.archiveBase64=bundle.b64
# -stack chart: prefix the two keys with copilot-deepagents-server-oss.
```

### Operator env handoff — the notebook prints this (fill real values)

Keep the secret **out** of the bundle and git.

```bash
# non-secret -> chart config.extraEnv (or .env for compose)
<PREFIX>_GENIE_MCP_SERVER_URL=https://<WORKSPACE_HOST>/api/2.0/mcp/genie/<GENIE_SPACE_ID>
<PREFIX>_FUNCTIONS_MCP_SERVER_URL=https://<WORKSPACE_HOST>/api/2.0/mcp/functions/<CATALOG>/<SCHEMA>
<PREFIX>_VECTORSEARCH_MCP_SERVER_URL=https://<WORKSPACE_HOST>/api/2.0/mcp/ai-search/<CATALOG>/<SCHEMA>
<PREFIX>_DBSQL_MCP_SERVER_URL=https://<WORKSPACE_HOST>/api/2.0/mcp/sql
<PREFIX>_OAUTH_CLIENT_ID=<SP_CLIENT_ID>
# secret -> chart secret.extraSecretEnv (NEVER in the bundle)
<PREFIX>_OAUTH_CLIENT_SECRET=<service-principal-secret>
# OAuth token URL auto-derives as https://<WORKSPACE_HOST>/oidc/v1/token
```

For end-to-end delivery of this bundle on Docker Compose, Helm, and GitHub Actions,
see the [Adding Domain Agents via Overlay Guide](../../agent-server-deployment/Spotfire%20Copilot%20-%20Adding%20Domain%20Agents%20via%20Overlay%20Guide.md).
