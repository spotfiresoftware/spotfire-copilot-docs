# Spotfire Copilot - Backend Deployment Scripts User Guide

Interactive helper scripts that generate **Spotfire Copilot backend** deployment configuration 
and optionally deploy directly. Supports Docker Compose (single-host), AWS ECS/Fargate, and 
Azure Container Apps. The scripts produce environment files and (for single-host) a `docker-compose.yml`, 
and can optionally chain the DeepAgents OSS generator.

Two equivalent scripts are provided so you can run the generator from either platform:

| Script | Platform | Interpreter |
| --- | --- | --- |
| [`spotfire-copilot-backend-deploy.sh`](spotfire-copilot-backend-deploy.sh) | Linux / macOS | Bash 4+ |
| [`spotfire-copilot-backend-deploy.ps1`](spotfire-copilot-backend-deploy.ps1) | Windows | PowerShell 5.1+ |

Both scripts are functionally equivalent: same prompts, same defaults, same
generated files. Choose the one that matches your operating system.

**Platform-specific deployment scripts** (sourced automatically for cloud deployments):

| Script | Platform | Purpose |
| --- | --- | --- |
| `spotfire-copilot-backend-deploy-ecs.sh` | AWS ECS/Fargate | Phase 3-4: AWS-specific config + deployment |
| `spotfire-copilot-backend-deploy-ecs.ps1` | AWS ECS/Fargate | Phase 3-4: AWS-specific config + deployment (PowerShell) |
| `spotfire-copilot-backend-deploy-aca.sh` | Azure Container Apps | Phase 3-4: Azure-specific config + deployment |
| `spotfire-copilot-backend-deploy-aca.ps1` | Azure Container Apps | Phase 3-4: Azure-specific config + deployment (PowerShell) |

> **Note:** Platform scripts handle Phase 3-4 only (AWS ECS/Azure-specific questions and deployment). 
> All Phase 1-2 variables (credentials, database, LLM provider, optional components) are collected by 
> the main script and passed to platform scripts via environment export. You normally run only the main 
> script (`spotfire-copilot-backend-deploy.sh` or `.ps1`) — platform scripts are sourced automatically 
> when needed.

> **Generation vs. Deployment:**
> - **Docker Compose**: Script generates `docker-compose.yml` + env files; you run `docker compose up -d`.
> - **AWS ECS / Azure ACA**: Script can deploy directly (if CLI is available) or generate deployment scripts for later use.
> - For full background, see the
> [Backend Setup Installation Guide](../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md).

---

## Table of Contents

- [1. What the scripts do](#1-what-the-scripts-do)
- [2. Prerequisites](#2-prerequisites)
- [3. Quick start](#3-quick-start)
- [4. Operating modes](#4-operating-modes)
- [5. Command-line options](#5-command-line-options)
- [6. Output directory layout](#6-output-directory-layout)
- [7. Interactive walkthrough](#7-interactive-walkthrough)
  - [7.1 Deployment target](#71-deployment-target)
  - [7.2 Core setup](#72-core-setup)
  - [7.3 Credentials](#73-credentials)
  - [7.4 Backend database (PostgreSQL)](#74-backend-database-postgresql)
  - [7.5 LLM provider](#75-llm-provider)
  - [7.6 Optional Admin Console](#76-optional-admin-console)
  - [7.7 Optional RAG / Knowledge Base and Data Loader](#77-optional-rag--knowledge-base-and-data-loader)
  - [7.8 Optional Agent Registry](#78-optional-agent-registry)
  - [7.9 Optional DeepAgents OSS](#79-optional-deepagents-oss)
- [8. Generated files](#8-generated-files)
- [9. Deploying the generated configuration](#9-deploying-the-generated-configuration)
- [10. Upgrading](#10-upgrading)
- [11. Adding Agent Registry to an existing install](#11-adding-agent-registry-to-an-existing-install)
- [12. Security notes](#12-security-notes)
- [13. Troubleshooting](#13-troubleshooting)

---

## 1. What the scripts do

The generator interviews you about a Spotfire Copilot backend deployment and
writes ready-to-use configuration. For cloud deployments (AWS ECS, Azure Container Apps), 
it can also execute the deployment directly. Depending on your answers it can:

- Select the deployment target: **Docker Compose** (single-host), **AWS ECS/Fargate**, 
  or **Azure Container Apps**.
- Pin approved container image tags for the Orchestrator, Admin Console, Data
  Loader, and Agent Registry.
- Wire up **credentials** by running the official `generate_credentials.py`, or by
  reusing an existing `copilot-generated-values.txt`.
- Configure the **PostgreSQL** backend (existing/managed, or a Compose-managed
  local database) including SSL mode.
- Select the **LLM provider** and models.
- Optionally enable **Admin Console**, **RAG / Knowledge Base** (embeddings +
  vector DB), **Data Loader**, and **Agent Registry**.
- Optionally chain the **DeepAgents OSS** generator for the agent server.
- Generate a `docker-compose.yml` (single-host Docker Compose) and validate it with
  `docker compose config`.
- **For AWS ECS / Azure Container Apps**: Optionally deploy immediately using local 
  CLI, or generate deployment scripts for AWS CloudShell / Azure CloudShell.

The default backend image tag is `2.3.4` (override with `--image-tag` /
`-ImageTag` or the `DEFAULT_IMAGE_TAG` environment variable).

---

## 2. Prerequisites

**Common**

- Approved Spotfire Copilot image tags (from Spotfire Support or your platform team).
- Network access to the registry `copilotoci.azurecr.io`.
- Credentials for the LLM provider you intend to use.
- The official `generate_credentials.py` placed next to the script — **unless** you
  already have a `copilot-generated-values.txt`. The script does not create
  credentials itself; it runs the official generator.

**Linux / macOS (`spotfire-copilot-backend-deploy.sh`)**

- Bash 4 or newer, `openssl`.
- Python 3 with `bcrypt` (used by `generate_credentials.py`). The script can
  install/check prerequisites with `--install-prereqs`.
- Docker Engine + Docker Compose V2 for single-host deploys and Compose validation.
- *Optional (for immediate cloud deployment):*
  - **AWS CLI** (configured with credentials) for direct AWS ECS/Fargate deployment.
  - **Azure CLI** (authenticated) for direct Azure Container Apps deployment.

**Windows (`spotfire-copilot-backend-deploy.ps1`)**

- Windows PowerShell 5.1 or newer.
- Python 3 with `bcrypt` for credential generation.
- Docker Desktop (Compose V2) to run single-host deployments.
- *Optional (for immediate cloud deployment):*
  - **AWS CLI** (configured with credentials) for direct AWS ECS/Fargate deployment.
  - **Azure CLI** (authenticated) for direct Azure Container Apps deployment.

> **Note on cloud CLIs:** If AWS/Azure CLI is not installed, the script generates a 
> deployment script (e.g., `awscli-deploy.sh` or `azurecli-deploy.sh`) that you can 
> run later from AWS/Azure CloudShell or after installing the CLI locally.

**Credential keys** expected in `copilot-generated-values.txt`:
`SECRET_KEY`, `HASHED_ADMIN_PASSWORD`, `OAUTH2_CLIENT_ID`, `OAUTH2_CLIENT_SECRET_HASH`.

---

## 3. Quick start

**Linux / macOS**

```bash
chmod +x spotfire-copilot-backend-deploy.sh
# Ensure generate_credentials.py is in the same folder (unless you already have credentials)
./spotfire-copilot-backend-deploy.sh
```

**Windows (PowerShell)**

```powershell
.\spotfire-copilot-backend-deploy.ps1
```

Answer the prompts, review the files written under
`./spotfire-copilot/<image-tag>/backend`, then deploy.

Custom output directory:

```bash
./spotfire-copilot-backend-deploy.sh --dir /opt/spotfire-copilot/backend
```

```powershell
.\spotfire-copilot-backend-deploy.ps1 -Dir C:\opt\spotfire-copilot\backend
```

---

## 4. Operating modes

| Mode | How to invoke | Purpose |
| --- | --- | --- |
| **Interactive** (default) | run with no mode flag | Full guided generation of a backend deployment. |
| **Info** | `--info` / `-Info` | Print a summary of the currently generated environment. |
| **Upgrade** | `--upgrade` / `-Upgrade` | Update `IMAGE_TAG`, `FASTAPI_APP_VERSION`, and optionally `AGENT_CONTAINER_TAG` into a new versioned folder. |
| **Agent Registry only** | `--install-agent-registry` / `-InstallAgentRegistry` | Add/update only Agent Registry in an existing backend folder (needs `--dir`). |
| **DeepAgents chaining** | `--install-deepagents` / `-InstallDeepagents` | After core generation, run the standalone DeepAgents OSS generator. |

---

## 5. Command-line options

All options are optional; anything not supplied is asked for interactively. Bash
uses `--long-flags`; PowerShell uses `-PascalCaseParameters`. The PowerShell script
**also accepts the bash `--long-flags`** (e.g. `--upgrade --from-dir <dir>`), so a
command copied from the Linux docs works unchanged on Windows.

| Bash flag | PowerShell parameter | Description |
| --- | --- | --- |
| `--help`, `-h` | `-Help` | Show help and exit. |
| `--info` | `-Info` | Show current generated env summary. |
| `--upgrade` | `-Upgrade` | Update image tags into a new versioned folder. |
| `--image-tag TAG` | `-ImageTag TAG` | Orchestrator/Admin/Data-Loader image tag. |
| `--agent-tag TAG` | `-AgentTag TAG` | Agent Registry image tag (upgrade mode). |
| `--dir DIR` | `-Dir DIR` | Output directory. Default: `./spotfire-copilot/<image-tag>/backend`. |
| `--from-dir DIR` | `-FromDir DIR` | Source directory for upgrade mode. Defaults to last used directory. |
| `--yes`, `-y` | `-Yes` | Accept the auto-detected upgrade source without prompting (for non-interactive/CI runs). |
| `--install-prereqs` | `-InstallPrereqs` | Install/check Linux prerequisites when possible. |
| `--no-install-prereqs` | `-NoInstallPrereqs` | Do not install prerequisites; fail if Python/bcrypt are missing. |
| `--install-deepagents` | `-InstallDeepagents` | After core generation, run the standalone DeepAgents OSS generator. |
| `--deepagents-script PATH` | `-DeepagentsScript PATH` | Path to the DeepAgents installer script. |
| `--credentials-script PATH` | `-CredentialsScript PATH` | Path to `generate_credentials.py`. Default: next to this installer. |
| `--install-agent-registry` | `-InstallAgentRegistry` | Add/update only Agent Registry in an existing backend folder (use with `--dir`). |
| `--no-color` | `-NoColor` | Disable colored output. |

**Environment overrides:** `OUT_DIR`, `COPILOT_ROOT_DIR`, `DEFAULT_IMAGE_TAG`,
`DEFAULT_AGENT_TAG`, `CREDENTIALS_SCRIPT`, `PYTHON_BIN`, `NO_COLOR`.

---

## 6. Output directory layout

Installs live under a single parent folder, one subfolder per version, so multiple
versions can coexist:

```
<root>/spotfire-copilot/<image-tag>/backend/
├── .env                          # top-level compose variables (image tags, project name)
├── .env.orchestrator             # Orchestrator configuration + credentials + DB + LLM
├── .env.dataloader               # Data Loader configuration (only if enabled)
├── .env.agent-registry           # Agent Registry configuration (only if enabled)
├── docker-compose.yml            # single-host stack (Linux VM target)
├── copilot-generated-values.txt  # generated/copied credential file
└── reset-local-postgres-volume.sh  # only if a local PostgreSQL reset was selected
```

The default `<root>` is `./spotfire-copilot` (override with `COPILOT_ROOT_DIR`), and
the backend folder is finalized once the image tag is known. Existing files are
backed up with timestamped `.bak` copies before being overwritten, and files are
written with owner-only permissions where the platform allows.

Each image tag gets its own version folder, but the compose-managed PostgreSQL volume
is **shared across versions** — it uses the stable, version-independent name
`<project>_postgres_data` (the image tag is not part of the volume name). This is what
lets the database survive an upgrade: the new version folder mounts the same volume as
the previous one. A fresh reset (when selected) also writes a
`postgres_data_backup_<timestamp>.tgz` snapshot into the backend folder before deleting
the volume.

---

## 7. Interactive walkthrough

### 7.1 Deployment target

After answering all Phase 1-2 questions (credentials, database, LLM provider, optional components), the script asks:

```
Where do you want to deploy Spotfire Copilot?
  1) Docker Compose (single-host)
  2) AWS ECS / Fargate
  3) Azure Container Apps
```

**Docker Compose (single-host)**
- Generates `.env`, `.env.orchestrator`, and a `docker-compose.yml` file.
- Script exits; you run `docker compose up -d` locally.

**AWS ECS / Fargate**
- The main script hands off to the ECS-specific script (`spotfire-copilot-backend-deploy-ecs.sh`).
- Asks: "Deploy now?" — YES sources the ECS script to continue (Phase 3-4), NO provides instructions for deferred deployment.
- ECS script collects AWS-specific inputs (cluster, subnets, security group, etc.) and deploys via AWS CLI or generates a CloudShell script.

**Azure Container Apps**
- The main script hands off to the ACA-specific script (`spotfire-copilot-backend-deploy-aca.sh`).
- Asks: "Deploy now?" — YES sources the ACA script to continue (Phase 3-4), NO provides instructions for deferred deployment.
- ACA script collects Azure-specific inputs (resource group, app name, etc.) and deploys via Azure CLI or generates an Azure CloudShell script.

> **Note:** The main script is the **single entry point** for Phase 1-2 (credentials, database, LLM, components). Platform scripts (`ecs` and `aca`) handle Phase 3-4 (platform-specific inputs and deployment) only. All Phase 1-2 variables are exported so platform scripts don't duplicate questions.

### 7.2 Core setup

- **Image tag** — validated OCI tag; `FASTAPI_APP_VERSION` is set to match.
- **Compose project name** — lowercase letters, digits, `-`, `_`.
- **LOG_LEVEL** — `DEBUG`, `INFO`, `WARNING`, `ERROR`, or `CRITICAL`.
- **ACCESS_TOKEN_EXPIRE_DAYS** — positive integer (default 30).

### 7.3 Credentials

Credentials are required, but you can either reuse existing ones or have the
official generator create them.

- **Reuse** — provide the path to an existing `copilot-generated-values.txt`. The
  script also searches the working directory, the script directory, then the backend
  folder, and can fall back to values in existing `.env` files or manual entry.
- **Generate** — the script runs `generate_credentials.py` (which must be next to the
  installer) after ensuring Python/bcrypt are available.

All four values (`SECRET_KEY`, `HASHED_ADMIN_PASSWORD`, `OAUTH2_CLIENT_ID`,
`OAUTH2_CLIENT_SECRET_HASH`) must be present, or generation stops rather than writing
a broken `.env`.

### 7.4 Backend database (PostgreSQL)

PostgreSQL is required (Orchestrator stores users, OAuth clients, conversations,
threads, agents, and token data).

- **Existing / managed** — provide host, port, database name, username, password, and
  an SSL mode (`disable`, `allow`, `prefer`, `require`, `verify-ca`, `verify-full`).
- **Compose-managed local** — the script uses the `orchestrator-postgres` service and
  generates a strong password. If an existing local data volume is detected, you can
  **reuse** it (enter the original password) or perform a **fresh lab/test reset**
  (new password + a `reset-local-postgres-volume.sh` helper that deletes only the
  local PostgreSQL volume, after taking a `postgres_data_backup_<timestamp>.tgz`
  snapshot and guarded by a `DELETE` confirmation).

Database names and usernames must be valid PostgreSQL identifiers (start with a
letter/underscore; letters, digits, underscores; max 63 chars).

### 7.5 LLM provider

Select one provider (independent from the vector DB):

`Azure OpenAI`, `OpenAI`, `AWS Bedrock`, `Google Vertex AI`, `Google Gemini API`,
`NVIDIA NIM`, or `Ollama / self-hosted test`.

You are prompted for the provider's keys/endpoints and primary model, and the
correct Orchestrator/Data-Loader model plugins are written automatically.

### 7.6 Optional Admin Console

A web UI for managing OAuth clients, users, diagnostics, conversations, RAG indexes,
and agents. It reuses the same PostgreSQL database. If skipped, use the REST API
instead. See the [Admin Console Guide](../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Admin%20Console%20Guide.md).

### 7.7 Optional RAG / Knowledge Base and Data Loader

RAG powers Help, HowTo, Spotfire documentation answers, and custom document Q&A.
When enabled you choose:

- **Embeddings provider** — Azure OpenAI, OpenAI, AWS Bedrock, Vertex AI, NVIDIA NIM,
  or Ollama. Orchestrator and Data Loader must use the same embedding model per index.
- **Vector DB / Knowledge Base** — Azure AI Search, Milvus, Zilliz Cloud, Vertex AI
  Vector Search, AWS Bedrock Knowledge Bases, or a custom plugin. (Cloud/Kubernetes
  shortlists include additional options such as Qdrant, MongoDB Atlas, Redis, and
  Databricks.)
- **RAG defaults** — index name, `DEFAULT_RAG_TOPK`, `DEFAULT_RAG_SCORE_THRESHOLD`.

If the selected vector DB is writable, you can also deploy the **Data Loader** to
ingest Spotfire docs and custom PDFs. See the
[Data Loaders Installation Guide](../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Data%20Loaders%20Installation%20Guide.md).

### 7.8 Optional Agent Registry

Needed only when Copilot should call custom or bundled A2A agents. Agent Registry
requires its **own** Orchestrator OAuth client created with the `agent_developer`
scope profile — which only exists once the Orchestrator is running. In the main flow
the script therefore only **accepts** already-created credentials
(`ORCHESTRATOR_CLIENT_ID` / `ORCHESTRATOR_CLIENT_SECRET`); to create them live against
a running Orchestrator, use the dedicated flow described in
[section 11](#11-adding-agent-registry-to-an-existing-install).

### 7.9 Optional DeepAgents OSS

With `--install-deepagents` / `-InstallDeepagents`, the script runs the standalone
DeepAgents OSS generator after core generation. See the
[DeepAgents Deployment Scripts User Guide](Spotfire%20Copilot%20-%20DeepAgents%20Deployment%20Scripts%20User%20Guide.md).

---

## 8. Generated files

At the end, the script lists the files it wrote and prints a summary of your
selections (LLM provider, PostgreSQL mode, Admin Console, RAG, vector DB, embedding
provider, Data Loader, Agent Registry). See
[section 6](#6-output-directory-layout) for the full layout.

---

## 9. Deploying the generated configuration

### 9.1 Docker Compose (single-host)

After the script completes:

```bash
cd <output-dir>            # e.g. ./spotfire-copilot/2.3.4/backend
docker login copilotoci.azurecr.io
docker compose config > /tmp/copilot-compose-rendered.yml   # optional sanity check
docker compose up -d --no-build
```

### 9.2 AWS ECS / Fargate

**Option A: Immediate deployment**

After answering all questions, the main script asks "Deploy now?". If you answer YES:
- The main script sources the ECS-specific script (`spotfire-copilot-backend-deploy-ecs.sh`).
- The ECS script collects AWS inputs (cluster, subnets, security group, etc.).
- If AWS CLI is installed and configured locally, it deploys directly.
- Otherwise, it generates `awscli-deploy.sh` for AWS CloudShell.

**Option B: Deferred deployment**

If you answer NO, the script saves a template and prints instructions:

```bash
./spotfire-copilot-backend-deploy-ecs.sh --dir /path/to/backend/folder
```

For more details, see the
[Backend Setup Installation Guide](../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md).

### 9.3 Azure Container Apps

**Option A: Immediate deployment**

After answering all questions, the main script asks "Deploy now?". If you answer YES:
- The main script sources the ACA-specific script (`spotfire-copilot-backend-deploy-aca.sh`).
- The ACA script collects Azure inputs (resource group, app name, etc.).
- If Azure CLI is installed and configured locally, it deploys directly.
- Otherwise, it generates `azurecli-deploy.sh` for Azure CloudShell.

**Option B: Deferred deployment**

If you answer NO, the script saves a template and prints instructions:

```bash
./spotfire-copilot-backend-deploy-aca.sh --dir /path/to/backend/folder
```

For more details, see the
[Backend Setup Installation Guide](../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md)
and the
[Frontend Setup Guide](../Spotfire%20Copilot%20Client%20Extension/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Frontend%20Setup.md)
for the client extension.

---

## 10. Upgrading

Upgrade mode copies an existing deployment into a new versioned folder and updates
the image tags:

```bash
./spotfire-copilot-backend-deploy.sh --upgrade --image-tag 2.3.6
./spotfire-copilot-backend-deploy.sh --upgrade --image-tag 2.3.6 --from-dir /root/spotfire-copilot/2.3.4/backend
./spotfire-copilot-backend-deploy.sh --upgrade --image-tag 2.3.6 --agent-tag 1.0.0
```

```powershell
.\spotfire-copilot-backend-deploy.ps1 -Upgrade -ImageTag 2.3.6
.\spotfire-copilot-backend-deploy.ps1 -Upgrade -ImageTag 2.3.6 -AgentTag 1.0.0
```

It updates `IMAGE_TAG`, `FASTAPI_APP_VERSION`, and (when `--agent-tag` is given)
`AGENT_CONTAINER_TAG`. Then apply it with `docker compose up -d --no-build` from the
new folder.

### 10.1 Choosing the source

- **Explicit** — pass `--from-dir` / `-FromDir` to name the source backend folder. This
  is unambiguous and skips the confirmation prompt.
- **Auto-detected** — without `--from-dir`, the script uses the last recorded install
  directory, **prints the resolved source and target, and asks you to confirm** before
  copying anything. In a non-interactive/CI run it will refuse to guess: pass
  `--from-dir`, or add `--yes` / `-Yes` to accept the detected source.
- **Same tag as the source** — if the target tag resolves to the same directory as the
  source, the script skips the file copy and simply re-applies the tag values in place
  (an idempotent no-op), instead of failing.

### 10.2 Database continuity

The compose-managed PostgreSQL volume uses a stable, version-independent name
(`<project>_postgres_data`), so the upgraded stack **reuses the existing database
automatically** — no data is lost across a tag bump. For an external/managed
PostgreSQL, continuity is automatic because the upgrade copies the existing
`.env.orchestrator` (host, database, credentials) forward unchanged.

### 10.3 Backward-incompatible releases

If a release is **not backward compatible** with the existing database schema, reusing
the old data can cause startup/migration failures. In that case do a **fresh database**
instead: run the `reset-local-postgres-volume.sh` helper (compose-managed), which takes
a `postgres_data_backup_<timestamp>.tgz` snapshot before deleting the volume, or point
the new version at a **new external database** while leaving the old one intact for
rollback. Your previous version folder is untouched, so you can always bring the prior
stack back up against its original data.

---

## 11. Adding Agent Registry to an existing install

Because Agent Registry needs an Orchestrator OAuth client with the `agent_developer`
scope profile, create it against a **running** Orchestrator using the dedicated flow:

```bash
./spotfire-copilot-backend-deploy.sh --install-agent-registry --dir <backend-folder>
```

```powershell
.\spotfire-copilot-backend-deploy.ps1 -InstallAgentRegistry -Dir <backend-folder>
```

This adds/updates only the Agent Registry configuration (`.env.agent-registry` and the
compose service) in the specified backend folder without touching the rest of the
deployment.

---

## 12. Security notes

- Generated `.env*` files, `copilot-generated-values.txt`, and backups contain
  secrets. They are written with owner-only permissions where the platform allows;
  keep them out of source control.
- The script does not generate credentials itself — it relies on the official
  `generate_credentials.py`. Do not fabricate `SECRET_KEY` or bcrypt hashes.
- Use a distinct OAuth client with the `agent_developer` scope for Agent Registry;
  do not reuse the frontend/client OAuth credentials.
- For managed/cloud PostgreSQL, prefer `require` or stricter SSL modes.
- The local PostgreSQL reset deletes only the local Compose volume (after writing a
  `postgres_data_backup_<timestamp>.tgz` snapshot) and requires an explicit `DELETE`
  confirmation. Use it only for disposable lab/test data.
- Rotate credentials and provider keys per your organization's policy.

---

## 13. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `Missing required credential values` | Provide a complete `copilot-generated-values.txt`, or place `generate_credentials.py` next to the installer and answer "No" at the credentials question. |
| `Required command not found: python` (or bcrypt errors) | Install Python 3 + `bcrypt`, or pass `--install-prereqs`. Set `PYTHON_BIN` to select a specific interpreter. |
| `Invalid PostgreSQL name` | Database/username must start with a letter/underscore, then letters/digits/underscores (max 63). Avoid entering a menu number here. |
| `Existing local PostgreSQL volume detected` | Reuse it with the original password, or choose the fresh reset option (which creates `reset-local-postgres-volume.sh`). |
| `Non-interactive run cannot auto-confirm the detected source` | An upgrade without `--from-dir` was run without a terminal. Pass `--from-dir <dir>` to name the source explicitly, or add `--yes` / `-Yes` to accept the auto-detected source. |
| `cp: ... are the same file` on upgrade | Upgrading to the same tag as the source now skips the copy and re-applies tags in place. Ensure you are on the current script version. |
| `docker-compose.yml is missing orchestrator-postgres` | You chose `POSTGRES_MODE=compose` but the compose file lacks the service; let the script regenerate it. |
| `Invalid image tag` | Use an approved OCI tag: letters, digits, `.`, `_`, `-` (max 128), starting with an alphanumeric or underscore. |
| Agent Registry deferred / not configured | Its OAuth client didn't exist yet. Start the Orchestrator, then run `--install-agent-registry --dir <backend>`. |
| PowerShell "running scripts is disabled" | Launch with `powershell -ExecutionPolicy Bypass -File .\.spotfire-copilot-backend-deploy.ps1`, or set an appropriate execution policy. |

---

**Related documentation:**
[Backend Setup Installation Guide](../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Backend%20Setup.md) ·
[Admin Console Guide](../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Admin%20Console%20Guide.md) ·
[Data Loaders Installation Guide](../Spotfire%20Copilot%20Backend%20Services/Spotfire%20Copilot%20-%20Data%20Loaders%20Installation%20Guide.md) ·
[Frontend Setup Guide](../Spotfire%20Copilot%20Client%20Extension/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Frontend%20Setup.md) ·
[DeepAgents Deployment Scripts User Guide](Spotfire%20Copilot%20-%20DeepAgents%20Deployment%20Scripts%20User%20Guide.md)
