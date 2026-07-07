# Spotfire Copilot™ — Data Loaders Installation Guide

> **Versions covered:** 2.3.0, 2.3.1, 2.3.2, and 2.3.4 &nbsp;|&nbsp; **Last updated:** 23 June 2026 &nbsp;|&nbsp; **Applies to:** Data Loader Services
>
> This guide covers data-loader versions **2.3.0**, **2.3.1**, **2.3.2**, and **2.3.4**. For new deployments, use **2.3.4**.
>
> ## Before you start: registry access is required for current images
>
> Current Spotfire Copilot data-loader images are distributed through the credentialed OCI registry at **`copilotoci.azurecr.io/spotfirecopilot/`**. Obtain registry credentials from Spotfire Support, then authenticate Docker before pulling images. The legacy public ECR location `public.ecr.aws/tds/` is relevant only for historical **2.3.0** deployments.
>
> ## Milvus PDF loading fix
>
> The Milvus / Zilliz PDF-ingestion failure that surfaces as **`ConnectionNotExistException`** during `/load` was fixed in **2.3.2**. That fix remains included in **2.3.4**, which is the recommended tag for all current data-loader deployments.

---

## Table of Contents

- [1. Introduction](#1-introduction)
- [2. Available Data Loader Images](#2-available-data-loader-images)
  - [Azure Cognitive Search images](#azure-cognitive-search-images)
  - [Plugin-based approach (recommended)](#plugin-based-approach-recommended)
  - [Vector databases supported by the Orchestrator but NOT by Data Loaders](#vector-databases-supported-by-the-orchestrator-but-not-by-data-loaders)
- [3. Prerequisites](#3-prerequisites)
- [4. Step 1 — Generate Credentials](#4-step-1--generate-credentials)
- [5. Step 2 — Choose Your LLM and Embedding Provider](#5-step-2--choose-your-llm-and-embedding-provider)
  - [OpenAI](#openai)
  - [Azure OpenAI](#azure-openai)
  - [AWS Bedrock](#aws-bedrock)
  - [Google Vertex AI](#google-vertex-ai)
  - [Ollama (Local)](#ollama-local)
  - [NVIDIA NIM](#nvidia-nim)
- [6. Step 3 — Choose Your Knowledge Base (Vector Database)](#6-step-3--choose-your-knowledge-base-vector-database)
  - [Zilliz Cloud](#zilliz-cloud)
  - [Milvus (self-hosted)](#milvus-self-hosted)
  - [Qdrant](#qdrant)
  - [MongoDB Atlas](#mongodb-atlas)
  - [Redis](#redis)
  - [Azure Cognitive Search](#azure-cognitive-search)
  - [Vertex AI Vector Search](#vertex-ai-vector-search)
  - [Databricks (pypdf loader only)](#databricks-pypdf-loader-only)
  - [PostgreSQL pgvector](#postgresql-pgvector)
- [7. Step 4 — Prepare Your Documents](#7-step-4--prepare-your-documents)
  - [Local PDF files](#local-pdf-files)
  - [Cloud storage sources](#cloud-storage-sources)
- [8. Step 5 — Deploy](#8-step-5--deploy)
  - [Quick start (OpenAI + Zilliz)](#quick-start-openai--zilliz)
- [9. Step 6 — Load Documents via the API](#9-step-6--load-documents-via-the-api)
  - [Authenticate first](#authenticate-first)
  - [Register a client (optional)](#register-a-client-optional)
  - [Load documents](#load-documents)
  - [Load the standard Spotfire documentation](#load-the-standard-spotfire-documentation)
  - [Load your own documents](#load-your-own-documents)
  - [API documentation](#api-documentation)
- [10. Authentication Guide](#10-authentication-guide)
  - [Quick reference](#quick-reference)
  - [Swagger UI flow](#swagger-ui-flow)
- [11. Environment Variable Reference](#11-environment-variable-reference)
  - [Required (service will not start without these)](#required-service-will-not-start-without-these)
  - [Optional](#optional)
  - [LangSmith tracing (optional)](#langsmith-tracing-optional)
  - [Azure Blob Storage (for `azcog-data-loader-azblob` image only)](#azure-blob-storage-for-azcog-data-loader-azblob-image-only)
  - [Plugin entry points](#plugin-entry-points)
- [12. Docker Compose Examples](#12-docker-compose-examples)
  - [OpenAI + Zilliz](#openai--zilliz)
  - [OpenAI + Milvus](#openai--milvus)
  - [Azure OpenAI + Azure Cognitive Search](#azure-openai--azure-cognitive-search)
  - [AWS Bedrock + Milvus](#aws-bedrock--milvus)
  - [Google Vertex AI + Vertex AI Vector Search](#google-vertex-ai--vertex-ai-vector-search)
  - [Advanced Loader (Unstructured — OCR-enabled)](#advanced-loader-unstructured--ocr-enabled)
  - [OpenAI + PostgreSQL pgvector](#openai--postgresql-pgvector)
- [13. Troubleshooting](#13-troubleshooting)
  - [Container won't start](#container-wont-start)
  - [Authentication errors](#authentication-errors)
  - [Document loading errors](#document-loading-errors)
  - [Common `.env` mistakes](#common-env-mistakes)
  - [Useful commands](#useful-commands)
- [14. Security Best Practices](#14-security-best-practices)

---

## 1. Introduction

Data Loaders are containerised services that ingest documents (PDFs, images, text) into
vector databases (knowledge bases). They extract text, generate embeddings using an LLM
provider, and store the resulting vectors for semantic search.

**Why you need a Data Loader:** The Data Loader is the tool that builds the knowledge
base your Orchestrator queries at runtime. It serves two primary purposes:

1. **Load standard Spotfire documentation** — enables Copilot's built-in Help and HowTo
   features (documents ship pre-installed in the container image).
2. **Load your own enterprise documents** — enables Copilot to answer questions about
   your organisation's data, processes, and domain knowledge using RAG (Retrieval
   Augmented Generation). Any PDF content you provide can be made searchable.

**Relationship to the Orchestrator:** Data Loaders and the Orchestrator are independent
services. You run a Data Loader to populate your vector database, then configure the
Orchestrator to query that same vector database at runtime. They share the same plugin
naming conventions and credential patterns, but run as separate containers.

```
┌──────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Source Docs │──────▶  │   Data Loader    │──────▶  │  Knowledge Base │
│  (PDFs, etc) │         │  (Docker container)│        │  (Vector DB)    │
└──────────────┘         └──────────────────┘         └─────────────────┘
                                                              │
                                                              ▼
                                                      ┌─────────────────┐
                                                      │  Orchestrator   │
                                                      │  (queries at    │
                                                      │   runtime)      │
                                                      └─────────────────┘
```

---

## 2. Available Data Loader Images

All current images are hosted on the credentialed OCI registry at **`copilotoci.azurecr.io/spotfirecopilot/`**.

| Image | Description | Best For |
|---|---|---|
| `copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-pypdf:2.3.4` | **Basic text loader.** Extracts text from PDFs using PyPDF. Fast, lightweight, reliable. | Text-heavy PDFs, simple documents |
| `copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-unstruct:2.3.4` | **Advanced OCR loader.** Uses Unstructured.io for full document analysis — OCR, table extraction, layout preservation. | Scanned documents, image-heavy PDFs, complex layouts |

> **Which one should I use?** Start with the **Basic (PyPDF)** loader. It handles most
> text-based PDFs well and is significantly faster. Only use the Advanced (Unstructured)
> loader if you have scanned documents or require table/image extraction.

### Azure Cognitive Search images

These images are purpose-built for Azure Cognitive Search and support loading from
local PDFs or Azure Blob Storage:

| Image | Description |
|---|---|
| `copilotoci.azurecr.io/spotfirecopilot/azcog-data-loader-pdf:2.3.4` | Load PDFs into Azure Cognitive Search |
| `copilotoci.azurecr.io/spotfirecopilot/azcog-data-loader-azblob:2.3.4` | Load documents from Azure Blob Storage into Azure Cognitive Search |

### Plugin-based approach (recommended)

The current images (`data-loader-pdf-pypdf` and `data-loader-pdf-unstruct`) support most
vector databases via the plugin system — you select the target database through an
environment variable rather than choosing a different Docker image. This is the
recommended approach for new deployments.

### Vector databases supported by the Orchestrator but NOT by Data Loaders

The Orchestrator can **query** more vector databases than the Data Loaders can **write to**.
If you use one of the following knowledge bases, you must populate it using the provider's
own ingestion tools — there is no Spotfire Data Loader for them:

| Knowledge Base | How to Load Data | Orchestrator Retriever Plugin |
|---|---|---|
| **Qdrant** | Use [Qdrant's native import tools](https://qdrant.tech/documentation/), client SDKs, or LangChain's Qdrant integration | `plugins.retrievers.qdrant:QdrantRetrieverPlugin` |
| **AWS Bedrock Knowledge Bases** | Use the AWS Console or SDK to create a Knowledge Base with an S3 data source — AWS handles ingestion automatically | `plugins.retrievers.amazon_kbs:AmazonKBsRetrieverPlugin` |

> **This is not a problem** — it just means you use the provider's native tools to load your
> documents, then point the Orchestrator at the populated index. The Orchestrator handles
> retrieval at query time regardless of how the data was loaded.

---

## 3. Prerequisites

| Requirement | Details |
|---|---|
| **Docker** | Docker Engine 20.10+ with Docker Compose V2 |
| **LLM provider access** | An API key for embeddings generation (see **[§5](#5-step-2--choose-your-llm-and-embedding-provider) Step 2 — Choose Your LLM and Embedding Provider**) |
| **Vector database** | A running instance of your chosen knowledge base (Zilliz, Milvus, MongoDB, Redis, Azure Cognitive Search, Vertex AI Vector Search, or PostgreSQL with pgvector) |
| **Source documents** | PDF files in a local directory (or cloud storage credentials for remote sources) |
| **Python 3.11+** | Only needed on the machine where you generate credentials (Step 1). Not required on the deployment target. |

---

## 4. Step 1 — Generate Credentials

The Data Loader uses the same credential pattern as the Orchestrator. If you have already
generated credentials for the Orchestrator, you can reuse `SECRET_KEY` and
`HASHED_ADMIN_PASSWORD`.

```bash
# Install bcrypt (if not already installed)
pip install bcrypt

# Generate credentials
cd orchestrator-service
python generate_credentials.py
```

You need two values from the output:
- **`SECRET_KEY`** — for JWT token signing
- **`HASHED_ADMIN_PASSWORD`** — bcrypt hash of the admin password

> **Save the plaintext password** — it is shown only once. You will need it to authenticate
> with the Data Loader API.

---

## 5. Step 2 — Choose Your LLM and Embedding Provider

The Data Loader needs an LLM provider for two purposes:
1. **Embeddings** — converting document text into vectors for storage
2. **Summarisation** *(optional)* — generating document summaries for enriched metadata

Set the plugin entry points and credentials for your chosen provider:

### OpenAI

```bash
MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai:OpenAIPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.openai:OpenAIEmbeddingsPlugin

OPENAI_API_TYPE=openai
OPENAI_API_KEY=sk-your-openai-api-key
MODEL_NAME=gpt-4o
EMBEDDING_MODEL_NAME=text-embedding-ada-002
```

### Azure OpenAI

```bash
MODEL_PLUGIN_ENTRY_POINT=plugins.models.az_openai:AzOpenAIPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.az_openai:AzOpenAIEmbeddingsPlugin

OPENAI_API_TYPE=azure
OPENAI_API_KEY=your-azure-openai-key
AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com/
OPENAI_API_VERSION=2024-02-15-preview
MODEL_NAME=gpt-4o
EMBEDDING_MODEL_NAME=text-embedding-ada-002
```

### AWS Bedrock

```bash
MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock:BedrockPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.bedrock:BedrockEmbeddingsPlugin

AWS_REGION=us-east-1
# Mount AWS credentials directory (see Docker Compose examples)
```

### Google Vertex AI

```bash
MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai:VertexAIPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.vertexai:VertexAIEmbeddingsPlugin

PROJECT_ID=your-gcp-project-id
LOCATION_ID=us-central1
EMBEDDING_MODEL_NAME=text-embedding-004
GOOGLE_APPLICATION_CREDENTIALS=/app/credentials/service-account-key.json
# Mount GCP credentials directory (see Docker Compose examples)
```

### Ollama (Local)

```bash
MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama:OllamaPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.ollama:OllamaEmbeddingsPlugin

OLLAMA_BASE_URL=http://host.docker.internal:11434
MODEL_NAME=llama3.1:8b
EMBEDDING_MODEL_NAME=nomic-embed-text
```

> **Important:** `OLLAMA_BASE_URL` is used by **both** the LLM model plugin and the
> embeddings plugin. If Ollama is running on a remote host (not `localhost`), you **must**
> set this variable — otherwise the data loader will fail with a connection error when
> generating embeddings. Use `host.docker.internal` to reach Ollama on the Docker host,
> or the actual IP/hostname for a remote server (e.g., `http://192.168.1.100:11434`).
> On Linux without Docker Desktop, use `http://172.17.0.1:11434` instead.
>
> The embedding model must be pulled on your Ollama instance:
> ```bash
> ollama pull nomic-embed-text
> ```

### NVIDIA NIM

```bash
MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim:NvidiaNimPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.nvidia_nim:NvidiaNimEmbeddingsPlugin

NVIDIA_API_KEY=your-nvidia-api-key
NVIDIA_BASE_URL=https://integrate.api.nvidia.com/v1
```

---

## 6. Step 3 — Choose Your Knowledge Base (Vector Database)

Set the vector database plugin and connection credentials:

### Zilliz Cloud

```bash
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.zilliz:ZillizRetrieverPlugin

ZILLIZ_CLOUD_URI=https://your-instance.zillizcloud.com
ZILLIZ_CLOUD_API_KEY=your-zilliz-api-key
```

### Milvus (self-hosted)

```bash
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.milvus:MilvusRetrieverPlugin

VECTORDB_URI=http://your-milvus-host:19530
VECTORDB_TOKEN=root:Milvus
```

Use **2.3.4** for Milvus and Zilliz deployments. Versions before **2.3.2** can fail during document ingestion with `ConnectionNotExistException` even though the target collection or index is created.

### Qdrant

> **Not available via Data Loaders.** The data loader images do not include a Qdrant plugin.
> Load your data into Qdrant using its [native import tools](https://qdrant.tech/documentation/)
> or a LangChain Qdrant integration. The Orchestrator can then query Qdrant at runtime
> using `plugins.retrievers.qdrant:QdrantRetrieverPlugin`.
> See **[§2](#2-available-data-loader-images) Available Data Loader Images → Vector databases supported by the Orchestrator but NOT by Data Loaders**.

### MongoDB Atlas

```bash
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.mongo:MongoRetrieverPlugin

MONGODB_ATLAS_CLUSTER_URI=mongodb+srv://user:pass@cluster.mongodb.net
MONGODB_ATLAS_DB_NAME=your-db-name
MONGODB_ATLAS_COLLECTION_NAME=your-collection
MONGODB_ATLAS_INDEX_DIMENSIONS=1536
```

### Redis

```bash
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.redis:RedisRetrieverPlugin

REDIS_URL=redis://your-redis-host:6379
```

### Azure Cognitive Search

```bash
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.az_cog_search:ACognitiveSearchRetrieverPlugin

AZURE_COGNITIVE_SEARCH_SERVICE_NAME=your-search-service-name
AZURE_COGNITIVE_SEARCH_API_KEY=your-search-api-key
AZSEARCH_EP=https://your-service.search.windows.net/
AZSEARCH_KEY=your-search-key
```

### Vertex AI Vector Search

```bash
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin

PROJECT_ID=your-gcp-project-id
LOCATION_ID=us-central1
GCS_BUCKET_NAME=your-gcs-bucket-name
```

### Databricks (pypdf loader only)

```bash
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.databricks:DatabricksRetrieverPlugin

DATABRICKS_HOST=https://your-workspace.cloud.databricks.com
DATABRICKS_TOKEN=your-databricks-token
DATABRICKS_ENDPOINT=your-vector-search-endpoint
DATABRICKS_TEXT_COLUMN=content
DATABRICKS_COLUMNS=content,source,title
```

### PostgreSQL pgvector

```bash
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.pgvector:PgVectorRetrieverPlugin

PGVECTOR_CONNECTION_STRING=postgresql+psycopg://user:password@pgvector-host:5432/vectordb
```

> **Prerequisites:** PostgreSQL 15 or 16 with the `vector` extension installed.
> A **separate database** from the orchestrator's application database is recommended.
>
> **First-time setup** (run once on the target PostgreSQL instance):
> ```sql
> -- Create the role and database
> CREATE ROLE copilot_vector WITH LOGIN PASSWORD 'your-secure-password';
> CREATE DATABASE copilot_vectordb OWNER copilot_vector;
>
> -- Connect to the new database and enable pgvector
> \c copilot_vectordb
> CREATE EXTENSION IF NOT EXISTS vector;
>
> -- Grant permissions
> GRANT ALL PRIVILEGES ON SCHEMA public TO copilot_vector;
> ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO copilot_vector;
> ```
>
> The collection tables (`langchain_pg_collection`, `langchain_pg_embedding`) and HNSW
> indexes are created automatically by the Data Loader on first document ingestion.
>
> **Managed PostgreSQL services:**
> - **Azure Database for PostgreSQL:** `az postgres flexible-server parameter set --name azure.extensions --value vector`
> - **AWS RDS for PostgreSQL:** Add `pgvector` to the `shared_preload_libraries` parameter group
> - **GCP Cloud SQL:** Enable via the Extensions page in the Cloud Console
>
> **Compute resource guidelines:**
>
> | Workload | vCPUs | RAM | Storage |
> |---|---|---|---|
> | Small (< 50K chunks) | 2 | 4 GiB | 20 GB |
> | Medium (50K–500K chunks) | 4 | 16 GiB | 100 GB |
> | Large (500K+ chunks) | 8+ | 32+ GiB | 500+ GB |

---

## 7. Step 4 — Prepare Your Documents

The Data Loader can ingest any PDF documents you provide — internal guides, product
manuals, compliance documents, research papers, runbooks, or anything else you want
Spotfire Copilot to be able to answer questions about.

### Local PDF files

Create a directory containing your PDF documents:

```bash
mkdir -p ./pdf_docs
# Copy your PDF files into this directory
cp /path/to/your/documents/*.pdf ./pdf_docs/
```

This directory will be mounted into the container at `/docs`. When you call the `/load`
endpoint, the Data Loader processes every PDF in this directory, splits them into chunks,
generates embeddings, and stores the results in your vector database.

**Tips for best results:**

- **Keep documents focused** — a collection of related documents (e.g., all admin guides)
works better than one giant dump of unrelated content.
- **Use meaningful filenames** — the original filename is stored as the `source` metadata
field and can be used for filtering at query time.
- **Organise into separate collections** — load different document sets into different
`index_name` values (e.g., `admin-guides`, `api-docs`, `compliance`). The Orchestrator
can be configured to query a specific collection per intent.
- **PDF quality matters** — text-based (searchable) PDFs produce better results than
scanned images. For scanned documents, use the `unstruct` (Unstructured) loader image
with `partitioning_strategy=hi_res` for OCR extraction.

### Cloud storage sources

For documents stored in cloud services (Azure Blob, S3, GCS), configure the appropriate
environment variables and credentials instead of mounting a local directory. The
`azcog-data-loader-azblob` image can pull documents directly from Azure Blob Storage.
See **[§12](#12-docker-compose-examples) Docker Compose Examples**.

---

## 8. Step 5 — Deploy

### Quick start (OpenAI + Zilliz)

1. Create a `.env` file:

```bash
LOG_LEVEL=INFO
SECRET_KEY=your-64-char-hex-string
HASHED_ADMIN_PASSWORD='$2b$12$...your-bcrypt-hash...'
ACCESS_TOKEN_EXPIRE_DAYS=30

# Plugins
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.zilliz:ZillizRetrieverPlugin
MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai:OpenAIPlugin
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.openai:OpenAIEmbeddingsPlugin

# OpenAI
OPENAI_API_TYPE=openai
OPENAI_API_KEY=sk-your-key
MODEL_NAME=gpt-4o
EMBEDDING_MODEL_NAME=text-embedding-ada-002

# Zilliz
ZILLIZ_CLOUD_URI=https://your-instance.zillizcloud.com
ZILLIZ_CLOUD_API_KEY=your-zilliz-key

# Documents
DOCS_DIR=./pdf_docs
```

2. Create a `docker-compose.yml`:

```yaml
services:
  data-loader:
    image: copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-pypdf:2.3.4
    ports:
      - 8080:8080
    container_name: data-loader
    restart: unless-stopped
    volumes:
      - ${DOCS_DIR}:/docs
    env_file:
      - .env
```

Before starting the service, authenticate Docker to `copilotoci.azurecr.io` using the OCI registry credentials issued for your environment.

3. Start the service:

```bash
docker compose up -d
```

4. Verify it's running:

```bash
# Check container status
docker compose ps

# Check logs
docker compose logs -f data-loader
```

---

## 9. Step 6 — Load Documents via the API

Once the Data Loader is running, use its REST API to ingest documents.

### Authenticate first

```bash
# Get an admin token
curl -X POST http://localhost:8080/admin/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&username=admin&password=<your_admin_password>"
```

Response:
```json
{
  "access_token": "<admin_token>",
  "token_type": "bearer"
}
```

### Register a client (optional)

```bash
curl -X POST http://localhost:8080/register_client \
  -H "Authorization: Bearer <admin_token>"
```

### Load documents

The Data Loader provides two main loading endpoints:

1. **`/load_spotfire_docs`** — Loads the bundled Spotfire documentation (pre-installed in
   the image) into a `spotfiredocs` collection. **This is required for Copilot Help/HowTo
   features to work.**

2. **`/load`** — Loads your own PDF documents from the mounted `/docs` directory into a
   named collection.

```bash
# Step 1: Load the standard Spotfire documentation (required for Help/HowTo)
curl -X POST http://localhost:8080/load_spotfire_docs \
  -H "Authorization: Bearer <token>"

# Step 2: Load your own custom documents
curl -X POST "http://localhost:8080/load?index_name=my-custom-docs" \
  -H "Authorization: Bearer <token>"
```

See the detailed sections below for more information on each endpoint.

### Load the standard Spotfire documentation

The Data Loader images ship with **standard Spotfire documentation pre-installed** inside
the container at `/app/docs/docs_spotfire_analyst_um/`. These documents are essential for
Spotfire Copilot's **Help** and **HowTo** features to work correctly.

**Included documents:**

| Document | Description |
|---|---|
| `SpotfireCopilotUserManual.pdf` | Spotfire Copilot user manual |
| `SPOT_sfire_client_14_6.pdf` | Spotfire Analyst (desktop client) user guide |
| `SPOT_sfire_web_client_14_4.pdf` | Spotfire Web Player user guide |

**Why this matters:** When the Spotfire client sends a Help or HowTo request, the
Orchestrator retrieves answers from the vector database using the collection name
`spotfiredocs`. If this collection has not been populated, those features return no results.

**How to load them:**

The Data Loader provides a dedicated endpoint that loads the bundled documents into a
collection named `spotfiredocs`:

```bash
curl -X POST http://localhost:8080/load_spotfire_docs \
  -H "Authorization: Bearer <token>"
```

This endpoint:
- Reads all PDFs from `/app/docs/docs_spotfire_analyst_um/` (pre-installed in the image)
- Creates (or replaces) a collection/index named **`spotfiredocs`**
- Sets `drop_old=True` — all previous data in the `spotfiredocs` index is replaced
- Uses the `fast` partitioning strategy
- **No volume mount required** — the documents are already inside the container

> **⚠️ Important: Source metadata.** Each chunk stored in the vector database includes a
> `source` metadata field containing the original filename (e.g., `SPOT_sfire_client_14_6.pdf`).
> The Orchestrator uses this field to filter search results when the Spotfire client requests
> documentation from a specific source. **If your vector database does not support metadata
> filtering on a `source` field, source-specific queries will return unfiltered results.**

> **📌 Bedrock Knowledge Bases:** AWS Bedrock KBs do not store a flat `source` metadata field.
> The Orchestrator has a built-in workaround — it uses a two-phase retrieval strategy
> (native filter → post-filter by S3 URI filename suffix). However, you must upload the
> Spotfire PDFs to your Bedrock KB's S3 data source directly; the `/load_spotfire_docs`
> endpoint does not apply to Bedrock KBs.

**When to reload:** Run `/load_spotfire_docs` again after upgrading the Data Loader image
to a newer version, as updated documentation may be included.

### Load your own documents

In addition to the bundled Spotfire documentation, the Data Loader's primary purpose is
to ingest **your own enterprise documents** into a knowledge base that the Orchestrator
can query. This enables Spotfire Copilot to answer questions about your organisation's
content — internal guides, product documentation, compliance policies, runbooks, or any
other PDF materials.

Use the generic `/load` endpoint to load PDF documents from the mounted `/docs` directory:

```bash
# Load your documents into a named collection
curl -X POST "http://localhost:8080/load?index_name=my-custom-docs&drop_old=false" \
  -H "Authorization: Bearer <token>"
```

Parameters:
- `index_name` — Name of the target collection/index (default: `myindex`). Choose a
  meaningful name — this is what you'll configure in the Orchestrator to query.
- `drop_old` — Whether to replace existing data in that collection (default: `false`).
  Set to `true` when re-loading an updated document set.
- `partitioning_strategy` — `fast` (default) or `hi_res` (OCR-enabled, slower but
  better for scanned documents or complex layouts)

**Typical workflow:**

1. Place your PDFs in the directory specified by `DOCS_DIR` (mounted as `/docs`)
2. Start the Data Loader container
3. Authenticate (see above)
4. Call `/load` with your chosen `index_name`
5. Configure the Orchestrator to query that `index_name` for the relevant intent

**Loading multiple document sets:**

You can load different document sets into different collections by changing the contents
of your `/docs` volume and calling `/load` with a different `index_name` each time:

```bash
# Load admin guides
cp ./admin-guides/*.pdf ./pdf_docs/
curl -X POST "http://localhost:8080/load?index_name=admin-guides&drop_old=true" \
  -H "Authorization: Bearer <token>"

# Load API documentation
rm ./pdf_docs/*
cp ./api-docs/*.pdf ./pdf_docs/
curl -X POST "http://localhost:8080/load?index_name=api-docs&drop_old=true" \
  -H "Authorization: Bearer <token>"
```

> **💡 Tip:** Each document chunk stored in the vector database includes `source` (filename)
> and `page` (page number) metadata. The Orchestrator includes these in its responses so
> users can trace answers back to specific documents and pages.

### API documentation

Interactive API docs are available at:
- **Swagger UI:** `http://localhost:8080/docs`
- **ReDoc:** `http://localhost:8080/redoc`

Browse the Swagger UI to see all available endpoints, including:
- Loading bundled Spotfire documentation (`/load_spotfire_docs`)
- Loading your own documents from mounted volumes (`/load`)
- Searching/querying the vector database (`/search`)
- Managing indexes and collections

---

## 10. Authentication Guide

The Data Loader uses the same OAuth2 authentication flow as the Orchestrator.

### Quick reference

| Step | Endpoint | Method | Purpose |
|---|---|---|---|
| 1 | `/admin/token` | POST | Get an admin token using username/password |
| 2 | `/register_client` | POST | Create a client_id and client_secret (requires admin token) |
| 3 | `/client/token` | POST | Exchange client credentials for a Bearer token |
| 4 | Any endpoint | * | Use Bearer token in the `Authorization` header |

### Swagger UI flow

1. Open `http://localhost:8080/docs`
2. Click **Authorize** → enter `admin` / your password → click **Authorize**
3. Expand `POST /register_client` → **Try it out** → **Execute** → save the `client_id` and `client_secret`
4. Expand `POST /client/token` → **Try it out** → enter credentials → **Execute** → copy the `access_token`
5. Click **Authorize** again → paste the token in HTTPBearer → **Authorize**
6. All secured endpoints are now accessible

> **⚠️ Registered clients are ephemeral.** The Data Loader stores clients in memory only —
> any clients created via `/register_client` are **lost when the container restarts**. To avoid
> re-registering after every restart, set `DEFAULT_CLIENT_ID` and `DEFAULT_CLIENT_SECRET`
> in your environment variables. These are pre-seeded at startup and persist across restarts
> (as long as your `.env` or environment configuration is unchanged).
>
> ```bash
> # Add to your .env file for a persistent client
> DEFAULT_CLIENT_ID=my-data-loader-client
> DEFAULT_CLIENT_SECRET=my-secret-value
> ```

---

## 11. Environment Variable Reference

### Required (service will not start without these)

| Variable | Description |
|---|---|
| `SECRET_KEY` | 64-character hex string for JWT signing |
| `HASHED_ADMIN_PASSWORD` | Bcrypt hash of the admin password. **Wrap in single quotes in `.env` files.** |
| `VECTORDB_PLUGIN_ENTRY_POINT` | Vector database plugin (e.g., `plugins.vectordbs.zilliz:ZillizRetrieverPlugin`) |
| `MODEL_PLUGIN_ENTRY_POINT` | LLM plugin (e.g., `plugins.models.openai:OpenAIPlugin`) |
| `EMBEDDINGS_PLUGIN_ENTRY_POINT` | Embeddings plugin (e.g., `plugins.embeddings.openai:OpenAIEmbeddingsPlugin`) |
| At least one LLM API key | Provider-specific (e.g., `OPENAI_API_KEY`) |
| Vector DB credentials | Provider-specific (e.g., `ZILLIZ_CLOUD_URI` + `ZILLIZ_CLOUD_API_KEY`, or `PGVECTOR_CONNECTION_STRING` for pgvector) |

### Optional

| Variable | Default | Description |
|---|---|---|
| `LOG_LEVEL` | `INFO` | Logging verbosity: `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `ACCESS_TOKEN_EXPIRE_DAYS` | `30` | How long JWT tokens remain valid |
| `MODEL_NAME` | Provider default | LLM model for summarisation |
| `EMBEDDING_MODEL_NAME` | Provider default | Embedding model name |
| `DEFAULT_CLIENT_ID` | — | Pre-seeded OAuth2 client ID (survives restart) |
| `DEFAULT_CLIENT_SECRET` | — | Pre-seeded OAuth2 client secret (survives restart) |
| `DOCS_DIR` | `./pdf_docs` | Host path to mount as `/docs` in the container |

### LangSmith tracing (optional)

| Variable | Default | Description |
|---|---|---|
| `LANGCHAIN_TRACING_V2` | `false` | Enable LangSmith tracing |
| `LANGCHAIN_ENDPOINT` | `https://api.smith.langchain.com` | LangSmith API endpoint |
| `LANGCHAIN_API_KEY` | — | LangSmith API key |
| `LANGCHAIN_PROJECT` | — | LangSmith project name |

### Azure Blob Storage (for `azcog-data-loader-azblob` image only)

| Variable | Description |
|---|---|
| `AZURE_STORAGE_CONNECTION` | Azure Storage connection string (e.g., `DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...;EndpointSuffix=core.windows.net`) |

### Plugin entry points

**Vector databases:**

| Vector DB | Plugin Entry Point | Supported In |
|---|---|---|
| Zilliz Cloud | `plugins.vectordbs.zilliz:ZillizRetrieverPlugin` | pypdf, unstruct |
| Milvus | `plugins.vectordbs.milvus:MilvusRetrieverPlugin` | pypdf, unstruct |
| MongoDB Atlas | `plugins.vectordbs.mongo:MongoRetrieverPlugin` | pypdf, unstruct |
| Redis | `plugins.vectordbs.redis:RedisRetrieverPlugin` | pypdf, unstruct |
| Azure Cognitive Search | `plugins.vectordbs.az_cog_search:ACognitiveSearchRetrieverPlugin` | pypdf, unstruct |
| Vertex AI Vector Search | `plugins.vectordbs.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin` | pypdf, unstruct |
| Databricks | `plugins.vectordbs.databricks:DatabricksRetrieverPlugin` | pypdf only |
| PostgreSQL pgvector | `plugins.vectordbs.pgvector:PgVectorRetrieverPlugin` | pypdf, unstruct |

> **Note:** Qdrant is not supported via the plugin system in data loaders. Use Qdrant's
> native import tools or LangChain's Qdrant integration to load data, then query it at
> runtime via the Orchestrator's `plugins.retrievers.qdrant:QdrantRetrieverPlugin`.

**LLM models:**

| Provider | Plugin Entry Point |
|---|---|
| OpenAI | `plugins.models.openai:OpenAIPlugin` |
| Azure OpenAI | `plugins.models.az_openai:AzOpenAIPlugin` |
| AWS Bedrock | `plugins.models.bedrock:BedrockPlugin` |
| AWS Bedrock (profile auth) | `plugins.models.bedrock_anywhere:BedrockAnywherePlugin` |
| Google Vertex AI | `plugins.models.vertexai:VertexAIPlugin` |
| Cohere | `plugins.models.cohere:CoherePlugin` |
| Hugging Face | `plugins.models.hugging_face_endpoint:HuggingFaceEndpointPlugin` |
| NVIDIA NIM | `plugins.models.nvidia_nim:NvidiaNimPlugin` |
| Ollama | `plugins.models.ollama:OllamaPlugin` |

**Embeddings:**

| Provider | Plugin Entry Point |
|---|---|
| OpenAI | `plugins.embeddings.openai:OpenAIEmbeddingsPlugin` |
| Azure OpenAI | `plugins.embeddings.az_openai:AzOpenAIEmbeddingsPlugin` |
| AWS Bedrock | `plugins.embeddings.bedrock:BedrockEmbeddingsPlugin` |
| AWS Bedrock (profile auth) | `plugins.embeddings.bedrock_anywhere:BedrockAnywhereEmbeddingsPlugin` |
| Google Vertex AI | `plugins.embeddings.vertexai:VertexAIEmbeddingsPlugin` |
| Hugging Face | `plugins.embeddings.hugging_face:HuggingFaceEmbeddingsPlugin` |
| NVIDIA NIM | `plugins.embeddings.nvidia_nim:NvidiaNimEmbeddingsPlugin` |
| Ollama | `plugins.embeddings.ollama:OllamaEmbeddingsPlugin` |

---

## 12. Docker Compose Examples

### OpenAI + Zilliz

```yaml
services:
  data-loader:
    image: copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-pypdf:2.3.4
    ports:
      - 8080:8080
    container_name: data-loader
    restart: unless-stopped
    volumes:
      - ${DOCS_DIR}:/docs
    environment:
      LOG_LEVEL: ${LOG_LEVEL}
      SECRET_KEY: ${SECRET_KEY}
      ACCESS_TOKEN_EXPIRE_DAYS: ${ACCESS_TOKEN_EXPIRE_DAYS}
      HASHED_ADMIN_PASSWORD: ${HASHED_ADMIN_PASSWORD}
      VECTORDB_PLUGIN_ENTRY_POINT: ${VECTORDB_PLUGIN_ENTRY_POINT}
      MODEL_PLUGIN_ENTRY_POINT: ${MODEL_PLUGIN_ENTRY_POINT}
      EMBEDDINGS_PLUGIN_ENTRY_POINT: ${EMBEDDINGS_PLUGIN_ENTRY_POINT}
      OPENAI_API_TYPE: ${OPENAI_API_TYPE}
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      OPENAI_API_VERSION: ${OPENAI_API_VERSION}
      AZURE_OPENAI_ENDPOINT: ${AZURE_OPENAI_ENDPOINT}
      MODEL_NAME: ${MODEL_NAME}
      EMBEDDING_MODEL_NAME: ${EMBEDDING_MODEL_NAME}
      ZILLIZ_CLOUD_URI: ${ZILLIZ_CLOUD_URI}
      ZILLIZ_CLOUD_API_KEY: ${ZILLIZ_CLOUD_API_KEY}
```

### OpenAI + Milvus

```yaml
services:
  data-loader:
    image: copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-pypdf:2.3.4
    ports:
      - 8080:8080
    container_name: data-loader
    restart: unless-stopped
    volumes:
      - ${DOCS_DIR}:/docs
    environment:
      LOG_LEVEL: ${LOG_LEVEL}
      SECRET_KEY: ${SECRET_KEY}
      ACCESS_TOKEN_EXPIRE_DAYS: ${ACCESS_TOKEN_EXPIRE_DAYS}
      HASHED_ADMIN_PASSWORD: ${HASHED_ADMIN_PASSWORD}
      VECTORDB_PLUGIN_ENTRY_POINT: plugins.vectordbs.milvus:MilvusRetrieverPlugin
      MODEL_PLUGIN_ENTRY_POINT: plugins.models.openai:OpenAIPlugin
      EMBEDDINGS_PLUGIN_ENTRY_POINT: plugins.embeddings.openai:OpenAIEmbeddingsPlugin
      OPENAI_API_TYPE: openai
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      MODEL_NAME: ${MODEL_NAME}
      EMBEDDING_MODEL_NAME: ${EMBEDDING_MODEL_NAME}
      VECTORDB_URI: ${VECTORDB_URI}
      VECTORDB_TOKEN: ${VECTORDB_TOKEN}
```

### Azure OpenAI + Azure Cognitive Search

```yaml
services:
  data-loader:
    image: copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-pypdf:2.3.4
    ports:
      - 8080:8080
    container_name: data-loader
    restart: unless-stopped
    volumes:
      - ${DOCS_DIR}:/docs
    environment:
      LOG_LEVEL: ${LOG_LEVEL}
      SECRET_KEY: ${SECRET_KEY}
      ACCESS_TOKEN_EXPIRE_DAYS: ${ACCESS_TOKEN_EXPIRE_DAYS}
      HASHED_ADMIN_PASSWORD: ${HASHED_ADMIN_PASSWORD}
      VECTORDB_PLUGIN_ENTRY_POINT: plugins.vectordbs.az_cog_search:ACognitiveSearchRetrieverPlugin
      MODEL_PLUGIN_ENTRY_POINT: plugins.models.az_openai:AzOpenAIPlugin
      EMBEDDINGS_PLUGIN_ENTRY_POINT: plugins.embeddings.az_openai:AzOpenAIEmbeddingsPlugin
      OPENAI_API_TYPE: azure
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      OPENAI_API_VERSION: ${OPENAI_API_VERSION}
      AZURE_OPENAI_ENDPOINT: ${AZURE_OPENAI_ENDPOINT}
      MODEL_NAME: ${MODEL_NAME}
      EMBEDDING_MODEL_NAME: ${EMBEDDING_MODEL_NAME}
      AZURE_COGNITIVE_SEARCH_SERVICE_NAME: ${AZURE_COGNITIVE_SEARCH_SERVICE_NAME}
      AZURE_COGNITIVE_SEARCH_API_KEY: ${AZURE_COGNITIVE_SEARCH_API_KEY}
      AZSEARCH_EP: ${AZSEARCH_EP}
      AZSEARCH_KEY: ${AZSEARCH_KEY}
```

### AWS Bedrock + Milvus

```yaml
services:
  data-loader:
    image: copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-pypdf:2.3.4
    ports:
      - 8080:8080
    container_name: data-loader
    restart: unless-stopped
    volumes:
      - ${DOCS_DIR}:/docs
      - ${AWS_CONFIG_DIR}:/home/spotuser/.aws
    environment:
      LOG_LEVEL: ${LOG_LEVEL}
      SECRET_KEY: ${SECRET_KEY}
      ACCESS_TOKEN_EXPIRE_DAYS: ${ACCESS_TOKEN_EXPIRE_DAYS}
      HASHED_ADMIN_PASSWORD: ${HASHED_ADMIN_PASSWORD}
      VECTORDB_PLUGIN_ENTRY_POINT: plugins.vectordbs.milvus:MilvusRetrieverPlugin
      MODEL_PLUGIN_ENTRY_POINT: plugins.models.bedrock:BedrockPlugin
      EMBEDDINGS_PLUGIN_ENTRY_POINT: plugins.embeddings.bedrock:BedrockEmbeddingsPlugin
      MODEL_NAME: ${MODEL_NAME}
      EMBEDDING_MODEL_NAME: ${EMBEDDING_MODEL_NAME}
      VECTORDB_URI: ${VECTORDB_URI}
      VECTORDB_TOKEN: ${VECTORDB_TOKEN}
      AWS_PROFILE_NAME: ${AWS_PROFILE_NAME}
      AWS_REGION: ${AWS_REGION}
```

### Google Vertex AI + Vertex AI Vector Search

```yaml
services:
  data-loader:
    image: copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-pypdf:2.3.4
    ports:
      - 8080:8080
    container_name: data-loader
    restart: unless-stopped
    volumes:
      - ${DOCS_DIR}:/docs
      - ${GCLOUD_DIR}:/app/credentials:ro
    environment:
      LOG_LEVEL: ${LOG_LEVEL}
      SECRET_KEY: ${SECRET_KEY}
      ACCESS_TOKEN_EXPIRE_DAYS: ${ACCESS_TOKEN_EXPIRE_DAYS}
      HASHED_ADMIN_PASSWORD: ${HASHED_ADMIN_PASSWORD}
      VECTORDB_PLUGIN_ENTRY_POINT: plugins.vectordbs.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin
      MODEL_PLUGIN_ENTRY_POINT: plugins.models.vertexai:VertexAIPlugin
      EMBEDDINGS_PLUGIN_ENTRY_POINT: plugins.embeddings.vertexai:VertexAIEmbeddingsPlugin
      MODEL_NAME: ${MODEL_NAME}
      EMBEDDING_MODEL_NAME: ${EMBEDDING_MODEL_NAME}
      PROJECT_ID: ${PROJECT_ID}
      LOCATION_ID: ${LOCATION_ID}
      GCS_BUCKET_NAME: ${GCS_BUCKET_NAME}
      GOOGLE_APPLICATION_CREDENTIALS: /app/credentials/service-account-key.json
```

### Advanced Loader (Unstructured — OCR-enabled)

Use the same patterns above but replace the image:

```yaml
services:
  data-loader:
    image: copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-unstruct:2.3.4
    # ... rest of configuration is identical
```

### OpenAI + PostgreSQL pgvector

```yaml
services:
  data-loader:
    image: copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-pypdf:2.3.4
    ports:
      - 8080:8080
    container_name: data-loader
    restart: unless-stopped
    volumes:
      - ${DOCS_DIR}:/docs
    environment:
      LOG_LEVEL: ${LOG_LEVEL}
      SECRET_KEY: ${SECRET_KEY}
      ACCESS_TOKEN_EXPIRE_DAYS: ${ACCESS_TOKEN_EXPIRE_DAYS}
      HASHED_ADMIN_PASSWORD: ${HASHED_ADMIN_PASSWORD}
      VECTORDB_PLUGIN_ENTRY_POINT: plugins.vectordbs.pgvector:PgVectorRetrieverPlugin
      MODEL_PLUGIN_ENTRY_POINT: plugins.models.openai:OpenAIPlugin
      EMBEDDINGS_PLUGIN_ENTRY_POINT: plugins.embeddings.openai:OpenAIEmbeddingsPlugin
      OPENAI_API_TYPE: openai
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      MODEL_NAME: ${MODEL_NAME}
      EMBEDDING_MODEL_NAME: ${EMBEDDING_MODEL_NAME}
      PGVECTOR_CONNECTION_STRING: ${PGVECTOR_CONNECTION_STRING}
```

> **Note:** `PGVECTOR_CONNECTION_STRING` format: `postgresql+psycopg://user:pass@host:5432/dbname`
> The pgvector database must have the `vector` extension enabled before loading documents.

---

## 13. Troubleshooting

### Container won't start

| Symptom | Cause | Fix |
|---|---|---|
| Exits immediately | Missing `SECRET_KEY` or `HASHED_ADMIN_PASSWORD` | Ensure both are set in your `.env` or environment |
| Plugin import error | Wrong plugin entry point string | Check spelling against the plugin tables in **[§11](#11-environment-variable-reference) Environment Variable Reference** |
| Image pull fails | Missing registry login or network/firewall blocking OCI registry | Authenticate Docker to `copilotoci.azurecr.io` and ensure outbound HTTPS is allowed |

### Authentication errors

| Symptom | Cause | Fix |
|---|---|---|
| `401 Unauthorized` | Token expired or not provided | Re-authenticate via `/admin/token` or `/client/token` |
| Login returns 400 | Wrong Content-Type | Use `application/x-www-form-urlencoded`, not JSON |
| Login returns 500 | Corrupted password hash | Regenerate with `generate_credentials.py`. In `.env`, wrap the hash in **single quotes** |

### Document loading errors

| Symptom | Cause | Fix |
|---|---|---|
| `/docs` directory empty in container | `DOCS_DIR` not set or wrong path | Verify `DOCS_DIR` in `.env` points to a real directory with files |
| Embedding errors | Wrong embedding model or API key | Verify `EMBEDDING_MODEL_NAME` and API credentials |
| Vector DB connection refused | Wrong URI/host or DB not running | Check `VECTORDB_URI` / `ZILLIZ_CLOUD_URI` / `PGVECTOR_CONNECTION_STRING` and connectivity |
| `ConnectionNotExistException` during `/load` with Milvus or Zilliz | Running an older image that predates the connection-alias fix | Upgrade the data-loader image to `2.3.4`, redeploy, and retry the load |
| pgvector "extension not found" | `vector` extension not installed | Run `CREATE EXTENSION IF NOT EXISTS vector;` on the target database |
| Timeout during loading | Large documents or slow network | Check logs; consider splitting large PDFs |

### Common `.env` mistakes

| Mistake | Fix |
|---|---|
| Double-quoting bcrypt hash: `"$2b$12$..."` | Use single quotes: `'$2b$12$...'` |
| Using `$$` in the `.env` file | `$$` is only needed inside `docker-compose.yml` directly — `.env` files use a single `$` |
| Missing `DOCS_DIR` | Add `DOCS_DIR=./pdf_docs` (or your actual path) |
| Spaces around `=` in `.env` | Remove spaces: `KEY=value` not `KEY = value` |

### Useful commands

```bash
# Check container status
docker compose ps

# View real-time logs
docker compose logs -f data-loader

# Restart the container
docker compose restart data-loader

# Stop and remove
docker compose down

# Rebuild with a fresh pull
docker compose pull && docker compose up -d
```

---

## 14. Security Best Practices

- **Never commit `.env` files to source control** — add `.env` to `.gitignore`
- **Use `generate_credentials.py`** for all password hashing — never use online tools
- **Rotate credentials regularly** — regenerate and restart
- **Run containers as non-root** — the Data Loader images already run as a non-root user (`spotuser`)
- **Limit network exposure** — if the Data Loader is only used internally, don't expose port 8080 externally
- **Keep images up to date** — always use the latest tagged version (`2.3.4`)
- **Use TLS in production** — place a reverse proxy in front of the container for HTTPS

---

*Copyright © 2006 – 2026 Cloud Software Group, Inc. All rights reserved.*
