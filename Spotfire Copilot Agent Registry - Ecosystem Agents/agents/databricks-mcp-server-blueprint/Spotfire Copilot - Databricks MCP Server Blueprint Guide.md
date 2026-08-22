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

Once exported, the deployment team mounts it into the agent container (as a PVC, ConfigMap, or baked into the image) at the path specified by `DATABRICKS_AGENT_PACK_DIR`.

### 3. Environment Variables

```bash
# Pack location (inside the container)
DATABRICKS_AGENT_PACK_DIR=/config/databricks_agent

# MCP Server URLs
DATABRICKS_GENIE_MCP_SERVER_URL=https://<host>/api/2.0/mcp/genie/<space_id>
DATABRICKS_FUNCTIONS_MCP_SERVER_URL=https://<host>/api/2.0/mcp/functions/<catalog>/<schema>
DATABRICKS_VECTORSEARCH_MCP_SERVER_URL=https://<host>/api/2.0/mcp/ai-search/<catalog>/<schema>
# ^ Schema-scoped: auto-discovers all indexes in the schema.
#   Tool name still includes the index: {catalog}__{schema}__{index_name}
DATABRICKS_DBSQL_MCP_SERVER_URL=https://<host>/api/2.0/mcp/sql

# Authentication (OAuth M2M)
DATABRICKS_OAUTH_CLIENT_ID=<service-principal-app-id>
DATABRICKS_OAUTH_CLIENT_SECRET=<secret>
```

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
