# Spotfire License Management Agent — User Guide

spotfire × licenses × administration

The Spotfire License Management Agent is a specialist AI agent that helps administrators view and manage Spotfire licenses and license functions for users and groups on a Spotfire Server.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [Invoking the Agent](#invoking-the-agent)
  - [What You Provide](#what-you-provide)
  - [What Data Is Available](#what-data-is-available)
- [What the Agent Can Do](#what-the-agent-can-do)
- [How the Workflow Operates](#how-the-workflow-operates)
  - [Stage 1: Orientation](#stage-1-orientation)
  - [Stage 2: License Catalog and Functions](#stage-2-license-catalog-and-functions)
  - [Stage 3: User Entitlements](#stage-3-user-entitlements)
  - [Stage 4: Group Entitlements](#stage-4-group-entitlements)
  - [Stage 5: License Assignment and Revocation](#stage-5-license-assignment-and-revocation)
  - [Stage 6: Multi-step Workflows](#stage-6-multi-step-workflows)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The Spotfire License Management Agent is a conversational assistant available inside the Spotfire Copilot Panel. It is connected to a Spotfire Server's license-administration endpoints through a dedicated MCP server and is designed to answer license questions — and perform license assignment changes — in natural language, without needing the Administration Manager UI or direct REST calls.

The agent uses a set of specialized tools to list licenses, list license functions, look up the licenses enabled for a specific user or group, and assign or revoke licenses (and their constituent functions) on a per-group basis. It can also enumerate the users and groups defined on the Spotfire Server.

The agent works independently of the surrounding analysis or dashboard. It does not receive marked rows, table data, or column metadata from a visualization — it only acts on the questions and instructions you type into the Spotfire Copilot Panel, and all answers come from the Spotfire Server through the agent's tools.

> **Note on changes.** Some of the tools modify license assignments (assign or remove licenses for a group). The agent should be used by administrators with the appropriate permissions, and the underlying credentials configured on the MCP server determine what is actually allowed.

## Prerequisites

This agent is not deployed standalone. Before you can invoke it from the Spotfire Copilot Panel, two components must already be deployed and reachable in your environment:

- **LangGraph agent server** — the agent ships as part of the LangGraph agent server. See the [OSS deployment guide](../Agent%20Server%20Deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md) or the [licensed deployment guide](../Agent%20Server%20Deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28Licensed%29%20Deployment%20Guide.md).
- **`spotfire-lic` MCP server** — the agent's tools call this MCP server at runtime. See the [Spotfire License MCP server user guide](../MCP%20Servers/Spotfire%20License/Spotfire%20Copilot%20-%20Spotfire%20License%20MCP%20Server%20User%20Guide.md) and [deployment guide](../MCP%20Servers/Spotfire%20License/Spotfire%20Copilot%20-%20Spotfire%20License%20MCP%20Server%20Deployment%20Guide.md).

If either component is missing or unreachable, the agent will not appear in the Copilot Panel, or it will fail to answer with a tool-related error.

## Getting Started

### Invoking the Agent

1. Open the Spotfire Copilot Panel.
2. Select **Spotfire License Management Agent** (or the equivalent label configured in your environment) from the agent picker if more than one agent is available.
3. Type your question and press Enter.

No data attachment step is required. The agent always queries the live Spotfire Server.

### What You Provide

The agent only needs **natural-language questions**. To get focused answers, mention any of the following when they apply to your question:

| Reference          | Examples                                                       |
| ------------------ | -------------------------------------------------------------- |
| License name       | `Spotfire Analyst`, `Spotfire Consumer`, `Spotfire Business Author` |
| License function   | `OpenAnalysisInClient`, `DataOnDemand`, `ScheduledUpdates`     |
| User identifier    | A Spotfire user ID (UUID), or "the user `jdoe`"                |
| Group identifier   | A Spotfire group ID (UUID), or "the Analysts group"            |
| Inheritance scope  | "including inherited", "direct only"                           |

If a required identifier is missing (for example, a group when asking about a group's licenses), the agent will ask a short clarifying question or first call a discovery tool to retrieve the list of groups.

### What Data Is Available

The agent reads from (and where applicable writes to) a Spotfire Server through the `spotfire-lic` MCP server. Typical content includes:

- **Licenses** — every license defined on the Spotfire Server, with its functions.
- **License functions** — the individual capabilities that make up a license.
- **User license assignments** — the licenses and functions enabled for a specific user (typically resolved through group membership).
- **Group license assignments** — the licenses and functions assigned to a group, optionally including those inherited from parent groups.
- **Users and groups** — the user and group accounts defined on the Spotfire Server.

The agent does **not** ingest spreadsheet uploads or read marked rows from a visualization. Read and write access is determined by the credentials configured on the MCP server.

## What the Agent Can Do

The Spotfire License Management Agent groups its tools into the following capability areas:

| Capability                       | What It Does                                                                                                  | Example Request                                                  |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| License Catalog                  | List all licenses defined on the Spotfire Server, optionally with their full set of functions                  | "List all licenses."                                             |
| License Function Inspection      | List the functions that belong to a specific license                                                           | "What functions are in `Spotfire Analyst`?"                       |
| User Entitlements                | Show the licenses and functions enabled for a user (and optionally for a specific license)                     | "What licenses does user `<user-id>` have?"                       |
| Group Entitlements               | Show the licenses and functions assigned to a group, optionally including inherited assignments                | "What licenses does the Analysts group have, including inherited?" |
| License Assignment               | Assign or update a license — and specific functions within it — for a group                                    | "Give the Analysts group `Spotfire Analyst` with `DataOnDemand`."  |
| License Revocation               | Remove a license from a group                                                                                  | "Remove `Spotfire Analyst` from the Contractors group."           |
| User & Group Discovery           | List all users or all groups defined on the Spotfire Server                                                    | "List all groups."                                               |

## How the Workflow Operates

The agent guides you through a natural, question-and-answer flow. There is no upload step — every question is answered by calling the appropriate tools against the live Spotfire Server.

### Stage 1: Orientation

**When to use:** You want to know what is available before drilling in.

**Example prompts:**
- "What can you do?"
- "List all licenses."
- "List all groups."
- "List all users."

**What you get back:** A capability summary or a JSON-derived list of licenses, groups, or users.

### Stage 2: License Catalog and Functions

**When to use:** You want to know which licenses exist on the server and what each one includes.

**Example prompts:**
- "List all licenses and their functions."
- "What functions are in `Spotfire Analyst`?"
- "Show me the function list for `Spotfire Consumer`."

**What you get back:** The set of licenses on the server and, for any one license, the full list of its functions.

### Stage 3: User Entitlements

**When to use:** You want to know what a specific user can do.

**Example prompts:**
- "What licenses does user `<user-id>` have?"
- "Which functions of `Spotfire Analyst` are enabled for user `<user-id>`?"

**What you get back:** The licenses and license functions enabled for the user — typically derived from the user's group memberships.

### Stage 4: Group Entitlements

**When to use:** You want to know what a group is entitled to, or whether a particular license is reaching the group through inheritance.

**Example prompts:**
- "What licenses does the Analysts group have?"
- "What licenses does the Analysts group have, including inherited ones?"
- "Which functions of `Spotfire Analyst` are enabled for the Analysts group?"

**What you get back:** The licenses and functions assigned to the group, with an indication of inherited vs. direct assignments when requested.

### Stage 5: License Assignment and Revocation

**When to use:** You want to grant or remove licenses for a group. These operations modify the Spotfire Server.

**Example prompts:**
- "Assign `Spotfire Analyst` to the Analysts group with all functions."
- "Give the Analysts group `Spotfire Analyst` with only `OpenAnalysisInClient` and `DataOnDemand`."
- "Remove `Spotfire Analyst` from the Contractors group."

**What you get back:** A confirmation of the change as reported by the Spotfire Server, and (when appropriate) a re-read of the group's entitlements so you can verify the result.

### Stage 6: Multi-step Workflows

**When to use:** Your question combines discovery and a change.

**Example prompts:**
- "Find the Analysts group and give it `Spotfire Analyst` with all functions."
- "List the functions in `Spotfire Analyst`, then assign the read-only subset to the Contractors group."
- "Show me the licenses for the Analysts group, including inherited ones, then remove the directly-assigned `Spotfire Business Author` license."

**What you get back:** A consolidated answer where the agent has chained tools internally (list groups / list license functions → assign or remove → re-read group entitlements) and reports the final result with brief notes about intermediate steps.

## Typical End-to-End Session

```
You:    What can you do?

Agent:  [Returns the capability summary covering license catalog,
         user and group entitlements, assignment and revocation,
         and user/group discovery.]

You:    List all licenses.

Agent:  Spotfire Analyst, Spotfire Business Author, Spotfire Consumer,
        Spotfire Automation Services, Spotfire Statistics Services,
        Spotfire Library Administrator.

You:    What functions are in Spotfire Analyst?

Agent:  OpenAnalysisInClient, DataOnDemand, ScheduledUpdates,
        InformationDesigner, Geocoding, ScriptAuthor, ...

You:    List all groups.

Agent:  Analysts, Contractors, Administrators, Authors, Consumers, ...

You:    What licenses does the Analysts group have, including inherited?

Agent:  Direct:    Spotfire Analyst (all functions)
        Inherited: Spotfire Library Administrator (from "Administrators")

You:    Remove Spotfire Library Administrator from Administrators.

Agent:  Removed Spotfire Library Administrator from the
        Administrators group. Re-reading the Analysts group...
        Direct:    Spotfire Analyst (all functions)
        Inherited: (none)
```

## Key Benefits

| Benefit                              | Description                                                                                                                  |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| Natural-language license admin       | Discover licenses, inspect entitlements, and make assignment changes in plain English without opening the admin UI.          |
| User and group perspectives          | Ask the same question from a user's or a group's perspective; the agent picks the right tool.                                 |
| Inheritance awareness                | Group entitlement queries can include or exclude licenses inherited from parent groups.                                      |
| Fine-grained assignments             | Assign a license with a specific list of functions, not just the license as a whole.                                          |
| Audit-friendly verification          | After a change, the agent can re-read the affected group's entitlements so the result is easy to confirm.                     |
| Works independently                  | No need to mark rows or attach tables — the agent acts on the question you type in the Spotfire Copilot Panel.               |

## Tips for Best Results

- **Identify groups and users by name when possible.** The agent will look up IDs via the discovery tools and confirm them before making changes.
- **Be explicit about inheritance.** Say "including inherited" or "direct only" when asking about group entitlements.
- **State the function list when assigning.** "Give the Analysts group `Spotfire Analyst` with `DataOnDemand` and `OpenAnalysisInClient`" is unambiguous; "give them Analyst" lets the agent default to all functions.
- **Verify after changes.** Asking "show me the Analysts group's licenses again" right after an assignment gives you an audit trail.
- **Cap discovery lists.** For large servers, ask for "the first 25 groups" or filter by name to keep responses easy to scan.
- **Treat mutations carefully.** Changes to license assignments take effect on the Spotfire Server. Use a clear, single instruction per change.
- **Ask for help anytime.** Typing `help` or `what can you do?` returns the capability summary.

## Glossary

| Term                         | Definition                                                                                                                |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Spotfire Server              | The server that hosts the Spotfire library, user accounts, licenses, and authentication.                                  |
| License                      | A named set of capabilities (e.g. `Spotfire Analyst`) that can be assigned to groups.                                     |
| License Function             | An individual capability inside a license (e.g. `OpenAnalysisInClient`, `DataOnDemand`).                                  |
| User                         | A Spotfire user account defined on the Spotfire Server.                                                                   |
| Group                        | A Spotfire group account; licenses are assigned to groups, and users inherit entitlements from their group memberships.   |
| Inheritance                  | The mechanism by which a group's licenses can be inherited from parent groups.                                            |
| Assignment                   | The act of granting a license (with selected functions) to a group.                                                       |
| Revocation                   | The act of removing a license from a group.                                                                               |
| MCP Server                   | The Model Context Protocol server (`spotfire-lic`) that exposes the license tools the agent calls at runtime.             |
