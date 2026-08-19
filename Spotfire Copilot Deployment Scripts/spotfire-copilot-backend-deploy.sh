#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_DIR="$(pwd)"
DEFAULT_IMAGE_TAG="${DEFAULT_IMAGE_TAG:-2.3.4}"
DEFAULT_AGENT_TAG="${DEFAULT_AGENT_TAG:-}"
# All installs live under a single parent folder, one subfolder per version:
#   <root>/spotfire-copilot/<image-tag>/backend
# The real backend directory is finalized once the image tag is known (interactive),
# or taken from --dir / the OUT_DIR environment variable.
COPILOT_ROOT_DIR="${COPILOT_ROOT_DIR:-${START_DIR}/spotfire-copilot}"
if [[ -n "${OUT_DIR:-}" ]]; then
  OUT_DIR_EXPLICIT="yes"
else
  OUT_DIR="${COPILOT_ROOT_DIR}/${DEFAULT_IMAGE_TAG}/backend"
  OUT_DIR_EXPLICIT="no"
fi
FROM_DIR=""
ASSUME_YES="no"
DEFAULT_CREDENTIALS_FILE=""
CREDENTIALS_SCRIPT="${CREDENTIALS_SCRIPT:-}"
MODE="interactive"
UPGRADE_IMAGE_TAG=""
UPGRADE_AGENT_TAG=""
FORCE_COLOR="auto"
INSTALL_PREREQS="prompt"
PYTHON_BIN="${PYTHON_BIN:-}"
POSTGRES_RESET_LOCAL_VOLUME_SELECTED="no"
LAST_DIR_STATE_DIR="${HOME:-/tmp}/.spotfire-copilot-env-generator"
LAST_DIR_FILE="${LAST_DIR_STATE_DIR}/last-dir"
WITH_DEEPAGENTS="no"
INSTALL_AGENT_REGISTRY_ONLY="no"
DEEPAGENTS_SCRIPT=""

# ---------- color / output helpers ----------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_INFO=$'\033[1;36m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_OK=$'\033[1;32m'; C_STEP=$'\033[1;35m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_BOLD=""; C_INFO=""; C_WARN=""; C_ERR=""; C_OK=""; C_STEP=""; C_DIM=""
fi
section() { echo; echo "${C_STEP}== $* ==${C_RESET}"; }
info() { echo "${C_INFO}INFO:${C_RESET} $*"; }
ok() { echo "${C_OK}OK:${C_RESET} $*"; }
warn() { echo "${C_WARN}WARN:${C_RESET} $*" >&2; }
die() { echo "${C_ERR}ERROR:${C_RESET} $*" >&2; exit 1; }
timestamp() { date +"%Y%m%d_%H%M%S"; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

# ---------- generic helpers ----------
strip_outer_quotes() {
  local value="${1:-}"
  value="${value%$'\r'}"
  value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [[ "$value" =~ ^\".*\"$ ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" =~ ^\'.*\'$ ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

get_existing() {
  local key="$1"; shift || true
  local f line val
  for f in "$@"; do
 [[ -f "$f" ]] || continue
    line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$f" | tail -n 1 || true)"
 [[ -n "$line" ]] || continue
    val="${line#*=}"
    strip_outer_quotes "$val"
    return 0
  done
  return 1
}

get_from_credentials_file() {
  local key="$1" file="$2"
 [[ -f "$file" ]] || return 1
  local line value
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*[:=]" "$file" | tail -n 1 || true)"
 [[ -n "$line" ]] || return 1
  if [[ "$line" == *"="* ]]; then value="${line#*=}"; else value="${line#*:}"; fi
  strip_outer_quotes "$value"
}

mask() {
  local value="${1:-}"
  local len="${#value}"
  if [[ -z "$value" ]]; then printf '<empty>'; elif (( len <= 8 )); then printf '****'; else printf '%s...%s' "${value:0:4}" "${value: -4}"; fi
}

prompt() {
  local var_name="$1" label="$2" default_value="${3:-}" secret="${4:-false}" default_hint="${5:-}" __prompt_input=""
  if [[ "$secret" == "true" ]]; then
    if [[ -n "$default_value" ]]; then read -r -s -p "${label} [${default_hint:-press Enter to reuse existing}]: " __prompt_input; echo; else read -r -s -p "${label}: " __prompt_input; echo; fi
  else
    if [[ -n "$default_value" ]]; then read -r -p "${label} [${default_value}]: " __prompt_input; else read -r -p "${label}: " __prompt_input; fi
  fi
  if [[ -z "$__prompt_input" ]]; then printf -v "$var_name" '%s' "$default_value"; else printf -v "$var_name" '%s' "$__prompt_input"; fi
}

# Prompt that refuses to accept a blank value. Used where a placeholder or empty
# value would silently produce a broken configuration.
prompt_required() {
  local var_name="$1" label="$2" default_value="${3:-}" secret="${4:-false}" value=""
  while true; do
    prompt value "$label" "$default_value" "$secret"
    value="$(strip_outer_quotes "$value")"
    if [[ -n "$value" ]]; then printf -v "$var_name" '%s' "$value"; return 0; fi
    warn "${label} cannot be blank."
  done
}

# PostgreSQL identifier rules (database name / username): must start with a letter
# or underscore, followed by letters, digits, or underscores; max 63 chars.
# This deliberately rejects pure numbers like "2" (a common slip when the prompt
# sits directly under a numbered menu) and anything with spaces, dots, or hyphens.
valid_pg_identifier() {
 [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]]
}

# Prompt for a PostgreSQL identifier, validating the input and the default.
# If the previously stored value is not a valid identifier (e.g. a stray "2"
# left over from an earlier run), it is ignored and the safe fallback is shown
# instead, so a bad value can never keep coming back as the default.
prompt_pg_identifier() {
  local var_name="$1" label="$2" stored="${3:-}" fallback="${4:-orchestrator}" def input=""
  if valid_pg_identifier "$stored"; then def="$stored"; else def="$fallback"; fi
  while true; do
    prompt input "$label" "$def"
    input="$(strip_outer_quotes "$input")"
    if valid_pg_identifier "$input"; then printf -v "$var_name" '%s' "$input"; return 0; fi
    warn "Invalid PostgreSQL name '$input'. Start with a letter or underscore, then letters, digits, or underscores (max 63 chars). Example: orchestrator"
  done
}

# Docker Compose project names are safest when limited to lowercase letters,
# digits, underscore and dash. This also protects against accidentally entering
# a numbered menu choice at a free-text prompt.
valid_compose_project_name() {
 [[ "${1:-}" =~ ^[a-z0-9][a-z0-9_-]{0,62}$ ]]
}

prompt_compose_project_name() {
  local var_name="$1" label="$2" stored="${3:-spotfire-copilot}" def value=""
  if valid_compose_project_name "$stored"; then def="$stored"; else def="spotfire-copilot"; fi
  while true; do
    prompt value "$label" "$def"
    value="$(strip_outer_quotes "$value")"
    if valid_compose_project_name "$value"; then printf -v "$var_name" '%s' "$value"; return 0; fi
    warn "Invalid Docker Compose project name '$value'. Use lowercase letters, digits, '-' or '_', and start with a lowercase letter or digit. Example: spotfire-copilot"
  done
}

prompt_log_level() {
  local var_name="$1" label="$2" stored="${3:-INFO}" def value=""
  def="$(printf '%s' "${stored:-INFO}" | tr '[:lower:]' '[:upper:]')"
  case "$def" in DEBUG|INFO|WARNING|WARN|ERROR|CRITICAL) ;; *) def="INFO" ;; esac
  while true; do
    prompt value "$label" "$def"
    value="$(strip_outer_quotes "$value" | tr '[:lower:]' '[:upper:]')"
 [[ "$value" == "WARN" ]] && value="WARNING"
    case "$value" in
      DEBUG|INFO|WARNING|ERROR|CRITICAL) printf -v "$var_name" '%s' "$value"; return 0 ;;
      *) warn "Invalid LOG_LEVEL '$value'. Use DEBUG, INFO, WARNING, ERROR, or CRITICAL." ;;
    esac
  done
}

prompt_positive_int() {
  local var_name="$1" label="$2" stored="${3:-30}" def value=""
  if [[ "$stored" =~ ^[0-9]+$ ]] && (( stored > 0 )); then def="$stored"; else def="30"; fi
  while true; do
    prompt value "$label" "$def"
    value="$(strip_outer_quotes "$value")"
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value > 0 )); then printf -v "$var_name" '%s' "$value"; return 0; fi
    warn "Invalid value '$value'. Enter a positive whole number. Example: 30"
  done
}

# OCI/Docker image tag rules: max 128 chars, must start with an alphanumeric or
# underscore, then alphanumerics, '.', '_' or '-'. Permits "2.3.4", "1.1.0", "latest".
valid_tag_format() {
 [[ "${1:-}" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$ ]]
}

# Best-effort existence check. Requires the user to be logged into the registry
# (docker login copilotoci.azurecr.io). Returns: 0 found, 1 not found, 2 unable to check.
tag_exists_in_registry() {
  return 2 
  local repo="$1" tag="$2"
  command -v docker >/dev/null 2>&1 || return 2
  docker manifest inspect "${repo}:${tag}" >/dev/null 2>&1 && return 0
  return 1
}

# Prompt for an image tag with format validation. If a repo is supplied and Docker
# is available/logged in, also verify the tag exists and warn (not hard-fail) on a
# miss. A blank entry is returned as-is so callers that require a value can re-ask.
prompt_image_tag() {
  local var_name="$1" label="$2" default_value="${3:-}" repo="${4:-}" tag="" rc=0
  while true; do
    prompt tag "$label" "$default_value"
    # Strip control characters first (stray CR/LF/tab from CRLF files or copy-paste,
    # common on Windows) so an otherwise-valid tag such as "2.3.6" is not falsely
    # rejected. Surrounding whitespace/quotes are removed next; genuine internal
    # spaces survive so real typos are still flagged.
    tag="$(printf '%s' "$tag" | tr -d '[:cntrl:]')"
    tag="$(strip_outer_quotes "$tag")"
    if [[ -z "$tag" ]]; then printf -v "$var_name" '%s' ""; return 0; fi
    if ! valid_tag_format "$tag"; then
      warn "Invalid image tag '$tag'. Allowed: letters, digits, '.', '_', '-' (max 128 chars). Example: 2.3.4 or latest"
      # Interactive users can simply retry. In a non-interactive/piped run there is
      # no one to correct the value, so fail fast instead of looping forever.
      [[ -t 0 ]] || die "Non-interactive input: no valid image tag was provided. Pass a valid tag such as 2.3.6 or latest."
      continue
    fi
    if [[ -n "$repo" ]]; then
      rc=0; tag_exists_in_registry "$repo" "$tag" || rc=$?
      case "$rc" in
        0) ok "Verified ${repo}:${tag} exists in the registry." ;;
        1) warn "Tag '${tag}' was not found in ${repo}. Check for a typo, or run 'docker login copilotoci.azurecr.io' first."
           yes_no_num USE_TAG_ANYWAY "Use '${tag}' anyway?" "no"
 [[ "$USE_TAG_ANYWAY" == "yes" ]] || continue ;;
        2) : ;;  # Docker unavailable / not usable here; skip existence check silently.
      esac
    fi
    printf -v "$var_name" '%s' "$tag"
    return 0
  done
}

choose_num() {
  local var_name="$1" label="$2" default_number="$3"; shift 3
  local options=("$@") choice="" i option value display selected
  while true; do
    echo; echo "$label"
    i=1
    for option in "${options[@]}"; do
      value="${option%%|*}"; display="${option#*|}"
      echo "  ${i}) ${display}"
      i=$((i + 1))
    done
    read -r -p "Enter number [${default_number}]: " choice
    choice="${choice:-$default_number}"
    choice="$(printf '%s' "$choice" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # Number-only input. Text shortcuts like "yes"/"no" are intentionally not
    # accepted; the user must enter the number shown in the menu.
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      selected="${options[$((choice - 1))]}"; printf -v "$var_name" '%s' "${selected%%|*}"; return 0
    fi

    warn "Please enter only the number shown — a number from 1 to ${#options[@]}."
  done
}

yes_no_num() {
  local var_name="$1" label="$2" default_value="${3:-no}" default_num="2"
 [[ "$default_value" == "yes" ]] && default_num="1"
  choose_num "$var_name" "$label" "$default_num" "yes|Yes" "no|No"
}

backup_file() { local file="$1"; [[ -f "$file" ]] || return 0; local backup="${file}.bak.$(timestamp)"; cp -p "$file" "$backup"; info "Backed up $file -> $backup"; }
write_file() { local file="$1" content="$2"; backup_file "$file"; printf '%s\n' "$content" > "$file"; chmod 600 "$file"; ok "Wrote $file"; }

urlencode() { python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}
single_quote_env_value() { local value="${1:-}"; value="${value//\'/\'\\\'\'}"; printf "'%s'" "$value"; }

compact_env_content() {
  printf '%s
' "$1" | sed -E '/^# (REQUIRED|OPTIONAL|RECOMMENDED|INFO|TODO|REQUIRED FOR RAG|REQUIRED FOR PRODUCTION):/d' | sed -E '/^[[:space:]]*$/N;/^\n$/D'
}
random_hex_32() { openssl rand -hex 32; }
# URL-safe random token (base64url, no padding) - matches the documented spec for
# AUTH_SIGNING_KEY ("URL-safe random key") and is equivalent to:
#   python -c "import secrets; print(secrets.token_urlsafe(32))"
random_urlsafe_token() { openssl rand -base64 32 | tr -d '\n' | tr '+/' '-_' | tr -d '='; }

build_database_urls() {
  local user_enc pass_enc async_base sync_base sslmode
  user_enc="$(urlencode "$POSTGRES_USER")"
  pass_enc="$(urlencode "$POSTGRES_PASSWORD")"
  async_base="postgresql+asyncpg://${user_enc}:${pass_enc}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
  sync_base="postgresql://${user_enc}:${pass_enc}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
  # Normalize DB_SSLMODE: trim + lowercase, then map common aliases to the
  # canonical libpq sslmode values. This prevents malformed URLs (e.g. a user
  # who types "DISABLE", "false", or "off" for a PostgreSQL without SSL).
  sslmode="$(printf '%s' "${DB_SSLMODE:-disable}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$sslmode" in
    ""|disable|disabled|false|off|none|no)        sslmode="disable" ;;
    true|on|yes|enable|enabled|ssl)               sslmode="require" ;;
    allow|prefer|require|verify-ca|verify-full)    ;;  # already canonical
    *) warn "Unrecognized DB_SSLMODE '${DB_SSLMODE}'; falling back to 'require'. Valid values: disable, allow, prefer, require, verify-ca, verify-full."
       sslmode="require" ;;
  esac
  DB_SSLMODE="$sslmode"   # write the normalized value back so the env file matches the URL

  # SQLAlchemy + asyncpg does not accept sslmode=... in the URL; it can raise:
  # TypeError: connect() got an unexpected keyword argument 'sslmode'.
  # asyncpg's async URL uses ssl=<mode>; the sync (psycopg2) URL uses sslmode=<mode>.
  # For "disable" we omit the SSL query ENTIRELY, because passing ssl=disable as a
  # string is treated as truthy by some asyncpg/SQLAlchemy versions and would wrongly
  # ENABLE SSL against a server that has none (the reported no-SSL failure).
  if [[ "$sslmode" == "disable" ]]; then
    DATABASE_URL="$async_base"
    SYNC_DATABASE_URL="$sync_base"
  else
    DATABASE_URL="${async_base}?ssl=${sslmode}"
    SYNC_DATABASE_URL="${sync_base}?sslmode=${sslmode}"
  fi
}

set_env_value() {
  local file="$1" key="$2" value="$3"
  touch "$file"; chmod 600 "$file"
  if grep -qE "^[[:space:]]*${key}=" "$file"; then
    sed -i.bak -E "s|^[[:space:]]*${key}=.*|${key}=${value}|" "$file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$file"
  fi
}
read_env_value() { local file="$1" key="$2"; [[ -f "$file" ]] || return 1; get_existing "$key" "$file"; }

patch_compose_image_refs() {
  local compose_file="$1"
 [[ -f "$compose_file" ]] || return 0
  cp -p "$compose_file" "${compose_file}.bak.$(timestamp)"
  sed -i -E 's|(copilotoci\.azurecr\.io/spotfirecopilot/llm-orchestrator:)[^[:space:]]+|\1${IMAGE_TAG}|g' "$compose_file"
  sed -i -E 's|(copilotoci\.azurecr\.io/spotfirecopilot/data-loader-pdf-pypdf:)[^[:space:]]+|\1${IMAGE_TAG}|g' "$compose_file"
  sed -i -E 's|(copilotoci\.azurecr\.io/spotfirecopilot/agent-container:)[^[:space:]]+|\1${AGENT_CONTAINER_TAG}|g' "$compose_file"
  ok "Patched image references in $compose_file to use variables."
}

print_help() {
  cat <<'HELP'
Spotfire Copilot 2.3.x Environment File Generator

Usage:
 ./spotfire-copilot-deploy.sh [options]

Interactive generation:
 ./spotfire-copilot-deploy.sh
 ./spotfire-copilot-deploy.sh --dir /opt/spotfire-copilot/backend
 # Default output directory is: ./spotfire-copilot/<image-tag>/backend

Info:
 ./spotfire-copilot-deploy.sh --info
 ./spotfire-copilot-deploy.sh --dir /opt/spotfire-copilot/backend --info

Upgrade tags and create a new versioned folder:
 ./spotfire-copilot-deploy.sh --upgrade --image-tag 2.3.6
 ./spotfire-copilot-deploy.sh --upgrade --image-tag 2.3.6 --from-dir /root/spotfire-copilot/2.3.4/backend
 ./spotfire-copilot-deploy.sh --upgrade --image-tag 2.3.6 --agent-tag 1.0.0

Options:
 --help              Show this help.
 --info              Show current generated env summary.
 --upgrade           Update IMAGE_TAG, FASTAPI_APP_VERSION, and optionally AGENT_CONTAINER_TAG.
 --image-tag TAG     Orchestrator/admin/data-loader image tag for upgrade mode.
 --agent-tag TAG     Agent Registry image tag for upgrade mode.
 --dir DIR           Output directory. Default: ./spotfire-copilot/<image-tag>/backend.
 --from-dir DIR      Source directory for upgrade mode. Defaults to last used directory.
 --yes, -y           Accept the auto-detected upgrade source without prompting (for non-interactive/CI runs).
 --install-prereqs   Install/check Linux prerequisites automatically when possible.
 --no-install-prereqs Do not install prerequisites; fail if Python/bcrypt are missing.
 --install-deepagents
 After core generation, run standalone generate-deepagents-oss-env.sh if found.
 --deepagents-script PATH
 Optional path to standalone DeepAgents installer.
 --credentials-script PATH
 Optional path to generate_credentials.py. Default: next to this installer.
 --install-agent-registry
 Add/update only Agent Registry in an existing backend folder. Use with --dir.
 Legacy alias also accepted: --install-agent-resgirty.
 --no-color          Disable colored output.

Credentials:
 This installer does not generate credentials itself. It runs generate_credentials.py,
 the official generator shipped with the Spotfire Copilot backend package.
 Place generate_credentials.py next to this installer:
   <this-script-directory>/generate_credentials.py
 If you already have credentials, answer Yes at the credentials question and provide
 the existing copilot-generated-values.txt instead.
 Expected keys: SECRET_KEY, HASHED_ADMIN_PASSWORD, OAUTH2_CLIENT_ID, OAUTH2_CLIENT_SECRET_HASH.
HELP
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) MODE="help"; shift ;;
      --info) MODE="info"; shift ;;
      --upgrade) MODE="upgrade"; shift ;;
      --image-tag) UPGRADE_IMAGE_TAG="${2:-}"; shift 2 ;;
      --agent-tag) UPGRADE_AGENT_TAG="${2:-}"; shift 2 ;;
      --dir) OUT_DIR="${2:-}"; OUT_DIR_EXPLICIT="yes"; shift 2 ;;
      --from-dir) FROM_DIR="${2:-}"; shift 2 ;;
      --yes|-y) ASSUME_YES="yes"; shift ;;
      --install-prereqs) INSTALL_PREREQS="yes"; shift ;;
      --no-install-prereqs) INSTALL_PREREQS="no"; shift ;;
      --install-deepagents|--with-deepagents) WITH_DEEPAGENTS="yes"; shift ;;
      --deepagents-script) DEEPAGENTS_SCRIPT="${2:-}"; shift 2 ;;
      --credentials-script) CREDENTIALS_SCRIPT="${2:-}"; shift 2 ;;
      --install-agent-registry|--install-agent-resgirty) MODE="agent_registry_only"; INSTALL_AGENT_REGISTRY_ONLY="yes"; shift ;;
      --no-color) FORCE_COLOR="no"; shift ;;
      *) die "Unknown option: $1. Use --help." ;;
    esac
  done
}


normalize_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then printf '%s' "$p"; else printf '%s/%s' "$(pwd)" "$p"; fi
}

remember_out_dir() {
  mkdir -p "$LAST_DIR_STATE_DIR"
  printf '%s\n' "$OUT_DIR" > "$LAST_DIR_FILE"
  chmod 700 "$LAST_DIR_STATE_DIR" 2>/dev/null || true
  chmod 600 "$LAST_DIR_FILE" 2>/dev/null || true
}

last_out_dir() {
 [[ -f "$LAST_DIR_FILE" ]] || return 1
  local d
  d="$(head -n 1 "$LAST_DIR_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
 [[ -n "$d" ]] || return 1
  printf '%s' "$d"
}

detect_default_credentials_file() {
  local candidate
  for candidate in     "$START_DIR/copilot-generated-values.txt"     "$SCRIPT_DIR/copilot-generated-values.txt"     "$OUT_DIR/copilot-generated-values.txt"; do
    if [[ -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  printf '%s' "$OUT_DIR/copilot-generated-values.txt"
}

copy_credentials_to_out_dir() {
  local source_file="$1" target_file="$OUT_DIR/copilot-generated-values.txt"
 [[ -f "$source_file" ]] || return 0
  if [[ "$source_file" != "$target_file" ]]; then
    cp -p "$source_file" "$target_file"
    chmod 600 "$target_file" 2>/dev/null || true
    ok "Copied credential file into backend folder: $target_file"
  fi
  CREDENTIALS_FILE="$target_file"
}

normalize_credentials_path() {
  local p="$1"
  if [[ -d "$p" || "$p" == */ ]]; then
    p="${p%/}/copilot-generated-values.txt"
  fi
  printf '%s' "$p"
}

# The Compose "postgres_data" volume is given a stable, version-independent name of
# "<project>_postgres_data" (the image tag is NOT part of the name) so the database
# survives image-tag upgrades. Scope all detection/reset logic to THIS deployment's
# project volume so we never match (or delete) a postgres_data volume that belongs to
# another project on the same host.
compose_postgres_volume_name() {
  printf '%s_postgres_data' "${COMPOSE_PROJECT_NAME:-spotfire-copilot}"
}

existing_backend_state_detected() {
 [[ -f "$OUT_DIR/.env.orchestrator" ]] && return 0
  if command -v docker >/dev/null 2>&1; then
    docker volume inspect "$(compose_postgres_volume_name)" >/dev/null 2>&1 && return 0
  fi
  return 1
}


existing_compose_postgres_volume_detected() {
  command -v docker >/dev/null 2>&1 || return 1
  docker volume inspect "$(compose_postgres_volume_name)" >/dev/null 2>&1
}

write_reset_compose_postgres_helper() {
  local helper="$OUT_DIR/reset-local-postgres-volume.sh"

  cat > "$helper" <<'HELPER'
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/.env"

cd "$SCRIPT_DIR"

if [[ ! -f "$COMPOSE_FILE" ]]; then
 echo "ERROR: docker-compose.yml not found at: $COMPOSE_FILE" >&2
 exit 1
fi

PROJECT_NAME=""
IMAGE_TAG=""
if [[ -f "$ENV_FILE" ]]; then
 PROJECT_NAME="$(awk -F= '/^COMPOSE_PROJECT_NAME=/{val=$0; sub(/^[^=]*=/,"",val)} END{print val}' "$ENV_FILE" | tr -d '\r')"
 IMAGE_TAG="$(awk -F= '/^IMAGE_TAG=/{val=$0; sub(/^[^=]*=/,"",val)} END{print val}' "$ENV_FILE" | tr -d '\r')"
fi

PROJECT_NAME="${PROJECT_NAME:-spotfire-copilot}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
POSTGRES_VOLUME="${PROJECT_NAME}_postgres_data"

cat <<WARN
This will stop the Copilot Docker Compose stack and delete ONLY the local PostgreSQL volume below:

 $POSTGRES_VOLUME

Use this only for a fresh lab/test install where Copilot backend data can be discarded.
It will remove users, OAuth clients, conversations, threads, agents, and any other state stored in the local Postgres volume.

It will NOT run:
 docker compose down -v

Instead, it will run:
 docker compose down
 (back up the volume to a local .tgz snapshot)
 docker volume rm "$POSTGRES_VOLUME"
 docker compose up -d --force-recreate
WARN

if ! docker volume inspect "$POSTGRES_VOLUME" >/dev/null 2>&1; then
 echo "ERROR: Expected PostgreSQL volume was not found: $POSTGRES_VOLUME" >&2
 echo
 echo "Available postgres_data-like volumes:" >&2
 docker volume ls -q | grep -E '_postgres_data(_|$)' >&2 || true
 echo
 echo "No volume was deleted." >&2
 exit 1
fi

read -r -p "Type DELETE to remove only $POSTGRES_VOLUME: " answer
if [[ "$answer" != "DELETE" ]]; then
 echo "Cancelled."
 exit 1
fi

docker compose --project-directory "$SCRIPT_DIR" -f "$COMPOSE_FILE" down
BACKUP_FILE="$SCRIPT_DIR/postgres_data_backup_$(date +%Y%m%d_%H%M%S).tgz"
echo "Backing up volume $POSTGRES_VOLUME to $BACKUP_FILE before deletion..."
if ! docker run --rm -v "$POSTGRES_VOLUME":/from -v "$SCRIPT_DIR":/backup alpine tar czf "/backup/$(basename "$BACKUP_FILE")" -C /from . ; then
 echo "ERROR: Backup failed; aborting without deleting the volume." >&2
 docker compose --project-directory "$SCRIPT_DIR" -f "$COMPOSE_FILE" up -d
 exit 1
fi
echo "Backup complete: $BACKUP_FILE"
docker volume rm "$POSTGRES_VOLUME"
docker compose --project-directory "$SCRIPT_DIR" -f "$COMPOSE_FILE" up -d --force-recreate
HELPER

  chmod 700 "$helper"
  ok "Wrote local PostgreSQL reset helper: $helper"
}

warn_admin_password_regeneration_existing_state() {
  if existing_backend_state_detected; then
    warn "Existing Copilot env files or PostgreSQL volume detected. Generating a new HASHED_ADMIN_PASSWORD updates the env file, but it may not reset the already-created admin user stored in PostgreSQL. For an existing deployment, reuse the original admin password or reset it through the application/database process. Only recreate the PostgreSQL volume for a fresh lab install where data can be discarded."
  fi
}

set_default_dir_for_info() {
  if [[ "$OUT_DIR_EXPLICIT" == "no" ]]; then
    local last=""
    last="$(last_out_dir || true)"
 [[ -n "$last" ]] && OUT_DIR="$last"
  fi
}

versioned_backend_dir() {
  # Standard backend path for a given image tag: <root>/spotfire-copilot/<tag>/backend
  printf '%s/%s/backend' "$COPILOT_ROOT_DIR" "$1"
}

versioned_backend_dir_from_source() {
  local src_dir="$1" tag="$2" ver_dir root
  ver_dir="$(dirname "$src_dir")"   # <root>/spotfire-copilot/<oldtag>  (new layout)
  root="$(dirname "$ver_dir")"      # <root>/spotfire-copilot           (new layout)
  # If the source does not follow the new "<root>/spotfire-copilot/<tag>/backend"
  # layout (e.g. an older "spotfire-copilot-<tag>/backend" install), fall back to the
  # standard versioned root so upgrades migrate into the new structure.
  if [[ "$(basename "$root")" != "spotfire-copilot" ]]; then
    root="$COPILOT_ROOT_DIR"
  fi
  printf '%s/%s/backend' "$root" "$tag"
}

finalize_out_dir_for_tag() {
  # Finalize the interactive backend directory once the image tag is known. Honors an
  # explicit --dir/OUT_DIR; otherwise defaults to the versioned path and lets the user
  # confirm or override it. Creates the directory and refreshes existing-file/credential
  # detection so re-runs of the same tag reuse prior values.
  local tag="$1" computed="" input=""
  if [[ "$OUT_DIR_EXPLICIT" == "no" ]]; then
    computed="$(versioned_backend_dir "$tag")"
    read -r -p "Backend output directory [${computed}]: " input || true
    input="$(printf '%s' "$input" | tr -d '[:cntrl:]')"
    input="$(strip_outer_quotes "$input")"
    [[ -n "$input" ]] && computed="$input"
    OUT_DIR="$computed"
  fi
  mkdir -p "$OUT_DIR"; cd "$OUT_DIR"; OUT_DIR="$(pwd)"
  DEFAULT_CREDENTIALS_FILE="$(detect_default_credentials_file)"
  EXISTING_FILES=("$OUT_DIR/.env" "$OUT_DIR/.env.orchestrator" "$OUT_DIR/.env.dataloader" "$OUT_DIR/.env.agent-registry")
  info "Backend output directory: $OUT_DIR"
}

copy_existing_config_to_new_dir() {
  local from="$1" to="$2" f
  mkdir -p "$to"
  for f in .env .env.orchestrator .env.dataloader .env.agent-registry docker-compose.yml copilot-generated-values.txt; do
    if [[ -f "$from/$f" ]]; then
      cp -p "$from/$f" "$to/$f"
    fi
  done
}

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then "$@"; else command -v sudo >/dev/null 2>&1 || die "sudo is required to install packages as non-root."; sudo "$@"; fi
}

select_python_bin() {
  local candidate
  for candidate in "${PYTHON_BIN:-}" python3.12 python3.11 python3; do
 [[ -n "$candidate" ]] || continue
    command -v "$candidate" >/dev/null 2>&1 || continue
    if "$candidate" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 11) else 1)
PY
    then
      PYTHON_BIN="$(command -v "$candidate")"
      return 0
    fi
  done
  return 1
}

python_version_ok() {
  select_python_bin
}

python_has_bcrypt() {
 [[ -n "${PYTHON_BIN:-}" ]] || select_python_bin || return 1
  "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1
import bcrypt
PY
}

install_python_packages_linux() {
  if command -v dnf >/dev/null 2>&1; then
    # RHEL/Rocky/Alma 9 keep python3 at 3.9. Install the versioned 3.11 package instead.
    run_as_root dnf install -y python3.11 python3.11-pip || run_as_root dnf install -y python3.12 python3.12-pip
  elif command -v yum >/dev/null 2>&1; then
    run_as_root yum install -y python3.11 python3.11-pip || run_as_root yum install -y python3.12 python3.12-pip
  elif command -v apt-get >/dev/null 2>&1; then
    run_as_root apt-get update
    run_as_root apt-get install -y python3.11 python3.11-venv python3-pip || run_as_root apt-get install -y python3 python3-pip
  elif command -v zypper >/dev/null 2>&1; then
    run_as_root zypper --non-interactive install python311 python311-pip || run_as_root zypper --non-interactive install python3 python3-pip
  elif command -v apk >/dev/null 2>&1; then
    run_as_root apk add --no-cache python3 py3-pip
  else
    die "No supported package manager found. Install Python 3.11+ and pip manually, then rerun."
  fi
}

install_bcrypt_python_module() {
 [[ -n "${PYTHON_BIN:-}" ]] || select_python_bin || die "Python 3.11+ is required before installing bcrypt."
  local venv_dir="$OUT_DIR/.credential-generator-venv"
  if "$PYTHON_BIN" -m venv "$venv_dir" >/dev/null 2>&1; then
    "$venv_dir/bin/python" -m pip install --upgrade pip >/dev/null 2>&1 || true
    "$venv_dir/bin/python" -m pip install bcrypt
    PYTHON_BIN="$venv_dir/bin/python"
    ok "Created isolated credential-generator Python environment: $venv_dir"
  else
    warn "Python venv creation failed. Falling back to --user pip install for bcrypt."
    "$PYTHON_BIN" -m pip install --user bcrypt
  fi
}

ensure_linux_prereqs() {
  section "Linux prerequisites"
  info "Python 3.11+ and bcrypt are needed only to generate Spotfire Copilot credentials. Docker/Compose must already be available for deployment."

  if ! python_version_ok; then
    if [[ "$INSTALL_PREREQS" == "no" ]]; then die "Python 3.11+ is missing or outdated."; fi
    if [[ "$INSTALL_PREREQS" == "prompt" ]]; then
      yes_no_num INSTALL_PY_NOW "Python 3.11+ is missing or outdated. Install Python/pip using the OS package manager?" "yes"
 [[ "$INSTALL_PY_NOW" == "yes" ]] || die "Python 3.11+ is required for automatic credential generation."
    fi
    install_python_packages_linux
  fi
  python_version_ok || die "Python 3.11+ is still not available after prerequisite installation."
  ok "Python is available: $($PYTHON_BIN --version 2>&1) at $PYTHON_BIN"

  if ! python_has_bcrypt; then
    if [[ "$INSTALL_PREREQS" == "no" ]]; then die "Python module bcrypt is missing."; fi
    if [[ "$INSTALL_PREREQS" == "prompt" ]]; then
      yes_no_num INSTALL_BCRYPT_NOW "Python module bcrypt is missing. Install it with pip now?" "yes"
 [[ "$INSTALL_BCRYPT_NOW" == "yes" ]] || die "bcrypt is required for automatic credential generation."
    fi
    install_bcrypt_python_module
  fi
  python_has_bcrypt || die "Python module bcrypt is still unavailable after installation."
  ok "Python bcrypt module is available."
}

# Locate the official Spotfire Copilot credential generator (generate_credentials.py).
# This installer does NOT reimplement credential generation: it runs the generator
# shipped with the Copilot backend package, exactly like a manual run, and then reads
# the values it produces.
find_credentials_script() {
  local candidate
  if [[ -n "${CREDENTIALS_SCRIPT:-}" ]]; then
    if [[ -f "$CREDENTIALS_SCRIPT" ]]; then printf '%s' "$CREDENTIALS_SCRIPT"; return 0; fi
    return 1
  fi
  for candidate in \
    "$SCRIPT_DIR/generate_credentials.py" \
    "$START_DIR/generate_credentials.py" \
    "$OUT_DIR/generate_credentials.py"; do
    if [[ -f "$candidate" ]]; then printf '%s' "$candidate"; return 0; fi
  done
  return 1
}

# Ask the user to place generate_credentials.py next to this installer, and keep
# checking until it is found, a path is supplied, or the user stops.
resolve_credentials_script() {
  local found=""
  while true; do
    if found="$(find_credentials_script)"; then
      CREDENTIALS_SCRIPT="$found"
      ok "Found credential generator: $CREDENTIALS_SCRIPT"
      return 0
    fi
    warn "generate_credentials.py was not found."
    info "generate_credentials.py is the official credential generator shipped with the Spotfire Copilot backend package."
    info "Copy it next to this installer, then continue:"
    info "  $SCRIPT_DIR/generate_credentials.py"
    choose_num CREDENTIALS_SCRIPT_ACTION "How do you want to continue?" "1" \
      "retry|I have placed generate_credentials.py next to this installer - check again" \
      "path|Let me enter the full path to generate_credentials.py" \
      "abort|Stop here so I can get generate_credentials.py first"
    case "$CREDENTIALS_SCRIPT_ACTION" in
      retry) : ;;
      path)
        prompt CREDENTIALS_SCRIPT "Full path to generate_credentials.py" ""
        CREDENTIALS_SCRIPT="$(strip_outer_quotes "$CREDENTIALS_SCRIPT")"
        if [[ ! -f "$CREDENTIALS_SCRIPT" ]]; then
          warn "File not found: $CREDENTIALS_SCRIPT"
          CREDENTIALS_SCRIPT=""
        fi
        ;;
      abort)
        die "generate_credentials.py is required to generate credentials. Copy it next to this installer (or pass --credentials-script /path/to/generate_credentials.py) and re-run."
        ;;
    esac
  done
}

# Run generate_credentials.py and capture the credentials it produces.
# Handles both generator styles: printing the values to stdout, or writing its own
# output file. The result is normalized into $file (copilot-generated-values.txt).
generate_credentials_file() {
  local file="$1"
  file="$(normalize_credentials_path "$file")"
  CREDENTIALS_FILE="$file"
  mkdir -p "$(dirname "$file")"

  resolve_credentials_script

  local work_dir console_log produced rc=0
  work_dir="$(mktemp -d)"
  console_log="$work_dir/.credential-generator-console.log"

  info "Running credential generator (this is the same as running it manually):"
  info "  $PYTHON_BIN $CREDENTIALS_SCRIPT"
  echo
  # Run it in a scratch directory so that anything it writes is easy to detect.
  # Output is shown live and captured at the same time.
  set +o pipefail
  ( cd "$work_dir" && "$PYTHON_BIN" "$CREDENTIALS_SCRIPT" ) 2>&1 | tee "$console_log"
  rc="${PIPESTATUS[0]}"
  set -o pipefail
  echo
  if [[ "$rc" -ne 0 ]]; then
    rm -rf "$work_dir"
    die "generate_credentials.py failed (exit code $rc). Fix the error above, then re-run this installer."
  fi

  # Prefer a file the generator wrote itself; otherwise use what it printed.
  produced="$(find "$work_dir" -maxdepth 1 -type f ! -name '.credential-generator-console.log' 2>/dev/null | head -n 1 || true)"
  if [[ -n "$produced" ]]; then
    info "Credential generator wrote: $(basename "$produced")"
    cp "$produced" "$file"
  else
    cp "$console_log" "$file"
  fi
  rm -rf "$work_dir"
  chmod 600 "$file"

  # The generated file must contain everything this installer needs. Never fall back
  # to placeholder values: a half-configured .env fails later in a confusing way.
  local key missing=""
  for key in SECRET_KEY HASHED_ADMIN_PASSWORD OAUTH2_CLIENT_ID OAUTH2_CLIENT_SECRET_HASH; do
    if [[ -z "$(get_from_credentials_file "$key" "$file" 2>/dev/null || true)" ]]; then
      missing="${missing}${missing:+, }${key}"
    fi
  done
  if [[ -n "$missing" ]]; then
    warn "Output kept for review: $file"
    die "generate_credentials.py ran, but these required values were not found in its output: ${missing}. Expected keys: SECRET_KEY, HASHED_ADMIN_PASSWORD, OAUTH2_CLIENT_ID, OAUTH2_CLIENT_SECRET_HASH."
  fi

  ok "Generated credential file: $file"
  warn "Save the plaintext admin password and OAuth client secret from the output above in a secure vault. They are needed for first login / client setup and are not recoverable from the hashes."
}
ensure_credentials_file_available() {
  local default_file="$1"
 [[ -n "$default_file" ]] || default_file="$OUT_DIR/copilot-generated-values.txt"
  if [[ -f "$default_file" ]]; then return 0; fi
  yes_no_num GENERATE_CREDS_NOW "Credential file not found at $default_file. Generate it now?" "yes"
  if [[ "$GENERATE_CREDS_NOW" == "yes" ]]; then
    ensure_linux_prereqs
    generate_credentials_file "$default_file"
  fi
}

validate_compose_if_possible() {
  local compose_file="$OUT_DIR/docker-compose.yml"
 [[ -f "$compose_file" ]] || return 0
  if docker compose version >/dev/null 2>&1; then
 (cd "$OUT_DIR" && docker compose config >/tmp/copilot-compose-rendered.yml)
    ok "Docker Compose config validated. Rendered file: /tmp/copilot-compose-rendered.yml"
  else
    warn "Docker Compose V2 was not found or is not usable. Skipping docker compose config validation."
  fi
}

show_info() {
  local base="$OUT_DIR/.env" orch="$OUT_DIR/.env.orchestrator" dl="$OUT_DIR/.env.dataloader" agent="$OUT_DIR/.env.agent-registry" compose="$OUT_DIR/docker-compose.yml"
  section "Current configuration summary"
  echo "Output directory: $OUT_DIR"
  echo "IMAGE_TAG: $(read_env_value "$base" IMAGE_TAG || echo '<missing>')"
  echo "FASTAPI_APP_VERSION: $(read_env_value "$base" FASTAPI_APP_VERSION || echo '<missing>')"
  echo "AGENT_CONTAINER_TAG: $(read_env_value "$base" AGENT_CONTAINER_TAG || echo '<missing>')"
  echo "LLM_PROVIDER: $(read_env_value "$base" LLM_PROVIDER || echo '<missing>')"
  echo "ENABLE_ADMIN_CONSOLE: $(read_env_value "$base" ENABLE_ADMIN_CONSOLE || echo '<missing>')"
  echo "ENABLE_RAG: $(read_env_value "$base" ENABLE_RAG || echo '<missing>')"
  echo "VECTOR_DB_PROVIDER: $(read_env_value "$base" VECTOR_DB_PROVIDER || echo '<missing>')"
  echo "ENABLE_DATA_LOADER: $(read_env_value "$base" ENABLE_DATA_LOADER || echo '<missing>')"
  echo "ENABLE_AGENT_REGISTRY: $(read_env_value "$base" ENABLE_AGENT_REGISTRY || echo '<missing>')"
  echo "PostgreSQL host: $(read_env_value "$orch" POSTGRES_HOST || echo '<missing>')"
  echo "Files:"
  for f in "$base" "$orch" "$dl" "$agent" "$compose"; do [[ -f "$f" ]] && echo "  - $f" || echo "  - $f <missing>"; done
}

run_upgrade() {
 [[ -n "$UPGRADE_IMAGE_TAG" ]] || die "--upgrade requires --image-tag <tag>. Example: --upgrade --image-tag 2.3.4"

  local source_dir="${FROM_DIR:-}" source_auto="no"
  if [[ -z "$source_dir" ]]; then source_dir="$(last_out_dir || true)"; source_auto="yes"; fi
 [[ -n "$source_dir" ]] || die "No previous install directory found. Use --from-dir /path/to/spotfire-copilot/2.3.4/backend."
 [[ -d "$source_dir" ]] || die "Source directory not found: $source_dir"

  if [[ "$OUT_DIR_EXPLICIT" == "no" ]]; then
    OUT_DIR="$(versioned_backend_dir_from_source "$source_dir" "$UPGRADE_IMAGE_TAG")"
  fi

  mkdir -p "$OUT_DIR"
  info "Upgrade source directory: $source_dir"
  info "Upgrade target directory: $OUT_DIR"

  # When the source was auto-detected (no --from-dir), show it and require confirmation
  # so we never silently upgrade from the wrong baseline.
  if [[ "$source_auto" == "yes" ]]; then
    if [[ "$ASSUME_YES" == "yes" ]]; then
      info "Auto-detected source accepted via --yes."
    elif [[ -t 0 ]]; then
      local __confirm=""
      read -r -p "Upgrade using the auto-detected source above -> IMAGE_TAG=$UPGRADE_IMAGE_TAG? [y/N]: " __confirm || true
      case "$__confirm" in
        y|Y|yes|YES) : ;;
        *) die "Upgrade cancelled. Re-run with --from-dir <dir> to choose the source explicitly." ;;
      esac
    else
      die "Non-interactive run cannot auto-confirm the detected source: $source_dir. Pass --from-dir <dir>, or add --yes to accept the detected source."
    fi
  fi

  # Same-directory guard (e.g. upgrading to the same tag the source already uses):
  # skip the self-copy so 'cp' does not fail, and just re-apply the tag values in place.
  local src_abs tgt_abs
  src_abs="$( (cd "$source_dir" 2>/dev/null && pwd -P) || printf '%s' "$source_dir")"
  tgt_abs="$( (cd "$OUT_DIR" 2>/dev/null && pwd -P) || printf '%s' "$OUT_DIR")"
  if [[ "$src_abs" == "$tgt_abs" ]]; then
    warn "Source and target are the same directory (tag unchanged). Skipping copy; re-applying tag values in place."
  else
    copy_existing_config_to_new_dir "$source_dir" "$OUT_DIR"
  fi

  local base="$OUT_DIR/.env" compose="$OUT_DIR/docker-compose.yml"
 [[ -f "$base" ]] || die "Missing $base after copy. Run an initial generation first, or provide a valid --from-dir."
  backup_file "$base"
  set_env_value "$base" IMAGE_TAG "$UPGRADE_IMAGE_TAG"
  set_env_value "$base" FASTAPI_APP_VERSION "$UPGRADE_IMAGE_TAG"
  if [[ -n "$UPGRADE_AGENT_TAG" ]]; then set_env_value "$base" AGENT_CONTAINER_TAG "$UPGRADE_AGENT_TAG"; fi
  patch_compose_image_refs "$compose"
  validate_compose_if_possible
  remember_out_dir
  ok "Upgrade directory prepared. IMAGE_TAG=$UPGRADE_IMAGE_TAG FASTAPI_APP_VERSION=$UPGRADE_IMAGE_TAG AGENT_CONTAINER_TAG=${UPGRADE_AGENT_TAG:-unchanged}"
  info "Next: cd $OUT_DIR && docker compose pull && docker compose up -d"
}

find_deepagents_oss_script() {
  local candidate

  if [[ -n "${DEEPAGENTS_SCRIPT:-}" ]]; then
    candidate="$DEEPAGENTS_SCRIPT"
    if [[ -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
    return 1
  fi

  for candidate in \
    "$SCRIPT_DIR/generate-deepagents-oss-env.sh" \
    "$SCRIPT_DIR/generate-deepagents-oss-env-v7-template-flow.sh" \
    "$SCRIPT_DIR/generate-deepagents-oss-env-v6.sh" \
    "$SCRIPT_DIR/generate-deepagents-oss-env-v5.sh" \
    "$START_DIR/generate-deepagents-oss-env.sh" \
    "$START_DIR/generate-deepagents-oss-env-v7-template-flow.sh" \
    "$START_DIR/generate-deepagents-oss-env-v6.sh" \
    "$START_DIR/generate-deepagents-oss-env-v5.sh"; do
    if [[ -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

run_deepagents_oss_generator_if_requested() {
  # DeepAgents is intentionally NOT prompted during the normal Copilot flow.
  # It runs only when the caller explicitly passes --install-deepagents.
 [[ "${WITH_DEEPAGENTS:-no}" == "yes" ]] || return 0

  section "DeepAgents OSS"
  info "DeepAgents OSS is a separate A2A agent server. It is not part of the core Copilot/Agent Registry stack."
  info "This main script delegates to a standalone DeepAgents installer instead of embedding a duplicate copy."

  local deepagents_script=""
  deepagents_script="$(find_deepagents_oss_script || true)"
  if [[ -z "$deepagents_script" ]]; then
    if [[ -n "${DEEPAGENTS_SCRIPT:-}" ]]; then
      warn "DeepAgents OSS generator was not found at: $DEEPAGENTS_SCRIPT"
    else
      warn "DeepAgents OSS generator was not found next to this script."
    fi
    warn "Place generate-deepagents-oss-env.sh beside this script, or pass --deepagents-script /path/to/generate-deepagents-oss-env.sh."
    return 0
  fi

  chmod +x "$deepagents_script" 2>/dev/null || true
  info "Running standalone DeepAgents OSS generator: $deepagents_script"
  bash "$deepagents_script"
}


# ---------- Agent Registry only mode ----------
write_or_update_agent_registry_compose_service() {
  local compose_file="$OUT_DIR/docker-compose.yml"
 [[ -f "$compose_file" ]] || die "Missing docker-compose.yml in $OUT_DIR. Agent Registry only mode must be run against an existing backend folder."

  # Insert/update the agent-registry service using awk, with the YAML block emitted
  # from print statements whose indentation lives INSIDE the quoted strings. awk
  # ignores source indentation, and interior string spaces survive whitespace
  # collapse, so this stays valid even if the script file's indentation is mangled
  # in transit. It also removes any previously-inserted (possibly flattened) block.
  local compose_tmp="${compose_file}.tmp.$$"
  if awk -v ap="${AGENT_PORT:-8050}" '
    function emit() {
      print "  agent-registry:"
      print "    image: copilotoci.azurecr.io/spotfirecopilot/agent-container:${AGENT_CONTAINER_TAG}"
      print "    container_name: spotfire-agent-registry-${AGENT_CONTAINER_TAG}"
      print "    restart: unless-stopped"
      print "    ports:"
      print "      - \"" ap ":" ap "\""
      print "    env_file:"
      print "      - .env"
      print "      - .env.agent-registry"
      print "    extra_hosts:"
      print "      - \"host.docker.internal:host-gateway\""
      print "    volumes:"
      print "      - /opt/spotfire-agent-registry/custom-workflows:/custom-workflows:ro"
      print "      - /opt/spotfire-agent-registry/logs:/conversation-logs"
    }
    { L[NR] = $0 }
    END {
      n = NR
      svc = 0
      for (i = 1; i <= n; i++) if (L[i] ~ /^services:[ \t]*$/) { svc = 1; break }
      if (!svc) { exit 3 }
      start = 0
      for (i = 1; i <= n; i++) if (L[i] ~ /^[ \t]*agent-registry:[ \t]*$/) { start = i; break }
      if (start > 0) {
        # End of the existing block = next top-level key (col 0) or a proper 2-space
        # service key. A flattened block s 1-space keys match neither, so the whole
        # mis-indented block is removed regardless of how mangled it was.
        end = n + 1
        for (j = start + 1; j <= n; j++) if (L[j] ~ /^[A-Za-z0-9_.-]+:[ \t]*$/ || L[j] ~ /^  [A-Za-z0-9_.-]+:[ \t]*$/) { end = j; break }
        for (i = 1; i < start; i++) print L[i]
        emit()
        for (i = end; i <= n; i++) print L[i]
      } else {
        insert = 0
        for (i = 1; i <= n; i++) if (L[i] ~ /^(networks|volumes):[ \t]*$/) { insert = i; break }
        if (insert == 0) insert = n + 1
        for (i = 1; i < insert; i++) print L[i]
        if (insert > 1 && L[insert - 1] ~ /[^ \t]/) print ""
        emit()
        for (i = insert; i <= n; i++) print L[i]
      }
    }
  ' "$compose_file" > "$compose_tmp"; then
    mv "$compose_tmp" "$compose_file"
    ok "Added/updated agent-registry service in $compose_file"
  else
    rm -f "$compose_tmp"
    die "docker-compose.yml does not contain a top-level services: section, or the agent-registry update failed."
  fi
}

# Obtains an Orchestrator admin JWT by logging in at /auth/jwt/login and stores it in
# the global ORCH_ADMIN_BEARER_TOKEN. It first tries the plaintext admin password from
# the credentials file (operators may store it under ADMIN_PASSWORD_PLAINTEXT); if the
# file is missing it asks for the path, and if no plaintext password is available it
# prompts for it. Username defaults to the hard-coded admin email.
get_orchestrator_admin_token() {
  local base_url="$1"
  require_cmd curl
  require_cmd python3
  ORCH_ADMIN_BEARER_TOKEN=""
  local cred_file="${CREDENTIALS_FILE:-}"
  if [[ -z "$cred_file" || ! -f "$cred_file" ]]; then cred_file="$OUT_DIR/copilot-generated-values.txt"; fi

  local admin_user="" admin_pass=""
  if [[ ! -f "$cred_file" ]]; then
    warn "Credentials file not found at $cred_file."
    local entered=""
    prompt entered "Path to copilot-generated-values.txt (leave blank to enter the admin password manually)" ""
    entered="$(strip_outer_quotes "$entered")"
    if [[ -n "$entered" && -f "$entered" ]]; then cred_file="$entered"; elif [[ -n "$entered" ]]; then warn "File not found: $entered"; fi
  fi
  if [[ -f "$cred_file" ]]; then
    admin_user="$(get_from_credentials_file ADMIN_USERNAME "$cred_file" || true)"
    [[ -z "$admin_user" ]] && admin_user="$(get_from_credentials_file ADMIN_EMAIL "$cred_file" || true)"
    admin_pass="$(get_from_credentials_file ADMIN_PASSWORD_PLAINTEXT "$cred_file" || true)"
    [[ -z "$admin_pass" ]] && admin_pass="$(get_from_credentials_file ADMIN_PASSWORD "$cred_file" || true)"
    [[ -n "$admin_pass" ]] && info "Using the admin password found in $cred_file to log in to the Orchestrator."
  fi

  [[ -z "$admin_user" ]] && admin_user="admin@orchestrator.local"
  if [[ -z "$admin_pass" ]]; then
    info "The plaintext admin password is not stored in the credentials file by default (only its bcrypt hash is). Enter it to let the installer log in for you."
    prompt admin_user "Orchestrator admin username (email)" "$admin_user"
    prompt admin_pass "Orchestrator admin password (plaintext saved from generate_credentials.py)" "" true
  fi
  if [[ -z "$admin_pass" ]]; then
    die "No Orchestrator admin password was provided, so the admin token could not be obtained and the Agent Registry OAuth client could not be created. No Agent Registry configuration was applied."
  fi

  info "Logging in to the Orchestrator at ${base_url}/auth/jwt/login as ${admin_user} to obtain an admin token."
  local login_response=""
  if ! login_response="$(curl -fsS -X POST "${base_url}/auth/jwt/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "username=${admin_user}" \
    --data-urlencode "password=${admin_pass}")"; then
    die "Could not log in to the Orchestrator at ${base_url}/auth/jwt/login. Check that the Orchestrator is running and reachable at that URL and that the admin username/password are correct (username must be the email, e.g. admin@orchestrator.local). No Agent Registry configuration was applied."
  fi
  ORCH_ADMIN_BEARER_TOKEN="$(printf '%s' "$login_response" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token", ""))' 2>/dev/null || true)"
  if [[ -z "$ORCH_ADMIN_BEARER_TOKEN" ]]; then
    die "The Orchestrator login response did not include an access_token. No Agent Registry configuration was applied."
  fi
}

configure_agent_registry_env_only() {
  section "Agent Registry"
  LOG_LEVEL="$(get_existing LOG_LEVEL "${EXISTING_FILES[@]}" || echo INFO)"
  AGENT_TAG_DEFAULT="$(get_existing AGENT_CONTAINER_TAG "${EXISTING_FILES[@]}" || true)"
  while true; do
    prompt_image_tag AGENT_CONTAINER_TAG "Agent container image tag" "$AGENT_TAG_DEFAULT" "copilotoci.azurecr.io/spotfirecopilot/agent-container"
 [[ -n "$AGENT_CONTAINER_TAG" ]] && break
    warn "Agent Registry image tag is required. Use the exact agent-container tag provided/tested for your environment."
  done

  prompt AGENT_PORT "Agent Registry PORT" "$(get_existing PORT "$OUT_DIR/.env.agent-registry" || echo 8050)"
  prompt AGENT_BASE_URL "Agent Registry BASE_URL" "$(get_existing BASE_URL "$OUT_DIR/.env.agent-registry" || echo http://agent-registry:8050)"
  prompt AUTH_CLIENT_ID "Agent Registry AUTH_CLIENT_ID" "$(get_existing AUTH_CLIENT_ID "$OUT_DIR/.env.agent-registry" || echo agent-registry-client)"

  EXISTING_AUTH_CLIENT_SECRET="$(get_existing AUTH_CLIENT_SECRET "$OUT_DIR/.env.agent-registry" || true)"
  if [[ -n "$EXISTING_AUTH_CLIENT_SECRET" ]]; then
    prompt AUTH_CLIENT_SECRET "Agent Registry AUTH_CLIENT_SECRET" "$EXISTING_AUTH_CLIENT_SECRET" true
  else
    AUTH_CLIENT_SECRET="$(random_urlsafe_token)"
    ok "Generated Agent Registry AUTH_CLIENT_SECRET. Save .env.agent-registry securely."
  fi

  EXISTING_AUTH_SIGNING_KEY="$(get_existing AUTH_SIGNING_KEY "$OUT_DIR/.env.agent-registry" || true)"
  if [[ -n "$EXISTING_AUTH_SIGNING_KEY" ]]; then
    prompt AUTH_SIGNING_KEY "Agent Registry AUTH_SIGNING_KEY" "$EXISTING_AUTH_SIGNING_KEY" true
  else
    AUTH_SIGNING_KEY="$(random_urlsafe_token)"
    ok "Generated Agent Registry AUTH_SIGNING_KEY. Save .env.agent-registry securely."
  fi

  prompt ORCHESTRATOR_URL "ORCHESTRATOR_URL for Agent Registry" "$(get_existing ORCHESTRATOR_URL "$OUT_DIR/.env.agent-registry" || echo http://orchestrator:8080)"

  EXISTING_ORCH_AGENT_CLIENT_ID="$(get_existing ORCHESTRATOR_CLIENT_ID "$OUT_DIR/.env.agent-registry" || true)"
  EXISTING_ORCH_AGENT_CLIENT_SECRET="$(get_existing ORCHESTRATOR_CLIENT_SECRET "$OUT_DIR/.env.agent-registry" || true)"
  # Placeholder values from an earlier incomplete run are NOT valid credentials and
  # must never be offered for reuse (same rule as the main installation flow).
  if [[ -n "$EXISTING_ORCH_AGENT_CLIENT_ID" && -n "$EXISTING_ORCH_AGENT_CLIENT_SECRET" \
        && "$EXISTING_ORCH_AGENT_CLIENT_ID" != REPLACE_WITH_* && "$EXISTING_ORCH_AGENT_CLIENT_SECRET" != REPLACE_WITH_* ]]; then
    yes_no_num USE_EXISTING_ORCH_AGENT_CLIENT "Existing Agent Registry Orchestrator OAuth client found in .env.agent-registry. Reuse it?" "yes"
    if [[ "$USE_EXISTING_ORCH_AGENT_CLIENT" == "yes" ]]; then
      ORCHESTRATOR_CLIENT_ID="$EXISTING_ORCH_AGENT_CLIENT_ID"
      ORCHESTRATOR_CLIENT_SECRET="$EXISTING_ORCH_AGENT_CLIENT_SECRET"
    else
      prompt_required ORCHESTRATOR_CLIENT_ID "ORCHESTRATOR_CLIENT_ID for Agent Registry" "$EXISTING_ORCH_AGENT_CLIENT_ID" "false"
      prompt_required ORCHESTRATOR_CLIENT_SECRET "ORCHESTRATOR_CLIENT_SECRET for Agent Registry" "$EXISTING_ORCH_AGENT_CLIENT_SECRET" "true"
    fi
  else
    yes_no_num HAVE_ORCH_AGENT_CLIENT "Have you already created the Orchestrator OAuth client for Agent Registry with Scope Profile agent_developer?" "no"
    if [[ "$HAVE_ORCH_AGENT_CLIENT" == "yes" ]]; then
      prompt_required ORCHESTRATOR_CLIENT_ID "ORCHESTRATOR_CLIENT_ID for Agent Registry" "" "false"
      prompt_required ORCHESTRATOR_CLIENT_SECRET "ORCHESTRATOR_CLIENT_SECRET for Agent Registry" "" "true"
    else
      yes_no_num CREATE_ORCH_AGENT_CLIENT "Do you want this installer to create the Agent Registry Orchestrator OAuth client now?" "no"
      # This is a dedicated install mode: if real credentials cannot be obtained,
      # stop instead of writing placeholders. Placeholders would produce an
      # agent-registry service that starts but can never authenticate.
      if [[ "$CREATE_ORCH_AGENT_CLIENT" != "yes" ]]; then
        die "Agent Registry needs an Orchestrator OAuth client with Scope Profile agent_developer. Create it in the Admin Console (or re-run and let the installer create it), then run this again. No Agent Registry configuration was applied."
      fi
      require_cmd curl
      require_cmd python3
      # The client-creation call is made from THIS host, so default to the
      # host-published orchestrator port. The in-compose hostname
      # (http://orchestrator:8080) is not resolvable from the host.
      ORCH_AGENT_CLIENT_CREATE_DEFAULT="$ORCHESTRATOR_URL"
      if [[ "$ORCH_AGENT_CLIENT_CREATE_DEFAULT" == http://orchestrator:* || "$ORCH_AGENT_CLIENT_CREATE_DEFAULT" == https://orchestrator:* ]]; then
        ORCH_AGENT_CLIENT_CREATE_DEFAULT="http://localhost:8080"
      fi
      prompt ORCH_AGENT_CLIENT_CREATE_URL "Orchestrator URL reachable from this machine for client creation" "$ORCH_AGENT_CLIENT_CREATE_DEFAULT"
      ORCH_AGENT_CLIENT_CREATE_URL="${ORCH_AGENT_CLIENT_CREATE_URL%/}"
      # Obtain the admin token by logging in on the operator's behalf instead of asking
      # them to paste one. Uses the plaintext admin password from the credentials file
      # when available, otherwise prompts for it. Sets ORCH_ADMIN_BEARER_TOKEN.
      get_orchestrator_admin_token "$ORCH_AGENT_CLIENT_CREATE_URL"
      prompt ORCH_AGENT_CLIENT_NAME "OAuth client name" "Agent Registry"
      info "Creating Agent Registry OAuth client in Orchestrator using scope_profile=agent_developer."
      if ! ORCH_AGENT_CLIENT_RESPONSE="$(curl -fsS -X POST "${ORCH_AGENT_CLIENT_CREATE_URL}/register_client" \
        -H "Authorization: Bearer ${ORCH_ADMIN_BEARER_TOKEN}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "client_name=${ORCH_AGENT_CLIENT_NAME}" \
        --data-urlencode "scope_profile=agent_developer")"; then
        die "Agent Registry OAuth client could not be created through ${ORCH_AGENT_CLIENT_CREATE_URL}/register_client. Check that the Orchestrator is running and reachable at that URL and that the admin bearer token is valid. No Agent Registry configuration was applied."
      fi
      ORCHESTRATOR_CLIENT_ID="$(printf '%s' "$ORCH_AGENT_CLIENT_RESPONSE" | python3 -c 'import sys,json; data=json.load(sys.stdin); print(data.get("client_id", ""))' 2>/dev/null || true)"
      ORCHESTRATOR_CLIENT_SECRET="$(printf '%s' "$ORCH_AGENT_CLIENT_RESPONSE" | python3 -c 'import sys,json; data=json.load(sys.stdin); print(data.get("client_secret", ""))' 2>/dev/null || true)"
      if [[ -z "$ORCHESTRATOR_CLIENT_ID" || -z "$ORCHESTRATOR_CLIENT_SECRET" ]]; then
        warn "The /register_client response was: $ORCH_AGENT_CLIENT_RESPONSE"
        die "The /register_client response did not contain both client_id and client_secret. No Agent Registry configuration was applied."
      fi
      ok "Created Agent Registry orchestrator OAuth client: $(mask "$ORCHESTRATOR_CLIENT_ID")"
      warn "Save the generated ORCHESTRATOR_CLIENT_SECRET securely."
    fi
  fi

  prompt CUSTOM_WORKFLOWS_DIR "CUSTOM_WORKFLOWS_DIR inside container" "$(get_existing CUSTOM_WORKFLOWS_DIR "$OUT_DIR/.env.agent-registry" || echo /custom-workflows)"
  CONVERSATION_LOGS_DIR="/conversation-logs"
  AGENT_ENV_CONTENT=$(cat <<EOM
# ------------------------------
# Agent Registry runtime
# ------------------------------
PORT=${AGENT_PORT}
BASE_URL=${AGENT_BASE_URL}
LOG_LEVEL=${LOG_LEVEL}


# ------------------------------
# Agent Registry authentication
# ------------------------------
AUTH_CLIENT_ID=${AUTH_CLIENT_ID}
AUTH_CLIENT_SECRET=${AUTH_CLIENT_SECRET}
AUTH_SIGNING_KEY=${AUTH_SIGNING_KEY}
AUTH_TOKEN_TTL=3600

# ------------------------------
# Orchestrator connection
# ------------------------------
ORCHESTRATOR_URL=${ORCHESTRATOR_URL}
ORCHESTRATOR_CLIENT_ID=${ORCHESTRATOR_CLIENT_ID}
ORCHESTRATOR_CLIENT_SECRET=${ORCHESTRATOR_CLIENT_SECRET}

# ------------------------------
# Agent paths
# ------------------------------
CUSTOM_WORKFLOWS_DIR=${CUSTOM_WORKFLOWS_DIR}
CONVERSATION_LOGS_DIR=${CONVERSATION_LOGS_DIR}
EOM
)
  AGENT_ENV_CONTENT="$(compact_env_content "$AGENT_ENV_CONTENT")"
}

run_agent_registry_only() {
  section "Agent Registry only install/update"
  if [[ "$OUT_DIR_EXPLICIT" != "yes" ]]; then
    die "--install-agent-registry requires --dir /path/to/existing/backend"
  fi
  OUT_DIR="$(normalize_path "$OUT_DIR")"
  [[ -d "$OUT_DIR" ]] || die "Backend directory not found: $OUT_DIR"
  cd "$OUT_DIR"; OUT_DIR="$(pwd)"
  [[ -f "$OUT_DIR/.env" ]] || die "Missing $OUT_DIR/.env. Run this against an existing Copilot backend folder."
  [[ -f "$OUT_DIR/docker-compose.yml" ]] || die "Missing $OUT_DIR/docker-compose.yml. Run this against an existing Docker Compose backend folder."
  EXISTING_FILES=("$OUT_DIR/.env" "$OUT_DIR/.env.orchestrator" "$OUT_DIR/.env.dataloader" "$OUT_DIR/.env.agent-registry")

  configure_agent_registry_env_only
  write_file "$OUT_DIR/.env.agent-registry" "$AGENT_ENV_CONTENT"
  set_env_value "$OUT_DIR/.env" ENABLE_AGENT_REGISTRY yes
  set_env_value "$OUT_DIR/.env" AGENT_CONTAINER_TAG "$AGENT_CONTAINER_TAG"
  mkdir -p /opt/spotfire-agent-registry/custom-workflows /opt/spotfire-agent-registry/logs 2>/dev/null || true
  write_or_update_agent_registry_compose_service
  validate_compose_if_possible
  remember_out_dir

  ok "Agent Registry install/update files are ready."
  echo "Next:"
  echo "  cd $OUT_DIR"
  echo "  docker login copilotoci.azurecr.io"
  echo "  docker compose pull agent-registry"
  echo "  docker compose up -d --force-recreate agent-registry"
}

# ---------- provider block builders ----------
MODEL_BLOCK_ORCH=""; MODEL_BLOCK_DL=""; EMBED_BLOCK_ORCH=""; EMBED_BLOCK_DL=""; VECTOR_BLOCK_ORCH=""; VECTOR_BLOCK_DL=""; RAG_DEFAULTS_BLOCK=""; DATA_LOADER_NOTICE=""
LLM_PROVIDER=""; EMBEDDING_PROVIDER=""; VECTOR_DB_PROVIDER=""; VECTOR_WRITABLE="no"

category_vars() {
  local prefix="$1" primary="$2" temp_fast="$3" temp_large="$4" temp_vision="$5" temp_code="$6" temp_reasoning="$7"
  cat <<EOM
# OPTIONAL per-category model overrides. Each category falls back to MODEL_NAME (${primary}) unless BOTH
# the *_MODEL and *_TEMPERATURE for that category are set. Uncomment and edit to override the image defaults.
# Fast model/deployment for title generation, summarization, and RAG enrichment.
#${prefix}_FAST_MODEL=${primary}
#${prefix}_FAST_TEMPERATURE=${temp_fast}
# Large model/deployment for general chat and data analysis.
#${prefix}_LARGE_MODEL=${primary}
#${prefix}_LARGE_TEMPERATURE=${temp_large}
# Vision model/deployment for visualization/image analysis.
#${prefix}_VISION_MODEL=${primary}
#${prefix}_VISION_TEMPERATURE=${temp_vision}
# Code model/deployment for SQL/code/data-function generation.
#${prefix}_CODE_MODEL=${primary}
#${prefix}_CODE_TEMPERATURE=${temp_code}
# Reasoning model/deployment for complex multi-step analysis.
#${prefix}_REASONING_MODEL=${primary}
#${prefix}_REASONING_TEMPERATURE=${temp_reasoning}
EOM
}

configure_advanced_categories() {
  local prefix="$1" primary="$2" temp_fast="${3:-0.3}" temp_large="${4:-0.2}" temp_vision="${5:-0.1}" temp_code="${6:-0.0}" temp_reasoning="${7:-0.2}"
  CATEGORY_BLOCK="$(category_vars "$prefix" "$primary" "$temp_fast" "$temp_large" "$temp_vision" "$temp_code" "$temp_reasoning")"
  info "Optional per-category model overrides for ${prefix} were written to the .env (commented out). Uncomment ${prefix}_FAST_MODEL / ${prefix}_LARGE_MODEL etc. to override the ${primary} default."
}

# Sets the global GPT5_FLAG_BLOCK based on the model name. GPT-5.x and o-series
# models require OPENAI_GPT5_COMPATIBLE=true so the orchestrator binds
# max_completion_tokens and omits temperature. Non-matching models leave it empty.
set_gpt5_flag_block() {
  local model
  model="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  GPT5_FLAG_BLOCK=""
  case "$model" in
    gpt-5*|gpt5*|o1|o1-*|o3|o3-*|o4|o4-*)
      GPT5_FLAG_BLOCK=$'# REQUIRED for GPT-5.x / o-series models: orchestrator binds max_completion_tokens and omits temperature.\nOPENAI_GPT5_COMPATIBLE=true'
      info "Detected a GPT-5.x / o-series model ('${1:-}') - setting OPENAI_GPT5_COMPATIBLE=true."
      ;;
  esac
}

configure_llm_provider() {
  section "LLM provider"
  info "The LLM provider is independent from the Vector DB. For example, Azure OpenAI can use Milvus, Zilliz, or Azure AI Search for RAG."
  choose_num LLM_PROVIDER "Select LLM provider" "1" \
    "azure_openai|Azure OpenAI" \
    "openai|OpenAI" \
    "aws_bedrock|AWS Bedrock" \
    "vertex_ai|Google Vertex AI" \
    "gemini|Google Gemini API" \
    "nvidia_nim|NVIDIA NIM" \
    "ollama|Ollama / self-hosted test"

  case "$LLM_PROVIDER" in
    azure_openai)
      prompt OPENAI_API_KEY "Azure OpenAI API key" "$(get_existing OPENAI_API_KEY "${EXISTING_FILES[@]}" || true)" true
      prompt AZURE_OPENAI_ENDPOINT "Azure OpenAI endpoint" "$(get_existing AZURE_OPENAI_ENDPOINT "${EXISTING_FILES[@]}" || echo https://your-resource.openai.azure.com/)"
      prompt OPENAI_API_VERSION "Azure OpenAI API version" "$(get_existing OPENAI_API_VERSION "${EXISTING_FILES[@]}" || echo 2024-02-15-preview)"
      prompt PRIMARY_MODEL "Primary Azure deployment name" "$(get_existing MODEL_NAME "${EXISTING_FILES[@]}" || echo gpt-4o)"
      set_gpt5_flag_block "$PRIMARY_MODEL"
      configure_advanced_categories AZURE "$PRIMARY_MODEL" 0.3 0.2 0.1 0.0 0.2
      MODEL_BLOCK_ORCH=$(cat <<EOM
# REQUIRED: Orchestrator model plugin for Azure OpenAI.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.azure_openai_enhanced:AzureOpenAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.azure_openai_enhanced:AzureOpenAIPlugin
# REQUIRED: OpenAI API type for Azure OpenAI.
OPENAI_API_TYPE=azure
# REQUIRED: Azure OpenAI API key.
OPENAI_API_KEY=${OPENAI_API_KEY}
# REQUIRED: Azure OpenAI endpoint URL.
AZURE_OPENAI_ENDPOINT=${AZURE_OPENAI_ENDPOINT}
# REQUIRED: Azure OpenAI API version.
OPENAI_API_VERSION=${OPENAI_API_VERSION}
# REQUIRED: Primary model/deployment name used as fallback.
MODEL_NAME=${PRIMARY_MODEL}
${GPT5_FLAG_BLOCK}
${CATEGORY_BLOCK}
EOM
)
      MODEL_BLOCK_DL=$(cat <<EOM
# REQUIRED: Data Loader model plugin for Azure OpenAI.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.az_openai:AzOpenAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.az_openai:AzOpenAIPlugin
# REQUIRED: OpenAI API type for Azure OpenAI.
OPENAI_API_TYPE=azure
# REQUIRED: Azure OpenAI API key.
OPENAI_API_KEY=${OPENAI_API_KEY}
# REQUIRED: Azure OpenAI endpoint URL.
AZURE_OPENAI_ENDPOINT=${AZURE_OPENAI_ENDPOINT}
# REQUIRED: Azure OpenAI API version.
OPENAI_API_VERSION=${OPENAI_API_VERSION}
# REQUIRED: Data Loader model/deployment name.
MODEL_NAME=${PRIMARY_MODEL}
EOM
)
      ;;
    openai)
      prompt OPENAI_API_KEY "OpenAI API key" "$(get_existing OPENAI_API_KEY "${EXISTING_FILES[@]}" || true)" true
      prompt OPENAI_API_BASE "OPENAI_API_BASE (optional; leave blank for default OpenAI)" "$(get_existing OPENAI_API_BASE "${EXISTING_FILES[@]}" || true)"
      prompt PRIMARY_MODEL "Primary OpenAI model name" "$(get_existing MODEL_NAME "${EXISTING_FILES[@]}" || echo gpt-4o)"
      set_gpt5_flag_block "$PRIMARY_MODEL"
      configure_advanced_categories OPENAI "$PRIMARY_MODEL" 0.3 0.2 0.1 0.0 0.2
      OPENAI_BASE_LINE=""; [[ -n "$OPENAI_API_BASE" ]] && OPENAI_BASE_LINE="# OPTIONAL: Custom OpenAI-compatible base URL.\nOPENAI_API_BASE=${OPENAI_API_BASE}"
      MODEL_BLOCK_ORCH=$(cat <<EOM
# REQUIRED: Orchestrator model plugin for OpenAI.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai_enhanced:OpenAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai_enhanced:OpenAIPlugin
# REQUIRED: OpenAI API type.
OPENAI_API_TYPE=openai
# REQUIRED: OpenAI API key.
OPENAI_API_KEY=${OPENAI_API_KEY}
${OPENAI_BASE_LINE}
# REQUIRED: Primary model name used as fallback.
MODEL_NAME=${PRIMARY_MODEL}
${GPT5_FLAG_BLOCK}
${CATEGORY_BLOCK}
EOM
)
      MODEL_BLOCK_DL=$(cat <<EOM
# REQUIRED: Data Loader model plugin for OpenAI.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai:OpenAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai:OpenAIPlugin
# REQUIRED: OpenAI API type.
OPENAI_API_TYPE=openai
# REQUIRED: OpenAI API key.
OPENAI_API_KEY=${OPENAI_API_KEY}
${OPENAI_BASE_LINE}
# REQUIRED: Data Loader model name.
MODEL_NAME=${PRIMARY_MODEL}
EOM
)
      ;;
    aws_bedrock)
      prompt AWS_REGION "AWS_REGION" "$(get_existing AWS_REGION "${EXISTING_FILES[@]}" || echo us-east-1)"
      yes_no_num USE_AWS_KEYS "Use explicit AWS keys in env? Choose No for IAM role/task role." "no"
      AWS_KEYS_BLOCK="# OPTIONAL: Using IAM role/task role; AWS keys are not set."
      if [[ "$USE_AWS_KEYS" == "yes" ]]; then
        prompt AWS_ACCESS_KEY_ID "AWS_ACCESS_KEY_ID" "$(get_existing AWS_ACCESS_KEY_ID "${EXISTING_FILES[@]}" || true)" true
        prompt AWS_SECRET_ACCESS_KEY "AWS_SECRET_ACCESS_KEY" "$(get_existing AWS_SECRET_ACCESS_KEY "${EXISTING_FILES[@]}" || true)" true
        prompt AWS_SESSION_TOKEN "AWS_SESSION_TOKEN optional" "$(get_existing AWS_SESSION_TOKEN "${EXISTING_FILES[@]}" || true)" true
        AWS_KEYS_BLOCK=$(cat <<EOM
# OPTIONAL: AWS access key ID. Prefer IAM role in production.
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
# OPTIONAL: AWS secret access key. Prefer IAM role in production.
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
# OPTIONAL: AWS session token, if temporary credentials are used.
AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}
EOM
)
      fi
      prompt PRIMARY_MODEL "Primary Bedrock model ID" "$(get_existing MODEL_NAME "${EXISTING_FILES[@]}" || echo anthropic.claude-3-5-sonnet-20241022-v2:0)"
      configure_advanced_categories BEDROCK "$PRIMARY_MODEL" 0.3 0.2 0.1 0.0 1.0
      MODEL_BLOCK_ORCH=$(cat <<EOM
# REQUIRED: Orchestrator model plugin for AWS Bedrock.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock_enhanced:BedrockPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock_enhanced:BedrockPlugin
# REQUIRED: AWS region for Bedrock.
AWS_REGION=${AWS_REGION}
${AWS_KEYS_BLOCK}
# REQUIRED: Primary Bedrock model ID.
MODEL_NAME=${PRIMARY_MODEL}
${CATEGORY_BLOCK}
EOM
)
      MODEL_BLOCK_DL=$(cat <<EOM
# REQUIRED: Data Loader model plugin for AWS Bedrock.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock:BedrockPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock:BedrockPlugin
# REQUIRED: AWS region for Bedrock.
AWS_REGION=${AWS_REGION}
${AWS_KEYS_BLOCK}
# REQUIRED: Data Loader Bedrock model ID.
MODEL_NAME=${PRIMARY_MODEL}
EOM
)
      ;;
    vertex_ai)
      prompt PROJECT_ID "GCP PROJECT_ID" "$(get_existing PROJECT_ID "${EXISTING_FILES[@]}" || echo your-gcp-project-id)"
      prompt LOCATION_ID "GCP LOCATION_ID" "$(get_existing LOCATION_ID "${EXISTING_FILES[@]}" || echo us-central1)"
      prompt GOOGLE_APPLICATION_CREDENTIALS "GOOGLE_APPLICATION_CREDENTIALS path inside container" "$(get_existing GOOGLE_APPLICATION_CREDENTIALS "${EXISTING_FILES[@]}" || echo /app/credentials/service-account-key.json)"
      prompt PRIMARY_MODEL "Primary Vertex AI model" "$(get_existing MODEL_NAME "${EXISTING_FILES[@]}" || echo gemini-2.0-flash)"
      configure_advanced_categories VERTEXAI "$PRIMARY_MODEL" 0.3 0.2 0.1 0.0 0.1
      MODEL_BLOCK_ORCH=$(cat <<EOM
# REQUIRED: Orchestrator model plugin for Vertex AI.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai_enhanced:VertexAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai_enhanced:VertexAIPlugin
# REQUIRED: GCP project ID.
PROJECT_ID=${PROJECT_ID}
# REQUIRED: GCP location.
LOCATION_ID=${LOCATION_ID}
# REQUIRED: Service account path inside container.
GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS}
# REQUIRED: Primary Vertex AI model.
MODEL_NAME=${PRIMARY_MODEL}
${CATEGORY_BLOCK}
EOM
)
      MODEL_BLOCK_DL=$(cat <<EOM
# REQUIRED: Data Loader model plugin for Vertex AI.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai:VertexAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai:VertexAIPlugin
# REQUIRED: GCP project ID.
PROJECT_ID=${PROJECT_ID}
# REQUIRED: GCP location.
LOCATION_ID=${LOCATION_ID}
# REQUIRED: Service account path inside container.
GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS}
# REQUIRED: Data Loader Vertex AI model.
MODEL_NAME=${PRIMARY_MODEL}
EOM
)
      ;;
    gemini)
      prompt GOOGLE_API_KEY "Google Gemini API key" "$(get_existing GOOGLE_API_KEY "${EXISTING_FILES[@]}" || true)" true
      prompt PRIMARY_MODEL "Primary Gemini model" "$(get_existing MODEL_NAME "${EXISTING_FILES[@]}" || echo gemini-2.0-flash)"
      configure_advanced_categories GEMINI "$PRIMARY_MODEL" 0.3 0.2 0.1 0.0 0.1
      MODEL_BLOCK_ORCH=$(cat <<EOM
# REQUIRED: Orchestrator model plugin for Google Gemini API.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.gemini_enhanced:GeminiPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.gemini_enhanced:GeminiPlugin
# REQUIRED: Gemini API key.
GOOGLE_API_KEY=${GOOGLE_API_KEY}
# REQUIRED: Primary Gemini model.
MODEL_NAME=${PRIMARY_MODEL}
${CATEGORY_BLOCK}
EOM
)
      MODEL_BLOCK_DL=$(cat <<EOM
# REQUIRED: Data Loader model plugin for Vertex AI/Gemini-compatible setup.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai:VertexAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai:VertexAIPlugin
# REQUIRED: Data Loader model name.
MODEL_NAME=${PRIMARY_MODEL}
EOM
)
      ;;
    nvidia_nim)
      prompt NVIDIA_API_KEY "NVIDIA_API_KEY" "$(get_existing NVIDIA_API_KEY "${EXISTING_FILES[@]}" || true)" true
      prompt NVIDIA_BASE_URL "NVIDIA_BASE_URL" "$(get_existing NVIDIA_BASE_URL "${EXISTING_FILES[@]}" || echo https://integrate.api.nvidia.com/v1)"
      prompt PRIMARY_MODEL "Primary NVIDIA NIM model" "$(get_existing MODEL_NAME "${EXISTING_FILES[@]}" || echo meta/llama-3.1-70b-instruct)"
      configure_advanced_categories NVIDIA "$PRIMARY_MODEL" 0.3 0.2 0.1 0.0 0.2
      MODEL_BLOCK_ORCH=$(cat <<EOM
# REQUIRED: Orchestrator model plugin for NVIDIA NIM.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin
# REQUIRED: NVIDIA API key.
NVIDIA_API_KEY=${NVIDIA_API_KEY}
# REQUIRED: NVIDIA base URL.
NVIDIA_BASE_URL=${NVIDIA_BASE_URL}
# REQUIRED: Primary NVIDIA model.
MODEL_NAME=${PRIMARY_MODEL}
${CATEGORY_BLOCK}
EOM
)
      MODEL_BLOCK_DL=$(cat <<EOM
# REQUIRED: Data Loader model plugin for NVIDIA NIM.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim:NvidiaNimPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim:NvidiaNimPlugin
# REQUIRED: NVIDIA API key.
NVIDIA_API_KEY=${NVIDIA_API_KEY}
# REQUIRED: NVIDIA base URL.
NVIDIA_BASE_URL=${NVIDIA_BASE_URL}
# REQUIRED: Data Loader NVIDIA model.
MODEL_NAME=${PRIMARY_MODEL}
EOM
)
      ;;
    ollama)
      prompt OLLAMA_BASE_URL "OLLAMA_BASE_URL" "$(get_existing OLLAMA_BASE_URL "${EXISTING_FILES[@]}" || echo http://host.docker.internal:11434)"
      prompt PRIMARY_MODEL "Primary Ollama model" "$(get_existing MODEL_NAME "${EXISTING_FILES[@]}" || echo llama3.1:8b)"
      configure_advanced_categories OLLAMA "$PRIMARY_MODEL" 0.3 0.2 0.1 0.0 0.2
      MODEL_BLOCK_ORCH=$(cat <<EOM
# REQUIRED: Orchestrator model plugin for Ollama.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama_enhanced:OllamaPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama_enhanced:OllamaPlugin
# REQUIRED: Ollama base URL reachable from the container.
OLLAMA_BASE_URL=${OLLAMA_BASE_URL}
# REQUIRED: Primary Ollama model.
MODEL_NAME=${PRIMARY_MODEL}
${CATEGORY_BLOCK}
EOM
)
      MODEL_BLOCK_DL=$(cat <<EOM
# REQUIRED: Data Loader model plugin for Ollama.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama:OllamaPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama:OllamaPlugin
# REQUIRED: Ollama base URL reachable from the container.
OLLAMA_BASE_URL=${OLLAMA_BASE_URL}
# REQUIRED: Data Loader Ollama model.
MODEL_NAME=${PRIMARY_MODEL}
EOM
)
      ;;
  esac
}

configure_embeddings() {
  local default_choice="1"
  case "$LLM_PROVIDER" in
    azure_openai) default_choice="1" ;;
    openai) default_choice="2" ;;
    aws_bedrock) default_choice="3" ;;
    vertex_ai) default_choice="4" ;;
    nvidia_nim) default_choice="5" ;;
    ollama) default_choice="6" ;;
    gemini) default_choice="4" ;;
  esac
  choose_num EMBEDDING_PROVIDER "Select embedding provider for RAG. Data Loader and Orchestrator must use the same embedding model for the same index." "$default_choice" \
    "azure_openai|Azure OpenAI embeddings" \
    "openai|OpenAI embeddings" \
    "aws_bedrock|AWS Bedrock embeddings" \
    "vertex_ai|Vertex AI embeddings" \
    "nvidia_nim|NVIDIA NIM embeddings" \
    "ollama|Ollama embeddings"

  case "$EMBEDDING_PROVIDER" in
    azure_openai)
      if [[ -z "${OPENAI_API_KEY:-}" ]]; then prompt OPENAI_API_KEY "Azure/OpenAI API key for embeddings" "$(get_existing OPENAI_API_KEY "${EXISTING_FILES[@]}" || true)" true; fi
      if [[ -z "${AZURE_OPENAI_ENDPOINT:-}" ]]; then prompt AZURE_OPENAI_ENDPOINT "Azure OpenAI endpoint for embeddings" "$(get_existing AZURE_OPENAI_ENDPOINT "${EXISTING_FILES[@]}" || echo https://your-resource.openai.azure.com/)"; fi
      if [[ -z "${OPENAI_API_VERSION:-}" ]]; then prompt OPENAI_API_VERSION "Azure OpenAI API version for embeddings" "$(get_existing OPENAI_API_VERSION "${EXISTING_FILES[@]}" || echo 2024-02-15-preview)"; fi
      prompt EMBEDDING_MODEL_NAME "Azure embedding deployment name" "$(get_existing EMBEDDING_MODEL_NAME "${EXISTING_FILES[@]}" || echo text-embedding-ada-002)"
      EMBED_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Embedding plugin for Azure OpenAI.
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.az_openai:AzOpenAIEmbeddingsPlugin
# REQUIRED FOR RAG: OpenAI API type for Azure OpenAI embeddings.
OPENAI_API_TYPE=azure
# REQUIRED FOR RAG: Azure OpenAI API key for embeddings.
OPENAI_API_KEY=${OPENAI_API_KEY}
# REQUIRED FOR RAG: Azure OpenAI endpoint for embeddings.
AZURE_OPENAI_ENDPOINT=${AZURE_OPENAI_ENDPOINT}
# REQUIRED FOR RAG: Azure OpenAI API version for embeddings.
OPENAI_API_VERSION=${OPENAI_API_VERSION}
# REQUIRED FOR RAG: Embedding deployment name.
EMBEDDING_MODEL_NAME=${EMBEDDING_MODEL_NAME}
EOM
)
      EMBED_BLOCK_DL="$EMBED_BLOCK_ORCH"
      ;;
    openai)
      if [[ -z "${OPENAI_API_KEY:-}" ]]; then prompt OPENAI_API_KEY "OpenAI API key for embeddings" "$(get_existing OPENAI_API_KEY "${EXISTING_FILES[@]}" || true)" true; fi
      prompt EMBEDDING_MODEL_NAME "OpenAI embedding model" "$(get_existing EMBEDDING_MODEL_NAME "${EXISTING_FILES[@]}" || echo text-embedding-ada-002)"
      EMBED_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Embedding plugin for OpenAI.
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.openai:OpenAIEmbeddingsPlugin
# REQUIRED FOR RAG: OpenAI API type.
OPENAI_API_TYPE=openai
# REQUIRED FOR RAG: OpenAI API key for embeddings.
OPENAI_API_KEY=${OPENAI_API_KEY}
# REQUIRED FOR RAG: Embedding model name.
EMBEDDING_MODEL_NAME=${EMBEDDING_MODEL_NAME}
EOM
)
      EMBED_BLOCK_DL="$EMBED_BLOCK_ORCH"
      ;;
    aws_bedrock)
      if [[ -z "${AWS_REGION:-}" ]]; then prompt AWS_REGION "AWS_REGION for embeddings" "$(get_existing AWS_REGION "${EXISTING_FILES[@]}" || echo us-east-1)"; fi
      prompt EMBEDDING_MODEL_NAME "Bedrock embedding model ID" "$(get_existing EMBEDDING_MODEL_NAME "${EXISTING_FILES[@]}" || echo amazon.titan-embed-text-v2:0)"
      EMBED_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Embedding plugin for AWS Bedrock.
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.bedrock:BedrockEmbeddingsPlugin
# REQUIRED FOR RAG: AWS region for Bedrock embeddings.
AWS_REGION=${AWS_REGION}
# REQUIRED FOR RAG: Bedrock embedding model ID.
EMBEDDING_MODEL_NAME=${EMBEDDING_MODEL_NAME}
EOM
)
      EMBED_BLOCK_DL="$EMBED_BLOCK_ORCH"
      ;;
    vertex_ai)
      if [[ -z "${PROJECT_ID:-}" ]]; then prompt PROJECT_ID "GCP PROJECT_ID for embeddings" "$(get_existing PROJECT_ID "${EXISTING_FILES[@]}" || echo your-gcp-project-id)"; fi
      if [[ -z "${LOCATION_ID:-}" ]]; then prompt LOCATION_ID "GCP LOCATION_ID for embeddings" "$(get_existing LOCATION_ID "${EXISTING_FILES[@]}" || echo us-central1)"; fi
      if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then prompt GOOGLE_APPLICATION_CREDENTIALS "GOOGLE_APPLICATION_CREDENTIALS path inside container" "$(get_existing GOOGLE_APPLICATION_CREDENTIALS "${EXISTING_FILES[@]}" || echo /app/credentials/service-account-key.json)"; fi
      prompt EMBEDDING_MODEL_NAME "Vertex AI embedding model" "$(get_existing EMBEDDING_MODEL_NAME "${EXISTING_FILES[@]}" || echo text-embedding-004)"
      EMBED_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Embedding plugin for Vertex AI.
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.vertexai:VertexAIEmbeddingsPlugin
# REQUIRED FOR RAG: GCP project ID for embeddings.
PROJECT_ID=${PROJECT_ID}
# REQUIRED FOR RAG: GCP location for embeddings.
LOCATION_ID=${LOCATION_ID}
# REQUIRED FOR RAG: Service account path inside container for embeddings.
GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS}
# REQUIRED FOR RAG: Vertex AI embedding model.
EMBEDDING_MODEL_NAME=${EMBEDDING_MODEL_NAME}
EOM
)
      EMBED_BLOCK_DL="$EMBED_BLOCK_ORCH"
      ;;
    nvidia_nim)
      if [[ -z "${NVIDIA_API_KEY:-}" ]]; then prompt NVIDIA_API_KEY "NVIDIA_API_KEY for embeddings" "$(get_existing NVIDIA_API_KEY "${EXISTING_FILES[@]}" || true)" true; fi
      if [[ -z "${NVIDIA_BASE_URL:-}" ]]; then prompt NVIDIA_BASE_URL "NVIDIA_BASE_URL for embeddings" "$(get_existing NVIDIA_BASE_URL "${EXISTING_FILES[@]}" || echo https://integrate.api.nvidia.com/v1)"; fi
      prompt EMBEDDING_MODEL_NAME "NVIDIA NIM embedding model" "$(get_existing EMBEDDING_MODEL_NAME "${EXISTING_FILES[@]}" || echo nvidia/nv-embedqa-e5-v5)"
      EMBED_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Embedding plugin for NVIDIA NIM.
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.nvidia_nim:NvidiaNimEmbeddingsPlugin
# REQUIRED FOR RAG: NVIDIA API key for embeddings.
NVIDIA_API_KEY=${NVIDIA_API_KEY}
# REQUIRED FOR RAG: NVIDIA base URL for embeddings.
NVIDIA_BASE_URL=${NVIDIA_BASE_URL}
# REQUIRED FOR RAG: NVIDIA embedding model.
EMBEDDING_MODEL_NAME=${EMBEDDING_MODEL_NAME}
EOM
)
      EMBED_BLOCK_DL="$EMBED_BLOCK_ORCH"
      ;;
    ollama)
      if [[ -z "${OLLAMA_BASE_URL:-}" ]]; then prompt OLLAMA_BASE_URL "OLLAMA_BASE_URL for embeddings" "$(get_existing OLLAMA_BASE_URL "${EXISTING_FILES[@]}" || echo http://host.docker.internal:11434)"; fi
      prompt EMBEDDING_MODEL_NAME "Ollama embedding model" "$(get_existing EMBEDDING_MODEL_NAME "${EXISTING_FILES[@]}" || echo nomic-embed-text)"
      EMBED_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Embedding plugin for Ollama.
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.ollama:OllamaEmbeddingsPlugin
# REQUIRED FOR RAG: Ollama base URL for embeddings.
OLLAMA_BASE_URL=${OLLAMA_BASE_URL}
# REQUIRED FOR RAG: Ollama embedding model.
EMBEDDING_MODEL_NAME=${EMBEDDING_MODEL_NAME}
EOM
)
      EMBED_BLOCK_DL="$EMBED_BLOCK_ORCH"
      ;;
  esac
}

configure_vector_db() {
  choose_num VECTOR_DB_PROVIDER "Select Vector DB / Knowledge Base provider. This is independent from your LLM provider." "1" \
    "azure_ai_search|Azure AI Search / Azure Cognitive Search" \
    "milvus|Milvus self-hosted" \
    "zilliz|Zilliz Cloud" \
    "redis|Redis (self-hosted)" \
    "vertex_vector_search|Vertex AI Vector Search" \
    "aws_bedrock_kb|AWS Bedrock Knowledge Bases" \
    "custom|Custom / advanced plugin entrypoints"

  VECTOR_WRITABLE="yes"
  case "$VECTOR_DB_PROVIDER" in
    azure_ai_search)
      prompt AZURE_COGNITIVE_SEARCH_SERVICE_NAME "Azure AI Search service name" "$(get_existing AZURE_COGNITIVE_SEARCH_SERVICE_NAME "${EXISTING_FILES[@]}" || echo your-search-service-name)"
      prompt AZURE_COGNITIVE_SEARCH_API_KEY "Azure AI Search API key" "$(get_existing AZURE_COGNITIVE_SEARCH_API_KEY "${EXISTING_FILES[@]}" || true)" true
      prompt AZSEARCH_EP "Azure AI Search endpoint" "$(get_existing AZSEARCH_EP "${EXISTING_FILES[@]}" || echo https://your-search-service-name.search.windows.net/)"
      AZSEARCH_KEY="$AZURE_COGNITIVE_SEARCH_API_KEY"
      VECTOR_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Retriever plugin used by Orchestrator for Azure AI Search.
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.az_cog_search:AzCognitiveSearchRetrieverPlugin
# REQUIRED FOR RAG: Azure AI Search service name.
AZURE_COGNITIVE_SEARCH_SERVICE_NAME=${AZURE_COGNITIVE_SEARCH_SERVICE_NAME}
# REQUIRED FOR RAG: Azure AI Search API key.
AZURE_COGNITIVE_SEARCH_API_KEY=${AZURE_COGNITIVE_SEARCH_API_KEY}
# REQUIRED FOR RAG: Azure AI Search endpoint.
AZSEARCH_EP=${AZSEARCH_EP}
# REQUIRED FOR RAG: Azure AI Search key alias.
AZSEARCH_KEY=${AZSEARCH_KEY}
EOM
)
      VECTOR_BLOCK_DL=$(cat <<EOM
# REQUIRED: Vector DB writer plugin used by Data Loader for Azure AI Search.
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.az_cog_search:ACognitiveSearchRetrieverPlugin
# REQUIRED: Azure AI Search service name.
AZURE_COGNITIVE_SEARCH_SERVICE_NAME=${AZURE_COGNITIVE_SEARCH_SERVICE_NAME}
# REQUIRED: Azure AI Search API key.
AZURE_COGNITIVE_SEARCH_API_KEY=${AZURE_COGNITIVE_SEARCH_API_KEY}
# REQUIRED: Azure AI Search endpoint.
AZSEARCH_EP=${AZSEARCH_EP}
# REQUIRED: Azure AI Search key alias.
AZSEARCH_KEY=${AZSEARCH_KEY}
EOM
)
      ;;
    milvus)
      prompt VECTORDB_URI "Milvus VECTORDB_URI" "$(get_existing VECTORDB_URI "${EXISTING_FILES[@]}" || echo http://your-milvus-host:19530)"
      prompt VECTORDB_TOKEN "Milvus VECTORDB_TOKEN" "$(get_existing VECTORDB_TOKEN "${EXISTING_FILES[@]}" || echo root:Milvus)" true
      VECTOR_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Retriever plugin used by Orchestrator for Milvus.
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.milvus:MilvusRetrieverPlugin
# REQUIRED FOR RAG: Milvus endpoint URI.
VECTORDB_URI=${VECTORDB_URI}
# REQUIRED FOR RAG: Milvus token or user:password.
VECTORDB_TOKEN=${VECTORDB_TOKEN}
EOM
)
      VECTOR_BLOCK_DL=$(cat <<EOM
# REQUIRED: Vector DB writer plugin used by Data Loader for Milvus.
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.milvus:MilvusRetrieverPlugin
# REQUIRED: Milvus endpoint URI.
VECTORDB_URI=${VECTORDB_URI}
# REQUIRED: Milvus token or user:password.
VECTORDB_TOKEN=${VECTORDB_TOKEN}
EOM
)
      ;;
    zilliz)
      prompt ZILLIZ_CLOUD_URI "Zilliz Cloud URI" "$(get_existing ZILLIZ_CLOUD_URI "${EXISTING_FILES[@]}" || echo https://your-instance.zillizcloud.com)"
      prompt ZILLIZ_CLOUD_API_KEY "Zilliz Cloud API key" "$(get_existing ZILLIZ_CLOUD_API_KEY "${EXISTING_FILES[@]}" || true)" true
      VECTOR_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Retriever plugin used by Orchestrator for Zilliz Cloud.
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.zilliz:ZillizRetrieverPlugin
# REQUIRED FOR RAG: Zilliz Cloud URI.
ZILLIZ_CLOUD_URI=${ZILLIZ_CLOUD_URI}
# REQUIRED FOR RAG: Zilliz Cloud API key.
ZILLIZ_CLOUD_API_KEY=${ZILLIZ_CLOUD_API_KEY}
EOM
)
      VECTOR_BLOCK_DL=$(cat <<EOM
# REQUIRED: Vector DB writer plugin used by Data Loader for Zilliz Cloud.
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.zilliz:ZillizRetrieverPlugin
# REQUIRED: Zilliz Cloud URI.
ZILLIZ_CLOUD_URI=${ZILLIZ_CLOUD_URI}
# REQUIRED: Zilliz Cloud API key.
ZILLIZ_CLOUD_API_KEY=${ZILLIZ_CLOUD_API_KEY}
EOM
)
      ;;
    redis)
      prompt REDIS_URL "REDIS_URL (may embed credentials, e.g. redis://user:pass@host:6379)" "$(get_existing REDIS_URL "${EXISTING_FILES[@]}" || echo redis://your-redis-host:6379)" true
      VECTOR_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Retriever plugin used by Orchestrator for Redis.
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.redis:RedisRetrieverPlugin
# REQUIRED FOR RAG: Redis connection URL.
REDIS_URL=${REDIS_URL}
EOM
)
      VECTOR_BLOCK_DL=$(cat <<EOM
# REQUIRED: Vector DB writer plugin used by Data Loader for Redis.
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.redis:RedisRetrieverPlugin
# REQUIRED: Redis connection URL.
REDIS_URL=${REDIS_URL}
EOM
)
      ;;
    vertex_vector_search)
      if [[ -z "${PROJECT_ID:-}" ]]; then prompt PROJECT_ID "GCP PROJECT_ID" "$(get_existing PROJECT_ID "${EXISTING_FILES[@]}" || echo your-gcp-project-id)"; fi
      if [[ -z "${LOCATION_ID:-}" ]]; then prompt LOCATION_ID "GCP LOCATION_ID" "$(get_existing LOCATION_ID "${EXISTING_FILES[@]}" || echo us-central1)"; fi
      prompt GCS_BUCKET_NAME "GCS bucket for Vertex AI Vector Search" "$(get_existing GCS_BUCKET_NAME "${EXISTING_FILES[@]}" || echo your-gcs-bucket-name)"
      prompt PRIVATE_SC_IP "PRIVATE_SC_IP (optional; leave blank if not using Private Service Connect)" "$(get_existing PRIVATE_SC_IP "${EXISTING_FILES[@]}" || true)"
      VECTOR_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Retriever plugin used by Orchestrator for Vertex AI Vector Search.
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin
# REQUIRED FOR RAG: GCP project for Vertex AI Vector Search.
PROJECT_ID=${PROJECT_ID}
# REQUIRED FOR RAG: GCP location for Vertex AI Vector Search.
LOCATION_ID=${LOCATION_ID}
# REQUIRED FOR RAG: GCS bucket used by Vertex AI Vector Search.
GCS_BUCKET_NAME=${GCS_BUCKET_NAME}
# OPTIONAL: Private Service Connect IP, if used.
PRIVATE_SC_IP=${PRIVATE_SC_IP}
EOM
)
      VECTOR_BLOCK_DL=$(cat <<EOM
# REQUIRED: Vector DB writer plugin used by Data Loader for Vertex AI Vector Search.
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin
# REQUIRED: GCP project for Vertex AI Vector Search.
PROJECT_ID=${PROJECT_ID}
# REQUIRED: GCP location for Vertex AI Vector Search.
LOCATION_ID=${LOCATION_ID}
# REQUIRED: GCS bucket used by Vertex AI Vector Search.
GCS_BUCKET_NAME=${GCS_BUCKET_NAME}
# OPTIONAL: Private Service Connect IP, if used.
PRIVATE_SC_IP=${PRIVATE_SC_IP}
EOM
)
      ;;
    aws_bedrock_kb)
      if [[ -z "${AWS_REGION:-}" ]]; then prompt AWS_REGION "AWS_REGION for Bedrock KB" "$(get_existing AWS_REGION "${EXISTING_FILES[@]}" || echo us-east-1)"; fi
      VECTOR_WRITABLE="no"
      VECTOR_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Retriever plugin used by Orchestrator for AWS Bedrock Knowledge Bases.
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.amazon_kbs:AmazonKBsRetrieverPlugin
# REQUIRED FOR RAG: AWS region for Bedrock Knowledge Bases.
AWS_REGION=${AWS_REGION}
# Runtime IAM role/user should allow: bedrock:Retrieve, bedrock:ListKnowledgeBases,
# bedrock:GetKnowledgeBase, and optionally bedrock:ListDataSources.
EOM
)
      VECTOR_BLOCK_DL=$(cat <<'EOM'
# Data Loader omitted because Bedrock Knowledge Bases use AWS-native ingestion from S3.
EOM
)
      DATA_LOADER_NOTICE="AWS Bedrock Knowledge Bases should be populated through AWS-native ingestion, not Spotfire Data Loader."
      ;;
    custom)
      warn "Custom mode writes plugin entrypoints only. Add provider-specific variables manually after generation."
      prompt CUSTOM_RETRIEVER_PLUGIN "RETRIEVER_PLUGIN_ENTRY_POINT" "$(get_existing RETRIEVER_PLUGIN_ENTRY_POINT "${EXISTING_FILES[@]}" || echo plugins.retrievers.example:ExampleRetrieverPlugin)"
      yes_no_num CUSTOM_HAS_LOADER "Does this vector DB have a Data Loader writer plugin you want to configure now?" "no"
      VECTOR_WRITABLE="no"
      if [[ "$CUSTOM_HAS_LOADER" == "yes" ]]; then
        VECTOR_WRITABLE="yes"
        prompt CUSTOM_VECTORDB_PLUGIN "VECTORDB_PLUGIN_ENTRY_POINT" "$(get_existing VECTORDB_PLUGIN_ENTRY_POINT "${EXISTING_FILES[@]}" || echo plugins.vectordbs.example:ExampleVectorDbPlugin)"
      else
        CUSTOM_VECTORDB_PLUGIN=""
      fi
      VECTOR_BLOCK_ORCH=$(cat <<EOM
# REQUIRED FOR RAG: Custom retriever plugin used by Orchestrator.
RETRIEVER_PLUGIN_ENTRY_POINT=${CUSTOM_RETRIEVER_PLUGIN}
# TODO: Add required custom vector DB credentials below.
EOM
)
      if [[ "$VECTOR_WRITABLE" == "yes" ]]; then
        VECTOR_BLOCK_DL=$(cat <<EOM
# REQUIRED: Custom vector DB writer plugin used by Data Loader.
VECTORDB_PLUGIN_ENTRY_POINT=${CUSTOM_VECTORDB_PLUGIN}
# TODO: Add required custom vector DB credentials below.
EOM
)
      else
        VECTOR_BLOCK_DL="# OPTIONAL: Data Loader disabled or native ingestion required for custom vector DB."
      fi
      ;;
  esac
}


# ---------- cloud template env shortlist mode ----------
cloud_target_label() {
  case "${1:-}" in
    azure_container_apps) echo "Azure Container Apps" ;;
    aws_ecs_fargate) echo "AWS ECS / Fargate" ;;
    gcp_cloud_run) echo "GCP Cloud Run" ;;
    kubernetes) echo "Kubernetes (AKS / EKS / GKE)" ;;
    other_cloud) echo "Other cloud / customer-managed container platform" ;;
    *) echo "Cloud provider" ;;
  esac
}

cloud_secret_store_label() {
  case "${1:-}" in
    azure_container_apps) echo "Azure Key Vault / Azure Container App secrets" ;;
    aws_ecs_fargate) echo "AWS Secrets Manager or SSM Parameter Store" ;;
    gcp_cloud_run) echo "GCP Secret Manager" ;;
    kubernetes) echo "Kubernetes Secret, or external secret manager via CSI/external-secrets" ;;
    other_cloud) echo "Platform secret manager" ;;
    *) echo "Platform secret manager" ;;
  esac
}

cloud_secret_reference_hint() {
  case "${1:-}" in
    azure_container_apps) echo "For Azure Container Apps, create app secrets/Key Vault references and map env vars with secretref:<secret-name>." ;;
    aws_ecs_fargate) echo "For AWS ECS/Fargate, store secrets in Secrets Manager/SSM and map env vars with valueFrom in the task definition." ;;
    gcp_cloud_run) echo "For GCP Cloud Run, store values in Secret Manager and map them as secret-backed environment variables." ;;
    kubernetes) echo "For Kubernetes, put SECRET variables in a Secret and CONFIG variables in a ConfigMap." ;;
    other_cloud) echo "Use your platform's secret manager for SECRET variables and normal environment variables for CONFIG variables." ;;
    *) echo "Use your platform's secret manager for SECRET variables and normal environment variables for CONFIG variables." ;;
  esac
}

cloud_llm_block() {
  case "${1:-}" in
    azure_openai)
      cat <<'EOM'
# ============================================================
# 05_LLM_PROVIDER_AZURE_OPENAI
# Include these in the Orchestrator container.
# ============================================================

# CONFIG
MODEL_PLUGIN_ENTRY_POINT=plugins.models.azure_openai_enhanced:AzureOpenAIPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.azure_openai_enhanced:AzureOpenAIPlugin
OPENAI_API_TYPE=azure
AZURE_OPENAI_ENDPOINT=
OPENAI_API_VERSION=

# SECRET
OPENAI_API_KEY=

# OPTIONAL CONFIG - only if GPT-5.x / o-series Azure OpenAI deployments are used
# OPENAI_GPT5_COMPATIBLE=true
EOM
 ;;
    openai)
      cat <<'EOM'
# ============================================================
# 05_LLM_PROVIDER_OPENAI
# Include these in the Orchestrator container.
# ============================================================

# CONFIG
MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai_enhanced:OpenAIPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai_enhanced:OpenAIPlugin
OPENAI_API_TYPE=openai
# OPENAI_API_BASE=

# SECRET
OPENAI_API_KEY=

# OPTIONAL CONFIG - only if GPT-5.x / o-series models are used
# OPENAI_GPT5_COMPATIBLE=true
EOM
 ;;
    aws_bedrock)
      cat <<'EOM'
# ============================================================
# 05_LLM_PROVIDER_AWS_BEDROCK
# Include these in the Orchestrator container.
# Prefer task role / IAM role over explicit AWS keys.
# ============================================================

# CONFIG
MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock_enhanced:BedrockPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock_enhanced:BedrockPlugin
AWS_REGION=

# OPTIONAL SECRET - only when IAM/task role is not used
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=
# AWS_SESSION_TOKEN=
# AWS_PROFILE_NAME=
EOM
 ;;
    vertex_ai)
      cat <<'EOM'
# ============================================================
# 05_LLM_PROVIDER_GOOGLE_VERTEX_AI
# Include these in the Orchestrator container.
# Prefer workload identity / platform identity where available.
# ============================================================

# CONFIG
MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai_enhanced:VertexAIPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai_enhanced:VertexAIPlugin
PROJECT_ID=
LOCATION_ID=
GOOGLE_APPLICATION_CREDENTIALS=

# SECRET / FILE SECRET - only if using a service account JSON file
# GOOGLE_APPLICATION_CREDENTIALS_JSON=
EOM
 ;;
    gemini)
      cat <<'EOM'
# ============================================================
# 05_LLM_PROVIDER_GOOGLE_GEMINI_API
# Include these in the Orchestrator container.
# ============================================================

# CONFIG
MODEL_PLUGIN_ENTRY_POINT=plugins.models.gemini_enhanced:GeminiPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.gemini_enhanced:GeminiPlugin

# SECRET
GOOGLE_API_KEY=
EOM
 ;;
    nvidia_nim)
      cat <<'EOM'
# ============================================================
# 05_LLM_PROVIDER_NVIDIA_NIM
# Include these in the Orchestrator container.
# ============================================================

# CONFIG
MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin
NVIDIA_BASE_URL=

# SECRET
NVIDIA_API_KEY=
EOM
 ;;
    ollama)
      cat <<'EOM'
# ============================================================
# 05_LLM_PROVIDER_OLLAMA_SELF_HOSTED
# Include these in the Orchestrator container.
# ============================================================

# CONFIG
MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama_enhanced:OllamaPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama_enhanced:OllamaPlugin
OLLAMA_BASE_URL=
EOM
 ;;
    *)
      cat <<'EOM'
# ============================================================
# 05_LLM_PROVIDER_CUSTOM
# ============================================================

MODEL_PLUGIN_ENTRY_POINT=
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=
# PROVIDER_API_KEY=
# PROVIDER_ENDPOINT=
EOM
 ;;
  esac
}

cloud_embeddings_block() {
  case "${1:-}" in
    azure_openai)
      cat <<'EOM'
# ============================================================
# 06_EMBEDDINGS_AZURE_OPENAI
# ============================================================

# CONFIG
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.az_openai:AzOpenAIEmbeddingsPlugin
OPENAI_API_TYPE=azure
AZURE_OPENAI_ENDPOINT=
OPENAI_API_VERSION=

# SECRET
OPENAI_API_KEY=
EOM
 ;;
    openai)
      cat <<'EOM'
# ============================================================
# 06_EMBEDDINGS_OPENAI
# ============================================================

# CONFIG
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.openai:OpenAIEmbeddingsPlugin
OPENAI_API_TYPE=openai
# OPENAI_API_BASE=

# SECRET
OPENAI_API_KEY=
EOM
 ;;
    aws_bedrock)
      cat <<'EOM'
# ============================================================
# 06_EMBEDDINGS_AWS_BEDROCK
# Prefer IAM/task role in AWS cloud deployments.
# ============================================================

# CONFIG
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.bedrock:BedrockEmbeddingsPlugin
AWS_REGION=

# OPTIONAL SECRET - local development only; do not set when using IAM role
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=
# AWS_SESSION_TOKEN=
# AWS_PROFILE_NAME=
EOM
 ;;
    vertex_ai)
      cat <<'EOM'
# ============================================================
# 06_EMBEDDINGS_VERTEX_AI
# ============================================================

# CONFIG
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.vertexai:VertexAIEmbeddingsPlugin
PROJECT_ID=
LOCATION_ID=
EMBEDDING_MODEL_NAME=
GOOGLE_APPLICATION_CREDENTIALS=
EOM
 ;;
    nvidia_nim)
      cat <<'EOM'
# ============================================================
# 06_EMBEDDINGS_NVIDIA_NIM
# ============================================================

# CONFIG
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.nvidia_nim:NvidiaNimEmbeddingsPlugin
NVIDIA_BASE_URL=

# SECRET
NVIDIA_API_KEY=
EOM
 ;;
    ollama)
      cat <<'EOM'
# ============================================================
# 06_EMBEDDINGS_OLLAMA
# ============================================================

# CONFIG
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.ollama:OllamaEmbeddingsPlugin
OLLAMA_BASE_URL=
EMBEDDING_MODEL_NAME=
EOM
 ;;
    *)
      cat <<'EOM'
# ============================================================
# 06_EMBEDDINGS_CUSTOM_OR_NOT_LISTED
# The selected embedding provider is not listed as a first-party embeddings block
# in the backend guide. Enter only variables required by your custom plugin.
# ============================================================

EMBEDDINGS_PLUGIN_ENTRY_POINT=
EMBEDDING_MODEL_NAME=
EOM
 ;;
  esac
}

cloud_vector_block() {
  case "${1:-}" in
    azure_ai_search)
      cat <<'EOM'
# ============================================================
# 07_KNOWLEDGE_BASE_AZURE_COGNITIVE_SEARCH
# ============================================================

# CONFIG
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.az_cog_search:AzCognitiveSearchRetrieverPlugin
AZURE_COGNITIVE_SEARCH_SERVICE_NAME=

# SECRET
AZURE_COGNITIVE_SEARCH_API_KEY=
EOM
 ;;
    milvus)
      cat <<'EOM'
# ============================================================
# 07_KNOWLEDGE_BASE_MILVUS
# ============================================================

# CONFIG
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.milvus:MilvusRetrieverPlugin
VECTORDB_URI=

# SECRET
VECTORDB_TOKEN=
EOM
 ;;
    zilliz)
      cat <<'EOM'
# ============================================================
# 07_KNOWLEDGE_BASE_ZILLIZ_CLOUD
# ============================================================

# CONFIG
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.zilliz:ZillizRetrieverPlugin
ZILLIZ_CLOUD_URI=

# SECRET
ZILLIZ_CLOUD_API_KEY=
EOM
 ;;
    qdrant)
      cat <<'EOM'
# ============================================================
# 07_KNOWLEDGE_BASE_QDRANT
# ============================================================

# CONFIG
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.qdrant:QdrantRetrieverPlugin
QDRANT_URL=

# SECRET - leave empty for local/no-auth Qdrant
QDRANT_API_KEY=
EOM
 ;;
    mongodb_atlas)
      cat <<'EOM'
# ============================================================
# 07_KNOWLEDGE_BASE_MONGODB_ATLAS
# ============================================================

# CONFIG
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.mongo:MongoRetrieverPlugin
MONGODB_ATLAS_DB_NAME=
MONGODB_ATLAS_COLLECTION_NAME=
MONGODB_ATLAS_INDEX_DIMENSIONS=1536

# SECRET
MONGODB_ATLAS_CLUSTER_URI=
EOM
 ;;
    redis)
      cat <<'EOM'
# ============================================================
# 07_KNOWLEDGE_BASE_REDIS
# ============================================================

# CONFIG or SECRET depending on whether credentials are embedded in the URL
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.redis:RedisRetrieverPlugin
REDIS_URL=
EOM
 ;;
    vertex_vector_search)
      cat <<'EOM'
# ============================================================
# 07_KNOWLEDGE_BASE_VERTEX_AI_VECTOR_SEARCH
# ============================================================

# CONFIG
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin
PROJECT_ID=
LOCATION_ID=
GCS_BUCKET_NAME=
# PRIVATE_SC_IP=
EOM
 ;;
    aws_bedrock_kb)
      cat <<'EOM'
# ============================================================
# 07_KNOWLEDGE_BASE_AWS_BEDROCK_KNOWLEDGE_BASES
# ============================================================

# CONFIG
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.amazon_kbs:AmazonKBsRetrieverPlugin
AWS_REGION=

# IAM permissions needed by the runtime role/user:
# bedrock:Retrieve
# bedrock:ListKnowledgeBases
# bedrock:GetKnowledgeBase
# bedrock:ListDataSources
EOM
 ;;
    databricks)
      cat <<'EOM'
# ============================================================
# 07_KNOWLEDGE_BASE_DATABRICKS
# Documented retriever variables only.
# ============================================================

# CONFIG
DATABRICKS_HOST=
DATABRICKS_ENDPOINT=
DATABRICKS_TEXT_COLUMN=
DATABRICKS_COLUMNS=

# SECRET
DATABRICKS_TOKEN=
EOM
 ;;
    pgvector)
      cat <<'EOM'
# ============================================================
# 07_KNOWLEDGE_BASE_POSTGRESQL_PGVECTOR
# Documented retriever variables only.
# ============================================================

# SECRET
PGVECTOR_CONNECTION_STRING=
EOM
 ;;
    *)
      cat <<'EOM'
# ============================================================
# 07_KNOWLEDGE_BASE_CUSTOM_OR_OTHER
# Enter only variables documented by your custom retriever plugin.
# ============================================================

RETRIEVER_PLUGIN_ENTRY_POINT=
EOM
 ;;
  esac
}

run_cloud_master_env_mode() {
  section "Cloud  env shortlist mode"
  info "This mode shortlists the env variables the customer must configure in the cloud platform."

  # ----- optional: generate the four core credentials and inline them -----
  # By default the checklist is name-only. On request we run the official
  # generate_credentials.py and fill SECRET_KEY, HASHED_ADMIN_PASSWORD,
  # OAUTH2_CLIENT_SECRET_HASH and OAUTH2_CLIENT_ID directly into the template so the
  # customer can copy-paste them into their cloud secret manager. Customers who use
  # their own approved tool can decline, and the fields stay blank as before.
  local CLOUD_GEN_CREDS="no" C_SECRET_KEY="" C_HASHED_ADMIN="" C_OAUTH_ID="" C_OAUTH_HASH="" GEN_CLOUD_CREDS=""
  info "The four core credentials (SECRET_KEY, HASHED_ADMIN_PASSWORD, OAUTH2_CLIENT_ID, OAUTH2_CLIENT_SECRET_HASH) can be generated now and written straight into the checklist for copy-paste."
  info "Choose No if you prefer to produce them with your own approved tool - the fields will be left blank for you to fill in."
  yes_no_num GEN_CLOUD_CREDS "Generate these credentials now and fill them into the template?" "no"
  if [[ "$GEN_CLOUD_CREDS" == "yes" ]]; then
    section "Credentials"
    ensure_linux_prereqs
    generate_credentials_file "$OUT_DIR/copilot-generated-values.txt"
    C_SECRET_KEY="$(get_from_credentials_file SECRET_KEY "$CREDENTIALS_FILE")"
    C_HASHED_ADMIN="$(get_from_credentials_file HASHED_ADMIN_PASSWORD "$CREDENTIALS_FILE")"
    C_OAUTH_ID="$(get_from_credentials_file OAUTH2_CLIENT_ID "$CREDENTIALS_FILE")"
    C_OAUTH_HASH="$(get_from_credentials_file OAUTH2_CLIENT_SECRET_HASH "$CREDENTIALS_FILE")"
    CLOUD_GEN_CREDS="yes"
  fi

  prompt_image_tag IMAGE_TAG "Copilot backend/data-loader image tag to show in the checklist" "${DEFAULT_IMAGE_TAG}" ""
  FASTAPI_APP_VERSION="$IMAGE_TAG"

  yes_no_num ENABLE_ADMIN_CONSOLE "Include Admin Console variables?" "yes"
  yes_no_num ENABLE_RAG "Include RAG / Knowledge Base variables?" "yes"

  choose_num LLM_PROVIDER "Which LLM provider should the checklist include?" "1" \
    "azure_openai|Azure OpenAI" \
    "openai|OpenAI" \
    "aws_bedrock|AWS Bedrock" \
    "vertex_ai|Google Vertex AI" \
    "gemini|Google Gemini API" \
    "nvidia_nim|NVIDIA NIM" \
    "ollama|Ollama / self-hosted" \
    "custom|Custom / other"

  if [[ "$ENABLE_RAG" == "yes" ]]; then
    choose_num EMBEDDING_PROVIDER "Which embeddings provider should the checklist include?" "1" \
      "same_as_llm|Same family as selected LLM if documented" \
      "azure_openai|Azure OpenAI embeddings" \
      "openai|OpenAI embeddings" \
      "aws_bedrock|AWS Bedrock embeddings" \
      "vertex_ai|Google Vertex AI embeddings" \
      "nvidia_nim|NVIDIA NIM embeddings" \
      "ollama|Ollama embeddings" \
      "custom|Custom / other embeddings"
    if [[ "$EMBEDDING_PROVIDER" == "same_as_llm" ]]; then
      case "$LLM_PROVIDER" in
        azure_openai|openai|aws_bedrock|vertex_ai|nvidia_nim|ollama) EMBEDDING_PROVIDER="$LLM_PROVIDER" ;;
        *) EMBEDDING_PROVIDER="custom"; warn "The backend guide does not list a first-party embeddings block for $LLM_PROVIDER; using custom embeddings placeholders." ;;
      esac
    fi

    choose_num VECTOR_DB_PROVIDER "Which Vector DB / Knowledge Base should the checklist include?" "1" \
      "azure_ai_search|Azure AI Search / Azure Cognitive Search" \
      "milvus|Milvus self-hosted" \
      "zilliz|Zilliz Cloud" \
      "qdrant|Qdrant" \
      "mongodb_atlas|MongoDB Atlas" \
      "redis|Redis" \
      "vertex_vector_search|Vertex AI Vector Search" \
      "aws_bedrock_kb|AWS Bedrock Knowledge Bases" \
      "databricks|Databricks" \
      "pgvector|PostgreSQL pgvector" \
      "custom|Custom / other"
    if [[ "$VECTOR_DB_PROVIDER" == "aws_bedrock_kb" ]]; then
      ENABLE_DATA_LOADER="no"
      warn "Bedrock Knowledge Bases usually use AWS-native ingestion. Data Loader variables will be omitted."
    else
      yes_no_num ENABLE_DATA_LOADER "Include Data Loader variables?" "yes"
    fi
  else
    EMBEDDING_PROVIDER="none"
    VECTOR_DB_PROVIDER="none"
    ENABLE_DATA_LOADER="no"
  fi

  yes_no_num ENABLE_AGENT_REGISTRY "Include Agent Registry variables?" "no"

  local cloud_file="$OUT_DIR/cloud-env-template.env"
  local target_label secret_store secret_hint data_loader_section admin_section rag_defaults_section agent_section
  target_label="$(cloud_target_label "$DEPLOYMENT_TARGET")"
  secret_store="$(cloud_secret_store_label "$DEPLOYMENT_TARGET")"
  secret_hint="$(cloud_secret_reference_hint "$DEPLOYMENT_TARGET")"

  if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
    admin_section=$(cat <<EOM
# ############################################################
# CONTAINER: ADMIN CONSOLE
# Copy every variable in this block into the Admin Console container.
# The SECRET values below MUST be identical to the same variables in
# the Orchestrator container - copy the exact same values into both.
# ############################################################

# CONFIG
ORCHESTRATOR_INTERNAL_URL=

# SECRET - must match the Orchestrator container exactly
SECRET_KEY=${C_SECRET_KEY}
DATABASE_URL=
SYNC_DATABASE_URL=
HASHED_ADMIN_PASSWORD=${C_HASHED_ADMIN}
EOM
)
  else
    admin_section="# CONTAINER: ADMIN CONSOLE omitted because Admin Console was not selected."
  fi

  if [[ "$ENABLE_RAG" == "yes" ]]; then
    rag_defaults_section=$(cat <<'EOM'
# ============================================================
# 08_RAG_OPTIONAL_TUNING
# Optional documented RAG tuning values. Dont use them unless needed
# ============================================================

# CONFIG
# RAG_COLLECTIONS_METADATA=[]
# DEFAULT_RAG_TOPK=10
# DEFAULT_RAG_SCORE_THRESHOLD=0.5
# DEFAULT_RAG_RETRIEVER_TYPE=vector-store
EOM
)
  else
    rag_defaults_section="# 08_RAG_OPTIONAL_TUNING omitted because RAG was not selected."
  fi

  if [[ "$ENABLE_DATA_LOADER" == "yes" ]]; then
    data_loader_section=$(cat <<'EOM'
# ############################################################
# CONTAINER: DATA LOADER
# Copy the documented Data Loader variables for the specific loader
# image you deploy (see the Data Loader guide) into this container.
# It reuses the SAME embeddings and vector-DB SECRET values as the
# Orchestrator container - copy those identical values here too.
# ############################################################
EOM
)
  else
    data_loader_section="# CONTAINER: DATA LOADER omitted because Data Loader was not selected."
  fi

  if [[ "$ENABLE_AGENT_REGISTRY" == "yes" ]]; then
    agent_section=$(cat <<'EOM'
# ############################################################
# CONTAINER: AGENT REGISTRY
# Copy every variable in this block into the Agent Registry container.
# Agent Registry has two credential sets: AUTH_* and ORCHESTRATOR_*.
# ############################################################

# CONFIG
AUTH_CLIENT_ID=
ORCHESTRATOR_URL=
ORCHESTRATOR_CLIENT_ID=
BASE_URL=
CUSTOM_WORKFLOWS_DIR=/custom-workflows
MCP_ENABLED=false
TUNNEL_ENABLED=false

# SECRET
AUTH_CLIENT_SECRET=
AUTH_SIGNING_KEY=
ORCHESTRATOR_CLIENT_SECRET=
EOM
)
  else
    agent_section="# CONTAINER: AGENT REGISTRY omitted because Agent Registry was not selected."
  fi

  local content
  local secrets_present_note="#"
  if [[ "$CLOUD_GEN_CREDS" == "yes" ]]; then
    secrets_present_note=$(cat <<'EOM'
#
# ############################################################
# !! THIS FILE CONTAINS REAL GENERATED SECRETS !!
# SECRET_KEY, HASHED_ADMIN_PASSWORD and OAUTH2_CLIENT_SECRET_HASH below
# have been filled in with freshly generated values for copy-paste.
# - Please keep this template file safe and treat it as a secret.
# - After copying the values into your cloud secret manager, delete this
#   file or move it into a secure vault.
# - Do NOT commit it to version control.
# ############################################################
#
EOM
)
  fi
  content=$(cat <<EOM
# ============================================================
# Spotfire Copilot Cloud Template ENV Checklist
# Target deployment: ${target_label}
# Secret store: ${secret_store}
${secrets_present_note}
# PURPOSE
# This file is a customer-facing checklist for cloud deployments.
# Please copy the variable names from this file into your cloud
# provider UI, CLI, or IaC tool, and then enter either:
#   - the actual non-secret CONFIG value, or
#   - a reference to a secret already created in the cloud secret manager.
#
# IMPORTANT
# This is not a completed runtime env file and should not be blindly mounted
# into production containers. Any GENERATED secret values present below must be
# moved into your cloud secret manager; supply all remaining secret values
# yourself from your approved tool or secret store.
#
# HOW TO USE
# This file is organized into per-container blocks marked "CONTAINER: <name>".
# For each container you deploy, copy the variables from its block into that
# container's environment / secret configuration only.
# 1. Review each CONTAINER block for the components you are deploying.
# 2. Put SECRET variables into ${secret_store}.
# 3. Put CONFIG variables into normal environment-variable configuration.
# 4. Keep STORE ONLY values in a password vault; do not inject them into containers.
# 5. Where a value is duplicated across blocks (e.g. SECRET_KEY, DATABASE_URL,
#    HASHED_ADMIN_PASSWORD in Orchestrator and Admin Console) use the IDENTICAL
#    value in every block - they must match.
# 6. Deploy the selected containers using the cloud provider UI, CLI, or IaC tool.
#
# CLOUD SECRET MAPPING
# ${secret_hint}
#
# VARIABLE CLASSIFICATION
# SECRET     = store in cloud secret manager and reference from env var.
# CONFIG     = normal environment variable.
# STORE ONLY = keep in password vault; do not inject into containers.
#
# GENERATED SELECTIONS OVERVIEW
#
# Deployment target: ${target_label}
# LLM provider: ${LLM_PROVIDER}
# RAG enabled: ${ENABLE_RAG}
# Embeddings provider: ${EMBEDDING_PROVIDER}
# Vector DB provider: ${VECTOR_DB_PROVIDER}
# Data Loader: ${ENABLE_DATA_LOADER}
# Agent Registry: ${ENABLE_AGENT_REGISTRY}
# ============================================================

# ============================================================
# 00_DEPLOYMENT_AND_IMAGE_NOTES
# These are notes only, not container environment variables.
# Target deployment: ${target_label}
# Selected image tag: ${IMAGE_TAG}
# Orchestrator image: copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:${IMAGE_TAG}
# Admin Console image: copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:${IMAGE_TAG}
# Data Loader image family: copilotoci.azurecr.io/spotfirecopilot/data-loader-<type>:${IMAGE_TAG}
# Registry credentials are configured as image-pull/platform settings, not app env vars.

# ############################################################
# CONTAINER: ORCHESTRATOR
# Copy every variable from here through the end of the RAG tuning
# section into the Orchestrator container's environment / secret config.
# ############################################################

# ------------------------------------------------------------
# 02_ORCHESTRATOR_CORE
# ------------------------------------------------------------

# GENERATED + SECRET
SECRET_KEY=${C_SECRET_KEY}
HASHED_ADMIN_PASSWORD=${C_HASHED_ADMIN}
OAUTH2_CLIENT_SECRET_HASH=${C_OAUTH_HASH}

# GENERATED + CONFIG
OAUTH2_CLIENT_ID=${C_OAUTH_ID}

# STORE ONLY - generated plaintext values shown once; keep in secure vault
# Do not inject these into the container unless a documented setup flow requires it.
# ADMIN_PASSWORD_PLAINTEXT=
# OAUTH2_CLIENT_SECRET_PLAINTEXT=

# CONFIG
LOG_LEVEL=INFO

# ------------------------------------------------------------
# 03_DATABASE
# Managed PostgreSQL is recommended for cloud deployments.
# The same DATABASE_URL / SYNC_DATABASE_URL values are also copied
# into the Admin Console container block below.
# ------------------------------------------------------------

# SECRET
DATABASE_URL=
SYNC_DATABASE_URL=

# CONFIG
DB_SSLMODE=require

$(cloud_llm_block "$LLM_PROVIDER")

$(if [[ "$ENABLE_RAG" == "yes" ]]; then cloud_embeddings_block "$EMBEDDING_PROVIDER"; else echo "# 06_EMBEDDINGS omitted because RAG was not selected."; fi)

$(if [[ "$ENABLE_RAG" == "yes" ]]; then cloud_vector_block "$VECTOR_DB_PROVIDER"; else echo "# 07_VECTOR_DB omitted because RAG was not selected."; fi)

${rag_defaults_section}

${admin_section}

${data_loader_section}

${agent_section}

EOM
)

  write_file "$cloud_file" "$content"

  if [[ "$CLOUD_GEN_CREDS" == "yes" ]]; then
    chmod 600 "$cloud_file" 2>/dev/null || true
    warn "This template now contains REAL generated secrets (SECRET_KEY, HASHED_ADMIN_PASSWORD, OAUTH2_CLIENT_SECRET_HASH). Please keep this template file safe: copy the values into your cloud secret manager, then delete the file or move it into a secure vault. Do not commit it to version control."
  fi

  ok "Cloud template env checklist generated."
  echo "cloud-env-template.env: $cloud_file"
  echo
  info "No Docker Compose files were generated in cloud mode."
  info "Use the generated checklist to configure cloud secrets/env vars in the selected platform."
}

# ---------- kubernetes (Helm) mode ----------

# Map an LLM provider key to the orchestrator chart's model plugin entry point.
k8s_model_plugin() {
  case "$1" in
    azure_openai) echo "plugins.models.azure_openai_enhanced:AzureOpenAIPlugin" ;;
    openai)       echo "plugins.models.openai_enhanced:OpenAIPlugin" ;;
    aws_bedrock)  echo "plugins.models.bedrock_enhanced:BedrockPlugin" ;;
    vertex_ai)    echo "plugins.models.vertexai_enhanced:VertexAIPlugin" ;;
    gemini)       echo "plugins.models.gemini_enhanced:GeminiPlugin" ;;
    nvidia_nim)   echo "plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin" ;;
    ollama)       echo "plugins.models.ollama_enhanced:OllamaPlugin" ;;
    *)            echo "" ;;
  esac
}

# Map an embeddings provider key to the orchestrator chart's embeddings plugin entry point.
k8s_embeddings_plugin() {
  case "$1" in
    azure_openai) echo "plugins.embeddings.az_openai:AzOpenAIEmbeddingsPlugin" ;;
    openai)       echo "plugins.embeddings.openai:OpenAIEmbeddingsPlugin" ;;
    aws_bedrock)  echo "plugins.embeddings.bedrock:BedrockEmbeddingsPlugin" ;;
    vertex_ai)    echo "plugins.embeddings.vertexai:VertexAIEmbeddingsPlugin" ;;
    nvidia_nim)   echo "plugins.embeddings.nvidia_nim:NvidiaNimEmbeddingsPlugin" ;;
    ollama)       echo "plugins.embeddings.ollama:OllamaEmbeddingsPlugin" ;;
    *)            echo "" ;;
  esac
}

# Map a vector DB / retriever key to the orchestrator chart's retriever plugin entry point.
k8s_retriever_plugin() {
  case "$1" in
    azure_ai_search)      echo "plugins.retrievers.az_cog_search:AzCognitiveSearchRetrieverPlugin" ;;
    milvus)               echo "plugins.retrievers.milvus:MilvusRetrieverPlugin" ;;
    zilliz)               echo "plugins.retrievers.zilliz:ZillizRetrieverPlugin" ;;
    vertex_vector_search) echo "plugins.retrievers.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin" ;;
    aws_bedrock_kb)       echo "plugins.retrievers.amazon_kbs:AmazonKBsRetrieverPlugin" ;;
    *)                    echo "" ;;
  esac
}

# Generate a Helm values bundle (values.yaml + secrets.values.yaml + helm-install.sh)
# for the official orchestrator-stack OCI chart. No cluster access is needed to
# generate the files; the operator runs helm-install.sh from a machine with helm
# and kubectl configured against the target cluster.
run_kubernetes_mode() {
  local K8S_CHART_VERSION=""
  local k8s_dir="$OUT_DIR/k8s"

  section "Kubernetes (Helm) mode"
  info "This mode generates a Helm values bundle for the official Spotfire Copilot 'orchestrator-stack' chart."
  info "It writes values.yaml, secrets.values.yaml, helm-install.sh, and copilot-generated-values.txt under: $k8s_dir"
  info "The generated helm-install.sh deploys the orchestrator, optional Admin Console, and optional in-cluster PostgreSQL."

  # Credentials first: run the official generate_credentials.py (mandated next to this
  # installer, exactly like the Linux VM flow) and capture its output so real values are
  # written into secrets.values.yaml instead of leaving blanks for manual pasting.
  section "Credentials"
  info "This mode runs the official generate_credentials.py and writes SECRET_KEY, HASHED_ADMIN_PASSWORD, OAUTH2_CLIENT_ID, and OAUTH2_CLIENT_SECRET_HASH into secrets.values.yaml."
  ensure_linux_prereqs
  mkdir -p "$k8s_dir"
  generate_credentials_file "$k8s_dir/copilot-generated-values.txt"
  local K8S_SECRET_KEY K8S_HASHED_ADMIN_PW K8S_OAUTH_ID K8S_OAUTH_HASH
  K8S_SECRET_KEY="$(get_from_credentials_file SECRET_KEY "$CREDENTIALS_FILE")"
  K8S_HASHED_ADMIN_PW="$(get_from_credentials_file HASHED_ADMIN_PASSWORD "$CREDENTIALS_FILE")"
  K8S_OAUTH_ID="$(get_from_credentials_file OAUTH2_CLIENT_ID "$CREDENTIALS_FILE")"
  K8S_OAUTH_HASH="$(get_from_credentials_file OAUTH2_CLIENT_SECRET_HASH "$CREDENTIALS_FILE")"

  prompt K8S_NAMESPACE "Kubernetes namespace to deploy into" "copilot"
  prompt_required K8S_CHART_VERSION "Approved orchestrator-stack Helm chart version (--version)" "0.3.4"
  prompt_image_tag IMAGE_TAG "Copilot orchestrator image tag" "${DEFAULT_IMAGE_TAG}" "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator"
  [[ -n "$IMAGE_TAG" ]] || IMAGE_TAG="${DEFAULT_IMAGE_TAG}"
  prompt K8S_PULL_SECRET "Name of the Kubernetes image pull Secret for the ACR registry" "orchestrator-acr-pull"

  yes_no_num K8S_BUNDLED_DB "Deploy a PostgreSQL container inside the cluster (bundled)? Choose No to use an external/managed PostgreSQL." "no"
  local pg_password="" db_url="" sync_db_url="" K8S_PG_STORAGE_CLASS="" K8S_PG_SIZE="100Gi"
  if [[ "$K8S_BUNDLED_DB" == "yes" ]]; then
    pg_password="$(random_hex_32)"
    db_url="postgresql+asyncpg://orchestrator:${pg_password}@orchestrator-postgresql:5432/orchestrator"
    sync_db_url="postgresql://orchestrator:${pg_password}@orchestrator-postgresql:5432/orchestrator"
    prompt K8S_PG_STORAGE_CLASS "StorageClass for the bundled PostgreSQL volume (leave blank for the cluster default)" ""
    prompt K8S_PG_SIZE "Persistent volume size for the bundled PostgreSQL" "100Gi"
    info "A random PostgreSQL password was generated and written into secrets.values.yaml and the database URLs."
  else
    info "You chose external PostgreSQL. databaseUrl and syncDatabaseUrl will be left blank in secrets.values.yaml for you to fill in."
  fi

  yes_no_num ENABLE_ADMIN_CONSOLE "Deploy the Admin Console alongside the orchestrator?" "yes"

  choose_num LLM_PROVIDER "Which LLM provider will the orchestrator use?" "1" \
    "azure_openai|Azure OpenAI" \
    "openai|OpenAI" \
    "aws_bedrock|AWS Bedrock" \
    "vertex_ai|Google Vertex AI" \
    "gemini|Google Gemini API" \
    "nvidia_nim|NVIDIA NIM" \
    "ollama|Ollama / self-hosted"
  local model_plugin
  model_plugin="$(k8s_model_plugin "$LLM_PROVIDER")"

  yes_no_num ENABLE_RAG "Enable RAG / vector-store retrieval?" "no"
  local embeddings_plugin="" retriever_plugin=""
  if [[ "$ENABLE_RAG" == "yes" ]]; then
    choose_num EMBEDDING_PROVIDER "Which embeddings provider?" "1" \
      "azure_openai|Azure OpenAI embeddings" \
      "openai|OpenAI embeddings" \
      "aws_bedrock|AWS Bedrock embeddings" \
      "vertex_ai|Google Vertex AI embeddings" \
      "nvidia_nim|NVIDIA NIM embeddings" \
      "ollama|Ollama embeddings"
    embeddings_plugin="$(k8s_embeddings_plugin "$EMBEDDING_PROVIDER")"
    choose_num VECTOR_DB_PROVIDER "Which retriever / vector store?" "1" \
      "azure_ai_search|Azure AI Search / Azure Cognitive Search" \
      "milvus|Milvus" \
      "zilliz|Zilliz Cloud" \
      "vertex_vector_search|Vertex AI Vector Search" \
      "aws_bedrock_kb|AWS Bedrock Knowledge Bases"
    retriever_plugin="$(k8s_retriever_plugin "$VECTOR_DB_PROVIDER")"
  else
    EMBEDDING_PROVIDER="none"
    VECTOR_DB_PROVIDER="none"
  fi

  choose_num K8S_INGRESS_CLASS "Which ingress controller class should the Ingress resources use?" "1" \
    "nginx|NGINX Ingress Controller" \
    "alb|AWS ALB (aws-load-balancer-controller)" \
    "none|No Ingress (use port-forward or your own routing)"
  local K8S_ORCH_HOST="" K8S_CONSOLE_HOST="" K8S_TLS="no" K8S_ORCH_TLS_SECRET="" K8S_CONSOLE_TLS_SECRET=""
  if [[ "$K8S_INGRESS_CLASS" != "none" ]]; then
    prompt K8S_ORCH_HOST "Hostname for the orchestrator Ingress" "orchestrator.example.com"
    if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
      prompt K8S_CONSOLE_HOST "Hostname for the Admin Console Ingress" "orchestrator-console.example.com"
    fi
    yes_no_num K8S_TLS "Enable TLS on the Ingress host(s)? Requires TLS Secret(s) to already exist in namespace ${K8S_NAMESPACE}." "no"
    if [[ "$K8S_TLS" == "yes" ]]; then
      prompt K8S_ORCH_TLS_SECRET "TLS Secret name for the orchestrator host" "orchestrator-tls"
      if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
        prompt K8S_CONSOLE_TLS_SECRET "TLS Secret name for the Admin Console host" "orchestrator-console-tls"
      fi
    fi
  fi

  prompt_positive_int K8S_REPLICAS "Orchestrator replica count" "2"
  yes_no_num K8S_HPA "Enable Horizontal Pod Autoscaling (HPA) for the orchestrator?" "no"
  local hpa_max="10"
  if [[ "$K8S_HPA" == "yes" ]]; then
    prompt_positive_int K8S_HPA_MAX "Maximum orchestrator replicas for HPA" "10"
    hpa_max="$K8S_HPA_MAX"
  fi

  choose_num K8S_RESOURCE_PRESET "Resource requests/limits preset for the orchestrator and console pods?" "2" \
    "small|Small  - requests 250m CPU / 512Mi, limits 1 CPU / 1Gi" \
    "medium|Medium - requests 500m CPU / 512Mi, limits 2 CPU / 2Gi (chart default)" \
    "large|Large  - requests 1 CPU / 1Gi, limits 4 CPU / 4Gi"
  local res_cpu_req res_mem_req res_cpu_lim res_mem_lim
  case "$K8S_RESOURCE_PRESET" in
    small) res_cpu_req="250m";  res_mem_req="512Mi"; res_cpu_lim="1000m"; res_mem_lim="1Gi" ;;
    large) res_cpu_req="1000m"; res_mem_req="1Gi";   res_cpu_lim="4000m"; res_mem_lim="4Gi" ;;
    *)     res_cpu_req="500m";  res_mem_req="512Mi"; res_cpu_lim="2000m"; res_mem_lim="2Gi" ;;
  esac
  local resources_block
  resources_block=$(cat <<EOM
  resources:
    requests:
      cpu: "${res_cpu_req}"
      memory: "${res_mem_req}"
    limits:
      cpu: "${res_cpu_lim}"
      memory: "${res_mem_lim}"
EOM
)

  # ----- assemble values.yaml blocks -----
  local orch_config
  orch_config=$(cat <<EOM
  config:
    logLevel: "INFO"
    storageType: "postgres"
    modelPluginEntryPoint: "${model_plugin}"
    secondaryModelPluginEntryPoint: "${model_plugin}"
EOM
)
  if [[ "$ENABLE_RAG" == "yes" ]]; then
    orch_config="${orch_config}
    embeddingsPluginEntryPoint: \"${embeddings_plugin}\"
    retrieverPluginEntryPoint: \"${retriever_plugin}\""
  fi

  local autoscaling_block
  if [[ "$K8S_HPA" == "yes" ]]; then
    autoscaling_block=$(cat <<EOM
  autoscaling:
    enabled: true
    minReplicas: ${K8S_REPLICAS}
    maxReplicas: ${hpa_max}
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 75
EOM
)
  else
    autoscaling_block=$(cat <<'EOM'
  autoscaling:
    enabled: false
EOM
)
  fi

  local orch_tls_yaml="    tls: []"
  local console_tls_yaml="    tls: []"
  if [[ "$K8S_TLS" == "yes" ]]; then
    orch_tls_yaml=$(cat <<EOM
    tls:
      - hosts:
          - "${K8S_ORCH_HOST}"
        secretName: "${K8S_ORCH_TLS_SECRET}"
EOM
)
    console_tls_yaml=$(cat <<EOM
    tls:
      - hosts:
          - "${K8S_CONSOLE_HOST}"
        secretName: "${K8S_CONSOLE_TLS_SECRET}"
EOM
)
  fi

  local orch_ingress_block
  if [[ "$K8S_INGRESS_CLASS" == "none" ]]; then
    orch_ingress_block=$(cat <<'EOM'
  ingress:
    enabled: false
EOM
)
  else
    orch_ingress_block=$(cat <<EOM
  ingress:
    enabled: true
    className: "${K8S_INGRESS_CLASS}"
    annotations: {}
    hosts:
      - host: "${K8S_ORCH_HOST}"
        paths:
          - path: /
            pathType: Prefix
${orch_tls_yaml}
EOM
)
  fi

  local console_block
  if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
    local console_ingress
    if [[ "$K8S_INGRESS_CLASS" == "none" ]]; then
      console_ingress=$(cat <<'EOM'
  ingress:
    enabled: false
EOM
)
    else
      console_ingress=$(cat <<EOM
  ingress:
    enabled: true
    className: "${K8S_INGRESS_CLASS}"
    annotations: {}
    hosts:
      - host: "${K8S_CONSOLE_HOST}"
        paths:
          - path: /
            pathType: Prefix
${console_tls_yaml}
EOM
)
    fi
    console_block=$(cat <<EOM
orchestratorConsole:
  enabled: true
  replicaCount: 2
  imagePullSecrets:
    - name: "${K8S_PULL_SECRET}"
${resources_block}
  config:
    logLevel: "INFO"
    orchestratorInternalUrl: "http://orchestrator:80"
  secret:
    create: false
    existingSecretName: "orchestrator"
${console_ingress}
EOM
)
  else
    console_block=$(cat <<'EOM'
orchestratorConsole:
  enabled: false
EOM
)
  fi

  local pg_block
  if [[ "$K8S_BUNDLED_DB" == "yes" ]]; then
    local sc_line='storageClass: ""'
    [[ -n "$K8S_PG_STORAGE_CLASS" ]] && sc_line="storageClass: \"${K8S_PG_STORAGE_CLASS}\""
    pg_block=$(cat <<EOM
postgresql:
  enabled: true
  postgres:
    database: orchestrator
    username: orchestrator
  persistence:
    enabled: true
    size: ${K8S_PG_SIZE}
    ${sc_line}
EOM
)
  else
    pg_block=$(cat <<'EOM'
postgresql:
  enabled: false
EOM
)
  fi

  local values_content
  values_content=$(cat <<EOM
# ============================================================
# Spotfire Copilot - Kubernetes (Helm) values
# Chart: orchestrator-stack ${K8S_CHART_VERSION}
# Release name: orchestrator   Namespace: ${K8S_NAMESPACE}
# Generated by spotfire-copilot-deploy.sh
#
# Non-secret configuration only. Secrets live in secrets.values.yaml, which
# helm-install.sh passes AFTER this file so it overrides secret fields.
# ============================================================

# Single source of truth for the orchestrator + console image (both share it).
global:
  orchestratorImage:
    repository: "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator"
    tag: "${IMAGE_TAG}"

orchestrator:
  replicaCount: ${K8S_REPLICAS}
  imagePullSecrets:
    - name: "${K8S_PULL_SECRET}"
${resources_block}
${orch_config}
${autoscaling_block}
${orch_ingress_block}

${console_block}

${pg_block}
EOM
)

  # ----- assemble secrets.values.yaml blocks -----
  local secret_db_lines
  if [[ "$K8S_BUNDLED_DB" == "yes" ]]; then
    secret_db_lines=$(cat <<EOM
    # Bundled in-cluster PostgreSQL (postgresql.enabled=true). Password auto-generated.
    databaseUrl: "${db_url}"
    syncDatabaseUrl: "${sync_db_url}"
EOM
)
  else
    secret_db_lines=$(cat <<'EOM'
    # External / managed PostgreSQL - FILL THESE IN before installing.
    # Async (asyncpg):  postgresql+asyncpg://USER:PASSWORD@HOST:5432/DBNAME
    # Sync  (psycopg2): postgresql://USER:PASSWORD@HOST:5432/DBNAME
    databaseUrl: ""
    syncDatabaseUrl: ""
EOM
)
  fi

  local provider_secret_lines
  case "$LLM_PROVIDER" in
    openai)
      provider_secret_lines='    openaiApiKey: ""' ;;
    azure_openai)
      provider_secret_lines=$(cat <<'EOM'
    azureOpenaiApiKey: ""
    azureApiBase: ""
    azureApiVersion: ""
EOM
) ;;
    gemini)
      provider_secret_lines='    googleApiKey: ""' ;;
    aws_bedrock)
      provider_secret_lines=$(cat <<'EOM'
    # Omit these if the pods use IRSA / instance roles instead of static keys.
    awsAccessKeyId: ""
    awsSecretAccessKey: ""
    awsRegionName: ""
EOM
) ;;
    vertex_ai)
      provider_secret_lines='    # Vertex AI uses a GCP service-account JSON via the chart gcpCredentials.* block, not an API key.' ;;
    nvidia_nim|ollama)
      provider_secret_lines='    # No first-party API key required by default; use extraSecretEnv for custom endpoints/keys.' ;;
    *)
      provider_secret_lines='    # Add provider credentials here or via extraSecretEnv.' ;;
  esac

  local rag_secret_lines=""
  if [[ "$ENABLE_RAG" == "yes" && "$VECTOR_DB_PROVIDER" == "azure_ai_search" ]]; then
    rag_secret_lines='    azureCognitiveSearchApiKey: ""'
  fi

  local pg_secret_block=""
  if [[ "$K8S_BUNDLED_DB" == "yes" ]]; then
    pg_secret_block=$(cat <<EOM

postgresql:
  postgres:
    password: "${pg_password}"
EOM
)
  fi

  local secrets_content
  secrets_content=$(cat <<EOM
# ============================================================
# Spotfire Copilot - Kubernetes (Helm) SECRET values
# Chart: orchestrator-stack ${K8S_CHART_VERSION}
#
# SENSITIVE - do NOT commit to version control.
# helm-install.sh passes this file with -f AFTER values.yaml.
# The Admin Console reuses this Secret via existingSecretName: orchestrator.
# ============================================================

orchestrator:
  secret:
    create: true
    # Auto-filled by generate_credentials.py (also saved to copilot-generated-values.txt).
    secretKey: '${K8S_SECRET_KEY}'
    hashedAdminPassword: '${K8S_HASHED_ADMIN_PW}'
    oauth2ClientId: '${K8S_OAUTH_ID}'
    oauth2ClientSecretHash: '${K8S_OAUTH_HASH}'
${secret_db_lines}
    # Provider credentials (${LLM_PROVIDER}):
${provider_secret_lines}
${rag_secret_lines}
${pg_secret_block}
EOM
)

  # ----- helm-install.sh wrapper -----
  local install_script
  install_script=$(cat <<EOM
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Spotfire Copilot - orchestrator-stack Helm installer
# Generated by spotfire-copilot-deploy.sh
# ============================================================

NAMESPACE="${K8S_NAMESPACE}"
RELEASE="orchestrator"
CHART="oci://copilotoci.azurecr.io/spotfirecopilot/orchestrator-stack"
CHART_VERSION="${K8S_CHART_VERSION}"
REGISTRY="copilotoci.azurecr.io"
PULL_SECRET="${K8S_PULL_SECRET}"

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
VALUES="\$SCRIPT_DIR/values.yaml"
SECRETS="\$SCRIPT_DIR/secrets.values.yaml"

command -v helm >/dev/null 2>&1 || { echo "ERROR: helm not found on PATH."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found on PATH."; exit 1; }

echo "==> Logging in to \$REGISTRY (Helm OCI registry)"
if command -v az >/dev/null 2>&1; then
  az acr login --name "\${REGISTRY%%.*}" || {
    echo "az acr login failed; falling back to 'helm registry login'."
    helm registry login "\$REGISTRY"
  }
else
  echo "Azure CLI not found; using 'helm registry login' (you will be prompted for registry credentials)."
  helm registry login "\$REGISTRY"
fi

echo "==> Ensuring namespace \$NAMESPACE exists"
kubectl create namespace "\$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

if ! kubectl -n "\$NAMESPACE" get secret "\$PULL_SECRET" >/dev/null 2>&1; then
  echo "NOTE: image pull secret '\$PULL_SECRET' not found in namespace \$NAMESPACE."
  echo "The pods reference it to pull from \$REGISTRY. Create it with your registry credentials, e.g.:"
  echo "  kubectl -n \$NAMESPACE create secret docker-registry \$PULL_SECRET --docker-server=\$REGISTRY --docker-username=<user> --docker-password=<password>"
fi

echo "==> helm upgrade --install \$RELEASE (chart \$CHART_VERSION) into namespace \$NAMESPACE"
helm upgrade --install "\$RELEASE" "\$CHART" --version "\$CHART_VERSION" --namespace "\$NAMESPACE" --create-namespace -f "\$VALUES" -f "\$SECRETS"

echo "==> Done. Check the rollout with:"
echo "   kubectl -n \$NAMESPACE get pods"
EOM
)

  mkdir -p "$k8s_dir"
  write_file "$k8s_dir/values.yaml" "$values_content"
  write_file "$k8s_dir/secrets.values.yaml" "$secrets_content"
  write_file "$k8s_dir/helm-install.sh" "$install_script"
  chmod 700 "$k8s_dir/helm-install.sh"

  ok "Kubernetes Helm bundle generated under: $k8s_dir"
  echo "  values.yaml                    - non-secret Helm values"
  echo "  secrets.values.yaml            - SECRET values, credentials pre-filled (do not commit)"
  echo "  copilot-generated-values.txt   - raw generate_credentials.py output (do not commit)"
  echo "  helm-install.sh                - installs orchestrator-stack ${K8S_CHART_VERSION} into namespace ${K8S_NAMESPACE}"
  echo
  info "Next steps:"
  info "1. Credentials were generated and written into secrets.values.yaml (also saved to ${k8s_dir}/copilot-generated-values.txt). Store the plaintext admin password / OAuth client secret shown above in a secure vault."
  if [[ "$K8S_BUNDLED_DB" != "yes" ]]; then
    info "2. Fill in databaseUrl and syncDatabaseUrl (external PostgreSQL) in secrets.values.yaml."
  fi
  info "3. Ensure the '${K8S_PULL_SECRET}' image pull secret exists in namespace ${K8S_NAMESPACE} (helm-install.sh prints the command if it is missing)."
  info "4. From a machine with helm + kubectl access to the cluster, run: ${k8s_dir}/helm-install.sh"
  warn "secrets.values.yaml contains sensitive data. Keep it out of version control."
}

# ---------- main ----------
parse_args "$@"
if [[ "$FORCE_COLOR" == "no" ]]; then C_RESET=""; C_BOLD=""; C_INFO=""; C_WARN=""; C_ERR=""; C_OK=""; C_STEP=""; C_DIM=""; fi
if [[ "$MODE" == "help" ]]; then print_help; exit 0; fi
require_cmd grep; require_cmd sed; require_cmd openssl
if [[ "$MODE" == "info" ]]; then set_default_dir_for_info; fi
if [[ "$MODE" == "upgrade" ]]; then run_upgrade; exit 0; fi
if [[ "$MODE" == "agent_registry_only" ]]; then run_agent_registry_only; exit 0; fi
# With an explicit --dir/OUT_DIR the target is known now. For interactive generation the
# backend directory is finalized later from the image tag (finalize_out_dir_for_tag), so
# it is not created here.
if [[ "$OUT_DIR_EXPLICIT" == "yes" || "$MODE" == "info" ]]; then
  mkdir -p "$OUT_DIR"; cd "$OUT_DIR"; OUT_DIR="$(pwd)"
fi
DEFAULT_CREDENTIALS_FILE="$(detect_default_credentials_file)"
EXISTING_FILES=("$OUT_DIR/.env" "$OUT_DIR/.env.orchestrator" "$OUT_DIR/.env.dataloader" "$OUT_DIR/.env.agent-registry")
if [[ "$MODE" == "info" ]]; then show_info; exit 0; fi

echo "${C_STEP}================================================================${C_RESET}"
echo "${C_STEP}Spotfire Copilot 2.3.x Environment File Generator - ${C_RESET}"
if [[ "$OUT_DIR_EXPLICIT" == "yes" ]]; then
  echo "${C_STEP}Output directory: $OUT_DIR${C_RESET}"
else
  echo "${C_STEP}Output directory: set from the image tag you enter below${C_RESET}"
fi
echo "${C_STEP}================================================================${C_RESET}"

section "Deployment target"
choose_num DEPLOYMENT_TARGET "Where are you deploying Spotfire Copilot?" "1" \
  "linux_vm|Linux VM / Docker Compose" \
  "azure_container_apps|Azure Container Apps" \
  "aws_ecs_fargate|AWS ECS / Fargate" \
  "gcp_cloud_run|GCP Cloud Run" \
  "kubernetes|Kubernetes (AKS / EKS / GKE)" \
  "other_cloud|Other cloud / customer-managed container platform"

if [[ "$DEPLOYMENT_TARGET" != "linux_vm" ]]; then
  if [[ "$OUT_DIR_EXPLICIT" == "no" ]]; then mkdir -p "$OUT_DIR"; cd "$OUT_DIR"; OUT_DIR="$(pwd)"; fi
  if [[ "$DEPLOYMENT_TARGET" == "kubernetes" ]]; then
    run_kubernetes_mode
  else
    run_cloud_master_env_mode
  fi
  remember_out_dir
  exit 0
fi

section "Required core setup"
info "Core setup creates the Orchestrator configuration needed for authentication, PostgreSQL persistence, and LLM calls."

IMAGE_TAG_DEFAULT="$(get_existing IMAGE_TAG "${EXISTING_FILES[@]}" || true)"; IMAGE_TAG_DEFAULT="${IMAGE_TAG_DEFAULT:-$DEFAULT_IMAGE_TAG}"
prompt_image_tag IMAGE_TAG "Copilot backend/data-loader image tag" "$IMAGE_TAG_DEFAULT" "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator"
FASTAPI_APP_VERSION="$IMAGE_TAG"
info "FASTAPI_APP_VERSION will be set automatically to ${FASTAPI_APP_VERSION}."
finalize_out_dir_for_tag "$IMAGE_TAG"
COMPOSE_PROJECT_DEFAULT="$(get_existing COMPOSE_PROJECT_NAME "${EXISTING_FILES[@]}" || true)"; COMPOSE_PROJECT_DEFAULT="${COMPOSE_PROJECT_DEFAULT:-spotfire-copilot}"
LOG_LEVEL_DEFAULT="$(get_existing LOG_LEVEL "${EXISTING_FILES[@]}" || true)"; LOG_LEVEL_DEFAULT="${LOG_LEVEL_DEFAULT:-INFO}"
ACCESS_DAYS_DEFAULT="$(get_existing ACCESS_TOKEN_EXPIRE_DAYS "${EXISTING_FILES[@]}" || true)"; ACCESS_DAYS_DEFAULT="${ACCESS_DAYS_DEFAULT:-30}"
prompt_compose_project_name COMPOSE_PROJECT_NAME "Docker Compose project name" "$COMPOSE_PROJECT_DEFAULT"
prompt_log_level LOG_LEVEL "LOG_LEVEL" "$LOG_LEVEL_DEFAULT"
prompt_positive_int ACCESS_TOKEN_EXPIRE_DAYS "ACCESS_TOKEN_EXPIRE_DAYS" "$ACCESS_DAYS_DEFAULT"

section "Credentials"
info "Credentials are required, but generating them is optional if you already have valid values."
info "Credential search order: current working directory, script directory, then selected backend folder."
info "Expected keys: SECRET_KEY, HASHED_ADMIN_PASSWORD, OAUTH2_CLIENT_ID, OAUTH2_CLIENT_SECRET_HASH."
info "Answering No runs generate_credentials.py (the official generator shipped with the Copilot backend package). Place it next to this installer: $SCRIPT_DIR/generate_credentials.py"
yes_no_num HAVE_GENERATED_CREDS "Have you already generated Spotfire Copilot credentials?" "yes"
if [[ "$HAVE_GENERATED_CREDS" == "yes" ]]; then
  prompt CREDENTIALS_FILE "Please provide path to existing copilot-generated-values.txt. If missing, I can pick up from existing env values or you could enter them manually" "$DEFAULT_CREDENTIALS_FILE"
  CREDENTIALS_FILE="$(normalize_credentials_path "$CREDENTIALS_FILE")"
  if [[ -f "$CREDENTIALS_FILE" ]]; then
    info "Using credential file: $CREDENTIALS_FILE"
  else
    warn "Credential file not found at $CREDENTIALS_FILE. The script will try existing .env files first, then prompt for missing values."
  fi
else
  CREDENTIALS_FILE="$OUT_DIR/copilot-generated-values.txt"
  info "No existing credentials selected. Credentials will be generated automatically at: $CREDENTIALS_FILE"
  warn_admin_password_regeneration_existing_state
  if [[ -f "$CREDENTIALS_FILE" ]]; then
    yes_no_num REGENERATE_CREDS "Credential file already exists in the backend folder. Regenerate and overwrite it?" "no"
    if [[ "$REGENERATE_CREDS" == "yes" ]]; then
      backup_file "$CREDENTIALS_FILE"
      ensure_linux_prereqs
      generate_credentials_file "$CREDENTIALS_FILE"
    else
      info "Using existing credential file: $CREDENTIALS_FILE"
    fi
  else
    ensure_linux_prereqs
    generate_credentials_file "$CREDENTIALS_FILE"
  fi
fi
SECRET_KEY_FILE="$(get_from_credentials_file SECRET_KEY "$CREDENTIALS_FILE" || true)"
HASHED_ADMIN_FILE="$(get_from_credentials_file HASHED_ADMIN_PASSWORD "$CREDENTIALS_FILE" || true)"
OAUTH_CLIENT_ID_FILE="$(get_from_credentials_file OAUTH2_CLIENT_ID "$CREDENTIALS_FILE" || true)"
OAUTH_CLIENT_SECRET_HASH_FILE="$(get_from_credentials_file OAUTH2_CLIENT_SECRET_HASH "$CREDENTIALS_FILE" || true)"
if [[ -f "$CREDENTIALS_FILE" ]]; then
  info "Credential file selected: $CREDENTIALS_FILE"
  copy_credentials_to_out_dir "$CREDENTIALS_FILE"
else
  warn "No credential file selected; falling back to existing env files or manual prompts."
fi
SECRET_KEY_FILE="$(get_from_credentials_file SECRET_KEY "$CREDENTIALS_FILE" || true)"
HASHED_ADMIN_FILE="$(get_from_credentials_file HASHED_ADMIN_PASSWORD "$CREDENTIALS_FILE" || true)"
OAUTH_CLIENT_ID_FILE="$(get_from_credentials_file OAUTH2_CLIENT_ID "$CREDENTIALS_FILE" || true)"
OAUTH_CLIENT_SECRET_HASH_FILE="$(get_from_credentials_file OAUTH2_CLIENT_SECRET_HASH "$CREDENTIALS_FILE" || true)"
LOADED_COUNT=0; [[ -n "$SECRET_KEY_FILE" ]] && LOADED_COUNT=$((LOADED_COUNT+1)); [[ -n "$HASHED_ADMIN_FILE" ]] && LOADED_COUNT=$((LOADED_COUNT+1)); [[ -n "$OAUTH_CLIENT_ID_FILE" ]] && LOADED_COUNT=$((LOADED_COUNT+1)); [[ -n "$OAUTH_CLIENT_SECRET_HASH_FILE" ]] && LOADED_COUNT=$((LOADED_COUNT+1))
USE_LOADED_CREDS="no"
if (( LOADED_COUNT == 4 )); then
  ok "Loaded SECRET_KEY from credential file."
  ok "Loaded HASHED_ADMIN_PASSWORD from credential file."
  ok "Loaded OAUTH2_CLIENT_ID from credential file: $(mask "$OAUTH_CLIENT_ID_FILE")"
  ok "Loaded OAUTH2_CLIENT_SECRET_HASH from credential file."
  yes_no_num USE_LOADED_CREDS "Use credentials loaded from copilot-generated-values.txt without re-prompting?" "yes"
else
  warn "Loaded ${LOADED_COUNT}/4 credential values from the credential file. Missing values will be requested."
fi
if [[ "$USE_LOADED_CREDS" == "yes" ]]; then
  SECRET_KEY="$SECRET_KEY_FILE"; HASHED_ADMIN_PASSWORD="$HASHED_ADMIN_FILE"; OAUTH2_CLIENT_ID="$OAUTH_CLIENT_ID_FILE"; OAUTH2_CLIENT_SECRET_HASH="$OAUTH_CLIENT_SECRET_HASH_FILE"
else
  SECRET_KEY_DEFAULT="${SECRET_KEY_FILE:-$(get_existing SECRET_KEY "${EXISTING_FILES[@]}" || true)}"; SECRET_KEY_DEFAULT="${SECRET_KEY_DEFAULT:-$(random_hex_32)}"
  HASHED_ADMIN_DEFAULT="${HASHED_ADMIN_FILE:-$(get_existing HASHED_ADMIN_PASSWORD "${EXISTING_FILES[@]}" || true)}"
  OAUTH_CLIENT_ID_DEFAULT="${OAUTH_CLIENT_ID_FILE:-$(get_existing OAUTH2_CLIENT_ID "${EXISTING_FILES[@]}" || true)}"
  OAUTH_CLIENT_SECRET_HASH_DEFAULT="${OAUTH_CLIENT_SECRET_HASH_FILE:-$(get_existing OAUTH2_CLIENT_SECRET_HASH "${EXISTING_FILES[@]}" || true)}"
  info "Review/edit each credential value. Press Enter to keep the loaded/default value."
  prompt SECRET_KEY "SECRET_KEY" "$SECRET_KEY_DEFAULT" true
  prompt HASHED_ADMIN_PASSWORD "HASHED_ADMIN_PASSWORD bcrypt hash" "$HASHED_ADMIN_DEFAULT" true
  prompt OAUTH2_CLIENT_ID "OAUTH2_CLIENT_ID" "$OAUTH_CLIENT_ID_DEFAULT"
  prompt OAUTH2_CLIENT_SECRET_HASH "OAUTH2_CLIENT_SECRET_HASH bcrypt hash" "$OAUTH_CLIENT_SECRET_HASH_DEFAULT" true
fi
# No placeholder fallback: credentials must be real. If any value is still missing at
# this point, stop rather than writing an .env that cannot work.
CRED_MISSING=""
[[ -n "${SECRET_KEY:-}" ]] || CRED_MISSING="${CRED_MISSING}${CRED_MISSING:+, }SECRET_KEY"
[[ -n "${HASHED_ADMIN_PASSWORD:-}" ]] || CRED_MISSING="${CRED_MISSING}${CRED_MISSING:+, }HASHED_ADMIN_PASSWORD"
[[ -n "${OAUTH2_CLIENT_ID:-}" ]] || CRED_MISSING="${CRED_MISSING}${CRED_MISSING:+, }OAUTH2_CLIENT_ID"
[[ -n "${OAUTH2_CLIENT_SECRET_HASH:-}" ]] || CRED_MISSING="${CRED_MISSING}${CRED_MISSING:+, }OAUTH2_CLIENT_SECRET_HASH"
[[ -z "$CRED_MISSING" ]] || die "Missing required credential values: ${CRED_MISSING}. Run generate_credentials.py (place it next to this installer and choose 'No' at the credentials question), or provide a copilot-generated-values.txt that contains all four values."

section "Required backend database for Orchestrator"
info "PostgreSQL is required because Orchestrator stores backend state such as users, OAuth clients, conversations, threads, agents, and token-related data."
choose_num POSTGRES_MODE "Where should Orchestrator store its PostgreSQL data?" "1" \
  "existing|Use existing PostgreSQL / managed PostgreSQL" \
  "compose|Create PostgreSQL using this Docker Compose deployment"
if [[ "$POSTGRES_MODE" == "existing" ]]; then
  prompt POSTGRES_HOST "PostgreSQL host" "$(get_existing POSTGRES_HOST "${EXISTING_FILES[@]}" || echo postgres.example.com)"
  prompt POSTGRES_PORT "PostgreSQL port" "$(get_existing POSTGRES_PORT "${EXISTING_FILES[@]}" || echo 5432)"
  prompt_pg_identifier POSTGRES_DB "PostgreSQL database name" "$(get_existing POSTGRES_DB "${EXISTING_FILES[@]}" || true)" "orchestrator"
  prompt_pg_identifier POSTGRES_USER "PostgreSQL username" "$(get_existing POSTGRES_USER "${EXISTING_FILES[@]}" || true)" "orchestrator"
  prompt POSTGRES_PASSWORD "PostgreSQL password" "" true
  DB_SSLMODE_DEFAULT="$(get_existing DB_SSLMODE "${EXISTING_FILES[@]}" || echo require)"
  case "$(printf '%s' "$DB_SSLMODE_DEFAULT" | tr '[:upper:]' '[:lower:]')" in
    disable|disabled|false|off|none|no) DB_SSLMODE_DEFNUM=1 ;;
    allow)                              DB_SSLMODE_DEFNUM=2 ;;
    prefer)                             DB_SSLMODE_DEFNUM=3 ;;
    verify-ca)                          DB_SSLMODE_DEFNUM=5 ;;
    verify-full)                        DB_SSLMODE_DEFNUM=6 ;;
    *)                                  DB_SSLMODE_DEFNUM=4 ;;
  esac
  info "If your PostgreSQL server does NOT have SSL/TLS enabled (no certificate), choose 'disable'. Managed/cloud PostgreSQL usually needs 'require' or stricter."
  choose_num DB_SSLMODE "PostgreSQL SSL mode (DB_SSLMODE)" "$DB_SSLMODE_DEFNUM" \
    "disable|disable - no SSL (use this if the server has no SSL certificate)" \
    "allow|allow - try non-SSL first, then SSL" \
    "prefer|prefer - try SSL first, fall back to non-SSL" \
    "require|require - SSL required, without certificate verification" \
    "verify-ca|verify-ca - SSL required, verify the server certificate CA" \
    "verify-full|verify-full - SSL required, verify CA and hostname"
  if [[ -z "$POSTGRES_PASSWORD" ]]; then
    EXISTING_DATABASE_URL="$(get_existing DATABASE_URL "${EXISTING_FILES[@]}" || true)"; EXISTING_SYNC_DATABASE_URL="$(get_existing SYNC_DATABASE_URL "${EXISTING_FILES[@]}" || true)"
    if [[ -n "$EXISTING_DATABASE_URL" && -n "$EXISTING_SYNC_DATABASE_URL" ]]; then DATABASE_URL="$EXISTING_DATABASE_URL"; SYNC_DATABASE_URL="$EXISTING_SYNC_DATABASE_URL"; warn "PostgreSQL password blank. Reusing existing DATABASE_URL and SYNC_DATABASE_URL."; else POSTGRES_PASSWORD="REPLACE_WITH_POSTGRES_PASSWORD"; build_database_urls; fi
  else
    build_database_urls
  fi
else
  POSTGRES_HOST="orchestrator-postgres"; POSTGRES_PORT="5432"; DB_SSLMODE="disable"
  prompt POSTGRES_HOST_PORT "Bundled PostgreSQL host port (published on 127.0.0.1; container port stays 5432)" "5432"
  prompt_pg_identifier POSTGRES_DB "Compose PostgreSQL database name" "$(get_existing POSTGRES_DB "${EXISTING_FILES[@]}" || true)" "orchestrator"
  prompt_pg_identifier POSTGRES_USER "Compose PostgreSQL username" "$(get_existing POSTGRES_USER "${EXISTING_FILES[@]}" || true)" "orchestrator"
  DEFAULT_COMPOSE_PG_PASS="$(get_existing POSTGRES_PASSWORD "${EXISTING_FILES[@]}" || true)"

  if existing_compose_postgres_volume_detected; then
    warn "Existing Docker Compose PostgreSQL volume detected. POSTGRES_PASSWORD initializes the database only when the data directory is empty; changing the env file later does not change the password stored inside the existing database volume."
    choose_num COMPOSE_PG_VOLUME_ACTION "How should the installer handle the existing local PostgreSQL volume?" "1"       "reuse|Reuse existing local PostgreSQL data; I will enter/reuse the ORIGINAL database password"       "reset|Fresh lab/test install; generate env with a new password and create a reset helper to delete the local PostgreSQL volume"
    if [[ "$COMPOSE_PG_VOLUME_ACTION" == "reuse" ]]; then
      prompt POSTGRES_PASSWORD "Existing Compose PostgreSQL password used when the volume was first initialized" "$DEFAULT_COMPOSE_PG_PASS" true
      if [[ -z "$POSTGRES_PASSWORD" ]]; then
        die "Existing local PostgreSQL volume selected, but no password was provided. Enter the original database password or choose the reset option for a disposable lab install."
      fi
    else
      POSTGRES_RESET_LOCAL_VOLUME_SELECTED="yes"
      DEFAULT_COMPOSE_PG_PASS="Copilot_Postgres_$(openssl rand -hex 8)"
      info "A strong PostgreSQL password was auto-generated for the reinitialized volume."
      prompt POSTGRES_PASSWORD "New Compose PostgreSQL password for reinitialized local volume" "$DEFAULT_COMPOSE_PG_PASS" true "press Enter to accept the generated password"
      write_reset_compose_postgres_helper
      warn "You selected a fresh lab/test reset. The installer will offer to run the targeted reset ($OUT_DIR/reset-local-postgres-volume.sh) after the files are generated. If you skip it, run that helper before starting/restarting the stack."
    fi
  else
    if [[ -n "$DEFAULT_COMPOSE_PG_PASS" ]]; then
      # A saved POSTGRES_PASSWORD was found in an existing env file (re-run without a volume).
      prompt POSTGRES_PASSWORD "Compose PostgreSQL password" "$DEFAULT_COMPOSE_PG_PASS" true
    else
      # Fresh install: nothing was saved, so generate a strong password as the default.
      DEFAULT_COMPOSE_PG_PASS="Copilot_Postgres_$(openssl rand -hex 8)"
      info "A strong PostgreSQL password was auto-generated for this fresh install."
      prompt POSTGRES_PASSWORD "Compose PostgreSQL password" "$DEFAULT_COMPOSE_PG_PASS" true "press Enter to accept the generated password"
    fi
  fi
  build_database_urls
fi

configure_llm_provider

section "Orchestrator host port"
info "The Orchestrator API is published on this host port. The container port stays 8080; change the host port only if 8080 is already in use on this host."
prompt ORCH_HOST_PORT "Orchestrator host port" "8080"

section "Optional Admin Console"
info "Admin Console is optional and uses the same PostgreSQL database already configured for Orchestrator."
yes_no_num ENABLE_ADMIN_CONSOLE "Deploy Admin Console?" "yes"
if [[ "$ENABLE_ADMIN_CONSOLE" == "no" ]]; then
  warn "Skipping Admin Console: manage OAuth clients, users, diagnostics, conversations, RAG indexes, and agents through REST API instead of the web UI."
else
  prompt ADMIN_HOST_PORT "Admin Console host port (container port stays 8081)" "8081"
fi

section "Optional RAG / Knowledge Base"
info "RAG is required for Help, HowTo, Spotfire documentation answers, and custom document Q&A."
yes_no_num ENABLE_RAG "Enable RAG / Knowledge Base?" "no"
ENABLE_DATA_LOADER="no"
DOCS_DIR="$(get_existing DOCS_DIR "${EXISTING_FILES[@]}" || echo /root/spotfire-copilot/pdf_docs_folder)"
if [[ "$ENABLE_RAG" == "no" ]]; then
  warn "Skipping RAG: Orchestrator and LLM smoke tests can work, but Help, HowTo, docs answers, and custom document Q&A will not work."
  EMBED_BLOCK_ORCH="# OPTIONAL: RAG disabled by installer choice; configure an embeddings plugin when enabling RAG."
  EMBED_BLOCK_DL="# OPTIONAL: Data Loader disabled because RAG was not enabled."
  VECTOR_BLOCK_ORCH="# OPTIONAL: RAG disabled by installer choice; configure a retriever plugin/vector DB for Help, HowTo, and document Q&A."
  VECTOR_BLOCK_DL="# OPTIONAL: Data Loader disabled because RAG was not enabled."
  DEFAULT_HOWTO_INDEX="spotfiredocs"; DEFAULT_RAG_TOPK="10"; DEFAULT_RAG_SCORE_THRESHOLD="0.5"
else
  configure_embeddings
  configure_vector_db
  DEFAULT_HOWTO_INDEX="$(get_existing DEFAULT_HOWTO_INDEX "${EXISTING_FILES[@]}" || true)"; DEFAULT_HOWTO_INDEX="${DEFAULT_HOWTO_INDEX:-spotfiredocs}"
  DEFAULT_RAG_TOPK="$(get_existing DEFAULT_RAG_TOPK "${EXISTING_FILES[@]}" || true)"; DEFAULT_RAG_TOPK="${DEFAULT_RAG_TOPK:-10}"
  DEFAULT_RAG_SCORE_THRESHOLD="$(get_existing DEFAULT_RAG_SCORE_THRESHOLD "${EXISTING_FILES[@]}" || true)"; DEFAULT_RAG_SCORE_THRESHOLD="${DEFAULT_RAG_SCORE_THRESHOLD:-0.5}"
  prompt DEFAULT_HOWTO_INDEX "Default Spotfire docs / HowTo index name" "$DEFAULT_HOWTO_INDEX"
  prompt DEFAULT_RAG_TOPK "DEFAULT_RAG_TOPK" "$DEFAULT_RAG_TOPK"
  prompt DEFAULT_RAG_SCORE_THRESHOLD "DEFAULT_RAG_SCORE_THRESHOLD" "$DEFAULT_RAG_SCORE_THRESHOLD"
  RAG_DEFAULTS_BLOCK=$(cat <<EOM
# RECOMMENDED: Default Spotfire docs / HowTo index name.
DEFAULT_HOWTO_INDEX=${DEFAULT_HOWTO_INDEX}
# OPTIONAL: Number of RAG chunks to retrieve.
DEFAULT_RAG_TOPK=${DEFAULT_RAG_TOPK}
# OPTIONAL: Minimum RAG relevance score threshold.
DEFAULT_RAG_SCORE_THRESHOLD=${DEFAULT_RAG_SCORE_THRESHOLD}
# RECOMMENDED: Default RAG retriever type.
DEFAULT_RAG_RETRIEVER_TYPE=vector-store
EOM
)
  section "Optional Data Loader"
  if [[ "$VECTOR_WRITABLE" == "yes" ]]; then
    info "Data Loader ingests Spotfire docs and custom PDFs into a writable vector database."
    yes_no_num ENABLE_DATA_LOADER "Deploy Data Loader?" "yes"
    if [[ "$ENABLE_DATA_LOADER" == "no" ]]; then
      warn "Skipping Data Loader: populate the knowledge base through native tools or an existing ingestion process."
    else
      prompt LOADER_HOST_PORT "Data Loader host port (container port stays 8080)" "8090"
      prompt DOCS_DIR "Host folder for the Data Loader's PDF documents (mounted to /docs in the container)" "$DOCS_DIR"
    fi
  else
    ENABLE_DATA_LOADER="no"
    warn "Skipping Data Loader: ${DATA_LOADER_NOTICE:-selected vector DB uses native/manual ingestion or no writer plugin was configured.}"
  fi
fi

section "Optional Agent Registry"
info "Agent Registry is only needed when Copilot should call custom or bundled A2A agents."
yes_no_num ENABLE_AGENT_REGISTRY "Enable Agent Registry?" "no"
AGENT_CONTAINER_TAG="$(get_existing AGENT_CONTAINER_TAG "${EXISTING_FILES[@]}" || true)"; AGENT_ENV_CONTENT=""
if [[ "$ENABLE_AGENT_REGISTRY" == "yes" ]]; then
  # ------------------------------------------------------------------
  # Agent Registry needs an Orchestrator OAuth client with the
  # agent_developer scope profile (ORCHESTRATOR_CLIENT_ID + SECRET).
  # That client can only be created against a RUNNING Orchestrator, which
  # does not exist yet during this initial generation. So the main flow
  # only ACCEPTS already-created credentials. Creating them live via the
  # Orchestrator REST API is handled by the dedicated flow:
  #   ./spotfire-copilot-deploy.sh --install-agent-registry --dir <backend>
  # If the credentials are not available, we defer and configure nothing
  # for Agent Registry in this run (no .env.agent-registry, no compose service).
  # ------------------------------------------------------------------
  ORCH_AGENT_CREDS_READY="no"
  ORCHESTRATOR_CLIENT_ID=""; ORCHESTRATOR_CLIENT_SECRET=""

  EXISTING_ORCH_AGENT_CLIENT_ID="$(get_existing ORCHESTRATOR_CLIENT_ID "$OUT_DIR/.env.agent-registry" || true)"
  EXISTING_ORCH_AGENT_CLIENT_SECRET="$(get_existing ORCHESTRATOR_CLIENT_SECRET "$OUT_DIR/.env.agent-registry" || true)"
  if [[ -n "$EXISTING_ORCH_AGENT_CLIENT_ID" && -n "$EXISTING_ORCH_AGENT_CLIENT_SECRET" \
        && "$EXISTING_ORCH_AGENT_CLIENT_ID" != REPLACE_WITH_* && "$EXISTING_ORCH_AGENT_CLIENT_SECRET" != REPLACE_WITH_* ]]; then
    yes_no_num USE_EXISTING_ORCH_AGENT_CLIENT "Existing Agent Registry Orchestrator OAuth client found in .env.agent-registry. Reuse it?" "yes"
    if [[ "$USE_EXISTING_ORCH_AGENT_CLIENT" == "yes" ]]; then
      ORCHESTRATOR_CLIENT_ID="$EXISTING_ORCH_AGENT_CLIENT_ID"
      ORCHESTRATOR_CLIENT_SECRET="$EXISTING_ORCH_AGENT_CLIENT_SECRET"
      ORCH_AGENT_CREDS_READY="yes"
    fi
  fi

  if [[ "$ORCH_AGENT_CREDS_READY" != "yes" ]]; then
    warn "Agent Registry needs its own orchestrator OAuth client with the agent_developer scope profile. Do not reuse the frontend/client OAuth credentials unless that client was explicitly created with agent_developer scopes."
    yes_no_num HAVE_ORCH_AGENT_CLIENT "Have you already created the Orchestrator OAuth client for Agent Registry with Scope Profile agent_developer (you have its client ID and secret)?" "no"
    if [[ "$HAVE_ORCH_AGENT_CLIENT" == "yes" ]]; then
      while true; do
        prompt ORCHESTRATOR_CLIENT_ID "ORCHESTRATOR_CLIENT_ID from that agent_developer OAuth client" ""
        ORCHESTRATOR_CLIENT_ID="$(strip_outer_quotes "$ORCHESTRATOR_CLIENT_ID")"
 [[ -n "$ORCHESTRATOR_CLIENT_ID" ]] && break
        warn "ORCHESTRATOR_CLIENT_ID cannot be blank when you choose Yes."
      done
      while true; do
        prompt ORCHESTRATOR_CLIENT_SECRET "ORCHESTRATOR_CLIENT_SECRET plaintext from that agent_developer OAuth client" "" true
        ORCHESTRATOR_CLIENT_SECRET="$(strip_outer_quotes "$ORCHESTRATOR_CLIENT_SECRET")"
 [[ -n "$ORCHESTRATOR_CLIENT_SECRET" ]] && break
        warn "ORCHESTRATOR_CLIENT_SECRET cannot be blank when you choose Yes."
      done
      ORCH_AGENT_CREDS_READY="yes"
    fi
  fi

  if [[ "$ORCH_AGENT_CREDS_READY" != "yes" ]]; then
    # Defer: the agent_developer client cannot be minted until the Orchestrator is up.
    ENABLE_AGENT_REGISTRY="no"
    warn "Agent Registry was NOT configured in this run: it requires an Orchestrator agent_developer OAuth client, and the Orchestrator is not running yet during initial setup."
    info "Add Agent Registry after the core stack is deployed and the Orchestrator is up:"
    info "  1) cd \"$OUT_DIR\""
    info "  2) docker compose up -d          # start the Orchestrator and core services"
    info "  3) create the agent_developer OAuth client (Admin Console, or let the installer create it in the next step)"
    info "  4) re-run: \"$0\" --install-agent-registry --dir \"$OUT_DIR\""
    info "Nothing for Agent Registry was written to the .env files or docker-compose.yml in this run."
  else
    warn "Agent Registry image tags can vary by entitlement/release. The installer will not default to 1.1.0; enter the exact agent-container tag provided/tested for your environment."
    AGENT_TAG_DEFAULT="$(get_existing AGENT_CONTAINER_TAG "${EXISTING_FILES[@]}" || true)"
    while true; do
      prompt_image_tag AGENT_CONTAINER_TAG "Agent container image tag (required; example: 1.1.0 or the tag confirmed by Spotfire Support)" "$AGENT_TAG_DEFAULT" "copilotoci.azurecr.io/spotfirecopilot/agent-container"
 [[ -n "$AGENT_CONTAINER_TAG" ]] && break
      warn "Agent container image tag is required when Agent Registry is enabled. Do not leave this blank."
    done
    prompt AGENT_PORT "Agent Registry PORT" "$(get_existing PORT "$OUT_DIR/.env.agent-registry" || echo 8050)"
    prompt AGENT_BASE_URL "Agent Registry BASE_URL" "$(get_existing BASE_URL "$OUT_DIR/.env.agent-registry" || echo http://agent-registry:8050)"
    prompt AUTH_CLIENT_ID "Agent Registry AUTH_CLIENT_ID" "$(get_existing AUTH_CLIENT_ID "$OUT_DIR/.env.agent-registry" || echo agent-registry-client)"

    EXISTING_AUTH_CLIENT_SECRET="$(get_existing AUTH_CLIENT_SECRET "$OUT_DIR/.env.agent-registry" || true)"
    if [[ -n "$EXISTING_AUTH_CLIENT_SECRET" ]]; then
      prompt AUTH_CLIENT_SECRET "Agent Registry AUTH_CLIENT_SECRET" "$EXISTING_AUTH_CLIENT_SECRET" true
    else
      AUTH_CLIENT_SECRET="$(random_urlsafe_token)"
      ok "Generated Agent Registry AUTH_CLIENT_SECRET. Save .env.agent-registry securely."
    fi

    EXISTING_AUTH_SIGNING_KEY="$(get_existing AUTH_SIGNING_KEY "$OUT_DIR/.env.agent-registry" || true)"
    if [[ -n "$EXISTING_AUTH_SIGNING_KEY" ]]; then
      prompt AUTH_SIGNING_KEY "Agent Registry AUTH_SIGNING_KEY" "$EXISTING_AUTH_SIGNING_KEY" true
    else
      AUTH_SIGNING_KEY="$(random_urlsafe_token)"
      ok "Generated Agent Registry AUTH_SIGNING_KEY. Save .env.agent-registry securely."
    fi

    prompt ORCHESTRATOR_URL "ORCHESTRATOR_URL for Agent Registry" "$(get_existing ORCHESTRATOR_URL "$OUT_DIR/.env.agent-registry" || echo http://orchestrator:8080)"

    prompt CUSTOM_WORKFLOWS_DIR "CUSTOM_WORKFLOWS_DIR inside container" "$(get_existing CUSTOM_WORKFLOWS_DIR "$OUT_DIR/.env.agent-registry" || echo /custom-workflows)"
    CONVERSATION_LOGS_DIR="/conversation-logs"
    AGENT_ENV_CONTENT=$(cat <<EOM
# ------------------------------
# Agent Registry runtime
# ------------------------------
PORT=${AGENT_PORT}
BASE_URL=${AGENT_BASE_URL}
LOG_LEVEL=${LOG_LEVEL}

# ------------------------------
# Agent Registry authentication
# ------------------------------
AUTH_CLIENT_ID=${AUTH_CLIENT_ID}
AUTH_CLIENT_SECRET=${AUTH_CLIENT_SECRET}
AUTH_SIGNING_KEY=${AUTH_SIGNING_KEY}
AUTH_TOKEN_TTL=3600

# ------------------------------
# Orchestrator connection
# ------------------------------
ORCHESTRATOR_URL=${ORCHESTRATOR_URL}
ORCHESTRATOR_CLIENT_ID=${ORCHESTRATOR_CLIENT_ID}
ORCHESTRATOR_CLIENT_SECRET=${ORCHESTRATOR_CLIENT_SECRET}

# ------------------------------
# Custom workflow folder
# ------------------------------
CUSTOM_WORKFLOWS_DIR=${CUSTOM_WORKFLOWS_DIR}
CONVERSATION_LOGS_DIR=${CONVERSATION_LOGS_DIR}

# ------------------------------
# Development-only options
# Keep both false in production
# ------------------------------
MCP_ENABLED=false
TUNNEL_ENABLED=false
EOM
)
  fi
else
  warn "Skipping Agent Registry: Copilot will not call A2A agents, but core Orchestrator/RAG features can still work."
fi

section "Deployment platform"
choose_num DEPLOYMENT_PLATFORM "Where do you want to deploy Spotfire Copilot?" "1" \
  "docker-compose|Docker Compose (single-host, includes docker-compose.yml)" \
  "aws-ecs|AWS ECS / Fargate" \
  "azure-aca|Azure Container Apps"
ok "Selected deployment platform: $DEPLOYMENT_PLATFORM"

# For cloud platforms, we'll generate cloud-env-checklist.txt instead of docker-compose.yml
if [[ "$DEPLOYMENT_PLATFORM" != "docker-compose" ]]; then
  GENERATE_COMPOSE="no"
else
  section "Output generation"
  yes_no_num GENERATE_COMPOSE "Generate a docker-compose.yml file?" "yes"
fi


# If the user selected the Docker Compose PostgreSQL option, the compose file must
# contain the orchestrator-postgres service. Otherwise .env.orchestrator will point
# to POSTGRES_HOST=orchestrator-postgres, but Docker DNS will have no such service.
if [[ "$POSTGRES_MODE" == "compose" && "$GENERATE_COMPOSE" != "yes" ]]; then
  if [[ -f "$OUT_DIR/docker-compose.yml" ]] && grep -qE '^[[:space:]]+orchestrator-postgres:' "$OUT_DIR/docker-compose.yml"; then
    warn "POSTGRES_MODE=compose selected and existing docker-compose.yml already contains orchestrator-postgres; not regenerating compose."
  else
    warn "POSTGRES_MODE=compose requires docker-compose.yml to include the orchestrator-postgres service."
    yes_no_num GENERATE_COMPOSE "Generate docker-compose.yml now to include orchestrator-postgres?" "yes"
 [[ "$GENERATE_COMPOSE" == "yes" ]] || die "Cannot continue with POSTGRES_MODE=compose unless docker-compose.yml contains orchestrator-postgres."
  fi
fi

BASE_ENV_CONTENT=$(cat <<EOM
# ------------------------------
# Spotfire Copilot image versions
# ------------------------------
IMAGE_TAG=${IMAGE_TAG}
FASTAPI_APP_VERSION=${FASTAPI_APP_VERSION}
AGENT_CONTAINER_TAG=${AGENT_CONTAINER_TAG}

# ------------------------------
# Docker Compose runtime
# ------------------------------
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
LOG_LEVEL=${LOG_LEVEL}
ACCESS_TOKEN_EXPIRE_DAYS=${ACCESS_TOKEN_EXPIRE_DAYS}
# Host folder for the Data Loader PDF documents. docker-compose interpolates this
# into the data-loader volume mapping (DOCS_DIR:/docs). Edit here to change the mount.
DOCS_DIR=${DOCS_DIR}

# ------------------------------
# Installer selections
# These are informational and help with later review/upgrade
# ------------------------------
LLM_PROVIDER=${LLM_PROVIDER}
POSTGRES_MODE=${POSTGRES_MODE}
ENABLE_ADMIN_CONSOLE=${ENABLE_ADMIN_CONSOLE}
ENABLE_RAG=${ENABLE_RAG}
EMBEDDING_PROVIDER=${EMBEDDING_PROVIDER:-none}
VECTOR_DB_PROVIDER=${VECTOR_DB_PROVIDER:-none}
ENABLE_DATA_LOADER=${ENABLE_DATA_LOADER}
ENABLE_AGENT_REGISTRY=${ENABLE_AGENT_REGISTRY}
EOM
)

ORCH_ENV_CONTENT=$(cat <<EOM
# ------------------------------
# Core authentication
# Generated values must come from generate_credentials.py
# ------------------------------
SECRET_KEY=${SECRET_KEY}
HASHED_ADMIN_PASSWORD=$(single_quote_env_value "$HASHED_ADMIN_PASSWORD")

# ------------------------------
# OAuth2 client credentials for Spotfire Copilot
# Spotfire Administration Manager uses the plaintext client secret
# ------------------------------
OAUTH2_CLIENT_ID=${OAUTH2_CLIENT_ID}
OAUTH2_CLIENT_SECRET_HASH=$(single_quote_env_value "$OAUTH2_CLIENT_SECRET_HASH")

# ------------------------------
# PostgreSQL
# Orchestrator and optional Admin Console use this database
# ------------------------------
POSTGRES_MODE=${POSTGRES_MODE}
POSTGRES_HOST=${POSTGRES_HOST}
POSTGRES_PORT=${POSTGRES_PORT}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
DATABASE_URL=${DATABASE_URL}
SYNC_DATABASE_URL=${SYNC_DATABASE_URL}
DB_SSLMODE=${DB_SSLMODE}

# ------------------------------
# Application URLs
# ------------------------------
ORCHESTRATOR_INTERNAL_URL=http://orchestrator:8080
CORS_ALLOWED_ORIGINS=http://localhost:${ADMIN_HOST_PORT:-8081},http://localhost:3000

# ------------------------------
# LLM provider
# ------------------------------
${MODEL_BLOCK_ORCH}

# ------------------------------
# Embeddings
# Used for RAG document/query vectorization
# ------------------------------
${EMBED_BLOCK_ORCH}

# ------------------------------
# Vector DB / Knowledge Base
# Orchestrator uses RETRIEVER_PLUGIN_ENTRY_POINT
# ------------------------------
${VECTOR_BLOCK_ORCH}

# ------------------------------
# RAG defaults
# ------------------------------
${RAG_DEFAULTS_BLOCK}

# ------------------------------
# Optional LangSmith tracing - uncomment only when LangSmith tracing is required
# ------------------------------
# LANGCHAIN_TRACING_V2=true
# LANGCHAIN_ENDPOINT=https://api.smith.langchain.com
# LANGCHAIN_API_KEY=<langsmith-api-key>
# LANGCHAIN_PROJECT=orchestrator-${IMAGE_TAG}
EOM
)

DL_ENV_CONTENT=$(cat <<EOM
# ------------------------------
# Data Loader authentication
# Must match Orchestrator SECRET_KEY and admin hash
# ------------------------------
SECRET_KEY=${SECRET_KEY}
HASHED_ADMIN_PASSWORD=$(single_quote_env_value "$HASHED_ADMIN_PASSWORD")

# ------------------------------
# Core
# ------------------------------
LOG_LEVEL=${LOG_LEVEL}
ACCESS_TOKEN_EXPIRE_DAYS=${ACCESS_TOKEN_EXPIRE_DAYS}

# ------------------------------
# LLM provider
# ------------------------------
${MODEL_BLOCK_DL}

# ------------------------------
# Embeddings
# Data Loader uses this to create vectors
# ------------------------------
${EMBED_BLOCK_DL}

# ------------------------------
# Vector DB / Knowledge Base
# Data Loader uses VECTORDB_PLUGIN_ENTRY_POINT
# ------------------------------
${VECTOR_BLOCK_DL}

# ------------------------------
# Local PDF document folder
# The host folder is configured via DOCS_DIR in .env and mounted to /docs by docker-compose.
# ------------------------------
DOCS_DIR=${DOCS_DIR}
EOM
)

BASE_ENV_CONTENT="$(compact_env_content "$BASE_ENV_CONTENT")"
ORCH_ENV_CONTENT="$(compact_env_content "$ORCH_ENV_CONTENT")"
DL_ENV_CONTENT="$(compact_env_content "$DL_ENV_CONTENT")"
AGENT_ENV_CONTENT="$(compact_env_content "$AGENT_ENV_CONTENT")"

write_file "$OUT_DIR/.env" "$BASE_ENV_CONTENT"
write_file "$OUT_DIR/.env.orchestrator" "$ORCH_ENV_CONTENT"
if [[ "$ENABLE_DATA_LOADER" == "yes" ]]; then write_file "$OUT_DIR/.env.dataloader" "$DL_ENV_CONTENT"; else info "Data Loader disabled; .env.dataloader was not written."; fi
if [[ "$ENABLE_AGENT_REGISTRY" == "yes" ]]; then write_file "$OUT_DIR/.env.agent-registry" "$AGENT_ENV_CONTENT"; fi

if [[ "$GENERATE_COMPOSE" == "yes" ]]; then
  # Build docker-compose.yml as an array of single-quoted lines whose indentation
  # lives INSIDE the quotes. awk/bash ignore source indentation and interior string
  # spaces survive whitespace-collapse, so this stays valid YAML even if this script
  # file's leading indentation is mangled in transit. ${...} stays literal for Compose.
  compose_lines=('services:')

  if [[ "$POSTGRES_MODE" == "compose" ]]; then
    compose_lines+=(
      '  orchestrator-postgres:'
      '    image: public.ecr.aws/docker/library/postgres:15-alpine'
      '    container_name: orchestrator-postgres-${IMAGE_TAG}'
      '    restart: unless-stopped'
      '    ports:'
      "      - \"127.0.0.1:${POSTGRES_HOST_PORT}:5432\""
      '    env_file:'
      '      - .env'
      '      - .env.orchestrator'
      '    volumes:'
      '      - postgres_data:/var/lib/postgresql/data'
      '    healthcheck:'
      '      # $${...} keeps Compose from interpolating at config time; the container gets these from .env.orchestrator.'
      '      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]'
      '      interval: 10s'
      '      timeout: 5s'
      '      retries: 10'
 )
  fi

  compose_lines+=(
    '  orchestrator:'
    '    image: copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:${IMAGE_TAG}'
    '    container_name: orchestrator-${IMAGE_TAG}'
    '    restart: unless-stopped'
 )
  if [[ "$POSTGRES_MODE" == "compose" ]]; then
    compose_lines+=(
      '    depends_on:'
      '      orchestrator-postgres:'
      '        condition: service_healthy'
 )
  fi
  compose_lines+=(
    '    ports:'
    "      - \"${ORCH_HOST_PORT}:8080\""
    '    env_file:'
    '      - .env'
    '      - .env.orchestrator'
    '    extra_hosts:'
    '      - "host.docker.internal:host-gateway"'
    '    healthcheck:'
    '      test: ["CMD", "curl", "-f", "http://localhost:8080/"]'
    '      interval: 30s'
    '      timeout: 10s'
    '      retries: 5'
    '      start_period: 60s'
 )

  if [[ "$ENABLE_ADMIN_CONSOLE" == "yes" ]]; then
    compose_lines+=(
      ''
      '  admin-console-service:'
      '    image: copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:${IMAGE_TAG}'
      '    container_name: orchestrator-admin-console-${IMAGE_TAG}'
      '    restart: unless-stopped'
      '    command: ["python", "/app/admin_console/admin_main.py"]'
      '    depends_on:'
      '      orchestrator:'
      '        condition: service_healthy'
      '    ports:'
      "      - \"${ADMIN_HOST_PORT}:8081\""
      '    env_file:'
      '      - .env'
      '      - .env.orchestrator'
      '    environment:'
      '      ORCHESTRATOR_INTERNAL_URL: http://orchestrator:8080'
      '    extra_hosts:'
      '      - "host.docker.internal:host-gateway"'
      '    healthcheck:'
      '      test: ["CMD", "curl", "-f", "http://localhost:8081/health"]'
      '      interval: 30s'
      '      timeout: 10s'
      '      retries: 5'
      '      start_period: 30s'
 )
  fi

  if [[ "$ENABLE_DATA_LOADER" == "yes" ]]; then
    compose_lines+=(
      ''
      '  data-loader:'
      '    image: copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-pypdf:${IMAGE_TAG}'
      '    container_name: data-loader-${IMAGE_TAG}'
      '    restart: unless-stopped'
      '    ports:'
      "      - \"${LOADER_HOST_PORT}:8080\""
      '    env_file:'
      '      - .env'
      '      - .env.dataloader'
      '    extra_hosts:'
      '      - "host.docker.internal:host-gateway"'
      '    volumes:'
      '      - ${DOCS_DIR}:/docs'
 )
  fi

  if [[ "$ENABLE_AGENT_REGISTRY" == "yes" ]]; then
    compose_lines+=(
      ''
      '  agent-registry:'
      '    image: copilotoci.azurecr.io/spotfirecopilot/agent-container:${AGENT_CONTAINER_TAG}'
      '    container_name: spotfire-agent-registry-${AGENT_CONTAINER_TAG}'
      '    restart: unless-stopped'
      '    ports:'
      "      - \"${AGENT_PORT}:${AGENT_PORT}\""
      '    env_file:'
      '      - .env'
      '      - .env.agent-registry'
      '    extra_hosts:'
      '      - "host.docker.internal:host-gateway"'
      '    volumes:'
      '      - /opt/spotfire-agent-registry/custom-workflows:/custom-workflows:ro'
      '      - /opt/spotfire-agent-registry/logs:/conversation-logs'
      '    healthcheck:'
      '      test: ["CMD", "curl", "-f", "http://localhost:8050/healthz"]'
      '      interval: 30s'
      '      timeout: 10s'
      '      retries: 5'
      '      start_period: 30s'
 )
  fi

  compose_lines+=(
    ''
    'volumes:'
    '  postgres_data:'
    '    driver: local'
    '    name: ${COMPOSE_PROJECT_NAME:-spotfire-copilot}_postgres_data'
 )

  COMPOSE_CONTENT="$(printf '%s\n' "${compose_lines[@]}")"
  write_file "$OUT_DIR/docker-compose.yml" "$COMPOSE_CONTENT"

  if [[ "$POSTGRES_MODE" == "compose" ]]; then
    grep -qE '^[[:space:]]+orchestrator-postgres:' "$OUT_DIR/docker-compose.yml" || die "Generated docker-compose.yml is missing orchestrator-postgres even though POSTGRES_MODE=compose."
    ok "Verified docker-compose.yml contains orchestrator-postgres service."
  fi
fi

if [[ "${POSTGRES_RESET_LOCAL_VOLUME_SELECTED:-no}" == "yes" ]]; then
  section "Local PostgreSQL reset"
  warn "You selected a fresh lab/test reset. This stops the Docker Compose stack and deletes ONLY the local PostgreSQL volume. Do this only when Copilot backend data can be discarded."
  yes_no_num RUN_POSTGRES_RESET_NOW "Run the targeted local PostgreSQL volume reset now?" "yes"
  if [[ "$RUN_POSTGRES_RESET_NOW" == "yes" ]]; then
    read -r -p "Type DELETE to remove the local PostgreSQL volume now: " DELETE_CONFIRM
    if [[ "$DELETE_CONFIRM" == "DELETE" ]]; then
      "$OUT_DIR/reset-local-postgres-volume.sh"
      ok "Local Docker Compose PostgreSQL volume reset completed. Next docker compose up will initialize PostgreSQL with the password now in .env.orchestrator."
    else
      warn "Reset skipped. You must run $OUT_DIR/reset-local-postgres-volume.sh before starting/restarting, otherwise the stale database password will remain."
    fi
  else
    warn "Reset skipped. You must run $OUT_DIR/reset-local-postgres-volume.sh before starting/restarting, otherwise the stale database password will remain."
  fi
fi

run_deepagents_oss_generator_if_requested

validate_compose_if_possible
remember_out_dir

# ── Cloud platform deployment handoff ─────────────────────────────────────
if [[ "$DEPLOYMENT_PLATFORM" != "docker-compose" ]]; then
  section "Cloud deployment configuration"
  
  # Generate cloud-env-checklist.txt for reference
  CLOUD_ENV_CHECKLIST="$OUT_DIR/cloud-env-checklist.txt"
  cat > "$CLOUD_ENV_CHECKLIST" <<'CHECKLIST'
# Cloud Deployment Environment Checklist
# Generated by spotfire-copilot-backend-deploy.sh
# Use this with the platform-specific deployment scripts

## Core Configuration
CHECKLIST
  echo "IMAGE_TAG=${IMAGE_TAG}" >> "$CLOUD_ENV_CHECKLIST"
  echo "FASTAPI_APP_VERSION=${FASTAPI_APP_VERSION}" >> "$CLOUD_ENV_CHECKLIST"
  echo "LLM_PROVIDER=${LLM_PROVIDER}" >> "$CLOUD_ENV_CHECKLIST"
  echo "POSTGRES_MODE=${POSTGRES_MODE}" >> "$CLOUD_ENV_CHECKLIST"
  echo "ENABLE_ADMIN_CONSOLE=${ENABLE_ADMIN_CONSOLE}" >> "$CLOUD_ENV_CHECKLIST"
  
  ok "Generated cloud-env-checklist.txt for deployment reference"
  
  # Ask if user wants to deploy now
  echo ""
  yes_no_num DEPLOY_NOW_CHOICE "Deploy this configuration to $DEPLOYMENT_PLATFORM now?" "yes"
  
  if [[ "$DEPLOY_NOW_CHOICE" == "yes" ]]; then
    echo ""
    info "Handing off to platform-specific deployment script..."
    echo ""
    
    # Source the appropriate platform script
    case "$DEPLOYMENT_PLATFORM" in
      aws-ecs)
        PLATFORM_SCRIPT="$SCRIPT_DIR/spotfire-copilot-backend-deploy-ecs.sh"
        [[ -f "$PLATFORM_SCRIPT" ]] || die "Platform script not found: $PLATFORM_SCRIPT"
        # Export all variables so platform script can access them
        export DEPLOYMENT_PLATFORM OUT_DIR IMAGE_TAG FASTAPI_APP_VERSION LLM_PROVIDER
        export POSTGRES_MODE POSTGRES_HOST POSTGRES_PORT POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD
        export DATABASE_URL SYNC_DATABASE_URL DB_SSLMODE SECRET_KEY HASHED_ADMIN_PASSWORD
        export OAUTH2_CLIENT_ID OAUTH2_CLIENT_SECRET_HASH
        export ENABLE_ADMIN_CONSOLE ENABLE_RAG EMBEDDING_PROVIDER VECTOR_DB_PROVIDER
        export ENABLE_DATA_LOADER ENABLE_AGENT_REGISTRY LOG_LEVEL ACCESS_TOKEN_EXPIRE_DAYS
        export MODEL_BLOCK_ORCH MODEL_BLOCK_DL EMBED_BLOCK_ORCH EMBED_BLOCK_DL
        export VECTOR_BLOCK_ORCH VECTOR_BLOCK_DL RAG_DEFAULTS_BLOCK LLM_ENV_BLOCK LLM_SECRETS_BLOCK
        # Source and execute Phase 3-4 of ECS deployment
        source "$PLATFORM_SCRIPT"
        ;;
      azure-aca)
        PLATFORM_SCRIPT="$SCRIPT_DIR/spotfire-copilot-backend-deploy-aca.sh"
        [[ -f "$PLATFORM_SCRIPT" ]] || die "Platform script not found: $PLATFORM_SCRIPT"
        # Export all variables so platform script can access them
        export DEPLOYMENT_PLATFORM OUT_DIR IMAGE_TAG FASTAPI_APP_VERSION LLM_PROVIDER
        export POSTGRES_MODE POSTGRES_HOST POSTGRES_PORT POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD
        export DATABASE_URL SYNC_DATABASE_URL DB_SSLMODE SECRET_KEY HASHED_ADMIN_PASSWORD
        export OAUTH2_CLIENT_ID OAUTH2_CLIENT_SECRET_HASH
        export ENABLE_ADMIN_CONSOLE ENABLE_RAG EMBEDDING_PROVIDER VECTOR_DB_PROVIDER
        export ENABLE_DATA_LOADER ENABLE_AGENT_REGISTRY LOG_LEVEL ACCESS_TOKEN_EXPIRE_DAYS
        export MODEL_BLOCK_ORCH MODEL_BLOCK_DL EMBED_BLOCK_ORCH EMBED_BLOCK_DL
        export VECTOR_BLOCK_ORCH VECTOR_BLOCK_DL RAG_DEFAULTS_BLOCK LLM_ENV_BLOCK LLM_SECRETS_BLOCK
        # Source and execute Phase 3-4 of ACA deployment
        source "$PLATFORM_SCRIPT"
        ;;
    esac
  else
    info "Deployment deferred. To deploy later, run:"
    echo ""
    case "$DEPLOYMENT_PLATFORM" in
      aws-ecs)
        echo "  $SCRIPT_DIR/spotfire-copilot-backend-deploy-ecs.sh --dir $OUT_DIR"
        ;;
      azure-aca)
        echo "  $SCRIPT_DIR/spotfire-copilot-backend-deploy-aca.sh --dir $OUT_DIR"
        ;;
    esac
    echo ""
    ok "Configuration template saved. You can deploy at any time using the command above."
    echo ""
  fi
fi

section "Generated files"
ls -l "$OUT_DIR/.env" "$OUT_DIR/.env.orchestrator" 2>/dev/null || true
[[ "$ENABLE_DATA_LOADER" == "yes" ]] && ls -l "$OUT_DIR/.env.dataloader" 2>/dev/null || true
[[ "$ENABLE_AGENT_REGISTRY" == "yes" ]] && ls -l "$OUT_DIR/.env.agent-registry" 2>/dev/null || true
[[ "$GENERATE_COMPOSE" == "yes" ]] && ls -l "$OUT_DIR/docker-compose.yml" 2>/dev/null || true

echo
ok "Generation complete."
echo "LLM provider: ${LLM_PROVIDER}"
echo "PostgreSQL mode: ${POSTGRES_MODE}"
echo "Admin Console: ${ENABLE_ADMIN_CONSOLE}"
echo "RAG: ${ENABLE_RAG}"
echo "Vector DB: ${VECTOR_DB_PROVIDER:-none}"
echo "Embedding provider: ${EMBEDDING_PROVIDER:-none}"
echo "Data Loader: ${ENABLE_DATA_LOADER}"
echo "Agent Registry: ${ENABLE_AGENT_REGISTRY}"
echo
info "Next checks:"
echo "  Change to your working directory"
echo "  docker compose config >/tmp/copilot-compose-rendered.yml"
echo "  docker compose up -d --no-build"
echo