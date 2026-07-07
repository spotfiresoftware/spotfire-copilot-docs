<!--
  <copyright file="AGENT_REGISTRY_TOOLKIT_USER_GUIDE.md" company="Cloud Software Group, Inc.">
    Copyright (c) 2006 - 2026 Cloud Software Group, Inc.
  All rights reserved.
  This software is the confidential and proprietary information
  of Cloud Software Group, Inc. ("Confidential Information"). You shall not
  disclose such Confidential Information and may not use it in any way,
  absent an express written license agreement between you and
  Cloud Software Group, Inc. that authorizes such use.
  </copyright>
-->

# Spotfire Copilot™ — Agent Registry Toolkit User Guide

> **Version:** `1.1.0` &nbsp;|&nbsp; **Last updated:** 1 July 2026 &nbsp;|&nbsp; **Applies to:** Agent Registry `1.1.0`
>
> This guide is for **Spotfire developers** who want to build custom agents locally using the Agent Registry Toolkit and MCP development server. It covers the toolkit module surface, the VS Code development workflow, a complete reference of every MCP tool and skill, and a full end-to-end walkthrough of creating a new agent from scratch.
>
> **This is a how-to guide, not a container-setup guide.** It assumes you already have a local Agent Registry container running with `MCP_ENABLED=true` and `TUNNEL_ENABLED=true`. If you have not yet done that, follow the [Setup and Deployment Guide for the Agent Registry Container](../Spotfire%20Copilot%20Agent%20Registry%20-%20Domain%20Agents/Spotfire%20Copilot%20-%20Agent%20Registry%20Installation%20Guide.md) first. Once the container is running, [§4](#4-getting-started-in-vs-code), Getting Started in VS Code, walks you through connecting VS Code to it and installing the toolkit stubs — start there.

---

## Table of Contents

- [1. Introduction](#1-introduction)
  - [1.1 What Is the Agent Registry Toolkit?](#11-what-is-the-agent-registry-toolkit)
  - [1.2 What Is the MCP Development Server?](#12-what-is-the-mcp-development-server)
  - [1.3 How They Work Together](#13-how-they-work-together)
  - [1.4 Which AI Coding Assistant?](#14-which-ai-coding-assistant)
- [2. Prerequisites Recap](#2-prerequisites-recap)
- [3. The Reverse Tunnel — Your Local Agent in Spotfire](#3-the-reverse-tunnel--your-local-agent-in-spotfire)
  - [How it works](#how-it-works)
  - [What this means for you](#what-this-means-for-you)
  - [Confirming the tunnel is connected](#confirming-the-tunnel-is-connected)
- [4. Getting Started in VS Code](#4-getting-started-in-vs-code)
  - [4.1 Open your custom-agents folder](#41-open-your-custom-agents-folder)
  - [4.2 Create `.vscode/mcp.json`](#42-create-vscodemcpjson)
  - [4.3 Run `setup_workspace` to pull in the toolkit stubs](#43-run-setup_workspace-to-pull-in-the-toolkit-stubs)
  - [4.4 Install the stubs into a local virtual environment](#44-install-the-stubs-into-a-local-virtual-environment)
  - [4.5 Verify everything is wired up](#45-verify-everything-is-wired-up)
- [5. The Development Toolkit — Skills, Stubs, and the API Reference](#5-the-development-toolkit--skills-stubs-and-the-api-reference)
  - [5.1 Skills — Context-Rich Guides for the AI Assistant](#51-skills--context-rich-guides-for-the-ai-assistant)
  - [5.2 Type Stubs — Autocomplete for Your Agent Code](#52-type-stubs--autocomplete-for-your-agent-code)
  - [5.3 The Toolkit API Reference](#53-the-toolkit-api-reference)
  - [5.4 Templates — Agent Boilerplate](#54-templates--agent-boilerplate)
- [6. MCP Tool Reference](#6-mcp-tool-reference)
  - [6.1 Workspace Tools](#61-workspace-tools)
  - [6.2 Design Tools](#62-design-tools)
  - [6.3 Technical Design Tools](#63-technical-design-tools)
  - [6.4 Scaffolding Tools](#64-scaffolding-tools)
  - [6.5 Validation and Dry-Run Tools](#65-validation-and-dry-run-tools)
  - [6.6 Schema Discovery Tools](#66-schema-discovery-tools)
  - [6.7 Observability Tools](#67-observability-tools)
  - [6.8 Knowledge Tools](#68-knowledge-tools)
- [7. The Agent Development Process — A Full Walkthrough](#7-the-agent-development-process--a-full-walkthrough)
  - [Phase 0: Prepare Your Spotfire Data (Schema Discovery)](#phase-0-prepare-your-spotfire-data-schema-discovery)
  - [Phase 1: Design — Define What the Agent Will Do](#phase-1-design--define-what-the-agent-will-do)
  - [Phase 2: Technical Design — Define How It Will Be Built](#phase-2-technical-design--define-how-it-will-be-built)
  - [Phase 3: Scaffold — Create the Files](#phase-3-scaffold--create-the-files)
  - [Phase 4: Implement — Write the Agent Logic](#phase-4-implement--write-the-agent-logic)
  - [Phase 5: Validate — Dry-Run and Test](#phase-5-validate--dry-run-and-test)
  - [Phase 6: Register for Other Users (Optional)](#phase-6-register-for-other-users-optional)
- [8. Agent Structure Reference](#8-agent-structure-reference)
  - [8.1 Folder Layout](#81-folder-layout)
  - [8.2 Required Files](#82-required-files)
  - [8.3 Prompt File Conventions](#83-prompt-file-conventions)
- [9. Working in Non-VS-Code Environments](#9-working-in-non-vs-code-environments)
- [10. Troubleshooting](#10-troubleshooting)
  - [MCP server not connecting](#mcp-server-not-connecting)
  - [Agent not visible in Spotfire](#agent-not-visible-in-spotfire)
  - [Stale local Python process (port conflict)](#stale-local-python-process-port-conflict)
  - [`dry_run_agent` fails immediately](#dry_run_agent-fails-immediately)
  - [LLM calls failing inside the agent](#llm-calls-failing-inside-the-agent)
  - [Hot-reload not picking up changes](#hot-reload-not-picking-up-changes)
- [11. Security Considerations](#11-security-considerations)

---

## 1. Introduction

### 1.1 What Is the Agent Registry Toolkit?

The **Agent Registry Toolkit** (`agent_registry_toolkit_for_spotfire`) is a Python library installed inside the Agent Registry container. It provides the building blocks every custom agent uses:

| Module | What it does |
|---|---|
| `agent_framework` | `FunctionalWorkflow`, `RunContext`, `@step` — the core A2A execution model |
| `helpers` | High-level helpers: `create_ask_user`, `reply_and_continue`, `action_buttons` |
| `llm` | LLM relay: `create_llm_caller`, `create_fast_llm_caller` — sends prompts to the orchestrator |
| `schema_pipeline` | `discover_schema` — discovers the active Spotfire table schema at runtime |
| `stage_executor` | `execute_stage`, `build_stage_system_prompt` — drives a single intent stage |
| `ops` | All Spotfire operation builders: filter, mark rows, create charts, SQL queries |
| `sql_helpers` | Safe SQL construction and parameterisation for Spotfire's dialect |
| `schema_contract` | `SchemaContract`, `ColumnMapping` — the validated column-name contract |
| `intent_router` | `build_router_input`, `parse_route_response` — LLM-based intent routing |
| `response_parser` | Parses typed responses from the LLM |
| `result_parser` | Parses Spotfire result envelopes |
| `session` | `format_orientation`, session state helpers |
| `workflow_loop` | Low-level loop driver (normally not called directly) |
| `filter_state` | Filter state serialisation |
| `marked_data` | `extract_marked_data`, `respect_marking` — access marked rows |
| `validation` | Input and response validation utilities |
| `analytical_helpers` | Domain analysis helpers |
| `timeseries` / `surveillance` / `spatial` | Specialised analytical pipeline helpers |
| `discovery` | Schema discovery report access |
| `rag` | Retrieval-augmented generation via the orchestrator |

The toolkit is **only available inside the container**. To get IDE autocomplete and type checking on your host machine, install the accompanying type stubs wheel — see [§5.2](#52-type-stubs--autocomplete-for-your-agent-code), Type Stubs.

### 1.2 What Is the MCP Development Server?

The **MCP development server** is an optional HTTP server running inside the Agent Registry container (at `/mcp/`) that exposes a set of development tools over the [Model Context Protocol (MCP)](https://modelcontextprotocol.io). These tools are consumed by AI coding assistants — primarily **GitHub Copilot in VS Code Agent mode** — to give them structured, accurate context about your agent development environment.

The MCP server enables:

- **Interactive agent design** through a rich VS Code form — the AI asks the right questions rather than generating generic scaffolding
- **Automated technical design** — an LLM generates a Technical Design Document (TDD) from your confirmed SPEC
- **Scaffolding gated behind design** — `scaffold_code_agent` refuses to run until a SPEC and TDD are confirmed, preventing skeleton-first development
- **Structural dry-runs** — `dry_run_agent` imports your agent, instantiates it, and drives a simulated conversation before you test in Spotfire
- **Skill injection** — domain-specific development guides (skills) are served to the AI on demand, so it knows the correct patterns for your agent type
- **Schema discovery integration** — discovery reports from Spotfire flow automatically into the design form, grounding the SPEC in real data

The MCP server is **disabled in production** (`MCP_ENABLED` must be unset or `false`). It is only active on a local development workstation.

### 1.3 How They Work Together

```
Developer in VS Code
       │
       │  asks: "help me build a turbine analyst"
       ▼
GitHub Copilot (Agent mode)
       │
       │  calls MCP tools over HTTP → localhost:8050/mcp/
       │
       ▼
┌─────────────────────────────────────────────────────┐
│          Agent Registry Container (:8050)           │
│                                                     │
│  MCP Server                                         │
│  ├── design_agent_form  → VS Code rich form         │
│  ├── technical_design   → TDD.md (LLM-generated)   │
│  ├── scaffold_code_agent → agent files on disk      │
│  ├── dry_run_agent       → structural validation    │
│  ├── read_skill          → patterns & guidance      │
│  └── read_toolkit_api    → full API reference       │
│                                                     │
│  A2A Server (always on)                             │
│  └── /agents/<slug>/    → your agent live via tunnel│
│                                                     │
│  Custom-Agent Watcher                               │
│  └── hot-reloads your workspace on every save       │
└─────────────────────────────────────────────────────┘
       │ outbound WebSocket tunnel (always on)
       ▼
  Deployed Orchestrator
       │
       ▼
  Spotfire Copilot (your session only)
```

When you save a file in your workspace, the container reloads it in-process and re-exposes the agent through the tunnel — your changes are live in Spotfire in under a second, with no manual steps.

### 1.4 Which AI Coding Assistant?

**This toolkit is designed and tested for GitHub Copilot in VS Code Agent mode.** That is where the experience is richest: the interactive design form renders natively, the Copilot customization files installed by `setup_workspace` (agent, prompts, instructions) are picked up automatically, and skill/pattern injection flows through the MCP server without you having to think about it. If you have a choice, use VS Code with GitHub Copilot — the rest of this guide assumes that path unless a section says otherwise.

**It should also work with Claude Code and other MCP-capable assistants — with a "your mileage may vary" caveat.** The development server is a standard HTTP MCP endpoint, so any MCP client (Claude Code, Cursor, Cline, JetBrains AI Assistant) can connect and call the tools. The core loop — `technical_design` → `scaffold_code_agent` → `dry_run_agent`, plus `read_skill` and `read_toolkit_api` — behaves identically across clients. What differs:

- **The design form is VS Code-only.** `design_agent_form` renders a rich UI via the MCP Apps `ui://` protocol, which only VS Code supports. In other clients, use the text-only `design_agent` tool instead — it runs the same interview as plain conversation.
- **Copilot customization files don't apply.** `setup_workspace` writes `.github/` instruction and prompt files and a VS Code-shaped `.vscode/mcp.json`. Claude Code ignores these — it reads `CLAUDE.md` / `.claude/` and a project-root `.mcp.json`. You still get the portable artifacts (the stubs wheel and `pyproject.toml`), but pattern compliance is not automatic: explicitly ask the assistant to read `correct-agent-patterns` and call `read_toolkit_api` before it generates code.
- **Config location and shape differ.** Point Claude Code at the same endpoint with a project-root `.mcp.json` (note `mcpServers`, not `servers`):

  ```json
  {
    "mcpServers": {
      "spotfire-agent-dev": {
        "type": "http",
        "url": "http://localhost:8050/mcp/"
      }
    }
  }
  ```

  or run `claude mcp add --transport http spotfire-agent-dev http://localhost:8050/mcp/`.

See [§9](#9-working-in-non-vs-code-environments), Working in Non-VS-Code Environments, for the full compatibility notes. Everywhere this guide says "ask Copilot," substitute your assistant of choice.

---

## 2. Prerequisites Recap

This guide picks up once your local Agent Registry **container** is running. The [Setup and Deployment Guide for the Agent Registry Container](../Spotfire%20Copilot%20Agent%20Registry%20-%20Domain%20Agents/Spotfire%20Copilot%20-%20Agent%20Registry%20Installation%20Guide.md) should have left you with:

| Requirement | Set up in the deployment guide |
|---|---|
| Agent Registry container running locally with `MCP_ENABLED=true` and `TUNNEL_ENABLED=true` | *Local development* |
| Custom-agents workspace directory bind-mounted at `CUSTOM_WORKFLOWS_DIR=/custom-workflows` | *Local development* |
| `TUNNEL_USER_ID` set to your exact Spotfire login | *Configure the orchestrator connection* |
| VS Code (1.109+) with the **GitHub Copilot** extension installed | *Enabling the MCP development server* |
| Python 3.11+ available on your host (for the local `.venv` used by the type stubs) | *Type stubs for IDE autocomplete* |

Connecting VS Code to the running container — creating `.vscode/mcp.json` and installing the type-stubs wheel — is covered in [§4](#4-getting-started-in-vs-code), Getting Started in VS Code, below. If the container isn't running yet, complete the [deployment guide](../Spotfire%20Copilot%20Agent%20Registry%20-%20Domain%20Agents/Spotfire%20Copilot%20-%20Agent%20Registry%20Installation%20Guide.md) first.

---

## 3. The Reverse Tunnel — Your Local Agent in Spotfire

The reverse tunnel is what makes local development possible without opening any inbound ports. Understanding it saves significant debugging time.

### How it works

When the container starts with `TUNNEL_ENABLED=true`, it opens a persistent outbound WebSocket to the orchestrator's `/tunnel/connect` endpoint and announces each discovered agent to the orchestrator. The orchestrator registers these as "tunneled" agents, scoped exclusively to `TUNNEL_USER_ID`.

When a Spotfire user logged in as that exact user ID opens the Copilot panel, the orchestrator includes the tunneled agents in the agent list. When the user sends a message to one of those agents, the orchestrator proxies the request back over the same WebSocket — your local container handles it and responds. No inbound firewall rules are needed.

### What this means for you

- **Your agents are private.** Only your Spotfire session sees them. Other users on the same orchestrator are unaffected.
- **`TUNNEL_USER_ID` must match exactly.** Case-sensitive, including any domain or realm portion. `alice.smith@company.com` and `Alice.Smith@COMPANY.COM` are different identities. If your agents do not appear in Spotfire, this is almost always the cause.
- **Tunneled agents auto-register.** You never need to register tunneled agents in the orchestrator admin console — they appear automatically when the tunnel connects, and disappear when the container stops.
- **Hot-reload is live.** Edits to your agent code are picked up in-process within a second. Adding or removing an entire agent folder requires `docker compose restart` to trigger re-discovery.
- **Reconnection is automatic.** If the tunnel drops (network hiccup, orchestrator restart), the container reconnects with exponential backoff. Check `docker compose logs -f` if agents disappear from Spotfire for more than a minute.

### Confirming the tunnel is connected

```bash
# Check readiness — includes tunnel state
curl http://localhost:8050/readyz
# Expected: {"status":"ok"}

# Check container logs for the tunnel message
docker compose logs dev | grep -i tunnel
# Expected: "Tunnel connected" or "Registered N agents via tunnel"
```

---

## 4. Getting Started in VS Code

With the container running, three steps connect VS Code to it and give you a working development environment: point VS Code at the MCP server, pull the toolkit stubs into your workspace, and install them into a local virtual environment. This takes a couple of minutes and you only do it once per workspace.

### 4.1 Open your custom-agents folder

Open the folder that is bind-mounted to `CUSTOM_WORKFLOWS_DIR=/custom-workflows` in the container as your VS Code workspace root. This is where your agents live and where the toolkit tools read and write. Do not open a parent or child folder — the workspace root must be the custom-agents directory itself.

### 4.2 Create `.vscode/mcp.json`

VS Code discovers MCP servers through a `mcp.json` file in the `.vscode/` folder at the workspace root. Create it with exactly this content:

**`.vscode/mcp.json`**

```json
{
  "servers": {
    "spotfire-agent-dev": {
      "type": "http",
      "url": "http://localhost:8050/mcp/"
    }
  }
}
```

- The MCP server URL (`http://localhost:8050/mcp/`) requires no authentication — it is intentionally open for local development convenience.
- VS Code reloads MCP server definitions when you save `mcp.json`. If it does not pick up the server automatically, open the command palette and run **MCP: List Servers** to trigger a refresh.

> **⚠️ The MCP server endpoint is unauthenticated.** Never expose port `8050` to untrusted networks while `MCP_ENABLED=true`. The container should only be reachable from localhost on your workstation. See [§11](#11-security-considerations), Security Considerations.

### 4.3 Run `setup_workspace` to pull in the toolkit stubs

With the container running and VS Code connected to the MCP server, open Copilot Chat in **Agent mode** and ask:

```
run setup_workspace
```

Copilot invokes the `setup_workspace` MCP tool, which copies the prebuilt `agent_registry_toolkit_for_spotfire_stubs-*.whl` from inside the container into your workspace root, alongside a `pyproject.toml` (and a `.vscode/mcp.json` if you skipped step 4.2). It skips files that already exist, so it is safe to re-run — do so after upgrading the container image to refresh the wheel.

### 4.4 Install the stubs into a local virtual environment

The toolkit itself runs only inside the container. Installing the stubs wheel on your host gives VS Code full import resolution, autocomplete, hover docs, and type checking for `agent_registry_toolkit_for_spotfire`.

```bash
# Windows
python -m venv .venv
.venv\Scripts\activate
pip install agent_registry_toolkit_for_spotfire_stubs-*.whl

# macOS / Linux
python -m venv .venv
source .venv/bin/activate
pip install agent_registry_toolkit_for_spotfire_stubs-*.whl
```

If VS Code does not auto-detect the `.venv`, open the command palette and run **Python: Select Interpreter**, then choose the `.venv` interpreter. After upgrading the container image, re-run `setup_workspace` and `pip install --force-reinstall agent_registry_toolkit_for_spotfire_stubs-*.whl` to refresh the stubs.

### 4.5 Verify everything is wired up

Run these three quick checks before you start building. If any fails, see [§10](#10-troubleshooting), Troubleshooting.

**Container and tunnel are up:**

```bash
# Readiness — agents discovered and tunnel connected
curl http://localhost:8050/readyz
# Expected: {"status":"ok"}
```

**MCP server is connected** — in Copilot Chat (Agent mode), ask:

```
list agents
```

If the MCP server is connected, Copilot invokes the `list_agents` tool and returns the agents currently served by the container (bundled agents plus any custom agents already in your workspace). If you see a standard Copilot reply with no tool call, the MCP server is not connected — confirm `.vscode/mcp.json` points at `http://localhost:8050/mcp/` and run **MCP: List Servers** from the command palette.

**Type stubs resolve** — open any agent file that imports from `agent_registry_toolkit_for_spotfire`. If imports resolve with autocomplete and no red underlines, the stubs are installed correctly. If not, re-run steps 4.3 and 4.4, then confirm the `.venv` interpreter is selected.

---

## 5. The Development Toolkit — Skills, Stubs, and the API Reference

The MCP server ships three sources of developer knowledge that the AI assistant can access on demand. You do not need to read these yourself — the AI pulls them in automatically when relevant — but understanding what they are helps you get better results.

### 5.1 Skills — Context-Rich Guides for the AI Assistant

**Skills** are domain-specific development guides stored as Markdown files inside the container. When the AI needs detailed guidance on a topic — imports, button patterns, SQL helpers, debugging — it calls `read_skill` to fetch the relevant guide.

Skills are not loaded into the AI's context by default (they are too large). The AI loads them on demand, and you can also ask it to load specific skills explicitly:

```
read the correct-agent-patterns skill
```

#### Skill Reference

| Skill name | When the AI uses it | What you get |
|---|---|---|
| `correct-agent-patterns` | **Always before writing any agent code** | The mandatory NEVER/ALWAYS checklist: correct imports, workflow shape, schema access patterns, SQL helper rules, marking semantics |
| `advanced-code-patterns` | When building multi-turn flows, buttons, routing, or caching | Action buttons, deterministic routing, caching, multi-turn flow, stage executor hooks, conversation logging |
| `workflow-structure` | When `workflow.py` grows past ~150 lines | How to decompose into `stages/`, `hooks.py`, `state.py` — file layout and import boundaries |
| `create-code-agent` | When scaffolding a new code-based agent | Required folder structure, `__init__.py` contract, `create_workflow` factory, kwargs available at startup |
| `agent-design` | During the design conversation | How to run the design interview: personas, use cases, data model, workflow style, acceptance scenarios |
| `technical-design` | When producing the TDD | The 14 required TDD sections, the Intent→Stage Map format, structural rules enforced by `dry_run_agent` |
| `prompt-engineering` | When writing prompt files | Prompt file hierarchy, `role_intro.txt` / `data_schema.txt` / `output_rules.txt` conventions, prompt-relay vs. code-based differences |
| `marked-data` | When building agents that operate on selected rows | `extract_marked_data`, `respect_marking` parameter, SQL on a marked subset |
| `discovery-module` | When the agent needs deep schema exploration | What the discovery report contains, how to feed it into design and SQL generation |
| `time-series-analysis` | For trend, anomaly, surveillance, or decline workloads | LTTB downsampling, stats summariser, surveillance helpers, timeseries pipelines |
| `viz-data-shaping` | When creating or configuring Spotfire visualizations | Authoritative parameter names for filtering, trellising, data limiting, and chart configuration |
| `visual-analytic-thinking` | When designing how an agent surfaces results on the active page | Main vs. details visualizations, master/detail cascades, response form decision guide (text / mark / filter / chart) |
| `debug-agent` | When an agent crashes or behaves unexpectedly | Tier-A dry-run interpretation, log file locations, port conflict diagnosis, stuck loop fixes |
| `register-agent` | When promoting an agent from tunnel to permanent registration | Step-by-step orchestrator admin console registration |

> **Using skills from other AI environments:** Skills are plain Markdown files stored at `agent_container/dev_mcp/skills/` inside the container image. You can read them directly with any text editor or tool, but in VS Code the AI fetches them via `read_skill` and applies them in-context automatically. In non-VS-Code environments (see [§9](#9-working-in-non-vs-code-environments), Working in Non-VS-Code Environments), instruct the AI to read the relevant skill files manually.

### 5.2 Type Stubs — Autocomplete for Your Agent Code

The stubs wheel (installed in [§4.4](#44-install-the-stubs-into-a-local-virtual-environment), Install the Stubs into a Local Virtual Environment) provides:

- **Full `import` resolution** for every public module in `agent_registry_toolkit_for_spotfire`
- **Function signatures and type annotations** on all public API functions
- **Inline docstrings** available as hover documentation in VS Code
- **Type checking** via mypy or Pylance — incorrect argument types are caught at edit time

The stubs cover the full public surface: `ops`, `session`, `schema_discovery`, `schema_pipeline`, `llm`, `sql_helpers`, `workflow_loop`, `filter_state`, `intent_router`, `response_parser`, `stage_executor`, `validation`, `marked_data`, `helpers`, and `analytical_helpers`.

> When you upgrade the container image, re-run `setup_workspace` and then `pip install --force-reinstall agent_registry_toolkit_for_spotfire_stubs-*.whl` to refresh the stubs against the new toolkit version.

### 5.3 The Toolkit API Reference

For a complete, always-current reference of every public function, class, and type alias in the toolkit, ask the AI to call `read_toolkit_api`:

```
read the toolkit api
```

The `read_toolkit_api` MCP tool returns the full `README.md` from the toolkit module, including module index, common import patterns, and type aliases. Use this instead of guessing imports — the toolkit surface is large and some function names are non-obvious.

**Common import patterns** (also shown in the API reference):

```python
# Core workflow
from agent_framework import FunctionalWorkflow, RunContext

# Helpers and UX
from agent_registry_toolkit_for_spotfire.helpers import (
    create_ask_user, reply_and_continue, action_buttons
)

# LLM relay
from agent_registry_toolkit_for_spotfire.llm import create_llm_caller

# Schema
from agent_registry_toolkit_for_spotfire.schema_pipeline import discover_schema

# Stage execution
from agent_registry_toolkit_for_spotfire.stage_executor import (
    execute_stage, build_stage_system_prompt
)

# Spotfire ops
from agent_registry_toolkit_for_spotfire.ops import (
    build_filter_op, build_mark_rows_op, build_create_viz_op
)

# SQL
from agent_registry_toolkit_for_spotfire.sql_helpers import (
    build_select, safe_column_name
)
```

### 5.4 Templates — Agent Boilerplate

The `read_template` tool returns the canonical boilerplate for agent files. There are three template types:

| Template | What it contains |
|---|---|
| `code` | The full recommended folder structure with annotated stub files — `__init__.py`, `workflow.py`, `state.py`, `hooks.py`, `stages/__init__.py`, `stages/example.py`, `prompts/router.txt` |
| `spec` | The SPEC.md skeleton — user stories, data model, intent categories, acceptance scenarios, out-of-scope |
| `tdd` | The TDD.md skeleton — all 14 required sections with guidance comments |

You will rarely need to call `read_template` manually. The scaffold tool (`scaffold_code_agent`) uses these templates internally. They are exposed as a tool so the AI can reference the canonical patterns when filling in stubs.

---

## 6. MCP Tool Reference

The full list of tools exposed by the MCP development server. All tools are available when `MCP_ENABLED=true` and the MCP server is connected in VS Code.

### 6.1 Workspace Tools

#### `setup_workspace`

Sets up a new agent workspace. Copies the stubs wheel, `pyproject.toml`, and `.vscode/mcp.json` from the container into your workspace directory. Safe to re-run — skips files that already exist.

**When to use:** The first time you open a new workspace, or after upgrading the container image to refresh the stubs.

```
run setup_workspace
```

#### `reload_container`

Triggers an in-process hot-reload of the agent registry. Returns a summary of discovered agents. Use this only if the automatic file-watcher appears stuck — in normal operation, saves reload automatically.

```
reload the container
```

### 6.2 Design Tools

#### `design_agent_form`

**(VS Code only)** Renders a rich interactive design form directly in the Copilot Chat panel. The form collects requirements (persona, use cases, data model, Spotfire operations, out-of-scope), then on submission calls `process_design_inputs` to generate a SPEC using the orchestrator's LLM.

If a Schema Discovery report exists for this agent (see [§6.6](#66-schema-discovery-tools), Schema Discovery Tools), the form displays the discovery status and the LLM pre-populates domain-specific hints for each field.

**When to use:** At the start of every new agent. This is the primary entry point for VS Code users.

```
design agent form for "turbine analyst"
```

#### `process_design_inputs`

Processes the completed form data from `design_agent_form` and generates the SPEC markdown. Called automatically by the form on submission — you do not normally invoke this directly.

#### `confirm_design`

Confirms or corrects a generated SPEC. On confirmation, the SPEC is written to `<slug>/SPEC.md` in your workspace and scaffolding gates advance to the TDD stage. Pass `corrections` to iterate without reconfirming.

```
confirm_design(agent_name="turbine analyst", confirmed=True)
confirm_design(agent_name="turbine analyst", corrections="add a fault-count intent")
```

#### `design_agent`

**(Non-VS-Code fallback)** Text-only design conversation. Use this if `design_agent_form` is unavailable (Claude Code, Cursor, JetBrains). In VS Code, always prefer `design_agent_form` — it produces a richer SPEC by rendering the form UI.

### 6.3 Technical Design Tools

#### `technical_design`

Generates a Technical Design Document (TDD) from the confirmed SPEC. The TDD has 14 required sections: file manifest, intent→stage map, data flow per stage, toolkit usage, gaps, shared utilities, state shape, failure modes, verification plan, welcome screen, LLM prompting strategy, algorithms, open questions, and out-of-scope.

The TDD is written to `<slug>/TDD.md` in your workspace. Scaffolding is gated behind a confirmed TDD.

```
technical_design(agent_name="turbine analyst")
# iterate:
technical_design(agent_name="turbine analyst", corrections="add SQL caching to section 7")
```

#### `confirm_technical_design`

Confirms or corrects a generated TDD. On confirmation, the TDD is validated structurally (all 14 sections present, Intent→Stage Map rows present and well-formed) and the scaffolding gate opens. Pass `corrections` to regenerate.

```
confirm_technical_design(agent_name="turbine analyst", confirmed=True)
```

#### `validate_tdd`

Runs static structural checks on the TDD without changing confirmation state. Reports missing sections, empty sections, unresolved placeholders (`TODO`, `TBD`), and non-blocking warnings. Use this after editing `TDD.md` directly in the editor.

```
validate_tdd(agent_name="turbine analyst")
```

#### `backfill_tdd`

Generates a TDD for an existing agent that pre-dates the TDD requirement, by inspecting the code on disk. The generated TDD is left unconfirmed — review it, fix any TODOs, then call `confirm_technical_design` to lock it in.

```
backfill_tdd(agent_name="old_agent")
backfill_tdd(agent_name="old_agent", force=True)  # overwrite an existing TDD
```

### 6.4 Scaffolding Tools

#### `scaffold_code_agent`

Creates a complete code-based agent folder structure from the confirmed TDD. Generates one `stages/<name>.py` stub per row in the TDD's Intent→Stage Map, plus `workflow.py`, `state.py`, `hooks.py`, `__init__.py`, and matching `prompts/<stage>.txt` files. Requires both SPEC and TDD to be confirmed.

```
scaffold_code_agent(name="turbine analyst")
```

The scaffolded stubs are immediately live in the container via the file watcher — you can call `dry_run_agent` against them before writing any implementation code.

### 6.5 Validation and Dry-Run Tools

#### `dry_run_agent`

The most important validation tool. It:

1. **Imports your agent package** and confirms all imports succeed
2. **Calls `create_workflow()`** and confirms it returns a valid `FunctionalWorkflow`
3. **Compares the file system against the TDD** manifest — every stage file declared must exist; extra undeclared files are warned about
4. **Drives the workflow loop** with a canned conversation: if the agent presents buttons, it clicks the first one; otherwise it sends an empty message envelope
5. **Reports a structured result** with status, checks, observed pauses, and the TDD's verification plan

| Status | Meaning | Action |
|---|---|---|
| `pass` | Workflow reached IDLE cleanly | Safe to test in Spotfire |
| `pass-partial` | Pause cap reached, but every pause had a unique `request_id` (forward progress) | Treat as green; safe to test. Pass `max_pauses=20` to exercise more turns |
| `fail` | A `request_id` repeated (stuck loop), unexpected terminal state, or an exception | Read `error.traceback`; fix and re-run |
| `error` | Import, factory, or setup failure | Read `error.traceback`; fix and re-run |

```
dry_run_agent(agent_name="turbine analyst")
dry_run_agent(agent_name="turbine analyst", max_pauses=20)
```

> **Run `dry_run_agent` before testing in Spotfire.** It catches import errors, wrong function signatures, stuck loops, and TDD-manifest mismatches without needing a live Spotfire session. A `pass` or `pass-partial` does not guarantee the agent works against real data — only that the Python plumbing is intact.

#### `replay_session`

Replays a specific conversation from the agent's log files, allowing the AI to analyse what happened during a previous session. Useful for reproducing bugs.

```
replay_session(agent_name="turbine analyst")
```

### 6.6 Schema Discovery Tools

#### `discover_workspace_schema`

Checks the status of the schema discovery report for an agent — whether a report exists, how old it is, and what Spotfire document it covers. Does not run discovery; that is done from Spotfire itself using the built-in **Schema Discovery** agent.

```
discover_workspace_schema(agent_name="turbine analyst")
```

#### `read_discovery_report`

Reads the full content of the latest schema discovery report for an agent. Reports are stored at `<workspace>/.discovery/<slug>.json` and are generated by running the Schema Discovery agent from Spotfire.

```
read_discovery_report(agent_name="turbine analyst")
```

#### `analyze_discovery`

Analyzes a discovery report and proposes three concrete agent use case options based on the actual data — tables, columns, sample values, and row counts. Call this after running the Schema Discovery agent but before starting the design form, to identify the best agent concept for your data.

```
analyze_discovery(agent_name="turbine data")
```

### 6.7 Observability Tools

#### `list_agents`

Lists all agents currently served by the container — bundled agents and custom agents from your workspace. Includes each agent's slug, status, and endpoint URL.

```
list agents
```

#### `read_agent_logs`

Reads the most recent log file for an agent, including full exception tracebacks from crashed executions. The first place to look when an agent returns "Internal workflow error".

```
read_agent_logs(agent_name="turbine analyst")
```

#### `debug_session`

Provides a structured debug summary for a recent agent conversation — the turn-by-turn exchange, any errors, and timing data.

```
debug_session(agent_name="turbine analyst")
```

### 6.8 Knowledge Tools

#### `read_skill`

Fetches the content of a named skill guide. Used by the AI internally; you can also ask it to load skills explicitly when you want it to follow a specific set of patterns.

```
read the correct-agent-patterns skill
read the debug-agent skill
```

#### `read_toolkit_api`

Returns the full API reference for `agent_registry_toolkit_for_spotfire`, including the module index, common import patterns, and type aliases. Use this instead of guessing imports.

```
read the toolkit api
```

#### `read_template`

Returns the template content for agent boilerplate. Types: `code`, `spec`, `tdd`.

```
read_template(template_type="code")
```

---

## 7. The Agent Development Process — A Full Walkthrough

This section walks through building a complete agent from scratch. The example is a **Turbine Performance Analyst** agent for wind turbine data — adapt it to your domain.

### Phase 0: Prepare Your Spotfire Data (Schema Discovery)

Before designing an agent, run the built-in **Schema Discovery** agent from Spotfire to generate a report of your data's tables, columns, types, and sample values. The design form reads this report automatically, grounding your SPEC in real data rather than assumptions.

**In Spotfire:**
1. Open your Spotfire document with the data you want to analyse.
2. Open the Copilot panel and select the **Schema Discovery** agent from the agent list.
3. Send any message (e.g. "discover this document"). The agent explores every table and writes a report.
4. Wait for the agent to confirm it has finished.

The report is written to `<workspace>/.discovery/<slug>.json`. The design form will automatically read it when you start designing.

> The Schema Discovery agent is always deployed — it ships with the Agent Registry and requires no configuration. One report covers all agents in development; re-run it whenever the data changes.

**In VS Code** (optional, to verify the report exists):

```
discover_workspace_schema(agent_name="turbine analyst")
```

The tool reports the report age, whether it is fresh enough, and what document it covers.

---

### Phase 1: Design — Define What the Agent Will Do

Open Copilot Chat in Agent mode and start the design form:

```
design agent form for "turbine analyst"
```

A rich interactive form appears in the chat panel. Fill in:

| Field | What to enter |
|---|---|
| **User persona** | Who will use this agent — e.g. "Wind farm operations engineer who monitors turbine health daily and makes maintenance scheduling decisions." |
| **Use cases** | 2-4 concrete scenarios — e.g. "Show me turbines with below-average power output this week", "Which turbines are approaching their scheduled maintenance date?" |
| **Data model** | Tables and key columns — leave blank if uncertain (the form pre-fills hints from the discovery report) |
| **Spotfire operations** | What the agent should DO — e.g. "filter to selected turbines, mark underperformers, create a scatter chart of power vs wind speed" |
| **Out of scope** | What it should NOT do — e.g. "not responsible for safety shutdowns or alarm management" |

Click **Submit**. The LLM generates a SPEC based on your answers and the discovery report. The SPEC appears in the form preview and is also written to `<slug>/SPEC.md` in your workspace — open it in a VS Code editor tab for full review.

**Review the SPEC.** Check that:
- User stories reflect real workflow steps, not generic descriptions
- The data model references actual column names from the discovery report
- Intent categories (what the agent can be asked to do) match your use cases
- Acceptance scenarios are specific and testable

**Confirm or correct:**

To confirm:
```
confirm_design(agent_name="turbine analyst", confirmed=True)
```

To request changes without losing the current version:
```
confirm_design(agent_name="turbine analyst", corrections="split the 'analyse performance' intent into 'compare turbines' and 'flag underperformers'")
```

Once confirmed, `<slug>/SPEC.md` and `<slug>/design.json` are written to your workspace and the design gate advances.

---

### Phase 2: Technical Design — Define How It Will Be Built

With the SPEC confirmed, generate the Technical Design Document:

```
technical_design(agent_name="turbine analyst")
```

The LLM reads your confirmed SPEC and produces a TDD with 14 sections, including:

- **File manifest** — every file the scaffold will create
- **Intent→Stage Map** — one row per SPEC intent, mapping it to a stage file and entry function
- **Data flow per stage** — what state fields each stage reads and writes, what Spotfire ops it performs
- **Toolkit usage** — which modules from `agent_registry_toolkit_for_spotfire` each stage uses
- **Toolkit gaps** — capabilities the toolkit doesn't cover (shared utilities to build)
- **State shape** — the `@dataclass State` fields and their types
- **Failure modes** — what can go wrong and how the agent handles it
- **Verification plan** — how `dry_run_agent` should validate the agent

The TDD is written to `<slug>/TDD.md` in your workspace. Open it in an editor tab alongside the SPEC for review.

**Review the TDD carefully.** The Intent→Stage Map is the most critical section — every row becomes a `stages/<name>.py` file and `dry_run_agent` enforces it. Check that:

- Every SPEC intent has a row
- Stage file names follow `stages/<basename>.py`
- Entry function names follow `async def <name>(state, ctx)`
- Toolkit modules are correct (cross-check with `read_toolkit_api` if unsure)
- No placeholder gaps were missed

**Iterate if needed:**

```
technical_design(agent_name="turbine analyst", corrections="section 4: use create_fast_llm_caller for the router, not create_llm_caller")
```

**Validate and confirm:**

Before confirming, run structural validation:
```
validate_tdd(agent_name="turbine analyst")
```

Fix any errors reported, then confirm:
```
confirm_technical_design(agent_name="turbine analyst", confirmed=True)
```

Confirmation runs a final structural check and unlocks scaffolding.

---

### Phase 3: Scaffold — Create the Files

With both SPEC and TDD confirmed, scaffold the agent:

```
scaffold_code_agent(name="turbine analyst")
```

This creates the complete folder structure in your workspace:

```
turbine_analyst/
├── __init__.py               # AGENT_CARD_METADATA + create_workflow
├── workflow.py               # Stage switchboard (≤200 LOC)
├── state.py                  # @dataclass State, initial_state()
├── hooks.py                  # RouterHooks instance
├── SPEC.md                   # Your confirmed SPEC
├── TDD.md                    # Your confirmed TDD
├── design.json               # Structured design record
├── stages/
│   ├── __init__.py           # Re-exports stage functions
│   ├── compare_turbines.py   # async def run_compare_turbines(state, ctx)
│   └── flag_underperformers.py  # async def run_flag_underperformers(state, ctx)
└── prompts/
    ├── router.txt            # Intent classification system prompt
    ├── compare_turbines.txt  # Stage-specific system prompt
    └── flag_underperformers.txt
```

The scaffold creates one `stages/<name>.py` stub per Intent→Stage Map row, each containing the declared `async def <entry_fn>(state, ctx)` signature with a `raise NotImplementedError` placeholder. The prompts are also stubs — one `.txt` per stage.

**The agent is immediately live.** The container's file watcher picks up the new folder and exposes it at `/agents/turbine-analyst/` through the tunnel. You can run `dry_run_agent` against the stubs before writing any implementation:

```
dry_run_agent(agent_name="turbine analyst")
```

This confirms the structure is correct even before any logic is written. Expect `pass-partial` (stubs raise `NotImplementedError`).

---

### Phase 4: Implement — Write the Agent Logic

With the scaffold in place, implement each stage stub. The AI assists you here — tell it which stage to implement and it will read the relevant skills and toolkit API to generate correct, idiomatic code.

**Before implementing, the AI must read the skills in this order:**

```
read the correct-agent-patterns skill
```

Then, as needed:
- `advanced-code-patterns` — for button handling, deterministic routing, multi-turn caching
- `workflow-structure` — if `workflow.py` grows complex
- Domain skills (`marked-data`, `time-series-analysis`, `viz-data-shaping`, etc.)
- `prompt-engineering` — when writing the system prompt files

**Example conversation:**

```
Implement the run_compare_turbines stage in turbine_analyst/stages/compare_turbines.py.
It should run SQL to compare turbines by power output, mark the top N in Spotfire, 
and return a summary table. Use the columns from the TDD's data flow section.
```

The AI reads the skill, checks the toolkit API, and generates code that follows the correct patterns.

**Key implementation patterns** (the `correct-agent-patterns` skill covers all of these):

- Create `ask_user = create_ask_user('turbine_analyst_ask')` at **module level** in `workflow.py`, not inside `build_workflow`
- Detect the Spotfire open-trigger with `is_agent_open_trigger(initial_message)` and show the welcome screen + `format_orientation(...)` + `action_buttons(...)` on the first turn
- Route free-text through the LLM router; route button clicks directly via `STAGE_DISPATCH`
- Run `discover_schema(ask_user_fn=ask_user)` before any LLM or SQL call
- Use `execute_stage(state, ctx, ...)` rather than calling LLM directly from the stage

---

### Phase 5: Validate — Dry-Run and Test

After implementing each stage, re-run `dry_run_agent`:

```
dry_run_agent(agent_name="turbine analyst")
```

Iterate until the status is `pass` or `pass-partial`.

**Testing in Spotfire:**

1. Open your Spotfire document with the turbine data.
2. Open the Copilot panel. Your tunneled agent appears in the agent list (close and reopen the panel if needed to force a refresh).
3. Select **Turbine Analyst** and interact with it — the welcome screen should appear, then the action buttons.

**Reading logs if something goes wrong:**

```
read_agent_logs(agent_name="turbine analyst")
```

Logs contain the full Python traceback for any exception that occurred during execution.

---

### Phase 6: Register for Other Users (Optional)

Tunneled agents are private — only your Spotfire session sees them. To make an agent available to other Spotfire users on the same orchestrator, register it in the orchestrator admin console using HTTP-direct mode.

See the `register-agent` skill for step-by-step instructions:

```
read the register-agent skill
```

The key difference from tunnel mode: you must provide the container's `BASE_URL` in the admin console, and the container must be reachable from the orchestrator over HTTP (cloud or on-premise deployment).

---

## 8. Agent Structure Reference

### 8.1 Folder Layout

Every agent lives in its own folder under the workspace root (i.e., the directory bind-mounted at `/custom-workflows`). The folder name becomes the agent's slug — underscores are replaced with hyphens in the URL:

```
turbine_analyst/  →  /agents/turbine-analyst/
```

**Minimum viable code agent:**

```
turbine_analyst/
├── __init__.py      # required: AGENT_CARD_METADATA + create_workflow
└── workflow.py      # required: FunctionalWorkflow
```

**Recommended layout (multi-stage agents):**

```
turbine_analyst/
├── __init__.py
├── workflow.py        # switchboard only (≤200 LOC)
├── state.py           # @dataclass State
├── hooks.py           # RouterHooks
├── SPEC.md            # design spec
├── TDD.md             # technical design
├── design.json        # structured design record
├── stages/
│   ├── __init__.py    # re-exports stage functions
│   └── <intent>.py    # one file per intent
└── prompts/
    ├── router.txt     # intent routing prompt
    └── <intent>.txt   # one file per stage
```

### 8.2 Required Files

#### `__init__.py`

Must export exactly:

```python
AGENT_CARD_METADATA = {
    "name": "Turbine Analyst",
    "description": "Analyses wind turbine performance...",
    "version": "0.1.0",
    "skills": [
        {
            "id": "compare_turbines",
            "name": "Compare Turbines",
            "description": "Compares turbine output against site average.",
            "tags": ["performance", "comparison"],
            "examples": ["Which turbines are underperforming?"],
        },
    ],
}

def create_workflow(**kwargs):
    """Factory called at startup. Must be synchronous (def, not async def)."""
    from turbine_analyst.workflow import build_workflow
    return build_workflow(**kwargs)
```

The `name` and `description` fields appear in the Spotfire Copilot agent list. The `skills[].examples` are shown to the LLM router to guide intent matching.

#### `workflow.py`

Contains `build_workflow(**kwargs)` which returns a `FunctionalWorkflow`. The workflow function is a Python `async def` coroutine. For the correct shape (module-level `ask_user`, open-trigger detection, schema discovery first), read the `correct-agent-patterns` skill.

### 8.3 Prompt File Conventions

Prompts are plain text files loaded explicitly by stage code. The conventional hierarchy:

```
prompts/
├── router.txt              # intent classification — lists intents + descriptions
├── <stage_name>.txt        # stage-specific instructions for the LLM
├── base/                   # optional shared context
│   ├── role_intro.txt      # who the agent is
│   ├── data_schema.txt     # what data it works with
│   └── output_rules.txt    # how to format responses
└── intents/                # optional per-intent additions (prompt-relay agents)
    └── <intent>.txt
```

In code-based agents, stages load prompt files explicitly:

```python
from pathlib import Path

PROMPTS_DIR = Path(__file__).parent.parent / "prompts"

async def run_compare_turbines(state, ctx):
    system_prompt = build_stage_system_prompt(
        role_intro=PROMPTS_DIR.joinpath("base/role_intro.txt").read_text(),
        stage_instructions=PROMPTS_DIR.joinpath("compare_turbines.txt").read_text(),
        schema=state.contract,
    )
    ...
```

---

## 9. Working in Non-VS-Code Environments

The MCP development server is a standard HTTP MCP endpoint and can be connected to any MCP-compatible AI coding assistant (Claude Code, Cursor, JetBrains AI Assistant, Cline, etc.). See [§1.4](#14-which-ai-coding-assistant), Which AI Coding Assistant?, for the short version and the "your mileage may vary" caveat. This section covers the details.

The development experience differs in one important way: **`design_agent_form` renders a rich interactive form in VS Code** (via the MCP Apps `ui://` resource protocol). Other clients do not support this — they will receive raw JSON instead of the rendered form.

**In non-VS-Code environments:**

- Use `design_agent` instead of `design_agent_form` — it runs the same design conversation but as a text-only elicitation
- All other tools (`technical_design`, `scaffold_code_agent`, `dry_run_agent`, `read_skill`, etc.) work identically across all MCP clients
- Skills and the toolkit API reference are the same content regardless of client

**Configuring the MCP endpoint** in other clients means pointing them at `http://localhost:8050/mcp/` as an HTTP MCP server. For **Claude Code**, create a project-root `.mcp.json` (note the `mcpServers` key — VS Code uses `servers`):

```json
{
  "mcpServers": {
    "spotfire-agent-dev": {
      "type": "http",
      "url": "http://localhost:8050/mcp/"
    }
  }
}
```

Or add it from the CLI: `claude mcp add --transport http spotfire-agent-dev http://localhost:8050/mcp/`. For Cursor, Cline, and JetBrains, consult your client's documentation for the exact configuration syntax — all of them accept an HTTP MCP server URL.

**The `setup_workspace` tool is Copilot-oriented.** It writes `.github/` instruction and prompt files, a `.github/copilot-instructions.md`, and a VS Code-shaped `.vscode/mcp.json` — none of which Claude Code or other clients read. Running it in a non-VS-Code workspace still gives you the portable artifacts (the `agent_registry_toolkit_for_spotfire_stubs-*.whl` and a `pyproject.toml`), which are all you need for stub installation. Install the stubs into a local `.venv` exactly as in [§4.4](#44-install-the-stubs-into-a-local-virtual-environment). Claude Code users who want the equivalent standing guidance can copy the key rules from `correct-agent-patterns` into a `CLAUDE.md` at the project root.

**Note on skills and pattern compliance:** The MCP server's system prompt instructs the AI to read `correct-agent-patterns` before writing any code, and to use `read_toolkit_api` instead of guessing imports. In VS Code with GitHub Copilot, these instructions flow automatically via the MCP server's `instructions` field. In other clients, the same instructions are technically present but enforcement varies — you may need to explicitly ask the AI to read the skills before generating code.

---

## 10. Troubleshooting

### MCP server not connecting

| Symptom | Likely cause | Fix |
|---|---|---|
| No MCP tools in Copilot Chat; `list agents` returns a text answer instead of a tool result | VS Code has not connected the MCP server | Confirm the container is running, `MCP_ENABLED=true`, and `.vscode/mcp.json` exists at the workspace root with the correct URL. Open the command palette → **MCP: List Servers** |
| MCP server listed but no tools | Server connected but tool list empty | Check container logs: `docker compose logs dev \| grep MCP`. The MCP server logs "MCP server started" at startup |
| `connection refused` on `http://localhost:8050/mcp/` | Container not running, or `MCP_ENABLED` not set | `docker compose ps` to confirm the container is up; check `.env` for `MCP_ENABLED=true` |

### Agent not visible in Spotfire

| Symptom | Likely cause | Fix |
|---|---|---|
| Tunneled agent not in Spotfire agent list | `TUNNEL_USER_ID` mismatch | Compare the value in `.env` against your Spotfire username exactly — case, domain, and realm portion. The match is case-sensitive |
| Agent was visible, now gone | Tunnel disconnected | Check `docker compose logs dev \| grep -i tunnel`. The container reconnects automatically, but close and reopen the Spotfire Copilot panel to force a refresh |
| Adding a new agent folder — not appearing | Missing container restart | Hot-reload picks up changes to existing agents; adding a new folder requires `docker compose restart` |

### Stale local Python process (port conflict)

**Symptom:** Agent returns 404 from orchestrator; works fine from `localhost:8050` directly on the host.

**Cause:** A stale `uv run` or uvicorn process from a previous session is still running on the host, bound to port 8050. Docker's vpnkit routes `host.docker.internal:8050` non-deterministically between the container and the host process — requests sometimes hit the wrong server.

**Diagnosis:**

```powershell
# Windows — find all listeners on 8050
netstat -ano | findstr ":8050" | findstr "LISTEN"

# Identify the process
Get-CimInstance Win32_Process -Filter "ProcessId = <PID>" | Select-Object CommandLine
```

**Fix:**

```powershell
Stop-Process -Id <PID> -Force
```

**Prevention:** Never leave `uv run` processes running in VS Code terminals when the container is active on the same port.

### `dry_run_agent` fails immediately

| Error type | Fix |
|---|---|
| `ImportError` or `ModuleNotFoundError` | Check your imports against `correct-agent-patterns`. Ensure you are using `from agent_framework import FunctionalWorkflow` (not `from ag2 import ...`) |
| `TypeError: create_workflow() got unexpected keyword argument` | `create_workflow` must accept `**kwargs` even if it doesn't use them |
| `TDD manifest mismatch` | A stage file declared in the TDD's Intent→Stage Map is missing from disk. Scaffold creates them; check that you have not deleted or renamed a file |
| Stuck loop (`status: fail`, repeated `request_id`) | The workflow is not advancing — likely a missing `is_agent_open_trigger` check or an incorrect button payload. Read `advanced-code-patterns` for the correct dispatch pattern |

### LLM calls failing inside the agent

All LLM calls from agents are relayed to the orchestrator. Check:

1. `ORCHESTRATOR_URL`, `ORCHESTRATOR_CLIENT_ID`, and `ORCHESTRATOR_CLIENT_SECRET` are correct in `.env`
2. The orchestrator is reachable: `curl http://host.docker.internal:8080/healthz` from inside the container — `docker compose exec dev curl http://host.docker.internal:8080/healthz`
3. The orchestrator client has the correct scopes (`agent_developer` profile)

### Hot-reload not picking up changes

| Symptom | Fix |
|---|---|
| Edits to an existing agent are not picked up | The watcher runs inside the container. Confirm the file you edited is inside the bind-mounted directory. Check container logs for "Reloading agent" messages |
| A brand new agent folder is not discovered | New folders require `docker compose restart` — hot-reload only updates existing discovered agents |
| Changes are picked up but the agent still behaves the old way | The agent may be caching state across hot-reloads. The container's in-process reload re-imports the module but does not restart pending conversations. Start a new conversation in Spotfire |

---

## 11. Security Considerations

The MCP server is designed for **local development only**. It must be disabled in production. The risks it introduces are:

- **Unauthenticated file creation.** `scaffold_code_agent` and related tools create files in `CUSTOM_WORKFLOWS_DIR` without authentication. Anyone who can reach `/mcp/` can create files in your workspace.
- **Source code and template exposure.** `read_skill`, `read_template`, and `read_toolkit_api` return internal implementation details that would assist an attacker targeting the container.
- **Agent internals.** `list_agents`, `dry_run_agent`, and `read_agent_logs` reveal agent names, conversation history, and exception tracebacks.

**On a development workstation, these are acceptable trade-offs** — port 8050 is only accessible from localhost by default, and the tools are designed for developer use.

**Mandatory production controls:**

- `MCP_ENABLED` must be unset or `false` in every non-development deployment
- Do not expose port 8050 to any network beyond localhost — never use `0.0.0.0:8050` without a firewall in front
- Do not commit `.env` files containing `MCP_ENABLED=true` to source control
- The tunnel (`TUNNEL_ENABLED=true`) is also development-only and must be disabled in production

See the [Setup and Deployment Guide for the Agent Registry Container](../Spotfire%20Copilot%20Agent%20Registry%20-%20Domain%20Agents/Spotfire%20Copilot%20-%20Agent%20Registry%20Installation%20Guide.md) for the full production security guidance.

---

*Copyright © 2006 – 2026 Cloud Software Group, Inc. All rights reserved.*
