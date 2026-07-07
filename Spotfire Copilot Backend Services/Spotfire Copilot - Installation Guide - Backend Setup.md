# Spotfire Copilot™ Installation Guide — Backend Setup

> **Versions covered:** 2.3.0, 2.3.1, 2.3.2, 2.3.4, and 2.3.5 &nbsp;|&nbsp; **Last updated:** 29 June 2026 &nbsp;|&nbsp; **Applies to:** Orchestrator Service
>
> This guide covers backend versions **2.3.0**, **2.3.1**, **2.3.2**, **2.3.4**, and **2.3.5**. New configuration introduced in 2.3.1, 2.3.2, and 2.3.4 is called out inline and summarised in **[Appendix D](#appendix-d--release-notes) — Release notes** at the end of this guide. **2.3.5 is a security release for the Admin Console** — see **[Appendix D](#appendix-d--release-notes) — Release notes → What's new in 2.3.5**.

## Table of Contents

- [Current Latest Versions](#current-latest-versions)
- [1. Introduction](#1-introduction)
  - [1.1 What You Are Deploying](#11-what-you-are-deploying)
  - [1.2 Architecture Overview](#12-architecture-overview)
  - [1.3 Prerequisites](#13-prerequisites)
  - [1.4 Recommended Personnel](#14-recommended-personnel)
- [2. Choose Your Deployment Path](#2-choose-your-deployment-path)
- [3. Step 1 — Generate Credentials](#3-step-1--generate-credentials)
  - [Install the generator dependency](#install-the-generator-dependency)
  - [Generate all credentials](#generate-all-credentials)
  - [Other generator options](#other-generator-options)
  - [Create your environment configuration](#create-your-environment-configuration)
  - [If `generate_credentials.py` cannot run in your environment](#if-generate_credentialspy-cannot-run-in-your-environment)
- [4. Step 2 — Choose and Configure Your LLM Provider](#4-step-2--choose-and-configure-your-llm-provider)
  - [OpenAI](#openai)
- [5. Step 3 — Configure Your Knowledge Base](#5-step-3--configure-your-knowledge-base)
  - [Configuration Examples](#configuration-examples)
  - [Embeddings Plugin](#embeddings-plugin)
  - [Knowledge Base Tuning](#knowledge-base-tuning)
- [6. Step 4 — Deploy](#6-step-4--deploy)
  - [6.1 Pulling the Docker Images](#61-pulling-the-docker-images)
  - [Managing Environment Variables in the Cloud](#managing-environment-variables-in-the-cloud)
  - [6.2 Azure Container Apps](#62-azure-container-apps)
  - [6.3 GCP Cloud Run](#63-gcp-cloud-run)
  - [6.4 AWS (ECS / Fargate)](#64-aws-ecs--fargate)
  - [6.5 Kubernetes](#65-kubernetes)
  - [6.6 Using Your Own PostgreSQL Server (No Docker)](#66-using-your-own-postgresql-server-no-docker)
- [7. Step 5 — Verify and First Login](#7-step-5--verify-and-first-login)
  - [Health check endpoints](#health-check-endpoints)
  - [First admin login](#first-admin-login)
  - [API documentation](#api-documentation)
- [8. Step 6 — Post-Deployment Setup](#8-step-6--post-deployment-setup)
  - [Create OAuth2 clients for your applications](#create-oauth2-clients-for-your-applications)
  - [Create additional users](#create-additional-users)
  - [Load knowledge base documents](#load-knowledge-base-documents)
  - [Configure conversation summarization](#configure-conversation-summarization)
- [9. Authentication Guide](#9-authentication-guide)
  - [9.1 Using the Swagger UI (Browser)](#91-using-the-swagger-ui-browser)
  - [9.2 Using the REST API (Programmatic)](#92-using-the-rest-api-programmatic)
  - [9.3 Troubleshooting](#93-troubleshooting)
  - [General REST guidelines](#general-rest-guidelines)
- [10. Knowledge Base & RAG Configuration](#10-knowledge-base--rag-configuration)
  - [How knowledge base retrieval works](#how-knowledge-base-retrieval-works)
  - [Direct RAG query endpoint](#direct-rag-query-endpoint)
  - [Knowledge base index enrichment](#knowledge-base-index-enrichment)
  - [Static knowledge base index metadata](#static-knowledge-base-index-metadata)
- [11. Environment Variable Reference](#11-environment-variable-reference)
  - [Required variables (service will not start without these)](#required-variables-service-will-not-start-without-these)
  - [Authentication variables](#authentication-variables)
  - [Plugin variables](#plugin-variables)
  - [LLM provider credentials](#llm-provider-credentials)
  - [Vector database credentials](#vector-database-credentials)
  - [Model category overrides](#model-category-overrides)
  - [Application variables](#application-variables)
  - [Database variables](#database-variables)
  - [Knowledge base / RAG variables](#knowledge-base--rag-variables)
  - [Summarization variables](#summarization-variables)
  - [LangSmith tracing (optional)](#langsmith-tracing-optional)
  - [Conversation retention (2.3.1)](#conversation-retention-231)
  - [WebSocket tunnel — developer agent containers (2.3.1)](#websocket-tunnel--developer-agent-containers-231)
- [12. Troubleshooting](#12-troubleshooting)
  - [Authentication errors](#authentication-errors)
  - [RAG endpoint access issues](#rag-endpoint-access-issues)
  - [Container startup issues](#container-startup-issues)
  - [Database issues](#database-issues)
  - [LLM provider issues](#llm-provider-issues)
  - [Useful diagnostic commands](#useful-diagnostic-commands)
- [13. Upgrading from Previous Versions](#13-upgrading-from-previous-versions)
  - [Migrating from the single-container architecture](#migrating-from-the-single-container-architecture)
- [14. Security Best Practices](#14-security-best-practices)
  - [Credential management](#credential-management)
  - [Container security](#container-security)
  - [Network security](#network-security)
  - [Authentication security](#authentication-security)
  - [Monitoring](#monitoring)
- [Appendix A — Other LLM Provider Configurations](#appendix-a--other-llm-provider-configurations)
  - [Azure OpenAI](#azure-openai)
  - [Google Gemini (API Key — Simplest Google Option)](#google-gemini-api-key--simplest-google-option)
  - [Google Vertex AI (GCP Service Account — Recommended for GCP)](#google-vertex-ai-gcp-service-account--recommended-for-gcp)
  - [AWS Bedrock](#aws-bedrock)
  - [Anthropic Claude](#anthropic-claude)
  - [Mistral AI](#mistral-ai)
  - [Ollama (Local / Self-Hosted)](#ollama-local--self-hosted)
  - [Cohere](#cohere)
  - [NVIDIA NIM](#nvidia-nim)
- [Appendix B — Other Knowledge Base Configurations](#appendix-b--other-knowledge-base-configurations)
- [Appendix C — Self-hosted pgvector setup](#appendix-c--self-hosted-pgvector-setup)
  - [Prerequisites](#prerequisites-2)
  - [Install the pgvector extension](#install-the-pgvector-extension)
  - [Create the vector database](#create-the-vector-database)
  - [Verify the extension](#verify-the-extension)
  - [Configure the orchestrator](#configure-the-orchestrator)
  - [Performance tuning](#performance-tuning)
  - [Sizing reference](#sizing-reference)
- [Appendix D — Release notes](#appendix-d--release-notes)
  - [What's new in 2.3.5](#whats-new-in-235)
  - [What's new in 2.3.4](#whats-new-in-234)
  - [What's new in 2.3.2](#whats-new-in-232)
  - [What's new in 2.3.1](#whats-new-in-231)

---

## Current Latest Versions

> ⚠️ **New installations should deploy the latest version of every component.** Newer releases contain security and bug fixes. Existing deployments do not always need to upgrade — see the per-component notes below. For changelogs and upgrade details between specific versions, refer to each component's linked article.

| Component | Latest Version | Notes |
|-----------|---------------|-------|
| **Orchestrator (backend)** | **2.3.5** | Drop-in replacement for 2.3.0–2.3.4 (no breaking changes, no required migrations). **Security release — operators running the Admin Console are strongly recommended to upgrade to 2.3.5.** See **[Appendix D](#appendix-d--release-notes) — Release notes → What's new in 2.3.5**. Still **required for GPT-5.x or o-series (`o1` / `o3` / `o4`) Azure OpenAI deployments** — set `OPENAI_GPT5_COMPATIBLE=true` (introduced in 2.3.4) in addition to upgrading the image. Existing deployments on GPT-4o, Claude, Bedrock, Gemini, Vertex AI, Mistral, Ollama, Cohere, Hugging Face, or NVIDIA NIM continue to be supported. See **[§11](#11-environment-variable-reference) Environment Variable Reference → GPT-5+ / o-series deployment flag** and **[Appendix D](#appendix-d--release-notes) — Release notes**. |
| [**Data loaders**](Spotfire%20Copilot%20-%20Data%20Loaders%20Installation%20Guide.md) | **2.3.4** | Existing deployments on 2.3.2 or later do not need to upgrade. |
| [**Spotfire client packages**](../Spotfire%20Copilot%20Client%20Extension/Spotfire%20Copilot%20-%20Installation%20Guide%20-%20Frontend%20Setup.md) | **2.3.4** | Compatible with the 2.3.0, 2.3.1, 2.3.2, and 2.3.4 backends. |
| [**Agent Registry — Domain Agents Container**](../Spotfire%20Copilot%20Agent%20Registry%20-%20Domain%20Agents/Spotfire%20Copilot%20-%20Agent%20Registry%20Installation%20Guide.md) | **1.1.0** | *Optional.* Industry-vertical agents (e.g. Well Recompletions) plus the [Agent Registry Toolkit](../Spotfire%20Copilot%20Agent%20Registry%20Toolkit/Spotfire%20Copilot%20-%20Agent%20Registry%20Toolkit%20User%20Guide.md) for building your own. See the [Agent Registry overview](https://community.spotfire.com/articles/spotfire/agent-registry-for-spotfire/). |
| [**Agent Registry — Platform Integrations Container**](https://community.spotfire.com/articles/spotfire/langgraph-deepagents-server-licensed-deployment-guide/) | **1.0.0** | *Optional.* Ecosystem integration agents (Databricks, Snowflake, OSDU, and more). Deployed via the LangGraph DeepAgents Server — [Licensed](https://community.spotfire.com/articles/spotfire/langgraph-deepagents-server-licensed-deployment-guide/) or [OSS](https://community.spotfire.com/articles/spotfire/langgraph-deepagents-server-oss-deployment-guide/). See the [Agent Registry overview](https://community.spotfire.com/articles/spotfire/agent-registry-for-spotfire/). |

> ## 🔑 Before you start: registry access is required
>
> All Spotfire Copilot container images are distributed through a credentialed OCI registry at **`copilotoci.azurecr.io/spotfirecopilot/`**. You will not be able to pull any image — and therefore not be able to deploy on any platform in this guide — until you have obtained credentials.
>
> **To request access**, open a Support Portal case at [support.tibco.com](https://support.tibco.com/) and select **Spotfire Enterprise** as the Product. Then follow the [OCI Registry Access Guide](https://community.spotfire.com/articles/spotfire/oci-registry-access-guide/) to authenticate Docker, Kubernetes, or your cloud platform against the registry.
>
> The legacy public ECR location `public.ecr.aws/tds/` is available for **2.3.0 only** and is not recommended for new deployments.

---

## 1. Introduction

### 1.1 What You Are Deploying

The Spotfire Copilot™ backend is a production-ready AI orchestration platform that connects Spotfire to Large Language Models (LLMs) and Vector Databases. It provides:

- **LLM orchestration** — route requests to any supported LLM provider (OpenAI, Azure, AWS, Google, Anthropic, Mistral, and more)
- **Conversation management** — persistent, thread-based conversation history with branching support
- **Knowledge Base (RAG)** — connect to vector databases (knowledge bases) to ground LLM responses in your documents. **Required** for Spotfire Copilot's built-in Help and HowTo features
- **Admin console** *(optional but recommended)* — a web-based operations dashboard for user management, conversation analytics, and system configuration
- **Authentication** — OAuth2 machine-to-machine credentials, JWT tokens, and role-based access control
- **Agent routing** — optional A2A (Agent-to-Agent) protocol support for invoking remote AI agents

> **Knowledge Bases are required.** Spotfire Copilot's Help and HowTo functionality depends
> on a connected knowledge base (vector database) to retrieve relevant documentation
> and provide context-aware assistance. Without a knowledge base, these features will
> not work.

> **The Admin Console is optional but highly recommended.** The orchestrator is fully
> functional on its own — Spotfire clients can connect, authenticate, and use all LLM and
> knowledge base features without it. However, the admin console provides substantial
> operational value that is difficult to replicate by other means:
>
> - **User & OAuth2 client management** — create and manage users, roles, and M2M API
>   credentials through a visual interface (otherwise you must use the REST API directly)
> - **Conversation monitoring** — browse, search, and inspect all conversations, threads,
>   and messages across all users, including the full LLM context sent for each request
> - **Knowledge base management** — view vector database collections, inspect document
>   sources, rename collections, and trigger manual index enrichment
> - **Security audit log** — track failed logins, account lockouts, and password resets
> - **Agent management** — register, test, and manage AI agents
> - **System diagnostics** — dashboard statistics, container logs, debug thread states,
>   and on-demand summarization
>
> For production deployments, we strongly recommend deploying the admin console. For
> quick proof-of-concept or development work, you can skip it and manage the system
> entirely via the orchestrator's REST API.

### 1.2 Architecture Overview

The backend is **two services from one Docker image**, sharing one PostgreSQL database. The admin console is optional but recommended. Everything else in this guide is configuration for these two services.

#### Service reference card

| | **Orchestrator** | **Admin Console** *(optional, recommended)* |
|---|---|---|
| **Purpose** | LLM inference, conversation persistence, RAG retrieval, OAuth2 token issuance, agent routing | Web UI for user / OAuth2-client management, conversation monitoring, knowledge-base inspection, system diagnostics |
| **Required?** | **Yes** — Spotfire clients depend on it | No — orchestrator is fully usable on its own via the REST API |
| **Image** | `copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4` | Same image |
| **Startup command** | *(default — no override)* | `python /app/admin_console/admin_main.py` |
| **Container port** | `8080` | `8081` |
| **Health check** | `GET /` → `200` *(note: there is no `/health` path)* | `GET /health` → `200` *(note: `/` returns `302 → /login`)* |
| **Talks to (direct connections)** | PostgreSQL · LLM provider · vector database (knowledge base) | PostgreSQL (reads users / threads / agents directly) · Orchestrator (only for thread-title generation) |
| **Required env vars** | `SECRET_KEY`, `DATABASE_URL`, `SYNC_DATABASE_URL`, `HASHED_ADMIN_PASSWORD`, `MODEL_PLUGIN_ENTRY_POINT`, `SECONDARY_MODEL_PLUGIN_ENTRY_POINT`, `EMBEDDINGS_PLUGIN_ENTRY_POINT`, `RETRIEVER_PLUGIN_ENTRY_POINT`, an LLM provider key, vector-DB credentials | `SECRET_KEY`, `DATABASE_URL`, `SYNC_DATABASE_URL`, `HASHED_ADMIN_PASSWORD`, `ORCHESTRATOR_INTERNAL_URL` *(LLM and vector-DB credentials are **not** needed)* |

> **Key implication for cloud deployments:** the admin-console container needs **direct network access to PostgreSQL** with the same `DATABASE_URL` / `SYNC_DATABASE_URL` the orchestrator uses. It is **not** a thin UI in front of the orchestrator's REST API — it reads users, threads, agents, OAuth2 clients, and feedback from PostgreSQL itself via SQLAlchemy.

**PostgreSQL** (third container, on-premise only): `postgres:15-alpine` on port `5432`. Cloud deployments use a managed PostgreSQL service (Azure Database for PostgreSQL, GCP Cloud SQL, or Amazon RDS) instead.

> **2.3.0 users:** substitute `public.ecr.aws/tds/llm-orchestrator` (no authentication required) for the orchestrator/admin-console image. See **[§6.1](#61-pulling-the-docker-images) Pulling the Docker Images** for the full version-by-version pull procedure.

```mermaid
block-beta
  columns 5

  %% ── Row 1: Client → Orchestrator → LLM ────────────────────────
  Client["Spotfire Client\nREST API · Bearer Token"]:1
  space:1
  Orch["Orchestrator\n:8080"]:1
  space:1
  LLM["LLM Provider\nOpenAI · Azure · Bedrock\nVertex AI · Anthropic\nMistral · Ollama"]:1

  %% ── Row 2: PostgreSQL (offset left so it doesn't sit between Console and Orchestrator) → Vector DB ─
  space:1
  PG[("PostgreSQL\n:5432")]:1
  space:2
  Vec["Knowledge Base\nZilliz · Milvus · Qdrant\nMongoDB · Redis\nAzure Search"]:1

  %% ── Row 3: Admin → Console → LangSmith ────────────────────────
  Admin["Admin User\nBrowser · Session Auth"]:1
  space:1
  Console["Admin Console\n:8081 (optional)"]:1
  space:1
  LS["LangSmith\n(optional tracing)"]:1

  %% ── Connections ────────────────────────────────────────────────
  Client --> Orch
  Admin --> Console
  Orch --> PG
  Console --> PG
  Console --> Orch
  Orch --> LLM
  Orch --> Vec
  Orch -.-> LS

  %% ── Styles ─────────────────────────────────────────────────────
  style Client fill:#fff,stroke:#5f6368,color:#000
  style Admin fill:#fff,stroke:#5f6368,color:#000
  style Orch fill:#e8f0fe,stroke:#1a73e8,color:#000
  style Console fill:#fce8e6,stroke:#d93025,color:#000
  style PG fill:#e6f4ea,stroke:#1e8e3e,color:#000
  style LLM fill:#fef7e0,stroke:#f9ab00,color:#000
  style Vec fill:#fef7e0,stroke:#f9ab00,color:#000
  style LS fill:#fef7e0,stroke:#f9ab00,color:#000
```

Both services share the **same PostgreSQL database** and use `SECRET_KEY` for:
- JWT token signing and verification
- `X-Internal-API-Key` header for service-to-service authentication between the admin console and orchestrator

The canonical health-check paths and per-platform probe configuration are in **[§7](#7-step-5--verify-and-first-login) Verify and First Login → Health check endpoints**. Image pulling (registry, authentication, mirroring) is covered in **[§6.1](#61-pulling-the-docker-images) Pulling the Docker Images**.

### 1.3 Prerequisites

Before you begin, ensure you have:

| Requirement | Details |
|---|---|
| **Cloud platform account** | An active account on Azure, GCP, or AWS. Most deployments target one of these cloud providers. |
| **Cloud CLI tools** | `az` CLI for Azure, `gcloud` CLI for GCP, `aws` CLI for AWS. Required for deploying and managing services. |
| **Docker** *(on-premise only)* | Docker Engine 20.10+ with Docker Compose V2. Only needed if self-hosting. |
| **Python 3.11+** | Needed **only** on the machine where you generate credentials (Step 1). Not required on the deployment target. |
| **LLM provider access** | An API key or service account for at least one provider (see **[§4](#4-step-2--choose-and-configure-your-llm-provider) Choose and Configure Your LLM Provider**). |
| **Knowledge base (vector database)** | **Required** for Spotfire Copilot Help and HowTo features. Can be a cloud-managed service (Zilliz Cloud, MongoDB Atlas, Azure Cognitive Search, AWS Bedrock Knowledge Bases) or self-hosted (Milvus, Qdrant, Redis). |
| **Managed PostgreSQL** *(cloud only)* | Azure Database for PostgreSQL, Cloud SQL (GCP), or Amazon RDS. Not needed for on-premise (included as a container). |

### 1.4 Recommended Personnel

We recommend the following role from your organization:

**IT / Analytics Engineer** who is:
- Experienced with at least one cloud platform (Azure, AWS, or GCP)
- Familiar with deploying containerized applications to cloud services (Container Apps, Cloud Run, ECS, or Kubernetes)
- Comfortable managing environment variables, secrets, and networking in cloud environments
- Able to manage API keys and credentials securely (e.g., via Key Vault, Secrets Manager, or Kubernetes Secrets)
- Familiar with Docker and Docker Compose (if deploying on-premise)

---

## 2. Choose Your Deployment Path

You will run **two containers** (orchestrator + admin console) plus a **PostgreSQL database**. The decision is *where* you run them:

- **Cloud Managed Service** *(recommended)* — Azure Container Apps, GCP Cloud Run, AWS ECS / Fargate, or Kubernetes (AKS / GKE / EKS). PostgreSQL is a managed service (Azure Database for PostgreSQL, Cloud SQL, RDS); secrets live in the platform's secret store (Key Vault, Secrets Manager, GCP Secret Manager); the platform handles TLS termination and auto-scaling.
- **On-Premise / Self-Hosted** — Docker Compose on your own servers. PostgreSQL runs as a container; secrets live in `.env`; you manage TLS and any reverse proxy.

Either path follows **[§3](#3-step-1--generate-credentials)–[§5](#5-step-3--configure-your-knowledge-base)** to configure, then **[§6](#6-step-4--deploy) Deploy** for the platform-specific recipe:

> - **Cloud (most customers):** Deploy via Azure, GCP, or AWS console/CLI/IaC — see
>   [Section 6.2](#62-azure-container-apps)–6.5 for platform-specific instructions
> - **Kubernetes:** Deploy via Helm or raw manifests — see [Section 6.5](#65-kubernetes)
> - **On-Premise:** `docker compose up` — see **[§6.1](#61-pulling-the-docker-images) Pulling the Docker Images** to authenticate against the registry, then follow **[§6.6](#66-using-your-own-postgresql-server-no-docker)** if you want to point the orchestrator at an external PostgreSQL server instead of the bundled container.

## 3. Step 1 — Generate Credentials

> **Applies to:** All deployments (on-premise and cloud).

> **Get the Backend Server Resources first.** The `generate_credentials.py` script, along with `.env.example` and `docker-compose.yml`, ships in the **Spotfire Copilot™ client download package** on the Spotfire Community file portal: [Spotfire Copilot™ downloads](https://community.spotfire.com/files/file/190-spotfire-copilot%E2%84%A2/). After downloading, open the **Backend Server Resources** folder — it contains all three files. Extract that folder to a working directory on the machine where you will run the credential generator and (for on-premise) `docker compose`. The commands below assume you are working inside that extracted **Backend Server Resources** folder.

The orchestrator requires **hashed credentials** — no plaintext passwords are ever stored in configuration files. Run the credential generator **once** before your first deployment.

### Install the generator dependency

```bash
# Only bcrypt is required — install it in any Python 3.11+ environment
pip install bcrypt
```

### Generate all credentials

```bash
# Run from inside the extracted Backend Server Resources folder

# Generate everything: admin password + OAuth2 client + SECRET_KEY
python generate_credentials.py
```

This outputs:
1. **`SECRET_KEY`** — a 64-character hex string for JWT signing
2. **Admin password** — a random 24-character password + its bcrypt hash
3. **OAuth2 client credentials** — a `client_id` and `client_secret` + the secret's bcrypt hash

> **Save the plaintext passwords immediately** — they are shown only once. The bcrypt
> hashes go into your environment configuration (`.env` file for on-premise, or your
> cloud platform's secrets store); the plaintext values are what you use to log in.

### Other generator options

```bash
# Rotate only the admin password
python generate_credentials.py --admin-only

# Use a specific password instead of a random one
python generate_credentials.py --password "MyP@ssw0rd!"

# Generate only a new SECRET_KEY
python generate_credentials.py --secret-key-only

# Generate only new OAuth2 client credentials
python generate_credentials.py --oauth2-only
```

### Create your environment configuration

For **on-premise (Docker Compose)** deployments:

```bash
cp .env.example .env
```

Paste the generated values into `.env`:

```bash
# Core (REQUIRED)
SECRET_KEY=<paste the hex string from generate_credentials.py>
POSTGRES_PASSWORD=<choose a database password>

# Admin bootstrap (REQUIRED for first deploy)
# ⚠️ MUST be wrapped in single quotes — double quotes or no quotes
#    will break the $ characters in the bcrypt hash.
HASHED_ADMIN_PASSWORD='$2b$12$...paste-your-bcrypt-hash...'

# OAuth2 client (optional — auto-generated if omitted)
# OAUTH2_CLIENT_ID=<paste client_id>
# OAUTH2_CLIENT_SECRET_HASH='$2b$12$...paste-secret-hash...'
```

> **Common mistake:** Using double quotes around bcrypt hashes. Docker Compose
> interprets `$` as variable references inside double quotes, which corrupts the hash.
> Always use **single quotes**: `HASHED_ADMIN_PASSWORD='$2b$12$...'`

For **cloud deployments**, these values go into your platform's secrets/environment variable
configuration instead of a `.env` file. See **Managing Environment Variables in the Cloud**
in [§6](#6-step-4--deploy) for platform-specific instructions.

### If `generate_credentials.py` cannot run in your environment

Some customers cannot run the bundled `generate_credentials.py` script — typically because corporate security tooling blocks `pip install` of `bcrypt`, blocks ad-hoc Python execution, or requires that all secrets be produced by an approved cryptographic tool. You do **not** have to use `generate_credentials.py`. The orchestrator only cares about the *format* of the values you put in `.env` (or your cloud secret store) — not which tool produced them. Use any FIPS-validated or otherwise-approved tool inside your environment to produce values that match the spec below.

**What each required value must look like:**

| Variable | Format | What to generate |
|---|---|---|
| `SECRET_KEY` | 64-character lowercase hex string (256 bits of entropy) | Any cryptographically-secure random source — `openssl rand -hex 32`, `head -c 32 /dev/urandom \| xxd -p -c 64`, Windows `[Convert]::ToHexString((1..32 \| %{ Get-Random -Min 0 -Max 256 }))` (PowerShell), or your enterprise key-management system. |
| `POSTGRES_PASSWORD` | Any strong password (your choice) | This is the database password the bundled PostgreSQL container will be initialized with (or that you set on your external server). It is **not** hashed and not used by the orchestrator code path — Docker Compose / your DB tooling consumes it directly. Generate via your password manager. |
| `HASHED_ADMIN_PASSWORD` | A **bcrypt** hash of the admin password you choose. Must start with `$2b$`, `$2a$`, or `$2y$` and be 60 characters long. Cost factor **10 or higher** (12 recommended — matches what the bundled generator uses). | Pick any strong plaintext admin password and hash it with any bcrypt-compatible tool. See recipes below. Save the plaintext securely (in a vault); only the hash goes in `.env`. |
| `OAUTH2_CLIENT_ID` | A random URL-safe string, ~22 characters from `[A-Za-z0-9-_]` | Any random-string generator: `openssl rand -base64 18 \| tr '+/' '-_' \| tr -d '='`, your secrets manager, or your password manager's "API key" generator. |
| `OAUTH2_CLIENT_SECRET_HASH` | A **bcrypt** hash of the OAuth2 client secret you choose. Same `$2b$` / `$2a$` / `$2y$` / 60-char / cost ≥ 10 rules as `HASHED_ADMIN_PASSWORD`. | Generate a strong plaintext secret (43+ random characters is what the bundled generator produces) and hash it with bcrypt. Save the plaintext securely — your Spotfire client deployments will use it. |

**Approved-tool bcrypt recipes (any one of these works):**

```bash
# ── Recipe 1: Apache htpasswd (often pre-installed on Linux build hosts) ──
#   Produces a $2y$ hash. The orchestrator accepts $2y$ just like $2b$.
#   The "admin" username placeholder is discarded — only the hash matters.
htpasswd -nbBC 12 admin 'YourStrongAdminPassword' | cut -d: -f2

# ── Recipe 2: One-shot Docker container (no host pip install required) ──
#   Useful if Python+bcrypt cannot be installed locally but Docker is approved.
docker run --rm httpd:alpine \
  htpasswd -nbBC 12 admin 'YourStrongAdminPassword' | cut -d: -f2

# ── Recipe 3: Existing Python environment with bcrypt approved ────────────
python -c "import bcrypt; print(bcrypt.hashpw(b'YourStrongAdminPassword', bcrypt.gensalt(rounds=12)).decode())"
```

Repeat any of these recipes with the OAuth2 client secret as the input to produce `OAUTH2_CLIENT_SECRET_HASH`.

> **Validation tip:** The orchestrator logs a clear error on startup if `HASHED_ADMIN_PASSWORD` or `OAUTH2_CLIENT_SECRET_HASH` does not start with a valid bcrypt prefix. If you see that error, your hash was produced by something other than bcrypt (e.g. SHA-256, Argon2, scrypt) and will not work — use one of the recipes above.

> **Do not use online bcrypt generators** for production credentials. Any web form that asks you to type your admin password is exfiltrating it. All of the recipes above run locally.

---

## 4. Step 2 — Choose and Configure Your LLM Provider

> **Applies to:** All deployments.

The orchestrator uses a **plugin system** for LLM providers. For each provider, you must configure two things that **must match**:

| Setting | Purpose |
|---|---|
| `MODEL_PLUGIN_ENTRY_POINT` | Python class that communicates with the LLM |
| Provider credentials | API key, service account, or IAM role |

> **⚠️ The #1 configuration mistake** is changing the API key but not the plugin entry point
> (or vice versa). If these don't match, the service will fail with authentication errors at
> startup or on first request.

> **About `SECONDARY_MODEL_PLUGIN_ENTRY_POINT`:** This variable is **required at startup**
> (the service will crash without it), but it is not used by Spotfire clients at runtime.
> It exists for a deprecated internal feature. **Always set it to the same value as
> `MODEL_PLUGIN_ENTRY_POINT`** — there is no need to configure a different provider.

Set the environment variables for your chosen provider. For on-premise deployments, edit
your `.env` file. For cloud deployments, set these via your platform's environment variable
or secrets management system (see **Managing Environment Variables in the Cloud** in [§6](#6-step-4--deploy)).

**Supported providers:**

| Provider | Authentication | Best for |
|---|---|---|
| **OpenAI** | API key | General purpose, widest model selection |
| **Azure OpenAI** | API key + endpoint URL | Enterprise Azure environments |
| **Google Gemini** | API key | Simple setup, no GCP project needed |
| **Google Vertex AI** | GCP service account | GCP-native, GKE / Cloud Run deployments |
| **AWS Bedrock** | IAM credentials or role | AWS-native, ECS / EKS deployments |
| **Anthropic Claude** | API key | Claude models via direct API |
| **Mistral AI** | API key | Mistral models, EU data residency |
| **Ollama** | None (local) | Air-gapped or local development |
| **Cohere** | API key | Cohere language models |
| **NVIDIA NIM** | API key | NVIDIA-hosted models |

The **OpenAI** block below is the worked example. For any other provider, the env-var pattern is the same — see **[Appendix A](#appendix-a--other-llm-provider-configurations): Other LLM Provider Configurations** at the end of this guide for a drop-in block per provider.

---

### OpenAI

```bash
# Plugin
MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai_enhanced:OpenAIPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai_enhanced:OpenAIPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.openai:OpenAIEmbeddingsPlugin

# Credentials
OPENAI_API_TYPE=openai
OPENAI_API_KEY=sk-your-openai-api-key

# Custom endpoint (optional) — use for OpenAI-compatible gateways/proxies
# OPENAI_API_BASE=https://your-gateway.example.com/v1
```

Default models: `gpt-4o-mini` (fast), `gpt-4o` (large / vision / code), `o1-preview` (reasoning). To override per-category models or temperatures, see **[§11](#11-environment-variable-reference) Environment Variable Reference → Model category overrides**.

> **Using GPT-5 (or later) or any o-series (`o1` / `o3` / `o4`) model? Requires backend 2.3.4 or later, and you must set one environment variable.** These deployments use the post-Sep-2024 OpenAI Chat Completions contract: they reject the legacy `max_tokens` parameter (requiring `max_completion_tokens` instead) and reject any `temperature` other than the API default (1.0). To enable correct behaviour, set `OPENAI_GPT5_COMPATIBLE=true` in the orchestrator environment. The orchestrator then binds `max_completion_tokens` on every LLM call and omits `temperature` from the model constructor (so the API default applies). Leave the flag unset (or `false`) for GPT-4o-family and earlier deployments. **Backend 2.3.2 and earlier do not support GPT-5+ or o-series deployments** — every request that includes a token limit will fail with `Unsupported parameter: 'max_tokens' is not supported with this model. Use 'max_completion_tokens' instead.` See **[§11](#11-environment-variable-reference) Environment Variable Reference → GPT-5+ / o-series deployment flag** and **[Appendix A](#appendix-a--other-llm-provider-configurations) — Azure OpenAI** for the full details.

---

## 5. Step 3 — Configure Your Knowledge Base

> **Applies to:** All deployments. A knowledge base is **required** for Spotfire Copilot's
> Help and HowTo features to function.

The orchestrator uses the terms "knowledge base" and "RAG" (Retrieval-Augmented Generation)
interchangeably. Both refer to the same capability: retrieving relevant document chunks from
a vector database and including them as context in LLM prompts. Throughout this guide and the
orchestrator's configuration, you will see references to "RAG", "retriever", and "vector database" —
these all relate to your knowledge base.

The orchestrator uses a **retriever plugin** to connect to your knowledge base. Set the
appropriate plugin and credentials in your environment configuration. **Zilliz Cloud** is the worked example below; for any other provider, see **[Appendix B](#appendix-b--other-knowledge-base-configurations): Other Knowledge Base Configurations** at the end of this guide for a drop-in block per provider (Milvus, Qdrant, MongoDB Atlas, Redis, Azure Cognitive Search, Vertex AI Vector Search, AWS Bedrock Knowledge Bases, Databricks, PostgreSQL pgvector).

> **Cloud-native recommendations:** Use Azure Cognitive Search on Azure, AWS Bedrock
> Knowledge Bases on AWS, and Vertex AI Vector Search on GCP to simplify authentication
> (managed identity / IAM roles) and minimise cross-cloud network hops.
>
> **On-premise recommendation:** **Milvus** is the recommended choice for on-premise
> deployments. Compared to pgvector (PostgreSQL's vector extension), Milvus delivers
> significantly better query performance at scale, efficient memory management through
> segment-based architecture and quantization, and handles large document collections
> (500K+ chunks) without requiring all indexes to fit in RAM. It also supports GPU
> acceleration and built-in replication for production workloads.
>
> **pgvector** is a viable alternative for **small workloads only** (< 50K chunks) where
> you want to avoid introducing a new database system. It reuses existing PostgreSQL
> infrastructure and expertise, but its HNSW indexes must fit entirely in RAM for
> acceptable query latency — at scale this becomes prohibitively expensive (budget
> ~1 GB RAM per 1M 1536-dimensional vectors). For anything beyond a POC, prefer
> Milvus or Qdrant.

### Configuration Examples

**Zilliz Cloud** (this guide's worked example):
```bash
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.zilliz:ZillizRetrieverPlugin
ZILLIZ_CLOUD_URI=https://your-instance.zillizcloud.com
ZILLIZ_CLOUD_API_KEY=your-zilliz-api-key
```

> **Other providers:** Milvus (self-hosted) · Qdrant · MongoDB Atlas · Redis · Azure Cognitive Search · Vertex AI Vector Search · AWS Bedrock Knowledge Bases · Databricks · PostgreSQL pgvector — see **[Appendix B](#appendix-b--other-knowledge-base-configurations): Other Knowledge Base Configurations** (at the end of this guide). pgvector has additional setup requirements (compute sizing, extension install, role/database SQL) documented in the same appendix.

### Embeddings Plugin

The embeddings plugin must match the embedding model used to create your vector index. Supported embeddings:

| Provider | Plugin Entry Point |
|---|---|
| **OpenAI** | `plugins.embeddings.openai:OpenAIEmbeddingsPlugin` |
| **Azure OpenAI** | `plugins.embeddings.az_openai:AzOpenAIEmbeddingsPlugin` |
| **Vertex AI** | `plugins.embeddings.vertexai:VertexAIEmbeddingsPlugin` |
| **AWS Bedrock** | `plugins.embeddings.bedrock:BedrockEmbeddingsPlugin` |
| **Ollama** | `plugins.embeddings.ollama:OllamaEmbeddingsPlugin` |
| **NVIDIA NIM** | `plugins.embeddings.nvidia_nim:NvidiaNimEmbeddingsPlugin` |

### Knowledge Base Tuning

Defaults work for most deployments. To tune retrieval (chunks per query, score threshold, retriever strategy) see **[§11](#11-environment-variable-reference) Environment Variable Reference → Knowledge base / RAG variables**.

---

## 6. Step 4 — Deploy

> **Image references in the examples below assume 2.3.4 (latest).** All snippets pull from
> `copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4`. You must have already
> logged in to the registry with credentials issued by Spotfire Support — see
> **[§6.1](#61-pulling-the-docker-images) Pulling the Docker Images** below and the
> [OCI Registry Access Guide](https://community.spotfire.com/articles/spotfire/oci-registry-access-guide/).
>
> **Already on 2.3.2?** You only need to redeploy with the 2.3.4 image tag if you use a GPT-5.x or o-series (`o1` / `o3` / `o4`) Azure OpenAI deployment. Otherwise 2.3.2 is fully supported — see **[Appendix D](#appendix-d--release-notes) — Release notes → What's new in 2.3.4**.
>
> **Deploying 2.3.0?** Substitute `public.ecr.aws/tds/llm-orchestrator:2.3.0` for the image
> in every snippet and omit any registry-credential / image-pull-secret configuration
> (that registry is public).

> **Key pattern for all platforms:** You deploy the **same Docker image** for the orchestrator
> (default startup) and optionally a second time for the admin console (with a custom
> startup command), alongside a PostgreSQL database. The only differences between
> platforms are *how* you configure environment variables and *where* the database lives.
>
> **Deploying without the admin console:** If you choose to skip the admin console, simply
> omit the admin console container/service from the instructions below. The orchestrator
> and PostgreSQL are sufficient. You can manage users and OAuth2 clients via the
> orchestrator's REST API (see **[§9.2](#92-using-the-rest-api-programmatic) Using the REST API**).

### 6.1 Pulling the Docker Images

The container image source depends on the version you are installing.

| Version | Registry | Authentication | Reference |
|---|---|---|---|
| **2.3.4** *(latest — use for new deployments)* | `copilotoci.azurecr.io/spotfirecopilot/` (Azure Container Registry) | **Required** — credentials issued by Spotfire Support | [OCI Registry Access Guide](https://community.spotfire.com/articles/spotfire/oci-registry-access-guide/) |
| **2.3.2** *(previous release — fully supported)* | `copilotoci.azurecr.io/spotfirecopilot/` (Azure Container Registry) | **Required** — credentials issued by Spotfire Support | [OCI Registry Access Guide](https://community.spotfire.com/articles/spotfire/oci-registry-access-guide/) |
| **2.3.1** | `copilotoci.azurecr.io/spotfirecopilot/` (Azure Container Registry) | **Required** — credentials issued by Spotfire Support | [OCI Registry Access Guide](https://community.spotfire.com/articles/spotfire/oci-registry-access-guide/) |
| **2.3.0** | `public.ecr.aws/tds/` (Amazon ECR Public) | None — anonymous pull | n/a |

#### 2.3.4 / 2.3.2 / 2.3.1 — OCI registry

Starting with 2.3.1, all Spotfire Copilot container images are distributed via an OCI registry hosted in Azure Container Registry. **You must obtain credentials before deploying.**

1. **Request access.** Open a case via the [Spotfire Support Portal](https://support.tibco.com) selecting **Spotfire Enterprise** as the Product and request access to the Spotfire Copilot OCI registry. Support will issue a registry username and password/token.
2. **Log in to the registry** on every host that needs to pull images:
   ```bash
   docker login copilotoci.azurecr.io
   # (optional, for Helm-based deployments)
   helm registry login copilotoci.azurecr.io
   ```
3. **Pull the images** (substitute the tag for the version you want — `2.3.4` for new deployments):
   ```bash
   # Orchestrator (also used for the admin console — same image)
   docker pull copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4

  # Data loaders (pull only the ones you need)
  docker pull copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-pypdf:2.3.4
  docker pull copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-unstruct:2.3.4
   ```

For login command details, version policy, troubleshooting registry auth errors, and the complete artifact catalog, consult the [OCI Registry Access Guide](https://community.spotfire.com/articles/spotfire/oci-registry-access-guide/).

> **Cloud and Kubernetes deployments:** create an image-pull secret using your registry credentials and reference it from your deployment manifest. For example, on Kubernetes:
> ```bash
> kubectl create secret docker-registry copilotoci-pull \
>   --docker-server=copilotoci.azurecr.io \
>   --docker-username='<registry-username>' \
>   --docker-password='<registry-password-or-token>'
> ```
> Then add `imagePullSecrets: [{ name: copilotoci-pull }]` to each deployment that pulls from `copilotoci.azurecr.io`. AWS ECS, Azure Container Apps, and GCP Cloud Run have equivalent registry-credential mechanisms — see the platform-specific subsections below.

#### 2.3.0 — Amazon ECR Public (no authentication)

For **2.3.0 only**, the image is hosted on Amazon ECR Public and requires no authentication.

```bash
docker pull public.ecr.aws/tds/llm-orchestrator:2.3.0
```

> **No ECR login required.** The `public.ecr.aws` registry is a public gallery — you do
> **not** need an AWS account or `aws ecr-public get-login-password` to pull. If you are
> behind a corporate proxy or firewall, ensure outbound HTTPS access to
> `public.ecr.aws` is allowed.

#### Air-gapped / private registry mirroring

If your deployment environment cannot reach the upstream registry, pull on an internet-connected machine, then retag and push to your internal registry:

```bash
# 2.3.4 (latest)
docker login copilotoci.azurecr.io
docker pull copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4
docker tag  copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4 your-registry.example.com/llm-orchestrator:2.3.4
docker push your-registry.example.com/llm-orchestrator:2.3.4

# 2.3.2 (previous release — still supported)
docker pull copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.2
docker tag  copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.2 your-registry.example.com/llm-orchestrator:2.3.2
docker push your-registry.example.com/llm-orchestrator:2.3.2

# 2.3.0
docker pull public.ecr.aws/tds/llm-orchestrator:2.3.0
docker tag  public.ecr.aws/tds/llm-orchestrator:2.3.0 your-registry.example.com/llm-orchestrator:2.3.0
docker push your-registry.example.com/llm-orchestrator:2.3.0
```

Update all deployment manifests and compose files to reference your internal registry URL.

The PostgreSQL image (`postgres:15-alpine`) is pulled from Docker Hub and is only needed for on-premise deployments. Cloud deployments use a managed PostgreSQL service instead.

### Managing Environment Variables in the Cloud

In cloud deployments, you **do not use `.env` files**. Each cloud platform has its own mechanism
for injecting environment variables and secrets into containers:

| Platform | Environment Variables | Secrets (API keys, passwords) |
|---|---|---|
| **Azure Container Apps** | Container App → **Settings → Environment variables** (portal), or `--set-env-vars` (CLI) | Azure Key Vault references: `secretref:my-kv-secret` |
| **GCP Cloud Run** | `--set-env-vars` flag, or Cloud Run → **Variables & Secrets** tab (console) | GCP Secret Manager: `--set-secrets MY_KEY=my-secret:latest` |
| **AWS ECS** | Task Definition → `environment` block (JSON), or `--environment` (CLI) | AWS Secrets Manager / SSM Parameter Store: `valueFrom` in the task definition |
| **Kubernetes** | `ConfigMap` mounted as `envFrom`, or inline `env` in the Pod spec | `Secret` resources mounted as `envFrom` or individual `valueFrom` references |

#### Best practices

- **Never embed secrets in container images or source control.** Use your platform's secrets manager.
- **Separate secrets from configuration.** Use a `Secret` (or Key Vault / Secrets Manager) for `SECRET_KEY`, `HASHED_ADMIN_PASSWORD`, API keys, and `DATABASE_URL`. Use plain environment variables for non-sensitive settings like `LOG_LEVEL` and plugin entry points.
- **Keep both services in sync.** `SECRET_KEY` and database connection strings **must be identical** in both the orchestrator and admin console. Use a shared secret reference rather than duplicating values.
- **Bcrypt hashes contain `$` characters.** Some platforms (notably Docker Compose) interpret `$` as variable substitution. In Kubernetes Secrets, Azure Key Vault, and AWS Secrets Manager this is not an issue — the value is stored verbatim. Only Docker Compose `.env` files require single-quoting.

#### Required environment variables (all platforms)

| Variable | Orchestrator | Admin Console *(if deployed)* | Notes |
|---|---|---|---|
| `SECRET_KEY` | ✅ | ✅ | **Must be identical.** JWT signing + inter-service auth. |
| `DATABASE_URL` | ✅ | ✅ | Async driver: `postgresql+asyncpg://user:pass@host:5432/orchestrator` |
| `SYNC_DATABASE_URL` | ✅ | ✅ | Sync driver: `postgresql://user:pass@host:5432/orchestrator` |
| `HASHED_ADMIN_PASSWORD` | ✅ | ✅ | Bcrypt hash from `generate_credentials.py` |
| `MODEL_PLUGIN_ENTRY_POINT` | ✅ | — | Must match your LLM provider |
| `SECONDARY_MODEL_PLUGIN_ENTRY_POINT` | ✅ | — | **Set to same value as `MODEL_PLUGIN_ENTRY_POINT`.** Required at startup but not used by clients at runtime (deprecated internal feature). |
| `EMBEDDINGS_PLUGIN_ENTRY_POINT` | ✅ | — | Must match embeddings used to build your knowledge base |
| `RETRIEVER_PLUGIN_ENTRY_POINT` | ✅ | — | Knowledge base retriever plugin |
| LLM credentials (API key / IAM role) | ✅ | — | Provider-specific |
| Knowledge base credentials | ✅ | — | Provider-specific |
| `ORCHESTRATOR_INTERNAL_URL` | — | ✅ | URL the console uses to reach the orchestrator (e.g., `http://orch-orchestrator`) |
| `DB_SSLMODE` | ✅ | ✅ | Set to `require` for managed PostgreSQL (Azure, GCP, AWS) |

---

### 6.2 Azure Container Apps

> **Prerequisites:** Azure subscription, `az` CLI installed and authenticated, an Azure
> Container Apps Environment, and an Azure Database for PostgreSQL Flexible Server.

#### Provision the infrastructure

```bash
# Create a resource group
az group create --name SpotfireCopilot --location eastus

# Create a Container Apps environment
az containerapp env create \
  --name copilot-env \
  --resource-group SpotfireCopilot \
  --location eastus

# Create a managed PostgreSQL instance
az postgres flexible-server create \
  --name copilot-postgres \
  --resource-group SpotfireCopilot \
  --admin-user orchestrator \
  --admin-password '<your-db-password>' \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --version 15
```

#### Store secrets in Azure Key Vault

```bash
# Create a Key Vault (or use an existing one)
az keyvault create --name copilot-kv --resource-group SpotfireCopilot --location eastus

# Store secrets
az keyvault secret set --vault-name copilot-kv --name secret-key --value "<your-SECRET-KEY>"
az keyvault secret set --vault-name copilot-kv --name db-url \
  --value "postgresql+asyncpg://orchestrator:<db-pass>@copilot-postgres.postgres.database.azure.com:5432/orchestrator?ssl=require"
az keyvault secret set --vault-name copilot-kv --name db-url-sync \
  --value "postgresql://orchestrator:<db-pass>@copilot-postgres.postgres.database.azure.com:5432/orchestrator?sslmode=require"
az keyvault secret set --vault-name copilot-kv --name hashed-admin-pw --value '<bcrypt-hash>'
az keyvault secret set --vault-name copilot-kv --name openai-api-key --value "sk-..."
```

#### Deploy the orchestrator

> **Service: Orchestrator** · port `8080` · default startup command · health probe `GET /`.

```bash
az containerapp create \
  --name orch-orchestrator \
  --resource-group SpotfireCopilot \
  --environment copilot-env \
  --image copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4 \
  --target-port 8080 \
  --ingress external \
  --min-replicas 1 \
  --secrets \
    secret-key=keyvaultref:https://copilot-kv.vault.azure.net/secrets/secret-key,identityref:/subscriptions/.../managedIdentities/copilot-id \
    db-url=keyvaultref:https://copilot-kv.vault.azure.net/secrets/db-url,identityref:... \
    db-url-sync=keyvaultref:https://copilot-kv.vault.azure.net/secrets/db-url-sync,identityref:... \
    hashed-admin-pw=keyvaultref:https://copilot-kv.vault.azure.net/secrets/hashed-admin-pw,identityref:... \
    openai-key=keyvaultref:https://copilot-kv.vault.azure.net/secrets/openai-api-key,identityref:... \
  --env-vars \
    SECRET_KEY=secretref:secret-key \
    DATABASE_URL=secretref:db-url \
    SYNC_DATABASE_URL=secretref:db-url-sync \
    HASHED_ADMIN_PASSWORD=secretref:hashed-admin-pw \
    OPENAI_API_KEY=secretref:openai-key \
    MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai_enhanced:OpenAIPlugin \
    SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai_enhanced:OpenAIPlugin \
    EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.openai:OpenAIEmbeddingsPlugin \
    RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.az_cog_search:AzCognitiveSearchRetrieverPlugin \
    DB_SSLMODE=require \
    LOG_LEVEL=INFO
```

#### Deploy the admin console (optional)

> **Service: Admin Console** · port `8081` · command override `python /app/admin_console/admin_main.py` · health probe `GET /health`.

```bash
az containerapp create \
  --name orch-console \
  --resource-group SpotfireCopilot \
  --environment copilot-env \
  --image copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4 \
  --target-port 8081 \
  --ingress external \
  --min-replicas 1 \
  --command "python" "/app/admin_console/admin_main.py" \
  --secrets \
    secret-key=keyvaultref:... \
    db-url=keyvaultref:... \
    db-url-sync=keyvaultref:... \
    hashed-admin-pw=keyvaultref:... \
  --env-vars \
    SECRET_KEY=secretref:secret-key \
    DATABASE_URL=secretref:db-url \
    SYNC_DATABASE_URL=secretref:db-url-sync \
    HASHED_ADMIN_PASSWORD=secretref:hashed-admin-pw \
    ORCHESTRATOR_INTERNAL_URL=http://orch-orchestrator \
    LOG_LEVEL=INFO
```

> **Critical:** The admin console **must** have a command override. Without it, the container
> starts the orchestrator instead. The target port **must** be `8081`, not `8080`.

#### Azure Portal alternative

1. Open **orch-console** → **Containers** → edit the container
2. **Command override:** `python` | **Arguments:** `/app/admin_console/admin_main.py`
3. **Ingress** → set **Target port** to `8081`
4. **Settings → Environment variables** — add all required variables, referencing Key Vault secrets
5. Save and wait for the new revision to deploy

---

### 6.3 GCP Cloud Run

> **Prerequisites:** GCP project, `gcloud` CLI installed and authenticated, Cloud SQL for
> PostgreSQL instance, and GCP Secret Manager enabled.

#### Store secrets in GCP Secret Manager

```bash
# Create secrets
echo -n "<your-SECRET-KEY>" | gcloud secrets create secret-key --data-file=-
echo -n "postgresql+asyncpg://user:pass@/orchestrator?host=/cloudsql/PROJECT:REGION:INSTANCE" \
  | gcloud secrets create db-url --data-file=-
echo -n "postgresql://user:pass@/orchestrator?host=/cloudsql/PROJECT:REGION:INSTANCE" \
  | gcloud secrets create db-url-sync --data-file=-
echo -n '<bcrypt-hash>' | gcloud secrets create hashed-admin-pw --data-file=-
echo -n "sk-..." | gcloud secrets create openai-api-key --data-file=-

# Grant the Cloud Run service account access
gcloud secrets add-iam-policy-binding secret-key \
  --member="serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
# (repeat for each secret)
```

#### Deploy the orchestrator

> **Service: Orchestrator** · port `8080` · default startup command · health probe `GET /`.

```bash
gcloud run deploy llm-orchestrator \
  --image copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4 \
  --port 8080 \
  --set-env-vars \
    MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai_enhanced:VertexAIPlugin,\
    SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai_enhanced:VertexAIPlugin,\
    EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.vertexai:VertexAIEmbeddingsPlugin,\
    RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin,\
    PROJECT_ID=your-gcp-project-id,\
    LOCATION_ID=us-central1,\
    DB_SSLMODE=require,\
    LOG_LEVEL=INFO \
  --set-secrets \
    SECRET_KEY=secret-key:latest,\
    DATABASE_URL=db-url:latest,\
    SYNC_DATABASE_URL=db-url-sync:latest,\
    HASHED_ADMIN_PASSWORD=hashed-admin-pw:latest,\
    OPENAI_API_KEY=openai-api-key:latest \
  --add-cloudsql-instances PROJECT:REGION:INSTANCE \
  --region us-central1
```

#### Deploy the admin console (optional)

> **Service: Admin Console** · port `8081` · command override `python /app/admin_console/admin_main.py` · health probe `GET /health`.

```bash
gcloud run deploy llm-orchestrator-console \
  --image copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4 \
  --port 8081 \
  --command "python","/app/admin_console/admin_main.py" \
  --set-env-vars \
    ORCHESTRATOR_INTERNAL_URL=https://llm-orchestrator-HASH-uc.a.run.app,\
    LOG_LEVEL=INFO \
  --set-secrets \
    SECRET_KEY=secret-key:latest,\
    DATABASE_URL=db-url:latest,\
    SYNC_DATABASE_URL=db-url-sync:latest,\
    HASHED_ADMIN_PASSWORD=hashed-admin-pw:latest \
  --add-cloudsql-instances PROJECT:REGION:INSTANCE \
  --region us-central1
```

#### Vertex AI notes

If using Vertex AI as your LLM provider on GCP:
- The Cloud Run service account inherits IAM permissions — no API key file needed
- Set `PROJECT_ID` and `LOCATION_ID` as environment variables
- Set `EMBEDDING_MODEL_NAME=text-embedding-004` (must be an embedding model, not a generative model)

Health check startup probe path:
- Orchestrator: `/`
- Admin Console: `/health`

---

### 6.4 AWS (ECS / Fargate)

> **Prerequisites:** AWS account, `aws` CLI installed and authenticated, an ECS cluster,
> an RDS PostgreSQL instance, and AWS Secrets Manager enabled.

#### Store secrets in AWS Secrets Manager

```bash
aws secretsmanager create-secret --name copilot/secret-key \
  --secret-string "<your-SECRET-KEY>"
aws secretsmanager create-secret --name copilot/database-url \
  --secret-string "postgresql+asyncpg://user:pass@your-rds-endpoint:5432/orchestrator"
aws secretsmanager create-secret --name copilot/database-url-sync \
  --secret-string "postgresql://user:pass@your-rds-endpoint:5432/orchestrator"
aws secretsmanager create-secret --name copilot/hashed-admin-pw \
  --secret-string '<bcrypt-hash>'
```

#### IAM task role

Create an ECS task role with the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:Retrieve",
        "bedrock:ListKnowledgeBases",
        "bedrock:GetKnowledgeBase"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:copilot/*"
    }
  ]
}
```

> **⚠️ IAM roles:** When running on ECS/Fargate with an IAM task role, do **NOT** set
> `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`. These override the IAM role and
> cause authentication failures. Only set `AWS_REGION`.

#### ECS task definition (orchestrator)

> **Service: Orchestrator** · port `8080` · default startup command · health probe `curl -f http://localhost:8080/`.

```json
{
  "family": "copilot-orchestrator",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "taskRoleArn": "arn:aws:iam::...:role/copilot-task-role",
  "executionRoleArn": "arn:aws:iam::...:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "orchestrator",
      "image": "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4",
      "portMappings": [{ "containerPort": 8080 }],
      "environment": [
        { "name": "MODEL_PLUGIN_ENTRY_POINT", "value": "plugins.models.bedrock_enhanced:BedrockPlugin" },
        { "name": "SECONDARY_MODEL_PLUGIN_ENTRY_POINT", "value": "plugins.models.bedrock_enhanced:BedrockPlugin" },
        { "name": "EMBEDDINGS_PLUGIN_ENTRY_POINT", "value": "plugins.embeddings.bedrock:BedrockEmbeddingsPlugin" },
        { "name": "RETRIEVER_PLUGIN_ENTRY_POINT", "value": "plugins.retrievers.amazon_kbs:AmazonKBsRetrieverPlugin" },
        { "name": "AWS_REGION", "value": "us-east-1" },
        { "name": "DB_SSLMODE", "value": "require" },
        { "name": "LOG_LEVEL", "value": "INFO" }
      ],
      "secrets": [
        { "name": "SECRET_KEY", "valueFrom": "arn:aws:secretsmanager:...:secret:copilot/secret-key" },
        { "name": "DATABASE_URL", "valueFrom": "arn:aws:secretsmanager:...:secret:copilot/database-url" },
        { "name": "SYNC_DATABASE_URL", "valueFrom": "arn:aws:secretsmanager:...:secret:copilot/database-url-sync" },
        { "name": "HASHED_ADMIN_PASSWORD", "valueFrom": "arn:aws:secretsmanager:...:secret:copilot/hashed-admin-pw" }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8080/ || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

#### ECS task definition (admin console, optional)

> **Service: Admin Console** · port `8081` · command override `python /app/admin_console/admin_main.py` · health probe `curl -f http://localhost:8081/health`.

Use the same image but override the command and port:

```json
{
  "family": "copilot-admin-console",
  "containerDefinitions": [
    {
      "name": "admin-console",
      "image": "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4",
      "command": ["python", "/app/admin_console/admin_main.py"],
      "portMappings": [{ "containerPort": 8081 }],
      "environment": [
        { "name": "ORCHESTRATOR_INTERNAL_URL", "value": "http://orchestrator.copilot.local:8080" },
        { "name": "LOG_LEVEL", "value": "INFO" }
      ],
      "secrets": [
        { "name": "SECRET_KEY", "valueFrom": "arn:aws:secretsmanager:...:secret:copilot/secret-key" },
        { "name": "DATABASE_URL", "valueFrom": "arn:aws:secretsmanager:...:secret:copilot/database-url" },
        { "name": "SYNC_DATABASE_URL", "valueFrom": "arn:aws:secretsmanager:...:secret:copilot/database-url-sync" },
        { "name": "HASHED_ADMIN_PASSWORD", "valueFrom": "arn:aws:secretsmanager:...:secret:copilot/hashed-admin-pw" }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8081/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 30
      }
    }
  ]
}
```

---

### 6.5 Kubernetes

> **Applies to:** AKS (Azure), GKE (Google), EKS (Amazon), or any conformant Kubernetes
> cluster (v1.25+). Kubernetes is a common choice for organisations that already have
> a cluster and want fine-grained control over scaling, networking, and deployment.

#### Prerequisites

- `kubectl` configured against your cluster
- A Kubernetes namespace (e.g., `copilot`)
- A managed PostgreSQL instance accessible from the cluster (Cloud SQL, RDS, Azure Database for PostgreSQL) — or an in-cluster PostgreSQL StatefulSet
- Familiarity with `Deployment`, `Service`, `Secret`, `ConfigMap`, and `Ingress` resources

#### Secrets and ConfigMaps

Store sensitive values in a Kubernetes `Secret` and non-sensitive configuration in a `ConfigMap`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: copilot-secrets
  namespace: copilot
type: Opaque
stringData:
  SECRET_KEY: "<your-64-char-hex-string>"
  DATABASE_URL: "postgresql+asyncpg://user:pass@db-host:5432/orchestrator"
  SYNC_DATABASE_URL: "postgresql://user:pass@db-host:5432/orchestrator"
  HASHED_ADMIN_PASSWORD: "$2b$12$...your-bcrypt-hash..."
  OPENAI_API_KEY: "sk-..."           # or whichever LLM provider key you use
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: copilot-config
  namespace: copilot
data:
  LOG_LEVEL: "INFO"
  MODEL_PLUGIN_ENTRY_POINT: "plugins.models.openai_enhanced:OpenAIPlugin"
  SECONDARY_MODEL_PLUGIN_ENTRY_POINT: "plugins.models.openai_enhanced:OpenAIPlugin"
  EMBEDDINGS_PLUGIN_ENTRY_POINT: "plugins.embeddings.openai:OpenAIEmbeddingsPlugin"
  RETRIEVER_PLUGIN_ENTRY_POINT: "plugins.retrievers.zilliz:ZillizRetrieverPlugin"
  DB_SSLMODE: "require"
```

> **Tip:** On AKS, GKE, or EKS you can integrate with your cloud's secret manager
> (Azure Key Vault CSI driver, GCP Secrets Store CSI driver, AWS Secrets Manager CSI
> driver) instead of storing secrets directly in Kubernetes. This is recommended for
> production.

#### Orchestrator Deployment

> **Service: Orchestrator** · container port `8080` · default startup command · liveness/readiness probe path `/`.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orchestrator
  namespace: copilot
spec:
  replicas: 2
  selector:
    matchLabels:
      app: orchestrator
  template:
    metadata:
      labels:
        app: orchestrator
    spec:
      containers:
        - name: orchestrator
          image: copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: copilot-config
            - secretRef:
                name: copilot-secrets
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: "2"
              memory: 2Gi
```

#### Admin Console Deployment (optional)

> **Service: Admin Console** · container port `8081` · command override `python /app/admin_console/admin_main.py` · liveness/readiness probe path `/health`.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: admin-console
  namespace: copilot
spec:
  replicas: 1
  selector:
    matchLabels:
      app: admin-console
  template:
    metadata:
      labels:
        app: admin-console
    spec:
      containers:
        - name: admin-console
          image: copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4
          command: ["python", "/app/admin_console/admin_main.py"]
          ports:
            - containerPort: 8081
          envFrom:
            - configMapRef:
                name: copilot-config
            - secretRef:
                name: copilot-secrets
          env:
            - name: ORCHESTRATOR_INTERNAL_URL
              value: "http://orchestrator.copilot.svc.cluster.local:8080"
          livenessProbe:
            httpGet:
              path: /health
              port: 8081
            initialDelaySeconds: 15
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 8081
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
```

#### Services

```yaml
apiVersion: v1
kind: Service
metadata:
  name: orchestrator
  namespace: copilot
spec:
  selector:
    app: orchestrator
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: admin-console
  namespace: copilot
spec:
  selector:
    app: admin-console
  ports:
    - port: 8081
      targetPort: 8081
```

#### Ingress

Expose both services through a single Ingress with path-based routing (adapt for your
ingress controller — nginx, Traefik, ALB, etc.):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: copilot-ingress
  namespace: copilot
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  tls:
    - hosts:
        - copilot.your-domain.com
      secretName: copilot-tls
  rules:
    - host: copilot.your-domain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: orchestrator
                port:
                  number: 8080
    - host: copilot-admin.your-domain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: admin-console
                port:
                  number: 8081
```

#### Horizontal Pod Autoscaler (optional)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: orchestrator-hpa
  namespace: copilot
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: orchestrator
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

### 6.6 Using Your Own PostgreSQL Server (No Docker)

> **Use this option** if you already have PostgreSQL infrastructure (physical servers,
> VMs, or a DBA-managed instance) and prefer not to use Docker for the database.
> You still run the orchestrator and admin console as Docker containers (or bare
> processes), but point them at your existing PostgreSQL server.

#### Prerequisites

- PostgreSQL **15** or **16** (15 recommended)
- A PostgreSQL user with `CREATE DATABASE` privileges (or a DBA who can run the setup)
- Network connectivity from the orchestrator host to the PostgreSQL server
- `psql` client installed on the machine where you'll run the setup script

#### Create the application database

Connect to your PostgreSQL server as a superuser (or a role with `CREATEDB` and `CREATEROLE`):

```bash
psql -h your-pg-host -U postgres
```

Then run:

```sql
-- 1. Create a dedicated role for the orchestrator
CREATE ROLE orchestrator WITH LOGIN PASSWORD 'choose-a-strong-password';

-- 2. Create the application database
CREATE DATABASE orchestrator OWNER orchestrator;

-- 3. Connect to the new database
\c orchestrator

-- 4. Grant schema permissions
GRANT ALL PRIVILEGES ON SCHEMA public TO orchestrator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO orchestrator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO orchestrator;

-- 5. Enable UUID generation (required by the application)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

#### Configure the orchestrator to use your database

Set the following environment variables (in your `.env` file or process environment):

```bash
# Async driver (used by the orchestrator at runtime)
DATABASE_URL=postgresql+asyncpg://orchestrator:choose-a-strong-password@your-pg-host:5432/orchestrator

# Sync driver (used by Alembic migrations and admin console)
SYNC_DATABASE_URL=postgresql://orchestrator:choose-a-strong-password@your-pg-host:5432/orchestrator

# SSL mode — set to 'require' if your server enforces SSL, 'disable' for local
DB_SSLMODE=disable
```

> **Do NOT set `POSTGRES_PASSWORD`** when using an external database. That variable is
> only used by Docker Compose to initialize the bundled PostgreSQL container. With your
> own server, use `DATABASE_URL` and `SYNC_DATABASE_URL` directly.

#### Run migrations

The orchestrator automatically runs Alembic migrations on startup. To verify manually:

```bash
# If running the orchestrator via Docker (pointed at your external DB)
docker run --rm \
  -e DATABASE_URL="postgresql+asyncpg://orchestrator:pass@your-pg-host:5432/orchestrator" \
  -e SYNC_DATABASE_URL="postgresql://orchestrator:pass@your-pg-host:5432/orchestrator" \
  -e SECRET_KEY="dummy-for-migration-only" \
  copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:2.3.4 \
  alembic upgrade head

# If running bare (Python environment with the source)
cd orchestrator-service/src
SYNC_DATABASE_URL="postgresql://orchestrator:pass@your-pg-host:5432/orchestrator" \
  alembic upgrade head
```

#### Security hardening for production

```sql
-- Restrict the orchestrator role to only its own database
REVOKE ALL ON DATABASE postgres FROM orchestrator;
REVOKE ALL ON DATABASE template1 FROM orchestrator;

-- If using pg_hba.conf, add a line restricting the role to the orchestrator DB:
-- host  orchestrator  orchestrator  10.0.0.0/24  scram-sha-256
```

> **Backups:** The orchestrator database stores conversations, user accounts, OAuth2
> clients, and agent registrations. Ensure your existing backup strategy covers this
> database. A logical backup (`pg_dump`) is sufficient for disaster recovery.

---

## 7. Step 5 — Verify and First Login

### Health check endpoints

> **⚠️ The orchestrator and admin console use different health check paths.** Using the wrong path returns 404 and your platform will restart the container in a loop — the single most common deployment failure we see. The orchestrator has **no `/health` endpoint**; only `/` returns 200.

| Container | Health Path | Port | Method | Expected Response |
|---|---|---|---|---|
| **Orchestrator** | **`/`** | 8080 | `GET` | `{"status":"ok","service":"llm-orchestrator"}` |
| **Admin Console** | **`/health`** | 8081 | `GET` | `{"service":"Spotfire Copilot Admin Console","status":"running",...}` |

Smoke-test from a shell:

```bash
# On-premise
curl -f http://localhost:8080/         # Orchestrator — use ROOT, not /health
curl -f http://localhost:8081/health   # Admin Console — use /health, not / (/ returns 302 → /login)

# Cloud (replace with your actual hostnames)
curl -f https://<ORCHESTRATOR_HOST>/
curl -f https://<CONSOLE_HOST>/health
```

**Platform-specific probe configuration:**

| Platform | Orchestrator | Admin Console |
|---|---|---|
| **Docker Compose** | `curl -f http://localhost:8080/` | `curl -f http://localhost:8081/health` |
| **Kubernetes** | `httpGet` → path: `/`, port: `8080` | `httpGet` → path: `/health`, port: `8081` |
| **AWS ECS** | `CMD-SHELL curl -f http://localhost:8080/ \|\| exit 1` | `CMD-SHELL curl -f http://localhost:8081/health \|\| exit 1` |
| **Azure Container Apps** | Ingress probe → path: `/`, port: `8080` | Ingress probe → path: `/health`, port: `8081` |
| **GCP Cloud Run** | Startup probe → path: `/`, port: `8080` | Startup probe → path: `/health`, port: `8081` |

### First admin login

1. Open the **Admin Console** in a browser: `http://localhost:8081` (or your cloud URL)
2. Login with:
   - **Username:** `admin`
   - **Password:** the plaintext password from `generate_credentials.py` (the one you saved in Step 1)
3. You should see the admin dashboard with system status and conversation analytics

### API documentation

Interactive API docs are available at:
- **Swagger UI:** `http://localhost:8080/docs`
- **ReDoc:** `http://localhost:8080/redoc`

---

## 8. Step 6 — Post-Deployment Setup

### Create OAuth2 clients for your applications

The Spotfire client (or any programmatic consumer) needs an OAuth2 client to authenticate. You can create one via:

**Admin Console (easiest — if deployed):**
1. Log in to the admin console
2. Navigate to **OAuth2 Clients**
3. Click **Create Client** — the system generates a `client_id` and `client_secret`
4. Save the credentials securely

**REST API:**
See **[§9.2](#92-using-the-rest-api-programmatic) Using the REST API** for the programmatic flow.

### Create additional users

The admin console (if deployed) allows you to create users with different roles. Without the admin console, use the orchestrator's REST API:

| Role | Capabilities |
|---|---|
| **admin** | Full access — manage users, clients, conversations, system configuration |
| **power_user** | Access conversations, manage some settings |
| **user** | Standard API access |

### Load knowledge base documents

Your knowledge base must be populated with documents before Spotfire Copilot's Help
and HowTo features will function. Use the **Data Loaders** to ingest documents into
your vector database.

> **See the [Data Loaders Installation Guide](Spotfire%20Copilot%20-%20Data%20Loaders%20Installation%20Guide.md)** for complete
> deployment instructions, Docker Compose examples, and environment variable reference
> for all supported LLM providers and vector databases.

Quick summary:
```bash
# Pull and run the basic data loader
docker pull copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-pypdf:2.3.4

# Configure .env with your LLM + vector DB credentials, then:
docker compose -f docker-compose-data-loader.yml up -d

# Authenticate and load documents via the API at http://localhost:8080/docs
```

Alternatively, you can load data directly into your vector database using its native tools
or SDKs.

### Configure conversation summarization

Conversation summarization runs automatically in the background with sensible defaults. To tune it, see **[§11](#11-environment-variable-reference) Environment Variable Reference → Summarization variables** — four toggles control thread-title generation, progressive summarization, the background daemon, and the summary token budget.

---

## 9. Authentication Guide

The orchestrator's external API supports two authentication flows:

1. **Admin password login** (`POST /auth/jwt/login`) — for human users (admin console, browsing the Swagger UI). This is what the Swagger UI **Authorize** button calls.
2. **OAuth2 Client Credentials** (`POST /client/token`) — for machine-to-machine (M2M) integrations (Spotfire client, scripts, CI/CD).

> The internal `/admin/token` route exists in code but is intentionally blocked by the API gateway middleware on the external port (8080). Customers should not attempt to call it — it returns `404 — Endpoint not found — This endpoint is not available via the external API`. Use `/auth/jwt/login` instead.

### 9.1 Using the Swagger UI (Browser)

This is the easiest way to test most endpoints — Swagger handles the token for you.

1. **Open the Swagger UI** — navigate to `http://localhost:8080/docs`.

2. **Click the green Authorize button** at the top right and fill **only** these two fields:
   - **username:** `admin@orchestrator.local`
   - **password:** the plaintext admin password you saved when running `generate_credentials.py`

   Leave `client_id` and `client_secret` empty. Leave the scopes unchecked. Click **Authorize**, then **Close**.

   > **Important:** The username field must be the email `admin@orchestrator.local`, **not** `admin`. The orchestrator hard-codes that email when bootstrapping the admin user, and the login endpoint authenticates by email even though the Swagger field is labeled “username”.

3. **Use the API** — expand any endpoint, click **Try it out**, fill in the parameters, and **Execute**. Swagger automatically attaches the JWT it received from `/auth/jwt/login` to every subsequent request, so endpoints such as `/tunnel`, `/orchestrator`, `/model-categories`, `/threads`, `/rules`, and `/agents` work directly.

4. **Mint an OAuth2 client token (optional)** — if you also need a long-lived M2M token (for Spotfire clients, scripts, or curl), expand `POST /client/token` → **Try it out** and fill the form fields:
   - **client_id:** the `OAUTH2_CLIENT_ID` from `.env`
   - **client_secret:** the **plaintext** secret from `generate_credentials.py` (not the bcrypt hash in `.env`)
   - **grant_type:** `client_credentials`
   - **scope:** leave empty

   The response includes an `access_token` (a long `eyJ...` string). **Save it** — it is shown only here. This token is for use **outside** Swagger (curl, Postman, Spotfire) because the OpenAPI spec exposes only the password flow, so the **Authorize** dialog has no slot to paste it into.

### 9.2 Using the REST API (Programmatic)

**Base URL:** `http://localhost:8080` (or your cloud URL)

#### Step 1 — Get an admin token (only needed if you want to register new clients)

```bash
curl -X POST http://localhost:8080/auth/jwt/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "username=admin@orchestrator.local" \
  --data-urlencode "password=<your_plaintext_admin_password>"
```

Response:
```json
{
  "access_token": "<admin_token>",
  "token_type": "bearer"
}
```

#### Step 2 — Register an additional OAuth2 client (optional)

The bootstrap client (`OAUTH2_CLIENT_ID` from `.env`) is enough for most deployments. If you need a separate client per integration, register one as the admin:

```bash
curl -X POST http://localhost:8080/register_client \
  -H "Authorization: Bearer <admin_token>" \
  -H "Accept: application/json"
```

Response:
```json
{
  "client_id": "abc123",
  "client_secret": "s3cr3t456",
  "token_endpoint": "/client/token"
}
```

The `client_secret` is shown only once — save it now.

#### Step 3 — Get a client access token

```bash
curl -X POST http://localhost:8080/client/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "client_id=<client_id>" \
  --data-urlencode "client_secret=<client_secret>" \
  --data-urlencode "grant_type=client_credentials"
```

Response:
```json
{
  "access_token": "<client_token>",
  "token_type": "bearer",
  "expires_in": 3600
}
```

Client tokens expire after **1 hour**. Mint a new one when yours expires.

#### Step 4 — Make authenticated API calls

The main inference endpoint is `POST /orchestrator`. The minimum required body fields are `prompt`, `user_id`, and `document_id`:

```bash
curl -X POST http://localhost:8080/orchestrator \
  -H "Authorization: Bearer <client_token>" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"hi","user_id":"u1","document_id":"d1"}'
```

The response includes a `thread_id`. To continue the same conversation, pass it back on the next call:

```bash
curl -X POST http://localhost:8080/orchestrator \
  -H "Authorization: Bearer <client_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt":"What did I just ask?",
    "user_id":"u1",
    "document_id":"d1",
    "thread_id":"<thread_id from previous response>"
  }'
```

Useful optional fields: `request_tag` (for tracking), `message_id` (your own UUID), `document_path` (e.g. `/path/to/document.dxp`), `skip_storage: true` (fire-and-forget inference, no thread/messages persisted).

Other useful endpoints, all called with the same `Authorization: Bearer <client_token>` header:

| Endpoint | Method | Purpose |
|---|---|---|
| `/model-categories` | GET | List the configured model categories (`fast`, `large`, `vision`, etc.) |
| `/threads` | POST | Create a new conversation thread |
| `/threads/{thread_id}` | GET | Read a single thread |
| `/rag/query` | POST | Direct vector search without LLM processing (see **[§10](#10-knowledge-base--rag-configuration) Knowledge Base & RAG Configuration**) |
| `/agents` | GET / POST | List or register A2A agents |

### 9.3 Troubleshooting

**`HTTP 400 LOGIN_BAD_CREDENTIALS` from `/auth/jwt/login` (or the Swagger Authorize button)**
- The username must be the email `admin@orchestrator.local` — not `admin`, not `admin@spotfire.com`, not your real email. The orchestrator hard-codes that email when bootstrapping the admin user.
- The password is the **plaintext** value emitted by `python generate_credentials.py` — not the bcrypt hash stored in `.env`.
- If you have lost the plaintext, regenerate it: `python generate_credentials.py --admin-only`, paste the new `HASHED_ADMIN_PASSWORD` line into `.env`, then `docker compose restart orchestrator`. The orchestrator detects the changed hash on startup and resets the admin password.

**`HTTP 404 — This endpoint is not available via the external API`**
- You called an internal-only route (such as `/admin/token`). Use the public equivalent: `/auth/jwt/login` for password login, `/client/token` for OAuth2 client credentials.

**`HTTP 401 Unauthorized` on every endpoint**
- Your token has expired (client tokens last 1 hour). Mint a new one via `POST /client/token`.
- Confirm the header is exactly `Authorization: Bearer <token>` (one space, capital `B`).
- If you logged in via the Swagger **Authorize** button, your session may have ended when the orchestrator restarted. Click **Authorize** again.

**Rate limits**
- `/auth/jwt/login` and `/client/token` are rate-limited per IP. If you hit the limit, wait 60 seconds before retrying.

**Forgot the OAuth2 client secret**
- You cannot recover it from the bcrypt hash. Regenerate it: `python generate_credentials.py --oauth2-only`, paste the new `OAUTH2_CLIENT_ID` and `OAUTH2_CLIENT_SECRET_HASH` lines into `.env`, then `docker compose restart orchestrator`.

### General REST guidelines

| Header | Value | When |
|---|---|---|
| `Authorization` | `Bearer <token>` | All secured endpoints |
| `Content-Type` | `application/json` | Requests with a JSON body |

| Status Code | Meaning |
|---|---|
| `200 OK` | Success |
| `401 Unauthorized` | Invalid or missing token |
| `403 Forbidden` | Insufficient permissions |
| `400 Bad Request` | Invalid input |
| `500 Internal Server Error` | Server-side failure |

---

## 10. Knowledge Base & RAG Configuration

### How knowledge base retrieval works

The orchestrator uses RAG (Retrieval-Augmented Generation) to power Spotfire Copilot's
Help and HowTo features. When a user sends a prompt and a knowledge base is configured,
the orchestrator:

1. Generates an embedding from the user's query
2. Searches the knowledge base (vector database) for relevant document chunks
3. Includes the retrieved chunks as context in the LLM prompt
4. Returns the LLM's response, grounded in your documents

### Direct RAG query endpoint

For applications that need raw vector search results without LLM processing:

```bash
POST /rag/query
Authorization: Bearer <token>
Content-Type: application/json

{
  "query": "What is the maximum throughput?",
  "index_name": "product-docs",
  "top_k": 5,
  "score_threshold": 0.6,
  "metadata_filter": {"source": "datasheet.pdf"}
}
```

### Knowledge base index enrichment

The orchestrator includes a background daemon that automatically enriches knowledge base
index metadata:
- Runs daily at 2:00 AM UTC
- Samples documents from each vector DB collection
- Uses the LLM to generate natural-language descriptions
- Stores descriptions in the database for use in the admin console

### Static knowledge base index metadata

If auto-discovery is unavailable, you can statically define your indexes:

```bash
RAG_COLLECTIONS_METADATA=[{"name":"my-index","description":"Product documentation"},{"name":"faq","description":"FAQ database"}]
```

---

## 11. Environment Variable Reference

### Required variables (service will not start without these)

| Variable | Example | Description |
|---|---|---|
| `SECRET_KEY` | `a1b2c3d4e5f6...` (64 hex chars) | JWT signing key. Must be identical in orchestrator and admin console. |
| `IMAGE_TAG` | `2.3.2` | Docker image tag. Must be explicitly set for Docker Compose deployments (e.g., `IMAGE_TAG=2.3.2 docker compose up`, or `IMAGE_TAG=2.3.4 docker compose up` for GPT-5.x / o-series deployments). Cloud deployments specify this in their deployment manifest. |
| `POSTGRES_PASSWORD` | `your-db-password` | PostgreSQL password. Used by Docker Compose to construct `DATABASE_URL`. Not needed for cloud deployments (use `DATABASE_URL` directly). |
| At least one LLM API key | `OPENAI_API_KEY=sk-...` | Provider-specific (see Step 2). |

### Authentication variables

| Variable | Example | Description |
|---|---|---|
| `HASHED_ADMIN_PASSWORD` | `'$2b$12$...'` | Bcrypt hash of the admin password. **Wrap in single quotes.** |
| `OAUTH2_CLIENT_ID` | `my-api-client` | Pre-seeded OAuth2 client ID. Auto-generated if omitted. |
| `OAUTH2_CLIENT_SECRET_HASH` | `'$2b$12$...'` | Bcrypt hash of the OAuth2 client secret. **Wrap in single quotes.** |
| `ACCESS_TOKEN_EXPIRE_DAYS` | `30` | How long JWT tokens remain valid (default: 30 days). |

### Plugin variables

| Variable | Example | Description |
|---|---|---|
| `MODEL_PLUGIN_ENTRY_POINT` | `plugins.models.openai_enhanced:OpenAIPlugin` | Primary LLM provider plugin. |
| `SECONDARY_MODEL_PLUGIN_ENTRY_POINT` | `plugins.models.openai_enhanced:OpenAIPlugin` | **Set to same value as primary.** Required at startup but not used by clients (deprecated). |
| `EMBEDDINGS_PLUGIN_ENTRY_POINT` | `plugins.embeddings.openai:OpenAIEmbeddingsPlugin` | Embeddings provider plugin. |
| `RETRIEVER_PLUGIN_ENTRY_POINT` | `plugins.retrievers.zilliz:ZillizRetrieverPlugin` | Knowledge base retriever plugin. |

### LLM provider credentials

Set credentials only for the provider matching `MODEL_PLUGIN_ENTRY_POINT`. Other providers' variables are ignored. For ready-to-paste `.env` blocks per provider, see **[§4](#4-step-2--choose-and-configure-your-llm-provider) Choose and Configure Your LLM Provider** and **[Appendix A](#appendix-a--other-llm-provider-configurations) — Other LLM Provider Configurations**.

| Provider | Variable | Required? | Description |
|---|---|---|---|
| **OpenAI** | `OPENAI_API_TYPE` | Yes | Must be `openai`. |
| **OpenAI** | `OPENAI_API_KEY` | Yes | OpenAI API key. |
| **OpenAI** | `OPENAI_API_BASE` | Optional | Override base URL for OpenAI-compatible gateways/proxies. |
| **Azure OpenAI** | `OPENAI_API_TYPE` | Yes | Must be `azure`. |
| **Azure OpenAI** | `OPENAI_API_KEY` | Yes | Azure OpenAI key. |
| **Azure OpenAI** | `AZURE_OPENAI_ENDPOINT` | Yes | `https://<resource>.openai.azure.com/`. |
| **Azure OpenAI** | `OPENAI_API_VERSION` | Yes | Azure OpenAI API version, e.g. `2024-02-15-preview`. |
| **AWS Bedrock** | `AWS_REGION` | Yes | Region hosting the Bedrock models (e.g. `us-east-1`). |
| **AWS Bedrock** | `AWS_ACCESS_KEY_ID` | Local dev only | **Do not set** when running on ECS/EC2 with an IAM task role — it overrides the role and causes auth failures. |
| **AWS Bedrock** | `AWS_SECRET_ACCESS_KEY` | Local dev only | Pair with `AWS_ACCESS_KEY_ID`. Same warning. |
| **AWS Bedrock** | `AWS_SESSION_TOKEN` | Optional | Required for temporary STS credentials. |
| **AWS Bedrock** | `AWS_PROFILE_NAME` | Optional | Named profile from `~/.aws/credentials` (local dev). |
| **Ollama (local)** | `OLLAMA_BASE_URL` | Yes | Ollama server URL, e.g. `http://host.docker.internal:11434`. |
| **Ollama (local)** | `EMBEDDING_MODEL_NAME` | Optional | Embedding model name, e.g. `nomic-embed-text`. |
| **NVIDIA NIM** | `NVIDIA_API_KEY` | Yes | NVIDIA API key. |
| **NVIDIA NIM** | `NVIDIA_BASE_URL` | Optional | Override base URL (default `https://integrate.api.nvidia.com/v1`). |
| **Cohere** | `COHERE_API_KEY` | Yes | Cohere API key. |
| **Google Vertex AI** | `GOOGLE_APPLICATION_CREDENTIALS` | One of these | Path to GCP service-account JSON file. |
| **Google Vertex AI** | `GOOGLE_ACCOUNT_FILE` | One of these | Alternative path variable read by some plugins. |
| **Google Vertex AI** | `PROJECT_ID` | Yes | GCP project ID. |
| **Google Vertex AI** | `LOCATION_ID` | Yes | GCP region, e.g. `us-central1`. |
| **Google Vertex AI** | `EMBEDDING_MODEL_NAME` | Yes | **Must be an embedding model** (e.g. `text-embedding-004`, `text-multilingual-embedding-002`). Do **not** set a generative model name here. |
| **Google Vertex AI** | `GCS_BUCKET_NAME` | Vector Search only | GCS bucket backing Vertex AI Vector Search. |
| **Google Vertex AI** | `GDRIVE_FOLDER_ID` | Optional | Google Drive folder ID for ingestion workflows. |
| **Google Vertex AI** | `PRIVATE_SC_IP` | Optional | Private Service Connect IP, if applicable. |
| **Anthropic Claude** | `ANTHROPIC_API_KEY` | Yes | `sk-ant-...` API key. |
| **Anthropic Claude** | `ANTHROPIC_BASE_URL` | Optional | Override base URL (e.g. for proxies). |
| **Google Gemini** | `GOOGLE_API_KEY` | Yes | Google AI Studio API key (different from Vertex AI). |
| **Mistral AI** | `MISTRAL_API_KEY` | Yes | Mistral API key. |
| **Mistral AI** | `MISTRAL_ENDPOINT` | Optional | Override base URL (default `https://api.mistral.ai`). |

### Vector database credentials

Set credentials only for the vector database matching `RETRIEVER_PLUGIN_ENTRY_POINT`. Other variables are ignored. Most plugins also require a matching `EMBEDDINGS_PLUGIN_ENTRY_POINT` whose model dimension matches the index.

| Vector DB | Variable | Required? | Description |
|---|---|---|---|
| **Zilliz Cloud** | `ZILLIZ_CLOUD_URI` | Yes | Endpoint URI from the Zilliz console. |
| **Zilliz Cloud** | `ZILLIZ_CLOUD_API_KEY` | Yes | API key from the Zilliz console. |
| **Milvus (self-hosted)** | `VECTORDB_URI` | Yes | e.g. `http://localhost:19530`. |
| **Milvus (self-hosted)** | `VECTORDB_TOKEN` | Yes (if auth enabled) | Milvus token. |
| **Azure AI Search** | `AZURE_COGNITIVE_SEARCH_SERVICE_NAME` | Yes | Search service name (not URL). |
| **Azure AI Search** | `AZURE_COGNITIVE_SEARCH_API_KEY` | Yes | Search admin or query key. |
| **Qdrant** | `QDRANT_URL` | Yes | e.g. `http://localhost:6333` or Qdrant Cloud URL. |
| **Qdrant** | `QDRANT_API_KEY` | Yes for Qdrant Cloud | Empty for local. |
| **PostgreSQL pgvector** | `PGVECTOR_CONNECTION_STRING` | Yes | `postgresql+psycopg://user:pass@host:5432/dbname`. |
| **MongoDB Atlas** | `MONGODB_ATLAS_CLUSTER_URI` | Yes | `mongodb+srv://user:pass@cluster.mongodb.net`. |
| **MongoDB Atlas** | `MONGODB_ATLAS_DB_NAME` | Yes | Database name. |
| **MongoDB Atlas** | `MONGODB_ATLAS_COLLECTION_NAME` | Yes | Collection name. |
| **MongoDB Atlas** | `MONGODB_ATLAS_INDEX_DIMENSIONS` | Yes | Must match the embedding model dimension (e.g. `1536` for `text-embedding-ada-002`). |
| **Vertex AI Vector Search** | *(uses Vertex AI credentials)* | — | See **LLM provider credentials → Google Vertex AI** above; also requires `GCS_BUCKET_NAME` and `EMBEDDING_MODEL_NAME`. |
| **Amazon Bedrock KBs** | *(uses AWS credentials)* | — | See **LLM provider credentials → AWS Bedrock** above. Requires IAM permissions `bedrock:Retrieve`, `bedrock:ListKnowledgeBases`, `bedrock:GetKnowledgeBase`, `bedrock:ListDataSources`. |

### Model category overrides

The orchestrator automatically selects a model from each provider for different task types. Defaults are set per provider in `.env.example`; override any of them with `<PROVIDER>_<CATEGORY>_MODEL` and `<PROVIDER>_<CATEGORY>_TEMPERATURE`.

Each category must be configured as a pair. If you set only `<PROVIDER>_<CATEGORY>_MODEL` without the matching `<PROVIDER>_<CATEGORY>_TEMPERATURE`, that category is treated as missing and can resolve to `UNCONFIGURED` at runtime.

Each plugin only reads variables matching its own provider prefix. For example, `AzureOpenAIPlugin` reads `AZURE_*` variables and ignores `OPENAI_*` ones; `OpenAIPlugin` does the opposite. If you switch providers and carry over category variables from the previous one, the new plugin will not see them and categories will fall back to defaults or `UNCONFIGURED`. When changing `MODEL_PLUGIN_ENTRY_POINT`, review and update all `<PROVIDER>_*_MODEL` and `<PROVIDER>_*_TEMPERATURE` variables to match the new provider prefix.

| Category | Used for | Example override |
|---|---|---|
| **fast** | Quick responses, summarization, title generation | `OPENAI_FAST_MODEL=gpt-4o-mini` |
| **large** | Complex reasoning, detailed responses | `OPENAI_LARGE_MODEL=gpt-4o` |
| **vision** | Image understanding and analysis | `OPENAI_VISION_MODEL=gpt-4o` |
| **code** | Code generation and analysis | `OPENAI_CODE_MODEL=gpt-4o` |
| **reasoning** | Multi-step analysis, advanced reasoning | `OPENAI_REASONING_MODEL=o1-preview` |

#### Default model + temperature per provider

Values shown in the table below are the suggested defaults from `.env.example` and the active defaults baked into `docker-compose.yml`. Override any cell with `<PROVIDER>_<CATEGORY>_MODEL` / `<PROVIDER>_<CATEGORY>_TEMPERATURE`. The provider prefix must match the plugin selected via `MODEL_PLUGIN_ENTRY_POINT` (see **LLM provider credentials** above for the prefix list).

| Provider | Prefix | fast | large | vision | code | reasoning |
|---|---|---|---|---|---|---|
| OpenAI | `OPENAI_` | `gpt-4o-mini` @ `0.3` | `gpt-4o` @ `0.2` | `gpt-4o` @ `0.1` | `gpt-4o` @ `0.0` | `o1-preview` @ `1.0` |
| Azure OpenAI | `AZURE_` | `gpt-4o-mini` @ `0.3` | `gpt-4o` @ `0.2` | `gpt-4o` @ `0.1` | `gpt-4o` @ `0.0` | `o1-preview` @ `1.0` |
| AWS Bedrock | `BEDROCK_` | `anthropic.claude-3-haiku-20240307-v1:0` @ `0.3` | `anthropic.claude-3-5-sonnet-20241022-v2:0` @ `0.2` | `anthropic.claude-3-5-sonnet-20241022-v2:0` @ `0.1` | `anthropic.claude-3-5-sonnet-20241022-v2:0` @ `0.0` | `anthropic.claude-3-5-sonnet-20241022-v2:0` @ `1.0` |
| Ollama | `OLLAMA_` | `llama3.2:3b` @ `0.3` | `llama3.1:8b` @ `0.2` | `llama3.2-vision:11b` @ `0.1` | `codellama:13b` @ `0.0` | `llama3.1:70b` @ `1.0` |
| Anthropic Claude | `ANTHROPIC_` | `claude-3-5-haiku-20241022` @ `0.3` | `claude-sonnet-4-20250514` @ `0.2` | `claude-sonnet-4-20250514` @ `0.1` | `claude-sonnet-4-20250514` @ `0.0` | `claude-sonnet-4-20250514` @ `0.1` |
| Google Gemini | `GEMINI_` | `gemini-2.0-flash` @ `0.3` | `gemini-2.5-pro-preview-06-05` @ `0.2` | `gemini-2.5-pro-preview-06-05` @ `0.1` | `gemini-2.5-pro-preview-06-05` @ `0.0` | `gemini-2.5-flash-preview-05-20` @ `0.1` |
| Google Vertex AI | `VERTEXAI_` | `gemini-2.0-flash` @ `0.3` | `gemini-2.5-pro-preview-06-05` @ `0.2` | `gemini-2.5-pro-preview-06-05` @ `0.1` | `gemini-2.5-pro-preview-06-05` @ `0.0` | `gemini-2.5-flash-preview-05-20` @ `0.1` |
| Mistral AI | `MISTRAL_` | `mistral-small-latest` @ `0.3` | `mistral-large-latest` @ `0.2` | `mistral-large-latest` @ `0.1` | `codestral-latest` @ `0.0` | `mistral-large-latest` @ `0.1` |
| Cohere | `COHERE_` | `command-r` @ `0.3` | `command-r-plus` @ `0.2` | `command-r-plus` @ `0.1` | `command-r-plus` @ `0.0` | `command-r-plus` @ `0.1` |
| NVIDIA NIM | `NVIDIA_` | `meta/llama-3.1-8b-instruct` @ `0.3` | `meta/llama-3.1-70b-instruct` @ `0.2` | `meta/llama-3.2-90b-vision-instruct` @ `0.1` | `meta/codellama-70b` @ `0.0` | `meta/llama-3.1-70b-instruct` @ `0.1` |

> **GPT-5.x / o-series temperature requirement.** These models accept only `temperature=1.0`. Override the relevant `*_TEMPERATURE` variables accordingly — see **[Appendix A](#appendix-a--other-llm-provider-configurations) — Azure OpenAI**.

#### GPT-5+ / o-series deployment flag

GPT-5 (and later) and o-series (`o1`, `o3`, `o4`, ...) deployments use the post-Sep-2024 OpenAI Chat Completions contract: they require `max_completion_tokens` (not `max_tokens`) and reject any `temperature` other than the API default (1.0). Set the following flag whenever your OpenAI or Azure OpenAI deployment is one of these models:

| Variable | Default | Description |
|---|---|---|
| `OPENAI_GPT5_COMPATIBLE` | `false` | Set to `true` when your OpenAI / Azure OpenAI deployment is GPT-5 (or later) or any o-series model. When `true`, the orchestrator binds `max_completion_tokens` on every LLM call and omits `temperature` from the model constructor (so the API default of 1.0 applies). Leave `false` for GPT-4o-family and earlier deployments. The flag is read at startup and applied to every category (fast / large / vision / code / reasoning). |

If the flag is left unset but the configured model name looks like a GPT-5+ or o-series deployment (e.g., starts with `gpt-5`, `o1`, `o3`, or `o4`), the orchestrator logs a one-line `WARN` at model-construction time as a diagnostic hint. The flag value is still authoritative — the warning never changes behaviour.

### Application variables

| Variable | Default | Description |
|---|---|---|
| `LOG_LEVEL` | `INFO` | Logging verbosity: `DEBUG`, `INFO`, `WARNING`, `ERROR`. |
| `ORCHESTRATOR_INTERNAL_URL` | `http://orchestrator:8080` | URL used by admin console to reach the orchestrator. |
| `CORS_ALLOWED_ORIGINS` | `http://localhost:8081,http://localhost:3000` | Comma-separated list of origins allowed to make cross-origin requests. **Must be set in production** — include every domain that hosts a Spotfire client or custom UI that calls the API. Both the orchestrator and admin console read this variable. |

### Database variables

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | *(constructed by docker-compose on-prem, or set directly for cloud)* | Async PostgreSQL connection string (`postgresql+asyncpg://...`). |
| `SYNC_DATABASE_URL` | *(constructed by docker-compose on-prem, or set directly for cloud)* | Sync PostgreSQL connection string (`postgresql://...`). |
| `DB_SSLMODE` | *(driver default)* | PostgreSQL SSL mode: `disable`, `require`, `verify-ca`, `verify-full`. |

### Knowledge base / RAG variables

| Variable | Default | Description |
|---|---|---|
| `DEFAULT_RAG_TOPK` | `10` | Number of chunks retrieved per query. |
| `DEFAULT_RAG_SCORE_THRESHOLD` | `0.5` | Minimum relevance score. |
| `DEFAULT_RAG_RETRIEVER_TYPE` | `vector-store` | Retriever strategy. |
| `RAG_COLLECTIONS_METADATA` | *(empty)* | Static JSON array of index definitions. Used as a fallback for retrievers that cannot auto-list their indexes (notably Amazon Bedrock Knowledge Bases). Merged with auto-discovered indexes; auto-discovered entries win on name conflicts. |
| `PGVECTOR_CONNECTION_STRING` | — | PostgreSQL pgvector connection string (only for pgvector plugin). Format: `postgresql+psycopg://user:pass@host:5432/dbname` |

### Summarization variables

| Variable | Default | Description |
|---|---|---|
| `ENABLE_THREAD_SUMMARIZATION` | `true` | Generate thread titles after first exchange. |
| `ENABLE_PROGRESSIVE_SUMMARIZATION` | `true` | Compress context when conversations grow long. |
| `ENABLE_BACKGROUND_SUMMARIZATION` | `true` | Run the summarization daemon. |
| `SUMMARIZER_MAX_TOKENS` | `4096` | Maximum tokens for summary generation. |

### LangSmith tracing (optional)

| Variable | Default | Description |
|---|---|---|
| `LANGCHAIN_TRACING_V2` | `false` | Enable LangSmith tracing. |
| `LANGCHAIN_ENDPOINT` | `https://api.smith.langchain.com` | LangSmith API endpoint. |
| `LANGCHAIN_API_KEY` | — | LangSmith API key. |
| `LANGCHAIN_PROJECT` | — | LangSmith project name. |

### Conversation retention (2.3.1)

Introduced in 2.3.1. Controls the background cleanup daemon that deletes old conversation threads.

| Variable | Default | Description |
|---|---|---|
| `CONVERSATION_RETENTION_DAYS` | *(unset — disabled)* | Automatically delete conversations older than this many days. Set to `0` or leave unset to keep conversations indefinitely. When enabled, the daemon runs daily at 03:00 UTC and cascades the delete across messages, artifacts, feedback, and validation records. Surface via admin API at `GET /threads/retention/status`, `GET /threads/retention/preview`, `POST /threads/retention/cleanup`. |

### WebSocket tunnel — developer agent containers (2.3.1)

Introduced in 2.3.1. Enables locally-running agent containers to register with a deployed orchestrator via a reverse WebSocket tunnel (`/tunnel/connect`). Tunnel clients must hold the `agents:write` OAuth2 scope.

| Variable | Default | Description |
|---|---|---|
| `TUNNEL_ENABLED` | `false` | Enable the `/tunnel/connect` WebSocket endpoint. Leave disabled in production deployments that do not need developer-agent passthrough. |
| `TUNNEL_MAX_CONNECTIONS_PER_CLIENT` | `5` | Maximum concurrent tunnel WebSocket connections per OAuth2 client. |
| `TUNNEL_MAX_AGENTS_PER_CLIENT` | `20` | Maximum total tunneled agents across all connections per OAuth2 client. |
| `TUNNEL_REQUEST_TIMEOUT` | `120` | Timeout (seconds) for a proxied request sent through the tunnel. |
| `TUNNEL_PING_INTERVAL` | `30` | WebSocket ping interval (seconds). |
| `TUNNEL_PONG_TIMEOUT` | `60` | Drop the tunnel connection if no pong is received within this many seconds. |

---

> **Canonical source.** The `.env.example` file shipped with the orchestrator distribution is the canonical, comment-annotated list of every variable the orchestrator reads, with inline guidance, example values, and lifecycle notes (especially for the bootstrap-credential variables). The tables above reorganise that content by purpose; when in doubt or when looking for a variable that doesn't appear here, consult `.env.example` from the distribution.

---

## 12. Troubleshooting

### Authentication errors

| Symptom | Cause | Fix |
|---|---|---|
| `401 Unauthorized` on every request | Missing or expired token | Re-authenticate (see **[§9](#9-authentication-guide) Authentication Guide**) |
| OAuth2 client credentials become invalid after pod or container restart | Running v2.1.0 or earlier, which stored OAuth2 clients in memory only | Upgrade to v2.3.0 or later — OAuth2 clients are persisted in PostgreSQL and survive restarts. On v2.3+, set `OAUTH2_CLIENT_ID` and `OAUTH2_CLIENT_SECRET_HASH` as environment variables at startup so the client is always seeded (see **[§3](#3-step-1--generate-credentials) Generate Credentials**). |
| Login fails with correct password | Bcrypt hash corrupted by `$` interpolation | On-premise: wrap in single quotes in `.env`. Cloud: ensure your secrets store is passing the value verbatim (Key Vault, Secrets Manager, and K8s Secrets handle `$` correctly). |
| `AssumeRoleWithWebIdentity` error on GCP | Plugin set to OpenAI/Bedrock but running on GCP | Change plugin to Gemini or Vertex AI (see **[§4](#4-step-2--choose-and-configure-your-llm-provider) Choose and Configure Your LLM Provider**) |

### RAG endpoint access issues

| Symptom | Cause | Fix |
|---|---|---|
| `403 Forbidden` on `POST /rag/query`, while token issuance succeeds and token contains `rag` scope | Path-specific network policy in front of the orchestrator (commonly AWS ALB / API Gateway / WAF / NACL) is intercepting or rejecting `/rag/query` before the request reaches the container | Verify path routing and security policy for `/rag/query` end-to-end. Confirm `POST` and `OPTIONS` are allowed, preserve the `Authorization: Bearer` header through all proxy hops, and ensure path rewrites still forward `/rag/query` to the orchestrator service on port `8080`. |

When investigating this scenario, use this checklist:

1. Compare direct and front-door behavior from the same network path: call `/rag/query` directly against the orchestrator service URL and again through the customer-facing load balancer/API gateway URL.
2. Correlate timestamps across Analyst and orchestrator logs. If Analyst shows 403 but orchestrator has no matching `/rag/query` request at that time, the block is upstream of the orchestrator.
3. Review AWS load balancer and gateway configuration for path rules, method allow-lists, header forwarding, base-path mappings, and rewrite rules that treat `/rag/query` differently from `/orchestrator`.
4. Review AWS WAF logs and rule matches (managed and custom) for blocked `/rag/query` requests.
5. Review security groups and network ACLs for asymmetrical rules that allow auth/token endpoints but deny or interrupt the RAG path.
6. Validate Spotfire client connection settings: use the orchestrator base URL (not an endpoint-specific path), then let the client call `/rag/query` under that base URL.

This issue has been observed in traditional on-premise installs hosted on AWS where the orchestrator itself was healthy and OAuth scopes were correct, but `/rag/query` was blocked at the load balancer layer.

### Container startup issues

| Symptom | Cause | Fix |
|---|---|---|
| Orchestrator exits immediately | Missing `SECRET_KEY` | Ensure `SECRET_KEY` is set in your environment (secrets store or `.env`) |
| Orchestrator container keeps restarting | Health probe hitting `/health` instead of `/` | The orchestrator has **no `/health` endpoint**. Set the health check path to **`/`** on port 8080. See **[§7](#7-step-5--verify-and-first-login) Health check endpoints**. |
| Admin console health check fails with 302 | Health probe hitting `/` instead of `/health` | The admin console root path (`/`) redirects to `/login` (HTTP 302), which most health checkers treat as a failure. Set the health check path to **`/health`** on port 8081. |
| PostgreSQL not healthy | Wrong password or port conflict | On-premise: `docker compose logs orchestrator-postgres`. Cloud: check managed DB instance status and firewall rules. |
| Admin console returns 404 | Wrong target port | Set ingress/target port to `8081` (not `8080`) |
| Admin console starts orchestrator instead | Missing startup command override | Set command to `python /app/admin_console/admin_main.py` |
| Admin console health check passes but no UI is visible in the browser | Accessing the wrong path or port | The admin console UI is a full web interface served on port `8081`. Browse to `http://<host>:8081/` — this redirects to `/login`. If you see only a JSON response or a redirect you are likely hitting the orchestrator on port `8080` instead. |
| Container cannot reach database (cloud) | VPC/security group misconfiguration | Ensure the container's network/VPC can route to the managed PostgreSQL instance. Check security groups, firewall rules, and VPC peering. |

### Database issues

| Symptom | Cause | Fix |
|---|---|---|
| `connection refused` | PostgreSQL not started or not reachable | On-premise: wait for postgres health check. Cloud: verify managed DB endpoint, SSL mode, and network connectivity. |
| `SSL connection required` | Managed PostgreSQL enforces SSL | Set `DB_SSLMODE=require` in your environment variables |
| DNS resolution failure on Azure | Azure Container Apps DNS race condition | The orchestrator retries DNS at startup automatically — check logs |
| Migration errors | Stale migration state | Run `alembic upgrade head` in the orchestrator container |

### LLM provider issues

| Symptom | Cause | Fix |
|---|---|---|
| `AuthenticationError` | API key doesn't match plugin | Verify that `MODEL_PLUGIN_ENTRY_POINT` matches your API key provider |
| `Warning: Missing configuration for AZURE fast category`, requests to `/deployments/UNCONFIGURED/chat/completions`, and `DeploymentNotFound` | Azure model-category env vars are incomplete; the enhanced plugin loads a category only when both `AZURE_<CATEGORY>_MODEL` and `AZURE_<CATEGORY>_TEMPERATURE` are set | Set complete pairs for every category you use, especially `AZURE_FAST_MODEL` + `AZURE_FAST_TEMPERATURE` (summarization/title generation uses `fast`). Keep `MODEL_PLUGIN_ENTRY_POINT=plugins.models.azure_openai_enhanced:AzureOpenAIPlugin` and verify deployment names exactly match Azure deployment names |
| `DeploymentNotFound` with a non-`UNCONFIGURED` deployment in the request URL | The configured Azure deployment name does not exist in that Azure OpenAI resource (typo, deleted deployment, wrong environment/resource, or propagation delay right after creation) | Verify every configured deployment value exists in the same Azure OpenAI resource and matches exactly (`AZURE_FAST_MODEL`, `AZURE_LARGE_MODEL`, `AZURE_VISION_MODEL`, `AZURE_CODE_MODEL`, `AZURE_REASONING_MODEL`, and any `*_MODEL_NAME` overrides). If the deployment was just created, wait a few minutes and retry. |
| `The model associated with the deployment is deprecated and no longer available for use` | The model version backing an Azure deployment has been retired by Microsoft. This error comes directly from Azure and is unrelated to the Copilot version. The same request would fail on any Copilot version once the underlying model is retired. | In Azure AI Studio, check the status of the affected deployment. Either update it to a supported model version in-place, or create a new deployment with a currently active model and update your `AZURE_*_MODEL` env vars to reference the new deployment name. |
| `Rate limit exceeded` | LLM provider rate limit | This error comes from the upstream LLM provider (OpenAI, Bedrock, etc.), not from the orchestrator. Reduce request frequency or increase your provider's rate limits. The orchestrator itself rate-limits only auth endpoints (5/min for admin login, 20/min for client tokens). |
| Timeout on first request | Model cold start (Bedrock, Vertex AI) | First request may take 10-30 seconds — subsequent requests are faster |
| IAM/role errors on AWS | Explicit keys override IAM role | Remove `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from the task definition — only set `AWS_REGION` |

### Useful diagnostic commands

```bash
# ── On-premise (Docker Compose) ──────────────────────────────────
docker compose ps
docker compose logs orchestrator | head -50
docker compose exec orchestrator alembic current

# ── Kubernetes ───────────────────────────────────────────────────
kubectl -n copilot get pods
kubectl -n copilot logs deployment/orchestrator --tail=50
kubectl -n copilot exec deployment/orchestrator -- alembic current

# ── Cloud (any platform) ─────────────────────────────────────────
# Verify health endpoints (replace with your actual URLs)
curl -s https://<ORCHESTRATOR_HOST>/ | python -m json.tool
curl -s https://<CONSOLE_HOST>/health | python -m json.tool
```

---

## 13. Upgrading from Previous Versions

### Migrating from the single-container architecture

If you are upgrading from an earlier version of the Copilot backend that used a single orchestrator container without PostgreSQL:

#### What has changed

| Before | After |
|---|---|
| Single `orchestrator` container | Two or three containers: orchestrator + PostgreSQL + admin console (optional) |
| In-memory conversation state | Persistent PostgreSQL database |
| `plugins.models.openai:OpenAIPlugin` | `plugins.models.openai_enhanced:OpenAIPlugin` (enhanced variants) |
| `VECTORDB_PLUGIN_ENTRY_POINT` | `RETRIEVER_PLUGIN_ENTRY_POINT` (knowledge base) |
| No admin console | Optional admin console on port 8081 (highly recommended for production) |
| No database migrations | Automatic Alembic migrations on startup |
| `bcrypt-generator.com` for password hashing | `generate_credentials.py` (offline, secure) |
| `openssl rand -hex 32` for SECRET_KEY | `generate_credentials.py` generates everything |
| No `SECONDARY_MODEL_PLUGIN_ENTRY_POINT` | Now required at startup — **set to the same value as `MODEL_PLUGIN_ENTRY_POINT`**. Not used by clients at runtime (deprecated feature). |
| No model categories | Five categories per provider (fast, large, vision, code, reasoning) |

#### Upgrade steps

1. **Back up your `.env` file** — you will need to update several variables
2. **Update plugin entry points** — change `plugins.models.openai:OpenAIPlugin` to `plugins.models.openai_enhanced:OpenAIPlugin` (and similarly for other providers)
3. **Rename `VECTORDB_PLUGIN_ENTRY_POINT`** to `RETRIEVER_PLUGIN_ENTRY_POINT`
4. **Add `SECONDARY_MODEL_PLUGIN_ENTRY_POINT`** — set it to the same value as `MODEL_PLUGIN_ENTRY_POINT`
5. **Add `POSTGRES_PASSWORD`** — choose a database password
6. **Generate new credentials** — run `python generate_credentials.py` and update your `.env`
7. **Use the new `docker-compose.yml`** — the old single-service compose file is replaced
8. **Start the services** — `docker compose up -d` — Alembic will create all database tables automatically

> **Note:** Conversation history from the single-container version is not migrated (it was
> in-memory only). The PostgreSQL database starts fresh.

---

## 14. Security Best Practices

### Credential management

- **Never embed secrets in container images or source control** — use your cloud platform's secrets manager (Azure Key Vault, GCP Secret Manager, AWS Secrets Manager) or Kubernetes Secrets
- **Use `generate_credentials.py`** for all password hashing — never use online tools
- **Rotate credentials regularly** — regenerate with `generate_credentials.py --admin-only`, update your secrets store, and restart
- **Store plaintext passwords in a vault** — not in files, not in chat history
- **`.env` files are for on-premise only** — in cloud deployments, use the platform's native environment variable and secrets management

### Container security

- **Keep Docker images up to date** — always deploy the latest official Copilot Docker images
- **Run containers as non-root** — the Copilot image already runs as a non-root user
- **Limit container resources** — set memory and CPU limits to prevent resource exhaustion
- **Use network isolation** — the `docker-compose.yml` uses a dedicated bridge network

### Network security

- **Enable TLS** — in cloud deployments, TLS is terminated by the platform; for on-premise, place a reverse proxy (nginx, Traefik) in front of the containers
- **Restrict port access** — PostgreSQL is bound to `127.0.0.1:5432` in the production compose file (not accessible from outside the host)
- **Use CORS** — set `CORS_ALLOWED_ORIGINS` to a comma-separated list of your actual client domains (e.g., `https://spotfire.example.com,https://admin.example.com`). The default (`http://localhost:8081,http://localhost:3000`) only allows local access. Both the orchestrator and admin console read this variable. If browsers report CORS 403 errors, this is usually the cause
- **Use DB SSL** — set `DB_SSLMODE=require` for managed PostgreSQL instances

### Authentication security

- **Use OAuth2 client credentials** for all programmatic access — not the admin password
- **The admin account is for administration only** — create dedicated OAuth2 clients for applications
- **Account lockout is enabled by default** — failed login attempts trigger exponential backoff
- **Token revocation** — revoked tokens are tracked in the database; they cannot be reused

### Monitoring

- **Check container logs** — both services log to stdout (captured by Docker's json-file driver)
- **Enable LangSmith tracing** for LLM request visibility (set `LANGCHAIN_TRACING_V2=true`)
- **Use the admin console** *(if deployed)* — it provides conversation analytics, system health, and user activity monitoring
- **Conduct regular security audits** of your deployment configuration

---

## Appendix A — Other LLM Provider Configurations

> Drop-in replacements for the OpenAI block in **[§4](#4-step-2--choose-and-configure-your-llm-provider) Choose and Configure Your LLM Provider**. Pick one provider, copy its block into your `.env` (or the equivalent cloud secret store), and the orchestrator will use it instead of OpenAI. The `SECONDARY_MODEL_PLUGIN_ENTRY_POINT` warning from [§4](#4-step-2--choose-and-configure-your-llm-provider) applies to every block here — keep it equal to `MODEL_PLUGIN_ENTRY_POINT`.

### Azure OpenAI

```bash
# Plugin
MODEL_PLUGIN_ENTRY_POINT=plugins.models.azure_openai_enhanced:AzureOpenAIPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.azure_openai_enhanced:AzureOpenAIPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.az_openai:AzOpenAIEmbeddingsPlugin

# Credentials
OPENAI_API_TYPE=azure
OPENAI_API_KEY=your-azure-openai-key
AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com/
OPENAI_API_VERSION=2024-02-15-preview
```

> **Note:** Azure OpenAI uses **deployment names** as model names. Your model names
> must match the deployment names you configured in the Azure portal.

> **Category variables must be set as pairs.** Each category is only active when both `AZURE_<CATEGORY>_MODEL` and `AZURE_<CATEGORY>_TEMPERATURE` are present. A missing temperature causes that category to be silently dropped and fall back to `UNCONFIGURED`.

> **o1 and GPT-5.x models require `temperature=1.0`.** If you are using an o1 or GPT-5.x deployment for any category, set the corresponding temperature to `1.0` — not the standard defaults. For example, if all categories point to the same GPT-5.x deployment:
> ```bash
> AZURE_FAST_TEMPERATURE=1.0
> AZURE_LARGE_TEMPERATURE=1.0
> AZURE_VISION_TEMPERATURE=1.0
> AZURE_CODE_TEMPERATURE=1.0
> AZURE_REASONING_TEMPERATURE=1.0
> ```
> Standard models (GPT-4o, GPT-4o-mini) use the defaults shown in **[§11](#11-environment-variable-reference) Environment Variable Reference → Model category overrides**.

> **GPT-5+ and o-series deployments (requires 2.3.4 or later).** GPT-5 (and later) and o-series (`o1`, `o3`, `o4`, ...) Azure deployments use the post-Sep-2024 OpenAI Chat Completions contract: they reject the legacy `max_tokens` parameter (requiring `max_completion_tokens` instead) and reject any `temperature` other than the API default (1.0). **Backend 2.3.4** handles both differences when you set `OPENAI_GPT5_COMPATIBLE=true` in the orchestrator environment — it then binds `max_completion_tokens` on every LLM call and omits `temperature` from the `AzureChatOpenAI` constructor. Leave the variable unset (or `false`) for GPT-4o-family and earlier deployments. The flag applies uniformly to every category (fast / large / vision / code / reasoning), regardless of whether the Azure deployment name reveals the underlying model family. **Backend 2.3.2 and earlier do not support GPT-5+ or o-series deployments** — every request that includes a token limit (which the Spotfire client and the background summarizer both do) will fail with `Unsupported parameter: 'max_tokens' is not supported with this model. Use 'max_completion_tokens' instead.` Upgrade to 2.3.4 to use these models.

**Which Spotfire Copilot feature uses which model category:**

| Category | Used by |
|---|---|
| **fast** | Thread title generation, background summarization, RAG index enrichment |
| **large** | General chat, data analysis, most Copilot panel interactions |
| **vision** | Explain Visualization, image/chart analysis, any request containing an image |
| **code** | Data function generation, SQL generation, code review |
| **reasoning** | Complex multi-step analysis, research-style queries |

If a feature fails with `DeploymentNotFound` and other interactions work fine, check which category that feature uses in the table above and verify the corresponding `AZURE_<CATEGORY>_MODEL` and `AZURE_<CATEGORY>_TEMPERATURE` are both set correctly.

---

### Google Gemini (API Key — Simplest Google Option)

```bash
# Plugin
MODEL_PLUGIN_ENTRY_POINT=plugins.models.gemini_enhanced:GeminiPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.gemini_enhanced:GeminiPlugin

# Credentials
GOOGLE_API_KEY=your-google-ai-api-key

# ⚠️ Comment out OpenAI lines if present:
# OPENAI_API_TYPE=openai
# OPENAI_API_KEY=...
```

Default models: `gemini-2.0-flash` (fast), `gemini-2.5-pro-preview-06-05` (large/vision/code), `gemini-2.5-flash-preview-05-20` (reasoning).

> **Gemini vs Vertex AI:** Use Gemini when you want simple API-key authentication and
> don't need a full GCP project. Use Vertex AI when running on GCP with service account
> credentials and project-based billing.

---

### Google Vertex AI (GCP Service Account — Recommended for GCP)

```bash
# Plugin
MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai_enhanced:VertexAIPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai_enhanced:VertexAIPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.vertexai:VertexAIEmbeddingsPlugin

# Credentials
PROJECT_ID=your-gcp-project-id
LOCATION_ID=us-central1
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json

# Embedding model (MUST be an embedding model, not a generative model)
EMBEDDING_MODEL_NAME=text-embedding-004

# ⚠️ Comment out OpenAI lines if present:
# OPENAI_API_TYPE=openai
# OPENAI_API_KEY=...
```

> **Important:** `EMBEDDING_MODEL_NAME` must be set to a valid embedding model like
> `text-embedding-004`. Do NOT use a generative model name (e.g., `gemini-*`) — the
> VertexAI embeddings plugin will reject it.

---

### AWS Bedrock

```bash
# Plugin
MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock_enhanced:BedrockPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock_enhanced:BedrockPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.bedrock:BedrockEmbeddingsPlugin

# Credentials — choose ONE method:

# Method 1: Explicit keys (local development)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key

# Method 2: Named profile (local development)
# AWS_REGION=us-east-1
# AWS_PROFILE_NAME=your-profile

# Method 3: IAM role (ECS, EC2) — RECOMMENDED for production
# AWS_REGION=us-east-1
# Don't set AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY — they override the IAM role
```

> **⚠️ ECS/EC2 IAM roles:** When running on ECS or EC2 with an IAM role, do NOT set
> `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`. These override the IAM role and
> cause authentication failures. Just set `AWS_REGION`.

Default models: `claude-3-haiku` (fast), `claude-3.5-sonnet` (large/vision/code/reasoning).

Required IAM permissions:
```
bedrock:InvokeModel
bedrock:InvokeModelWithResponseStream
```

---

### Anthropic Claude

```bash
# Plugin
MODEL_PLUGIN_ENTRY_POINT=plugins.models.anthropic_enhanced:AnthropicPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.anthropic_enhanced:AnthropicPlugin

# Credentials
ANTHROPIC_API_KEY=sk-ant-your-anthropic-api-key
```

Default models: `claude-3-5-haiku` (fast), `claude-sonnet-4` (large/vision/code/reasoning).

---

### Mistral AI

```bash
# Plugin
MODEL_PLUGIN_ENTRY_POINT=plugins.models.mistral_enhanced:MistralPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.mistral_enhanced:MistralPlugin

# Credentials
MISTRAL_API_KEY=your-mistral-api-key
# MISTRAL_ENDPOINT=https://api.mistral.ai  # optional, for self-hosted or Azure AI
```

Default models: `mistral-small-latest` (fast), `mistral-large-latest` (large/vision/reasoning), `codestral-latest` (code).

---

### Ollama (Local / Self-Hosted)

```bash
# Plugin
MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama_enhanced:OllamaPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama_enhanced:OllamaPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.ollama:OllamaEmbeddingsPlugin

# Credentials
OLLAMA_BASE_URL=http://host.docker.internal:11434

# Embedding model (must be pulled on your Ollama instance)
EMBEDDING_MODEL_NAME=nomic-embed-text
```

> **Docker note:** Use `host.docker.internal` to reach Ollama running on the Docker host.
> On Linux without Docker Desktop, use `http://172.17.0.1:11434` instead.

> **Important:** `OLLAMA_BASE_URL` is used by **both** the LLM model plugin and the
> embeddings plugin. If Ollama is running on a remote host (not `localhost`), you must
> set this variable — otherwise embeddings will fail with a connection error.
> You must also pull the embedding model on your Ollama instance:
> `ollama pull nomic-embed-text`

Default models: `llama3.2:3b` (fast), `llama3.1:8b` (large), `llama3.2-vision:11b` (vision), `codellama:13b` (code), `llama3.1:70b` (reasoning).

---

### Cohere

```bash
# Plugin
MODEL_PLUGIN_ENTRY_POINT=plugins.models.cohere_enhanced:CoherePlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.cohere_enhanced:CoherePlugin

# Credentials
COHERE_API_KEY=your-cohere-api-key
```

---

### NVIDIA NIM

```bash
# Plugin
MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.nvidia_nim:NvidiaNimEmbeddingsPlugin

# Credentials
NVIDIA_API_KEY=your-nvidia-api-key
NVIDIA_BASE_URL=https://integrate.api.nvidia.com/v1
```

---

## Appendix B — Other Knowledge Base Configurations

> Drop-in replacements for the Zilliz Cloud block in **[§5](#5-step-3--configure-your-knowledge-base) Configure Your Knowledge Base**. Each block sets `RETRIEVER_PLUGIN_ENTRY_POINT` plus that provider's credentials — nothing else in [§5](#5-step-3--configure-your-knowledge-base) changes. The pgvector entry has additional setup requirements (extension install, role / database SQL, performance tuning) documented in **[Appendix C](#appendix-c--self-hosted-pgvector-setup) — Self-hosted pgvector setup**.

**Milvus (self-hosted):**
```bash
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.milvus:MilvusRetrieverPlugin
VECTORDB_URI=http://localhost:19530
VECTORDB_TOKEN=your-milvus-token
```

**Qdrant:**
```bash
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.qdrant:QdrantRetrieverPlugin
QDRANT_URL=http://localhost:6333
QDRANT_API_KEY=your-qdrant-api-key  # leave empty for local
```

**MongoDB Atlas:**
```bash
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.mongo:MongoRetrieverPlugin
MONGODB_ATLAS_CLUSTER_URI=mongodb+srv://user:pass@cluster.mongodb.net
MONGODB_ATLAS_DB_NAME=your-db-name
MONGODB_ATLAS_COLLECTION_NAME=your-collection
MONGODB_ATLAS_INDEX_DIMENSIONS=1536
```

**Redis:**
```bash
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.redis:RedisRetrieverPlugin
REDIS_URL=redis://your-redis-host:6379
```

**Azure Cognitive Search:**
```bash
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.az_cog_search:AzCognitiveSearchRetrieverPlugin
AZURE_COGNITIVE_SEARCH_SERVICE_NAME=your-search-service-name
AZURE_COGNITIVE_SEARCH_API_KEY=your-search-api-key
```

**Vertex AI Vector Search:**
```bash
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin
PROJECT_ID=your-gcp-project-id
LOCATION_ID=us-central1
GCS_BUCKET_NAME=your-gcs-bucket-name
# PRIVATE_SC_IP=10.0.0.1  # Optional — set if using Private Service Connect
```

**AWS Bedrock Knowledge Bases:**
```bash
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.amazon_kbs:AmazonKBsRetrieverPlugin
AWS_REGION=us-east-1
# Uses same AWS credentials as the Bedrock LLM plugin (IAM role recommended)
```

Additional IAM permissions for Knowledge Bases:
```
bedrock:Retrieve                  — retrieve documents
bedrock:ListKnowledgeBases        — auto-discover KBs (recommended)
bedrock:GetKnowledgeBase          — fetch KB metadata (recommended)
bedrock:ListDataSources           — show data sources in admin console (optional)
```

**Databricks:**
```bash
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.databricks:DatabricksRetrieverPlugin
DATABRICKS_HOST=https://your-workspace.cloud.databricks.com
DATABRICKS_TOKEN=your-databricks-token
DATABRICKS_ENDPOINT=your-vector-search-endpoint
DATABRICKS_TEXT_COLUMN=content
DATABRICKS_COLUMNS=content,source,title
```

**PostgreSQL pgvector:**
```bash
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.pgvector:PgVectorRetrieverPlugin
PGVECTOR_CONNECTION_STRING=postgresql+psycopg://user:password@pgvector-host:5432/vectordb
```

> pgvector requires PostgreSQL 15 or 16 with the `vector` extension installed. For full setup instructions (extension install, role / database SQL, performance tuning, sizing reference) see **[Appendix C](#appendix-c--self-hosted-pgvector-setup) — Self-hosted pgvector setup**.
>
> For managed PostgreSQL services:
> - **Azure:** Enable the extension via `az postgres flexible-server parameter set --name azure.extensions --value vector`
> - **AWS RDS:** Add `pgvector` to the shared_preload_libraries in the parameter group
> - **GCP Cloud SQL:** Enable via the Extensions page in the Cloud Console

---

## Appendix C — Self-hosted pgvector setup

> **Use this appendix** if you want to use PostgreSQL pgvector as your knowledge base on existing infrastructure — without Docker or a cloud-managed service. This is a **separate database** from the orchestrator's application database described in **[§6.6](#66-using-your-own-postgresql-server-no-docker)**.

### Prerequisites

- PostgreSQL **15** or **16** with the `vector` extension available
- Superuser access (required to `CREATE EXTENSION`)
- Sufficient RAM for HNSW indexes (see sizing table below)

### Install the pgvector extension

If pgvector is not already installed on your PostgreSQL server:

```bash
# ── From source (any Linux) ──────────────────────────────────────
cd /tmp
git clone --branch v0.8.0 https://github.com/pgvector/pgvector.git
cd pgvector
make
sudo make install    # installs to your PostgreSQL extension directory

# ── Package managers ─────────────────────────────────────────────
# Debian/Ubuntu (PostgreSQL 16)
sudo apt install postgresql-16-pgvector

# RHEL/Rocky/Alma (from PGDG repo)
sudo dnf install pgvector_16

# macOS (Homebrew)
brew install pgvector
```

After installation, restart PostgreSQL if required by your OS/package manager.

### Create the vector database

Connect as superuser and run:

```sql
-- 1. Create a dedicated role (separate from the orchestrator app role)
CREATE ROLE copilot_vector WITH LOGIN PASSWORD 'your-secure-password';

-- 2. Create a dedicated database for vector data
CREATE DATABASE copilot_vectordb OWNER copilot_vector;

-- 3. Connect to the new database
\c copilot_vectordb

-- 4. Install the pgvector extension (requires superuser)
CREATE EXTENSION IF NOT EXISTS vector;

-- 5. Grant permissions
GRANT ALL PRIVILEGES ON SCHEMA public TO copilot_vector;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO copilot_vector;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO copilot_vector;
```

### Verify the extension

```sql
\c copilot_vectordb
SELECT extversion FROM pg_extension WHERE extname = 'vector';
-- Should return: 0.8.0 (or your installed version)
```

### Configure the orchestrator

```bash
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.pgvector:PgVectorRetrieverPlugin
PGVECTOR_CONNECTION_STRING=postgresql+psycopg://copilot_vector:your-secure-password@your-pg-host:5432/copilot_vectordb
```

### Performance tuning

Add these to your `postgresql.conf` (adjust based on available RAM):

```ini
# Memory — allow large HNSW index builds
maintenance_work_mem = 2GB          # increase for large index creation
shared_buffers = 4GB                # 25% of total RAM is a good starting point
effective_cache_size = 12GB         # 75% of total RAM

# Parallelism — speed up index creation and queries
max_parallel_workers_per_gather = 4
max_parallel_maintenance_workers = 4

# WAL — reduce I/O during bulk loads
wal_level = minimal                 # only during initial data load, revert to 'replica' after
max_wal_senders = 0                 # only during initial data load
```

> **After loading data**, revert `wal_level` to `replica` and set `max_wal_senders` back to your normal replication configuration, then restart PostgreSQL.

### Sizing reference

| Workload | Vectors | RAM (minimum) | Storage | Notes |
|---|---|---|---|---|
| Small / POC | < 50K | 4 GiB | 20 GB | Default settings acceptable |
| Medium | 50K–500K | 16 GiB | 100 GB | HNSW index; tune `maintenance_work_mem` |
| Large | 500K–2M | 32+ GiB | 500 GB | Dedicated instance strongly recommended |
| Very large | 2M+ | 64+ GiB | 1+ TB | Consider Milvus instead |

> **Rule of thumb:** ~1 GB RAM per 1M vectors (at 1536 dimensions) for the HNSW index to remain in memory. If your index exceeds available RAM, query latency degrades significantly — at that point, migrate to Milvus.

> **Tables are created automatically.** The `langchain_pg_collection` and `langchain_pg_embedding` tables (with HNSW indexes) are created by the Data Loader on first document ingestion. You do not need to create them manually.

---

## Appendix D — Release notes

### What's new in 2.3.5

Released 29 June 2026. **Backwards-compatible drop-in replacement for 2.3.0–2.3.4** — no breaking changes, no required migrations, and no new mandatory environment variables.

> **Security release — Admin Console.** 2.3.5 contains security hardening for the **Admin Console** service (`orchestrator-admin-console`, port 8081). The fix addresses a **privilege-escalation** issue. As a matter of responsible disclosure, the specific details are intentionally not described here while operators upgrade.
>
> **Scope of the issue.** Exploitation required an **authenticated** Admin Console user — it could **not** be triggered by unauthenticated or anonymous users.
>
> **Who should upgrade?** **Any deployment that runs the Admin Console is strongly recommended to upgrade to 2.3.5.** The orchestrator service image is unchanged in behaviour, so the upgrade is a straightforward image-tag bump with no configuration changes. There are no breaking changes and no migrations.
>
> **If you do not run the Admin Console**, there is no functional change for you in this release; upgrading is still recommended to stay current.

**Hardening:**

- **Admin Console security hardening** — this release strengthens authorization controls in the Admin Console. No action beyond upgrading is required; existing accounts, roles, and configuration continue to work unchanged.

**Upgrade procedure:**

For Docker Compose deployments, change `IMAGE_TAG` to `2.3.5` and restart both the orchestrator and admin-console services:

```bash
IMAGE_TAG=2.3.5 docker compose up -d
```

For Kubernetes, AWS ECS, Azure Container Apps, GCP Cloud Run, and other manifest-driven deployments, update the image tag in your deployment manifest from `:2.3.4` (or earlier) to `:2.3.5` for **both** the orchestrator and admin-console workloads, then apply. No environment-variable or schema changes are needed.

### What's new in 2.3.4

Released 18 June 2026. **Backwards-compatible drop-in replacement for 2.3.0, 2.3.1, and 2.3.2** — no breaking changes, no required migrations, no new mandatory environment variables.

> **Who needs to upgrade?** Only operators using **GPT-5.x or o-series (`o1` / `o3` / `o4`) Azure OpenAI deployments** must upgrade. Every other deployment (GPT-4o, GPT-4o-mini, Anthropic, AWS Bedrock, Google Gemini / Vertex AI, Mistral, Ollama, Cohere, Hugging Face, NVIDIA NIM) can stay on 2.3.2 — those plugins are unchanged. There are no security fixes in 2.3.4.

**Bug fix:**

- **GPT-5+ and o-series (`o1`, `o3`, `o4`, ...) deployment support** — OpenAI's GPT-5 (and later) and o-series chat completions endpoints use the post-Sep-2024 Chat Completions contract: they reject the legacy `max_tokens` parameter (requiring `max_completion_tokens` instead) and reject any `temperature` other than the API default (1.0). In 2.3.2 and earlier the orchestrator unconditionally bound `max_tokens` in three places — the main `/orchestrator` request flow, the internal inference endpoint used by agents, and the background conversation summarizer — and passed `temperature` to the model constructor for every category, causing every request to fail against these deployments. 2.3.4 introduces a single environment-variable flag that, when set, handles both differences uniformly across every category and every code path.

**New environment variable:**

| Variable | Default | Description |
|---|---|---|
| `OPENAI_GPT5_COMPATIBLE` | `false` | Set to `true` when your OpenAI / Azure OpenAI deployment is GPT-5 (or later) or any o-series model. When `true`, the orchestrator binds `max_completion_tokens` on every LLM call and omits `temperature` from the model constructor (so the API default of 1.0 applies). Leave `false` for GPT-4o-family and earlier deployments. |

**Behaviour:**

- `OPENAI_GPT5_COMPATIBLE=true` → `max_completion_tokens` is sent on every call; `temperature` is omitted from the constructor.
- `OPENAI_GPT5_COMPATIBLE=false` (or unset) → `max_tokens` is sent (unchanged from 2.3.2); the configured per-category `*_TEMPERATURE` is passed through.
- If the flag is unset but the configured model name starts with `gpt-5`, `o1`, `o3`, or `o4`, the orchestrator logs a one-line `WARN` at model-construction time as a diagnostic hint. The flag value is still authoritative — the warning never changes behaviour.

**Upgrade procedure:**

For Docker Compose deployments, change `IMAGE_TAG` from `2.3.2` to `2.3.4` and restart:

```bash
IMAGE_TAG=2.3.4 docker compose up -d
```

For Kubernetes, AWS ECS, Azure Container Apps, GCP Cloud Run, and other manifest-driven deployments, update the image tag in your deployment manifest from `:2.3.2` to `:2.3.4` and apply. If your deployment is GPT-5+ or o-series, also add `OPENAI_GPT5_COMPATIBLE=true` to the orchestrator environment.

### What's new in 2.3.2

Released 9 June 2026. Backwards-compatible with 2.3.0 and 2.3.1 deployments.

**Spotfire administrators should be aware of the following bug fixes:**

- **Admin password policy enforcement on first login** — Admin-created users were not being prompted to change their temporary password on first login. This issue has been corrected: users will now be required to set a permanent password on initial login, strengthening account security and enforcing your organization's password policies.
- **Temperature configuration for LLM summarization and enrichment** — The temperature setting was not being properly applied to internal LLM operations for conversation summarization and enrichment. This has been fixed, ensuring that temperature configuration is now consistently applied across all LLM invocations, including background processing tasks.
- **Milvus vector database connection alias registration** — When using Milvus as a vector database with langchain-milvus 0.3+, the connection alias registration was missing, causing "ConnectionNotExistException" errors during document indexing. Administrators using Milvus or Zilliz deployments should upgrade to resolve document loading failures.
- **Image tag environment variable requirement** — The `IMAGE_TAG` environment variable is now **required** for Docker deployments. This variable must be explicitly set to specify which container image version to use (e.g., `IMAGE_TAG=2.3.2`), replacing the previous approach of modifying `docker-compose.yml`. This change simplifies version management and reduces the risk of deployment inconsistencies.

> **⚠️ CRITICAL: Check your `docker-compose.yml` for hard-coded image tags.** If you are upgrading to 2.3.2, inspect your `docker-compose.yml` file and ensure that the orchestrator and admin-console service images reference the **`${IMAGE_TAG}`** variable instead of hard-coded tags (e.g., `llm-orchestrator:2.3.1`). Hard-coded image tags will prevent you from using the `IMAGE_TAG` environment variable to control which version is deployed, and may cause version mismatches across your services. Use `IMAGE_TAG=2.3.2 docker compose up` to deploy correctly.

### What's new in 2.3.1

Released May 2026. Backwards-compatible with 2.3.0 deployments.

- **New container image source (OCI registry, credentialed)** — starting with 2.3.1, container images are distributed via the **Azure Container Registry** at `copilotoci.azurecr.io/spotfirecopilot/`. Operators must obtain registry credentials by opening a Support Portal case (select **Spotfire Enterprise** as the Product) and follow the [OCI Registry Access Guide](https://community.spotfire.com/articles/spotfire/oci-registry-access-guide/). The previous public ECR location (`public.ecr.aws/tds/`) remains available for **2.3.0** only.
- **Conversation retention cleanup** — new `CONVERSATION_RETENTION_DAYS` env var enables a daily background daemon (03:00 UTC) that deletes threads older than the configured TTL. Disabled by default. New admin endpoints: `GET /threads/retention/status`, `GET /threads/retention/preview`, `POST /threads/retention/cleanup`.
- **WebSocket reverse tunnel for developer agents** — new `/tunnel/connect` WebSocket endpoint lets locally-running agent containers register with a deployed orchestrator. Controlled by `TUNNEL_ENABLED` and five `TUNNEL_*` tuning vars. Requires the `agents:write` OAuth2 scope. Admin console gains a **Tunnels** tab showing live connection status.
- **Token-usage tracking & admin stats** — no new env vars. `GET /stats/token-usage?period=week|month|quarter|year|all` and `DELETE /stats/token-usage` (admin-only). New **Token Usage** dashboard tab with per-user breakdown.
- **LLM behaviour fix** — when a client omits `temperature`, the value is now passed as `None` to the plugin so its `.env`-configured default applies (previously `0.2` was forced).
- **Milvus auto-detect metric type** — Milvus retriever now auto-detects `IP` vs `L2` from the collection index instead of hard-coding `L2`.

Full env-var details are in **[§11](#11-environment-variable-reference) Environment Variable Reference** — 2.3.1-only variables are marked **(2.3.1)**.

---

*Copyright © 2006 – 2026 Cloud Software Group, Inc. All rights reserved.*
