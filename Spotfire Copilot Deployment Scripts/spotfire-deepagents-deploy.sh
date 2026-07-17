#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_DIR="$(pwd)"
OUT_DIR="${OUT_DIR:-${START_DIR}/deepagents-oss-deploy}"
DEFAULT_IMAGE_TAG="${DEFAULT_IMAGE_TAG:-}"
IMAGE_TAG_ARG=""
HOST_PORT_ARG=""
PUBLIC_BASE_URL_ARG=""
PERSISTENCE_ARG=""
MODE="generate"
ROTATE_A2A_CREDENTIAL="no"

ALL_AGENTS="osdu_agent,databricks_agent,databricks_genie_agent,snowflake_agent,dv_agent,sf_lib_md_agent,sf_lic_agent,tavily_agent,milvus_agent,ddr_agent"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_STEP=$'\033[1;35m'; C_INFO=$'\033[1;36m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_OK=$'\033[1;32m'
else
  C_RESET=""; C_STEP=""; C_INFO=""; C_WARN=""; C_ERR=""; C_OK=""
fi

section() { echo; echo "${C_STEP}== $* ==${C_RESET}"; }
info()    { echo "${C_INFO}INFO:${C_RESET} $*"; }
ok()      { echo "${C_OK}OK:${C_RESET} $*"; }
warn()    { echo "${C_WARN}WARN:${C_RESET} $*" >&2; }
die()     { echo "${C_ERR}ERROR:${C_RESET} $*" >&2; exit 1; }
timestamp(){ date +"%Y%m%d_%H%M%S"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

trim() {
  printf '%s' "${1:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

strip_outer_quotes() {
  local value
  value="$(trim "${1:-}")"
  value="${value%$'\r'}"
  if [[ "$value" =~ ^\".*\"$ ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" =~ ^\'.*\'$ ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

backup_file() {
  local file="$1"
 [[ -f "$file" ]] || return 0
  local backup="${file}.bak.$(timestamp)"
  cp -p "$file" "$backup"
  chmod 600 "$backup" 2>/dev/null || true
  info "Backed up $file -> $backup"
}

write_file() {
  local file="$1" content="$2"
  mkdir -p "$(dirname "$file")"
  backup_file "$file"
  printf '%s\n' "$content" > "$file"
  chmod 600 "$file"
  ok "Wrote $file"
}

get_env_value() {
  local file="$1" key="$2" line value
 [[ -f "$file" ]] || return 1
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" | tail -n 1 || true)"
 [[ -n "$line" ]] || return 1
  value="${line#*=}"
  strip_outer_quotes "$value"
}

set_env_value() {
  local file="$1" key="$2" value="$3"
 [[ -f "$file" ]] || die "Cannot update missing file: $file"
  backup_file "$file"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key}=${value}|" "$file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$file"
  fi
  chmod 600 "$file"
}

random_token() {
  require_cmd openssl
  openssl rand -base64 48 | tr -d '\n' | tr '+/' '-_' | tr -d '='
}

prompt() {
  local var_name="$1" label="$2" default_value="${3:-}" secret="${4:-false}" input=""
  if [[ "$secret" == "true" ]]; then
    if [[ -n "$default_value" ]]; then
      read -r -s -p "${label} [press Enter to reuse existing]: " input; echo
    else
      read -r -s -p "${label}: " input; echo
    fi
  else
    if [[ -n "$default_value" ]]; then
      read -r -p "${label} [${default_value}]: " input
    else
      read -r -p "${label}: " input
    fi
  fi
  if [[ -z "$input" ]]; then
    printf -v "$var_name" '%s' "$default_value"
  else
    printf -v "$var_name" '%s' "$input"
  fi
}

prompt_required() {
  local var_name="$1" label="$2" default_value="${3:-}" secret="${4:-false}" value=""
  while true; do
    prompt value "$label" "$default_value" "$secret"
    value="$(strip_outer_quotes "$value")"
    if [[ -n "$value" ]]; then
      printf -v "$var_name" '%s' "$value"
      return 0
    fi
    warn "$label is required."
  done
}

choose_num() {
  local var_name="$1" label="$2" default_number="$3"; shift 3
  local options=("$@") choice option selected i
  while true; do
    echo
    echo "$label"
    i=1
    for option in "${options[@]}"; do
      echo "  ${i}) ${option#*|}"
      i=$((i + 1))
    done
    read -r -p "Enter number [${default_number}]: " choice
    choice="$(trim "${choice:-$default_number}")"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      selected="${options[$((choice - 1))]}"
      printf -v "$var_name" '%s' "${selected%%|*}"
      return 0
    fi
    warn "Enter a number from 1 to ${#options[@]}."
  done
}

yes_no_num() {
  local var_name="$1" label="$2" default_value="${3:-no}" default_number="2"
 [[ "$default_value" == "yes" ]] && default_number="1"
  choose_num "$var_name" "$label" "$default_number" "yes|Yes" "no|No"
}

valid_port() {
 [[ "${1:-}" =~ ^[0-9]+$ ]] && (( 1 <= 10#$1 && 10#$1 <= 65535 ))
}

prompt_port() {
  local var_name="$1" label="$2" default_value="${3:-8000}" value=""
  while true; do
    prompt value "$label" "$default_value"
    value="$(trim "$value")"
    if valid_port "$value"; then
      printf -v "$var_name" '%s' "$value"
      return 0
    fi
    warn "Enter a TCP port from 1 to 65535."
  done
}

valid_image_tag() {
 [[ "${1:-}" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$ ]]
}

validate_runtime_url() {
  local label="$1" value="$2"
 [[ -n "$value" ]] || die "$label cannot be empty."
  if [[ "$value" == *"<"* || "$value" == *">"* || "$value" == *"USER:PASS"* || "$value" == *"POSTGRES_HOST"* || "$value" == *"REDIS_HOST"* || "$value" == *"replace-me"* ]]; then
    die "$label still contains a placeholder: $value"
  fi
}

usage() {
  cat <<'HELP'
DeepAgents OSS base configuration generator

Usage:
 ./generate-deepagents-oss-env-v9.sh
 ./generate-deepagents-oss-env-v9.sh --image-tag TAG
 ./generate-deepagents-oss-env-v9.sh --upgrade --image-tag TAG

Options:
 --help, -h                Show this help.
 --dir DIR                 Output/deployment directory.
 --image-tag TAG           Approved DeepAgents OSS image tag.
 --host-port PORT          Host port mapped to container port 8000.
 --public-base-url URL     PUBLIC_BASE_URL. Defaults to http://localhost:<host-port>.
 --local                   Use local Compose PostgreSQL and Redis.
 --external                Use external PostgreSQL and Redis.
 --rotate-a2a-token        Generate a new bearer token/API key instead of reusing one.
 --upgrade                 Update IMAGE_TAG in an existing deployment directory.

Notes:
 * The server always listens on container port 8000.
 * This version intentionally disables every built-in agent.
 * MCP server setup and agent enablement will be added as separate future flows.
 * The script never runs 'docker compose down -v'.
HELP
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) MODE="help"; shift ;;
      --dir) OUT_DIR="${2:-}"; [[ -n "$OUT_DIR" ]] || die "--dir requires a directory"; shift 2 ;;
      --image-tag) IMAGE_TAG_ARG="${2:-}"; [[ -n "$IMAGE_TAG_ARG" ]] || die "--image-tag requires a tag"; shift 2 ;;
      --host-port) HOST_PORT_ARG="${2:-}"; [[ -n "$HOST_PORT_ARG" ]] || die "--host-port requires a port"; shift 2 ;;
      --public-base-url) PUBLIC_BASE_URL_ARG="${2:-}"; [[ -n "$PUBLIC_BASE_URL_ARG" ]] || die "--public-base-url requires a URL"; shift 2 ;;
      --local) PERSISTENCE_ARG="local"; shift ;;
      --external) PERSISTENCE_ARG="external"; shift ;;
      --rotate-a2a-token) ROTATE_A2A_CREDENTIAL="yes"; shift ;;
      --upgrade) MODE="upgrade"; shift ;;
      *) die "Unknown option: $1. Use --help." ;;
    esac
  done
}

normalize_out_dir() {
  if [[ "$OUT_DIR" != /* ]]; then
    OUT_DIR="${START_DIR}/${OUT_DIR}"
  fi
}

validate_compose() {
  require_cmd docker
  docker compose version >/dev/null 2>&1 || die "Docker Compose V2 is required."
  local rendered="/tmp/deepagents-oss-compose-rendered.yml"
  if ! (cd "$OUT_DIR" && docker compose config > "$rendered"); then
    die "docker compose config failed. Review the Compose error above."
  fi
  ok "Docker Compose config validated: $rendered"
}

run_upgrade() {
  normalize_out_dir
 [[ -d "$OUT_DIR" ]] || die "Deployment directory not found: $OUT_DIR"
 [[ -f "$OUT_DIR/.env" ]] || die "Missing $OUT_DIR/.env"
 [[ -f "$OUT_DIR/docker-compose.yml" ]] || die "Missing $OUT_DIR/docker-compose.yml"
 [[ -n "$IMAGE_TAG_ARG" ]] || die "--upgrade requires --image-tag <approved-tag>"
  valid_image_tag "$IMAGE_TAG_ARG" || die "Invalid image tag: $IMAGE_TAG_ARG"

  section "DeepAgents OSS upgrade"
  set_env_value "$OUT_DIR/.env" IMAGE_TAG "$IMAGE_TAG_ARG"
  ok "Updated IMAGE_TAG to $IMAGE_TAG_ARG"

  DEEPAGENTS_HOST_PORT="$(get_env_value "$OUT_DIR/.env" DEEPAGENTS_HOST_PORT || echo 8000)"
  valid_port "$DEEPAGENTS_HOST_PORT" || die "Invalid DEEPAGENTS_HOST_PORT in existing .env: $DEEPAGENTS_HOST_PORT"

  validate_compose
  echo
  echo "Next:"
  echo "  cd $OUT_DIR"
  echo "  docker login copilotoci.azurecr.io"
  echo "  docker compose up -d"
}

parse_args "$@"
[[ "$MODE" == "help" ]] && { usage; exit 0; }
[[ "$MODE" == "upgrade" ]] && { run_upgrade; exit 0; }

normalize_out_dir
mkdir -p "$OUT_DIR"
EXISTING_ENV="$OUT_DIR/.env"

section "DeepAgents OSS base deployment"
info "This version generates the base DeepAgents server configuration only. MCP servers and agent enablement are intentionally deferred."
prompt OUT_DIR_INPUT "Output directory" "$OUT_DIR"
OUT_DIR="$OUT_DIR_INPUT"
normalize_out_dir
mkdir -p "$OUT_DIR"
EXISTING_ENV="$OUT_DIR/.env"

# ------------------------------------------------------------------------------
# Image and server settings
# ------------------------------------------------------------------------------
section "Image and server settings"
EXISTING_IMAGE_TAG="$(get_env_value "$EXISTING_ENV" IMAGE_TAG || true)"
IMAGE_TAG_DEFAULT="${IMAGE_TAG_ARG:-${EXISTING_IMAGE_TAG:-$DEFAULT_IMAGE_TAG}}"
while true; do
  prompt IMAGE_TAG "Approved DeepAgents OSS image tag" "$IMAGE_TAG_DEFAULT"
  IMAGE_TAG="$(strip_outer_quotes "$IMAGE_TAG")"
  if valid_image_tag "$IMAGE_TAG"; then
    break
  fi
  warn "Enter an approved OCI image tag using letters, digits, '.', '_' or '-'."
done

EXISTING_HOST="$(get_env_value "$EXISTING_ENV" HOST || echo 0.0.0.0)"
prompt HOST "Server bind address (HOST)" "$EXISTING_HOST"
HOST="$(strip_outer_quotes "$HOST")"
[[ -n "$HOST" ]] || die "HOST cannot be empty."

# Keep the application port fixed. A separate host-published port avoids the
# previous host-port/container-port mismatch.
PORT=8000
EXISTING_HOST_PORT="$(get_env_value "$EXISTING_ENV" DEEPAGENTS_HOST_PORT || true)"
if [[ -z "$EXISTING_HOST_PORT" ]]; then
  OLD_PORT="$(get_env_value "$EXISTING_ENV" PORT || true)"
  if [[ -n "$OLD_PORT" && "$OLD_PORT" != "8000" ]] && valid_port "$OLD_PORT"; then
    EXISTING_HOST_PORT="$OLD_PORT"
    info "Migrating the previous PORT=$OLD_PORT value to DEEPAGENTS_HOST_PORT; container PORT remains 8000."
  fi
fi
HOST_PORT_DEFAULT="${HOST_PORT_ARG:-${EXISTING_HOST_PORT:-8000}}"
prompt_port DEEPAGENTS_HOST_PORT "Host-published DeepAgents port" "$HOST_PORT_DEFAULT"

EXISTING_PUBLIC_BASE_URL="$(get_env_value "$EXISTING_ENV" PUBLIC_BASE_URL || true)"
PUBLIC_BASE_URL_DEFAULT="${PUBLIC_BASE_URL_ARG:-${EXISTING_PUBLIC_BASE_URL:-http://localhost:${DEEPAGENTS_HOST_PORT}}}"
prompt_required PUBLIC_BASE_URL "PUBLIC_BASE_URL" "$PUBLIC_BASE_URL_DEFAULT"

EXISTING_LOG_LEVEL="$(get_env_value "$EXISTING_ENV" LOG_LEVEL || echo INFO)"
prompt LOG_LEVEL "LOG_LEVEL" "$EXISTING_LOG_LEVEL"
LOG_LEVEL="$(printf '%s' "$LOG_LEVEL" | tr '[:lower:]' '[:upper:]')"
case "$LOG_LEVEL" in DEBUG|INFO|WARNING|ERROR|CRITICAL) ;; *) die "Invalid LOG_LEVEL: $LOG_LEVEL" ;; esac

# ------------------------------------------------------------------------------
# Persistence
# ------------------------------------------------------------------------------
section "Persistence"
EXISTING_POSTGRES_URL="$(get_env_value "$EXISTING_ENV" POSTGRES_URL || true)"
EXISTING_REDIS_URL="$(get_env_value "$EXISTING_ENV" REDIS_URL || true)"
EXISTING_PERSISTENCE="local"
if [[ -n "$EXISTING_POSTGRES_URL" && "$EXISTING_POSTGRES_URL" != *"@deepagents-oss-postgres:"* ]]; then
  EXISTING_PERSISTENCE="external"
fi

if [[ -n "$PERSISTENCE_ARG" ]]; then
  PERSISTENCE_MODE="$PERSISTENCE_ARG"
else
  PERSISTENCE_DEFAULT_NUM="1"
 [[ "$EXISTING_PERSISTENCE" == "external" ]] && PERSISTENCE_DEFAULT_NUM="2"
  choose_num PERSISTENCE_MODE "How should DeepAgents use PostgreSQL and Redis?" "$PERSISTENCE_DEFAULT_NUM" \
    "local|Local Docker Compose PostgreSQL + Redis (dev/test or small non-production)" \
    "external|External/managed PostgreSQL + Redis (production pattern)"
fi

case "$PERSISTENCE_MODE" in
  local)
    EXISTING_POSTGRES_PASSWORD="$(get_env_value "$EXISTING_ENV" DEEPAGENTS_POSTGRES_PASSWORD || true)"
    if [[ -n "$EXISTING_POSTGRES_PASSWORD" ]]; then
      DEEPAGENTS_POSTGRES_PASSWORD="$EXISTING_POSTGRES_PASSWORD"
      ok "Reusing the existing local PostgreSQL password."
    else
      # A persisted volume initialized with an unknown password must not be paired
      # with a newly generated env password.
      if command -v docker >/dev/null 2>&1 && docker volume inspect deepagents-oss_deepagents-oss-postgres-data >/dev/null 2>&1; then
        die "The existing DeepAgents PostgreSQL volume was found, but no password exists in $EXISTING_ENV. Restore the original .env/password or intentionally remove the volume outside this script."
      fi
      DEEPAGENTS_POSTGRES_PASSWORD="$(random_token)"
      ok "Generated a new local PostgreSQL password."
    fi
    POSTGRES_URL="postgresql://postgres:${DEEPAGENTS_POSTGRES_PASSWORD}@deepagents-oss-postgres:5432/deepagents_checkpoints"
    REDIS_URL="redis://deepagents-oss-redis:6379/0"
 ;;
  external)
    prompt_required POSTGRES_URL "External POSTGRES_URL" "$EXISTING_POSTGRES_URL" true
    prompt_required REDIS_URL "External REDIS_URL" "$EXISTING_REDIS_URL" true
    validate_runtime_url POSTGRES_URL "$POSTGRES_URL"
    validate_runtime_url REDIS_URL "$REDIS_URL"
    DEEPAGENTS_POSTGRES_PASSWORD=""
 ;;
  *) die "Unsupported persistence mode: $PERSISTENCE_MODE" ;;
esac

# ------------------------------------------------------------------------------
# Model provider
# ------------------------------------------------------------------------------
section "DeepAgents model"
EXISTING_MODEL="$(get_env_value "$EXISTING_ENV" DEEPAGENTS_MODEL || true)"
EXISTING_PROVIDER="openai"
case "$EXISTING_MODEL" in
  anthropic:*) EXISTING_PROVIDER="anthropic" ;;
  google:*) EXISTING_PROVIDER="google" ;;
  openai:*) EXISTING_PROVIDER="openai" ;;
esac
PROVIDER_DEFAULT_NUM="1"
[[ "$EXISTING_PROVIDER" == "anthropic" ]] && PROVIDER_DEFAULT_NUM="2"
[[ "$EXISTING_PROVIDER" == "google" ]] && PROVIDER_DEFAULT_NUM="3"
choose_num LLM_PROVIDER "Which model provider will DeepAgents OSS use?" "$PROVIDER_DEFAULT_NUM" \
  "openai|OpenAI" \
  "anthropic|Anthropic" \
  "google|Google Gemini API"

MODEL_SECRET_BLOCK=""
case "$LLM_PROVIDER" in
  openai)
    EXISTING_PROVIDER_KEY="$(get_env_value "$EXISTING_ENV" OPENAI_API_KEY || true)"
    prompt_required OPENAI_API_KEY "OPENAI_API_KEY" "$EXISTING_PROVIDER_KEY" true
    MODEL_DEFAULT="$EXISTING_MODEL"
 [[ "$MODEL_DEFAULT" == openai:* ]] || MODEL_DEFAULT="openai:gpt-5.1"
    prompt_required DEEPAGENTS_MODEL "DEEPAGENTS_MODEL" "$MODEL_DEFAULT"
 [[ "$DEEPAGENTS_MODEL" == openai:* ]] || die "OpenAI selection requires DEEPAGENTS_MODEL=openai:<model>."
    MODEL_SECRET_BLOCK="OPENAI_API_KEY=${OPENAI_API_KEY}"$'\n'"# ANTHROPIC_API_KEY="$'\n'"# GOOGLE_API_KEY="
 ;;
  anthropic)
    EXISTING_PROVIDER_KEY="$(get_env_value "$EXISTING_ENV" ANTHROPIC_API_KEY || true)"
    prompt_required ANTHROPIC_API_KEY "ANTHROPIC_API_KEY" "$EXISTING_PROVIDER_KEY" true
    MODEL_DEFAULT="$EXISTING_MODEL"
 [[ "$MODEL_DEFAULT" == anthropic:* ]] || MODEL_DEFAULT="anthropic:claude-3-5-sonnet-latest"
    prompt_required DEEPAGENTS_MODEL "DEEPAGENTS_MODEL" "$MODEL_DEFAULT"
 [[ "$DEEPAGENTS_MODEL" == anthropic:* ]] || die "Anthropic selection requires DEEPAGENTS_MODEL=anthropic:<model>."
    MODEL_SECRET_BLOCK="# OPENAI_API_KEY="$'\n'"ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"$'\n'"# GOOGLE_API_KEY="
 ;;
  google)
    EXISTING_PROVIDER_KEY="$(get_env_value "$EXISTING_ENV" GOOGLE_API_KEY || true)"
    prompt_required GOOGLE_API_KEY "GOOGLE_API_KEY" "$EXISTING_PROVIDER_KEY" true
    MODEL_DEFAULT="$EXISTING_MODEL"
 [[ "$MODEL_DEFAULT" == google:* ]] || MODEL_DEFAULT="google:gemini-2.0-flash"
    prompt_required DEEPAGENTS_MODEL "DEEPAGENTS_MODEL" "$MODEL_DEFAULT"
 [[ "$DEEPAGENTS_MODEL" == google:* ]] || die "Google selection requires DEEPAGENTS_MODEL=google:<model>."
    MODEL_SECRET_BLOCK="# OPENAI_API_KEY="$'\n'"# ANTHROPIC_API_KEY="$'\n'"GOOGLE_API_KEY=${GOOGLE_API_KEY}"
 ;;
  *) die "Unsupported model provider: $LLM_PROVIDER" ;;
esac

# ------------------------------------------------------------------------------
# A2A authentication
# ------------------------------------------------------------------------------
section "A2A authentication"
EXISTING_A2A_MODE="$(get_env_value "$EXISTING_ENV" A2A_AUTH_MODE || echo bearer)"
A2A_DEFAULT_NUM="1"
[[ "$EXISTING_A2A_MODE" == "apikey" ]] && A2A_DEFAULT_NUM="2"
[[ "$EXISTING_A2A_MODE" == "none" ]] && A2A_DEFAULT_NUM="3"
choose_num A2A_AUTH_MODE "How should clients authenticate to DeepAgents?" "$A2A_DEFAULT_NUM" \
  "bearer|Bearer token (recommended)" \
  "apikey|API key header" \
  "none|None (isolated local lab only)"

A2A_AUTH_BLOCK="A2A_AUTH_MODE=${A2A_AUTH_MODE}"$'\n'"A2A_AUTH_PUBLIC_CARD=false"
case "$A2A_AUTH_MODE" in
  bearer)
    EXISTING_A2A_VALUE="$(get_env_value "$EXISTING_ENV" A2A_BEARER_TOKENS || true)"
    if [[ -n "$EXISTING_A2A_VALUE" && "$ROTATE_A2A_CREDENTIAL" != "yes" ]]; then
      A2A_BEARER_TOKENS="$EXISTING_A2A_VALUE"
      ok "Reusing the existing A2A bearer token."
    else
      yes_no_num GENERATE_A2A "Generate a new A2A bearer token automatically?" "yes"
      if [[ "$GENERATE_A2A" == "yes" ]]; then
        A2A_BEARER_TOKENS="$(random_token)"
      else
        prompt_required A2A_BEARER_TOKENS "A2A_BEARER_TOKENS" "" true
      fi
 [[ -n "$EXISTING_A2A_VALUE" ]] && warn "The A2A bearer token was rotated. Update every registered client that uses the old token."
    fi
    A2A_AUTH_BLOCK+=$'\n'"A2A_BEARER_TOKENS=${A2A_BEARER_TOKENS}"
 ;;
  apikey)
    EXISTING_HEADER="$(get_env_value "$EXISTING_ENV" A2A_API_KEY_HEADER || echo X-API-Key)"
    prompt_required A2A_API_KEY_HEADER "A2A_API_KEY_HEADER" "$EXISTING_HEADER"
    EXISTING_A2A_VALUE="$(get_env_value "$EXISTING_ENV" A2A_API_KEYS || true)"
    if [[ -n "$EXISTING_A2A_VALUE" && "$ROTATE_A2A_CREDENTIAL" != "yes" ]]; then
      A2A_API_KEYS="$EXISTING_A2A_VALUE"
      ok "Reusing the existing A2A API key."
    else
      yes_no_num GENERATE_A2A "Generate a new A2A API key automatically?" "yes"
      if [[ "$GENERATE_A2A" == "yes" ]]; then
        A2A_API_KEYS="$(random_token)"
      else
        prompt_required A2A_API_KEYS "A2A_API_KEYS" "" true
      fi
 [[ -n "$EXISTING_A2A_VALUE" ]] && warn "The A2A API key was rotated. Update every registered client that uses the old key."
    fi
    A2A_AUTH_BLOCK+=$'\n'"A2A_API_KEY_HEADER=${A2A_API_KEY_HEADER}"$'\n'"A2A_API_KEYS=${A2A_API_KEYS}"
 ;;
  none)
    warn "A2A authentication is disabled. Use this only in an isolated local lab."
 ;;
  *) die "Unsupported A2A authentication mode: $A2A_AUTH_MODE" ;;
esac

# ------------------------------------------------------------------------------
# Generate .env and Compose
# ------------------------------------------------------------------------------
section "Generate deployment files"
POSTGRES_PASSWORD_LINE=""
if [[ -n "$DEEPAGENTS_POSTGRES_PASSWORD" ]]; then
  POSTGRES_PASSWORD_LINE="DEEPAGENTS_POSTGRES_PASSWORD=${DEEPAGENTS_POSTGRES_PASSWORD}"
fi

ENV_CONTENT=$(cat <<ENV
# ============================================================
# DeepAgents OSS base server environment
# Generated by generate-deepagents-oss-env-v9.sh
#
# Agents are intentionally disabled in this base deployment.
# Enable agents later only after their MCP servers are ready.
# ============================================================

IMAGE_TAG=${IMAGE_TAG}
HOST=${HOST}
PORT=8000
DEEPAGENTS_HOST_PORT=${DEEPAGENTS_HOST_PORT}
LOG_LEVEL=${LOG_LEVEL}
PUBLIC_BASE_URL=${PUBLIC_BASE_URL}

POSTGRES_URL=${POSTGRES_URL}
REDIS_URL=${REDIS_URL}
${POSTGRES_PASSWORD_LINE}

${A2A_AUTH_BLOCK}

${MODEL_SECRET_BLOCK}
DEEPAGENTS_MODEL=${DEEPAGENTS_MODEL}

# Base deployment: no agents or MCP integrations are enabled yet.
AGENTS_ENABLED=
AGENTS_DISABLED=${ALL_AGENTS}
# AGENTS_CONFIG_FILE=/etc/deepagents/agents.yaml

# Optional common tuning
A2A_THREAD_LOCK_TTL_SECONDS=60
A2A_THREAD_LOCK_WAIT_SECONDS=5.0
MCP_TOOLS_CACHE_TTL_SECONDS=300
JWKS_CACHE_TTL_SECONDS=600
ENV
)
write_file "$OUT_DIR/.env" "$ENV_CONTENT"

if [[ "$PERSISTENCE_MODE" == "local" ]]; then
  COMPOSE_CONTENT=$(cat <<'YAML'
name: deepagents-oss

volumes:
 deepagents-oss-postgres-data:

services:
 deepagents-oss-redis:
 image: redis:7-alpine
 restart: unless-stopped
 healthcheck:
 test: ["CMD", "redis-cli", "ping"]
 interval: 5s
 timeout: 2s
 retries: 5

 deepagents-oss-postgres:
 image: postgres:16
 restart: unless-stopped
 environment:
 POSTGRES_DB: deepagents_checkpoints
 POSTGRES_USER: postgres
 POSTGRES_PASSWORD: ${DEEPAGENTS_POSTGRES_PASSWORD}
 volumes:
 - deepagents-oss-postgres-data:/var/lib/postgresql/data
 healthcheck:
 test: ["CMD-SHELL", "pg_isready -U postgres -d deepagents_checkpoints"]
 interval: 5s
 timeout: 2s
 retries: 10
 start_period: 10s

 deepagents-oss:
 image: copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss:${IMAGE_TAG}
 restart: unless-stopped
 depends_on:
 deepagents-oss-redis:
 condition: service_healthy
 deepagents-oss-postgres:
 condition: service_healthy
 ports:
 - "${DEEPAGENTS_HOST_PORT:-8000}:8000"
 env_file:
 - .env
 extra_hosts:
 - "host.docker.internal:host-gateway"
 healthcheck:
 test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8000/healthz"]
 interval: 10s
 timeout: 3s
 retries: 5
 start_period: 15s
YAML
)
else
  COMPOSE_CONTENT=$(cat <<'YAML'
name: deepagents-oss

services:
 deepagents-oss:
 image: copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss:${IMAGE_TAG}
 restart: unless-stopped
 ports:
 - "${DEEPAGENTS_HOST_PORT:-8000}:8000"
 env_file:
 - .env
 extra_hosts:
 - "host.docker.internal:host-gateway"
 healthcheck:
 test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8000/healthz"]
 interval: 10s
 timeout: 3s
 retries: 5
 start_period: 15s
YAML
)
fi
write_file "$OUT_DIR/docker-compose.yml" "$COMPOSE_CONTENT"

SUMMARY_CONTENT=$(cat <<SUMMARY
DeepAgents OSS base deployment
Generated: $(date)

Deployment directory: ${OUT_DIR}
Image tag: ${IMAGE_TAG}
Host URL: http://localhost:${DEEPAGENTS_HOST_PORT}
Public base URL: ${PUBLIC_BASE_URL}
Persistence: ${PERSISTENCE_MODE}
Model: ${DEEPAGENTS_MODEL}
A2A authentication: ${A2A_AUTH_MODE}

Agents:
 All built-in agents are currently disabled.
 Future agent enablement must add the matching MCP URL and credentials.

Files:
 ${OUT_DIR}/.env
 ${OUT_DIR}/docker-compose.yml

Validation after startup:
 curl -fsS http://localhost:${DEEPAGENTS_HOST_PORT}/healthz
 curl -fsS http://localhost:${DEEPAGENTS_HOST_PORT}/readyz
SUMMARY
)
write_file "$OUT_DIR/deepagents-deployment-summary.txt" "$SUMMARY_CONTENT"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  validate_compose
else
  warn "Docker Compose V2 is unavailable, so Compose validation was skipped."
fi

section "Completed"
ok "DeepAgents OSS base deployment files are ready in $OUT_DIR"
warn "All runtime agents are disabled until MCP configuration is added."

echo
echo "Next:"
echo "  cd $OUT_DIR"
echo "  docker login copilotoci.azurecr.io"
echo "  docker compose up -d"
echo "  curl -fsS http://localhost:${DEEPAGENTS_HOST_PORT}/healthz"
echo "  curl -fsS http://localhost:${DEEPAGENTS_HOST_PORT}/readyz"
