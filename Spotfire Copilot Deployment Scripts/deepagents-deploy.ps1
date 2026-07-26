#Requires -Version 5.1
<#
================================================================================
 DeepAgents OSS base configuration generator  (Windows / PowerShell port)
================================================================================
 Faithful PowerShell port of spotfire-deepagents-deploy.sh.

 Windows adaptations (behavior kept identical where possible):
   * `openssl rand` -> .NET RandomNumberGenerator (URL-safe base64, no padding).
   * `sed` / `grep`  -> PowerShell regex / string operations.
   * `chmod 600/700` -> best-effort `icacls` (restrict to current user). NTFS
     ACLs are not identical to POSIX modes; failures are non-fatal.
   * All generated .env / compose / Kubernetes files are written with LF line
     endings so Docker/Compose/kubectl/helm parse them correctly.
   * Compose ${IMAGE_TAG} / ${DEEPAGENTS_HOST_BIND} / ${DEEPAGENTS_HOST_PORT}
     placeholders are kept LITERAL (single-quoted here-strings) so Docker
     Compose resolves them at runtime.
   * The generated Kubernetes helpers (create-secret.sh, helm-install.sh) are
     emitted as bash scripts, matching the Linux generator, because they run on
     a machine that already has kubectl and helm.

 Usage:
   .\deepagents-deploy.ps1
   .\deepagents-deploy.ps1 -ImageTag TAG
   .\deepagents-deploy.ps1 -Kubernetes
   .\deepagents-deploy.ps1 -Upgrade -ImageTag TAG
   .\deepagents-deploy.ps1 -Help

 Environment overrides (parity with the bash script):
   $env:OUT_DIR, $env:DEFAULT_IMAGE_TAG, $env:NO_COLOR
================================================================================
#>

[CmdletBinding()]
param(
    [Alias('h')][switch]$Help,
    [string]$Dir,
    [string]$ImageTag,
    [string]$HostPort,
    [string]$HostBind,
    [string]$PublicBaseUrl,
    [switch]$Local,
    [switch]$External,
    [switch]$Compose,
    [Alias('k8s')][switch]$Kubernetes,
    [string]$ChartVersion,
    [string]$Namespace,
    [switch]$RotateA2aToken,
    [switch]$Upgrade,
    [switch]$NoColor
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Global state (mirrors the bash globals)
# ----------------------------------------------------------------------------
$script:SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:START_DIR  = (Get-Location).Path
$script:OUT_DIR = if ($env:OUT_DIR) { $env:OUT_DIR } else { Join-Path $script:START_DIR 'deepagents-oss-deploy' }
$script:DEFAULT_IMAGE_TAG = if ($env:DEFAULT_IMAGE_TAG) { $env:DEFAULT_IMAGE_TAG } else { '' }
$script:MODE = 'generate'
$script:ROTATE_A2A_CREDENTIAL = if ($RotateA2aToken) { 'yes' } else { 'no' }
$script:UseColor = (-not $NoColor) -and [string]::IsNullOrEmpty($env:NO_COLOR)

$script:ALL_AGENTS = 'osdu_agent,databricks_agent,databricks_genie_agent,snowflake_agent,dv_agent,sf_lib_md_agent,sf_lic_agent,tavily_agent,milvus_agent,ddr_agent'

# Agent catalog rows: Id|Prefix|CoHostPort|Display  (empty port = external MCP).
# The co-host port is the default localhost port that agent's MCP server
# publishes when co-located with this server (see the mcp-servers guides).
$script:AGENT_CATALOG = @(
    [pscustomobject]@{ Id = 'osdu_agent';            Prefix = 'OSDU';      Port = '8063'; Display = 'OSDU' }
    [pscustomobject]@{ Id = 'databricks_agent';      Prefix = 'DATABRICKS'; Port = '8061'; Display = 'Databricks' }
    [pscustomobject]@{ Id = 'dv_agent';              Prefix = 'DV';        Port = '8065'; Display = 'Data Virtualization (DV)' }
    [pscustomobject]@{ Id = 'sf_lib_md_agent';       Prefix = 'SFLIB';     Port = '8062'; Display = 'Spotfire Library Metadata' }
    [pscustomobject]@{ Id = 'sf_lic_agent';          Prefix = 'SFLIC';     Port = '8064'; Display = 'Spotfire License Management' }
    [pscustomobject]@{ Id = 'tavily_agent';          Prefix = 'TAVILY';    Port = '8058'; Display = 'Tavily Web Search' }
    [pscustomobject]@{ Id = 'ddr_agent';             Prefix = 'DDR';       Port = '8060'; Display = 'Daily Drilling Reports (DDR)' }
    [pscustomobject]@{ Id = 'databricks_genie_agent'; Prefix = 'GENIE';    Port = '';     Display = 'Databricks Genie (external MCP)' }
    [pscustomobject]@{ Id = 'snowflake_agent';       Prefix = 'SNOWFLAKE'; Port = '';     Display = 'Snowflake (external MCP)' }
    [pscustomobject]@{ Id = 'milvus_agent';          Prefix = 'MILVUS';    Port = '';     Display = 'Milvus (external MCP)' }
)

# Populated by Set-AgentsAndMcp
$script:AGENTS_ENABLED = ''
$script:AGENTS_DISABLED = $script:ALL_AGENTS
$script:MCP_ENV_BLOCK = ''
$script:MCP_K8S_CONFIG_RAW = ''
$script:MCP_SECRET_KV = ''

# ----------------------------------------------------------------------------
# Output helpers
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
function Assert-Command { param([string]$Name)
    if (-not (Test-CommandExists $Name)) { Invoke-Die "Required command not found: $Name" }
}

# ----------------------------------------------------------------------------
# Generic helpers
# ----------------------------------------------------------------------------
function Get-Trim { param([string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Trim()
}

function Get-StripOuterQuotes { param([string]$Value)
    $v = Get-Trim $Value
    $v = $v -replace "`r$", ''
    if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) {
        $v = $v.Substring(1, $v.Length - 2)
    } elseif ($v.Length -ge 2 -and $v.StartsWith("'") -and $v.EndsWith("'")) {
        $v = $v.Substring(1, $v.Length - 2)
    }
    return $v
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

# Write text using LF line endings (so Docker/Compose/kubectl parse files correctly).
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
    Protect-File $backup
    Write-Info "Backed up $File -> $backup"
}

function Write-OutputFile { param([string]$File, [string]$Content)
    $dir = Split-Path -Parent $File
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Backup-File $File
    Write-TextFileLF -Path $File -Content $Content
    Protect-File $File
    Write-Ok "Wrote $File"
}

# Return the value of KEY in an env file, or $null if absent.
function Get-EnvValue { param([string]$File, [string]$Key)
    if (-not (Test-Path $File)) { return $null }
    $content = [System.IO.File]::ReadAllText($File) -replace "`r`n", "`n"
    $pattern = "(?m)^\s*$([regex]::Escape($Key))\s*=(.*)$"
    $matches = [regex]::Matches($content, $pattern)
    if ($matches.Count -eq 0) { return $null }
    $value = $matches[$matches.Count - 1].Groups[1].Value
    return (Get-StripOuterQuotes $value)
}

# Update or append KEY=VALUE in an existing file (dies if the file is absent).
function Set-EnvValue { param([string]$File, [string]$Key, [string]$Value)
    if (-not (Test-Path $File)) { Invoke-Die "Cannot update missing file: $File" }
    Backup-File $File
    $content = [System.IO.File]::ReadAllText($File) -replace "`r`n", "`n"
    $pattern = "(?m)^\s*$([regex]::Escape($Key))\s*=.*$"
    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, "$Key=$Value")
    } else {
        if (-not $content.EndsWith("`n")) { $content += "`n" }
        $content += "$Key=$Value`n"
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

# ----------------------------------------------------------------------------
# Prompt helpers
# ----------------------------------------------------------------------------
function Read-Prompt {
    param([string]$Label, [string]$Default = '', [switch]$Secret)
    if ($Secret) {
        if (-not [string]::IsNullOrEmpty($Default)) {
            $sec = Read-Host -Prompt "$Label [press Enter to reuse existing]" -AsSecureString
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

function Read-PromptRequired {
    param([string]$Label, [string]$Default = '', [switch]$Secret)
    while ($true) {
        $value = Read-Prompt -Label $Label -Default $Default -Secret:$Secret
        $value = Get-StripOuterQuotes $value
        if (-not [string]::IsNullOrEmpty($value)) { return $value }
        Write-Warn "$Label is required."
    }
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
        Write-Warn "Enter a number from 1 to $($Options.Count)."
    }
}

function Read-YesNo { param([string]$Label, [string]$Default = 'no')
    $defNum = if ($Default -eq 'yes') { 1 } else { 2 }
    return (Read-ChooseNum $Label $defNum @('yes|Yes', 'no|No'))
}

# ----------------------------------------------------------------------------
# Validation helpers
# ----------------------------------------------------------------------------
function Test-ValidPort { param([string]$Value)
    if ($Value -notmatch '^[0-9]+$') { return $false }
    $n = [int]$Value
    return ($n -ge 1 -and $n -le 65535)
}

function Test-ValidBindAddress { param([string]$Value)
    return ($Value -match '^([0-9]{1,3}\.){3}[0-9]{1,3}$')
}

function Read-Port {
    param([string]$Label, [string]$Default = '8000')
    while ($true) {
        $value = Get-Trim (Read-Prompt -Label $Label -Default $Default)
        if (Test-ValidPort $value) { return $value }
        Write-Warn 'Enter a TCP port from 1 to 65535.'
    }
}

function Test-ValidImageTag { param([string]$Value)
    return ($Value -match '^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$')
}

function Test-RuntimeUrl { param([string]$Label, [string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { Invoke-Die "$Label cannot be empty." }
    if ($Value -match '[<>]' -or $Value.Contains('USER:PASS') -or $Value.Contains('POSTGRES_HOST') -or $Value.Contains('REDIS_HOST') -or $Value.Contains('replace-me')) {
        Invoke-Die "$Label still contains a placeholder: $Value"
    }
}

function Show-Usage {
@'
DeepAgents OSS base configuration generator (PowerShell)

Usage:
  .\deepagents-deploy.ps1
  .\deepagents-deploy.ps1 -ImageTag TAG
  .\deepagents-deploy.ps1 -Kubernetes
  .\deepagents-deploy.ps1 -Upgrade -ImageTag TAG

Options:
  -Help, -h                 Show this help.
  -Dir DIR                  Output/deployment directory.
  -ImageTag TAG             Approved DeepAgents OSS image tag.
  -HostPort PORT            Host port mapped to container port 8000 (Compose mode).
  -HostBind ADDRESS         Host interface to publish the port on. Default 127.0.0.1.
  -PublicBaseUrl URL        PUBLIC_BASE_URL. Defaults to http://localhost:<host-port>.
  -Local                    Use local Compose PostgreSQL and Redis.
  -External                 Use external PostgreSQL and Redis.
  -Compose                  Generate a Docker Compose deployment (default).
  -Kubernetes, -k8s         Generate a Kubernetes Helm values bundle instead.
  -ChartVersion VER         Approved Helm chart version (Kubernetes mode).
  -Namespace NS             Kubernetes namespace (Kubernetes mode). Default deepagents-oss.
  -RotateA2aToken           Generate a new bearer token/API key instead of reusing one.
  -Upgrade                  Update IMAGE_TAG in an existing Compose deployment directory.

Notes:
  * The server always listens on container port 8000.
  * Compose mode publishes on 127.0.0.1 by default; use -HostBind to change it.
  * Agents are disabled unless you enable them in the "Agents and MCP wiring" step.
  * Deploy each agent's MCP server first, then enable the agent so DeepAgents can reach it.
  * Kubernetes mode writes values.yaml, create-secret.sh, and helm-install.sh under <dir>\k8s.
  * The script never runs 'docker compose down -v'.
'@ | Write-Host
}

function Set-NormalizedOutDir {
    if (-not [System.IO.Path]::IsPathRooted($script:OUT_DIR)) {
        $script:OUT_DIR = Join-Path $script:START_DIR $script:OUT_DIR
    }
}

# ----------------------------------------------------------------------------
# Compose validation
# ----------------------------------------------------------------------------
function Invoke-ValidateCompose {
    Assert-Command 'docker'
    $composeOk = $false
    try { & docker compose version 1>$null 2>$null; if ($LASTEXITCODE -eq 0) { $composeOk = $true } } catch { }
    if (-not $composeOk) { Invoke-Die 'Docker Compose V2 is required.' }

    $rendered = Join-Path ([System.IO.Path]::GetTempPath()) ("deepagents-oss-compose-rendered.{0}.yml" -f ([System.IO.Path]::GetRandomFileName()))
    # 'docker compose config' interpolates values from .env (including the local
    # PostgreSQL password), so the rendered output is sensitive. Always remove it.
    Push-Location $script:OUT_DIR
    try {
        & docker compose config 1>$rendered 2>$null
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if (Test-Path $rendered) { Remove-Item -LiteralPath $rendered -Force -ErrorAction SilentlyContinue }
    if ($code -ne 0) { Invoke-Die 'docker compose config failed. Review the Compose error above.' }
    Write-Ok 'Docker Compose config validated.'
}

# ----------------------------------------------------------------------------
# Upgrade mode
# ----------------------------------------------------------------------------
function Invoke-Upgrade {
    Set-NormalizedOutDir
    if (-not (Test-Path $script:OUT_DIR -PathType Container)) { Invoke-Die "Deployment directory not found: $($script:OUT_DIR)" }
    $envPath = Join-Path $script:OUT_DIR '.env'
    $composePath = Join-Path $script:OUT_DIR 'docker-compose.yml'
    if (-not (Test-Path $envPath)) { Invoke-Die "Missing $envPath" }
    if (-not (Test-Path $composePath)) { Invoke-Die "Missing $composePath" }
    if ([string]::IsNullOrEmpty($ImageTag)) { Invoke-Die '-Upgrade requires -ImageTag <approved-tag>' }
    if (-not (Test-ValidImageTag $ImageTag)) { Invoke-Die "Invalid image tag: $ImageTag" }

    Write-Section 'DeepAgents OSS upgrade'
    Set-EnvValue $envPath 'IMAGE_TAG' $ImageTag
    Write-Ok "Updated IMAGE_TAG to $ImageTag"

    $hostPort = Get-EnvValue $envPath 'DEEPAGENTS_HOST_PORT'
    if ([string]::IsNullOrEmpty($hostPort)) { $hostPort = '8000' }
    if (-not (Test-ValidPort $hostPort)) { Invoke-Die "Invalid DEEPAGENTS_HOST_PORT in existing .env: $hostPort" }

    Invoke-ValidateCompose
    Write-Host ''
    Write-Host 'Next:'
    Write-Host "  cd $($script:OUT_DIR)"
    Write-Host '  docker login copilotoci.azurecr.io'
    Write-Host '  docker compose up -d'
}

# ----------------------------------------------------------------------------
# Agent catalog lookups and MCP wiring (shared by Compose and Kubernetes modes)
# ----------------------------------------------------------------------------
function Get-AgentRow { param([string]$Id)
    foreach ($row in $script:AGENT_CATALOG) { if ($row.Id -eq $Id) { return $row } }
    return $null
}
function Get-AgentPrefix { param([string]$Id) $r = Get-AgentRow $Id; if ($r) { return $r.Prefix } return '' }
function Get-AgentPort { param([string]$Id) $r = Get-AgentRow $Id; if ($r) { return $r.Port } return '' }
function Get-AgentDisplay { param([string]$Id) $r = Get-AgentRow $Id; if ($r) { return $r.Display } return '' }

# Prefix every line of $Text with $Indent (blank lines stay blank).
function Add-LinePrefix { param([string]$Indent, [string]$Text)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Text -replace "`r`n", "`n").Split("`n")) {
        if ([string]::IsNullOrEmpty($line)) { $out.Add('') } else { $out.Add("$Indent$line") }
    }
    return ($out -join "`n")
}

# Interactive agent selection plus per-agent MCP wiring.
# Target = compose|kubernetes. Sets script-scoped result globals.
function Set-AgentsAndMcp { param([string]$Target)
    $script:AGENTS_ENABLED = ''
    $script:AGENTS_DISABLED = $script:ALL_AGENTS
    $script:MCP_ENV_BLOCK = ''
    $script:MCP_K8S_CONFIG_RAW = ''
    $script:MCP_SECRET_KV = ''

    Write-Section 'Agents and MCP wiring'
    Write-Info 'Deploy each agent''s MCP server first (see the mcp-servers guides), then enable the agent here so DeepAgents can reach it.'
    Write-Info 'Leave the selection blank to generate a base server with every agent disabled.'

    Write-Host ''
    Write-Host 'Available agents:'
    for ($i = 0; $i -lt $script:AGENT_CATALOG.Count; $i++) {
        $row = $script:AGENT_CATALOG[$i]
        if (-not [string]::IsNullOrEmpty($row.Port)) {
            Write-Host ("  {0}) {1}  [{2} | {3} | co-host port {4}]" -f ($i + 1), $row.Display, $row.Id, $row.Prefix, $row.Port)
        } else {
            Write-Host ("  {0}) {1}  [{2} | {3} | external MCP]" -f ($i + 1), $row.Display, $row.Id, $row.Prefix)
        }
    }

    $choice = Get-Trim (Read-Host -Prompt "Agents to enable (comma-separated numbers, 'all', or blank for none)")

    $enabled = New-Object System.Collections.Generic.List[string]
    if ($choice -eq 'all') {
        foreach ($row in $script:AGENT_CATALOG) { $enabled.Add($row.Id) }
    } elseif (-not [string]::IsNullOrEmpty($choice)) {
        foreach ($p in $choice.Split(',')) {
            $p = Get-Trim $p
            if ($p -notmatch '^[0-9]+$') { Write-Warn "Ignoring invalid selection: $p"; continue }
            $n = [int]$p
            if ($n -ge 1 -and $n -le $script:AGENT_CATALOG.Count) {
                $enabled.Add($script:AGENT_CATALOG[$n - 1].Id)
            } else {
                Write-Warn "Ignoring out-of-range selection: $p"
            }
        }
    }

    if ($enabled.Count -eq 0) {
        Write-Warn 'No agents enabled. Generating a base server with every agent disabled.'
        return
    }

    # De-duplicate while preserving order.
    $uniq = New-Object System.Collections.Generic.List[string]
    foreach ($a in $enabled) { if (-not $uniq.Contains($a)) { $uniq.Add($a) } }
    $enabled = $uniq

    $script:AGENTS_ENABLED = ($enabled -join ',')
    $disabled = New-Object System.Collections.Generic.List[string]
    foreach ($allId in $script:ALL_AGENTS.Split(',')) {
        if (-not $enabled.Contains($allId)) { $disabled.Add($allId) }
    }
    $script:AGENTS_DISABLED = ($disabled -join ',')

    foreach ($id2 in $enabled) {
        $pfx2 = Get-AgentPrefix $id2
        $port2 = Get-AgentPort $id2
        $disp2 = Get-AgentDisplay $id2
        Write-Host ''
        Write-Info "MCP wiring for $disp2 ($id2)"

        $urlDefault = ''
        if ($Target -eq 'compose' -and -not [string]::IsNullOrEmpty($port2)) {
            $urlDefault = "http://host.docker.internal:$port2/mcp"
        }
        if (-not [string]::IsNullOrEmpty($urlDefault)) {
            $url = Read-Prompt "${pfx2}_MCP_SERVER_URL" $urlDefault
        } else {
            $url = Read-PromptRequired "${pfx2}_MCP_SERVER_URL (for example https://mcp-host/mcp)" ''
        }
        $url = Get-StripOuterQuotes $url
        $transport = Get-StripOuterQuotes (Read-Prompt "${pfx2}_MCP_SERVER_TRANSPORT" 'streamable-http')
        $token = Get-StripOuterQuotes (Read-Prompt "${pfx2}_MCP_BEARER_TOKEN (blank if the MCP server has no inbound auth)" '' -Secret)

        $script:MCP_ENV_BLOCK += "${pfx2}_MCP_SERVER_URL=$url`n"
        $script:MCP_ENV_BLOCK += "${pfx2}_MCP_SERVER_TRANSPORT=$transport`n"
        if (-not [string]::IsNullOrEmpty($token)) { $script:MCP_ENV_BLOCK += "${pfx2}_MCP_BEARER_TOKEN=$token`n" }

        $lc = $pfx2.ToLower()
        $script:MCP_K8S_CONFIG_RAW += "${lc}McpServerUrl: `"$url`"`n"
        $script:MCP_K8S_CONFIG_RAW += "${lc}McpServerTransport: `"$transport`"`n"
        if (-not [string]::IsNullOrEmpty($token)) { $script:MCP_SECRET_KV += "${pfx2}_MCP_BEARER_TOKEN=$token`n" }
    }
}

# ----------------------------------------------------------------------------
# Kubernetes (Helm) mode: generate a values bundle. No live cluster calls here.
# ----------------------------------------------------------------------------
function Invoke-KubernetesMode {
    $k8sDir = Join-Path $script:OUT_DIR 'k8s'
    New-Item -ItemType Directory -Path $k8sDir -Force | Out-Null

    Write-Section 'Kubernetes (Helm) mode'
    Write-Info "Generates a Helm values bundle for the DeepAgents OSS chart under: $k8sDir"
    Write-Info 'No cluster access is required now. Later, run create-secret.sh then helm-install.sh from a machine with kubectl and helm.'

    while ($true) {
        $imageTag = Get-StripOuterQuotes (Read-Prompt 'Approved DeepAgents OSS image tag' $(if ($ImageTag) { $ImageTag } else { $script:DEFAULT_IMAGE_TAG }))
        if (Test-ValidImageTag $imageTag) { break }
        Write-Warn "Enter an approved OCI image tag using letters, digits, '.', '_' or '-'."
    }
    $chartVersion = Read-PromptRequired 'Approved Helm chart version (--version)' $(if ($ChartVersion) { $ChartVersion } else { '' })
    $k8sNamespace = Read-Prompt 'Kubernetes namespace' $(if ($Namespace) { $Namespace } else { 'deepagents-oss' })
    $k8sSecretName = Read-Prompt 'Name of the Kubernetes Secret for DeepAgents secrets' 'deepagents-oss-secrets'
    $k8sPullSecret = Read-Prompt 'Image pull Secret name (blank if nodes already authenticate to the registry)' ''

    $k8sPersistence = Read-ChooseNum 'How should DeepAgents get PostgreSQL and Redis?' 1 @(
        'external|External/managed PostgreSQL + Redis (app-only chart, production)',
        'bundled|Bundled in-cluster PostgreSQL + Redis (stack chart, POC/dev)'
    )
    $k8sPostgresUrl = ''
    $k8sRedisUrl = ''
    $k8sPgPassword = ''
    if ($k8sPersistence -eq 'bundled') {
        $chartRef = 'oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss-stack'
        $k8sPgPassword = Get-RandomToken
        Write-Info 'Generated a random in-cluster PostgreSQL password for the bundled stack.'
    } else {
        $chartRef = 'oci://copilotoci.azurecr.io/spotfirecopilot/copilot-deepagents-server-oss'
        $k8sPostgresUrl = Read-PromptRequired 'External POSTGRES_URL' '' -Secret
        $k8sRedisUrl = Read-PromptRequired 'External REDIS_URL' '' -Secret
        Test-RuntimeUrl 'POSTGRES_URL' $k8sPostgresUrl
        Test-RuntimeUrl 'REDIS_URL' $k8sRedisUrl
    }

    $publicBaseUrl = Read-PromptRequired 'PUBLIC_BASE_URL (external URL clients use)' 'https://deepagents.example.com'

    Write-Section 'DeepAgents model'
    $llmProvider = Read-ChooseNum 'Which model provider will DeepAgents OSS use?' 1 @(
        'openai|OpenAI', 'anthropic|Anthropic', 'google|Google Gemini API'
    )
    switch ($llmProvider) {
        'openai'    { $providerKeyName = 'OPENAI_API_KEY';    $modelDefault = 'openai:gpt-5.1' }
        'anthropic' { $providerKeyName = 'ANTHROPIC_API_KEY'; $modelDefault = 'anthropic:claude-3-5-sonnet-latest' }
        'google'    { $providerKeyName = 'GOOGLE_API_KEY';    $modelDefault = 'google:gemini-2.0-flash' }
    }
    $providerKeyValue = Read-PromptRequired $providerKeyName '' -Secret
    $deepagentsModel = Read-PromptRequired 'DEEPAGENTS_MODEL' $modelDefault
    if ($deepagentsModel -notlike "${llmProvider}:*") {
        Invoke-Die "DEEPAGENTS_MODEL must start with '${llmProvider}:' for the $llmProvider provider."
    }

    Write-Section 'A2A authentication'
    $a2aAuthMode = Read-ChooseNum 'How should clients authenticate to DeepAgents?' 1 @(
        'bearer|Bearer token (recommended)', 'none|None (isolated lab only)'
    )
    $a2aSecretKey = ''
    $a2aSecretValue = ''
    if ($a2aAuthMode -eq 'bearer') {
        $gen = Read-YesNo 'Generate a new A2A bearer token automatically?' 'yes'
        if ($gen -eq 'yes') { $a2aSecretValue = Get-RandomToken; Write-Ok 'Generated a new A2A bearer token.' }
        else { $a2aSecretValue = Read-PromptRequired 'A2A_BEARER_TOKENS' '' -Secret }
        $a2aSecretKey = 'A2A_BEARER_TOKENS'
    } else {
        Write-Warn 'A2A authentication is disabled. Use this only in an isolated lab.'
    }

    Set-AgentsAndMcp 'kubernetes'

    # Assemble the config: children as raw 'key: "value"' lines (indent added later).
    $cfg = ''
    $cfg += "deepagentsModel: `"$deepagentsModel`"`n"
    $cfg += "publicBaseUrl: `"$publicBaseUrl`"`n"
    $cfg += "a2aAuthMode: `"$a2aAuthMode`"`n"
    $cfg += "a2aAuthPublicCard: `"false`"`n"
    $cfg += "agentsEnabled: `"$($script:AGENTS_ENABLED)`"`n"
    if ($k8sPersistence -eq 'external') {
        $cfg += "postgresUrl: `"$k8sPostgresUrl`"`n"
        $cfg += "redisUrl: `"$k8sRedisUrl`"`n"
    }
    if (-not [string]::IsNullOrEmpty($script:MCP_K8S_CONFIG_RAW)) { $cfg += $script:MCP_K8S_CONFIG_RAW }
    $cfg = $cfg.TrimEnd("`n")

    $pullLine = ''
    if (-not [string]::IsNullOrEmpty($k8sPullSecret)) { $pullLine = "  - name: `"$k8sPullSecret`"" }

    $valuesFile = Join-Path $k8sDir 'values.yaml'
    $vlines = New-Object System.Collections.Generic.List[string]
    if ($k8sPersistence -eq 'bundled') {
        $vlines.Add('# DeepAgents OSS full-stack Helm values (app + in-cluster PostgreSQL + Redis).')
        $vlines.Add("# Chart: $chartRef")
        $vlines.Add("# Per-agent MCP config keys follow the OSS deployment guide's documented convention.")
        $vlines.Add('copilot-deepagents-server-oss:')
        $vlines.Add('  image:')
        $vlines.Add('    registry: copilotoci.azurecr.io')
        $vlines.Add('    repository: spotfirecopilot/copilot-deepagents-server-oss')
        $vlines.Add("    tag: `"$imageTag`"")
        if (-not [string]::IsNullOrEmpty($pullLine)) {
            $vlines.Add('  imagePullSecrets:')
            $vlines.Add("  $pullLine")
        }
        $vlines.Add('  config:')
        $vlines.Add((Add-LinePrefix '    ' $cfg))
        $vlines.Add('  secret:')
        $vlines.Add('    create: false')
        $vlines.Add("    existingSecretName: `"$k8sSecretName`"")
        $vlines.Add('')
        $vlines.Add('postgresql:')
        $vlines.Add('  enabled: true')
        $vlines.Add('  postgres:')
        $vlines.Add("    password: `"$k8sPgPassword`"")
        $vlines.Add('')
        $vlines.Add('redis:')
        $vlines.Add('  enabled: true')
    } else {
        $vlines.Add('# DeepAgents OSS app-only Helm values (bring-your-own PostgreSQL + Redis).')
        $vlines.Add("# Chart: $chartRef")
        $vlines.Add("# Per-agent MCP config keys follow the OSS deployment guide's documented convention.")
        $vlines.Add('image:')
        $vlines.Add('  registry: copilotoci.azurecr.io')
        $vlines.Add('  repository: spotfirecopilot/copilot-deepagents-server-oss')
        $vlines.Add("  tag: `"$imageTag`"")
        if (-not [string]::IsNullOrEmpty($pullLine)) {
            $vlines.Add('imagePullSecrets:')
            $vlines.Add($pullLine)
        }
        $vlines.Add('config:')
        $vlines.Add((Add-LinePrefix '  ' $cfg))
        $vlines.Add('secret:')
        $vlines.Add('  create: false')
        $vlines.Add("  existingSecretName: `"$k8sSecretName`"")
    }
    Write-OutputFile $valuesFile ($vlines -join "`n")

    $secretFile = Join-Path $k8sDir 'create-secret.sh'
    $slines = New-Object System.Collections.Generic.List[string]
    $slines.Add('#!/usr/bin/env bash')
    $slines.Add('set -Eeuo pipefail')
    $slines.Add('# Creates or updates the Kubernetes Secret referenced by values.yaml (secret.existingSecretName).')
    $slines.Add('# Requires kubectl configured against the target cluster.')
    $slines.Add("NAMESPACE=`"$k8sNamespace`"")
    $slines.Add("SECRET_NAME=`"$k8sSecretName`"")
    $slines.Add('kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -')
    $slines.Add('kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \')
    $slines.Add("  --from-literal=$providerKeyName='$providerKeyValue' \")
    if (-not [string]::IsNullOrEmpty($a2aSecretKey)) {
        $slines.Add("  --from-literal=$a2aSecretKey='$a2aSecretValue' \")
    }
    foreach ($kv in ($script:MCP_SECRET_KV -replace "`r`n", "`n").Split("`n")) {
        if ([string]::IsNullOrEmpty($kv)) { continue }
        $idx = $kv.IndexOf('=')
        if ($idx -lt 1) { continue }
        $sk = $kv.Substring(0, $idx)
        $sv = $kv.Substring($idx + 1)
        $slines.Add("  --from-literal=$sk='$sv' \")
    }
    $slines.Add('  --dry-run=client -o yaml | kubectl apply -f -')
    Write-OutputFile $secretFile ($slines -join "`n")

    $installFile = Join-Path $k8sDir 'helm-install.sh'
    $ilines = New-Object System.Collections.Generic.List[string]
    $ilines.Add('#!/usr/bin/env bash')
    $ilines.Add('set -Eeuo pipefail')
    $ilines.Add('# Installs or upgrades the DeepAgents OSS release. Run create-secret.sh first.')
    $ilines.Add("NAMESPACE=`"$k8sNamespace`"")
    $ilines.Add('helm registry login copilotoci.azurecr.io')
    $ilines.Add('helm upgrade --install deepagents-oss \')
    $ilines.Add("  $chartRef \")
    $ilines.Add("  --version `"$chartVersion`" \")
    $ilines.Add('  --namespace "$NAMESPACE" \')
    $ilines.Add('  --create-namespace \')
    $ilines.Add('  -f "$(dirname "$0")/values.yaml"')
    Write-OutputFile $installFile ($ilines -join "`n")

    $summaryFile = Join-Path $k8sDir 'deepagents-k8s-summary.txt'
    $enabledDisplay = if ([string]::IsNullOrEmpty($script:AGENTS_ENABLED)) { '<none>' } else { $script:AGENTS_ENABLED }
    $sumlines = @(
        'DeepAgents OSS Kubernetes (Helm) bundle'
        "Generated: $(Get-Date)"
        ''
        "Namespace:      $k8sNamespace"
        "Chart:          $chartRef"
        "Chart version:  $chartVersion"
        "Image tag:      $imageTag"
        "Persistence:    $k8sPersistence"
        "Model:          $deepagentsModel"
        "A2A auth:       $a2aAuthMode"
        "Agents enabled: $enabledDisplay"
        "Secret name:    $k8sSecretName"
        ''
        'Files:'
        "  $valuesFile"
        "  $secretFile"
        "  $installFile"
    )
    Write-OutputFile $summaryFile ($sumlines -join "`n")

    Write-Section 'Completed'
    Write-Ok "DeepAgents OSS Kubernetes bundle is ready in $k8sDir"
    Write-Host ''
    Write-Host 'Next:'
    Write-Host "  1) Review $valuesFile (per-agent MCP config keys follow the OSS deployment guide)."
    Write-Host "  2) bash `"$secretFile`"      # create the Kubernetes Secret"
    Write-Host "  3) bash `"$installFile`"     # helm upgrade --install"
    Write-Host "  4) kubectl -n $k8sNamespace get pods"
}

# ============================================================================
# main
# ============================================================================
if ($Help) { $script:MODE = 'help' }
if ($Upgrade) { $script:MODE = 'upgrade' }
if (-not [string]::IsNullOrEmpty($Dir)) { $script:OUT_DIR = $Dir }
if (-not [string]::IsNullOrEmpty($HostBind) -and -not (Test-ValidBindAddress $HostBind)) { Invoke-Die "Invalid -HostBind address: $HostBind" }

if ($script:MODE -eq 'help') { Show-Usage; exit 0 }
if ($script:MODE -eq 'upgrade') { Invoke-Upgrade; exit 0 }

Set-NormalizedOutDir
New-Item -ItemType Directory -Path $script:OUT_DIR -Force | Out-Null

Write-Section 'DeepAgents OSS deployment'
Write-Info 'Generates DeepAgents server configuration for Docker Compose or Kubernetes, including optional agent enablement and MCP wiring.'
$script:OUT_DIR = Read-Prompt 'Output directory' $script:OUT_DIR
Set-NormalizedOutDir
New-Item -ItemType Directory -Path $script:OUT_DIR -Force | Out-Null
$EXISTING_ENV = Join-Path $script:OUT_DIR '.env'

Write-Section 'Deployment target'
if ($Compose) {
    $DEPLOY_TARGET = 'compose'
} elseif ($Kubernetes) {
    $DEPLOY_TARGET = 'kubernetes'
} else {
    $DEPLOY_TARGET = Read-ChooseNum 'How do you want to deploy the DeepAgents server?' 1 @(
        'compose|Docker Compose on a single host',
        'kubernetes|Kubernetes via a generated Helm values bundle'
    )
}
if ($DEPLOY_TARGET -eq 'kubernetes') {
    Invoke-KubernetesMode
    exit 0
}

# ----------------------------------------------------------------------------
# Image and server settings
# ----------------------------------------------------------------------------
Write-Section 'Image and server settings'
$EXISTING_IMAGE_TAG = Get-EnvValue $EXISTING_ENV 'IMAGE_TAG'
$IMAGE_TAG_DEFAULT = if ($ImageTag) { $ImageTag } elseif ($EXISTING_IMAGE_TAG) { $EXISTING_IMAGE_TAG } else { $script:DEFAULT_IMAGE_TAG }
while ($true) {
    $IMAGE_TAG = Get-StripOuterQuotes (Read-Prompt 'Approved DeepAgents OSS image tag' $IMAGE_TAG_DEFAULT)
    if (Test-ValidImageTag $IMAGE_TAG) { break }
    Write-Warn "Enter an approved OCI image tag using letters, digits, '.', '_' or '-'."
}

$EXISTING_HOST = Get-EnvValue $EXISTING_ENV 'HOST'
if ([string]::IsNullOrEmpty($EXISTING_HOST)) { $EXISTING_HOST = '0.0.0.0' }
$HostValue = Get-StripOuterQuotes (Read-Prompt 'Server bind address (HOST)' $EXISTING_HOST)
if ([string]::IsNullOrEmpty($HostValue)) { Invoke-Die 'HOST cannot be empty.' }

# Keep the application port fixed. A separate host-published port avoids the
# previous host-port/container-port mismatch.
$PORT = 8000
$EXISTING_HOST_PORT = Get-EnvValue $EXISTING_ENV 'DEEPAGENTS_HOST_PORT'
if ([string]::IsNullOrEmpty($EXISTING_HOST_PORT)) {
    $OLD_PORT = Get-EnvValue $EXISTING_ENV 'PORT'
    if (-not [string]::IsNullOrEmpty($OLD_PORT) -and $OLD_PORT -ne '8000' -and (Test-ValidPort $OLD_PORT)) {
        $EXISTING_HOST_PORT = $OLD_PORT
        Write-Info "Migrating the previous PORT=$OLD_PORT value to DEEPAGENTS_HOST_PORT; container PORT remains 8000."
    }
}
$HOST_PORT_DEFAULT = if ($HostPort) { $HostPort } elseif ($EXISTING_HOST_PORT) { $EXISTING_HOST_PORT } else { '8000' }
$DEEPAGENTS_HOST_PORT = Read-Port 'Host-published DeepAgents port' $HOST_PORT_DEFAULT

# Publish the port on loopback by default so the server is not exposed to the
# network unless the operator explicitly opts in.
$EXISTING_HOST_BIND = Get-EnvValue $EXISTING_ENV 'DEEPAGENTS_HOST_BIND'
if (-not [string]::IsNullOrEmpty($HostBind)) {
    $DEEPAGENTS_HOST_BIND = $HostBind
} else {
    $bindDefaultNum = 1
    if ($EXISTING_HOST_BIND -eq '0.0.0.0') { $bindDefaultNum = 2 }
    $DEEPAGENTS_HOST_BIND = Read-ChooseNum 'Which host interface should publish the DeepAgents port?' $bindDefaultNum @(
        '127.0.0.1|Loopback only - safest; reach it through a reverse proxy or SSH tunnel',
        '0.0.0.0|All interfaces - exposes the port to the network'
    )
}
if ($DEEPAGENTS_HOST_BIND -ne '127.0.0.1') {
    Write-Warn "The DeepAgents port will be published on $DEEPAGENTS_HOST_BIND, reachable beyond this host. Ensure A2A authentication and firewall rules are enforced."
}

$EXISTING_PUBLIC_BASE_URL = Get-EnvValue $EXISTING_ENV 'PUBLIC_BASE_URL'
$PUBLIC_BASE_URL_DEFAULT = if ($PublicBaseUrl) { $PublicBaseUrl } elseif ($EXISTING_PUBLIC_BASE_URL) { $EXISTING_PUBLIC_BASE_URL } else { "http://localhost:$DEEPAGENTS_HOST_PORT" }
$PUBLIC_BASE_URL = Read-PromptRequired 'PUBLIC_BASE_URL' $PUBLIC_BASE_URL_DEFAULT

$EXISTING_LOG_LEVEL = Get-EnvValue $EXISTING_ENV 'LOG_LEVEL'
if ([string]::IsNullOrEmpty($EXISTING_LOG_LEVEL)) { $EXISTING_LOG_LEVEL = 'INFO' }
$LOG_LEVEL = (Read-Prompt 'LOG_LEVEL' $EXISTING_LOG_LEVEL).ToUpper()
switch ($LOG_LEVEL) {
    'DEBUG' {} 'INFO' {} 'WARNING' {} 'ERROR' {} 'CRITICAL' {}
    default { Invoke-Die "Invalid LOG_LEVEL: $LOG_LEVEL" }
}

# ----------------------------------------------------------------------------
# Persistence
# ----------------------------------------------------------------------------
Write-Section 'Persistence'
$EXISTING_POSTGRES_URL = Get-EnvValue $EXISTING_ENV 'POSTGRES_URL'
$EXISTING_REDIS_URL = Get-EnvValue $EXISTING_ENV 'REDIS_URL'
$EXISTING_PERSISTENCE = 'local'
if (-not [string]::IsNullOrEmpty($EXISTING_POSTGRES_URL) -and -not $EXISTING_POSTGRES_URL.Contains('@deepagents-oss-postgres:')) {
    $EXISTING_PERSISTENCE = 'external'
}

if ($Local) {
    $PERSISTENCE_MODE = 'local'
} elseif ($External) {
    $PERSISTENCE_MODE = 'external'
} else {
    $persistenceDefaultNum = 1
    if ($EXISTING_PERSISTENCE -eq 'external') { $persistenceDefaultNum = 2 }
    $PERSISTENCE_MODE = Read-ChooseNum 'How should DeepAgents use PostgreSQL and Redis?' $persistenceDefaultNum @(
        'local|Local Docker Compose PostgreSQL + Redis (dev/test or small non-production)',
        'external|External/managed PostgreSQL + Redis (production pattern)'
    )
}

$DEEPAGENTS_POSTGRES_PASSWORD = ''
switch ($PERSISTENCE_MODE) {
    'local' {
        $EXISTING_POSTGRES_PASSWORD = Get-EnvValue $EXISTING_ENV 'DEEPAGENTS_POSTGRES_PASSWORD'
        if (-not [string]::IsNullOrEmpty($EXISTING_POSTGRES_PASSWORD)) {
            $DEEPAGENTS_POSTGRES_PASSWORD = $EXISTING_POSTGRES_PASSWORD
            Write-Ok 'Reusing the existing local PostgreSQL password.'
        } else {
            # A persisted volume initialized with an unknown password must not be
            # paired with a newly generated env password.
            $volumeExists = $false
            if (Test-CommandExists 'docker') {
                try { & docker volume inspect deepagents-oss_deepagents-oss-postgres-data 1>$null 2>$null; if ($LASTEXITCODE -eq 0) { $volumeExists = $true } } catch { }
            }
            if ($volumeExists) {
                Invoke-Die "The existing DeepAgents PostgreSQL volume was found, but no password exists in $EXISTING_ENV. Restore the original .env/password or intentionally remove the volume outside this script."
            }
            $DEEPAGENTS_POSTGRES_PASSWORD = Get-RandomToken
            Write-Ok 'Generated a new local PostgreSQL password.'
        }
        $POSTGRES_URL = "postgresql://postgres:${DEEPAGENTS_POSTGRES_PASSWORD}@deepagents-oss-postgres:5432/deepagents_checkpoints"
        $REDIS_URL = 'redis://deepagents-oss-redis:6379/0'
    }
    'external' {
        $POSTGRES_URL = Read-PromptRequired 'External POSTGRES_URL' $EXISTING_POSTGRES_URL -Secret
        $REDIS_URL = Read-PromptRequired 'External REDIS_URL' $EXISTING_REDIS_URL -Secret
        Test-RuntimeUrl 'POSTGRES_URL' $POSTGRES_URL
        Test-RuntimeUrl 'REDIS_URL' $REDIS_URL
        $DEEPAGENTS_POSTGRES_PASSWORD = ''
    }
    default { Invoke-Die "Unsupported persistence mode: $PERSISTENCE_MODE" }
}

# ----------------------------------------------------------------------------
# Model provider
# ----------------------------------------------------------------------------
Write-Section 'DeepAgents model'
$EXISTING_MODEL = Get-EnvValue $EXISTING_ENV 'DEEPAGENTS_MODEL'
$EXISTING_PROVIDER = 'openai'
switch -Wildcard ($EXISTING_MODEL) {
    'anthropic:*' { $EXISTING_PROVIDER = 'anthropic' }
    'google:*'    { $EXISTING_PROVIDER = 'google' }
    'openai:*'    { $EXISTING_PROVIDER = 'openai' }
}
$providerDefaultNum = 1
if ($EXISTING_PROVIDER -eq 'anthropic') { $providerDefaultNum = 2 }
if ($EXISTING_PROVIDER -eq 'google') { $providerDefaultNum = 3 }
$LLM_PROVIDER = Read-ChooseNum 'Which model provider will DeepAgents OSS use?' $providerDefaultNum @(
    'openai|OpenAI', 'anthropic|Anthropic', 'google|Google Gemini API'
)

$MODEL_SECRET_BLOCK = ''
switch ($LLM_PROVIDER) {
    'openai' {
        $EXISTING_PROVIDER_KEY = Get-EnvValue $EXISTING_ENV 'OPENAI_API_KEY'
        $OPENAI_API_KEY = Read-PromptRequired 'OPENAI_API_KEY' $EXISTING_PROVIDER_KEY -Secret
        $MODEL_DEFAULT = $EXISTING_MODEL
        if ($MODEL_DEFAULT -notlike 'openai:*') { $MODEL_DEFAULT = 'openai:gpt-5.1' }
        $DEEPAGENTS_MODEL = Read-PromptRequired 'DEEPAGENTS_MODEL' $MODEL_DEFAULT
        if ($DEEPAGENTS_MODEL -notlike 'openai:*') { Invoke-Die 'OpenAI selection requires DEEPAGENTS_MODEL=openai:<model>.' }
        $MODEL_SECRET_BLOCK = "OPENAI_API_KEY=$OPENAI_API_KEY`n# ANTHROPIC_API_KEY=`n# GOOGLE_API_KEY="
    }
    'anthropic' {
        $EXISTING_PROVIDER_KEY = Get-EnvValue $EXISTING_ENV 'ANTHROPIC_API_KEY'
        $ANTHROPIC_API_KEY = Read-PromptRequired 'ANTHROPIC_API_KEY' $EXISTING_PROVIDER_KEY -Secret
        $MODEL_DEFAULT = $EXISTING_MODEL
        if ($MODEL_DEFAULT -notlike 'anthropic:*') { $MODEL_DEFAULT = 'anthropic:claude-3-5-sonnet-latest' }
        $DEEPAGENTS_MODEL = Read-PromptRequired 'DEEPAGENTS_MODEL' $MODEL_DEFAULT
        if ($DEEPAGENTS_MODEL -notlike 'anthropic:*') { Invoke-Die 'Anthropic selection requires DEEPAGENTS_MODEL=anthropic:<model>.' }
        $MODEL_SECRET_BLOCK = "# OPENAI_API_KEY=`nANTHROPIC_API_KEY=$ANTHROPIC_API_KEY`n# GOOGLE_API_KEY="
    }
    'google' {
        $EXISTING_PROVIDER_KEY = Get-EnvValue $EXISTING_ENV 'GOOGLE_API_KEY'
        $GOOGLE_API_KEY = Read-PromptRequired 'GOOGLE_API_KEY' $EXISTING_PROVIDER_KEY -Secret
        $MODEL_DEFAULT = $EXISTING_MODEL
        if ($MODEL_DEFAULT -notlike 'google:*') { $MODEL_DEFAULT = 'google:gemini-2.0-flash' }
        $DEEPAGENTS_MODEL = Read-PromptRequired 'DEEPAGENTS_MODEL' $MODEL_DEFAULT
        if ($DEEPAGENTS_MODEL -notlike 'google:*') { Invoke-Die 'Google selection requires DEEPAGENTS_MODEL=google:<model>.' }
        $MODEL_SECRET_BLOCK = "# OPENAI_API_KEY=`n# ANTHROPIC_API_KEY=`nGOOGLE_API_KEY=$GOOGLE_API_KEY"
    }
    default { Invoke-Die "Unsupported model provider: $LLM_PROVIDER" }
}

# ----------------------------------------------------------------------------
# A2A authentication
# ----------------------------------------------------------------------------
Write-Section 'A2A authentication'
$EXISTING_A2A_MODE = Get-EnvValue $EXISTING_ENV 'A2A_AUTH_MODE'
if ([string]::IsNullOrEmpty($EXISTING_A2A_MODE)) { $EXISTING_A2A_MODE = 'bearer' }
$a2aDefaultNum = 1
if ($EXISTING_A2A_MODE -eq 'apikey') { $a2aDefaultNum = 2 }
if ($EXISTING_A2A_MODE -eq 'none') { $a2aDefaultNum = 3 }
$A2A_AUTH_MODE = Read-ChooseNum 'How should clients authenticate to DeepAgents?' $a2aDefaultNum @(
    'bearer|Bearer token (recommended)',
    'apikey|API key header',
    'none|None (isolated local lab only)'
)

$A2A_AUTH_BLOCK = "A2A_AUTH_MODE=$A2A_AUTH_MODE`nA2A_AUTH_PUBLIC_CARD=false"
switch ($A2A_AUTH_MODE) {
    'bearer' {
        $EXISTING_A2A_VALUE = Get-EnvValue $EXISTING_ENV 'A2A_BEARER_TOKENS'
        if (-not [string]::IsNullOrEmpty($EXISTING_A2A_VALUE) -and $script:ROTATE_A2A_CREDENTIAL -ne 'yes') {
            $A2A_BEARER_TOKENS = $EXISTING_A2A_VALUE
            Write-Ok 'Reusing the existing A2A bearer token.'
        } else {
            $GENERATE_A2A = Read-YesNo 'Generate a new A2A bearer token automatically?' 'yes'
            if ($GENERATE_A2A -eq 'yes') { $A2A_BEARER_TOKENS = Get-RandomToken }
            else { $A2A_BEARER_TOKENS = Read-PromptRequired 'A2A_BEARER_TOKENS' '' -Secret }
            if (-not [string]::IsNullOrEmpty($EXISTING_A2A_VALUE)) { Write-Warn 'The A2A bearer token was rotated. Update every registered client that uses the old token.' }
        }
        $A2A_AUTH_BLOCK += "`nA2A_BEARER_TOKENS=$A2A_BEARER_TOKENS"
    }
    'apikey' {
        $EXISTING_HEADER = Get-EnvValue $EXISTING_ENV 'A2A_API_KEY_HEADER'
        if ([string]::IsNullOrEmpty($EXISTING_HEADER)) { $EXISTING_HEADER = 'X-API-Key' }
        $A2A_API_KEY_HEADER = Read-PromptRequired 'A2A_API_KEY_HEADER' $EXISTING_HEADER
        $EXISTING_A2A_VALUE = Get-EnvValue $EXISTING_ENV 'A2A_API_KEYS'
        if (-not [string]::IsNullOrEmpty($EXISTING_A2A_VALUE) -and $script:ROTATE_A2A_CREDENTIAL -ne 'yes') {
            $A2A_API_KEYS = $EXISTING_A2A_VALUE
            Write-Ok 'Reusing the existing A2A API key.'
        } else {
            $GENERATE_A2A = Read-YesNo 'Generate a new A2A API key automatically?' 'yes'
            if ($GENERATE_A2A -eq 'yes') { $A2A_API_KEYS = Get-RandomToken }
            else { $A2A_API_KEYS = Read-PromptRequired 'A2A_API_KEYS' '' -Secret }
            if (-not [string]::IsNullOrEmpty($EXISTING_A2A_VALUE)) { Write-Warn 'The A2A API key was rotated. Update every registered client that uses the old key.' }
        }
        $A2A_AUTH_BLOCK += "`nA2A_API_KEY_HEADER=$A2A_API_KEY_HEADER`nA2A_API_KEYS=$A2A_API_KEYS"
    }
    'none' {
        Write-Warn 'A2A authentication is disabled. Use this only in an isolated local lab.'
        if ($DEEPAGENTS_HOST_BIND -ne '127.0.0.1') { Write-Warn "A2A auth is 'none' while the port is published on $DEEPAGENTS_HOST_BIND; anyone who can reach it has unauthenticated access." }
    }
    default { Invoke-Die "Unsupported A2A authentication mode: $A2A_AUTH_MODE" }
}

Set-AgentsAndMcp 'compose'

# ----------------------------------------------------------------------------
# Generate .env and Compose
# ----------------------------------------------------------------------------
Write-Section 'Generate deployment files'
$POSTGRES_PASSWORD_LINE = ''
if (-not [string]::IsNullOrEmpty($DEEPAGENTS_POSTGRES_PASSWORD)) {
    $POSTGRES_PASSWORD_LINE = "DEEPAGENTS_POSTGRES_PASSWORD=$DEEPAGENTS_POSTGRES_PASSWORD"
}

$ENV_CONTENT = @"
# ============================================================
# DeepAgents OSS base server environment
# Generated by deepagents-deploy.ps1
#
# Agents are enabled only if selected during generation.
# Enable additional agents later only after their MCP servers are ready.
# ============================================================

IMAGE_TAG=$IMAGE_TAG
HOST=$HostValue
PORT=8000
DEEPAGENTS_HOST_PORT=$DEEPAGENTS_HOST_PORT
DEEPAGENTS_HOST_BIND=$DEEPAGENTS_HOST_BIND
LOG_LEVEL=$LOG_LEVEL
PUBLIC_BASE_URL=$PUBLIC_BASE_URL

POSTGRES_URL=$POSTGRES_URL
REDIS_URL=$REDIS_URL
$POSTGRES_PASSWORD_LINE

$A2A_AUTH_BLOCK

$MODEL_SECRET_BLOCK
DEEPAGENTS_MODEL=$DEEPAGENTS_MODEL

# Agent allow-list and per-agent MCP wiring (configured interactively).
AGENTS_ENABLED=$($script:AGENTS_ENABLED)
AGENTS_DISABLED=$($script:AGENTS_DISABLED)
# AGENTS_CONFIG_FILE=/etc/deepagents/agents.yaml
$($script:MCP_ENV_BLOCK)

# Optional common tuning
A2A_THREAD_LOCK_TTL_SECONDS=60
A2A_THREAD_LOCK_WAIT_SECONDS=5.0
MCP_TOOLS_CACHE_TTL_SECONDS=300
JWKS_CACHE_TTL_SECONDS=600
"@
Write-OutputFile (Join-Path $script:OUT_DIR '.env') $ENV_CONTENT

if ($PERSISTENCE_MODE -eq 'local') {
    $COMPOSE_CONTENT = @'
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
'@
} else {
    $COMPOSE_CONTENT = @'
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
'@
}
Write-OutputFile (Join-Path $script:OUT_DIR 'docker-compose.yml') $COMPOSE_CONTENT

$enabledDisplay = if ([string]::IsNullOrEmpty($script:AGENTS_ENABLED)) { '<none>' } else { $script:AGENTS_ENABLED }
$SUMMARY_CONTENT = @"
DeepAgents OSS base deployment
Generated: $(Get-Date)

Deployment directory: $($script:OUT_DIR)
Image tag: $IMAGE_TAG
Host URL: http://localhost:$DEEPAGENTS_HOST_PORT
Published interface: $DEEPAGENTS_HOST_BIND
Public base URL: $PUBLIC_BASE_URL
Persistence: $PERSISTENCE_MODE
Model: $DEEPAGENTS_MODEL
A2A authentication: $A2A_AUTH_MODE

Agents:
 Enabled:  $enabledDisplay
 Disabled: $($script:AGENTS_DISABLED)
 Per-agent MCP endpoints are configured in .env (<PREFIX>_MCP_SERVER_URL/TRANSPORT/BEARER_TOKEN).

Files:
 $(Join-Path $script:OUT_DIR '.env')
 $(Join-Path $script:OUT_DIR 'docker-compose.yml')

Validation after startup:
 curl -fsS http://localhost:$DEEPAGENTS_HOST_PORT/healthz
 curl -fsS http://localhost:$DEEPAGENTS_HOST_PORT/readyz
"@
Write-OutputFile (Join-Path $script:OUT_DIR 'deepagents-deployment-summary.txt') $SUMMARY_CONTENT

$dockerComposeOk = $false
if (Test-CommandExists 'docker') {
    try { & docker compose version 1>$null 2>$null; if ($LASTEXITCODE -eq 0) { $dockerComposeOk = $true } } catch { }
}
if ($dockerComposeOk) {
    Invoke-ValidateCompose
} else {
    Write-Warn 'Docker Compose V2 is unavailable, so Compose validation was skipped.'
}

Write-Section 'Completed'
Write-Ok "DeepAgents OSS base deployment files are ready in $($script:OUT_DIR)"
if ([string]::IsNullOrEmpty($script:AGENTS_ENABLED)) {
    Write-Warn 'No agents are enabled. Re-run and select agents once their MCP servers are ready.'
} else {
    Write-Info "Enabled agents: $($script:AGENTS_ENABLED). Confirm each agent's MCP server is running and reachable."
}

Write-Host ''
Write-Host 'Next:'
Write-Host "  cd $($script:OUT_DIR)"
Write-Host '  docker login copilotoci.azurecr.io'
Write-Host '  docker compose up -d'
Write-Host "  curl -fsS http://localhost:$DEEPAGENTS_HOST_PORT/healthz"
Write-Host "  curl -fsS http://localhost:$DEEPAGENTS_HOST_PORT/readyz"
