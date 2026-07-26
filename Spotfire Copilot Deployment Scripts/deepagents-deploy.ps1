#Requires -Version 5.1
<#
================================================================================
 DeepAgents OSS environment/template generator  (Windows / PowerShell port)
================================================================================
 PowerShell equivalent of generate-deepagents-oss-env (the bash generator).

 Faithful-port notes / Windows adaptations:
   * `openssl rand` -> .NET RandomNumberGenerator (URL-safe base64, no padding).
   * `sed` / `grep` -> PowerShell regex / string operations.
   * `chmod 600` -> best-effort `icacls` (restrict to current user). NTFS ACLs
     are not identical to POSIX modes; failures are non-fatal.
   * All generated env / compose files are written with LF line endings so that
     Docker / Compose parse them correctly.
   * Compose ${IMAGE_TAG} / ${PORT:-8000} / ${DEEPAGENTS_POSTGRES_PASSWORD}
     placeholders are kept LITERAL (single-quoted here-strings) so Docker
     Compose resolves them at runtime.

 Usage:
   .\Generate-DeepAgentsOssEnv.ps1
   .\Generate-DeepAgentsOssEnv.ps1 -Dir C:\opt\deepagents-oss
   .\Generate-DeepAgentsOssEnv.ps1 -Upgrade -ImageTag 1.0.1 -Dir C:\opt\deepagents-oss
   .\Generate-DeepAgentsOssEnv.ps1 -Help

 Environment overrides (parity with the bash script):
   $env:OUT_DIR, $env:DEFAULT_IMAGE_TAG, $env:AGENT_CATALOG_FILE, $env:NO_COLOR
================================================================================
#>

[CmdletBinding()]
param(
    [switch]$Help,
    [string]$Dir,
    [switch]$Upgrade,
    [string]$ImageTag,
    [switch]$NoColor
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Global state (mirrors the bash globals)
# ----------------------------------------------------------------------------
$script:SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:START_DIR  = (Get-Location).Path
$script:OUT_DIR = if ($env:OUT_DIR) { $env:OUT_DIR } else { Join-Path $script:START_DIR 'deepagents-oss-deploy' }
$script:DEFAULT_IMAGE_TAG = if ($env:DEFAULT_IMAGE_TAG) { $env:DEFAULT_IMAGE_TAG } else { '1.0.0' }
$script:MODE = 'generate'
$script:UPGRADE_IMAGE_TAG = ''
$script:AGENT_CATALOG_FILE = if ($env:AGENT_CATALOG_FILE) { $env:AGENT_CATALOG_FILE } else { Join-Path $script:SCRIPT_DIR 'deepagents-agent-catalog.conf' }
$script:UseColor = (-not $NoColor) -and [string]::IsNullOrEmpty($env:NO_COLOR)

# Catalog state (populated by Initialize-AgentCatalog)
$script:AGENT_IDS = @()
$script:AGENT_PREFIXES = @()
$script:AGENT_DESCS = @()
$script:SELECTED_AGENTS = @()
$script:MCP_TEMPLATE_BLOCK = ''
$script:REQUIRED_VALUES = ''

# ----------------------------------------------------------------------------
# color / output helpers
# ----------------------------------------------------------------------------
function Write-Section { param([string]$Text)
    Write-Host ''
    if ($script:UseColor) { Write-Host "== $Text ==" -ForegroundColor Magenta } else { Write-Host "== $Text ==" }
}
function Write-Info { param([string]$Text)
    if ($script:UseColor) { Write-Host 'INFO:' -ForegroundColor Cyan -NoNewline; Write-Host " $Text" } else { Write-Host "INFO: $Text" }
}
function Write-Ok { param([string]$Text)
    if ($script:UseColor) { Write-Host 'OK:' -ForegroundColor Green -NoNewline; Write-Host " $Text" } else { Write-Host "OK: $Text" }
}
function Write-Warn { param([string]$Text)
    if ($script:UseColor) { Write-Host 'WARN:' -ForegroundColor Yellow -NoNewline; Write-Host " $Text" } else { Write-Host "WARN: $Text" }
}
function Invoke-Die { param([string]$Text)
    if ($script:UseColor) { Write-Host 'ERROR:' -ForegroundColor Red -NoNewline; Write-Host " $Text" } else { Write-Host "ERROR: $Text" }
    exit 1
}
function Get-Timestamp { (Get-Date -Format 'yyyyMMdd_HHmmss') }
function Test-CommandExists { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# ----------------------------------------------------------------------------
# generic helpers
# ----------------------------------------------------------------------------
function Get-Trim { param([string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Trim()
}

# Best-effort POSIX-mode equivalent: restrict a file to the current user.
function Protect-File { param([string]$Path)
    try {
        if (Test-Path $Path) {
            $me = "$env:USERDOMAIN\$env:USERNAME"
            & icacls $Path /inheritance:r /grant:r "${me}:F" 2>$null | Out-Null
        }
    } catch { }
}

# Write text using LF line endings (so Docker/Compose parse files correctly).
function Write-TextFileLF { param([string]$Path, [string]$Content)
    $normalized = ($Content -replace "`r`n", "`n")
    if (-not $normalized.EndsWith("`n")) { $normalized += "`n" }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function Backup-File { param([string]$File)
    if (-not (Test-Path $File)) { return }
    $backup = "$File.bak.$(Get-Timestamp)"
    Copy-Item -LiteralPath $File -Destination $backup -Force
    Write-Info "Backed up $File"
}

function Write-OutputFile { param([string]$File, [string]$Content)
    $dir = Split-Path -Parent $File
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Backup-File $File
    Write-TextFileLF -Path $File -Content $Content
    Protect-File $File
    Write-Ok "Wrote $File"
}

# Update or append KEY=VALUE in an existing file (no-op if the file is absent).
function Set-EnvValue { param([string]$File, [string]$Key, [string]$Value)
    if (-not (Test-Path $File)) { return }
    Backup-File $File
    $content = [System.IO.File]::ReadAllText($File) -replace "`r`n", "`n"
    $pattern = "(?m)^\s*$([regex]::Escape($Key))=.*$"
    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, { param($m) "$Key=$Value" })
    } else {
        if (-not $content.EndsWith("`n")) { $content += "`n" }
        $content += "`n$Key=$Value`n"
    }
    Write-TextFileLF -Path $File -Content $content
    Protect-File $File
}

# URL-safe base64 token without padding (parity with openssl rand -base64 48 | tr).
function Get-RandomToken {
    $bytes = New-Object 'System.Byte[]' 48
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $b64 = [Convert]::ToBase64String($bytes)
    return ($b64 -replace '\+', '-' -replace '/', '_' -replace '=', '')
}

# Prompt for a value with an optional default. -Secret hides input.
function Read-Prompt {
    param([string]$Label, [string]$Default = '', [switch]$Secret)
    if ($Secret) {
        if (-not [string]::IsNullOrEmpty($Default)) {
            $sec = Read-Host -Prompt "$Label [press Enter to reuse existing/default]" -AsSecureString
        } else {
            $sec = Read-Host -Prompt "$Label" -AsSecureString
        }
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $inputValue = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    } else {
        if (-not [string]::IsNullOrEmpty($Default)) {
            $inputValue = Read-Host -Prompt "$Label [$Default]"
        } else {
            $inputValue = Read-Host -Prompt "$Label"
        }
    }
    if ([string]::IsNullOrEmpty($inputValue)) { return $Default }
    return $inputValue
}

# Numbered menu. $Options is an array of "value|display" strings. Number only.
function Read-ChooseNum {
    param([string]$Label, [int]$DefaultNumber, [string[]]$Options)
    while ($true) {
        Write-Host ''
        Write-Host $Label
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $display = $Options[$i].Substring($Options[$i].IndexOf('|') + 1)
            Write-Host ("  {0}) {1}" -f ($i + 1), $display)
        }
        $choice = Read-Host -Prompt "Enter number [$DefaultNumber]"
        if ([string]::IsNullOrEmpty($choice)) { $choice = "$DefaultNumber" }
        $choice = $choice.Trim()
        if ($choice -match '^[0-9]+$') {
            $n = [int]$choice
            if ($n -ge 1 -and $n -le $Options.Count) {
                $sel = $Options[$n - 1]
                return $sel.Substring(0, $sel.IndexOf('|'))
            }
        }
        Write-Warn "Invalid selection '$choice'. Enter a number from 1 to $($Options.Count)."
    }
}

function Read-YesNo { param([string]$Label, [string]$Default = 'no')
    $defNum = if ($Default -eq 'yes') { 1 } else { 2 }
    return (Read-ChooseNum $Label $defNum @('yes|Yes', 'no|No'))
}

function Show-Usage {
@'
DeepAgents OSS environment/template generator (PowerShell)

Usage:
  .\Generate-DeepAgentsOssEnv.ps1
  .\Generate-DeepAgentsOssEnv.ps1 -Dir C:\opt\deepagents-oss
  .\Generate-DeepAgentsOssEnv.ps1 -Upgrade -ImageTag 1.0.1 -Dir C:\opt\deepagents-oss
  $env:OUT_DIR='C:\opt\deepagents-oss'; $env:AGENT_CATALOG_FILE='C:\path\deepagents-agent-catalog.conf'; .\Generate-DeepAgentsOssEnv.ps1

Options:
  -Help             Show help.
  -Dir DIR          Output/deployment directory. Default: .\deepagents-oss-deploy.
  -Upgrade          Update IMAGE_TAG in existing .env/template and print restart commands.
  -ImageTag TAG     Image tag for generation default or upgrade target.
  -NoColor          Disable colored output.

Defaults:
  DEFAULT_IMAGE_TAG defaults to 1.0.0 unless overridden via $env:DEFAULT_IMAGE_TAG or -ImageTag.

Optional external catalog format:
  agent_id|ENV_PREFIX|One-line description

Example:
  databricks_agent|DATABRICKS|Databricks workspace/SQL/data agent; requires Databricks MCP server.
'@ | Write-Host
}

# ----------------------------------------------------------------------------
# Agent catalog
# ----------------------------------------------------------------------------
$script:DEFAULT_AGENT_CATALOG = @'
osdu_agent|OSDU|OSDU data agent; requires an OSDU MCP server.
databricks_agent|DATABRICKS|Databricks workspace/SQL/data agent; requires a Databricks MCP server.
databricks_genie_agent|GENIE|Databricks Genie conversational analytics agent; requires a Genie MCP server.
snowflake_agent|SNOWFLAKE|Snowflake data agent; requires a Snowflake MCP server.
dv_agent|DV|Spotfire Data Virtualization agent; requires a DV MCP server.
sf_lib_md_agent|SFLIB|Spotfire Library metadata agent; requires a Spotfire Library MCP server.
sf_lic_agent|SFLIC|Spotfire licensing/admin metadata agent; requires a Spotfire Licensing MCP server.
tavily_agent|TAVILY|Tavily/search-style agent; requires a Tavily MCP server or matching Tavily configuration.
milvus_agent|MILVUS|Milvus/vector-store agent; requires a Milvus MCP server.
ddr_agent|DDR|DDR workflow agent; requires the matching DDR MCP server.
'@

function Initialize-AgentCatalog {
    $script:AGENT_IDS = @()
    $script:AGENT_PREFIXES = @()
    $script:AGENT_DESCS = @()
    $sourceName = ''

    if (Test-Path $script:AGENT_CATALOG_FILE) {
        $sourceName = $script:AGENT_CATALOG_FILE
        Write-Info "Using external agent catalog: $($script:AGENT_CATALOG_FILE)"
        foreach ($raw in (Get-Content -LiteralPath $script:AGENT_CATALOG_FILE)) {
            $line = Get-Trim $raw
            if ([string]::IsNullOrEmpty($line) -or $line.StartsWith('#')) { continue }
            $parts = $line.Split('|')
            $agent = Get-Trim $parts[0]
            $prefix = if ($parts.Count -ge 2) { Get-Trim $parts[1] } else { '' }
            $desc = if ($parts.Count -ge 3) { Get-Trim (($parts[2..($parts.Count - 1)]) -join '|') } else { '' }
            if ([string]::IsNullOrEmpty($agent) -or [string]::IsNullOrEmpty($prefix)) { continue }
            if ([string]::IsNullOrEmpty($desc)) { $desc = 'Custom agent; verify MCP requirements in the official guide.' }
            $script:AGENT_IDS += $agent
            $script:AGENT_PREFIXES += $prefix
            $script:AGENT_DESCS += $desc
        }
    } else {
        $sourceName = 'built-in default catalog'
        foreach ($line in ($script:DEFAULT_AGENT_CATALOG -split "`n")) {
            $line = ($line -replace "`r$", '')
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line.Split('|')
            $script:AGENT_IDS += (Get-Trim $parts[0])
            $script:AGENT_PREFIXES += (Get-Trim $parts[1])
            $script:AGENT_DESCS += (Get-Trim (($parts[2..($parts.Count - 1)]) -join '|'))
        }
    }

    if ($script:AGENT_IDS.Count -le 0) { Invoke-Die 'Agent catalog is empty.' }
    Write-Info "Loaded $($script:AGENT_IDS.Count) agent definitions from $sourceName."
}

function Get-KnownAgentIndex { param([string]$Search)
    for ($i = 0; $i -lt $script:AGENT_IDS.Count; $i++) {
        if ($script:AGENT_IDS[$i] -eq $Search) { return $i }
    }
    return -1
}

function Get-AgentPrefix { param([string]$Agent)
    $i = Get-KnownAgentIndex $Agent
    if ($i -ge 0) { return $script:AGENT_PREFIXES[$i] }
    return ''
}

function Get-AgentDescription { param([string]$Agent)
    $i = Get-KnownAgentIndex $Agent
    if ($i -ge 0) { return $script:AGENT_DESCS[$i] }
    return 'Custom or unknown agent; verify the matching MCP/config variables in the official DeepAgents OSS guide.'
}

function Show-AgentCatalog {
    Write-Host 'Available agent catalog:'
    for ($i = 0; $i -lt $script:AGENT_IDS.Count; $i++) {
        Write-Host ("  - {0,-26} {1}" -f ($script:AGENT_IDS[$i] + ':'), $script:AGENT_DESCS[$i])
    }
}

function Get-AgentCommentBlock {
    $block = '# Agent catalog snapshot. Update AGENTS_ENABLED only after the matching MCP servers are ready.'
    for ($i = 0; $i -lt $script:AGENT_IDS.Count; $i++) {
        $block += "`n# " + $script:AGENT_IDS[$i] + ': ' + $script:AGENT_DESCS[$i]
    }
    return $block
}

function Split-AgentsCsv { param([string]$Csv)
    $script:SELECTED_AGENTS = @()
    if ([string]::IsNullOrEmpty($Csv)) { return }
    foreach ($item in $Csv.Split(',')) {
        $t = Get-Trim $item
        if (-not [string]::IsNullOrEmpty($t)) { $script:SELECTED_AGENTS += $t }
    }
}

function Add-McpTemplateForAgent { param([string]$Agent, [string]$Prefix)
    $lower = $Prefix.ToLower()
    $desc = Get-AgentDescription $Agent
    $script:MCP_TEMPLATE_BLOCK += "`n`n# --- ${Agent}: $desc`n"
    $script:MCP_TEMPLATE_BLOCK += "# Required when ${Agent} is enabled:`n"
    $script:MCP_TEMPLATE_BLOCK += "${Prefix}_MCP_SERVER_URL=https://mcp-${lower}.example.com/mcp`n"
    $script:MCP_TEMPLATE_BLOCK += "${Prefix}_MCP_BEARER_TOKEN=<token>`n"
    $script:MCP_TEMPLATE_BLOCK += "# Optional defaults/tuning:`n"
    $script:MCP_TEMPLATE_BLOCK += "${Prefix}_MCP_SERVER_TRANSPORT=streamable-http`n"
    $script:MCP_TEMPLATE_BLOCK += "${Prefix}_MCP_CALL_TIMEOUT=60`n"
    $script:MCP_TEMPLATE_BLOCK += "# ${Prefix}_MCP_ALLOW_DEGRADED_STARTUP=false`n"
    $script:MCP_TEMPLATE_BLOCK += "# ${Prefix}_MCP_INIT_TIMEOUT=10`n"
    $script:MCP_TEMPLATE_BLOCK += "# ${Prefix}_MCP_CONNECT_TIMEOUT=5`n"
    $script:MCP_TEMPLATE_BLOCK += "# ${Prefix}_MCP_READ_TIMEOUT=30`n"
    $script:MCP_TEMPLATE_BLOCK += "# ${Prefix}_MCP_INIT_RETRY_COUNT=3`n"
    $script:MCP_TEMPLATE_BLOCK += "# ${Prefix}_MCP_INIT_RETRY_BACKOFF_SECONDS=0.5`n"
    $script:MCP_TEMPLATE_BLOCK += "# ${Prefix}_MCP_SCHEMA_TTL_SECONDS=300`n"
}

function Add-McpChecklistForAgent { param([string]$Agent, [string]$Prefix)
    $script:REQUIRED_VALUES += "`n" + $Agent + ' - ' + (Get-AgentDescription $Agent) + "`n"
    if (-not [string]::IsNullOrEmpty($Prefix)) {
        $script:REQUIRED_VALUES += "  Required before enabling/registering:`n"
        $script:REQUIRED_VALUES += "    ${Prefix}_MCP_SERVER_URL`n"
        $script:REQUIRED_VALUES += "    ${Prefix}_MCP_BEARER_TOKEN or shared MCP_BEARER_TOKEN, if the MCP backend requires bearer auth`n"
        $script:REQUIRED_VALUES += "  Recommended defaults/tuning:`n"
        $script:REQUIRED_VALUES += "    ${Prefix}_MCP_SERVER_TRANSPORT=streamable-http`n"
        $script:REQUIRED_VALUES += "    ${Prefix}_MCP_CALL_TIMEOUT=60`n"
    } else {
        $script:REQUIRED_VALUES += "  This agent is not in the local catalog. Check the official DeepAgents OSS guide or your image-specific release notes for required env variables.`n"
    }
}

# ----------------------------------------------------------------------------
# Upgrade mode
# ----------------------------------------------------------------------------
function Invoke-Upgrade {
    if ([string]::IsNullOrEmpty($script:UPGRADE_IMAGE_TAG)) {
        Invoke-Die '-Upgrade requires -ImageTag <new-tag>. Example: -Upgrade -ImageTag 1.0.1 -Dir C:\opt\deepagents-oss'
    }
    if (-not (Test-Path $script:OUT_DIR -PathType Container)) {
        Invoke-Die "Output/deployment directory not found: $($script:OUT_DIR)"
    }

    Write-Section 'DeepAgents OSS upgrade'
    Write-Info "Deployment directory: $($script:OUT_DIR)"
    Write-Info "New IMAGE_TAG: $($script:UPGRADE_IMAGE_TAG)"

    $updated = $false
    foreach ($file in @((Join-Path $script:OUT_DIR '.env'), (Join-Path $script:OUT_DIR 'deepagents-env-template.env'))) {
        if (Test-Path $file) {
            Set-EnvValue $file 'IMAGE_TAG' $script:UPGRADE_IMAGE_TAG
            Write-Ok "Updated IMAGE_TAG in $file"
            $updated = $true
        }
    }
    if (-not $updated) { Invoke-Die "No .env or deepagents-env-template.env found in $($script:OUT_DIR). Run generation first, or provide the correct -Dir." }

    $composePath = Join-Path $script:OUT_DIR 'docker-compose.yml'
    if (Test-Path $composePath) {
        $composeText = [System.IO.File]::ReadAllText($composePath)
        if ($composeText.Contains('copilot-deepagents-server-oss:${IMAGE_TAG}')) {
            Write-Ok 'docker-compose.yml already uses IMAGE_TAG variable.'
        } else {
            Write-Warn 'docker-compose.yml may not use IMAGE_TAG variable. Verify the deepagents-oss image line before upgrading.'
        }
    } else {
        Write-Warn "docker-compose.yml was not found in $($script:OUT_DIR)."
    }

    $dockerOk = $false
    if ((Test-Path (Join-Path $script:OUT_DIR '.env')) -and (Test-Path $composePath) -and (Test-CommandExists 'docker')) {
        try { & docker compose version 1>$null 2>$null; if ($LASTEXITCODE -eq 0) { $dockerOk = $true } } catch { }
    }
    if ($dockerOk) {
        Push-Location $script:OUT_DIR
        try {
            $rendered = Join-Path ([System.IO.Path]::GetTempPath()) 'deepagents-oss-compose-rendered.yml'
            & docker compose config | Out-File -FilePath $rendered -Encoding utf8
            Write-Ok "Docker Compose config validated. Rendered file: $rendered"
        } catch {
            Write-Warn 'docker compose config validation failed.'
        } finally { Pop-Location }
    } else {
        Write-Warn 'Skipped compose validation because .env/docker compose is missing or Docker Compose is unavailable.'
    }

    Write-Host ''
    Write-Ok 'Upgrade files prepared.'
    Write-Host ''
    Write-Host 'Next:'
    Write-Host "  cd $($script:OUT_DIR)"
    Write-Host '  docker login copilotoci.azurecr.io'
    Write-Host '  docker compose pull deepagents-oss'
    Write-Host '  docker compose up -d --force-recreate deepagents-oss'
}

# ============================================================================
# main
# ============================================================================

# ---- translate PowerShell parameters into script state (parse_args) ----
if ($Help) { $script:MODE = 'help' }
if (-not [string]::IsNullOrEmpty($Dir)) { $script:OUT_DIR = $Dir }
if ($Upgrade) { $script:MODE = 'upgrade' }
if (-not [string]::IsNullOrEmpty($ImageTag)) {
    $script:UPGRADE_IMAGE_TAG = $ImageTag
    $script:DEFAULT_IMAGE_TAG = $ImageTag
}

if ($script:MODE -eq 'help') { Show-Usage; exit 0 }
if ($script:MODE -eq 'upgrade') { Invoke-Upgrade; exit 0 }

Write-Section 'DeepAgents OSS deployment generator'
Write-Info 'This is a separate deployment from Spotfire Copilot Orchestrator and Agent Registry.'
Write-Info 'This script generates either a deployment-ready .env or a template/checklist. It does not install MCP servers.'
Initialize-AgentCatalog

$script:OUT_DIR = Read-Prompt 'Output directory' $script:OUT_DIR
New-Item -ItemType Directory -Path $script:OUT_DIR -Force | Out-Null

Write-Section 'Generation mode'
$GENERATION_MODE = Read-ChooseNum 'What should this script generate?' 1 @(
    'template|Template/checklist first - recommended when MCP details are not ready',
    'runtime|Runnable .env + docker-compose.yml - only when you have required values'
)

while ($true) {
    $IMAGE_TAG = Read-Prompt 'DeepAgents OSS image tag approved for this environment' $script:DEFAULT_IMAGE_TAG
    if (-not [string]::IsNullOrEmpty($IMAGE_TAG)) { break }
    Write-Warn 'IMAGE_TAG is required. Use the image tag confirmed by Spotfire Support or your platform team.'
}

Write-Section 'Core server settings'
$HostValue       = Read-Prompt 'HOST' '0.0.0.0'
$PORT            = Read-Prompt 'PORT' '8000'
$PUBLIC_BASE_URL = Read-Prompt 'PUBLIC_BASE_URL reachable by Orchestrator/clients' 'http://localhost:8000'
$LOG_LEVEL       = Read-Prompt 'LOG_LEVEL' 'INFO'

Write-Section 'Persistence'
$PERSISTENCE_MODE = Read-ChooseNum 'How should DeepAgents use Postgres and Redis?' 1 @(
    'local|Local Docker Compose Postgres + Redis - dev/test or small non-prod',
    'external|External/managed Postgres + Redis - production pattern'
)
switch ($PERSISTENCE_MODE) {
    'local' {
        if ($GENERATION_MODE -eq 'runtime') {
            $DEEPAGENTS_POSTGRES_PASSWORD = Get-RandomToken
        } else {
            $DEEPAGENTS_POSTGRES_PASSWORD = '<generate-secure-postgres-password>'
        }
        $POSTGRES_URL = "postgresql://postgres:${DEEPAGENTS_POSTGRES_PASSWORD}@deepagents-oss-postgres:5432/deepagents_checkpoints"
        $REDIS_URL = 'redis://deepagents-oss-redis:6379/0'
    }
    'external' {
        $DEEPAGENTS_POSTGRES_PASSWORD = ''
        if ($GENERATION_MODE -eq 'runtime') {
            $POSTGRES_URL = Read-Prompt 'External POSTGRES_URL' 'postgresql://USER:PASS@POSTGRES_HOST:5432/deepagents_checkpoints?sslmode=require' -Secret
            $REDIS_URL = Read-Prompt 'External REDIS_URL' 'redis://REDIS_HOST:6379/0' -Secret
        } else {
            $POSTGRES_URL = 'postgresql://USER:PASS@POSTGRES_HOST:5432/deepagents_checkpoints?sslmode=require'
            $REDIS_URL = 'redis://REDIS_HOST:6379/0'
        }
    }
}

Write-Section 'DeepAgents model'
Write-Info 'DeepAgents OSS runs its own agent reasoning loop and needs an LLM model/provider. This is separate from the MCP servers.'
$LLM_PROVIDER = Read-ChooseNum 'Which model provider will DeepAgents OSS use?' 1 @(
    'openai|OpenAI',
    'anthropic|Anthropic',
    'google|Google Gemini API'
)
switch ($LLM_PROVIDER) {
    'openai' {
        if ($GENERATION_MODE -eq 'runtime') { $OPENAI_API_KEY = Read-Prompt 'OPENAI_API_KEY' '' -Secret } else { $OPENAI_API_KEY = '<set-openai-api-key>' }
        $DEEPAGENTS_MODEL = Read-Prompt 'DEEPAGENTS_MODEL' 'openai:gpt-5.1'
        $MODEL_SECRET_BLOCK = "OPENAI_API_KEY=$OPENAI_API_KEY`n# ANTHROPIC_API_KEY=`n# GOOGLE_API_KEY="
    }
    'anthropic' {
        if ($GENERATION_MODE -eq 'runtime') { $ANTHROPIC_API_KEY = Read-Prompt 'ANTHROPIC_API_KEY' '' -Secret } else { $ANTHROPIC_API_KEY = '<set-anthropic-api-key>' }
        $DEEPAGENTS_MODEL = Read-Prompt 'DEEPAGENTS_MODEL' 'anthropic:claude-3-5-sonnet-latest'
        $MODEL_SECRET_BLOCK = "# OPENAI_API_KEY=`nANTHROPIC_API_KEY=$ANTHROPIC_API_KEY`n# GOOGLE_API_KEY="
    }
    'google' {
        if ($GENERATION_MODE -eq 'runtime') { $GOOGLE_API_KEY = Read-Prompt 'GOOGLE_API_KEY' '' -Secret } else { $GOOGLE_API_KEY = '<set-google-api-key>' }
        $DEEPAGENTS_MODEL = Read-Prompt 'DEEPAGENTS_MODEL' 'google:gemini-2.0-flash'
        $MODEL_SECRET_BLOCK = "# OPENAI_API_KEY=`n# ANTHROPIC_API_KEY=`nGOOGLE_API_KEY=$GOOGLE_API_KEY"
    }
}

Write-Section 'A2A authentication'
Write-Info 'This protects Orchestrator -> DeepAgents A2A endpoints. It is not Databricks/Snowflake/OSDU/MCP authentication.'
$A2A_AUTH_MODE = Read-ChooseNum 'How should Copilot Orchestrator authenticate to this DeepAgents OSS Server?' 1 @(
    'bearer|Bearer token - recommended for production',
    'apikey|API key header - use only if required by customer standard/gateway',
    'none|None - local isolated lab only'
)
$A2A_AUTH_BLOCK = "A2A_AUTH_MODE=$A2A_AUTH_MODE`nA2A_AUTH_PUBLIC_CARD=false"
switch ($A2A_AUTH_MODE) {
    'bearer' {
        if ($GENERATION_MODE -eq 'runtime') {
            $gen = Read-YesNo 'Generate A2A bearer token automatically?' 'yes'
            if ($gen -eq 'yes') { $A2A_BEARER_TOKENS = Get-RandomToken } else { $A2A_BEARER_TOKENS = Read-Prompt 'A2A_BEARER_TOKENS' '' -Secret }
        } else {
            $A2A_BEARER_TOKENS = '<generate-or-provide-bearer-token>'
        }
        $A2A_AUTH_BLOCK += "`nA2A_BEARER_TOKENS=$A2A_BEARER_TOKENS"
    }
    'apikey' {
        $A2A_API_KEY_HEADER = Read-Prompt 'A2A_API_KEY_HEADER' 'X-API-Key'
        if ($GENERATION_MODE -eq 'runtime') {
            $gen = Read-YesNo 'Generate A2A API key automatically?' 'yes'
            if ($gen -eq 'yes') { $A2A_API_KEYS = Get-RandomToken } else { $A2A_API_KEYS = Read-Prompt 'A2A_API_KEYS' '' -Secret }
        } else {
            $A2A_API_KEYS = '<generate-or-provide-api-key>'
        }
        $A2A_AUTH_BLOCK += "`nA2A_API_KEY_HEADER=$A2A_API_KEY_HEADER`nA2A_API_KEYS=$A2A_API_KEYS"
    }
    'none' {
        Write-Warn 'A2A_AUTH_MODE=none is suitable only for isolated lab testing. Do not use this in customer production.'
    }
}

Write-Section 'Runtime agent selection'
Write-Info 'Agent-specific requirements can change by image version. The script uses AGENTS_ENABLED as a CSV allow-list and writes a required-values checklist.'
Show-AgentCatalog

Write-Host ''
$AGENTS_ENABLED = Read-Host -Prompt 'Enter comma-separated agent IDs planned for this deployment. Leave blank to configure later'
$AGENTS_ENABLED = Get-Trim $AGENTS_ENABLED
Split-AgentsCsv $AGENTS_ENABLED

$ALL_KNOWN_AGENTS = ($script:AGENT_IDS -join ',')
$AGENTS_DISABLED = ''
if ($script:SELECTED_AGENTS.Count -eq 0) {
    $AGENTS_ENABLED = ''
    $AGENTS_DISABLED = $ALL_KNOWN_AGENTS
    Write-Warn 'No agents selected. The template will disable the currently documented agents to avoid the default behavior of enabling all agents.'
}

$script:MCP_TEMPLATE_BLOCK = '# Per-agent MCP backends. Set only the integrations you enable.'
$agentsEnabledDisplay = if ([string]::IsNullOrEmpty($AGENTS_ENABLED)) { '<none selected yet>' } else { $AGENTS_ENABLED }
$script:REQUIRED_VALUES = @"
DeepAgents OSS required values checklist
Generated: $(Get-Date)

Core values to confirm:
  IMAGE_TAG
  PUBLIC_BASE_URL reachable by Orchestrator/clients
  POSTGRES_URL
  REDIS_URL
  DEEPAGENTS_MODEL and matching model provider key
  A2A_AUTH_MODE and matching A2A token/API key if auth is enabled
  AGENTS_ENABLED CSV allow-list

Selected/planned agents:
  $agentsEnabledDisplay

Important:
  The docker-compose.yml file is intentionally generic and reads env_file: .env.
  Agent-specific values belong in the env file, not in docker-compose.yml.
  Do not register an agent until its matching MCP server is installed, secured, reachable, and has the required credentials.

Per-agent values to collect:
"@

if ($script:SELECTED_AGENTS.Count -gt 0) {
    foreach ($agent in $script:SELECTED_AGENTS) {
        $prefix = Get-AgentPrefix $agent
        if (-not [string]::IsNullOrEmpty($prefix)) {
            Add-McpTemplateForAgent $agent $prefix
            Add-McpChecklistForAgent $agent $prefix
        } else {
            $script:MCP_TEMPLATE_BLOCK += "`n`n# TODO for ${agent}: unknown/custom agent.`n# Check the official DeepAgents OSS guide or image-specific release notes for required variables."
            Add-McpChecklistForAgent $agent ''
            Write-Warn "Unknown/custom agent '$agent' was added to AGENTS_ENABLED, but no MCP variable prefix is known."
        }
    }
} else {
    $script:MCP_TEMPLATE_BLOCK += "`n# TODO: Set AGENTS_ENABLED after the customer chooses agents and completes MCP setup."
    $script:REQUIRED_VALUES += "`n  No agents selected yet. Set AGENTS_ENABLED after reviewing the official guide and MCP readiness.`n"
}

$AGENT_DESCRIPTIONS_BLOCK = Get-AgentCommentBlock
$DISABLED_LINE = ''
if (-not [string]::IsNullOrEmpty($AGENTS_DISABLED)) { $DISABLED_LINE = "AGENTS_DISABLED=$AGENTS_DISABLED" }

$pgPassLine = if (-not [string]::IsNullOrEmpty($DEEPAGENTS_POSTGRES_PASSWORD)) { "DEEPAGENTS_POSTGRES_PASSWORD=$DEEPAGENTS_POSTGRES_PASSWORD" } else { '' }

$ENV_CONTENT = @"
# ============================================================
# DeepAgents OSS Server ENV template
# Generated by Generate-DeepAgentsOssEnv.ps1
#
# Purpose:
#   Run the DeepAgents OSS A2A server as a separate deployment.
#   This file does not install MCP servers. Enable only agents whose
#   matching MCP servers are installed, secured, and reachable.
# ============================================================

IMAGE_TAG=$IMAGE_TAG
HOST=$HostValue
PORT=$PORT
LOG_LEVEL=$LOG_LEVEL
PUBLIC_BASE_URL=$PUBLIC_BASE_URL

POSTGRES_URL=$POSTGRES_URL
REDIS_URL=$REDIS_URL
$pgPassLine

$A2A_AUTH_BLOCK

$MODEL_SECRET_BLOCK
DEEPAGENTS_MODEL=$DEEPAGENTS_MODEL

$AGENT_DESCRIPTIONS_BLOCK
# Agent selection. AGENTS_ENABLED is a CSV allow-list and should be set deliberately.
AGENTS_ENABLED=$AGENTS_ENABLED
$DISABLED_LINE
# AGENTS_CONFIG_FILE=/etc/deepagents/agents.yaml

$($script:MCP_TEMPLATE_BLOCK)

# Optional common tuning
A2A_THREAD_LOCK_TTL_SECONDS=60
A2A_THREAD_LOCK_WAIT_SECONDS=5.0
MCP_TOOLS_CACHE_TTL_SECONDS=300
JWKS_CACHE_TTL_SECONDS=600
"@

if ($GENERATION_MODE -eq 'runtime') {
    $ENV_FILE = Join-Path $script:OUT_DIR '.env'
} else {
    $ENV_FILE = Join-Path $script:OUT_DIR 'deepagents-env-template.env'
}
Write-OutputFile $ENV_FILE $ENV_CONTENT
Write-OutputFile (Join-Path $script:OUT_DIR 'deepagents-required-values.txt') $script:REQUIRED_VALUES

# ---- docker-compose.yml generation ----
# NOTE: ${IMAGE_TAG} / ${PORT:-8000} / ${DEEPAGENTS_POSTGRES_PASSWORD} are kept
# LITERAL (single-quoted here-strings) so Docker Compose resolves them at runtime.
if ($PERSISTENCE_MODE -eq 'local') {
    $COMPOSE_CONTENT = @'
name: deepagents-oss

volumes:
  deepagents-oss-postgres-data:

services:
  deepagents-oss-redis:
    image: redis:7-alpine
    ports:
      - "6390:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 2s
      retries: 5

  deepagents-oss-postgres:
    image: postgres:16
    ports:
      - "5443:5432"
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
    depends_on:
      deepagents-oss-redis:
        condition: service_healthy
      deepagents-oss-postgres:
        condition: service_healthy
    ports:
      - "${PORT:-8000}:8000"
    env_file:
      - .env
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8000/healthz"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 15s
'@
} else {
    $COMPOSE_CONTENT = @'
name: deepagents-oss

services:
  deepagents-oss:
    image: copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss:${IMAGE_TAG}
    ports:
      - "${PORT:-8000}:8000"
    env_file:
      - .env
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8000/healthz"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 15s
'@
}
Write-OutputFile (Join-Path $script:OUT_DIR 'docker-compose.yml') $COMPOSE_CONTENT

if ($GENERATION_MODE -eq 'runtime') {
    $dockerOk = $false
    if (Test-CommandExists 'docker') {
        try { & docker compose version 1>$null 2>$null; if ($LASTEXITCODE -eq 0) { $dockerOk = $true } } catch { }
    }
    if ($dockerOk) {
        Push-Location $script:OUT_DIR
        try {
            $rendered = Join-Path ([System.IO.Path]::GetTempPath()) 'deepagents-oss-compose-rendered.yml'
            & docker compose config | Out-File -FilePath $rendered -Encoding utf8
            Write-Ok "Docker Compose config validated. Rendered file: $rendered"
        } catch {
            Write-Warn 'docker compose config validation failed.'
        } finally { Pop-Location }
    } else {
        Write-Warn 'Docker Compose V2 not available; skipped compose validation.'
    }
} else {
    Write-Warn 'Template mode selected. docker-compose.yml expects .env, so compose validation is intentionally skipped until you review and copy the template to .env.'
}

Write-Section 'Generated files'
foreach ($f in @($ENV_FILE, (Join-Path $script:OUT_DIR 'deepagents-required-values.txt'), (Join-Path $script:OUT_DIR 'docker-compose.yml'))) {
    if (Test-Path $f) { Get-Item $f | ForEach-Object { Write-Host ("  {0,10}  {1}" -f $_.Length, $_.FullName) } }
}

Write-Host ''
Write-Ok 'DeepAgents OSS files generated.'
Write-Host ''
if ($GENERATION_MODE -eq 'template') {
    Write-Host 'Next:'
    Write-Host '  1. Send deepagents-required-values.txt to the customer/MCP owners.'
    Write-Host "  2. After values are collected, review $ENV_FILE."
    Write-Host '  3. Copy it to .env only when ready:'
    Write-Host "       Copy-Item '$ENV_FILE' '$(Join-Path $script:OUT_DIR '.env')'"
    Write-Host '  4. Start only after .env has valid model, A2A, AGENTS_ENABLED, and MCP values.'
} else {
    Write-Host 'Next:'
    Write-Host "  1. Review $(Join-Path $script:OUT_DIR '.env')."
    Write-Host '  2. Confirm each enabled agent has its matching MCP server URL/token.'
    Write-Host '  3. Start after review:'
    Write-Host "       cd $($script:OUT_DIR)"
    Write-Host '       docker compose up -d'
}

Write-Host ''
Write-Host 'Reference: Please follow the DeepAgents OSS deployment guide for image tags, agent enablement, MCP setup and A2A registration'