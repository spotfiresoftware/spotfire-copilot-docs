<!--
  <copyright file="WELL_RECOMPLETIONS_AGENT_USER_GUIDE.md" company="Cloud Software Group, Inc.">
    Copyright (c) 2006 - 2026 Cloud Software Group, Inc.
  All rights reserved.
  This software is the confidential and proprietary information
  of Cloud Software Group, Inc. ("Confidential Information"). You shall not
  disclose such Confidential Information and may not use it in any way,
  absent an express written license agreement between you and
  Cloud Software Group, Inc. that authorizes such use.
  </copyright>
-->

# Well Recompletions Agent — User Guide

## Table of Contents

- [Introduction](#introduction)
- [Getting Started](#getting-started)
  - [Invoking the Agent](#invoking-the-agent)
  - [What Data Does It Need?](#what-data-does-it-need)
- [How the Workflow Operates](#how-the-workflow-operates)
  - [Stage 1: Schema Discovery & Contract Negotiation (Automatic)](#stage-1-schema-discovery--contract-negotiation-automatic)
  - [Stage 2: Field Discovery](#stage-2-field-discovery)
  - [Stage 3: Candidate Listing](#stage-3-candidate-listing)
  - [Stage 4: Well-by-Well Evaluation](#stage-4-well-by-well-evaluation)
  - [Stage 5: Map Marking & Visualization](#stage-5-map-marking--visualization)
  - [Stage 6: Filtering & Exploration](#stage-6-filtering--exploration)
  - [Stage 7: General Questions](#stage-7-general-questions)
- [Typical End-to-End Session](#typical-end-to-end-session)
- [Key Benefits](#key-benefits)
- [Tips for Best Results](#tips-for-best-results)
- [Glossary](#glossary)

---

## Introduction

The **Well Recompletions Agent** is a specialist AI agent available within Spotfire Copilot that helps petroleum engineers and asset managers identify wells with untapped potential for **horizontal re-entry**, **recompletion**, or **refracturing**. Rather than manually filtering and cross-referencing data across spreadsheets, the agent works directly with the well data already loaded in your Spotfire analysis — querying it, filtering the map, and delivering expert-level recommendations in a guided, conversational workflow.

The agent acts as a senior petroleum engineering consultant: it understands well status codes, production metrics, formation data, completion vintages, and cost economics. It identifies candidates systematically, evaluates each well against its peers, and produces an actionable rating table you can export back into Spotfire for further analysis.

---

## Getting Started

### Invoking the Agent

1. Open your Spotfire analysis containing well data (e.g., a Well Index table with production and status information).
2. Open Spotfire Copilot.
3. Press the **/** key to bring up the agent selector.
4. Choose **Well Recompletions Agent** from the list.

The agent will greet you with three starter buttons:

| Button | Action |
|--------|--------|
| 🔍 Scan for candidates | Start scanning your data for recompletion candidates |
| 📊 What data do I have? | Review available data tables and fields |
| 📌 I'll mark wells to evaluate | Tell the agent you'll mark specific wells for evaluation |

You can click a button or type a request — for example: *"Evaluate my wells for recompletion opportunities"* or *"Which PA wells should we consider re-entering?"*

**Tip:** If you've already marked wells on your map, type **#** to send the marked wells directly for evaluation.

### What Data Does It Need?

The agent works with whatever well data is loaded in your Spotfire analysis. At minimum it needs:

- A **well table** with columns for well identifiers, well status, and total depth
- **Production data** (cumulative oil/water/gas) — embedded in the well table or linked

Optional but valuable:
- **Formation Tops** data (formations penetrated by each well)
- **Completion/frac history** metadata
- **Operator, spud date, and produced zones** columns

The agent automatically discovers your data schema — you do not need to configure column mappings manually.

---

## How the Workflow Operates

The agent guides you through a structured evaluation process in stages. At each stage, clickable **action buttons** appear so you can navigate forward, go back, or take specific actions without typing.

### Stage 1: Schema Discovery & Contract Negotiation (Automatic)

**What happens:** The moment you invoke the agent, it inspects your Spotfire analysis and negotiates a "schema contract" — a mapping from your column names to petroleum engineering concepts:

- Identifies which tables are loaded (Well Index, Formation Tops, Production, etc.)
- Reads column names and data types
- Checks what filters are currently applied
- **Negotiates a schema contract** — mapping your columns to semantic roles:
  - Well identifier (FileNo, API, WellID, etc.)
  - Well status column and status values (PA, IA, Active, etc.)
  - Grouping column (Field, Pool, Basin, etc.)
  - Production columns (cumulative oil, water, gas)
  - Depth, operator, spud date, and other key fields

**What you see:** A brief progress indicator while this completes, followed by a summary of your data (e.g., "Found 4,285 wells across 3 tables"). For known schemas like the ND Well Index, the agent uses a "fast path" and completes in under 2 seconds.

**Why it matters:** The schema contract allows the agent to work with *any* well dataset — whether it's North Dakota NDIC data, a Permian Basin database, or a custom corporate dataset with different column names. All subsequent queries and operations use your actual column names, not hardcoded assumptions.

---

### Stage 2: Field Discovery

**What happens:** The agent queries your data to find all available fields (or geographic groupings) and counts how many PA (Plugged & Abandoned) and IA (Inactive) wells exist in each.

**What you see:** A summary like:

> *"Your data has **4,285 PA/IA wells** spread across **80+ fields**. Here are the top 10 by well count:"*

Followed by a table showing the largest fields and their well counts, plus clickable buttons for the top fields:

| Button | Action |
|--------|--------|
| 🏔️ BEAVER LODGE (87) | Explore candidates in Beaver Lodge field |
| 🏔️ TIOGA (52) | Explore candidates in Tioga field |
| 🏔️ STANLEY (44) | Explore candidates in Stanley field |

**Your options:**
- **Click a field button** to proceed to candidate listing for that field
- **Type custom criteria** — e.g., *"Show me wells deeper than 18,000 ft operated by Continental"* — the agent will adapt

---

### Stage 3: Candidate Listing

**What happens:** After you select a field, the agent:

1. **Filters the Spotfire map** to show only wells in your chosen field
2. **Queries the top 20 wells** by total depth (deepest wells typically have the most recompletion potential)
3. Presents the raw well data in a table

**What you see:**

> *"I've filtered the map to show only **BEAVER LODGE** and queried the top 20 PA/IA wells by total depth."*

A data table showing each well's identifier, operator, status, total depth, produced formations, production figures, and spud date.

Below the table, the agent provides **field-level commentary**:

- How many wells are PA (re-entry candidates) vs. IA (refrac candidates)
- A production assessment — which wells show proven reservoir quality
- An overall field opportunity rating (🟢 High / 🟡 Moderate / 🔴 Low)

**Buttons offered:**

| Button | Action |
|--------|--------|
| 📊 Evaluate these wells | Proceed to full per-well evaluation |
| 🗺️ Mark all on map | Highlight all candidates on the Spotfire map |
| ↩️ Back to fields | Return to the field selection stage |

Additionally, you may see adjustment buttons to modify the query (e.g., include active wells, sort by a different column, or join production data).

---

### Stage 4: Well-by-Well Evaluation

**What happens:** This is the core analytical stage. The agent evaluates every candidate well individually using petroleum engineering criteria.

The agent automatically enriches the evaluation with additional data when available:
- **Formation Tops** — If your analysis includes a Tops table, the agent queries the specific formations each well penetrated to identify bypassed zones
- **Production Summary** — If a production table exists, the agent aggregates monthly production to show peak rates, decline patterns, and total volumes

**Factors assessed for each well:**

| Factor | What the Agent Looks At |
|--------|------------------------|
| Well status | PA = horizontal re-entry candidate; IA = refrac/recompletion candidate |
| Cumulative production | High oil = proven reservoir; low oil = potentially understimulated |
| Water-oil ratio | High WOR = water encroachment; low WOR = healthy well |
| Formation targets | Which zones were produced? Are deeper bypassed zones available? |
| Well vintage | Pre-2020 wells used older frac designs — prime refrac targets (completion technology evolves rapidly) |
| Total depth | Deeper wells may penetrate additional formation targets |
| Initial production rates | Compare IP to cumulative to assess decline severity |
| Formation Tops | (If available) Identifies specific bypassed formations |

**Rating system applied:**

| Rating | Meaning | Typical Action |
|--------|---------|----------------|
| 🟢 **RE-ENTER** | Well has bypassed formations it never produced from | Recompletion to a new zone ($2–5M) |
| 🔵 **REFRAC** | Pre-2020 well (6+ years old) with proven reservoir, likely understimulated by older completion designs | Re-stimulate the same zone ($1–3M) |
| 🟡 **EVALUATE** | Potential exists but data is insufficient or signals are mixed | Gather additional data (logs, pressure tests) |
| 🔴 **LEAVE P&A** | Poor candidate — low production, high water cut, no targets | No action recommended |

**What you see:** A comprehensive evaluation table with every well rated, plus:

- **Recommended Actions** — summary of the best RE-ENTER and REFRAC candidates
- **Evaluate Further** — what additional data would resolve the 🟡-rated wells
- **Geological Context** — formation characteristics and play description
- **Cost estimates** — individualized per well based on depth, age, and complexity

**Buttons offered:**

| Button | Action |
|--------|--------|
| 🗺️ Mark recommended wells on map | Highlight only the 🟢-rated wells on the Spotfire map |
| 📊 Add results table & scatter plot | Import the evaluation table into Spotfire as a new data table |
| ↩️ Back to fields | Start over with a different field |

---

### Stage 5: Map Marking & Visualization

**What happens:** When you click "Mark recommended wells on map" (or type *"mark the green wells"*), the agent highlights the selected wells directly on your Spotfire visualization. This is **instant and deterministic** — the agent uses the cached evaluation results rather than re-interpreting your request, ensuring the correct wells are always marked.

**What you see:** Your Spotfire map or scatter plot immediately highlights the marked wells. You can then:

- Visually inspect their geographic clustering
- Check proximity to infrastructure
- Overlay with other data layers in Spotfire

You can also ask for specific subsets:
- *"Mark the refrac candidates"* → marks only 🔵-rated wells
- *"Mark wells deeper than 20,000 ft"* → marks by custom criteria
- *"Show me a scatter plot of TD vs cumulative oil"* → creates a new visualization

---

### Stage 6: Filtering & Exploration

At any point during the conversation, you can ask the agent to manipulate Spotfire filters:

- *"Filter to just PA wells"*
- *"Show only wells operated by Continental"*
- *"Reset all filters"*
- *"Filter to spud dates before 2010"*

The agent applies these directly to your Spotfire analysis, updating all linked visualizations in real time.

---

### Stage 7: General Questions

The agent also answers general petroleum engineering questions using your data:

- *"What's the average TD in this field?"*
- *"How many wells were drilled before 2005?"*
- *"Which operator has the most PA wells?"*
- *"What formations are most common in this dataset?"*

It can run ad-hoc SQL queries against your data and present results conversationally.

---

## Typical End-to-End Session

Here's what a complete session looks like in practice:

```
You:    /Well Recompletions Agent

Agent:  [Discovers schema — 2 seconds]
        "Found 4,285 wells across 3 tables. Here's your data summary..."
        [Buttons: 🔍 Scan for candidates, 📊 What data do I have?, 📌 I'll mark wells]

You:    [Click: 🔍 Scan for candidates]

Agent:  "Your data has 4,285 PA/IA wells across 80 fields.
         Here are the top 10..."
        [Buttons: BEAVER LODGE, TIOGA, STANLEY, ...]

You:    [Click: 🏔️ BEAVER LODGE (87)]

Agent:  [Filters map to Beaver Lodge, queries top 20 wells]
        "Here are the top 20 candidates by depth..."
        [Data table + field commentary]
        [Buttons: Evaluate, Mark all, Back to fields]

You:    [Click: 📊 Evaluate these wells]

Agent:  [Runs evaluation with petroleum engineering analysis]
        "5 wells rated 🟢 RE-ENTER, 3 rated 🔵 REFRAC,
         8 rated 🟡 EVALUATE, 4 rated 🔴 LEAVE P&A"
        [Full rating table with costs and justifications]
        [Buttons: Mark recommended, Add table, Back to fields]

You:    [Click: 🗺️ Mark recommended wells on map]

Agent:  [Instantly marks 5 green-rated wells on the map]
        "Marked 5 recommended wells on the map."

You:    "Can you also show me a scatter plot of depth vs production?"

Agent:  [Creates scatter plot visualization in Spotfire]

You:    "done"

Agent:  "Session complete. Thank you for using the Well Recompletions Agent."
```

**Total time: ~2 minutes** for what would traditionally take hours of manual data review.

---

## Key Benefits

| Benefit | Description |
|---------|-------------|
| **No manual filtering** | The agent queries and filters your data automatically — no need to build complex filter schemes |
| **Works with any dataset** | Automatic schema discovery means it adapts to your column names and data structure |
| **Expert-level analysis** | Applies petroleum engineering judgment — formation targeting, vintage assessment, cost estimation |
| **Deterministic actions** | Map marking and filtering use cached results, not AI interpretation — ensuring accuracy |
| **Interactive exploration** | Clickable buttons guide you through the workflow; type free-form questions at any time |
| **Results stay in Spotfire** | Evaluation tables can be imported back as new data tables for further analysis and sharing |

---

## Tips for Best Results

- **Start broad, then narrow** — Let the agent show you the field breakdown first, then drill into specific fields
- **Mark wells before evaluating** — If you already know which wells to assess, mark them in Spotfire first and the agent will evaluate those specific wells directly
- **Use the buttons** — They're designed to guide you through the optimal workflow sequence
- **Ask follow-up questions** — After evaluation, ask things like *"Why did you rate FileNo 36186 as RE-ENTER?"* or *"What would it take to upgrade the yellow wells?"*
- **Try different fields** — Use "Back to fields" to quickly compare opportunity across multiple areas
- **Combine with visualization** — Ask for scatter plots or bar charts to visualize patterns in the evaluation data

---

## Glossary

| Term | Definition |
|------|------------|
| **PA (Plugged & Abandoned)** | A well that has been permanently sealed. Re-entering the existing wellbore is cheaper than drilling new. |
| **IA (Inactive)** | A well that is not currently producing but hasn't been permanently abandoned. May be reactivated. |
| **Recompletion** | Opening a new producing zone in an existing wellbore — targeting a formation the well penetrated but never produced from. |
| **Refracturing (Refrac)** | Re-stimulating an existing producing zone with modern frac technology to improve recovery. |
| **Horizontal Re-entry** | Drilling a lateral (horizontal) section from an existing vertical wellbore to access more reservoir. |
| **TD (Total Depth)** | The deepest point reached by the well — deeper wells may penetrate more formations. |
| **WOR (Water-Oil Ratio)** | Volume of water produced per volume of oil. High WOR suggests the reservoir is depleting. |
| **Formation Tops** | The measured depths where each geological formation begins in a wellbore. |
| **Bypassed Zone** | A formation the well drilled through but never produced from — a recompletion target. |
