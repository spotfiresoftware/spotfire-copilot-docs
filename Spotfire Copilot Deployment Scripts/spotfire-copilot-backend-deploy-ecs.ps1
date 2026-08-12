#Requires -Version 5.1
<#
==============================================================================
 Spotfire Copilot — AWS ECS / Fargate Deployment Script (Windows / PowerShell)
 Version: 2.3.x

 Usage:
   .\spotfire-copilot-deploy-ecs.ps1
   .\spotfire-copilot-deploy-ecs.ps1 -Dir C:\spotfire-copilot\backend
   .\spotfire-copilot-deploy-ecs.ps1 -Help

 Flow:
   Phase 1  — Collect all configuration (same questions as cloud mode)
   Phase 2  — Generate cloud-env-checklist.txt
   Phase 3  — Collect ECS-specific inputs
   Phase 4  — Check if AWS CLI is installed
              YES → deploy directly (or write + offer to run)
              NO  → write awscli-deploy.sh for AWS CloudShell
==============================================================================
#>

[CmdletBinding()]
param(
    [string]$Dir        = '',
    [string]$ImageTag   = '',
    [switch]$Yes,
    [switch]$NoColor,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# ── directories ──────────────────────────────────────────────────────────────
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$StartDir    = (Get-Location).Path
$DefaultTag  = if ($env:DEFAULT_IMAGE_TAG) { $env:DEFAULT_IMAGE_TAG } else { '2.3.4' }
if ($ImageTag) { $DefaultTag = $ImageTag }
$CopilotRoot = if ($env:COPILOT_ROOT_DIR) { $env:COPILOT_ROOT_DIR } else { Join-Path $StartDir 'spotfire-copilot' }
$OutDirExplicit = $false
if ($Dir) {
    $OutDir = $Dir; $OutDirExplicit = $true
} else {
    $OutDir = Join-Path (Join-Path $CopilotRoot $DefaultTag) 'backend'
}

if ($Help) {
    Write-Host "Spotfire Copilot AWS ECS / Fargate Deployment Script"
    Write-Host "Usage: .\spotfire-copilot-deploy-ecs.ps1 [-Dir PATH] [-ImageTag TAG] [-Yes] [-NoColor]"
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

# ── prompt helpers ────────────────────────────────────────────────────────
function Read-Prompt {
    param([string]$Label, [string]$Default = '', [bool]$Secret = $false)
    $display = if ($Default) { "$Label [$Default]: " } else { "${Label}: " }
    if ($Secret) {
        $secStr = Read-Host -AsSecureString -Prompt $display
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secStr)
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
    Write-Host ""
    Write-Host $Label
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $display = $Options[$i] -replace '^[^|]+\|',''
        Write-Host "  $($i+1)) $display"
    }
    while ($true) {
        $input = (Read-Host -Prompt "Choice [$Default]").Trim()
        if (-not $input) { $input = $Default }
        if ($input -match '^\d+$') {
            $idx = [int]$input - 1
            if ($idx -ge 0 -and $idx -lt $Options.Count) {
                return ($Options[$idx] -replace '\|.*$','')
            }
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
    return ([System.BitConverter]::ToString((New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes(32) -as [byte[]])) -replace '-',''
}

function Find-PythonBin {
    foreach ($cand in @($env:PYTHON_BIN, 'python3', 'python')) {
        if ($cand -and (Get-Command $cand -ErrorAction SilentlyContinue)) {
            $ver = & $cand -c "import sys; raise SystemExit(0 if sys.version_info>=(3,11) else 1)" 2>&1
            if ($LASTEXITCODE -eq 0) { return $cand }
        }
    }
    return $null
}

function Invoke-GenerateCredentials {
    param([string]$OutFile)
    $py = Find-PythonBin
    if (-not $py) { Invoke-Die "Python 3.11+ is required for credential generation." }
    $credScript = $null
    foreach ($cand in @(
        (Join-Path $ScriptDir 'generate_credentials.py'),
        (Join-Path $StartDir 'generate_credentials.py'),
        (Join-Path $OutDir   'generate_credentials.py')
    )) {
        if (Test-Path $cand) { $credScript = $cand; break }
    }
    if (-not $credScript) { Invoke-Die "generate_credentials.py not found. Place it next to this script." }
    Write-Info "Running generate_credentials.py ..."
    $tmp = New-TemporaryFile
    $tmpDir = Join-Path (Split-Path $tmp.FullName) "cred_gen_$([System.IO.Path]::GetRandomFileName())"
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

# ── LLM provider collection ────────────────────────────────────────────────
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
            $script:OpenAiApiKey          = Read-Prompt "Azure OpenAI API key" '' $true
            $script:AzureOpenAiEndpoint   = Read-Prompt "Azure OpenAI endpoint" "https://your-resource.openai.azure.com/"
            $script:OpenAiApiVersion      = Read-Prompt "Azure OpenAI API version" "2024-02-15-preview"
            $script:PrimaryModel          = Read-Prompt "Primary deployment name" "gpt-4o"
            $script:ModelPlugin           = "plugins.models.azure_openai_enhanced:AzureOpenAIPlugin"
            $script:LlmEnvBlock           = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nOPENAI_API_TYPE=azure`nAZURE_OPENAI_ENDPOINT=$($script:AzureOpenAiEndpoint)`nOPENAI_API_VERSION=$($script:OpenAiApiVersion)`nMODEL_NAME=$($script:PrimaryModel)"
            $script:LlmSecretsBlock       = "OPENAI_API_KEY=$($script:OpenAiApiKey)"
        }
        'openai' {
            $script:OpenAiApiKey          = Read-Prompt "OpenAI API key" '' $true
            $script:OpenAiApiBase         = Read-Prompt "Custom base URL (optional)" ''
            $script:PrimaryModel          = Read-Prompt "Primary model name" "gpt-4o"
            $script:ModelPlugin           = "plugins.models.openai_enhanced:OpenAIPlugin"
            $baseExtra = if ($script:OpenAiApiBase) { "`nOPENAI_API_BASE=$($script:OpenAiApiBase)" } else { '' }
            $script:LlmEnvBlock           = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nOPENAI_API_TYPE=openai`nMODEL_NAME=$($script:PrimaryModel)${baseExtra}"
            $script:LlmSecretsBlock       = "OPENAI_API_KEY=$($script:OpenAiApiKey)"
        }
        'aws_bedrock' {
            $script:AwsRegionLlm   = Read-Prompt "AWS region" "us-east-1"
            $script:PrimaryModel   = Read-Prompt "Bedrock model ID" "anthropic.claude-3-5-sonnet-20241022-v2:0"
            $useKeys               = Read-YesNo "Use explicit AWS keys (No = IAM/task role)" "no"
            $script:LlmSecretsBlock = ''
            if ($useKeys -eq 'yes') {
                $ak  = Read-Prompt "AWS_ACCESS_KEY_ID" '' $true
                $sk  = Read-Prompt "AWS_SECRET_ACCESS_KEY" '' $true
                $st  = Read-Prompt "AWS_SESSION_TOKEN (optional)" '' $true
                $script:LlmSecretsBlock = "AWS_ACCESS_KEY_ID=${ak}`nAWS_SECRET_ACCESS_KEY=${sk}" + $(if ($st) { "`nAWS_SESSION_TOKEN=${st}" } else { '' })
            }
            $script:ModelPlugin    = "plugins.models.bedrock_enhanced:BedrockPlugin"
            $script:LlmEnvBlock    = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nAWS_REGION=$($script:AwsRegionLlm)`nMODEL_NAME=$($script:PrimaryModel)"
        }
        'vertex_ai' {
            $script:GcpProjectId        = Read-Prompt "GCP project ID" "your-gcp-project"
            $script:GcpLocationId       = Read-Prompt "GCP location" "us-central1"
            $script:GoogleCreds         = Read-Prompt "Service account JSON path in container" "/app/credentials/sa.json"
            $script:PrimaryModel        = Read-Prompt "Vertex AI model" "gemini-2.0-flash"
            $script:ModelPlugin         = "plugins.models.vertexai_enhanced:VertexAIPlugin"
            $script:LlmEnvBlock         = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nPROJECT_ID=$($script:GcpProjectId)`nLOCATION_ID=$($script:GcpLocationId)`nGOOGLE_APPLICATION_CREDENTIALS=$($script:GoogleCreds)`nMODEL_NAME=$($script:PrimaryModel)"
            $script:LlmSecretsBlock     = ''
        }
        'gemini' {
            $script:GoogleApiKey   = Read-Prompt "Google Gemini API key" '' $true
            $script:PrimaryModel   = Read-Prompt "Gemini model" "gemini-2.0-flash"
            $script:ModelPlugin    = "plugins.models.gemini_enhanced:GeminiPlugin"
            $script:LlmEnvBlock    = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nMODEL_NAME=$($script:PrimaryModel)"
            $script:LlmSecretsBlock = "GOOGLE_API_KEY=$($script:GoogleApiKey)"
        }
        'nvidia_nim' {
            $script:NvidiaApiKey   = Read-Prompt "NVIDIA API key" '' $true
            $script:NvidiaBaseUrl  = Read-Prompt "NVIDIA base URL" "https://integrate.api.nvidia.com/v1"
            $script:PrimaryModel   = Read-Prompt "NIM model" "meta/llama-3.1-70b-instruct"
            $script:ModelPlugin    = "plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin"
            $script:LlmEnvBlock    = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nNVIDIA_BASE_URL=$($script:NvidiaBaseUrl)`nMODEL_NAME=$($script:PrimaryModel)"
            $script:LlmSecretsBlock = "NVIDIA_API_KEY=$($script:NvidiaApiKey)"
        }
        'ollama' {
            $script:OllamaBaseUrl  = Read-Prompt "Ollama base URL" "http://host.docker.internal:11434"
            $script:PrimaryModel   = Read-Prompt "Ollama model" "llama3.1:8b"
            $script:ModelPlugin    = "plugins.models.ollama_enhanced:OllamaPlugin"
            $script:LlmEnvBlock    = "MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nSECONDARY_MODEL_PLUGIN_ENTRY_POINT=$($script:ModelPlugin)`nOLLAMA_BASE_URL=$($script:OllamaBaseUrl)`nMODEL_NAME=$($script:PrimaryModel)"
            $script:LlmSecretsBlock = ''
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

# ── write cloud env checklist ──────────────────────────────────────────────
function Write-CloudEnvChecklist {
    $outFile = Join-Path $OutDir 'cloud-env-checklist.txt'
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $sslSuffix     = if ($script:DbSslMode -ne 'disable') { "?ssl=$($script:DbSslMode)" }     else { '' }
    $sslSuffixSync = if ($script:DbSslMode -ne 'disable') { "?sslmode=$($script:DbSslMode)" } else { '' }
    $content = @"
# ==============================================================================
# Spotfire Copilot — AWS ECS / Fargate Cloud Env Checklist
# Generated: $ts
# Image tag: $($script:ImageTag)
# Store SECRET values in AWS Secrets Manager.
# Use CONFIG values as plain ECS task definition environment variables.
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
DATABASE_URL=postgresql+asyncpg://$($script:DbUser):$($script:DbPassword)@$($script:DbHost):$($script:DbPort)/$($script:DbName)${sslSuffix}
SYNC_DATABASE_URL=postgresql://$($script:DbUser):$($script:DbPassword)@$($script:DbHost):$($script:DbPort)/$($script:DbName)${sslSuffixSync}

# CONFIG
DB_SSLMODE=$($script:DbSslMode)

# ── 03 LLM PROVIDER ───────────────────────────────────────────────────────────
# CONFIG
$($script:LlmEnvBlock)

# SECRET
$($script:LlmSecretsBlock)
"@

    if ($script:EnableAdminConsole -eq 'yes') {
        $content += @"

# ── 04 ADMIN CONSOLE ─────────────────────────────────────────────────────────
# CONFIG
ENABLE_ADMIN_CONSOLE=true
# SECRET — same DATABASE_URL / SECRET_KEY as orchestrator
ADMIN_SECRET_KEY=$($script:CSecretKey)
"@
    }

    if ($script:EnableAgentRegistry -eq 'yes') {
        $content += @"

# ── 05 AGENT REGISTRY ────────────────────────────────────────────────────────
# CONFIG
PORT=$($script:AgentPort)
BASE_URL=$($script:AgentBaseUrl)
LOG_LEVEL=INFO
# SECRET
AUTH_CLIENT_ID=$($script:AgentClientId)
AUTH_CLIENT_SECRET=$($script:AgentClientSecret)
AUTH_SIGNING_KEY=$($script:AgentSigningKey)
ORCHESTRATOR_URL=$($script:OrchestratorUrlForAgent)
"@
    }

    Set-Content -Path $outFile -Value $content -Encoding UTF8
    Write-Ok "Cloud env checklist written: $outFile"
}

# ── build ECS task definition JSON ─────────────────────────────────────────
function ConvertTo-EnvArray {
    param([string]$Block)
    $items = @()
    foreach ($line in ($Block -split "`n")) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $line.Substring(0, $idx)
        $val = $line.Substring($idx + 1)
        $items += [ordered]@{ name = $key; value = $val }
    }
    return ($items | ConvertTo-Json -Depth 5 -Compress)
}

function ConvertTo-SecretsArray {
    param([string]$Block, [string]$Prefix)
    $items = @()
    foreach ($line in ($Block -split "`n")) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $key = ($line -split '=')[0].Trim()
        if (-not $key) { continue }
        $arn = "arn:aws:secretsmanager:$($script:AwsRegion):$($script:AwsAccountId):secret:${Prefix}/${key}"
        $items += [ordered]@{ name = $key; valueFrom = $arn }
    }
    return ($items | ConvertTo-Json -Depth 5 -Compress)
}

function Write-TaskDefinition {
    param([string]$Name, [string]$Image, [int]$Port, [string]$EnvJson, [string]$SecretsJson, [string]$OutFile)
    $td = @"
{
  "family": "$($script:EcsServicePrefix)-${Name}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "$($script:TaskCpu)",
  "memory": "$($script:TaskMemory)",
  "executionRoleArn": "$($script:EcsExecutionRoleArn)",
  "containerDefinitions": [
    {
      "name": "${Name}",
      "image": "${Image}",
      "essential": true,
      "portMappings": [{"containerPort": ${Port}, "protocol": "tcp"}],
      "repositoryCredentials": {"credentialsParameter": "$($script:AcrSecretArn)"},
      "environment": ${EnvJson},
      "secrets": ${SecretsJson},
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/$($script:EcsServicePrefix)",
          "awslogs-region": "$($script:AwsRegion)",
          "awslogs-stream-prefix": "${Name}"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -fsS http://localhost:${Port}/ || exit 1"],
        "interval": 30, "timeout": 5, "retries": 3, "startPeriod": 60
      }
    }
  ]
}
"@
    Set-Content -Path $OutFile -Value $td -Encoding UTF8
    Write-Ok "Task definition written: $OutFile"
}

# ── generate CloudShell deploy script ─────────────────────────────────────
function Write-CloudShellScript {
    param([string]$DeployDir)
    $scriptFile = Join-Path $DeployDir 'awscli-deploy.sh'
    $sslSuffix     = if ($script:DbSslMode -ne 'disable') { "?ssl=$($script:DbSslMode)" }     else { '' }
    $sslSuffixSync = if ($script:DbSslMode -ne 'disable') { "?sslmode=$($script:DbSslMode)" } else { '' }
    $dbUrl     = "postgresql+asyncpg://$($script:DbUser):$($script:DbPassword)@$($script:DbHost):$($script:DbPort)/$($script:DbName)${sslSuffix}"
    $dbSyncUrl = "postgresql://$($script:DbUser):$($script:DbPassword)@$($script:DbHost):$($script:DbPort)/$($script:DbName)${sslSuffixSync}"

    # Build secrets store commands
    $secretsCmds = @"
echo '==> Storing core secrets...'
for PAIR in \
  "SECRET_KEY=$($script:CSecretKey)" \
  "HASHED_ADMIN_PASSWORD=$($script:CHashedAdmin)" \
  "OAUTH2_CLIENT_ID=$($script:COauthId)" \
  "OAUTH2_CLIENT_SECRET_HASH=$($script:COauthHash)" \
  "DATABASE_URL=${dbUrl}" \
  "SYNC_DATABASE_URL=${dbSyncUrl}"; do
  KEY="\${PAIR%%=*}"; VAL="\${PAIR#*=}"
  aws secretsmanager create-secret --region "\${AWS_REGION}" \
    --name "\${SECRETS_PREFIX}/\${KEY}" --secret-string "\${VAL}" 2>/dev/null || \
  aws secretsmanager update-secret --region "\${AWS_REGION}" \
    --secret-id "\${SECRETS_PREFIX}/\${KEY}" --secret-string "\${VAL}"
done
"@

    # LLM secrets
    $llmSecretLines = $script:LlmSecretsBlock -split "`n" | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') }
    foreach ($line in $llmSecretLines) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2 -and $parts[0].Trim()) {
            $k = $parts[0].Trim(); $v = $parts[1].Trim()
            $secretsCmds += @"

echo '==> Storing LLM secret $k...'
aws secretsmanager create-secret --region "`$AWS_REGION" \
  --name "`$SECRETS_PREFIX/$k" --secret-string "$v" 2>/dev/null || \
aws secretsmanager update-secret --region "`$AWS_REGION" \
  --secret-id "`$SECRETS_PREFIX/$k" --secret-string "$v"
"@
        }
    }

    $adminSvcBlock = ''
    if ($script:EnableAdminConsole -eq 'yes') {
        $adminSvcBlock = @'

echo "==> Creating/updating admin console ECS service..."
aws ecs create-service --region "${AWS_REGION}" \
  --cluster "${ECS_CLUSTER}" \
  --service-name "${ECS_SERVICE_PREFIX}-admin-console" \
  --task-definition "${ADMIN_TASK_REVISION}" \
  --launch-type FARGATE --desired-count "${DESIRED_COUNT}" \
  --network-configuration "${NETWORK_CONFIG}" 2>/dev/null || \
aws ecs update-service --region "${AWS_REGION}" \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE_PREFIX}-admin-console" \
  --task-definition "${ADMIN_TASK_REVISION}" \
  --desired-count "${DESIRED_COUNT}"
'@
    }

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $content = @"
#!/usr/bin/env bash
# ==============================================================================
#  Spotfire Copilot — AWS ECS CloudShell Deploy Script
#  Generated: $ts
#  Run in AWS CloudShell: bash awscli-deploy.sh
# ==============================================================================
set -Eeuo pipefail

AWS_REGION="$($script:AwsRegion)"
ECS_CLUSTER="$($script:EcsCluster)"
ECS_SERVICE_PREFIX="$($script:EcsServicePrefix)"
SUBNETS="$($script:Subnets)"
SECURITY_GROUP="$($script:SecurityGroup)"
SECRETS_PREFIX="$($script:SecretsPrefix)"
IMAGE_TAG="$($script:ImageTag)"
TASK_CPU="$($script:TaskCpu)"
TASK_MEMORY="$($script:TaskMemory)"
DESIRED_COUNT="$($script:DesiredCount)"

echo "================================================================"
echo " Spotfire Copilot - AWS ECS Deployment"
echo " Region:  `${AWS_REGION}  Cluster: `${ECS_CLUSTER}"
echo "================================================================"

AWS_ACCOUNT_ID=`$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: `${AWS_ACCOUNT_ID}"

# IAM Execution Role
EXEC_ROLE_NAME="`${ECS_SERVICE_PREFIX}-ecs-exec-role"
aws iam create-role --region "`${AWS_REGION}" --role-name "`${EXEC_ROLE_NAME}" \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
  2>/dev/null || true
aws iam attach-role-policy --role-name "`${EXEC_ROLE_NAME}" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" 2>/dev/null || true
aws iam put-role-policy --role-name "`${EXEC_ROLE_NAME}" --policy-name "SecretsManagerRead" \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"secretsmanager:GetSecretValue\"],\"Resource\":\"arn:aws:secretsmanager:`${AWS_REGION}:`${AWS_ACCOUNT_ID}:secret:`${SECRETS_PREFIX}/*\"}]}"
EXEC_ROLE_ARN=`$(aws iam get-role --role-name "`${EXEC_ROLE_NAME}" --query Role.Arn --output text)
echo "Execution role: `${EXEC_ROLE_ARN}"

# CloudWatch log group
aws logs create-log-group --region "`${AWS_REGION}" \
  --log-group-name "/ecs/`${ECS_SERVICE_PREFIX}" 2>/dev/null || true

# Secrets
$secretsCmds

# ACR credentials
echo '==> Storing ACR pull credentials...'
aws secretsmanager create-secret --region "`${AWS_REGION}" \
  --name "`${SECRETS_PREFIX}/acr-pull" \
  --secret-string '{"username":"$($script:AcrUsername)","password":"$($script:AcrPassword)"}' 2>/dev/null || \
aws secretsmanager update-secret --region "`${AWS_REGION}" \
  --secret-id "`${SECRETS_PREFIX}/acr-pull" \
  --secret-string '{"username":"$($script:AcrUsername)","password":"$($script:AcrPassword)"}'
ACR_SECRET_ARN=`$(aws secretsmanager describe-secret --region "`${AWS_REGION}" \
  --secret-id "`${SECRETS_PREFIX}/acr-pull" --query ARN --output text)

# Patch and register task definitions
ORCH_TD=`$(cat task-def-orchestrator.json | \
  sed "s|PLACEHOLDER_EXEC_ROLE_ARN|`${EXEC_ROLE_ARN}|g; s|PLACEHOLDER_ACR_SECRET_ARN|`${ACR_SECRET_ARN}|g; s|PLACEHOLDER_ACCOUNT_ID|`${AWS_ACCOUNT_ID}|g")
ORCH_TASK_REVISION=`$(aws ecs register-task-definition --region "`${AWS_REGION}" \
  --cli-input-json "`${ORCH_TD}" --query taskDefinition.taskDefinitionArn --output text)
echo "Orchestrator task: `${ORCH_TASK_REVISION}"

$(if ($script:EnableAdminConsole -eq 'yes') {
@'
ADMIN_TD=$(cat task-def-admin-console.json | \
  sed "s|PLACEHOLDER_EXEC_ROLE_ARN|${EXEC_ROLE_ARN}|g; s|PLACEHOLDER_ACR_SECRET_ARN|${ACR_SECRET_ARN}|g; s|PLACEHOLDER_ACCOUNT_ID|${AWS_ACCOUNT_ID}|g")
ADMIN_TASK_REVISION=$(aws ecs register-task-definition --region "${AWS_REGION}" \
  --cli-input-json "${ADMIN_TD}" --query taskDefinition.taskDefinitionArn --output text)
echo "Admin Console task: ${ADMIN_TASK_REVISION}"
'@
})

NETWORK_CONFIG="awsvpcConfiguration={subnets=[`${SUBNETS}],securityGroups=[`${SECURITY_GROUP}],assignPublicIp=DISABLED}"
echo "==> Creating/updating orchestrator service..."
aws ecs create-service --region "`${AWS_REGION}" --cluster "`${ECS_CLUSTER}" \
  --service-name "`${ECS_SERVICE_PREFIX}-orchestrator" \
  --task-definition "`${ORCH_TASK_REVISION}" \
  --launch-type FARGATE --desired-count "`${DESIRED_COUNT}" \
  --network-configuration "`${NETWORK_CONFIG}" 2>/dev/null || \
aws ecs update-service --region "`${AWS_REGION}" --cluster "`${ECS_CLUSTER}" \
  --service "`${ECS_SERVICE_PREFIX}-orchestrator" \
  --task-definition "`${ORCH_TASK_REVISION}" --desired-count "`${DESIRED_COUNT}"
$adminSvcBlock

echo "==> Waiting for service stability..."
aws ecs wait services-stable --region "`${AWS_REGION}" \
  --cluster "`${ECS_CLUSTER}" --services "`${ECS_SERVICE_PREFIX}-orchestrator"
echo "================================================================"
echo " Deployment complete. Wire your ALB target group to the service."
echo "================================================================"
"@

    Set-Content -Path $scriptFile -Value $content -Encoding UTF8
    Write-Ok "CloudShell deploy script written: $scriptFile"
}

# ── direct AWS CLI deployment ──────────────────────────────────────────────
function Invoke-AwsCliDeploy {
    param([string]$DeployDir)
    Write-Section "Live AWS CLI Deployment"

    $script:AwsAccountId = (aws sts get-caller-identity --query Account --output text).Trim()
    Write-Ok "AWS Account ID: $($script:AwsAccountId)"

    $roleName = "$($script:EcsServicePrefix)-ecs-exec-role"
    Write-Info "Creating/verifying ECS execution role: $roleName"
    aws iam create-role --region $script:AwsRegion --role-name $roleName `
        --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' `
        2>$null
    aws iam attach-role-policy --role-name $roleName `
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" 2>$null
    $smPolicy = "{`"Version`":`"2012-10-17`",`"Statement`":[{`"Effect`":`"Allow`",`"Action`":[`"secretsmanager:GetSecretValue`"],`"Resource`":`"arn:aws:secretsmanager:$($script:AwsRegion):$($script:AwsAccountId):secret:$($script:SecretsPrefix)/*`"}]}"
    aws iam put-role-policy --role-name $roleName --policy-name "SecretsManagerRead" --policy-document $smPolicy
    $script:EcsExecutionRoleArn = (aws iam get-role --role-name $roleName --query Role.Arn --output text).Trim()
    Write-Ok "Execution role ARN: $($script:EcsExecutionRoleArn)"

    aws logs create-log-group --region $script:AwsRegion --log-group-name "/ecs/$($script:EcsServicePrefix)" 2>$null

    Write-Info "Storing secrets..."
    $sslSuffix     = if ($script:DbSslMode -ne 'disable') { "?ssl=$($script:DbSslMode)" }     else { '' }
    $sslSuffixSync = if ($script:DbSslMode -ne 'disable') { "?sslmode=$($script:DbSslMode)" } else { '' }
    $dbUrl     = "postgresql+asyncpg://$($script:DbUser):$($script:DbPassword)@$($script:DbHost):$($script:DbPort)/$($script:DbName)${sslSuffix}"
    $dbSyncUrl = "postgresql://$($script:DbUser):$($script:DbPassword)@$($script:DbHost):$($script:DbPort)/$($script:DbName)${sslSuffixSync}"
    foreach ($pair in @(
        "SECRET_KEY=$($script:CSecretKey)",
        "HASHED_ADMIN_PASSWORD=$($script:CHashedAdmin)",
        "OAUTH2_CLIENT_ID=$($script:COauthId)",
        "OAUTH2_CLIENT_SECRET_HASH=$($script:COauthHash)",
        "DATABASE_URL=${dbUrl}",
        "SYNC_DATABASE_URL=${dbSyncUrl}"
    )) {
        $k = $pair.Split('=')[0]; $v = $pair.Substring($k.Length + 1)
        Invoke-StoreSecret $k $v
    }
    $llmLines = $script:LlmSecretsBlock -split "`n" | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') }
    foreach ($line in $llmLines) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) { Invoke-StoreSecret $parts[0].Trim() $parts[1].Trim() }
    }

    $acrJson = "{`"username`":`"$($script:AcrUsername)`",`"password`":`"$($script:AcrPassword)`"}"
    Invoke-StoreSecretJson "acr-pull" $acrJson
    $script:AcrSecretArn = (aws secretsmanager describe-secret --region $script:AwsRegion `
        --secret-id "$($script:SecretsPrefix)/acr-pull" --query ARN --output text).Trim()
    Write-Ok "ACR secret ARN: $($script:AcrSecretArn)"

    Invoke-WriteAndRegisterTasks $DeployDir

    $netCfg = "awsvpcConfiguration={subnets=[$($script:Subnets)],securityGroups=[$($script:SecurityGroup)],assignPublicIp=DISABLED}"
    Write-Info "Creating/updating orchestrator service..."
    aws ecs create-service --region $script:AwsRegion --cluster $script:EcsCluster `
        --service-name "$($script:EcsServicePrefix)-orchestrator" `
        --task-definition $script:OrchTaskRevision `
        --launch-type FARGATE --desired-count $script:DesiredCount `
        --network-configuration $netCfg 2>$null
    if ($LASTEXITCODE -ne 0) {
        aws ecs update-service --region $script:AwsRegion --cluster $script:EcsCluster `
            --service "$($script:EcsServicePrefix)-orchestrator" `
            --task-definition $script:OrchTaskRevision --desired-count $script:DesiredCount
    }

    if ($script:EnableAdminConsole -eq 'yes') {
        Write-Info "Creating/updating admin console service..."
        aws ecs create-service --region $script:AwsRegion --cluster $script:EcsCluster `
            --service-name "$($script:EcsServicePrefix)-admin-console" `
            --task-definition $script:AdminTaskRevision `
            --launch-type FARGATE --desired-count $script:DesiredCount `
            --network-configuration $netCfg 2>$null
        if ($LASTEXITCODE -ne 0) {
            aws ecs update-service --region $script:AwsRegion --cluster $script:EcsCluster `
                --service "$($script:EcsServicePrefix)-admin-console" `
                --task-definition $script:AdminTaskRevision --desired-count $script:DesiredCount
        }
    }

    Write-Info "Waiting for orchestrator service to stabilise (up to 5 min)..."
    aws ecs wait services-stable --region $script:AwsRegion `
        --cluster $script:EcsCluster --services "$($script:EcsServicePrefix)-orchestrator"

    Write-Host ""
    Write-Host "================================================================"
    Write-Host " Deployment complete."
    Write-Host " Cluster: $($script:EcsCluster)   Region: $($script:AwsRegion)"
    Write-Host " Service: $($script:EcsServicePrefix)-orchestrator"
    Write-Host " Note: Wire your ALB target group to the service."
    Write-Host "================================================================"
}

function Invoke-StoreSecret([string]$Name, [string]$Value) {
    aws secretsmanager create-secret --region $script:AwsRegion `
        --name "$($script:SecretsPrefix)/$Name" --secret-string $Value 2>$null
    if ($LASTEXITCODE -ne 0) {
        aws secretsmanager update-secret --region $script:AwsRegion `
            --secret-id "$($script:SecretsPrefix)/$Name" --secret-string $Value
    }
    Write-Ok "  Secret: $($script:SecretsPrefix)/$Name"
}

function Invoke-StoreSecretJson([string]$Name, [string]$Json) {
    aws secretsmanager create-secret --region $script:AwsRegion `
        --name "$($script:SecretsPrefix)/$Name" --secret-string $Json 2>$null
    if ($LASTEXITCODE -ne 0) {
        aws secretsmanager update-secret --region $script:AwsRegion `
            --secret-id "$($script:SecretsPrefix)/$Name" --secret-string $Json
    }
    Write-Ok "  Secret: $($script:SecretsPrefix)/$Name"
}

function Invoke-WriteAndRegisterTasks([string]$DeployDir) {
    $orchEnv = "IMAGE_TAG=$($script:ImageTag)`nFASTAPI_APP_VERSION=$($script:ImageTag)`nLOG_LEVEL=INFO`nDB_SSLMODE=$($script:DbSslMode)`n$($script:LlmEnvBlock)"
    $orchEnvJson = ConvertTo-EnvArray $orchEnv
    $secBlock = "SECRET_KEY`nHASHED_ADMIN_PASSWORD`nOAUTH2_CLIENT_ID`nOAUTH2_CLIENT_SECRET_HASH`nDATABASE_URL`nSYNC_DATABASE_URL"
    $llmLines = $script:LlmSecretsBlock -split "`n" | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') }
    foreach ($line in $llmLines) {
        $k = ($line -split '=')[0].Trim()
        if ($k) { $secBlock += "`n$k" }
    }
    $orchSecJson = ConvertTo-SecretsArray $secBlock $script:SecretsPrefix
    $orchTdFile  = Join-Path $DeployDir 'task-def-orchestrator.json'
    Write-TaskDefinition 'orchestrator' "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:$($script:ImageTag)" 8080 $orchEnvJson $orchSecJson $orchTdFile
    $script:OrchTaskRevision = (aws ecs register-task-definition --region $script:AwsRegion `
        --cli-input-json "file://$orchTdFile" --query taskDefinition.taskDefinitionArn --output text).Trim()
    Write-Ok "Orchestrator task: $($script:OrchTaskRevision)"

    if ($script:EnableAdminConsole -eq 'yes') {
        $adminEnvJson = ConvertTo-EnvArray "IMAGE_TAG=$($script:ImageTag)`nFASTAPI_APP_VERSION=$($script:ImageTag)`nLOG_LEVEL=INFO"
        $adminSecJson = ConvertTo-SecretsArray "SECRET_KEY`nDATABASE_URL`nSYNC_DATABASE_URL" $script:SecretsPrefix
        $adminTdFile  = Join-Path $DeployDir 'task-def-admin-console.json'
        Write-TaskDefinition 'admin-console' "copilotoci.azurecr.io/spotfirecopilot/admin-console:$($script:ImageTag)" 3000 $adminEnvJson $adminSecJson $adminTdFile
        $script:AdminTaskRevision = (aws ecs register-task-definition --region $script:AwsRegion `
            --cli-input-json "file://$adminTdFile" --query taskDefinition.taskDefinitionArn --output text).Trim()
        Write-Ok "Admin Console task: $($script:AdminTaskRevision)"
    }
}

# ════════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════════
Write-Host "================================================================"
Write-Host " Spotfire Copilot — AWS ECS / Fargate Deployment"
Write-Host "================================================================"

# Phase 1: Image tag + output directory
Write-Section "Image tag"
$script:ImageTag = Read-Prompt "Copilot image tag" $DefaultTag
if (-not $script:ImageTag) { $script:ImageTag = $DefaultTag }

if (-not $OutDirExplicit) {
    $OutDir = Join-Path (Join-Path $CopilotRoot $script:ImageTag) 'backend'
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
Write-Info "Output directory: $OutDir"
$ExistingFiles = @((Join-Path $OutDir '.env'), (Join-Path $OutDir '.env.orchestrator'))

# Phase 1: Credentials
Write-Section "Credentials"
$script:CSecretKey = ''; $script:CHashedAdmin = ''; $script:COauthId = ''; $script:COauthHash = ''
$credFile  = Join-Path $OutDir 'copilot-generated-values.txt'
$haveCreds = Test-Path $credFile
if ($haveCreds) {
    $reuse = Read-YesNo "Existing credentials file found. Reuse it?" "yes"
    $haveCreds = ($reuse -eq 'yes')
}
if (-not $haveCreds) {
    $genNow = Read-YesNo "Generate credentials using generate_credentials.py?" "yes"
    if ($genNow -eq 'yes') { Invoke-GenerateCredentials $credFile }
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
Write-Info "Provide connection details for your existing PostgreSQL instance."
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
$script:EnableAdminConsole   = Read-YesNo "Deploy Admin Console?"   "yes"
$script:EnableAgentRegistry  = Read-YesNo "Deploy Agent Registry?"  "no"
$script:AgentPort = ''; $script:AgentBaseUrl = ''; $script:AgentClientId = ''
$script:AgentClientSecret = ''; $script:AgentSigningKey = ''; $script:OrchestratorUrlForAgent = ''
if ($script:EnableAgentRegistry -eq 'yes') {
    $script:AgentPort               = Read-Prompt "Agent Registry port"         "8050"
    $script:AgentBaseUrl            = Read-Prompt "Agent Registry BASE_URL"     "http://agent-registry:8050"
    $script:AgentClientId           = Read-Prompt "Agent AUTH_CLIENT_ID"        "agent-registry-client"
    $script:AgentClientSecret       = New-RandomHex32
    $script:AgentSigningKey         = New-RandomHex32
    $script:OrchestratorUrlForAgent = Read-Prompt "ORCHESTRATOR_URL for Agent"  "http://orchestrator:8080"
    Write-Ok "Agent secrets generated."
}

# Phase 2: Cloud env checklist
Write-Section "Generating cloud env checklist"
Write-CloudEnvChecklist

# Phase 3: Deployment method
Write-Section "Deployment method"
$script:CliChoice = Read-Choice "How would you like to deploy?" @(
    "cli_deploy|I have the AWS CLI installed and configured — deploy directly from this machine"
    "no_cli|I don't have the AWS CLI installed yet"
    "generate_only|I don't want to use the CLI — just generate the commands for me"
)

switch ($script:CliChoice) {
    'no_cli' {
        Write-Host ""
        Write-Info "Please install and configure the AWS CLI, then re-run this script."
        Write-Host ""
        Write-Host "  Install:    https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        Write-Host "  Configure:  aws configure"
        Write-Host "              (sets default region, access key ID, secret access key, output format)"
        Write-Host ""
        Write-Info "Your Phase 1 & 2 configuration has been saved and will be reused on re-run:"
        Write-Host "  $(Join-Path $OutDir 'cloud-env-checklist.txt')"
        Write-Host "  $(Join-Path $OutDir 'copilot-generated-values.txt')"
        Write-Host ""
        Write-Host "Re-run with:  .\spotfire-copilot-deploy-ecs.ps1 -Dir $OutDir"
        exit 0
    }
    { $_ -in @('cli_deploy','generate_only') } {
        $haveDetails = Read-YesNo "Do you have your AWS infrastructure details ready? (region, cluster, subnets, security group, ACR credentials)" "yes"
        if ($haveDetails -eq 'no') {
            Write-Host ""
            Write-Info "Please gather the following details, then re-run this script:"
            Write-Host ""
            Write-Host "  AWS ECS / Fargate details required:"
            Write-Host "  ─────────────────────────────────────────────────────────"
            Write-Host "  • AWS region             (e.g. us-east-1)"
            Write-Host "  • ECS cluster name       (pre-existing Fargate cluster)"
            Write-Host "  • Service name prefix    (e.g. spotfire-copilot)"
            Write-Host "  • Subnet IDs             (comma-separated, e.g. subnet-abc,subnet-def)"
            Write-Host "  • Security group ID      (e.g. sg-0abc123def456)"
            Write-Host "  • Secrets Manager prefix (e.g. spotfire-copilot/$($script:ImageTag))"
            Write-Host "  • Fargate CPU units      (e.g. 1024 = 1 vCPU)"
            Write-Host "  • Fargate memory MB      (e.g. 2048)"
            Write-Host "  • Desired task count     (e.g. 1)"
            Write-Host ""
            Write-Host "  ACR pull credentials (from copilotoci.azurecr.io):"
            Write-Host "  • ACR username"
            Write-Host "  • ACR password"
            Write-Host ""
            Write-Info "Your Phase 1 & 2 configuration has been saved and will be reused on re-run:"
            Write-Host "  $(Join-Path $OutDir 'cloud-env-checklist.txt')"
            Write-Host "  $(Join-Path $OutDir 'copilot-generated-values.txt')"
            Write-Host ""
            Write-Host "Re-run with:  .\spotfire-copilot-deploy-ecs.ps1 -Dir $OutDir"
            exit 0
        }

        # Collect ECS infrastructure details
        Write-Section "AWS ECS infrastructure details"
        $script:AwsRegion        = Read-Prompt "AWS region"                    ((Get-ExistingEnvValue 'AWS_REGION' $ExistingFiles) ?? 'us-east-1')
        $script:EcsCluster       = Read-Prompt "ECS cluster name"              "spotfire-copilot"
        $script:EcsServicePrefix = Read-Prompt "Service name prefix"           "spotfire-copilot"
        $script:Subnets          = Read-Prompt "Subnet IDs (comma-separated)"  ""
        $script:SecurityGroup    = Read-Prompt "Security group ID"             ""
        $script:SecretsPrefix    = Read-Prompt "Secrets Manager path prefix"   "spotfire-copilot/$($script:ImageTag)"
        $script:TaskCpu          = Read-Prompt "Fargate task CPU units"        "1024"
        $script:TaskMemory       = Read-Prompt "Fargate task memory (MB)"      "2048"
        $script:DesiredCount     = Read-Prompt "Desired task count per service" "1"

        Write-Section "ACR pull credentials"
        Write-Info "Images are pulled from copilotoci.azurecr.io. These will be stored in Secrets Manager."
        $script:AcrUsername = Read-Prompt "ACR username" "spotfirecopilot"
        $script:AcrPassword = Read-Prompt "ACR password" '' $true

        $deployDir = Join-Path $OutDir 'aws-ecs'
        New-Item -ItemType Directory -Path $deployDir -Force | Out-Null
        $script:EcsExecutionRoleArn = 'PLACEHOLDER_EXEC_ROLE_ARN'
        $script:AcrSecretArn        = 'PLACEHOLDER_ACR_SECRET_ARN'
        $script:AwsAccountId        = 'PLACEHOLDER_ACCOUNT_ID'
        $script:OrchTaskRevision    = ''
        $script:AdminTaskRevision   = ''

        if ($script:CliChoice -eq 'cli_deploy') {
            Write-Section "Deploying via AWS CLI"
            Invoke-AwsCliDeploy $deployDir
        } else {
            Write-Section "Generating CloudShell deploy script"
            $orchEnv  = "IMAGE_TAG=$($script:ImageTag)`nFASTAPI_APP_VERSION=$($script:ImageTag)`nLOG_LEVEL=INFO`nDB_SSLMODE=$($script:DbSslMode)`n$($script:LlmEnvBlock)"
            $orchEnvJ = ConvertTo-EnvArray $orchEnv
            $secB     = "SECRET_KEY`nHASHED_ADMIN_PASSWORD`nOAUTH2_CLIENT_ID`nOAUTH2_CLIENT_SECRET_HASH`nDATABASE_URL`nSYNC_DATABASE_URL"
            $llmLines = $script:LlmSecretsBlock -split "`n" | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') }
            foreach ($l in $llmLines) { $k = ($l -split '=')[0].Trim(); if ($k) { $secB += "`n$k" } }
            $orchSecJ = ConvertTo-SecretsArray $secB $script:SecretsPrefix
            Write-TaskDefinition 'orchestrator' "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:$($script:ImageTag)" 8080 $orchEnvJ $orchSecJ (Join-Path $deployDir 'task-def-orchestrator.json')
            if ($script:EnableAdminConsole -eq 'yes') {
                $adminEnvJ = ConvertTo-EnvArray "IMAGE_TAG=$($script:ImageTag)`nFASTAPI_APP_VERSION=$($script:ImageTag)`nLOG_LEVEL=INFO"
                $adminSecJ = ConvertTo-SecretsArray "SECRET_KEY`nDATABASE_URL`nSYNC_DATABASE_URL" $script:SecretsPrefix
                Write-TaskDefinition 'admin-console' "copilotoci.azurecr.io/spotfirecopilot/admin-console:$($script:ImageTag)" 3000 $adminEnvJ $adminSecJ (Join-Path $deployDir 'task-def-admin-console.json')
            }
            Write-CloudShellScript $deployDir
        }
    }
}

Write-Host ""
Write-Host "================================================================"
Write-Host " Output files:"
Write-Host "   $(Join-Path $OutDir 'cloud-env-checklist.txt')"
if ($deployDir -and (Test-Path $deployDir)) {
    Write-Host "   $(Join-Path $deployDir 'task-def-orchestrator.json')"
    if ($script:EnableAdminConsole -eq 'yes') { Write-Host "   $(Join-Path $deployDir 'task-def-admin-console.json')" }
    Write-Host "   $(Join-Path $deployDir 'awscli-deploy.sh')"
}
Write-Host ""
if ($script:CliChoice -eq 'generate_only') {
    Write-Host " To deploy from AWS CloudShell:"
    Write-Host "   1. Upload awscli-deploy.sh + task-def-*.json to CloudShell"
    Write-Host "   2. bash awscli-deploy.sh"
    Write-Host ""
}
Write-Host " ⚠  Wire your ALB target group to the ECS service to expose it."
Write-Host "================================================================"
