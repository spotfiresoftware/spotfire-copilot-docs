#Requires -Version 5.1
<#
==============================================================================
 Spotfire Copilot — Azure Container Apps Deployment Script (Windows / PowerShell)
 Version: 2.3.x

 Usage:
   .\spotfire-copilot-deploy-aca.ps1
   .\spotfire-copilot-deploy-aca.ps1 -Dir C:\spotfire-copilot\backend
   .\spotfire-copilot-deploy-aca.ps1 -Help

 Flow:
   Phase 1  — Collect all configuration (same questions as cloud mode)
   Phase 2  — Generate cloud-env-checklist.txt
   Phase 3  — Collect ACA-specific inputs
   Phase 4  — Check if Azure CLI is installed
              YES → deploy directly (or write + offer to run)
              NO  → write azcli-deploy.sh for Azure Cloud Shell
==============================================================================
#>

[CmdletBinding()]
param(
    [string]$Dir       = '',
    [string]$ImageTag  = '',
    [switch]$Yes,
    [switch]$NoColor,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# ── directories ───────────────────────────────────────────────────────────────
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$StartDir    = (Get-Location).Path
$DefaultTag  = if ($env:DEFAULT_IMAGE_TAG) { $env:DEFAULT_IMAGE_TAG } else { '2.3.4' }
if ($ImageTag) { $DefaultTag = $ImageTag }
$CopilotRoot = if ($env:COPILOT_ROOT_DIR) { $env:COPILOT_ROOT_DIR } else { Join-Path $StartDir 'spotfire-copilot' }
$OutDirExplicit = $false
if ($Dir) { $OutDir = $Dir; $OutDirExplicit = $true }
else      { $OutDir = Join-Path (Join-Path $CopilotRoot $DefaultTag) 'backend' }

if ($Help) {
    Write-Host "Spotfire Copilot Azure Container Apps Deployment Script"
    Write-Host "Usage: .\spotfire-copilot-deploy-aca.ps1 [-Dir PATH] [-ImageTag TAG] [-Yes] [-NoColor]"
    exit 0
}

# ── colour helpers ─────────────────────────────────────────────────────────
$UseColor = -not $NoColor
function Write-Section([string]$Text) {
    Write-Host ""
    if ($UseColor) { Write-Host "== $Text ==" -ForegroundColor Magenta }
    else { Write-Host "== $Text ==" }
}
function Write-Info([string]$Text) {
    if ($UseColor) { Write-Host 'INFO:' -ForegroundColor Cyan -NoNewline; Write-Host " $Text" }
    else { Write-Host "INFO: $Text" }
}
function Write-Ok([string]$Text) {
    if ($UseColor) { Write-Host 'OK:' -ForegroundColor Green -NoNewline; Write-Host " $Text" }
    else { Write-Host "OK: $Text" }
}
function Write-Warn([string]$Text) {
    if ($UseColor) { Write-Host 'WARN:' -ForegroundColor Yellow -NoNewline; Write-Host " $Text" }
    else { Write-Host "WARN: $Text" }
}
function Invoke-Die([string]$Text) {
    if ($UseColor) { Write-Host 'ERROR:' -ForegroundColor Red -NoNewline; Write-Host " $Text" }
    else { Write-Host "ERROR: $Text" }
    exit 1
}

# ── prompt helpers ────────────────────────────────────────────────────────────
function Read-Prompt {
    param([string]$Label, [string]$Default = '', [bool]$Secret = $false)
    $display = if ($Default) { "$Label [$Default]: " } else { "${Label}: " }
    if ($Secret) {
        $sec  = Read-Host -AsSecureString -Prompt $display
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        $val  = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    } else {
        $val = Read-Host -Prompt $display
    }
    $val = $val.Trim()
    if (-not $val) { $val = $Default }
    return $val
}

function Read-YesNo {
    param([string]$Label, [string]$Default = 'yes')
    while ($true) {
        $input = (Read-Host -Prompt "$Label [$Default] (yes/no)").Trim().ToLower()
        if (-not $input) { $input = $Default.ToLower() }
        if ($input -in @('y','yes')) { return 'yes' }
        if ($input -in @('n','no'))  { return 'no' }
        Write-Warn "Please enter yes or no."
    }
}

function Read-Choice {
    param([string]$Label, [string[]]$Options, [string]$Default = '1')
    Write-Host ""; Write-Host $Label
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $display = $Options[$i] -replace '^[^|]+\|',''
        Write-Host "  $($i+1)) $display"
    }
    while ($true) {
        $input = (Read-Host -Prompt "Choice [$Default]").Trim()
        if (-not $input) { $input = $Default }
        if ($input -match '^\d+$') {
            $idx = [int]$input - 1
            if ($idx -ge 0 -and $idx -lt $Options.Count) { return ($Options[$idx] -replace '\|.*$','') }
        }
        Write-Warn "Enter a number between 1 and $($Options.Count)."
    }
}

# ── credential helpers ─────────────────────────────────────────────────────
function Get-ExistingEnvValue {
    param([string]$Key, [string[]]$Files)
    foreach ($f in $Files) {
        if (Test-Path $f) {
            $line = Get-Content $f | Where-Object { $_ -match "^\s*${Key}=" } | Select-Object -Last 1
            if ($line) { return ($line -replace "^[^=]+=", '').Trim() }
        }
    }
    return $null
}

function Get-FromCredFile {
    param([string]$Key, [string]$File)
    if (-not (Test-Path $File)) { return $null }
    $line = Get-Content $File | Where-Object { $_ -match "^\s*${Key}\s*[:=]" } | Select-Object -Last 1
    if ($line) { return ($line -replace "^[^:=]+[:=]\s*", '').Trim() }
    return $null
}

function New-RandomHex32 {
    $bytes = New-Object byte[] 32
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    return ([System.BitConverter]::ToString($bytes)) -replace '-',''
}

function Find-PythonBin {
    foreach ($cand in @($env:PYTHON_BIN, 'python3', 'python')) {
        if ($cand -and (Get-Command $cand -ErrorAction SilentlyContinue)) {
            & $cand -c "import sys; raise SystemExit(0 if sys.version_info>=(3,11) else 1)" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { return $cand }
        }
    }
    return $null
}

function Invoke-GenerateCredentials([string]$OutFile) {
    $py = Find-PythonBin
    if (-not $py) { Invoke-Die "Python 3.11+ is required for credential generation." }
    $credScript = $null
    foreach ($cand in @(
        (Join-Path $ScriptDir 'generate_credentials.py'),
        (Join-Path $StartDir 'generate_credentials.py'),
        (Join-Path $OutDir   'generate_credentials.py')
    )) { if (Test-Path $cand) { $credScript = $cand; break } }
    if (-not $credScript) { Invoke-Die "generate_credentials.py not found. Place it next to this script." }
    Write-Info "Running generate_credentials.py ..."
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "cred_gen_$([System.IO.Path]::GetRandomFileName())"
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
    Push-Location $tmpDir
    try {
        & $py $credScript 2>&1 | Tee-Object -FilePath (Join-Path $tmpDir 'output.log')
        $produced = Get-ChildItem $tmpDir -File | Where-Object { $_.Name -ne 'output.log' } | Select-Object -First 1
        if ($produced) { Copy-Item $produced.FullName $OutFile }
        else { Copy-Item (Join-Path $tmpDir 'output.log') $OutFile }
    } finally {
        Pop-Location
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Ok "Credentials written to $OutFile"
}

# ── LLM provider collection ───────────────────────────────────────────────────
function Get-CategoryBlockCommented { param([string]$Prefix, [string]$Primary, [string]$Reason = '0.2')
    return @"
# OPTIONAL per-category model overrides. Each category falls back to MODEL_NAME ($Primary) unless BOTH
# the *_MODEL and *_TEMPERATURE for that category are set. Uncomment and edit to override the image defaults.
#${Prefix}_FAST_MODEL=$Primary
#${Prefix}_FAST_TEMPERATURE=0.3
#${Prefix}_LARGE_MODEL=$Primary
#${Prefix}_LARGE_TEMPERATURE=0.2
#${Prefix}_VISION_MODEL=$Primary
#${Prefix}_VISION_TEMPERATURE=0.1
#${Prefix}_CODE_MODEL=$Primary
#${Prefix}_CODE_TEMPERATURE=0.0
#${Prefix}_REASONING_MODEL=$Primary
#${Prefix}_REASONING_TEMPERATURE=$Reason
"@
}

function Invoke-CollectLlmProvider {
    $script:LlmProvider = Read-Choice "Select LLM provider" @(
        "azure_openai|Azure OpenAI"
        "openai|OpenAI"
        "aws_bedrock|AWS Bedrock"
        "vertex_ai|Google Vertex AI"
        "gemini|Google Gemini API"
        "nvidia_nim|NVIDIA NIM"
        "ollama|Ollama / self-hosted test"
    )
    switch ($script:LlmProvider) {
        'azure_openai' {
            $script:OpenAiApiKey        = Read-Prompt "Azure OpenAI API key" '' $true
            $script:AzureEndpoint       = Read-Prompt "Azure OpenAI endpoint" "https://your-resource.openai.azure.com/"
            $script:OpenAiApiVersion    = Read-Prompt "Azure OpenAI API version" "2024-02-15-preview"
            $script:PrimaryModel        = Read-Prompt "Primary deployment name" "gpt-4o"
            $script:ModelPlugin         = "plugins.models.azure_openai_enhanced:AzureOpenAIPlugin"
            $script:LlmEnvBlock         = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nOPENAI_API_TYPE=azure`nAZURE_OPENAI_ENDPOINT=$($script:AzureEndpoint)`nOPENAI_API_VERSION=$($script:OpenAiApiVersion)`nMODEL_NAME=$($script:PrimaryModel)"
            $script:LlmSecretsBlock     = "OPENAI_API_KEY=$($script:OpenAiApiKey)"
        }
        'openai' {
            $script:OpenAiApiKey        = Read-Prompt "OpenAI API key" '' $true
            $script:OpenAiApiBase       = Read-Prompt "Custom base URL (optional)" ''
            $script:PrimaryModel        = Read-Prompt "Primary model name" "gpt-4o"
            $script:ModelPlugin         = "plugins.models.openai_enhanced:OpenAIPlugin"
            $base = if ($script:OpenAiApiBase) { "`nOPENAI_API_BASE=$($script:OpenAiApiBase)" } else { '' }
            $script:LlmEnvBlock         = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nOPENAI_API_TYPE=openai`nMODEL_NAME=$($script:PrimaryModel)${base}"
            $script:LlmSecretsBlock     = "OPENAI_API_KEY=$($script:OpenAiApiKey)"
        }
        'aws_bedrock' {
            $script:AwsRegionLlm        = Read-Prompt "AWS region" "us-east-1"
            $script:PrimaryModel        = Read-Prompt "Bedrock model ID" "anthropic.claude-3-5-sonnet-20241022-v2:0"
            $useKeys                    = Read-YesNo "Use explicit AWS keys (No = IAM role)" "no"
            $script:LlmSecretsBlock     = ''
            if ($useKeys -eq 'yes') {
                $ak = Read-Prompt "AWS_ACCESS_KEY_ID" '' $true
                $sk = Read-Prompt "AWS_SECRET_ACCESS_KEY" '' $true
                $script:LlmSecretsBlock = "AWS_ACCESS_KEY_ID=${ak}`nAWS_SECRET_ACCESS_KEY=${sk}"
            }
            $script:ModelPlugin         = "plugins.models.bedrock_enhanced:BedrockPlugin"
            $script:LlmEnvBlock         = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nAWS_REGION=$($script:AwsRegionLlm)`nMODEL_NAME=$($script:PrimaryModel)"
        }
        'vertex_ai' {
            $script:GcpProject          = Read-Prompt "GCP project ID" "your-gcp-project"
            $script:GcpLocation         = Read-Prompt "GCP location" "us-central1"
            $script:GoogleCreds         = Read-Prompt "SA JSON path in container" "/app/credentials/sa.json"
            $script:PrimaryModel        = Read-Prompt "Vertex AI model" "gemini-2.0-flash"
            $script:ModelPlugin         = "plugins.models.vertexai_enhanced:VertexAIPlugin"
            $script:LlmEnvBlock         = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nPROJECT_ID=$($script:GcpProject)`nLOCATION_ID=$($script:GcpLocation)`nGOOGLE_APPLICATION_CREDENTIALS=$($script:GoogleCreds)`nMODEL_NAME=$($script:PrimaryModel)"
            $script:LlmSecretsBlock     = ''
        }
        'gemini' {
            $script:GoogleApiKey        = Read-Prompt "Google Gemini API key" '' $true
            $script:PrimaryModel        = Read-Prompt "Gemini model" "gemini-2.0-flash"
            $script:ModelPlugin         = "plugins.models.gemini_enhanced:GeminiPlugin"
            $script:LlmEnvBlock         = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nMODEL_NAME=$($script:PrimaryModel)"
            $script:LlmSecretsBlock     = "GOOGLE_API_KEY=$($script:GoogleApiKey)"
        }
        'nvidia_nim' {
            $script:NvidiaApiKey        = Read-Prompt "NVIDIA API key" '' $true
            $script:NvidiaBaseUrl       = Read-Prompt "NVIDIA base URL" "https://integrate.api.nvidia.com/v1"
            $script:PrimaryModel        = Read-Prompt "NIM model" "meta/llama-3.1-70b-instruct"
            $script:ModelPlugin         = "plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin"
            $script:LlmEnvBlock         = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nNVIDIA_BASE_URL=$($script:NvidiaBaseUrl)`nMODEL_NAME=$($script:PrimaryModel)"
            $script:LlmSecretsBlock     = "NVIDIA_API_KEY=$($script:NvidiaApiKey)"
        }
        'ollama' {
            $script:OllamaBaseUrl       = Read-Prompt "Ollama base URL" "http://host.docker.internal:11434"
            $script:PrimaryModel        = Read-Prompt "Ollama model" "llama3.1:8b"
            $script:ModelPlugin         = "plugins.models.ollama_enhanced:OllamaPlugin"
            $script:LlmEnvBlock         = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nOLLAMA_BASE_URL=$($script:OllamaBaseUrl)`nMODEL_NAME=$($script:PrimaryModel)"
            $script:LlmSecretsBlock     = ''
        }
    }

    # Append optional per-category model overrides (commented out) to the LLM env block.
    $catPrefix = ''; $catReason = '0.2'
    switch ($script:LlmProvider) {
        'azure_openai' { $catPrefix = 'AZURE' }
        'openai'       { $catPrefix = 'OPENAI' }
        'aws_bedrock'  { $catPrefix = 'BEDROCK';  $catReason = '1.0' }
        'vertex_ai'    { $catPrefix = 'VERTEXAI'; $catReason = '0.1' }
        'gemini'       { $catPrefix = 'GEMINI';   $catReason = '0.1' }
        'nvidia_nim'   { $catPrefix = 'NVIDIA' }
        'ollama'       { $catPrefix = 'OLLAMA' }
    }
    if ($catPrefix) {
        $script:LlmEnvBlock = "$($script:LlmEnvBlock)`n$(Get-CategoryBlockCommented $catPrefix $script:PrimaryModel $catReason)"
    }
}

# ── write cloud env checklist ─────────────────────────────────────────────────
function Write-CloudEnvChecklist {
    $outFile = Join-Path $OutDir 'cloud-env-checklist.txt'
    $ts      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $sslS    = if ($script:DbSslMode -ne 'disable') { "?ssl=$($script:DbSslMode)" }     else { '' }
    $sslSync = if ($script:DbSslMode -ne 'disable') { "?sslmode=$($script:DbSslMode)" } else { '' }
    $content = @"
# ==============================================================================
# Spotfire Copilot — Azure Container Apps Cloud Env Checklist
# Generated: $ts
# Image tag: $($script:ImageTag)
# Store SECRET values in Azure Key Vault or as ACA secrets.
# Use CONFIG values as plain Container App environment variables.
# ==============================================================================

# ── 01 CORE ───────────────────────────────────────────────────────────────────
# CONFIG
IMAGE_TAG=$($script:ImageTag)
FASTAPI_APP_VERSION=$($script:ImageTag)
LOG_LEVEL=INFO

# SECRET
SECRET_KEY=$($script:CSecretKey)
HASHED_ADMIN_PASSWORD=$($script:CHashedAdmin)
OAUTH2_CLIENT_ID=$($script:COauthId)
OAUTH2_CLIENT_SECRET_HASH=$($script:COauthHash)

# ── 02 DATABASE ───────────────────────────────────────────────────────────────
# SECRET
DATABASE_URL=postgresql+asyncpg://$($script:DbUser):$($script:DbPassword)@$($script:DbHost):$($script:DbPort)/$($script:DbName)${sslS}
SYNC_DATABASE_URL=postgresql://$($script:DbUser):$($script:DbPassword)@$($script:DbHost):$($script:DbPort)/$($script:DbName)${sslSync}

# CONFIG
DB_SSLMODE=$($script:DbSslMode)

# ── 03 LLM PROVIDER ───────────────────────────────────────────────────────────
# CONFIG
$($script:LlmEnvBlock)

# SECRET
$($script:LlmSecretsBlock)
"@
    if ($script:EnableAdminConsole -eq 'yes') {
        $content += "`n# ── 04 ADMIN CONSOLE ─────────────────────────────────────────────────────────`nENABLE_ADMIN_CONSOLE=true`nADMIN_SECRET_KEY=$($script:CSecretKey)`n"
    }
    if ($script:EnableAgentRegistry -eq 'yes') {
        $content += "`n# ── 05 AGENT REGISTRY ────────────────────────────────────────────────────────`nPORT=$($script:AgentPort)`nBASE_URL=$($script:AgentBaseUrl)`nAUTH_CLIENT_ID=$($script:AgentClientId)`nAUTH_CLIENT_SECRET=$($script:AgentClientSecret)`nAUTH_SIGNING_KEY=$($script:AgentSigningKey)`nORCHESTRATOR_URL=$($script:OrchestratorUrlForAgent)`n"
    }
    Set-Content -Path $outFile -Value $content -Encoding UTF8
    Write-Ok "Cloud env checklist written: $outFile"
}

# ── helpers for ACA secret/env building ──────────────────────────────────────
function Build-AcaSecretString {
    # Returns "name1=val1 name2=val2 ..." for --secrets; secret names are lowercase-hyphen
    param([hashtable]$Pairs)
    $parts = @()
    foreach ($kv in $Pairs.GetEnumerator()) {
        $sname = $kv.Key.ToLower() -replace '_','-'
        $parts += "${sname}=$($kv.Value)"
    }
    return $parts -join ' '
}

function Build-AcaEnvVarsString {
    # Returns "KEY=value KEY2=secretref:name ..." for --env-vars
    param([hashtable]$PlainPairs, [hashtable]$SecretRefs)
    $parts = @()
    foreach ($kv in $PlainPairs.GetEnumerator()) { $parts += "$($kv.Key)=$($kv.Value)" }
    foreach ($kv in $SecretRefs.GetEnumerator()) {
        $sname = $kv.Key.ToLower() -replace '_','-'
        $parts += "$($kv.Key)=secretref:${sname}"
    }
    return $parts -join ' '
}

function Get-LlmSecretPairs {
    $pairs = @{}
    $script:LlmSecretsBlock -split "`n" | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') } | ForEach-Object {
        $idx = $_.IndexOf('=')
        if ($idx -gt 0) {
            $k = $_.Substring(0, $idx).Trim()
            $v = $_.Substring($idx + 1).Trim()
            $pairs[$k] = $v
        }
    }
    return $pairs
}

function Get-LlmEnvPairs {
    $pairs = @{}
    $script:LlmEnvBlock -split "`n" | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') } | ForEach-Object {
        $idx = $_.IndexOf('=')
        if ($idx -gt 0) { $pairs[$_.Substring(0,$idx).Trim()] = $_.Substring($idx+1).Trim() }
    }
    return $pairs
}

# ── write CloudShell deploy script ────────────────────────────────────────────
function Write-CloudShellScript {
    param([string]$DeployDir)
    $scriptFile = Join-Path $DeployDir 'azcli-deploy.sh'
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $sslS = if ($script:DbSslMode -ne 'disable') { "?ssl=$($script:DbSslMode)" }     else { '' }
    $sslY = if ($script:DbSslMode -ne 'disable') { "?sslmode=$($script:DbSslMode)" } else { '' }
    $dbUrl     = "postgresql+asyncpg://$($script:DbUser):$($script:DbPassword)@$($script:DbHost):$($script:DbPort)/$($script:DbName)${sslS}"
    $dbSyncUrl = "postgresql://$($script:DbUser):$($script:DbPassword)@$($script:DbHost):$($script:DbPort)/$($script:DbName)${sslY}"

    # Build secret string for orchestrator
    $orchSecretsStr = "secret-key=$($script:CSecretKey) hashed-admin-password=$($script:CHashedAdmin) oauth2-client-id=$($script:COauthId) oauth2-client-secret-hash=$($script:COauthHash) database-url=${dbUrl} sync-database-url=${dbSyncUrl}"
    $llmSecPairs = Get-LlmSecretPairs
    foreach ($kv in $llmSecPairs.GetEnumerator()) {
        $sname = $kv.Key.ToLower() -replace '_','-'
        $orchSecretsStr += " ${sname}=$($kv.Value)"
    }

    # Build env vars string (config + secretrefs)
    $orchEnvStr = "IMAGE_TAG=$($script:ImageTag) FASTAPI_APP_VERSION=$($script:ImageTag) LOG_LEVEL=INFO DB_SSLMODE=$($script:DbSslMode)"
    $llmEnvPairs = Get-LlmEnvPairs
    foreach ($kv in $llmEnvPairs.GetEnumerator()) { $orchEnvStr += " $($kv.Key)=$($kv.Value)" }
    $orchEnvStr += " SECRET_KEY=secretref:secret-key HASHED_ADMIN_PASSWORD=secretref:hashed-admin-password OAUTH2_CLIENT_ID=secretref:oauth2-client-id OAUTH2_CLIENT_SECRET_HASH=secretref:oauth2-client-secret-hash DATABASE_URL=secretref:database-url SYNC_DATABASE_URL=secretref:sync-database-url"
    foreach ($kv in $llmSecPairs.GetEnumerator()) {
        $sname = $kv.Key.ToLower() -replace '_','-'
        $orchEnvStr += " $($kv.Key)=secretref:${sname}"
    }

    $adminBlock = ''
    if ($script:EnableAdminConsole -eq 'yes') {
        $adminSecretsStr = "secret-key=$($script:CSecretKey) database-url=${dbUrl} sync-database-url=${dbSyncUrl}"
        $adminEnvStr     = "IMAGE_TAG=$($script:ImageTag) FASTAPI_APP_VERSION=$($script:ImageTag) LOG_LEVEL=INFO ENABLE_ADMIN_CONSOLE=true SECRET_KEY=secretref:secret-key DATABASE_URL=secretref:database-url SYNC_DATABASE_URL=secretref:sync-database-url"
        $adminBlock = @"

echo '==> Deploying Admin Console Container App...'
az containerapp create \
  --name "`${APP_PREFIX}-admin-console" \
  --resource-group "`${RESOURCE_GROUP}" \
  --environment "`${ACA_ENVIRONMENT}" \
  --image "copilotoci.azurecr.io/spotfirecopilot/admin-console:`${IMAGE_TAG}" \
  --registry-server "copilotoci.azurecr.io" \
  --registry-username "`${ACR_USERNAME}" \
  --registry-password "`${ACR_PASSWORD}" \
  --target-port 3000 \
  --ingress external \
  --min-replicas "`${MIN_REPLICAS}" \
  --max-replicas "`${MAX_REPLICAS}" \
  --cpu "`${APP_CPU}" \
  --memory "`${APP_MEMORY}" \
  --secrets "${adminSecretsStr}" \
  --env-vars "${adminEnvStr}" 2>/dev/null || \
az containerapp update \
  --name "`${APP_PREFIX}-admin-console" \
  --resource-group "`${RESOURCE_GROUP}" \
  --image "copilotoci.azurecr.io/spotfirecopilot/admin-console:`${IMAGE_TAG}" \
  --set-env-vars "${adminEnvStr}"
echo "Admin Console: https://`$(az containerapp show --name `"`${APP_PREFIX}-admin-console`" --resource-group `"`${RESOURCE_GROUP}`" --query properties.configuration.ingress.fqdn --output tsv)"
"@
    }

    $content = @"
#!/usr/bin/env bash
# ==============================================================================
#  Spotfire Copilot — Azure Container Apps CloudShell Deploy Script
#  Generated: $ts
#  Run in Azure Cloud Shell: bash azcli-deploy.sh
# ==============================================================================
set -Eeuo pipefail

RESOURCE_GROUP="$($script:AcaResourceGroup)"
ACA_ENVIRONMENT="$($script:AcaEnvironment)"
LOCATION="$($script:AcaLocation)"
APP_PREFIX="$($script:AcaAppPrefix)"
IMAGE_TAG="$($script:ImageTag)"
APP_CPU="$($script:AcaCpu)"
APP_MEMORY="$($script:AcaMemory)"
MIN_REPLICAS="$($script:AcaMinReplicas)"
MAX_REPLICAS="$($script:AcaMaxReplicas)"
ACR_USERNAME="$($script:AcrUsername)"
ACR_PASSWORD="$($script:AcrPassword)"

echo "================================================================"
echo " Spotfire Copilot — Azure Container Apps Deployment"
echo " Resource Group: `${RESOURCE_GROUP}  Location: `${LOCATION}"
echo "================================================================"

echo "==> Creating/verifying resource group: `${RESOURCE_GROUP}"
az group create --name "`${RESOURCE_GROUP}" --location "`${LOCATION}" --output none

echo "==> Creating/verifying ACA environment: `${ACA_ENVIRONMENT}"
az containerapp env create \
  --name "`${ACA_ENVIRONMENT}" \
  --resource-group "`${RESOURCE_GROUP}" \
  --location "`${LOCATION}" --output none 2>/dev/null || true

echo "==> Deploying Orchestrator: `${APP_PREFIX}-orchestrator"
az containerapp create \
  --name "`${APP_PREFIX}-orchestrator" \
  --resource-group "`${RESOURCE_GROUP}" \
  --environment "`${ACA_ENVIRONMENT}" \
  --image "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:`${IMAGE_TAG}" \
  --registry-server "copilotoci.azurecr.io" \
  --registry-username "`${ACR_USERNAME}" \
  --registry-password "`${ACR_PASSWORD}" \
  --target-port 8080 \
  --ingress external \
  --min-replicas "`${MIN_REPLICAS}" \
  --max-replicas "`${MAX_REPLICAS}" \
  --cpu "`${APP_CPU}" \
  --memory "`${APP_MEMORY}" \
  --secrets "${orchSecretsStr}" \
  --env-vars "${orchEnvStr}" 2>/dev/null || \
az containerapp update \
  --name "`${APP_PREFIX}-orchestrator" \
  --resource-group "`${RESOURCE_GROUP}" \
  --image "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:`${IMAGE_TAG}" \
  --set-env-vars "${orchEnvStr}"

ORCH_URL=`$(az containerapp show \
  --name "`${APP_PREFIX}-orchestrator" \
  --resource-group "`${RESOURCE_GROUP}" \
  --query properties.configuration.ingress.fqdn --output tsv)
echo "Orchestrator: https://`${ORCH_URL}"
${adminBlock}

echo "================================================================"
echo " Deployment complete. Orchestrator: https://`${ORCH_URL}"
echo " Update ORCHESTRATOR_BASE_URL in the Spotfire Copilot frontend."
echo "================================================================"
"@
    Set-Content -Path $scriptFile -Value $content -Encoding UTF8
    Write-Ok "CloudShell deploy script written: $scriptFile"
}

# ── direct Azure CLI deployment ───────────────────────────────────────────────
function Invoke-AzCliDeploy {
    param([string]$DeployDir)
    Write-Section "Live Azure CLI Deployment"

    Write-Info "Creating/verifying resource group: $($script:AcaResourceGroup)"
    az group create --name $script:AcaResourceGroup --location $script:AcaLocation --output none
    Write-Ok "Resource group ready."

    Write-Info "Creating/verifying Container Apps environment: $($script:AcaEnvironment)"
    az containerapp env create `
        --name $script:AcaEnvironment `
        --resource-group $script:AcaResourceGroup `
        --location $script:AcaLocation `
        --output none 2>$null
    Write-Ok "ACA environment ready."

    $sslS = if ($script:DbSslMode -ne 'disable') { "?ssl=$($script:DbSslMode)" }     else { '' }
    $sslY = if ($script:DbSslMode -ne 'disable') { "?sslmode=$($script:DbSslMode)" } else { '' }
    $dbUrl     = "postgresql+asyncpg://$($script:DbUser):$($script:DbPassword)@$($script:DbHost):$($script:DbPort)/$($script:DbName)${sslS}"
    $dbSyncUrl = "postgresql://$($script:DbUser):$($script:DbPassword)@$($script:DbHost):$($script:DbPort)/$($script:DbName)${sslY}"

    # Build secrets for orchestrator
    $orchSecrets = @{
        'secret-key'               = $script:CSecretKey
        'hashed-admin-password'    = $script:CHashedAdmin
        'oauth2-client-id'         = $script:COauthId
        'oauth2-client-secret-hash'= $script:COauthHash
        'database-url'             = $dbUrl
        'sync-database-url'        = $dbSyncUrl
    }
    $llmSecPairs = Get-LlmSecretPairs
    foreach ($kv in $llmSecPairs.GetEnumerator()) {
        $orchSecrets[$kv.Key.ToLower() -replace '_','-'] = $kv.Value
    }
    $orchSecretsStr = ($orchSecrets.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '

    # Build env vars for orchestrator
    $orchPlainEnv = @{
        'IMAGE_TAG'            = $script:ImageTag
        'FASTAPI_APP_VERSION'  = $script:ImageTag
        'LOG_LEVEL'            = 'INFO'
        'DB_SSLMODE'           = $script:DbSslMode
    }
    $llmEnvPairs = Get-LlmEnvPairs
    foreach ($kv in $llmEnvPairs.GetEnumerator()) { $orchPlainEnv[$kv.Key] = $kv.Value }
    $orchSecretRefs = @{
        'SECRET_KEY'             = 'secret-key'
        'HASHED_ADMIN_PASSWORD'  = 'hashed-admin-password'
        'OAUTH2_CLIENT_ID'       = 'oauth2-client-id'
        'OAUTH2_CLIENT_SECRET_HASH' = 'oauth2-client-secret-hash'
        'DATABASE_URL'           = 'database-url'
        'SYNC_DATABASE_URL'      = 'sync-database-url'
    }
    foreach ($kv in $llmSecPairs.GetEnumerator()) {
        $orchSecretRefs[$kv.Key] = $kv.Key.ToLower() -replace '_','-'
    }
    $orchEnvStr  = ($orchPlainEnv.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
    $orchEnvStr += ' ' + ($orchSecretRefs.GetEnumerator() | ForEach-Object { "$($_.Key)=secretref:$($_.Value)" }) -join ' '

    Write-Info "Deploying Orchestrator Container App: $($script:AcaAppPrefix)-orchestrator"
    $createResult = az containerapp create `
        --name "$($script:AcaAppPrefix)-orchestrator" `
        --resource-group $script:AcaResourceGroup `
        --environment $script:AcaEnvironment `
        --image "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:$($script:ImageTag)" `
        --registry-server "copilotoci.azurecr.io" `
        --registry-username $script:AcrUsername `
        --registry-password $script:AcrPassword `
        --target-port 8080 `
        --ingress external `
        --min-replicas $script:AcaMinReplicas `
        --max-replicas $script:AcaMaxReplicas `
        --cpu $script:AcaCpu `
        --memory $script:AcaMemory `
        --secrets $orchSecretsStr `
        --env-vars $orchEnvStr 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Container App exists — updating..."
        az containerapp update `
            --name "$($script:AcaAppPrefix)-orchestrator" `
            --resource-group $script:AcaResourceGroup `
            --image "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:$($script:ImageTag)" `
            --set-env-vars $orchEnvStr | Out-Null
    }

    $orchUrl = (az containerapp show `
        --name "$($script:AcaAppPrefix)-orchestrator" `
        --resource-group $script:AcaResourceGroup `
        --query properties.configuration.ingress.fqdn --output tsv).Trim()
    Write-Ok "Orchestrator deployed: https://$orchUrl"

    if ($script:EnableAdminConsole -eq 'yes') {
        $adminSecrets = "secret-key=$($script:CSecretKey) database-url=${dbUrl} sync-database-url=${dbSyncUrl}"
        $adminEnv     = "IMAGE_TAG=$($script:ImageTag) FASTAPI_APP_VERSION=$($script:ImageTag) LOG_LEVEL=INFO ENABLE_ADMIN_CONSOLE=true SECRET_KEY=secretref:secret-key DATABASE_URL=secretref:database-url SYNC_DATABASE_URL=secretref:sync-database-url"
        Write-Info "Deploying Admin Console Container App: $($script:AcaAppPrefix)-admin-console"
        az containerapp create `
            --name "$($script:AcaAppPrefix)-admin-console" `
            --resource-group $script:AcaResourceGroup `
            --environment $script:AcaEnvironment `
            --image "copilotoci.azurecr.io/spotfirecopilot/admin-console:$($script:ImageTag)" `
            --registry-server "copilotoci.azurecr.io" `
            --registry-username $script:AcrUsername `
            --registry-password $script:AcrPassword `
            --target-port 3000 `
            --ingress external `
            --min-replicas $script:AcaMinReplicas `
            --max-replicas $script:AcaMaxReplicas `
            --cpu $script:AcaCpu `
            --memory $script:AcaMemory `
            --secrets $adminSecrets `
            --env-vars $adminEnv 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            az containerapp update `
                --name "$($script:AcaAppPrefix)-admin-console" `
                --resource-group $script:AcaResourceGroup `
                --image "copilotoci.azurecr.io/spotfirecopilot/admin-console:$($script:ImageTag)" `
                --set-env-vars $adminEnv | Out-Null
        }
        $adminUrl = (az containerapp show `
            --name "$($script:AcaAppPrefix)-admin-console" `
            --resource-group $script:AcaResourceGroup `
            --query properties.configuration.ingress.fqdn --output tsv).Trim()
        Write-Ok "Admin Console deployed: https://$adminUrl"
    }

    Write-Host ""
    Write-Host "================================================================"
    Write-Host " Deployment complete."
    Write-Host " Orchestrator: https://$orchUrl"
    Write-Host " Update ORCHESTRATOR_BASE_URL in the Spotfire Copilot frontend."
    Write-Host "================================================================"
}

# ════════════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════════════
Write-Host "================================================================"
Write-Host " Spotfire Copilot — Azure Container Apps Deployment"
Write-Host "================================================================"

# Phase 1: Image tag + output directory
Write-Section "Image tag"
$script:ImageTag = Read-Prompt "Copilot image tag" $DefaultTag
if (-not $script:ImageTag) { $script:ImageTag = $DefaultTag }
if (-not $OutDirExplicit) { $OutDir = Join-Path (Join-Path $CopilotRoot $script:ImageTag) 'backend' }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
Write-Info "Output directory: $OutDir"
$ExistingFiles = @((Join-Path $OutDir '.env'), (Join-Path $OutDir '.env.orchestrator'))

# Phase 1: Credentials
Write-Section "Credentials"
$script:CSecretKey = ''; $script:CHashedAdmin = ''; $script:COauthId = ''; $script:COauthHash = ''
$credFile  = Join-Path $OutDir 'copilot-generated-values.txt'
$haveCreds = Test-Path $credFile
if ($haveCreds) { $haveCreds = (Read-YesNo "Existing credentials file found. Reuse it?" "yes") -eq 'yes' }
if (-not $haveCreds) {
    if ((Read-YesNo "Generate credentials using generate_credentials.py?" "yes") -eq 'yes') {
        Invoke-GenerateCredentials $credFile
    }
}
if (Test-Path $credFile) {
    $script:CSecretKey   = Get-FromCredFile 'SECRET_KEY'              $credFile
    $script:CHashedAdmin = Get-FromCredFile 'HASHED_ADMIN_PASSWORD'   $credFile
    $script:COauthId     = Get-FromCredFile 'OAUTH2_CLIENT_ID'        $credFile
    $script:COauthHash   = Get-FromCredFile 'OAUTH2_CLIENT_SECRET_HASH' $credFile
}
if (-not $script:CSecretKey)    { $script:CSecretKey    = Read-Prompt "SECRET_KEY" '' $true }
if (-not $script:CHashedAdmin)  { $script:CHashedAdmin  = Read-Prompt "HASHED_ADMIN_PASSWORD" '' $true }
if (-not $script:COauthId)      { $script:COauthId      = Read-Prompt "OAUTH2_CLIENT_ID" '' }
if (-not $script:COauthHash)    { $script:COauthHash    = Read-Prompt "OAUTH2_CLIENT_SECRET_HASH" '' $true }

# Phase 1: Database
Write-Section "Database (pre-existing PostgreSQL)"
Write-Info "Provide your existing Azure Database for PostgreSQL (or other managed PostgreSQL) details."
$script:DbHost     = Read-Prompt "PostgreSQL host"                   (Get-ExistingEnvValue 'POSTGRES_HOST' $ExistingFiles)
$script:DbPort     = Read-Prompt "PostgreSQL port"                   ((Get-ExistingEnvValue 'POSTGRES_PORT' $ExistingFiles) ?? '5432')
$script:DbName     = Read-Prompt "Database name"                     ((Get-ExistingEnvValue 'POSTGRES_DB' $ExistingFiles) ?? 'orchestrator')
$script:DbUser     = Read-Prompt "Database user"                     ((Get-ExistingEnvValue 'POSTGRES_USER' $ExistingFiles) ?? 'orchestrator')
$script:DbPassword = Read-Prompt "Database password" '' $true
$script:DbSslMode  = Read-Prompt "SSL mode (require/disable/prefer)" 'require'

# Phase 1: LLM provider
Write-Section "LLM provider"
$script:LlmProvider = ''; $script:LlmEnvBlock = ''; $script:LlmSecretsBlock = ''
Invoke-CollectLlmProvider

# Phase 1: Optional components
Write-Section "Optional components"
$script:EnableAdminConsole  = Read-YesNo "Deploy Admin Console?"  "yes"
$script:EnableAgentRegistry = Read-YesNo "Deploy Agent Registry?" "no"
$script:AgentPort = '8050'; $script:AgentBaseUrl = ''; $script:AgentClientId = ''
$script:AgentClientSecret = ''; $script:AgentSigningKey = ''; $script:OrchestratorUrlForAgent = ''
if ($script:EnableAgentRegistry -eq 'yes') {
    $script:AgentPort               = Read-Prompt "Agent Registry port"        "8050"
    $script:AgentBaseUrl            = Read-Prompt "Agent Registry BASE_URL"    "http://agent-registry:8050"
    $script:AgentClientId           = Read-Prompt "Agent AUTH_CLIENT_ID"       "agent-registry-client"
    $script:AgentClientSecret       = New-RandomHex32
    $script:AgentSigningKey         = New-RandomHex32
    $script:OrchestratorUrlForAgent = Read-Prompt "ORCHESTRATOR_URL for Agent" "http://orchestrator:8080"
    Write-Ok "Agent secrets generated."
}

# Phase 2: Cloud env checklist
Write-Section "Generating cloud env checklist"
Write-CloudEnvChecklist

# Phase 3: Deployment method
Write-Section "Deployment method"
$script:CliChoice = Read-Choice "How would you like to deploy?" @(
    "cli_deploy|I have the Azure CLI installed and configured — deploy directly from this machine"
    "no_cli|I don't have the Azure CLI installed yet"
    "generate_only|I don't want to use the CLI — just generate the commands for me"
)

switch ($script:CliChoice) {
    'no_cli' {
        Write-Host ""
        Write-Info "Please install and configure the Azure CLI, then re-run this script."
        Write-Host ""
        Write-Host "  Install:    https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
        Write-Host "  Login:      az login"
        Write-Host "  Set sub:    az account set --subscription <your-subscription-id>"
        Write-Host ""
        Write-Info "Your Phase 1 & 2 configuration has been saved and will be reused on re-run:"
        Write-Host "  $(Join-Path $OutDir 'cloud-env-checklist.txt')"
        Write-Host "  $(Join-Path $OutDir 'copilot-generated-values.txt')"
        Write-Host ""
        Write-Host "Re-run with:  .\spotfire-copilot-deploy-aca.ps1 -Dir $OutDir"
        exit 0
    }
    { $_ -in @('cli_deploy','generate_only') } {
        $haveDetails = Read-YesNo "Do you have your Azure infrastructure details ready? (resource group, location, ACA environment name, ACR credentials)" "yes"
        if ($haveDetails -eq 'no') {
            Write-Host ""
            Write-Info "Please gather the following details, then re-run this script:"
            Write-Host ""
            Write-Host "  Azure Container Apps details required:"
            Write-Host "  ─────────────────────────────────────────────────────────"
            Write-Host "  • Azure subscription ID"
            Write-Host "  • Resource group name    (will be created if it doesn't exist)"
            Write-Host "  • Azure region/location  (e.g. eastus, westeurope)"
            Write-Host "  • ACA environment name   (will be created if it doesn't exist)"
            Write-Host "  • Container App prefix   (e.g. spotfire-copilot)"
            Write-Host "  • CPU cores per app      (e.g. 1.0)"
            Write-Host "  • Memory per app         (e.g. 2.0Gi)"
            Write-Host "  • Min / max replicas     (e.g. 1 / 3)"
            Write-Host ""
            Write-Host "  ACR pull credentials (from copilotoci.azurecr.io):"
            Write-Host "  • ACR username"
            Write-Host "  • ACR password"
            Write-Host ""
            Write-Info "Your Phase 1 & 2 configuration has been saved and will be reused on re-run:"
            Write-Host "  $(Join-Path $OutDir 'cloud-env-checklist.txt')"
            Write-Host "  $(Join-Path $OutDir 'copilot-generated-values.txt')"
            Write-Host ""
            Write-Host "Re-run with:  .\spotfire-copilot-deploy-aca.ps1 -Dir $OutDir"
            exit 0
        }

        # Collect ACA infrastructure details
        Write-Section "Azure Container Apps infrastructure details"
        $script:AcaResourceGroup = Read-Prompt "Resource group name"              "rg-spotfire-copilot"
        $script:AcaLocation      = Read-Prompt "Azure location"                   "eastus"
        $script:AcaEnvironment   = Read-Prompt "Container Apps environment name"  "cae-spotfire-copilot"
        $script:AcaAppPrefix     = Read-Prompt "Container App name prefix"        "spotfire-copilot"
        $script:AcaCpu           = Read-Prompt "CPU cores per container app"      "1.0"
        $script:AcaMemory        = Read-Prompt "Memory per container app (Gi)"    "2.0Gi"
        $script:AcaMinReplicas   = Read-Prompt "Minimum replicas"                 "1"
        $script:AcaMaxReplicas   = Read-Prompt "Maximum replicas"                 "3"

        Write-Section "ACR pull credentials"
        Write-Info "Provide ACR credentials to pull images from copilotoci.azurecr.io."
        $script:AcrUsername = Read-Prompt "ACR username" "spotfirecopilot"
        $script:AcrPassword = Read-Prompt "ACR password" '' $true

        $deployDir = Join-Path $OutDir 'aca'
        New-Item -ItemType Directory -Path $deployDir -Force | Out-Null

        if ($script:CliChoice -eq 'cli_deploy') {
            Write-Section "Deploying via Azure CLI"
            Invoke-AzCliDeploy $deployDir
        } else {
            Write-Section "Generating Cloud Shell deploy script"
            Write-CloudShellScript $deployDir
        }
    }
}

Write-Host ""
Write-Host "================================================================"
Write-Host " Output files:"
Write-Host "   $(Join-Path $OutDir 'cloud-env-checklist.txt')"
if ($deployDir -and (Test-Path $deployDir)) {
    Write-Host "   $(Join-Path $deployDir 'azcli-deploy.sh')"
}
Write-Host ""
if ($script:CliChoice -eq 'generate_only') {
    Write-Host " To deploy from Azure Cloud Shell:"
    Write-Host "   1. Upload azcli-deploy.sh to Cloud Shell"
    Write-Host "   2. bash azcli-deploy.sh"
    Write-Host ""
}
Write-Host " Note: Update ORCHESTRATOR_BASE_URL in the Spotfire Copilot"
Write-Host "       frontend configuration to point to the orchestrator URL."
Write-Host "================================================================"
