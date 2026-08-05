# Spotfire Copilot - DeepAgents Deployment Scripts User Guide

Interactive helper scripts that generate the DeepAgents OSS server deployment
configuration (Docker Compose **or** Kubernetes/Helm), wire up optional agents
and their MCP servers, and manage image-tag upgrades.

Two equivalent scripts are provided so you can run the generator from either platform:

| Script | Platform | Interpreter |
| --- | --- | --- |
| [`spotfire-copilot-ecosystem-deploy.sh`](spotfire-copilot-ecosystem-deploy.sh) | Linux / macOS | Bash 4+ |
| [`spotfire-copilot-ecosystem-deploy.ps1`](spotfire-copilot-ecosystem-deploy.ps1) | Windows | PowerShell 5.1+ |

Both scripts are functionally identical: same prompts, same defaults, same
generated files. Choose the one that matches your operating system.

> These scripts only **generate** configuration. They do not pull images, start
> containers, or install anything into a cluster. You review the generated files,
> then run `docker compose` / `helm` yourself. For full background on the server,
> charts, agents, and A2A registration, see the
> [DeepAgents OSS Deployment Guide](../Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md).

---

## Table of Contents

- [1. What the scripts do](#1-what-the-scripts-do)
- [2. Prerequisites](#2-prerequisites)
- [3. Quick start](#3-quick-start)
- [4. Command-line options](#4-command-line-options)
- [5. Interactive walkthrough](#5-interactive-walkthrough)
  - [5.1 Deployment target](#51-deployment-target)
  - [5.2 Image and server settings](#52-image-and-server-settings)
  - [5.3 Persistence](#53-persistence)
  - [5.4 Model provider](#54-model-provider)
  - [5.5 A2A authentication](#55-a2a-authentication)
  - [5.6 Agents and MCP wiring](#56-agents-and-mcp-wiring)
- [6. Generated files](#6-generated-files)
  - [6.1 Docker Compose output](#61-docker-compose-output)
  - [6.2 Kubernetes output](#62-kubernetes-output)
- [7. Deploying the generated configuration](#7-deploying-the-generated-configuration)
- [8. Upgrading the image tag](#8-upgrading-the-image-tag)
- [9. Re-running the generator](#9-re-running-the-generator)
- [10. Security notes](#10-security-notes)
- [11. Troubleshooting](#11-troubleshooting)

---

## 1. What the scripts do

The generator interviews you about a single DeepAgents OSS server deployment and
writes ready-to-use configuration for one of two targets:

- **Docker Compose** — a `.env` file and a `docker-compose.yml` for a single host.
- **Kubernetes (Helm)** — a `values.yaml` bundle plus `create-secret.sh` and
  `helm-install.sh` helper scripts for the DeepAgents OSS Helm chart.

Along the way it can:

- Select an approved container image tag (and validate its format).
- Fix the container port at `8000` and publish it through a separate host port,
  bound to loopback (`127.0.0.1`) by default for safety.
- Configure local (in-Compose) or external/managed PostgreSQL + Redis.
- Choose the LLM provider (OpenAI, Anthropic, or Google) and model.
- Configure A2A authentication (bearer token, API key header, or none).
- Enable any subset of the ten catalog agents and wire each one to its MCP server.
- Validate the generated Compose file with `docker compose config`.

The scripts never run `docker compose down -v` and never delete data volumes.

---

## 2. Prerequisites

**Common**

- An approved DeepAgents OSS image tag (from Spotfire Support or your platform team).
- Network access to the registry `copilotoci.azurecr.io`.
- Credentials for the LLM provider you intend to use.

**Linux / macOS (`spotfire-copilot-ecosystem-deploy.sh`)**

- Bash 4 or newer.
- `openssl` (used to generate random secrets).
- Docker Engine + Docker Compose V2 — required for Compose validation and to run
  the deployment. Optional at generation time (validation is skipped if absent).

**Windows (`spotfire-copilot-ecosystem-deploy.ps1`)**

- Windows PowerShell 5.1 or newer.
- Docker Desktop (Compose V2) — optional at generation time, required to run the
  deployment.

**Kubernetes target (either script)**

- `kubectl` and `helm` are **not** needed on the generating machine. The scripts
  only produce a values bundle plus helper scripts that you later run from a
  machine that has cluster access.

> The generated Kubernetes helper scripts (`create-secret.sh`, `helm-install.sh`)
> are Bash scripts on both platforms, because they are meant to run where
> `kubectl`/`helm` live (typically Linux).

---

## 3. Quick start

**Linux / macOS**

```bash
chmod +x spotfire-copilot-ecosystem-deploy.sh
./spotfire-copilot-ecosystem-deploy.sh
```

**Windows (PowerShell)**

```powershell
.\spotfire-copilot-ecosystem-deploy.ps1
```

Answer the prompts, review the files written to the output directory
(`./deepagents-oss-deploy` by default), then deploy.

Non-interactive examples that pre-seed some choices:

```bash
# Compose, local Postgres/Redis, a fixed image tag
./spotfire-copilot-ecosystem-deploy.sh --compose --local --image-tag 1.0.0

# Kubernetes values bundle in a custom directory
./spotfire-copilot-ecosystem-deploy.sh --kubernetes --dir /opt/deepagents-oss --namespace deepagents
```

```powershell
# Compose, external Postgres/Redis
.\spotfire-copilot-ecosystem-deploy.ps1 -Compose -External -ImageTag 1.0.0

# Kubernetes values bundle
.\spotfire-copilot-ecosystem-deploy.ps1 -Kubernetes -Dir C:\opt\deepagents-oss -Namespace deepagents
```

---

## 4. Command-line options

All options are optional; anything not supplied is asked for interactively. Bash
uses `--long-flags`; PowerShell uses `-PascalCaseParameters`.

| Bash flag | PowerShell parameter | Description |
| --- | --- | --- |
| `--help`, `-h` | `-Help`, `-h` | Show help and exit. |
| `--dir DIR` | `-Dir DIR` | Output/deployment directory. Default: `./deepagents-oss-deploy`. |
| `--image-tag TAG` | `-ImageTag TAG` | Approved DeepAgents OSS image tag. |
| `--host-port PORT` | `-HostPort PORT` | Host port mapped to container port 8000 (Compose). |
| `--host-bind ADDRESS` | `-HostBind ADDRESS` | Host interface to publish the port on. Default `127.0.0.1`. |
| `--public-base-url URL` | `-PublicBaseUrl URL` | `PUBLIC_BASE_URL`. Defaults to `http://localhost:<host-port>`. |
| `--local` | `-Local` | Use local Compose PostgreSQL + Redis. |
| `--external` | `-External` | Use external/managed PostgreSQL + Redis. |
| `--compose` | `-Compose` | Generate a Docker Compose deployment (default). |
| `--kubernetes`, `--k8s` | `-Kubernetes`, `-k8s` | Generate a Kubernetes Helm values bundle instead. |
| `--chart-version VER` | `-ChartVersion VER` | Approved Helm chart version (Kubernetes mode). |
| `--namespace NS` | `-Namespace NS` | Kubernetes namespace. Default `deepagents-oss`. |
| `--rotate-a2a-token` | `-RotateA2aToken` | Generate a new A2A bearer token/API key instead of reusing the existing one. |
| `--upgrade` | `-Upgrade` | Update `IMAGE_TAG` in an existing Compose deployment directory. |

**Environment overrides** (both scripts): `OUT_DIR`, `DEFAULT_IMAGE_TAG`,
`NO_COLOR`.

---

## 5. Interactive walkthrough

### 5.1 Deployment target

Choose **Docker Compose** (single host) or **Kubernetes** (Helm values bundle).
This can be pre-selected with `--compose`/`-Compose` or `--kubernetes`/`-Kubernetes`.

### 5.2 Image and server settings

- **Image tag** — validated against the OCI tag format (letters, digits, `.`, `_`, `-`).
- **HOST** — the container's internal bind address. Default `0.0.0.0`.
- **Container port** — fixed at `8000` (not prompted).
- **Host-published port** (`DEEPAGENTS_HOST_PORT`) — the port on the host that
  maps to container `8000`. Default `8000`.
- **Host interface** (`DEEPAGENTS_HOST_BIND`) — `127.0.0.1` (loopback, default and
  safest) or `0.0.0.0` (all interfaces). Choosing `0.0.0.0` prints a warning to
  ensure A2A auth and firewall rules are in place.
- **PUBLIC_BASE_URL** — the external URL clients use. Defaults to
  `http://localhost:<host-port>`.
- **LOG_LEVEL** — one of `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`.

### 5.3 Persistence

- **Local** — PostgreSQL + Redis run as Compose services. A random PostgreSQL
  password is generated (or reused from an existing `.env`). If a data volume
  already exists but no password is present, the script stops rather than pairing
  a persisted volume with a new password.
- **External** — you provide `POSTGRES_URL` and `REDIS_URL`. These are checked for
  leftover placeholders (`<...>`, `USER:PASS`, `POSTGRES_HOST`, `REDIS_HOST`,
  `replace-me`) and rejected if any remain.

### 5.4 Model provider

Pick **OpenAI**, **Anthropic**, or **Google Gemini**. The script prompts for the
matching API key (masked) and the `DEEPAGENTS_MODEL` value, and enforces that the
model string starts with the selected provider prefix. Defaults:

| Provider | Key variable | Default model |
| --- | --- | --- |
| OpenAI | `OPENAI_API_KEY` | `openai:gpt-5.1` |
| Anthropic | `ANTHROPIC_API_KEY` | `anthropic:claude-3-5-sonnet-latest` |
| Google | `GOOGLE_API_KEY` | `google:gemini-2.0-flash` |

### 5.5 A2A authentication

Controls how clients (for example the Orchestrator) authenticate to the DeepAgents
A2A endpoints.

- **Compose** offers `bearer` (recommended), `apikey`, or `none`.
- **Kubernetes** offers `bearer` (recommended) or `none`.

For `bearer`/`apikey` the script can generate a random credential or accept one you
provide. On re-runs it reuses the existing credential unless you pass
`--rotate-a2a-token`/`-RotateA2aToken`. `none` is intended only for isolated labs
and prints warnings (especially when combined with a non-loopback bind).

### 5.6 Agents and MCP wiring

All agents are **disabled** unless you enable them here. You are shown a numbered
catalog and can enter comma-separated numbers, `all`, or leave it blank for a base
server with no agents.

| # | Agent | Prefix | Co-host port | MCP type |
| --- | --- | --- | --- | --- |
| 1 | OSDU | `OSDU` | 8063 | co-hosted |
| 2 | Databricks | `DATABRICKS` | 8061 | co-hosted |
| 3 | Data Virtualization (DV) | `DV` | 8065 | co-hosted |
| 4 | Spotfire Library Metadata | `SFLIB` | 8062 | co-hosted |
| 5 | Spotfire License Management | `SFLIC` | 8064 | co-hosted |
| 6 | Tavily Web Search | `TAVILY` | 8058 | co-hosted |
| 7 | Daily Drilling Reports (DDR) | `DDR` | 8060 | co-hosted |
| 8 | Databricks Genie | `GENIE` | — | external MCP |
| 9 | Snowflake | `SNOWFLAKE` | — | external MCP |
| 10 | Milvus | `MILVUS` | — | external MCP |

For each enabled agent you are prompted for:

- `<PREFIX>_MCP_SERVER_URL` — for co-hosted agents in Compose mode this defaults to
  `http://host.docker.internal:<co-host-port>/mcp`; external-MCP agents require an
  explicit URL.
- `<PREFIX>_MCP_SERVER_TRANSPORT` — default `streamable-http`.
- `<PREFIX>_MCP_BEARER_TOKEN` — optional; leave blank if the MCP server has no
  inbound auth.

> Deploy each agent's MCP server **first** (see the mcp-servers deployment guides),
> then enable the agent here so DeepAgents can reach it.

---

## 6. Generated files

Files are written into the output directory with restrictive permissions
(`chmod 600` on Linux, best-effort `icacls` on Windows), and any existing file is
backed up with a timestamped `.bak` copy first.

### 6.1 Docker Compose output

```
<output-dir>/
├── .env                                  # server + agent configuration and secrets
├── docker-compose.yml                    # deepagents-oss (+ postgres/redis if local)
└── deepagents-deployment-summary.txt     # human-readable summary
```

Key characteristics of the generated Compose file:

- Container port fixed at `8000`, published as
  `${DEEPAGENTS_HOST_BIND:-127.0.0.1}:${DEEPAGENTS_HOST_PORT:-8000}:8000`.
- `restart: unless-stopped` and `extra_hosts: host.docker.internal:host-gateway`.
- A `healthcheck` hitting `/healthz`.
- In local mode, PostgreSQL and Redis are **not** published to the host.

### 6.2 Kubernetes output

```
<output-dir>/k8s/
├── values.yaml                    # Helm values (app-only or full-stack)
├── create-secret.sh               # creates the referenced Kubernetes Secret
├── helm-install.sh                # helm upgrade --install
└── deepagents-k8s-summary.txt     # human-readable summary
```

- **External persistence** uses the app-only chart
  `oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss`.
- **Bundled persistence** uses the full-stack chart
  `oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss-stack`
  and generates a random in-cluster PostgreSQL password.
- Secrets (provider key, A2A credential, per-agent MCP bearer tokens) are placed in
  `create-secret.sh`, kept out of `values.yaml`, which references an existing Secret.

---

## 7. Deploying the generated configuration

**Docker Compose**

```bash
cd <output-dir>
docker login copilotoci.azurecr.io
docker compose up -d
curl -fsS http://localhost:<host-port>/healthz
curl -fsS http://localhost:<host-port>/readyz
```

**Kubernetes** (from a machine with `kubectl` and `helm`)

```bash
cd <output-dir>/k8s
bash create-secret.sh     # create/update the Kubernetes Secret
bash helm-install.sh      # helm upgrade --install
kubectl -n <namespace> get pods
```

---

## 8. Upgrading the image tag

Upgrade mode updates `IMAGE_TAG` in an existing Compose deployment directory,
re-validates the Compose file, and prints restart commands. It requires the target
directory to already contain `.env` and `docker-compose.yml`.

```bash
./spotfire-copilot-ecosystem-deploy.sh --upgrade --image-tag 1.0.1 --dir ./deepagents-oss-deploy
```

```powershell
.\spotfire-copilot-ecosystem-deploy.ps1 -Upgrade -ImageTag 1.0.1 -Dir .\deepagents-oss-deploy
```

Then apply it:

```bash
cd <output-dir>
docker login copilotoci.azurecr.io
docker compose up -d
```

For Kubernetes upgrades, re-run the generator (or edit `values.yaml`) and run
`helm-install.sh` again.

---

## 9. Re-running the generator

Running the generator again against an existing directory reuses previous values
as defaults where possible: image tag, host settings, persistence mode, model and
provider, and A2A credentials are read from the existing `.env`. Existing files are
backed up before being overwritten. Use `--rotate-a2a-token`/`-RotateA2aToken` to
force a new A2A credential (remember to update every registered client afterward).

---

## 10. Security notes

- Generated `.env`, `values.yaml`, secret scripts, and backups contain secrets.
  They are written with owner-only permissions where the platform allows; keep them
  out of source control.
- The host port binds to `127.0.0.1` by default. Only choose `0.0.0.0` when a
  firewall/reverse proxy is in place and A2A authentication is enabled.
- Prefer `bearer` A2A authentication for anything beyond an isolated lab. Avoid
  `none`.
- The scripts never run destructive Docker commands and never delete data volumes;
  removing a persisted PostgreSQL volume is left to you, deliberately.
- Rotate the A2A credential and provider keys per your organization's policy.

---

## 11. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `Docker Compose V2 is required` | Install Docker Engine + Compose V2, or generate without validation and run it elsewhere. |
| `docker compose config failed` | Review the Compose error printed above; usually a missing/invalid value in `.env`. |
| `... still contains a placeholder` | An external `POSTGRES_URL`/`REDIS_URL` (or K8s URL) still has template text like `USER:PASS`. Provide real values. |
| `The existing DeepAgents PostgreSQL volume was found, but no password exists` | A local data volume exists without a stored password. Restore the original `.env`/password, or intentionally remove the volume outside the script. |
| `Invalid image tag` | Use an approved OCI tag: letters, digits, `.`, `_`, `-` only. |
| `DEEPAGENTS_MODEL must start with '<provider>:'` | The model string must match the selected provider, e.g. `openai:gpt-5.1`. |
| An enabled agent can't be reached | Confirm the agent's MCP server is deployed, reachable at the configured URL, and that any required bearer token matches. |
| PowerShell "running scripts is disabled" | Launch with `powershell -ExecutionPolicy Bypass -File .\.spotfire-copilot-ecosystem-deploy.ps1`, or set an appropriate execution policy. |

---

**Related documentation:** [DeepAgents OSS Deployment Guide](../Spotfire%20Copilot%20Agent%20Registry%20-%20Ecosystem%20Agents/agent-server-deployment/Spotfire%20Copilot%20-%20LangGraph%20DeepAgents%20Server%20%28OSS%29%20Deployment%20Guide.md)
