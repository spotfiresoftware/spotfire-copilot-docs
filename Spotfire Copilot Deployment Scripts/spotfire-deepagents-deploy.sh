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
HOST_BIND_ARG=""
PUBLIC_BASE_URL_ARG=""
PERSISTENCE_ARG=""
DEPLOY_TARGET_ARG=""
CHART_VERSION_ARG=""
K8S_NAMESPACE_ARG=""
MODE="generate"
ROTATE_A2A_CREDENTIAL="no"

ALL_AGENTS="osdu_agent,databricks_agent,databricks_genie_agent,snowflake_agent,dv_agent,sf_lib_md_agent,sf_lic_agent,tavily_agent,milvus_agent,ddr_agent"

# Agent catalog rows: agent_id|ENV_PREFIX|cohost_port|display  (empty port = external MCP).
# The co-host port is the default localhost port that agent's MCP server publishes
# when co-located with this server (see the mcp-servers deployment guides).
AGENT_CATALOG=(
  "osdu_agent|OSDU|8063|OSDU"
  "databricks_agent|DATABRICKS|8061|Databricks"
  "dv_agent|DV|8065|Data Virtualization (DV)"
  "sf_lib_md_agent|SFLIB|8062|Spotfire Library Metadata"
  "sf_lic_agent|SFLIC|8064|Spotfire License Management"
  "tavily_agent|TAVILY|8058|Tavily Web Search"
  "ddr_agent|DDR|8060|Daily Drilling Reports (DDR)"
  "databricks_genie_agent|GENIE||Databricks Genie (external MCP)"
  "snowflake_agent|SNOWFLAKE||Snowflake (external MCP)"
  "milvus_agent|MILVUS||Milvus (external MCP)"
)

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

valid_bind_address() {
 [[ "${1:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
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
 ./spotfire-deepagents-deploy.sh
 ./spotfire-deepagents-deploy.sh --image-tag TAG
 ./spotfire-deepagents-deploy.sh --kubernetes
 ./spotfire-deepagents-deploy.sh --upgrade --image-tag TAG

Options:
 --help, -h                Show this help.
 --dir DIR                 Output/deployment directory.
 --image-tag TAG           Approved DeepAgents OSS image tag.
 --host-port PORT          Host port mapped to container port 8000 (Compose mode).
 --host-bind ADDRESS       Host interface to publish the port on. Default 127.0.0.1.
 --public-base-url URL     PUBLIC_BASE_URL. Defaults to http://localhost:<host-port>.
 --local                   Use local Compose PostgreSQL and Redis.
 --external                Use external PostgreSQL and Redis.
 --compose                 Generate a Docker Compose deployment (default).
 --kubernetes, --k8s       Generate a Kubernetes Helm values bundle instead.
 --chart-version VER       Approved Helm chart version (Kubernetes mode).
 --namespace NS            Kubernetes namespace (Kubernetes mode). Default deepagents-oss.
 --rotate-a2a-token        Generate a new bearer token/API key instead of reusing one.
 --upgrade                 Update IMAGE_TAG in an existing Compose deployment directory.

Notes:
 * The server always listens on container port 8000.
 * Compose mode publishes on 127.0.0.1 by default; use --host-bind to change it.
 * Agents are disabled unless you enable them in the "Agents and MCP wiring" step.
 * Deploy each agent's MCP server first, then enable the agent so DeepAgents can reach it.
 * Kubernetes mode writes values.yaml, create-secret.sh, and helm-install.sh under <dir>/k8s.
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
      --host-bind) HOST_BIND_ARG="${2:-}"; [[ -n "$HOST_BIND_ARG" ]] || die "--host-bind requires an address"; shift 2 ;;
      --public-base-url) PUBLIC_BASE_URL_ARG="${2:-}"; [[ -n "$PUBLIC_BASE_URL_ARG" ]] || die "--public-base-url requires a URL"; shift 2 ;;
      --local) PERSISTENCE_ARG="local"; shift ;;
      --external) PERSISTENCE_ARG="external"; shift ;;
      --compose) DEPLOY_TARGET_ARG="compose"; shift ;;
      --kubernetes|--k8s) DEPLOY_TARGET_ARG="kubernetes"; shift ;;
      --chart-version) CHART_VERSION_ARG="${2:-}"; [[ -n "$CHART_VERSION_ARG" ]] || die "--chart-version requires a value"; shift 2 ;;
      --namespace) K8S_NAMESPACE_ARG="${2:-}"; [[ -n "$K8S_NAMESPACE_ARG" ]] || die "--namespace requires a value"; shift 2 ;;
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
  local rendered
  rendered="$(mktemp "${TMPDIR:-/tmp}/deepagents-oss-compose-rendered.XXXXXX")" || die "Unable to create a temporary file for Compose validation."
  chmod 600 "$rendered" 2>/dev/null || true
  # 'docker compose config' interpolates values from .env (including the local
  # PostgreSQL password), so the rendered output is sensitive. Always remove it.
  if ! (cd "$OUT_DIR" && docker compose config > "$rendered"); then
    rm -f "$rendered"
    die "docker compose config failed. Review the Compose error above."
  fi
  rm -f "$rendered"
  ok "Docker Compose config validated."
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

# ------------------------------------------------------------------------------
# Agent catalog lookups and MCP wiring (shared by Compose and Kubernetes modes)
# ------------------------------------------------------------------------------
agent_prefix()  { local r i p q d; for r in "${AGENT_CATALOG[@]}"; do IFS='|' read -r i p q d <<< "$r"; [[ "$i" == "$1" ]] && { printf '%s' "$p"; return 0; }; done; return 1; }
agent_port()    { local r i p q d; for r in "${AGENT_CATALOG[@]}"; do IFS='|' read -r i p q d <<< "$r"; [[ "$i" == "$1" ]] && { printf '%s' "$q"; return 0; }; done; return 1; }
agent_display() { local r i p q d; for r in "${AGENT_CATALOG[@]}"; do IFS='|' read -r i p q d <<< "$r"; [[ "$i" == "$1" ]] && { printf '%s' "$d"; return 0; }; done; return 1; }

# Prefix every line of $2 with the indent string $1 (blank lines stay blank).
prefix_lines() {
  local indent="$1" text="$2" line
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then printf '\n'; else printf '%s%s\n' "$indent" "$line"; fi
  done <<< "$text"
}

# Interactive agent selection plus per-agent MCP wiring.
# Arg: target = compose|kubernetes
# Sets globals: AGENTS_ENABLED AGENTS_DISABLED MCP_ENV_BLOCK MCP_K8S_CONFIG_RAW MCP_SECRET_KV
configure_agents_and_mcp() {
  local target="$1"
  AGENTS_ENABLED=""; AGENTS_DISABLED="$ALL_AGENTS"
  MCP_ENV_BLOCK=""; MCP_K8S_CONFIG_RAW=""; MCP_SECRET_KV=""

  section "Agents and MCP wiring"
  info "Deploy each agent's MCP server first (see the mcp-servers guides), then enable the agent here so DeepAgents can reach it."
  info "Leave the selection blank to generate a base server with every agent disabled."

  local i=1 row id pfx port disp
  echo
  echo "Available agents:"
  for row in "${AGENT_CATALOG[@]}"; do
    IFS='|' read -r id pfx port disp <<< "$row"
    if [[ -n "$port" ]]; then
      echo "  ${i}) ${disp}  [${id} | ${pfx} | co-host port ${port}]"
    else
      echo "  ${i}) ${disp}  [${id} | ${pfx} | external MCP]"
    fi
    i=$((i + 1))
  done

  local choice
  read -r -p "Agents to enable (comma-separated numbers, 'all', or blank for none): " choice
  choice="$(trim "$choice")"

  local -a enabled=()
  if [[ "$choice" == "all" ]]; then
    for row in "${AGENT_CATALOG[@]}"; do enabled+=("${row%%|*}"); done
  elif [[ -n "$choice" ]]; then
    local oldifs="$IFS" p n
    IFS=','; local -a picks=($choice); IFS="$oldifs"
    for p in "${picks[@]}"; do
      p="$(trim "$p")"
      if [[ ! "$p" =~ ^[0-9]+$ ]]; then warn "Ignoring invalid selection: $p"; continue; fi
      n="$p"
      if (( n >= 1 && n <= ${#AGENT_CATALOG[@]} )); then
        enabled+=("${AGENT_CATALOG[$((n - 1))]%%|*}")
      else
        warn "Ignoring out-of-range selection: $p"
      fi
    done
  fi

  if [[ ${#enabled[@]} -eq 0 ]]; then
    warn "No agents enabled. Generating a base server with every agent disabled."
    return 0
  fi

  # De-duplicate while preserving order.
  local -a uniq=(); local a u seen
  for a in "${enabled[@]}"; do
    seen="no"
    for u in "${uniq[@]:-}"; do [[ "$u" == "$a" ]] && { seen="yes"; break; }; done
    [[ "$seen" == "no" ]] && uniq+=("$a")
  done
  enabled=("${uniq[@]}")

  AGENTS_ENABLED="$(IFS=,; printf '%s' "${enabled[*]}")"
  local -a disabled=(); local all_id oldifs2="$IFS"
  IFS=','; local -a all_arr=($ALL_AGENTS); IFS="$oldifs2"
  for all_id in "${all_arr[@]}"; do
    seen="no"
    for a in "${enabled[@]}"; do [[ "$a" == "$all_id" ]] && { seen="yes"; break; }; done
    [[ "$seen" == "no" ]] && disabled+=("$all_id")
  done
  AGENTS_DISABLED="$(IFS=,; printf '%s' "${disabled[*]}")"

  local id2 pfx2 port2 disp2 url transport token lc url_default
  for id2 in "${enabled[@]}"; do
    pfx2="$(agent_prefix "$id2")"; port2="$(agent_port "$id2")"; disp2="$(agent_display "$id2")"
    echo
    info "MCP wiring for ${disp2} (${id2})"
    if [[ "$target" == "compose" && -n "$port2" ]]; then
      url_default="http://host.docker.internal:${port2}/mcp"
    else
      url_default=""
    fi
    if [[ -n "$url_default" ]]; then
      prompt url "${pfx2}_MCP_SERVER_URL" "$url_default"
    else
      prompt_required url "${pfx2}_MCP_SERVER_URL (for example https://mcp-host/mcp)" ""
    fi
    url="$(strip_outer_quotes "$url")"
    prompt transport "${pfx2}_MCP_SERVER_TRANSPORT" "streamable-http"
    transport="$(strip_outer_quotes "$transport")"
    prompt token "${pfx2}_MCP_BEARER_TOKEN (blank if the MCP server has no inbound auth)" "" true
    token="$(strip_outer_quotes "$token")"

    MCP_ENV_BLOCK+="${pfx2}_MCP_SERVER_URL=${url}"$'\n'
    MCP_ENV_BLOCK+="${pfx2}_MCP_SERVER_TRANSPORT=${transport}"$'\n'
    [[ -n "$token" ]] && MCP_ENV_BLOCK+="${pfx2}_MCP_BEARER_TOKEN=${token}"$'\n'

    lc="$(printf '%s' "$pfx2" | tr '[:upper:]' '[:lower:]')"
    MCP_K8S_CONFIG_RAW+="${lc}McpServerUrl: \"${url}\""$'\n'
    MCP_K8S_CONFIG_RAW+="${lc}McpServerTransport: \"${transport}\""$'\n'
    [[ -n "$token" ]] && MCP_SECRET_KV+="${pfx2}_MCP_BEARER_TOKEN=${token}"$'\n'
  done
  return 0
}

# ------------------------------------------------------------------------------
# Kubernetes (Helm) mode: generate a values bundle. No live cluster calls here.
# ------------------------------------------------------------------------------
run_kubernetes_mode() {
  local k8s_dir="$OUT_DIR/k8s"
  mkdir -p "$k8s_dir"

  section "Kubernetes (Helm) mode"
  info "Generates a Helm values bundle for the DeepAgents OSS chart under: $k8s_dir"
  info "No cluster access is required now. Later, run create-secret.sh then helm-install.sh from a machine with kubectl and helm."

  local IMAGE_TAG
  while true; do
    prompt IMAGE_TAG "Approved DeepAgents OSS image tag" "${IMAGE_TAG_ARG:-$DEFAULT_IMAGE_TAG}"
    IMAGE_TAG="$(strip_outer_quotes "$IMAGE_TAG")"
    valid_image_tag "$IMAGE_TAG" && break
    warn "Enter an approved OCI image tag using letters, digits, '.', '_' or '-'."
  done
  local CHART_VERSION; prompt_required CHART_VERSION "Approved Helm chart version (--version)" "${CHART_VERSION_ARG:-}"
  local K8S_NAMESPACE; prompt K8S_NAMESPACE "Kubernetes namespace" "${K8S_NAMESPACE_ARG:-deepagents-oss}"
  local K8S_SECRET_NAME; prompt K8S_SECRET_NAME "Name of the Kubernetes Secret for DeepAgents secrets" "deepagents-oss-secrets"
  local K8S_PULL_SECRET; prompt K8S_PULL_SECRET "Image pull Secret name (blank if nodes already authenticate to the registry)" ""

  local K8S_PERSISTENCE
  choose_num K8S_PERSISTENCE "How should DeepAgents get PostgreSQL and Redis?" "1" \
    "external|External/managed PostgreSQL + Redis (app-only chart, production)" \
    "bundled|Bundled in-cluster PostgreSQL + Redis (stack chart, POC/dev)"
  local CHART_REF K8S_POSTGRES_URL="" K8S_REDIS_URL="" K8S_PG_PASSWORD=""
  if [[ "$K8S_PERSISTENCE" == "bundled" ]]; then
    CHART_REF="oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss-stack"
    K8S_PG_PASSWORD="$(random_token)"
    info "Generated a random in-cluster PostgreSQL password for the bundled stack."
  else
    CHART_REF="oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss"
    prompt_required K8S_POSTGRES_URL "External POSTGRES_URL" "" true
    prompt_required K8S_REDIS_URL "External REDIS_URL" "" true
    validate_runtime_url POSTGRES_URL "$K8S_POSTGRES_URL"
    validate_runtime_url REDIS_URL "$K8S_REDIS_URL"
  fi

  local PUBLIC_BASE_URL; prompt_required PUBLIC_BASE_URL "PUBLIC_BASE_URL (external URL clients use)" "https://deepagents.example.com"

  section "DeepAgents model"
  local LLM_PROVIDER DEEPAGENTS_MODEL PROVIDER_KEY_NAME MODEL_DEFAULT PROVIDER_KEY_VALUE
  choose_num LLM_PROVIDER "Which model provider will DeepAgents OSS use?" "1" \
    "openai|OpenAI" "anthropic|Anthropic" "google|Google Gemini API"
  case "$LLM_PROVIDER" in
    openai)    PROVIDER_KEY_NAME="OPENAI_API_KEY";    MODEL_DEFAULT="openai:gpt-4o" ;;
    anthropic) PROVIDER_KEY_NAME="ANTHROPIC_API_KEY"; MODEL_DEFAULT="anthropic:claude-3-5-sonnet-latest" ;;
    google)    PROVIDER_KEY_NAME="GOOGLE_API_KEY";    MODEL_DEFAULT="google:gemini-2.0-flash" ;;
  esac
  prompt_required PROVIDER_KEY_VALUE "$PROVIDER_KEY_NAME" "" true
  prompt_required DEEPAGENTS_MODEL "DEEPAGENTS_MODEL" "$MODEL_DEFAULT"
  case "$DEEPAGENTS_MODEL" in
    "$LLM_PROVIDER":*) ;;
    *) die "DEEPAGENTS_MODEL must start with '${LLM_PROVIDER}:' for the ${LLM_PROVIDER} provider." ;;
  esac

  section "A2A authentication"
  local A2A_AUTH_MODE A2A_SECRET_KEY="" A2A_SECRET_VALUE="" GEN
  choose_num A2A_AUTH_MODE "How should clients authenticate to DeepAgents?" "1" \
    "bearer|Bearer token (recommended)" \
    "none|None (isolated lab only)"
  if [[ "$A2A_AUTH_MODE" == "bearer" ]]; then
    yes_no_num GEN "Generate a new A2A bearer token automatically?" "yes"
    if [[ "$GEN" == "yes" ]]; then A2A_SECRET_VALUE="$(random_token)"; ok "Generated a new A2A bearer token."; else prompt_required A2A_SECRET_VALUE "A2A_BEARER_TOKENS" "" true; fi
    A2A_SECRET_KEY="A2A_BEARER_TOKENS"
  else
    warn "A2A authentication is disabled. Use this only in an isolated lab."
  fi

  configure_agents_and_mcp kubernetes

  # Assemble the config: children as raw 'key: "value"' lines (indent added later).
  local cfg=""
  cfg+="deepagentsModel: \"${DEEPAGENTS_MODEL}\""$'\n'
  cfg+="publicBaseUrl: \"${PUBLIC_BASE_URL}\""$'\n'
  cfg+="a2aAuthMode: \"${A2A_AUTH_MODE}\""$'\n'
  cfg+="a2aAuthPublicCard: \"false\""$'\n'
  cfg+="agentsEnabled: \"${AGENTS_ENABLED}\""$'\n'
  if [[ "$K8S_PERSISTENCE" == "external" ]]; then
    cfg+="postgresUrl: \"${K8S_POSTGRES_URL}\""$'\n'
    cfg+="redisUrl: \"${K8S_REDIS_URL}\""$'\n'
  fi
  [[ -n "$MCP_K8S_CONFIG_RAW" ]] && cfg+="$MCP_K8S_CONFIG_RAW"
  cfg="${cfg%$'\n'}"

  local pull_line=""
  [[ -n "$K8S_PULL_SECRET" ]] && pull_line="  - name: \"${K8S_PULL_SECRET}\""

  local values_file="$k8s_dir/values.yaml"
  if [[ "$K8S_PERSISTENCE" == "bundled" ]]; then
    {
      echo "# DeepAgents OSS full-stack Helm values (app + in-cluster PostgreSQL + Redis)."
      echo "# Chart: ${CHART_REF}"
      echo "# Per-agent MCP config keys follow the OSS deployment guide's documented convention."
      echo "copilot-deepagents-server-oss:"
      echo "  image:"
      echo "    registry: copilotoci.azurecr.io"
      echo "    repository: spotfirecopilot/copilot-deepagents-server-oss"
      echo "    tag: \"${IMAGE_TAG}\""
      if [[ -n "$pull_line" ]]; then
        echo "  imagePullSecrets:"
        echo "  ${pull_line}"
      fi
      echo "  config:"
      prefix_lines "    " "$cfg"
      echo "  secret:"
      echo "    create: false"
      echo "    existingSecretName: \"${K8S_SECRET_NAME}\""
      echo ""
      echo "postgresql:"
      echo "  enabled: true"
      echo "  postgres:"
      echo "    password: \"${K8S_PG_PASSWORD}\""
      echo ""
      echo "redis:"
      echo "  enabled: true"
    } > "$values_file"
  else
    {
      echo "# DeepAgents OSS app-only Helm values (bring-your-own PostgreSQL + Redis)."
      echo "# Chart: ${CHART_REF}"
      echo "# Per-agent MCP config keys follow the OSS deployment guide's documented convention."
      echo "image:"
      echo "  registry: copilotoci.azurecr.io"
      echo "  repository: spotfirecopilot/copilot-deepagents-server-oss"
      echo "  tag: \"${IMAGE_TAG}\""
      if [[ -n "$pull_line" ]]; then
        echo "imagePullSecrets:"
        echo "$pull_line"
      fi
      echo "config:"
      prefix_lines "  " "$cfg"
      echo "secret:"
      echo "  create: false"
      echo "  existingSecretName: \"${K8S_SECRET_NAME}\""
    } > "$values_file"
  fi
  chmod 600 "$values_file"
  ok "Wrote $values_file"

  local secret_file="$k8s_dir/create-secret.sh"
  {
    echo "#!/usr/bin/env bash"
    echo "set -Eeuo pipefail"
    echo "# Creates or updates the Kubernetes Secret referenced by values.yaml (secret.existingSecretName)."
    echo "# Requires kubectl configured against the target cluster."
    echo "NAMESPACE=\"${K8S_NAMESPACE}\""
    echo "SECRET_NAME=\"${K8S_SECRET_NAME}\""
    echo "kubectl create namespace \"\$NAMESPACE\" --dry-run=client -o yaml | kubectl apply -f -"
    echo "kubectl -n \"\$NAMESPACE\" create secret generic \"\$SECRET_NAME\" \\"
    printf '  --from-literal=%s='\''%s'\'' \\\n' "$PROVIDER_KEY_NAME" "$PROVIDER_KEY_VALUE"
    [[ -n "$A2A_SECRET_KEY" ]] && printf '  --from-literal=%s='\''%s'\'' \\\n' "$A2A_SECRET_KEY" "$A2A_SECRET_VALUE"
    while IFS='=' read -r sk sv; do
      [[ -z "$sk" ]] && continue
      printf '  --from-literal=%s='\''%s'\'' \\\n' "$sk" "$sv"
    done <<< "$MCP_SECRET_KV"
    echo "  --dry-run=client -o yaml | kubectl apply -f -"
  } > "$secret_file"
  chmod 700 "$secret_file"
  ok "Wrote $secret_file"

  local install_file="$k8s_dir/helm-install.sh"
  {
    echo "#!/usr/bin/env bash"
    echo "set -Eeuo pipefail"
    echo "# Installs or upgrades the DeepAgents OSS release. Run create-secret.sh first."
    echo "NAMESPACE=\"${K8S_NAMESPACE}\""
    echo "helm registry login copilotoci.azurecr.io"
    echo "helm upgrade --install deepagents-oss \\"
    echo "  ${CHART_REF} \\"
    echo "  --version \"${CHART_VERSION}\" \\"
    echo "  --namespace \"\$NAMESPACE\" \\"
    echo "  --create-namespace \\"
    echo "  -f \"\$(dirname \"\$0\")/values.yaml\""
  } > "$install_file"
  chmod 700 "$install_file"
  ok "Wrote $install_file"

  local summary_file="$k8s_dir/deepagents-k8s-summary.txt"
  {
    echo "DeepAgents OSS Kubernetes (Helm) bundle"
    echo "Generated: $(date)"
    echo
    echo "Namespace:      ${K8S_NAMESPACE}"
    echo "Chart:          ${CHART_REF}"
    echo "Chart version:  ${CHART_VERSION}"
    echo "Image tag:      ${IMAGE_TAG}"
    echo "Persistence:    ${K8S_PERSISTENCE}"
    echo "Model:          ${DEEPAGENTS_MODEL}"
    echo "A2A auth:       ${A2A_AUTH_MODE}"
    echo "Agents enabled: ${AGENTS_ENABLED:-<none>}"
    echo "Secret name:    ${K8S_SECRET_NAME}"
    echo
    echo "Files:"
    echo "  ${values_file}"
    echo "  ${secret_file}"
    echo "  ${install_file}"
  } > "$summary_file"
  chmod 600 "$summary_file"
  ok "Wrote $summary_file"

  section "Completed"
  ok "DeepAgents OSS Kubernetes bundle is ready in $k8s_dir"
  echo
  echo "Next:"
  echo "  1) Review $values_file (per-agent MCP config keys follow the OSS deployment guide)."
  echo "  2) bash \"$secret_file\"      # create the Kubernetes Secret"
  echo "  3) bash \"$install_file\"     # helm upgrade --install"
  echo "  4) kubectl -n ${K8S_NAMESPACE} get pods"
}

parse_args "$@"
[[ "$MODE" == "help" ]] && { usage; exit 0; }
[[ "$MODE" == "upgrade" ]] && { run_upgrade; exit 0; }

normalize_out_dir
mkdir -p "$OUT_DIR"
EXISTING_ENV="$OUT_DIR/.env"

section "DeepAgents OSS deployment"
info "Generates DeepAgents server configuration for Docker Compose or Kubernetes, including optional agent enablement and MCP wiring."
prompt OUT_DIR_INPUT "Output directory" "$OUT_DIR"
OUT_DIR="$OUT_DIR_INPUT"
normalize_out_dir
mkdir -p "$OUT_DIR"
EXISTING_ENV="$OUT_DIR/.env"

section "Deployment target"
if [[ -n "$DEPLOY_TARGET_ARG" ]]; then
  DEPLOY_TARGET="$DEPLOY_TARGET_ARG"
else
  choose_num DEPLOY_TARGET "How do you want to deploy the DeepAgents server?" "1" \
    "compose|Docker Compose on a single host" \
    "kubernetes|Kubernetes via a generated Helm values bundle"
fi
if [[ "$DEPLOY_TARGET" == "kubernetes" ]]; then
  run_kubernetes_mode
  exit 0
fi

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

# Publish the port on loopback by default so the server is not exposed to the
# network unless the operator explicitly opts in.
EXISTING_HOST_BIND="$(get_env_value "$EXISTING_ENV" DEEPAGENTS_HOST_BIND || true)"
if [[ -n "$HOST_BIND_ARG" ]]; then
  valid_bind_address "$HOST_BIND_ARG" || die "Invalid --host-bind address: $HOST_BIND_ARG"
  DEEPAGENTS_HOST_BIND="$HOST_BIND_ARG"
else
  BIND_DEFAULT_NUM="1"
 [[ "$EXISTING_HOST_BIND" == "0.0.0.0" ]] && BIND_DEFAULT_NUM="2"
  choose_num DEEPAGENTS_HOST_BIND "Which host interface should publish the DeepAgents port?" "$BIND_DEFAULT_NUM" \
    "127.0.0.1|Loopback only - safest; reach it through a reverse proxy or SSH tunnel" \
    "0.0.0.0|All interfaces - exposes the port to the network"
fi
if [[ "$DEEPAGENTS_HOST_BIND" != "127.0.0.1" ]]; then
  warn "The DeepAgents port will be published on ${DEEPAGENTS_HOST_BIND}, reachable beyond this host. Ensure A2A authentication and firewall rules are enforced."
fi

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
    [[ "$DEEPAGENTS_HOST_BIND" != "127.0.0.1" ]] && warn "A2A auth is 'none' while the port is published on ${DEEPAGENTS_HOST_BIND}; anyone who can reach it has unauthenticated access."
 ;;
  *) die "Unsupported A2A authentication mode: $A2A_AUTH_MODE" ;;
esac

configure_agents_and_mcp compose

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
# Generated by spotfire-deepagents-deploy.sh
#
# Agents are enabled only if selected during generation.
# Enable additional agents later only after their MCP servers are ready.
# ============================================================

IMAGE_TAG=${IMAGE_TAG}
HOST=${HOST}
PORT=8000
DEEPAGENTS_HOST_PORT=${DEEPAGENTS_HOST_PORT}
DEEPAGENTS_HOST_BIND=${DEEPAGENTS_HOST_BIND}
LOG_LEVEL=${LOG_LEVEL}
PUBLIC_BASE_URL=${PUBLIC_BASE_URL}

POSTGRES_URL=${POSTGRES_URL}
REDIS_URL=${REDIS_URL}
${POSTGRES_PASSWORD_LINE}

${A2A_AUTH_BLOCK}

${MODEL_SECRET_BLOCK}
DEEPAGENTS_MODEL=${DEEPAGENTS_MODEL}

# Agent allow-list and per-agent MCP wiring (configured interactively).
AGENTS_ENABLED=${AGENTS_ENABLED}
AGENTS_DISABLED=${AGENTS_DISABLED}
# AGENTS_CONFIG_FILE=/etc/deepagents/agents.yaml
${MCP_ENV_BLOCK}

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
      - "${DEEPAGENTS_HOST_BIND:-127.0.0.1}:${DEEPAGENTS_HOST_PORT:-8000}:8000"
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
      - "${DEEPAGENTS_HOST_BIND:-127.0.0.1}:${DEEPAGENTS_HOST_PORT:-8000}:8000"
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
Published interface: ${DEEPAGENTS_HOST_BIND}
Public base URL: ${PUBLIC_BASE_URL}
Persistence: ${PERSISTENCE_MODE}
Model: ${DEEPAGENTS_MODEL}
A2A authentication: ${A2A_AUTH_MODE}

Agents:
 Enabled:  ${AGENTS_ENABLED:-<none>}
 Disabled: ${AGENTS_DISABLED}
 Per-agent MCP endpoints are configured in .env (<PREFIX>_MCP_SERVER_URL/TRANSPORT/BEARER_TOKEN).

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
if [[ -z "$AGENTS_ENABLED" ]]; then
  warn "No agents are enabled. Re-run and select agents once their MCP servers are ready."
else
  info "Enabled agents: ${AGENTS_ENABLED}. Confirm each agent's MCP server is running and reachable."
fi

echo
echo "Next:"
echo "  cd $OUT_DIR"
echo "  docker login copilotoci.azurecr.io"
echo "  docker compose up -d"
echo "  curl -fsS http://localhost:${DEEPAGENTS_HOST_PORT}/healthz"
echo "  curl -fsS http://localhost:${DEEPAGENTS_HOST_PORT}/readyz"
