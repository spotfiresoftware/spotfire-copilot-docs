# Adding Domain Agents via Overlay (DeepAgents OSS)

> Companion to the [DeepAgents OSS Deployment Guide](Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md).
> That guide deploys the server and its **baked-in** agents. This guide explains
> how to add your **own domain / data-source agents at deploy time** — no image
> rebuild — using an **agent overlay bundle**.

## Table of Contents

- [1. Introduction](#1-introduction)
  - [1.1 Purpose](#11-purpose)
  - [1.2 The model: baked agents + overlay agents](#12-the-model-baked-agents--overlay-agents)
  - [1.3 Terminology (avoid the "overlay" ambiguity)](#13-terminology-avoid-the-overlay-ambiguity)
  - [1.4 When to use an overlay](#14-when-to-use-an-overlay)
- [2. Concepts](#2-concepts)
  - [2.1 The baked image](#21-the-baked-image)
  - [2.2 The overlay bundle](#22-the-overlay-bundle)
  - [2.3 What a behavior pack is](#23-what-a-behavior-pack-is)
  - [2.4 How layering and enablement work](#24-how-layering-and-enablement-work)
  - [2.5 The prefix is the environment namespace](#25-the-prefix-is-the-environment-namespace)
- [3. Prerequisites](#3-prerequisites)
- [4. Authoring an overlay bundle](#4-authoring-an-overlay-bundle)
  - [4.1 Folder layout](#41-folder-layout)
  - [4.2 The overlay manifest (`agents.yaml`)](#42-the-overlay-manifest-agentsyaml)
  - [4.3 Manifest field reference](#43-manifest-field-reference)
  - [4.4 The pack (`pack.yaml` + content)](#44-the-pack-packyaml--content)
  - [4.5 The per-agent environment (by prefix)](#45-the-per-agent-environment-by-prefix)
- [5. Deploying the overlay](#5-deploying-the-overlay)
  - [5.1 Docker Compose (folder mount)](#51-docker-compose-folder-mount)
  - [5.2 Kubernetes / Helm](#52-kubernetes--helm)
  - [5.3 GitHub Actions / infra deploy tooling](#53-github-actions--infra-deploy-tooling)
- [6. Worked example: a Databricks domain agent](#6-worked-example-a-databricks-domain-agent)
- [7. Verify](#7-verify)
- [8. Add another domain, upgrade, and roll back](#8-add-another-domain-upgrade-and-roll-back)
- [9. Troubleshooting](#9-troubleshooting)
- [10. Security notes](#10-security-notes)

---

## 1. Introduction

### 1.1 Purpose

The DeepAgents OSS server ships a fixed set of **generic, data-source-neutral
agents** in its image. This guide shows how to add **your own specialized
agents** **at deploy time**, by layering an **overlay bundle** over the running
image. Adding or removing an agent is a configuration change (a `docker compose`
restart or a `helm upgrade`), never an image rebuild.

These agents are usually **areas or sub-categories within your organization's
domain**, not necessarily entirely different data sources. For example, an
energy company might run separate agents for **petroleum**, **operations**,
**HSE**, and **reservoir** — each scoped to its own data, prompt, and knowledge,
often over the **same backend**. (This guide uses *domain agent* loosely for any
such specialized agent.)

Each agent needs an **MCP server** that exposes its backend as tools. If you
don't already have one for your backend, build and deploy it first — see the
[MCP Servers guides](../mcp-servers/README.md) and the
[Databricks MCP Server Blueprint Guide](../agents/databricks-mcp-server-blueprint/Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20Blueprint%20Guide.md)
for a worked blueprint.

### 1.2 The model: baked agents + overlay agents

The system has two layers:

| Layer | What it is | Who owns it | Changes require |
|---|---|---|---|
| **Baked agents** | The generic agents compiled into the image (OSDU, DV, Spotfire Library/License, Tavily, Milvus, DDR, Databricks Genie, Snowflake, Support). | Spotfire / the image build | A new image tag |
| **Overlay agents** | Your domain agents, described by a bundle (a manifest + behavior packs). | You (the operator) | A values / bundle change at deploy time |

The image is immutable; your domains are supplied on top. **You author and own
the overlay agents — the product ships no domain agents of its own.** Any
specific agent names used in this guide (a Databricks example in
[section 6](#6-worked-example-a-databricks-domain-agent)) are **illustrative
only**: they demonstrate the mechanism, not agents included in the product.

### 1.3 Terminology (avoid the "overlay" ambiguity)

Two unrelated things are both called "overlay". Keep them separate:

- **Agent overlay bundle** — *this guide*. A folder (`agents.yaml` + `packs/`)
  that adds **agents** to the running server. Delivered via the chart's
  `overlays` block or a mounted folder.
- **Helm/cloud values overlay** — a Helm *values* file with cloud-specific
  defaults (e.g. AWS ALB ingress). Covered in the OSS Deployment Guide
  ("Cloud Overlay Usage"). It has nothing to do with adding agents.

Throughout this document, "overlay" means the **agent overlay bundle**.

### 1.4 When to use an overlay

Use an overlay bundle when you want to:

- Expose a **scoped** assistant (e.g. one Databricks Genie space, one Snowflake
  schema, one catalog, one business area) as its own A2A agent.
- Run **several areas of the same domain** side by side (e.g. petroleum,
  operations, HSE for an energy company) — often over the **same backend** — each
  with its own prompt, knowledge, and credentials.
- Add an agent for a **new backend or data source** without waiting for an image
  release.

You do **not** need an overlay to run the baked agents — configure those with
their `*_MCP_SERVER_URL` variables as described in the OSS Deployment Guide.

---

## 2. Concepts

### 2.1 The baked image

The image exposes a fixed roster of baked agent IDs:

```
osdu_agent, dv_agent, sf_lib_md_agent, sf_lic_agent, tavily_agent,
milvus_agent, ddr_agent, databricks_genie_agent, snowflake_agent, support_agent
```

These are **generic**: each connects to an MCP server you point it at. They are
always present and are selected/limited with `AGENTS_ENABLED` / `AGENTS_DISABLED`.

### 2.2 The overlay bundle

An overlay bundle is a self-contained folder:

```
<bundle>/
  agents.yaml                 # the overlay manifest — one row per domain agent
  packs/
    <agent_id>/               # one behavior pack per agent
      pack.yaml
      system_prompt.md
      AGENTS.md
      help.md
      skills/<skill_id>/SKILL.md
```

At startup the server reads a single **overlay manifest** (via the
`AGENTS_OVERLAY_MANIFEST` path) and layers its agents on top of the baked roster.
The bundle is backend-agnostic — the same structure works for Databricks,
Snowflake, or any other source; only the manifest fields and the pack content
differ.

### 2.3 What a behavior pack is

A **pack** is everything that makes an agent domain-specific — with **no code**:

| File | Purpose |
|---|---|
| `pack.yaml` | Agent-card manifest: `name`, `description`, `version`, and the `skills` advertised on the card. |
| `system_prompt.md` | The agent's routing and tone instructions. |
| `AGENTS.md` | Domain knowledge — entities, formulas, thresholds, conventions. |
| `help.md` | The "help / what can you do" text and starter prompts. |
| `skills/<id>/SKILL.md` | One file per capability skill. |

A pack turns a generic template into "the Petroleum agent for the Volve field on
Databricks" purely through content.

### 2.4 How layering and enablement work

At startup the effective agent set is computed as:

```
baked manifest   <   overlay manifest   <   AGENTS_ENABLED / AGENTS_DISABLED
```

- **Overlay agents auto-enable.** Any agent that appears in the overlay but not
  in the baked roster is added and enabled automatically. You do **not** need to
  list overlay agents in `AGENTS_ENABLED` — that variable is an allow-list for
  **baked** agents only.
- **Disable still wins.** An overlay agent can be turned off by adding its ID to
  `AGENTS_DISABLED`.
- An overlay row whose ID matches a baked agent **overrides** that baked agent.

> Practical consequence: leave `AGENTS_ENABLED` describing the baked agents you
> want (or empty for all). Your overlay agents come along regardless.

### 2.5 The prefix is the environment namespace

Every overlay agent declares a **`prefix`**. That prefix is the namespace for all
of that agent's configuration variables. For an agent with `prefix: RESERVOIR`
the operator supplies:

- `RESERVOIR_MCP_SERVER_URL` (+ `RESERVOIR_MCP_BEARER_TOKEN`), or OAuth
  (`RESERVOIR_OAUTH_CLIENT_ID` / `_SECRET` / `_TOKEN_URL`).
- Optional model override: `RESERVOIR_DEEPAGENTS_MODEL`.

Resolution order (highest wins): `<PREFIX>_<KEY>` → `<BACKEND>_<KEY>` shared →
pack `config.servers` default. This lets one credential set (e.g. a shared
`DATABRICKS_OAUTH_CLIENT_ID`) serve several flavors while each flavor keeps its
own URLs.

---

## 3. Prerequisites

- A deployed DeepAgents OSS server (see the OSS Deployment Guide), reachable and
  healthy (`/healthz`, `/readyz`).
- For each agent: a running, reachable **MCP server / endpoint** that exposes
  your backend as tools, plus its credentials (static bearer token or an OAuth
  service principal). To build one, see the
  [MCP Servers guides](../mcp-servers/README.md) and the
  [Databricks MCP Server Blueprint Guide](../agents/databricks-mcp-server-blueprint/Spotfire%20Copilot%20-%20Databricks%20MCP%20Server%20Blueprint%20Guide.md).
- A **behavior pack** for each agent (prompt, knowledge, help, skills). For a
  worked authoring walkthrough see the
  [Behavior Pack Authoring Guide](../agents/databricks-mcp-server-blueprint/Spotfire%20Copilot%20-%20Databricks%20Agent%20Behavior%20Pack%20Authoring%20Guide.md)
  (Section 4 below summarizes the structure).
- Your model provider credentials already configured for the server. If an agent
  uses **AWS Bedrock**, the pod's IRSA role must be able to assume the Bedrock
  role from **this deployment's namespace** — see [section 9](#9-troubleshooting).
- Tools to package a bundle: `tar` + `base64` (Helm archive path), or Python 3
  (for the `gen-overlay-values.py` files path).

---

## 4. Authoring an overlay bundle

### 4.1 Folder layout

Create a folder you own (in your own repo — it is independent of the chart and
the image):

```
my-overlays/
  agents.yaml
  packs/
    reservoir_agent/
      pack.yaml
      system_prompt.md
      AGENTS.md
      help.md
      skills/
        query/SKILL.md
```

`pack:` paths in `agents.yaml` are resolved **relative to the manifest file's
directory**, so keep `agents.yaml` and `packs/` together.

### 4.2 The overlay manifest (`agents.yaml`)

```yaml
agents:
  reservoir_agent:
    template: mcp                 # agent template (mcp = MCP-backed agent)
    prefix: RESERVOIR             # env namespace for THIS agent
    pack: packs/reservoir_agent   # relative to this manifest file
    auth: bearer                  # bearer (static token) or oauth (M2M client-credentials)
    # model_prefix: RESERVOIR     # optional; defaults to `prefix`
```

### 4.3 Manifest field reference

| Field | Required | Description |
|---|---|---|
| `template` | Yes | The agent template. `mcp` builds an MCP-backed agent (the common case). |
| `prefix` | Yes | Uppercase namespace for this agent's env vars (`<PREFIX>_MCP_SERVER_URL`, `<PREFIX>_OAUTH_*`, `<PREFIX>_DEEPAGENTS_MODEL`, …). |
| `pack` | Yes | Path to the behavior pack, relative to the manifest file (or absolute). |
| `auth` | No | `bearer` (static `<PREFIX>_MCP_BEARER_TOKEN`) or `oauth` (M2M client-credentials via `<PREFIX>_OAUTH_*`). Default: bearer/global token. |
| `capabilities` | No | Expands a family of servers for one prefix. `databricks` expands to four managed servers: `<PREFIX>_FUNCTIONS_/VECTORSEARCH_/GENIE_/DBSQL_MCP_SERVER_URL`. Omit for a single `<PREFIX>_MCP_SERVER_URL`. |
| `model_prefix` | No | Prefix used to resolve the model (`<model_prefix>_DEEPAGENTS_MODEL`). Defaults to `prefix`. |

### 4.4 The pack (`pack.yaml` + content)

Minimal `pack.yaml`:

```yaml
name: "Reservoir Agent"
description: >-
  A reservoir-engineering assistant for <domain>. Retrieves data and answers
  questions via its MCP tools.
version: "0.1.0"

skills:
  - id: query
    name: Data questions
    description: Answer natural-language questions against the domain's data.
    tags: [reservoir, data]
  - id: help-and-capabilities
    name: Help and capabilities
    description: Onboarding and meta questions like "help" / "what can you do".
```

`help-and-capabilities` is provided by middleware (no `SKILL.md` needed); every
other skill ID maps to `skills/<id>/SKILL.md`. Put your routing rules in
`system_prompt.md`, your domain facts in `AGENTS.md`, and your starter prompts in
`help.md`.

### 4.5 The per-agent environment (by prefix)

Supply the deployment-specific values named by the agent's prefix. Non-secret
values (URLs, client IDs, transport) go in plain config; secrets (tokens, client
secrets) go in your secret store.

Static-token agent (`auth: bearer`):

```
RESERVOIR_MCP_SERVER_URL=https://mcp-reservoir.example.com/mcp
RESERVOIR_MCP_BEARER_TOKEN=<secret>          # or the shared MCP_BEARER_TOKEN fallback
RESERVOIR_MCP_SERVER_TRANSPORT=streamable-http
```

OAuth (M2M) agent (`auth: oauth`):

```
RESERVOIR_OAUTH_CLIENT_ID=<application-id>
RESERVOIR_OAUTH_CLIENT_SECRET=<secret>
RESERVOIR_OAUTH_TOKEN_URL=https://<host>/oidc/v1/token   # optional if derivable
```

Optional single-agent model override (keep the fleet on one model, move just this
agent):

```
RESERVOIR_DEEPAGENTS_MODEL=azure_openai:<deployment>
```

---

## 5. Deploying the overlay

Pick the path that matches your environment. In all cases the bundle content is
identical; only the delivery mechanism differs.

### 5.1 Docker Compose (folder mount)

The Compose stack **mounts a folder** at `/config/overlay`. Point `OVERLAY_DIR`
at your bundle and set `AGENTS_OVERLAY_MANIFEST` to load it.

`.env`:

```env
# Add your domain agents by mounting your bundle folder, then loading its manifest.
OVERLAY_DIR=./my-overlays
AGENTS_OVERLAY_MANIFEST=/config/overlay/agents.yaml

# Per-agent env (named by prefix)
RESERVOIR_MCP_SERVER_URL=https://mcp-reservoir.example.com/mcp
RESERVOIR_MCP_BEARER_TOKEN=replace-me
```

The provided `docker-compose.yml` already mounts `${OVERLAY_DIR}:/config/overlay:ro`,
so this is a `.env` change only:

```bash
docker compose up -d
```

Nested `skills/` subfolders are preserved by the folder mount. No rebuild.

### 5.2 Kubernetes / Helm

The chart is pulled **immutable** from the registry, so the bundle cannot live
inside it — you supply it at install time. Two equivalent options:

#### Option A — tarball (recommended; no helper script)

Package the folder as a base64 `tar.gz` and let the chart's `overlay-unpack`
init container untar it into `/config/overlay`:

```bash
tar czf bundle.tgz -C my-overlays .     # my-overlays = agents.yaml + packs/…
base64 < bundle.tgz > bundle.b64        # (Linux: `base64 bundle.tgz` also works)

helm upgrade --install deepagents-oss \
  oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss \
  --version <chart-version> -n <namespace> --create-namespace \
  -f my-values.yaml \
  --set overlays.enabled=true \
  --set-file overlays.archiveBase64=bundle.b64
```

> **Full-stack chart.** With `copilot-deepagents-server-oss-stack`, prefix the
> overlay keys with the subchart name:
> `--set copilot-deepagents-server-oss.overlays.enabled=true` and
> `--set-file copilot-deepagents-server-oss.overlays.archiveBase64=bundle.b64`.

#### Option B — files values (no tar)

Generate an `overlays.files` values file from your folder and pass it with `-f`:

```bash
python gen-overlay-values.py my-overlays > overlay-values.yaml
#   --subchart copilot-deepagents-server-oss   # for the -stack chart

helm upgrade --install deepagents-oss <chart-ref> --version <chart-version> \
  -n <namespace> --create-namespace \
  -f my-values.yaml -f overlay-values.yaml
```

Both options render the bundle into a ConfigMap, mount it (nested `skills/`
preserved), and set `AGENTS_OVERLAY_MANIFEST`. If both `archiveBase64` and
`files` are set, the archive wins.

#### Supplying the per-agent env in Helm

Non-secret values go in `config.extraEnv`; secrets go in `secret.extraSecretEnv`:

```yaml
config:
  extraEnv:
    RESERVOIR_MCP_SERVER_URL: http://mcp-reservoir.mcp-servers.svc:80/mcp
    RESERVOIR_MCP_SERVER_TRANSPORT: streamable-http
    RESERVOIR_OAUTH_CLIENT_ID: "<application-id>"
    RESERVOIR_OAUTH_TOKEN_URL: https://<host>/oidc/v1/token
secret:
  extraSecretEnv:
    RESERVOIR_MCP_BEARER_TOKEN: "<secret>"
    RESERVOIR_OAUTH_CLIENT_SECRET: "<secret>"
```

(For the `-stack` chart, nest these under `copilot-deepagents-server-oss:`.)

### 5.3 GitHub Actions / infra deploy tooling

If you deploy through the infra repo's tooling, the bundle and its non-secret env
live next to the deploy scripts as a **single** artifact, and the deploy script
wires them in:

```
deployments/<cloud>/overlays/
  bundle.b64            # the single deploy bundle (base64 tar.gz) the chart unpacks
  values.overlay.yaml   # overlays.enabled + non-secret <PREFIX>_* env (NO secrets)
  SOURCE.md             # provenance: which source(s)/commit it was built from
  build-bundle.py       # merges one or more source folders -> bundle.b64
```

Deploy (plain Helm or the wrapper script):

```bash
./deploy-stack.sh deploy <env> \
  --overlay-archive deployments/<cloud>/overlays/bundle.b64 \
  --overlay-values  deployments/<cloud>/overlays/values.overlay.yaml
```

In a workflow-config `*.env` file this is:

```env
LANGGRAPH_OSS_OVERLAY_ARCHIVE=overlays/bundle.b64
# non-secret per-agent env goes in the values file or as LANGGRAPH_OSS_XENV_* / EXTRA_ENV
```

**Secrets** (`*_OAUTH_CLIENT_SECRET`, bearer tokens) never go in the values file
or git — provide them as repository secrets mapped to the deployment's
`EXTRA_SECRET_ENV` (e.g. the `LANGGRAPH_OSS_EXTRA_SECRET_ENV` GitHub secret, one
`KEY=VALUE` per line).

> **One bundle, many domains.** The server loads exactly one manifest, so
> multiple domains run together only when they are combined into **one** bundle.
> Keep each domain's pack **source** in its own folder for authoring, then merge
> at build time:
> `python build-bundle.py -o bundle.b64 <databricks-src> <snowflake-src>`
> (agent IDs and pack folder names must be unique across sources).

---

## 6. Worked example: a Databricks domain agent

> **Illustrative only.** The product ships **no** domain agents. The agent IDs
> and packs below are an example of a bundle **you would author**, shown to
> demonstrate the mechanism — in particular a Databricks backend, which exercises
> the `capabilities: databricks` multi-server expansion. Use your own agent IDs,
> packs, workspace, and credentials.

An example bundle manifest defining three Databricks domain agents:

```yaml
# agents.yaml
agents:
  databricks_petroleum_agent:  { template: mcp, prefix: DATABRICKS_PETRO,      auth: oauth, capabilities: databricks, pack: packs/databricks_petroleum }
  databricks_htm_agent:        { template: mcp, prefix: DATABRICKS_HTM,        auth: oauth, capabilities: databricks, pack: packs/databricks_htm }
  databricks_energyops_agent:  { template: mcp, prefix: DATABRICKS_ENERGYOPS,  auth: oauth, capabilities: databricks, pack: packs/databricks_energyops }
```

Because `capabilities: databricks` expands to four managed servers per prefix,
each flavor needs four URLs plus its OAuth service principal. For
`DATABRICKS_PETRO` (repeat for `_HTM`, `_ENERGYOPS`):

```yaml
config:
  extraEnv:
    DATABRICKS_PETRO_FUNCTIONS_MCP_SERVER_URL:    https://<ws-host>/api/2.0/mcp/functions/<catalog>/<schema>
    DATABRICKS_PETRO_VECTORSEARCH_MCP_SERVER_URL: https://<ws-host>/api/2.0/mcp/vector-search/<catalog>/<schema>
    DATABRICKS_PETRO_GENIE_MCP_SERVER_URL:        https://<ws-host>/api/2.0/mcp/genie/<space_id>
    DATABRICKS_PETRO_DBSQL_MCP_SERVER_URL:        https://<ws-host>/api/2.0/mcp/sql
    DATABRICKS_PETRO_OAUTH_CLIENT_ID:             <service-principal-app-id>
secret:
  extraSecretEnv:
    DATABRICKS_PETRO_OAUTH_CLIENT_SECRET:         <service-principal-secret>
```

Notes specific to Databricks:

- **Genie must be a scoped space** (`/genie/<space_id>`), which scopes the tools
  to your domain's tables — this is the primary data-retrieval path.
- The **OAuth token URL auto-derives** from the workspace host
  (`https://<ws-host>/oidc/v1/token`); set `<PREFIX>_OAUTH_TOKEN_URL` only to
  override.
- A shared `DATABRICKS_OAUTH_CLIENT_ID` / `DATABRICKS_OAUTH_CLIENT_SECRET`
  (backend fallback) can serve all three flavors if they use one service
  principal; per-flavor `<PREFIX>_OAUTH_*` overrides it.
- To adapt to a **different** domain, create a new Genie space (+ functions +
  indexes), author a pack, add a manifest row with a new prefix, and set that
  prefix's URLs — no code, no image change.

Deploy exactly as in [section 5](#5-deploying-the-overlay). The baked agents keep
running; the example Databricks agents are added on top.

---

## 7. Verify

After deploying, confirm the overlay loaded and the agents are serving.

Kubernetes (adjust the deployment/namespace names):

```bash
NS=<namespace>
POD=$(kubectl -n "$NS" get pods -o name | grep -vE 'postgres|redis' | head -1)

# The overlay-unpack init container ran and the manifest is set
kubectl -n "$NS" get "$POD" -o jsonpath='{range .spec.initContainers[*]}{.name}{"\n"}{end}'   # includes overlay-unpack
kubectl -n "$NS" exec "${POD#pod/}" -- sh -c 'ls /config/overlay; echo $AGENTS_OVERLAY_MANIFEST'

# Registry loaded the expected count and your domain agents
kubectl -n "$NS" logs "${POD#pod/}" | grep -E 'Server ready|instantiated .* via template'
kubectl -n "$NS" logs "${POD#pod/}" | grep '<your_agent_id>'   # aggregated N tool(s) from M server(s)
```

Any environment — hit the agent card (public even when auth is enabled), then an
authenticated call (replace `<your_agent_id>` with one of your overlay agents):

```bash
BASE=http://<host>:8000     # or a port-forward: kubectl -n <ns> port-forward svc/<svc> 18000:8000

# Public agent card
curl -fsS "$BASE/a2a/<your_agent_id>/.well-known/agent-card.json" | head
read -rs "TOKEN?A2A bearer token: "; echo
curl -s "$BASE/a2a/<your_agent_id>" \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","parts":[{"kind":"text","text":"help"}],"messageId":"'"$(uuidgen)"'"}}}' \
  | python3 -m json.tool
```

Healthy signals:

- Startup log shows the expected total (baked + your overlay agents), e.g.
  `Server ready: agents=<N>`.
- Each overlay agent logs `aggregated N MCP tool(s) from M server(s)`.
- The agent card returns `200` and its `url` reflects `PUBLIC_BASE_URL`.
- Unauthenticated `POST /a2a/<id>` returns `401` (auth enforced); `help` returns
  a completed task without touching a backend.

---

## 8. Add another domain, upgrade, and roll back

- **Add a domain:** author its pack + a manifest row, rebuild the single bundle
  from all sources (`build-bundle.py -o bundle.b64 <src1> <src2>`), add its
  non-secret `<PREFIX>_*` env and secrets, and redeploy. The deploy paths and
  file names don't change — only the bundle's contents grow.
- **Upgrade an existing domain:** edit its pack (prompt/knowledge/skills), rebuild
  the bundle, and `helm upgrade` (or `docker compose up -d`). Bump the pack's
  `version` so the change is visible on the agent card.
- **Roll back:** overlay agents are values-only. `helm rollback <release>`, or
  redeploy without the overlay `-f` / `--set-file` to drop back to just the baked
  agents. In Compose, remove `AGENTS_OVERLAY_MANIFEST` (or `OVERLAY_DIR`) and
  restart.

---

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `overlay archive not found: …/bundle.b64` at deploy | The path passed to the deploy script is relative to a different working directory. | Pass an **absolute** path, or run the deploy from the directory the relative path is anchored to. The bundle must exist on the deploy host/runner. |
| Startup crash: `AGENTS_ENABLED lists unknown agents` | An overlay agent ID was added to `AGENTS_ENABLED`. | Don't list overlay agents in `AGENTS_ENABLED` — they auto-enable. Keep that variable for baked agents only. |
| Overlay agent missing from the registry | Manifest not loaded, or the ID is in `AGENTS_DISABLED`. | Confirm `AGENTS_OVERLAY_MANIFEST` points at the mounted `agents.yaml`; check the file mounted at `/config/overlay`; remove the ID from `AGENTS_DISABLED`. |
| Agent starts with **0 tools** | Its `<PREFIX>_*_MCP_SERVER_URL` is unset or unreachable. | Set the prefix's URL(s); verify the MCP server is reachable from the pod; check the `aggregated N tool(s)` log line. |
| `pack not found` / wrong card text | `pack:` path wrong, or `agents.yaml` and `packs/` were separated. | `pack:` is relative to the manifest file — keep `agents.yaml` and `packs/` together in the bundle. |
| **Bedrock** agent: `AccessDenied … AssumeRoleWithWebIdentity` | The IAM role's trust policy doesn't authorize **this** namespace's service account. New namespaces are not trusted automatically. | Add `system:serviceaccount:<namespace>:<serviceaccount>` to the role's trust policy `:sub` condition (array), or use a `StringLike` wildcard. No pod restart needed once it matches. Only agents on `bedrock_converse:*` need this. |
| Stray `._*` files under `/config/overlay` | The bundle tar was built on macOS and captured AppleDouble metadata. | Harmless (ignored by the loader). To clean: build the tar with `COPYFILE_DISABLE=1 tar …` or `--exclude='._*'`. |
| Agent card `url` is unreachable to clients | `PUBLIC_BASE_URL` doesn't resolve for the caller. | Set `PUBLIC_BASE_URL` to a client-reachable address; the card advertises `<PUBLIC_BASE_URL>/a2a/<id>`. |

---

## 10. Security notes

- **Never put secrets in the bundle or in `values.overlay.yaml`.** The bundle
  (packs + manifest) and non-secret env are config; `*_MCP_BEARER_TOKEN`,
  `*_OAUTH_CLIENT_SECRET`, and provider keys belong in your secret store
  (Kubernetes Secret / GitHub Actions secret → `secret.extraSecretEnv` /
  `EXTRA_SECRET_ENV`).
- **Prefer OAuth (M2M) over static tokens** for backends that support it
  (e.g. Databricks): tokens are short-lived and auto-refreshed.
- **Least privilege per domain.** Scope each service principal / token to only
  the data the domain agent should reach (e.g. one Genie space, one schema).
- **Keep inbound auth on.** Use `A2A_AUTH_MODE=bearer` (or `oidc`) so only
  authorized callers can invoke agents; agent cards can remain public via
  `A2A_AUTH_PUBLIC_CARD=true` for discovery without exposing invocation.
- **Pack source is not secret, but review it.** Prompts and `AGENTS.md` shape
  agent behavior — treat pack changes like code changes (branch, review, version).
