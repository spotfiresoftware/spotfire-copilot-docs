#Requires -Version 5.1
<#
================================================================================
 Spotfire Copilot 2.3.x Environment File Generator  (Windows / PowerShell port)
================================================================================

 Usage:
 .\Generate-CopilotEnv.ps1
 .\Generate-CopilotEnv.ps1 -Dir C:\spotfire-copilot\backend
 .\Generate-CopilotEnv.ps1 -Info
 .\Generate-CopilotEnv.ps1 -Upgrade -ImageTag 2.3.4
 .\Generate-CopilotEnv.ps1 -Upgrade -ImageTag 2.3.4 -FromDir C:\spotfire-copilot-2.3.4\backend
 .\Generate-CopilotEnv.ps1 -InstallAgentRegistry -Dir C:\spotfire-copilot\backend
 .\Generate-CopilotEnv.ps1 -Help
================================================================================
#>

[CmdletBinding()]
param(
 # All arguments are captured verbatim and parsed by hand further below. This is
 # deliberate: PowerShell's parameter binder mangles GNU-style "--long" flags (it
 # fuzzy-matches "--upgrade"/"--from-dir" onto the wrong parameter and silently drops
 # the value), which left customers who copied the documented bash command onto Windows
 # dropped back into the interactive prompts. Capturing raw args lets us accept BOTH
 # "-Upgrade -FromDir <dir>" and "--upgrade --from-dir <dir>" identically.
 [Parameter(ValueFromRemainingArguments = $true)]
 [string[]]$CliArgs
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Global state (mirrors the bash globals)
# ----------------------------------------------------------------------------
$script:SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:START_DIR  = (Get-Location).Path
$script:DEFAULT_IMAGE_TAG = if ($env:DEFAULT_IMAGE_TAG) { $env:DEFAULT_IMAGE_TAG } else { '2.3.4' }
$script:DEFAULT_AGENT_TAG = if ($env:DEFAULT_AGENT_TAG) { $env:DEFAULT_AGENT_TAG } else { '' }
# All installs live under a single parent folder, one subfolder per version:
#   <root>/spotfire-copilot/<image-tag>/backend
# The real backend directory is finalized once the image tag is known (interactive),
# or taken from -Dir / the OUT_DIR environment variable.
$script:COPILOT_ROOT_DIR = if ($env:COPILOT_ROOT_DIR) { $env:COPILOT_ROOT_DIR } else { Join-Path $script:START_DIR 'spotfire-copilot' }
if ($env:OUT_DIR) {
    $script:OUT_DIR = $env:OUT_DIR
    $script:OUT_DIR_EXPLICIT = 'yes'
} else {
    $script:OUT_DIR = Join-Path (Join-Path $script:COPILOT_ROOT_DIR $script:DEFAULT_IMAGE_TAG) 'backend'
    $script:OUT_DIR_EXPLICIT = 'no'
}
$script:FROM_DIR = ''
$script:ASSUME_YES = 'no'
$script:DEFAULT_CREDENTIALS_FILE = ''
$script:CREDENTIALS_SCRIPT = ''
$script:MODE = 'interactive'
$script:UPGRADE_IMAGE_TAG = ''
$script:UPGRADE_AGENT_TAG = ''
$script:INSTALL_PREREQS = 'prompt'
$script:PYTHON_BIN = if ($env:PYTHON_BIN) { $env:PYTHON_BIN } else { '' }
$script:PYTHON_ARGS = @()   # extra args (e.g. when using the `py` launcher)
$script:POSTGRES_RESET_LOCAL_VOLUME_SELECTED = 'no'
$script:LAST_DIR_STATE_DIR = Join-Path ($(if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME })) '.spotfire-copilot-env-generator'
$script:LAST_DIR_FILE = Join-Path $script:LAST_DIR_STATE_DIR 'last-dir'
$script:WITH_DEEPAGENTS = 'no'
$script:INSTALL_AGENT_REGISTRY_ONLY = 'no'
$script:DEEPAGENTS_SCRIPT = ''
$script:UseColor = $true
$script:EXISTING_FILES = @()

# Working variables populated as the flow runs (declared to avoid surprises)
$script:CREDENTIALS_FILE = ''

# ----------------------------------------------------------------------------
# color / output helpers
# ----------------------------------------------------------------------------
function Write-Section { param([string]$Text)
    Write-Host ''
    if ($script:UseColor) { Write-Host "== $Text ==" -ForegroundColor Magenta }
    else { Write-Host "== $Text ==" }
}
function Write-Info { param([string]$Text)
    if ($script:UseColor) { Write-Host 'INFO:' -ForegroundColor Cyan -NoNewline; Write-Host " $Text" }
    else { Write-Host "INFO: $Text" }
}
function Write-Ok { param([string]$Text)
    if ($script:UseColor) { Write-Host 'OK:' -ForegroundColor Green -NoNewline; Write-Host " $Text" }
    else { Write-Host "OK: $Text" }
}
function Write-Warn { param([string]$Text)
    if ($script:UseColor) { Write-Host 'WARN:' -ForegroundColor Yellow -NoNewline; Write-Host " $Text" }
    else { Write-Host "WARN: $Text" }
}
function Invoke-Die { param([string]$Text)
    if ($script:UseColor) { Write-Host 'ERROR:' -ForegroundColor Red -NoNewline; Write-Host " $Text" }
    else { Write-Host "ERROR: $Text" }
    exit 1
}
function Get-Timestamp { (Get-Date -Format 'yyyyMMdd_HHmmss') }

function Test-CommandExists { param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}
function Require-Cmd { param([string]$Name)
    if (-not (Test-CommandExists $Name)) { Invoke-Die "Required command not found: $Name" }
}

# Best-effort POSIX-mode equivalent. Restrict a file to the current user.
function Protect-File { param([string]$Path)
    try {
        if (Test-Path $Path) {
            $me = "$env:USERDOMAIN\$env:USERNAME"
            & icacls $Path /inheritance:r /grant:r "${me}:F" 2>$null | Out-Null
 }
 } catch { }
}

# Write text using LF line endings (so Docker/Compose parse env files correctly).
function Write-TextFileLF { param([string]$Path, [string]$Content)
    $normalized = ($Content -replace "`r`n", "`n")
    if (-not $normalized.EndsWith("`n")) { $normalized += "`n" }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
 [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

# ----------------------------------------------------------------------------
# generic helpers
# ----------------------------------------------------------------------------
function Get-StripOuterQuotes { param([string]$Value)
    if ($null -eq $Value) { return '' }
    $v = $Value -replace "`r$", ''
    $v = $v.Trim()
    if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) {
        $v = $v.Substring(1, $v.Length - 2)
 } elseif ($v.Length -ge 2 -and $v.StartsWith("'") -and $v.EndsWith("'")) {
        $v = $v.Substring(1, $v.Length - 2)
 }
    return $v
}

# Search a list of env files for the LAST occurrence of `key = value`.
# Returns $null when not found (callers test for $null).
function Get-Existing { param([string]$Key, [string[]]$Files)
    foreach ($f in $Files) {
        if ([string]::IsNullOrEmpty($f)) { continue }
        if (-not (Test-Path $f)) { continue }
        $pattern = "^\s*$([regex]::Escape($Key))\s*="
        $line = $null
        foreach ($l in (Get-Content -LiteralPath $f)) {
            if ($l -match $pattern) { $line = $l }
 }
        if ($null -ne $line) {
            $val = $line.Substring($line.IndexOf('=') + 1)
            return (Get-StripOuterQuotes $val)
 }
 }
    return $null
}

# Credentials file uses `key: value` or `key=value`.
function Get-FromCredentialsFile { param([string]$Key, [string]$File)
    if ([string]::IsNullOrEmpty($File) -or -not (Test-Path $File)) { return $null }
    $pattern = "^\s*$([regex]::Escape($Key))\s*[:=]"
    $line = $null
    foreach ($l in (Get-Content -LiteralPath $File)) {
        if ($l -match $pattern) { $line = $l }
 }
    if ($null -eq $line) { return $null }
    if ($line.Contains('=')) { $value = $line.Substring($line.IndexOf('=') + 1) }
    else { $value = $line.Substring($line.IndexOf(':') + 1) }
    return (Get-StripOuterQuotes $value)
}

function Get-Mask { param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '<empty>' }
    $len = $Value.Length
    if ($len -le 8) { return '****' }
    return ('{0}...{1}' -f $Value.Substring(0,4), $Value.Substring($len-4,4))
}

# Prompt for a value with an optional default. -Secret hides input.
function Read-Prompt {
    param([string]$Label, [string]$Default = '', [switch]$Secret, [string]$DefaultHint = 'press Enter to reuse existing')
    if ($Secret) {
        if (-not [string]::IsNullOrEmpty($Default)) {
            $sec = Read-Host -Prompt "$Label [$DefaultHint]" -AsSecureString
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

# Numbered menu. $Options is an array of "value|display" strings.
# Accepts the number, or (for 2-option menus) y/yes/n/no, or a matching value/display.
function Read-ChooseNum {
    param([string]$Label, [int]$DefaultNumber, [string[]]$Options)
    while ($true) {
        Write-Host ''
        Write-Host $Label
        $i = 1
        foreach ($option in $Options) {
            $display = $option.Substring($option.IndexOf('|') + 1)
            Write-Host ("  {0}) {1}" -f $i, $display)
            $i++
 }
        $choice = Read-Host -Prompt "Enter number [$DefaultNumber]"
        if ([string]::IsNullOrEmpty($choice)) { $choice = "$DefaultNumber" }
        $choice = $choice.Trim()

        # Number-only input. Text shortcuts like "yes"/"no" are intentionally not
        # accepted; the user must enter the number shown in the menu.
        if ($choice -match '^[0-9]+$') {
            $n = [int]$choice
            if ($n -ge 1 -and $n -le $Options.Count) {
                $selected = $Options[$n - 1]
                return $selected.Substring(0, $selected.IndexOf('|'))
            }
        }
        Write-Warn "Please enter only the number shown - a number from 1 to $($Options.Count)."
 }
}

function Read-YesNo { param([string]$Label, [string]$Default = 'no')
    $defNum = 2
    if ($Default -eq 'yes') { $defNum = 1 }
    return (Read-ChooseNum -Label $Label -DefaultNumber $defNum -Options @('yes|Yes', 'no|No'))
}

# Prompt that refuses to accept a blank value. Used where a placeholder or empty
# value would silently produce a broken configuration.
function Read-RequiredPrompt { param([string]$Label, [string]$Default = '', [switch]$Secret)
    while ($true) {
        if ($Secret) { $value = Get-StripOuterQuotes (Read-Prompt $Label $Default -Secret) }
        else         { $value = Get-StripOuterQuotes (Read-Prompt $Label $Default) }
        if (-not [string]::IsNullOrEmpty($value)) { return $value }
        Write-Warn "$Label cannot be blank."
    }
}

function Backup-File { param([string]$File)
    if (-not (Test-Path $File)) { return }
    $backup = "$File.bak.$(Get-Timestamp)"
    Copy-Item -LiteralPath $File -Destination $backup -Force
    Write-Info "Backed up $File -> $backup"
}

function Write-EnvFile { param([string]$File, [string]$Content)
    Backup-File $File
    Write-TextFileLF -Path $File -Content $Content
    Protect-File $File
    Write-Ok "Wrote $File"
}

function ConvertTo-UrlEncoded { param([string]$Value)
    return [uri]::EscapeDataString($Value)
}

function ConvertTo-SingleQuotedEnvValue { param([string]$Value)
    if ($null -eq $Value) { $Value = '' }
    $escaped = $Value -replace "'", "'\''"
    return "'$escaped'"
}

# Remove labeled comment lines and collapse runs of blank lines to a single one.
function Compress-EnvContent { param([string]$Content)
    $lines = ($Content -replace "`r`n", "`n").Split("`n")
    $labelPattern = '^# (REQUIRED|OPTIONAL|RECOMMENDED|INFO|TODO|REQUIRED FOR RAG|REQUIRED FOR PRODUCTION):'
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
        if ($l -match $labelPattern) { continue }
        $kept.Add($l)
 }
    # collapse multiple consecutive blank lines
    $out = New-Object System.Collections.Generic.List[string]
    $prevBlank = $false
    foreach ($l in $kept) {
        $isBlank = ($l.Trim() -eq '')
        if ($isBlank -and $prevBlank) { continue }
        $out.Add($l)
        $prevBlank = $isBlank
 }
    return ($out -join "`n")
}

function Get-RandomHex32 {
    $bytes = New-Object 'System.Byte[]' 32
 [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}
# URL-safe random token (base64url, no padding). Matches the documented spec for
# AUTH_SIGNING_KEY ("URL-safe random key") and is equivalent to:
#   python -c "import secrets; print(secrets.token_urlsafe(32))"
function Get-RandomUrlSafeToken {
    $bytes = New-Object 'System.Byte[]' 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ([Convert]::ToBase64String($bytes) -replace '\+', '-' -replace '/', '_' -replace '=', '')
}

# Database URL builder. Sets script-scoped DATABASE_URL / SYNC_DATABASE_URL.
function Build-DatabaseUrls {
    $userEnc = ConvertTo-UrlEncoded $script:POSTGRES_USER
    $passEnc = ConvertTo-UrlEncoded $script:POSTGRES_PASSWORD
    $asyncBase = "postgresql+asyncpg://${userEnc}:${passEnc}@$($script:POSTGRES_HOST):$($script:POSTGRES_PORT)/$($script:POSTGRES_DB)"
    $syncBase  = "postgresql://${userEnc}:${passEnc}@$($script:POSTGRES_HOST):$($script:POSTGRES_PORT)/$($script:POSTGRES_DB)"
    # Normalize DB_SSLMODE: trim + lowercase, then map common aliases to canonical
    # libpq sslmode values. Prevents malformed URLs (e.g. a user typing "DISABLE",
    # "false", or "off" for a PostgreSQL server without SSL).
    $sslmode = ("$($script:DB_SSLMODE)").Trim().ToLower()
    switch -Regex ($sslmode) {
        '^(|disable|disabled|false|off|none|no)$'      { $sslmode = 'disable' }
        '^(true|on|yes|enable|enabled|ssl)$'           { $sslmode = 'require' }
        '^(allow|prefer|require|verify-ca|verify-full)$' { }
        default {
            Write-Warn "Unrecognized DB_SSLMODE '$($script:DB_SSLMODE)'; falling back to 'require'. Valid values: disable, allow, prefer, require, verify-ca, verify-full."
            $sslmode = 'require'
        }
    }
    $script:DB_SSLMODE = $sslmode   # write normalized value back so the env file matches the URL

    # SQLAlchemy + asyncpg does not accept sslmode=... in the URL. asyncpg's async URL
    # uses ssl=<mode>; the sync (psycopg2) URL uses sslmode=<mode>.
    # For "disable" the SSL query is omitted ENTIRELY: passing ssl=disable as a string
    # is treated as truthy by some asyncpg/SQLAlchemy versions and would wrongly ENABLE
    # SSL against a server that has none.
    if ($sslmode -eq 'disable') {
        $script:DATABASE_URL = $asyncBase
        $script:SYNC_DATABASE_URL = $syncBase
    } else {
        $script:DATABASE_URL = "${asyncBase}?ssl=${sslmode}"
        $script:SYNC_DATABASE_URL = "${syncBase}?sslmode=${sslmode}"
    }
}

# Update or append KEY=VALUE in a file.
function Set-EnvValue { param([string]$File, [string]$Key, [string]$Value)
    if (-not (Test-Path $File)) { Write-TextFileLF -Path $File -Content '' }
    Protect-File $File
    $content = [System.IO.File]::ReadAllText($File) -replace "`r`n", "`n"
    $pattern = "(?m)^\s*$([regex]::Escape($Key))=.*$"
    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, "$Key=$Value")
 } else {
        if (-not $content.EndsWith("`n")) { $content += "`n" }
        $content += "`n$Key=$Value`n"
 }
    Write-TextFileLF -Path $File -Content $content
}

function Read-EnvValue { param([string]$File, [string]$Key)
    if (-not (Test-Path $File)) { return $null }
    return (Get-Existing -Key $Key -Files @($File))
}

# Patch image tags in an existing compose file to use ${IMAGE_TAG} variables.
function Update-ComposeImageRefs { param([string]$ComposeFile)
    if (-not (Test-Path $ComposeFile)) { return }
    Copy-Item -LiteralPath $ComposeFile -Destination "$ComposeFile.bak.$(Get-Timestamp)" -Force
    $text = [System.IO.File]::ReadAllText($ComposeFile) -replace "`r`n", "`n"
    $text = [regex]::Replace($text, '(copilotoci\.azurecr\.io/spotfirecopilot/llm-orchestrator:)[^\s]+', '${1}${IMAGE_TAG}')
    $text = [regex]::Replace($text, '(copilotoci\.azurecr\.io/spotfirecopilot/data-loader-pdf-pypdf:)[^\s]+', '${1}${IMAGE_TAG}')
    $text = [regex]::Replace($text, '(copilotoci\.azurecr\.io/spotfirecopilot/agent-container:)[^\s]+', '${1}${AGENT_CONTAINER_TAG}')
    Write-TextFileLF -Path $ComposeFile -Content $text
    Write-Ok "Patched image references in $ComposeFile to use variables."
}
# ============================================================================
# Validation helpers — paste these into Generate-CopilotEnv.ps1
# right after the Read-YesNo function definition.
# ============================================================================

# PostgreSQL identifier rules (database name / username): must start with a
# letter or underscore, then letters, digits, or underscores; max 63 chars.
# Deliberately rejects pure numbers like "2" (a common slip when the prompt
# sits under a numbered menu) and anything with spaces, dots, or hyphens.
function Test-PgIdentifier { param([string]$Value)
    if ($null -eq $Value) { return $false }
    return ($Value -match '^[A-Za-z_][A-Za-z0-9_]{0,62}$')
}

# Prompt for a PostgreSQL identifier, validating both the input and the default.
# If the previously stored value is not a valid identifier (e.g. a stray "2"
# left over from an earlier run), it is ignored and the safe fallback is shown
# instead, so a bad value can never keep coming back as the default.
function Read-PgIdentifier { param([string]$Label, [string]$Stored, [string]$Fallback = 'orchestrator')
    $def = if (Test-PgIdentifier $Stored) { $Stored } else { $Fallback }
    while ($true) {
        $value = Get-StripOuterQuotes (Read-Prompt $Label $def)
        if (Test-PgIdentifier $value) { return $value }
        Write-Warn "Invalid PostgreSQL name '$value'. Start with a letter or underscore, then letters, digits, or underscores (max 63 chars). Example: orchestrator"
    }
}

# OCI/Docker image tag rules: max 128 chars, must start with an alphanumeric or
# underscore, then alphanumerics, '.', '_' or '-'. Permits 2.3.4, 1.1.0, latest.
function Test-TagFormat { param([string]$Value)
    if ($null -eq $Value) { return $false }
    return ($Value -match '^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$')
}

# Best-effort registry existence check. Requires the user to be logged in
# (docker login copilotoci.azurecr.io). Returns: 0 found, 1 not found, 2 unable to check.
function Get-TagRegistryStatus { param([string]$Repo, [string]$Tag)
    # Disabled: the live registry probe caused a multi-second stall on every tag
    # prompt when not logged in to the private ACR. 2 = "unable to check", which
    # callers already handle by skipping silently. Remove this line to re-enable.
    return 2
    if (-not (Test-CommandExists 'docker')) { return 2 }
    try {
        & docker manifest inspect "${Repo}:${Tag}" 1>$null 2>$null
        if ($LASTEXITCODE -eq 0) { return 0 } else { return 1 }
    } catch { return 1 }
}

# Prompt for an image tag with format validation, and (when a repo is supplied
# and Docker is available/logged in) a soft existence check that warns instead
# of hard-failing. A blank entry is returned as '' so callers that require a
# value can re-ask. NOTE: uses if/elseif rather than switch on purpose —
# 'continue' inside a PowerShell switch would not continue the while loop.
function Read-ImageTag { param([string]$Label, [string]$Default = '', [string]$Repo = '')
    while ($true) {
        $tag = Get-StripOuterQuotes (Read-Prompt $Label $Default)
        if ([string]::IsNullOrEmpty($tag)) { return '' }
        if (-not (Test-TagFormat $tag)) {
            Write-Warn "Invalid image tag '$tag'. Allowed: letters, digits, '.', '_', '-' (max 128 chars). Example: 2.3.4 or latest"
            continue
        }
        if (-not [string]::IsNullOrEmpty($Repo)) {
            $status = Get-TagRegistryStatus $Repo $tag
            if ($status -eq 0) {
                Write-Ok "Verified ${Repo}:${tag} exists in the registry."
            } elseif ($status -eq 1) {
                Write-Warn "Tag '$tag' was not found in $Repo. Check for a typo, or run 'docker login copilotoci.azurecr.io' first."
                $useAnyway = Read-YesNo "Use '$tag' anyway?" 'no'
                if ($useAnyway -ne 'yes') { continue }
            }
            # status 2: Docker unavailable / not usable here; skip existence check silently.
        }
        return $tag
    }
}

function Show-Help {
@'
Spotfire Copilot 2.3.x Environment File Generator (PowerShell)

Usage:
 .\Generate-CopilotEnv.ps1 [options]

Interactive generation:
 .\Generate-CopilotEnv.ps1
 .\Generate-CopilotEnv.ps1 -Dir C:\spotfire-copilot\backend
 # Default output directory is: .\spotfire-copilot\<image-tag>\backend

Info:
 .\Generate-CopilotEnv.ps1 -Info
 .\Generate-CopilotEnv.ps1 -Dir C:\spotfire-copilot\backend -Info

Upgrade tags and create a new versioned folder:
 .\Generate-CopilotEnv.ps1 -Upgrade -ImageTag 2.3.4
 .\Generate-CopilotEnv.ps1 -Upgrade -ImageTag 2.3.4 -FromDir C:\spotfire-copilot\2.3.4\backend
 .\Generate-CopilotEnv.ps1 -Upgrade -ImageTag 2.3.4 -AgentTag 1.0.0

Options:
 -Help                  Show this help.
 -Info                  Show current generated env summary.
 -Upgrade               Update IMAGE_TAG, FASTAPI_APP_VERSION, and optionally AGENT_CONTAINER_TAG.
 -ImageTag TAG          Orchestrator/admin/data-loader image tag for upgrade mode.
 -AgentTag TAG          Agent Registry image tag for upgrade mode.
 -Dir DIR               Output directory. Default: .\spotfire-copilot\<image-tag>\backend.
 -FromDir DIR           Source directory for upgrade mode. Defaults to last used directory.
 -Yes                   Accept the auto-detected upgrade source without prompting (for non-interactive/CI runs).
 -InstallPrereqs        Install/check prerequisites automatically when possible.
 -NoInstallPrereqs      Do not install prerequisites; fail if Python/bcrypt are missing.
 -InstallDeepagents     After core generation, run standalone DeepAgents installer if found.
 -DeepagentsScript PATH Optional path to standalone DeepAgents installer.
 -CredentialsScript PATH Optional path to generate_credentials.py. Default: next to this installer.
 -InstallAgentRegistry  Add/update only Agent Registry in an existing backend folder. Use with -Dir.
 -NoColor               Disable colored output.

Credentials:
 This installer does not generate credentials itself. It runs generate_credentials.py,
 the official generator shipped with the Spotfire Copilot backend package.
 Place generate_credentials.py next to this installer.
 If you already have credentials, answer Yes at the credentials question and provide
 the existing copilot-generated-values.txt instead.
 Expected keys: SECRET_KEY, HASHED_ADMIN_PASSWORD, OAUTH2_CLIENT_ID, OAUTH2_CLIENT_SECRET_HASH.
'@ | Write-Host
}

function Resolve-NormalizedPath { param([string]$P)
    if ([System.IO.Path]::IsPathRooted($P)) { return $P }
    return (Join-Path (Get-Location).Path $P)
}

function Save-LastOutDir {
    if (-not (Test-Path $script:LAST_DIR_STATE_DIR)) {
        New-Item -ItemType Directory -Path $script:LAST_DIR_STATE_DIR -Force | Out-Null
 }
    Write-TextFileLF -Path $script:LAST_DIR_FILE -Content $script:OUT_DIR
    Protect-File $script:LAST_DIR_FILE
}

function Get-LastOutDir {
    if (-not (Test-Path $script:LAST_DIR_FILE)) { return $null }
    $d = (Get-Content -LiteralPath $script:LAST_DIR_FILE | Select-Object -First 1)
    if ($null -ne $d) { $d = $d.Trim() }
    if ([string]::IsNullOrEmpty($d)) { return $null }
    return $d
}

function Get-DefaultCredentialsFile {
    $candidates = @(
 (Join-Path $script:START_DIR  'copilot-generated-values.txt'),
 (Join-Path $script:SCRIPT_DIR 'copilot-generated-values.txt'),
 (Join-Path $script:OUT_DIR    'copilot-generated-values.txt')
 )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return (Join-Path $script:OUT_DIR 'copilot-generated-values.txt')
}

function Copy-CredentialsToOutDir { param([string]$SourceFile)
    $target = Join-Path $script:OUT_DIR 'copilot-generated-values.txt'
    if (-not (Test-Path $SourceFile)) { return }
    if ($SourceFile -ne $target) {
        Copy-Item -LiteralPath $SourceFile -Destination $target -Force
        Protect-File $target
        Write-Ok "Copied credential file into backend folder: $target"
 }
    $script:CREDENTIALS_FILE = $target
}

function Resolve-CredentialsPath { param([string]$P)
    if ((Test-Path $P -PathType Container) -or $P.EndsWith('\') -or $P.EndsWith('/')) {
        $P = (Join-Path ($P.TrimEnd('\','/')) 'copilot-generated-values.txt')
 }
    return $P
}

# The Compose "postgres_data" volume is given a stable, version-independent name of
# "<project>_postgres_data" (the image tag is NOT part of the name) so the database
# survives image-tag upgrades. Scope all detection/reset logic to THIS deployment's
# project volume so we never match (or delete) a postgres_data volume that belongs to
# another project on the same host.
function Get-ComposePostgresVolumeName {
    $proj = if ([string]::IsNullOrEmpty($script:COMPOSE_PROJECT_NAME)) { 'spotfire-copilot' } else { $script:COMPOSE_PROJECT_NAME }
    return "${proj}_postgres_data"
}

function Test-ExistingBackendState {
    if (Test-Path (Join-Path $script:OUT_DIR '.env.orchestrator')) { return $true }
    if (Test-CommandExists 'docker') {
        try {
            & docker volume inspect (Get-ComposePostgresVolumeName) 1>$null 2>$null
            if ($LASTEXITCODE -eq 0) { return $true }
 } catch { }
 }
    return $false
}

function Test-ExistingComposePostgresVolume {
    if (-not (Test-CommandExists 'docker')) { return $false }
    try {
        & docker volume inspect (Get-ComposePostgresVolumeName) 1>$null 2>$null
        return ($LASTEXITCODE -eq 0)
 } catch { return $false }
}

# Emit a PowerShell helper that resets ONLY the local compose postgres volume.
function Write-ResetComposePostgresHelper {
    $helper = Join-Path $script:OUT_DIR 'reset-local-postgres-volume.ps1'
    $body = @'
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ComposeFile = Join-Path $ScriptDir 'docker-compose.yml'
$EnvFile     = Join-Path $ScriptDir '.env'
Set-Location $ScriptDir

if (-not (Test-Path $ComposeFile)) {
 Write-Host "ERROR: docker-compose.yml not found at: $ComposeFile"
 exit 1
}

$ProjectName = ''
$ImageTag = ''
if (Test-Path $EnvFile) {
 foreach ($l in (Get-Content -LiteralPath $EnvFile)) {
 if ($l -match '^COMPOSE_PROJECT_NAME=') { $ProjectName = ($l -replace '^[^=]*=', '').Trim() }
 if ($l -match '^IMAGE_TAG=') { $ImageTag = ($l -replace '^[^=]*=', '').Trim() }
 }
}
if ([string]::IsNullOrEmpty($ProjectName)) { $ProjectName = 'spotfire-copilot' }
if ([string]::IsNullOrEmpty($ImageTag)) { $ImageTag = 'latest' }
$PostgresVolume = "${ProjectName}_postgres_data"

Write-Host @"
This will stop the Copilot Docker Compose stack and delete ONLY the local PostgreSQL volume below:

 $PostgresVolume

Use this only for a fresh lab/test install where Copilot backend data can be discarded.
It will remove users, OAuth clients, conversations, threads, agents, and any other state stored in the local Postgres volume.

It will NOT run:
 docker compose down -v

Instead, it will run:
 docker compose down
 (back up the volume to a local .tgz snapshot)
 docker volume rm "$PostgresVolume"
 docker compose up -d --force-recreate
"@

docker volume inspect $PostgresVolume 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
 Write-Host "ERROR: Expected PostgreSQL volume was not found: $PostgresVolume"
 Write-Host ''
 Write-Host 'Available postgres_data-like volumes:'
 docker volume ls -q | Where-Object { $_ -match '_postgres_data(_|$)' }
 Write-Host ''
 Write-Host 'No volume was deleted.'
 exit 1
}

$answer = Read-Host "Type DELETE to remove only $PostgresVolume"
if ($answer -ne 'DELETE') { Write-Host 'Cancelled.'; exit 1 }

docker compose --project-directory $ScriptDir -f $ComposeFile down
$BackupFile = Join-Path $ScriptDir ("postgres_data_backup_{0}.tgz" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Write-Host "Backing up volume $PostgresVolume to $BackupFile before deletion..."
docker run --rm -v "${PostgresVolume}:/from" -v "${ScriptDir}:/backup" alpine tar czf "/backup/$(Split-Path -Leaf $BackupFile)" -C /from .
if ($LASTEXITCODE -ne 0) {
 Write-Host 'ERROR: Backup failed; aborting without deleting the volume.'
 docker compose --project-directory $ScriptDir -f $ComposeFile up -d
 exit 1
}
Write-Host "Backup complete: $BackupFile"
docker volume rm $PostgresVolume
docker compose --project-directory $ScriptDir -f $ComposeFile up -d --force-recreate
'@
    Write-TextFileLF -Path $helper -Content $body
    Protect-File $helper
    Write-Ok "Wrote local PostgreSQL reset helper: $helper"
}

function Warn-AdminPasswordRegenExistingState {
    if (Test-ExistingBackendState) {
        Write-Warn "Existing Copilot env files or PostgreSQL volume detected. Generating a new HASHED_ADMIN_PASSWORD updates the env file, but it may not reset the already-created admin user stored in PostgreSQL. For an existing deployment, reuse the original admin password or reset it through the application/database process. Only recreate the PostgreSQL volume for a fresh lab install where data can be discarded."
 }
}

function Set-DefaultDirForInfo {
    if ($script:OUT_DIR_EXPLICIT -eq 'no') {
        $last = Get-LastOutDir
        if (-not [string]::IsNullOrEmpty($last)) { $script:OUT_DIR = $last }
 }
}

function Get-VersionedBackendDir { param([string]$Tag)
    # Standard backend path for a given image tag: <root>/spotfire-copilot/<tag>/backend
    return (Join-Path (Join-Path $script:COPILOT_ROOT_DIR $Tag) 'backend')
}

function Get-VersionedBackendDirFromSource { param([string]$SrcDir, [string]$Tag)
    $verDir = Split-Path -Parent $SrcDir   # <root>/spotfire-copilot/<oldtag>  (new layout)
    $root   = Split-Path -Parent $verDir   # <root>/spotfire-copilot           (new layout)
    # If the source does not follow the new "<root>/spotfire-copilot/<tag>/backend"
    # layout (e.g. an older "spotfire-copilot-<tag>/backend" install), fall back to the
    # standard versioned root so upgrades migrate into the new structure.
    if ((Split-Path -Leaf $root) -ne 'spotfire-copilot') { $root = $script:COPILOT_ROOT_DIR }
    return (Join-Path (Join-Path $root $Tag) 'backend')
}

function Set-FinalOutDirForTag { param([string]$Tag)
    # Finalize the interactive backend directory once the image tag is known. Honors an
    # explicit -Dir/OUT_DIR; otherwise defaults to the versioned path and lets the user
    # confirm or override it. Creates the directory and refreshes existing-file/credential
    # detection so re-runs of the same tag reuse prior values.
    if ($script:OUT_DIR_EXPLICIT -eq 'no') {
        $computed = Get-VersionedBackendDir $Tag
        $userInput = Read-Host "Backend output directory [$computed]"
        $userInput = ($userInput -replace '[\x00-\x1f]', '')
        $userInput = Get-StripOuterQuotes $userInput
        if (-not [string]::IsNullOrEmpty($userInput)) { $computed = $userInput }
        $script:OUT_DIR = $computed
    }
    if (-not (Test-Path $script:OUT_DIR)) { New-Item -ItemType Directory -Path $script:OUT_DIR -Force | Out-Null }
    Push-Location $script:OUT_DIR; $script:OUT_DIR = (Get-Location).Path; Pop-Location
    $script:DEFAULT_CREDENTIALS_FILE = Get-DefaultCredentialsFile
    $script:EXISTING_FILES = @(
        (Join-Path $script:OUT_DIR '.env'),
        (Join-Path $script:OUT_DIR '.env.orchestrator'),
        (Join-Path $script:OUT_DIR '.env.dataloader'),
        (Join-Path $script:OUT_DIR '.env.agent-registry')
    )
    Write-Info "Backend output directory: $($script:OUT_DIR)"
}

function Copy-ExistingConfigToNewDir { param([string]$From, [string]$To)
    if (-not (Test-Path $To)) { New-Item -ItemType Directory -Path $To -Force | Out-Null }
    foreach ($f in @('.env', '.env.orchestrator', '.env.dataloader', '.env.agent-registry', 'docker-compose.yml', 'copilot-generated-values.txt')) {
        $src = Join-Path $From $f
        if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $To $f) -Force }
 }
}

# ----------------------------------------------------------------------------
# Python prerequisite handling (credential bcrypt hashing)
# ----------------------------------------------------------------------------
function Invoke-Python { param([string[]]$PyArgs, [string]$StdinText)
    $argv = @()
    if ($script:PYTHON_ARGS) { $argv += $script:PYTHON_ARGS }
    $argv += $PyArgs
    if ($null -ne $StdinText) {
        return ($StdinText | & $script:PYTHON_BIN @argv 2>&1)
 } else {
        return (& $script:PYTHON_BIN @argv 2>&1)
 }
}

# Find a Python 3.11+ interpreter. Sets $script:PYTHON_BIN / $script:PYTHON_ARGS.
function Select-PythonBin {
    $candidates = @()
    if (-not [string]::IsNullOrEmpty($script:PYTHON_BIN)) { $candidates += ,@($script:PYTHON_BIN, @()) }
    # Windows `py` launcher with explicit versions, then bare interpreters.
    if (Test-CommandExists 'py') {
        $candidates += ,@('py', @('-3.12'))
        $candidates += ,@('py', @('-3.11'))
        $candidates += ,@('py', @('-3'))
 }
    $candidates += ,@('python3.12', @())
    $candidates += ,@('python3.11', @())
    $candidates += ,@('python3', @())
    $candidates += ,@('python', @())

    foreach ($cand in $candidates) {
        $exe = $cand[0]; $pre = $cand[1]
        if ([string]::IsNullOrEmpty($exe)) { continue }
        if (-not (Test-CommandExists $exe)) { continue }
        try {
            $code = 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'
            & $exe @pre '-c' $code 2>$null
            if ($LASTEXITCODE -eq 0) {
                $script:PYTHON_BIN = $exe
                $script:PYTHON_ARGS = $pre
                return $true
 }
 } catch { }
 }
    return $false
}

function Test-PythonVersionOk { return (Select-PythonBin) }

function Test-PythonHasBcrypt {
    if ([string]::IsNullOrEmpty($script:PYTHON_BIN)) { if (-not (Select-PythonBin)) { return $false } }
    try {
        Invoke-Python -PyArgs @('-c', 'import bcrypt') -StdinText $null | Out-Null
        return ($LASTEXITCODE -eq 0)
 } catch { return $false }
}

function Install-PythonPackagesWindows {
    if (Test-CommandExists 'winget') {
        Write-Info 'Attempting to install Python 3.11 via winget...'
        try {
            & winget install --id Python.Python.3.11 -e --accept-source-agreements --accept-package-agreements
 } catch {
            Invoke-Die "winget failed to install Python. Install Python 3.11+ from https://www.python.org/downloads/ and rerun."
 }
 } else {
        Invoke-Die "No winget found. Install Python 3.11+ from https://www.python.org/downloads/ (check 'Add to PATH'), then rerun."
 }
}

function Install-BcryptPythonModule {
    if ([string]::IsNullOrEmpty($script:PYTHON_BIN)) { if (-not (Select-PythonBin)) { Invoke-Die 'Python 3.11+ is required before installing bcrypt.' } }
    $venvDir = Join-Path $script:OUT_DIR '.credential-generator-venv'
    $created = $false
    try {
        Invoke-Python -PyArgs @('-m', 'venv', $venvDir) -StdinText $null | Out-Null
        if ($LASTEXITCODE -eq 0) { $created = $true }
 } catch { $created = $false }

    if ($created) {
        $venvPy = Join-Path (Join-Path $venvDir 'Scripts') 'python.exe'
        if (-not (Test-Path $venvPy)) { $venvPy = Join-Path (Join-Path $venvDir 'bin') 'python' }  # in case of non-Windows PS
        & $venvPy -m pip install --upgrade pip 2>$null | Out-Null
        & $venvPy -m pip install bcrypt
        if ($LASTEXITCODE -ne 0) { Invoke-Die 'pip failed to install bcrypt into the virtual environment.' }
        $script:PYTHON_BIN = $venvPy
        $script:PYTHON_ARGS = @()
        Write-Ok "Created isolated credential-generator Python environment: $venvDir"
 } else {
        Write-Warn 'Python venv creation failed. Falling back to --user pip install for bcrypt.'
        Invoke-Python -PyArgs @('-m', 'pip', 'install', '--user', 'bcrypt') -StdinText $null
        if ($LASTEXITCODE -ne 0) { Invoke-Die 'pip failed to install bcrypt.' }
 }
}

function Ensure-Prereqs {
    Write-Section 'Prerequisites'
    Write-Info 'Python 3.11+ and bcrypt are needed only to generate Spotfire Copilot credentials. Docker/Compose must already be available for deployment.'

    if (-not (Test-PythonVersionOk)) {
        if ($script:INSTALL_PREREQS -eq 'no') { Invoke-Die 'Python 3.11+ is missing or outdated.' }
        if ($script:INSTALL_PREREQS -eq 'prompt') {
            $ans = Read-YesNo 'Python 3.11+ is missing or outdated. Install Python/pip using winget?' 'yes'
            if ($ans -ne 'yes') { Invoke-Die 'Python 3.11+ is required for automatic credential generation.' }
 }
        Install-PythonPackagesWindows
 }
    if (-not (Test-PythonVersionOk)) { Invoke-Die 'Python 3.11+ is still not available after prerequisite installation.' }
    $ver = (Invoke-Python -PyArgs @('--version') -StdinText $null) -join ' '
    Write-Ok "Python is available: $ver ($($script:PYTHON_BIN))"

    if (-not (Test-PythonHasBcrypt)) {
        if ($script:INSTALL_PREREQS -eq 'no') { Invoke-Die 'Python module bcrypt is missing.' }
        if ($script:INSTALL_PREREQS -eq 'prompt') {
            $ans = Read-YesNo 'Python module bcrypt is missing. Install it with pip now?' 'yes'
            if ($ans -ne 'yes') { Invoke-Die 'bcrypt is required for automatic credential generation.' }
 }
        Install-BcryptPythonModule
 }
    if (-not (Test-PythonHasBcrypt)) { Invoke-Die 'Python module bcrypt is still unavailable after installation.' }
    Write-Ok 'Python bcrypt module is available.'
}

# Python source (identical credential format to the bash installer's generator).

# Locate the official Spotfire Copilot credential generator (generate_credentials.py).
# This installer does NOT reimplement credential generation: it runs the generator
# shipped with the Copilot backend package, exactly like a manual run, and then reads
# the values it produces.
function Find-CredentialsScript {
    if (-not [string]::IsNullOrEmpty($script:CREDENTIALS_SCRIPT)) {
        if (Test-Path $script:CREDENTIALS_SCRIPT) { return $script:CREDENTIALS_SCRIPT }
        return $null
    }
    foreach ($candidate in @(
        (Join-Path $script:SCRIPT_DIR 'generate_credentials.py'),
        (Join-Path $script:START_DIR  'generate_credentials.py'),
        (Join-Path $script:OUT_DIR    'generate_credentials.py'))) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

# Ask the user to place generate_credentials.py next to this installer, and keep
# checking until it is found, a path is supplied, or the user stops.
function Resolve-CredentialsScript {
    while ($true) {
        $found = Find-CredentialsScript
        if (-not [string]::IsNullOrEmpty($found)) {
            $script:CREDENTIALS_SCRIPT = $found
            Write-Ok "Found credential generator: $($script:CREDENTIALS_SCRIPT)"
            return
        }
        Write-Warn 'generate_credentials.py was not found.'
        Write-Info 'generate_credentials.py is the official credential generator shipped with the Spotfire Copilot backend package.'
        Write-Info 'Copy it next to this installer, then continue:'
        Write-Info "  $(Join-Path $script:SCRIPT_DIR 'generate_credentials.py')"
        $action = Read-ChooseNum 'How do you want to continue?' 1 @(
            'retry|I have placed generate_credentials.py next to this installer - check again',
            'path|Let me enter the full path to generate_credentials.py',
            'abort|Stop here so I can get generate_credentials.py first'
        )
        switch ($action) {
            'retry' { }
            'path' {
                $script:CREDENTIALS_SCRIPT = Get-StripOuterQuotes (Read-Prompt 'Full path to generate_credentials.py' '')
                if (-not (Test-Path $script:CREDENTIALS_SCRIPT)) {
                    Write-Warn "File not found: $($script:CREDENTIALS_SCRIPT)"
                    $script:CREDENTIALS_SCRIPT = ''
                }
            }
            'abort' {
                Invoke-Die 'generate_credentials.py is required to generate credentials. Copy it next to this installer (or pass -CredentialsScript C:\path\to\generate_credentials.py) and re-run.'
            }
        }
    }
}

# Run generate_credentials.py and capture the credentials it produces.
# Handles both generator styles: printing the values to stdout, or writing its own
# output file. The result is normalized into $File (copilot-generated-values.txt).
function New-CredentialsFile { param([string]$File)
    $File = Resolve-CredentialsPath $File
    $script:CREDENTIALS_FILE = $File
    $parent = Split-Path -Parent $File
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    Resolve-CredentialsScript

    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("copilot-cred-" + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    $consoleLog = Join-Path $workDir 'credential-generator-console.log'

    Write-Info 'Running credential generator (this is the same as running it manually):'
    Write-Info "  $($script:PYTHON_BIN) $($script:CREDENTIALS_SCRIPT)"
    Write-Host ''
    Push-Location $workDir
    $prevEap    = $ErrorActionPreference
    $prevPyIo   = $env:PYTHONIOENCODING
    $prevPyUtf8 = $env:PYTHONUTF8
    try {
        # $ErrorActionPreference='Stop' (set at the top of this script) turns ANY stderr
        # output from a native command into a terminating NativeCommandError. A Python
        # traceback - or even a harmless warning - would abort here and hide the real
        # message. Relax it for this call and rely on $LASTEXITCODE instead.
        $ErrorActionPreference = 'Continue'
        # Force UTF-8 for the generator's stdout/stderr. The official generate_credentials.py
        # prints characters such as (TM) and an em dash; on a legacy Windows console codepage
        # (cp437/cp1252) that raises UnicodeEncodeError and garbles the banner.
        $env:PYTHONIOENCODING = 'utf-8'
        $env:PYTHONUTF8 = '1'
        # Output is shown live and captured at the same time.
        & $script:PYTHON_BIN @($script:PYTHON_ARGS) $script:CREDENTIALS_SCRIPT 2>&1 | Tee-Object -FilePath $consoleLog
        $rc = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
        $env:PYTHONIOENCODING  = $prevPyIo
        $env:PYTHONUTF8        = $prevPyUtf8
        Pop-Location
    }
    Write-Host ''
    if ($rc -ne 0) {
        $savedLog = Join-Path (Split-Path -Parent $File) 'credential-generator-error.log'
        try { Copy-Item -LiteralPath $consoleLog -Destination $savedLog -Force } catch { }
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-Die "generate_credentials.py failed (exit code $rc). Full output saved to: $savedLog . Fix the error above, then re-run this installer."
    }

    # Prefer a file the generator wrote itself; otherwise use what it printed.
    # Get-Content -Raw auto-detects the source encoding (including the UTF-16 BOM that
    # Tee-Object writes on Windows PowerShell 5.1), so we always read the text correctly.
    $produced = Get-ChildItem -LiteralPath $workDir -File | Where-Object { $_.Name -ne 'credential-generator-console.log' } | Select-Object -First 1
    if ($null -ne $produced) {
        Write-Info "Credential generator wrote: $($produced.Name)"
        $credText = Get-Content -LiteralPath $produced.FullName -Raw
    } else {
        $credText = Get-Content -LiteralPath $consoleLog -Raw
    }
    # Always write the credential file as UTF-8 without a BOM. Tee-Object on Windows
    # PowerShell 5.1 has no -Encoding option and emits UTF-16; copying that log verbatim
    # produced an unreadable "ÿþ..." file for non-PowerShell consumers (docker, bash, editors).
    Write-TextFileLF $File $credText
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    Protect-File $File

    # The generated file must contain everything this installer needs. Never fall back
    # to placeholder values: a half-configured .env fails later in a confusing way.
    $missing = @()
    foreach ($key in @('SECRET_KEY','HASHED_ADMIN_PASSWORD','OAUTH2_CLIENT_ID','OAUTH2_CLIENT_SECRET_HASH')) {
        $v = Get-FromCredentialsFile $key $File
        if ([string]::IsNullOrEmpty($v)) { $missing += $key }
    }
    if ($missing.Count -gt 0) {
        Write-Warn "Output kept for review: $File"
        Invoke-Die "generate_credentials.py ran, but these required values were not found in its output: $($missing -join ', '). Expected keys: SECRET_KEY, HASHED_ADMIN_PASSWORD, OAUTH2_CLIENT_ID, OAUTH2_CLIENT_SECRET_HASH."
    }

    Write-Ok "Generated credential file: $File"
    Write-Warn 'Save the plaintext admin password and OAuth client secret from the output above in a secure vault. They are needed for first login / client setup and are not recoverable from the hashes.'
}


function Ensure-CredentialsFileAvailable { param([string]$DefaultFile)
    if ([string]::IsNullOrEmpty($DefaultFile)) { $DefaultFile = Join-Path $script:OUT_DIR 'copilot-generated-values.txt' }
    if (Test-Path $DefaultFile) { return }
    $ans = Read-YesNo "Credential file not found at $DefaultFile. Generate it now?" 'yes'
    if ($ans -eq 'yes') {
 Ensure-Prereqs
        New-CredentialsFile $DefaultFile
 }
}

function Test-ComposeIfPossible {
    $composeFile = Join-Path $script:OUT_DIR 'docker-compose.yml'
    if (-not (Test-Path $composeFile)) { return }
    $dockerOk = $false
    if (Test-CommandExists 'docker') {
        try { & docker compose version 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { $dockerOk = $true } } catch { }
 }
    if ($dockerOk) {
        Push-Location $script:OUT_DIR
        try {
            $rendered = Join-Path ([System.IO.Path]::GetTempPath()) 'copilot-compose-rendered.yml'
            & docker compose config | Out-File -FilePath $rendered -Encoding utf8
            Write-Ok "Docker Compose config validated. Rendered file: $rendered"
 } catch {
            Write-Warn 'docker compose config validation failed.'
 } finally { Pop-Location }
 } else {
        Write-Warn 'Docker Compose V2 was not found or is not usable. Skipping docker compose config validation.'
 }
}

function Show-CurrentInfo {
    $base = Join-Path $script:OUT_DIR '.env'
    $orch = Join-Path $script:OUT_DIR '.env.orchestrator'
    $dl   = Join-Path $script:OUT_DIR '.env.dataloader'
    $agent= Join-Path $script:OUT_DIR '.env.agent-registry'
    $compose = Join-Path $script:OUT_DIR 'docker-compose.yml'
    Write-Section 'Current configuration summary'
    Write-Host "Output directory: $($script:OUT_DIR)"
    function _rv($f,$k) { $v = Read-EnvValue $f $k; if ([string]::IsNullOrEmpty($v)) { '<missing>' } else { $v } }
    Write-Host "IMAGE_TAG: $(_rv $base 'IMAGE_TAG')"
    Write-Host "FASTAPI_APP_VERSION: $(_rv $base 'FASTAPI_APP_VERSION')"
    Write-Host "AGENT_CONTAINER_TAG: $(_rv $base 'AGENT_CONTAINER_TAG')"
    Write-Host "LLM_PROVIDER: $(_rv $base 'LLM_PROVIDER')"
    Write-Host "ENABLE_ADMIN_CONSOLE: $(_rv $base 'ENABLE_ADMIN_CONSOLE')"
    Write-Host "ENABLE_RAG: $(_rv $base 'ENABLE_RAG')"
    Write-Host "VECTOR_DB_PROVIDER: $(_rv $base 'VECTOR_DB_PROVIDER')"
    Write-Host "ENABLE_DATA_LOADER: $(_rv $base 'ENABLE_DATA_LOADER')"
    Write-Host "ENABLE_AGENT_REGISTRY: $(_rv $base 'ENABLE_AGENT_REGISTRY')"
    Write-Host "PostgreSQL host: $(_rv $orch 'POSTGRES_HOST')"
    Write-Host 'Files:'
    foreach ($f in @($base, $orch, $dl, $agent, $compose)) {
        if (Test-Path $f) { Write-Host "  - $f" } else { Write-Host "  - $f <missing>" }
 }
}

function Invoke-Upgrade {
    if ([string]::IsNullOrEmpty($script:UPGRADE_IMAGE_TAG)) { Invoke-Die '-Upgrade requires -ImageTag <tag>. Example: -Upgrade -ImageTag 2.3.4' }
    $sourceDir = $script:FROM_DIR
    $sourceAuto = $false
    if ([string]::IsNullOrEmpty($sourceDir)) { $sourceDir = Get-LastOutDir; $sourceAuto = $true }
    if ([string]::IsNullOrEmpty($sourceDir)) { Invoke-Die 'No previous install directory found. Use -FromDir C:\path\to\spotfire-copilot\2.3.4\backend.' }
    if (-not (Test-Path $sourceDir -PathType Container)) { Invoke-Die "Source directory not found: $sourceDir" }

    if ($script:OUT_DIR_EXPLICIT -eq 'no') {
        $script:OUT_DIR = Get-VersionedBackendDirFromSource $sourceDir $script:UPGRADE_IMAGE_TAG
 }
    if (-not (Test-Path $script:OUT_DIR)) { New-Item -ItemType Directory -Path $script:OUT_DIR -Force | Out-Null }
    Write-Info "Upgrade source directory: $sourceDir"
    Write-Info "Upgrade target directory: $($script:OUT_DIR)"

    # When the source was auto-detected (no -FromDir), show it and require confirmation
    # so we never silently upgrade from the wrong baseline.
    if ($sourceAuto) {
        if ($script:ASSUME_YES -eq 'yes') {
            Write-Info 'Auto-detected source accepted via -Yes.'
        } elseif (-not [System.Console]::IsInputRedirected) {
            $__confirm = Read-Host "Upgrade using the auto-detected source above -> IMAGE_TAG=$($script:UPGRADE_IMAGE_TAG)? [y/N]"
            if ($__confirm -notmatch '^(y|Y|yes|YES)$') { Invoke-Die 'Upgrade cancelled. Re-run with -FromDir <dir> to choose the source explicitly.' }
        } else {
            Invoke-Die "Non-interactive run cannot auto-confirm the detected source: $sourceDir. Pass -FromDir <dir>, or add -Yes to accept the detected source."
        }
 }

    # Same-directory guard (e.g. upgrading to the same tag the source already uses):
    # skip the self-copy and just re-apply the tag values in place.
    $srcAbs = (Resolve-Path -LiteralPath $sourceDir).Path
    $tgtAbs = (Resolve-Path -LiteralPath $script:OUT_DIR).Path
    if ($srcAbs -ieq $tgtAbs) {
        Write-Warn 'Source and target are the same directory (tag unchanged). Skipping copy; re-applying tag values in place.'
    } else {
        Copy-ExistingConfigToNewDir $sourceDir $script:OUT_DIR
 }

    $base = Join-Path $script:OUT_DIR '.env'
    $compose = Join-Path $script:OUT_DIR 'docker-compose.yml'
    if (-not (Test-Path $base)) { Invoke-Die "Missing $base after copy. Run an initial generation first, or provide a valid -FromDir." }
    Backup-File $base
    Set-EnvValue $base 'IMAGE_TAG' $script:UPGRADE_IMAGE_TAG
    Set-EnvValue $base 'FASTAPI_APP_VERSION' $script:UPGRADE_IMAGE_TAG
    if (-not [string]::IsNullOrEmpty($script:UPGRADE_AGENT_TAG)) { Set-EnvValue $base 'AGENT_CONTAINER_TAG' $script:UPGRADE_AGENT_TAG }
    Update-ComposeImageRefs $compose
    Test-ComposeIfPossible
    Save-LastOutDir
    $agentMsg = if ([string]::IsNullOrEmpty($script:UPGRADE_AGENT_TAG)) { 'unchanged' } else { $script:UPGRADE_AGENT_TAG }
    Write-Ok "Upgrade directory prepared. IMAGE_TAG=$($script:UPGRADE_IMAGE_TAG) FASTAPI_APP_VERSION=$($script:UPGRADE_IMAGE_TAG) AGENT_CONTAINER_TAG=$agentMsg"
    Write-Info "Next: cd $($script:OUT_DIR); docker compose pull; docker compose up -d"
}

function Find-DeepAgentsScript {
    if (-not [string]::IsNullOrEmpty($script:DEEPAGENTS_SCRIPT)) {
        if (Test-Path $script:DEEPAGENTS_SCRIPT) { return $script:DEEPAGENTS_SCRIPT }
        return $null
 }
    $names = @(
        'generate-deepagents-oss-env.ps1',
        'generate-deepagents-oss-env.sh',
        'generate-deepagents-oss-env-v7-template-flow.sh',
        'generate-deepagents-oss-env-v6.sh',
        'generate-deepagents-oss-env-v5.sh'
 )
    foreach ($root in @($script:SCRIPT_DIR, $script:START_DIR)) {
        foreach ($n in $names) {
            $cand = Join-Path $root $n
            if (Test-Path $cand) { return $cand }
 }
 }
    return $null
}

function Invoke-DeepAgentsIfRequested {
    if ($script:WITH_DEEPAGENTS -ne 'yes') { return }
    Write-Section 'DeepAgents OSS'
    Write-Info 'DeepAgents OSS is a separate A2A agent server. It is not part of the core Copilot/Agent Registry stack.'
    Write-Info 'This main script delegates to a standalone DeepAgents installer instead of embedding a duplicate copy.'
    $deep = Find-DeepAgentsScript
    if ([string]::IsNullOrEmpty($deep)) {
        if (-not [string]::IsNullOrEmpty($script:DEEPAGENTS_SCRIPT)) {
            Write-Warn "DeepAgents OSS generator was not found at: $($script:DEEPAGENTS_SCRIPT)"
 } else {
            Write-Warn 'DeepAgents OSS generator was not found next to this script.'
 }
        Write-Warn 'Place generate-deepagents-oss-env.ps1 (or .sh) beside this script, or pass -DeepagentsScript C:\path\to\generate-deepagents-oss-env.ps1.'
        return
 }
    Write-Info "Running standalone DeepAgents OSS generator: $deep"
    if ($deep.ToLower().EndsWith('.ps1')) {
        & $deep
 } elseif (Test-CommandExists 'bash') {
        & bash $deep
 } else {
        Write-Warn "Found $deep but it is a bash script and 'bash' is not available on PATH. Run it from WSL/Git Bash, or provide a .ps1 version."
 }
}

# ----------------------------------------------------------------------------
# Agent Registry only mode
# ----------------------------------------------------------------------------
# Agent Registry compose service, emitted as an array of single-quoted lines whose
# indentation lives INSIDE the quotes. Interior string spaces survive whitespace
# collapse, so the emitted YAML stays valid even if this file's leading indentation
# is mangled in transit. ${AGENT_CONTAINER_TAG} stays literal for Docker Compose.
function Get-AgentRegistryServiceLines {
    $ap = if ([string]::IsNullOrEmpty($script:AGENT_PORT)) { '8050' } else { $script:AGENT_PORT }
    return @(
        '  agent-registry:'
        '    image: copilotoci.azurecr.io/spotfirecopilot/agent-container:${AGENT_CONTAINER_TAG}'
        '    container_name: spotfire-agent-registry-${AGENT_CONTAINER_TAG}'
        '    restart: unless-stopped'
        '    ports:'
        ('      - "{0}:{0}"' -f $ap)
        '    env_file:'
        '      - .env'
        '      - .env.agent-registry'
        '    extra_hosts:'
        '      - "host.docker.internal:host-gateway"'
        '    volumes:'
        '      - /opt/spotfire-agent-registry/custom-workflows:/custom-workflows:ro'
        '      - /opt/spotfire-agent-registry/logs:/conversation-logs'
    )
}

# Reimplements the Python compose-service insert/replace from the bash version.
function Update-AgentRegistryComposeService {
    $composeFile = Join-Path $script:OUT_DIR 'docker-compose.yml'
    if (-not (Test-Path $composeFile)) { Invoke-Die "Missing docker-compose.yml in $($script:OUT_DIR). Agent Registry only mode must be run against an existing backend folder." }

    $text = [System.IO.File]::ReadAllText($composeFile) -replace "`r`n", "`n"
    if ($text -notmatch '(?m)^services:\s*$') { Invoke-Die 'docker-compose.yml does not contain a top-level services: section' }

    # Keep line terminators like the Python splitlines(True) approach.
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in $text.Split("`n")) { $lines.Add($l) }

    $serviceLines = Get-AgentRegistryServiceLines

    # Find an existing agent-registry block. Match ANY indentation so a previously
    # inserted (possibly flattened) block is detected and replaced, not duplicated.
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*agent-registry:\s*$') { $start = $i; break }
    }

    if ($start -ge 0) {
        $end = $lines.Count
        for ($j = $start + 1; $j -lt $lines.Count; $j++) {
            if ($lines[$j] -match '^  [A-Za-z0-9_.-]+:\s*$' -or $lines[$j] -match '^[A-Za-z0-9_.-]+:\s*$') { $end = $j; break }
 }
        $newLines = New-Object System.Collections.Generic.List[string]
        for ($k = 0; $k -lt $start; $k++) { $newLines.Add($lines[$k]) }
        foreach ($sl in $serviceLines) { $newLines.Add($sl) }
        for ($k = $end; $k -lt $lines.Count; $k++) { $newLines.Add($lines[$k]) }
        $lines = $newLines
 } else {
        $insert = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^(networks|volumes):\s*$') { $insert = $i; break }
 }
        if ($insert -lt 0) { $insert = $lines.Count }
        $newLines = New-Object System.Collections.Generic.List[string]
        for ($k = 0; $k -lt $insert; $k++) { $newLines.Add($lines[$k]) }
        if ($insert -gt 0 -and $lines[$insert - 1].Trim() -ne '') { $newLines.Add('') }
        foreach ($sl in $serviceLines) { $newLines.Add($sl) }
        for ($k = $insert; $k -lt $lines.Count; $k++) { $newLines.Add($lines[$k]) }
        $lines = $newLines
 }

    Write-TextFileLF -Path $composeFile -Content ($lines -join "`n")
    Write-Ok "Added/updated agent-registry service in $composeFile"
}

function Set-AgentRegistryEnvOnly {
    Write-Section 'Agent Registry'
    $lv = Get-Existing 'LOG_LEVEL' $script:EXISTING_FILES; if ([string]::IsNullOrEmpty($lv)) { $lv = 'INFO' }
    $script:LOG_LEVEL = $lv
    $agentTagDefault = Get-Existing 'AGENT_CONTAINER_TAG' $script:EXISTING_FILES
    while ($true) {
        $script:AGENT_CONTAINER_TAG = Read-ImageTag 'Agent container image tag' $agentTagDefault 'copilotoci.azurecr.io/spotfirecopilot/agent-container'
        if (-not [string]::IsNullOrEmpty($script:AGENT_CONTAINER_TAG)) { break }
        Write-Warn 'Agent Registry image tag is required. Use the exact agent-container tag provided/tested for your environment.'
 }

    $agentEnvFile = Join-Path $script:OUT_DIR '.env.agent-registry'
    $d = Get-Existing 'PORT' @($agentEnvFile); if ([string]::IsNullOrEmpty($d)) { $d = '8050' }
    $script:AGENT_PORT = Read-Prompt 'Agent Registry PORT' $d
    $d = Get-Existing 'BASE_URL' @($agentEnvFile); if ([string]::IsNullOrEmpty($d)) { $d = 'http://agent-registry:8050' }
    $script:AGENT_BASE_URL = Read-Prompt 'Agent Registry BASE_URL' $d
    $d = Get-Existing 'AUTH_CLIENT_ID' @($agentEnvFile); if ([string]::IsNullOrEmpty($d)) { $d = 'agent-registry-client' }
    $script:AUTH_CLIENT_ID = Read-Prompt 'Agent Registry AUTH_CLIENT_ID' $d

    $existingSecret = Get-Existing 'AUTH_CLIENT_SECRET' @($agentEnvFile)
    if (-not [string]::IsNullOrEmpty($existingSecret)) {
        $script:AUTH_CLIENT_SECRET = Read-Prompt 'Agent Registry AUTH_CLIENT_SECRET' $existingSecret -Secret
 } else {
        $script:AUTH_CLIENT_SECRET = Get-RandomUrlSafeToken
        Write-Ok 'Generated Agent Registry AUTH_CLIENT_SECRET. Save .env.agent-registry securely.'
 }

    $existingSign = Get-Existing 'AUTH_SIGNING_KEY' @($agentEnvFile)
    if (-not [string]::IsNullOrEmpty($existingSign)) {
        $script:AUTH_SIGNING_KEY = Read-Prompt 'Agent Registry AUTH_SIGNING_KEY' $existingSign -Secret
 } else {
        $script:AUTH_SIGNING_KEY = Get-RandomUrlSafeToken
        Write-Ok 'Generated Agent Registry AUTH_SIGNING_KEY. Save .env.agent-registry securely.'
 }

    $d = Get-Existing 'ORCHESTRATOR_URL' @($agentEnvFile); if ([string]::IsNullOrEmpty($d)) { $d = 'http://orchestrator:8080' }
    $script:ORCHESTRATOR_URL = Read-Prompt 'ORCHESTRATOR_URL for Agent Registry' $d

    $exId = Get-Existing 'ORCHESTRATOR_CLIENT_ID' @($agentEnvFile)
    $exSecret = Get-Existing 'ORCHESTRATOR_CLIENT_SECRET' @($agentEnvFile)
    # Placeholder values from an earlier incomplete run are NOT valid credentials and
    # must never be offered for reuse (same rule as the main installation flow).
    if (-not [string]::IsNullOrEmpty($exId) -and -not [string]::IsNullOrEmpty($exSecret) `
            -and $exId -notlike 'REPLACE_WITH_*' -and $exSecret -notlike 'REPLACE_WITH_*') {
        $reuse = Read-YesNo 'Existing Agent Registry Orchestrator OAuth client found in .env.agent-registry. Reuse it?' 'yes'
        if ($reuse -eq 'yes') {
            $script:ORCHESTRATOR_CLIENT_ID = $exId
            $script:ORCHESTRATOR_CLIENT_SECRET = $exSecret
        } else {
            $script:ORCHESTRATOR_CLIENT_ID = Read-RequiredPrompt 'ORCHESTRATOR_CLIENT_ID for Agent Registry' $exId
            $script:ORCHESTRATOR_CLIENT_SECRET = Read-RequiredPrompt 'ORCHESTRATOR_CLIENT_SECRET for Agent Registry' $exSecret -Secret
        }
    } else {
        $have = Read-YesNo 'Have you already created the Orchestrator OAuth client for Agent Registry with Scope Profile agent_developer?' 'no'
        if ($have -eq 'yes') {
            $script:ORCHESTRATOR_CLIENT_ID = Read-RequiredPrompt 'ORCHESTRATOR_CLIENT_ID for Agent Registry' ''
            $script:ORCHESTRATOR_CLIENT_SECRET = Read-RequiredPrompt 'ORCHESTRATOR_CLIENT_SECRET for Agent Registry' '' -Secret
        } else {
            $create = Read-YesNo 'Do you want this installer to create the Agent Registry Orchestrator OAuth client now?' 'no'
            # This is a dedicated install mode: if real credentials cannot be obtained,
            # stop instead of writing placeholders. Placeholders would produce an
            # agent-registry service that starts but can never authenticate.
            if ($create -ne 'yes') {
                Invoke-Die 'Agent Registry needs an Orchestrator OAuth client with Scope Profile agent_developer. Create it in the Admin Console (or re-run and let the installer create it), then run this again. No Agent Registry configuration was applied.'
            }
            $script:ORCHESTRATOR_CLIENT_ID, $script:ORCHESTRATOR_CLIENT_SECRET = Invoke-RegisterAgentClient $script:ORCHESTRATOR_URL
        }
    }

    $d = Get-Existing 'CUSTOM_WORKFLOWS_DIR' @($agentEnvFile); if ([string]::IsNullOrEmpty($d)) { $d = '/custom-workflows' }
    $script:CUSTOM_WORKFLOWS_DIR = Read-Prompt 'CUSTOM_WORKFLOWS_DIR inside container' $d
    $script:CONVERSATION_LOGS_DIR = '/conversation-logs'
    $script:AGENT_ENV_CONTENT = Build-AgentEnvContent
    $script:AGENT_ENV_CONTENT = Compress-EnvContent $script:AGENT_ENV_CONTENT
}


# Obtains an Orchestrator admin JWT by logging in at /auth/jwt/login. It first tries
# the plaintext admin password from the credentials file (operators may store it under
# ADMIN_PASSWORD_PLAINTEXT); if the file is missing it asks for the path, and if no
# plaintext password is available it prompts for it. The username defaults to the
# hard-coded admin email. Returns the access_token string.
function Get-OrchestratorAdminToken { param([string]$BaseUrl)
    $credFile = $script:CREDENTIALS_FILE
    if ([string]::IsNullOrEmpty($credFile) -or -not (Test-Path $credFile)) {
        $credFile = Join-Path $script:OUT_DIR 'copilot-generated-values.txt'
    }

    $adminUser = ''
    $adminPass = ''
    if (-not (Test-Path $credFile)) {
        Write-Warn "Credentials file not found at $credFile."
        $entered = Get-StripOuterQuotes (Read-Prompt 'Path to copilot-generated-values.txt (leave blank to enter the admin password manually)' '')
        if (-not [string]::IsNullOrEmpty($entered)) {
            if (Test-Path $entered) { $credFile = $entered } else { Write-Warn "File not found: $entered" }
        }
    }
    if (Test-Path $credFile) {
        $adminUser = Get-FromCredentialsFile 'ADMIN_USERNAME' $credFile
        if ([string]::IsNullOrEmpty($adminUser)) { $adminUser = Get-FromCredentialsFile 'ADMIN_EMAIL' $credFile }
        $adminPass = Get-FromCredentialsFile 'ADMIN_PASSWORD_PLAINTEXT' $credFile
        if ([string]::IsNullOrEmpty($adminPass)) { $adminPass = Get-FromCredentialsFile 'ADMIN_PASSWORD' $credFile }
        if (-not [string]::IsNullOrEmpty($adminPass)) {
            Write-Info "Using the admin password found in $credFile to log in to the Orchestrator."
        }
    }

    if ([string]::IsNullOrEmpty($adminUser)) { $adminUser = 'admin@orchestrator.local' }
    if ([string]::IsNullOrEmpty($adminPass)) {
        Write-Info 'The plaintext admin password is not stored in the credentials file by default (only its bcrypt hash is). Enter it to let the installer log in for you.'
        $adminUser = Read-Prompt 'Orchestrator admin username (email)' $adminUser
        $adminPass = Read-Prompt 'Orchestrator admin password (plaintext saved from generate_credentials.py)' '' -Secret
    }
    if ([string]::IsNullOrEmpty($adminPass)) {
        Invoke-Die 'No Orchestrator admin password was provided, so the admin token could not be obtained and the Agent Registry OAuth client could not be created. No Agent Registry configuration was applied.'
    }

    Write-Info "Logging in to the Orchestrator at $BaseUrl/auth/jwt/login as $adminUser to obtain an admin token."
    try {
        $loginBody = @{ username = $adminUser; password = $adminPass }
        $resp = Invoke-RestMethod -Method Post -Uri "$BaseUrl/auth/jwt/login" `
            -ContentType 'application/x-www-form-urlencoded' -Body $loginBody
        $token = $resp.access_token
    } catch {
        Invoke-Die "Could not log in to the Orchestrator at $BaseUrl/auth/jwt/login. Check that the Orchestrator is running and reachable at that URL and that the admin username/password are correct (username must be the email, e.g. admin@orchestrator.local). No Agent Registry configuration was applied. ($($_.Exception.Message))"
    }
    if ([string]::IsNullOrEmpty($token)) {
        Invoke-Die 'The Orchestrator login response did not include an access_token. No Agent Registry configuration was applied.'
    }
    return $token
}

# Calls the Orchestrator /register_client endpoint. Returns @(clientId, clientSecret).
function Invoke-RegisterAgentClient { param([string]$DefaultUrl)
    # The client-creation call is made from THIS host, so default to the
    # host-published orchestrator port. The in-compose hostname
    # (http://orchestrator:8080) is not resolvable from the host.
    if ($DefaultUrl -like 'http://orchestrator:*' -or $DefaultUrl -like 'https://orchestrator:*') {
        $DefaultUrl = 'http://localhost:8080'
    }
    $createUrl = Read-Prompt 'Orchestrator URL reachable from this machine for client creation' $DefaultUrl
    $createUrl = $createUrl.TrimEnd('/')
    $token = Get-OrchestratorAdminToken $createUrl
    $clientName = Read-Prompt 'OAuth client name to create' 'Agent Registry'
    Write-Info 'Creating Agent Registry OAuth client in Orchestrator using scope_profile=agent_developer.'
    try {
        $body = @{ client_name = $clientName; scope_profile = 'agent_developer' }
        $resp = Invoke-RestMethod -Method Post -Uri "$createUrl/register_client" `
            -Headers @{ Authorization = "Bearer $token" } `
            -ContentType 'application/x-www-form-urlencoded' -Body $body
        $cid = $resp.client_id
        $csecret = $resp.client_secret
        if ([string]::IsNullOrEmpty($cid) -or [string]::IsNullOrEmpty($csecret)) {
            Invoke-Die 'The /register_client response did not contain both client_id and client_secret. No Agent Registry configuration was applied.'
        }
        Write-Ok "Created Agent Registry orchestrator OAuth client: $(Get-Mask $cid)"
        Write-Warn 'Save the generated ORCHESTRATOR_CLIENT_SECRET securely. It will be written to .env.agent-registry now, but it may not be recoverable from the Orchestrator later.'
        return @($cid, $csecret)
    } catch {
        Invoke-Die "Agent Registry OAuth client could not be created through $createUrl/register_client. Check that the Orchestrator is running and reachable at that URL and that the admin bearer token is valid. No Agent Registry configuration was applied. ($($_.Exception.Message))"
    }
}

function Build-AgentEnvContent {
@"
# ------------------------------
# Agent Registry runtime
# ------------------------------
PORT=$($script:AGENT_PORT)
BASE_URL=$($script:AGENT_BASE_URL)
LOG_LEVEL=$($script:LOG_LEVEL)

# ------------------------------
# Agent Registry authentication
# ------------------------------
AUTH_CLIENT_ID=$($script:AUTH_CLIENT_ID)
AUTH_CLIENT_SECRET=$($script:AUTH_CLIENT_SECRET)
AUTH_SIGNING_KEY=$($script:AUTH_SIGNING_KEY)
AUTH_TOKEN_TTL=3600

# ------------------------------
# Orchestrator connection
# ------------------------------
ORCHESTRATOR_URL=$($script:ORCHESTRATOR_URL)
ORCHESTRATOR_CLIENT_ID=$($script:ORCHESTRATOR_CLIENT_ID)
ORCHESTRATOR_CLIENT_SECRET=$($script:ORCHESTRATOR_CLIENT_SECRET)

# ------------------------------
# Custom workflow folder
# ------------------------------
CUSTOM_WORKFLOWS_DIR=$($script:CUSTOM_WORKFLOWS_DIR)
CONVERSATION_LOGS_DIR=$($script:CONVERSATION_LOGS_DIR)

# ------------------------------
# Development-only options
# Keep both false in production
# ------------------------------
MCP_ENABLED=false
TUNNEL_ENABLED=false
"@
}

function Invoke-AgentRegistryOnly {
    Write-Section 'Agent Registry only install/update'
    if ($script:OUT_DIR_EXPLICIT -ne 'yes') { Invoke-Die '-InstallAgentRegistry requires -Dir C:\path\to\existing\backend' }
    $script:OUT_DIR = Resolve-NormalizedPath $script:OUT_DIR
    if (-not (Test-Path $script:OUT_DIR -PathType Container)) { Invoke-Die "Backend directory not found: $($script:OUT_DIR)" }
    Push-Location $script:OUT_DIR
    $script:OUT_DIR = (Get-Location).Path
    Pop-Location
    if (-not (Test-Path (Join-Path $script:OUT_DIR '.env'))) { Invoke-Die "Missing $($script:OUT_DIR)\.env. Run this against an existing Copilot backend folder." }
    if (-not (Test-Path (Join-Path $script:OUT_DIR 'docker-compose.yml'))) { Invoke-Die "Missing $($script:OUT_DIR)\docker-compose.yml. Run this against an existing Docker Compose backend folder." }
    $script:EXISTING_FILES = @(
        (Join-Path $script:OUT_DIR '.env'),
        (Join-Path $script:OUT_DIR '.env.orchestrator'),
        (Join-Path $script:OUT_DIR '.env.dataloader'),
        (Join-Path $script:OUT_DIR '.env.agent-registry')
    )

    Set-AgentRegistryEnvOnly
    Write-EnvFile (Join-Path $script:OUT_DIR '.env.agent-registry') $script:AGENT_ENV_CONTENT
    Set-EnvValue (Join-Path $script:OUT_DIR '.env') 'ENABLE_AGENT_REGISTRY' 'yes'
    Set-EnvValue (Join-Path $script:OUT_DIR '.env') 'AGENT_CONTAINER_TAG' $script:AGENT_CONTAINER_TAG
    Update-AgentRegistryComposeService
    Test-ComposeIfPossible
    Save-LastOutDir

    Write-Ok 'Agent Registry install/update files are ready.'
    Write-Host 'Next:'
    Write-Host "  cd $($script:OUT_DIR)"
    Write-Host '  docker login copilotoci.azurecr.io'
    Write-Host '  docker compose pull agent-registry'
    Write-Host '  docker compose up -d --force-recreate agent-registry'
}

# ----------------------------------------------------------------------------
# provider block builders
# ----------------------------------------------------------------------------
function Get-ExistingOr { param([string]$Key, [string]$Default)
    $v = Get-Existing $Key $script:EXISTING_FILES
    if ([string]::IsNullOrEmpty($v)) { return $Default }
    return $v
}

# configure_advanced_categories: the installer does not prompt for overrides.
function Set-AdvancedCategories { param([string]$Prefix, [string]$Primary)
    $script:CATEGORY_BLOCK = ''
    Write-Info "Advanced model category overrides are not prompted by this installer. Using $Primary as MODEL_NAME; add ${Prefix}_FAST_MODEL / ${Prefix}_LARGE_MODEL overrides manually after generation if needed."
}

function Configure-LlmProvider {
    Write-Section 'LLM provider'
    Write-Info 'The LLM provider is independent from the Vector DB. For example, Azure OpenAI can use Milvus, Zilliz, or Azure AI Search for RAG.'
    $script:LLM_PROVIDER = Read-ChooseNum 'Select LLM provider' 1 @(
        'azure_openai|Azure OpenAI',
        'openai|OpenAI',
        'aws_bedrock|AWS Bedrock',
        'vertex_ai|Google Vertex AI',
        'gemini|Google Gemini API',
        'nvidia_nim|NVIDIA NIM',
        'ollama|Ollama / self-hosted test'
    )

    switch ($script:LLM_PROVIDER) {
        'azure_openai' {
            $script:OPENAI_API_KEY = Read-Prompt 'Azure OpenAI API key' (Get-ExistingOr 'OPENAI_API_KEY' '') -Secret
            $script:AZURE_OPENAI_ENDPOINT = Read-Prompt 'Azure OpenAI endpoint' (Get-ExistingOr 'AZURE_OPENAI_ENDPOINT' 'https://your-resource.openai.azure.com/')
            $script:OPENAI_API_VERSION = Read-Prompt 'Azure OpenAI API version' (Get-ExistingOr 'OPENAI_API_VERSION' '2024-02-15-preview')
            $script:PRIMARY_MODEL = Read-Prompt 'Primary Azure deployment name' (Get-ExistingOr 'MODEL_NAME' 'gpt-4o')
            $script:GPT5_FLAG_BLOCK = ''
            Set-AdvancedCategories 'AZURE' $script:PRIMARY_MODEL
            $script:MODEL_BLOCK_ORCH = @"
# REQUIRED: Orchestrator model plugin for Azure OpenAI.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.azure_openai_enhanced:AzureOpenAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.azure_openai_enhanced:AzureOpenAIPlugin
# REQUIRED: OpenAI API type for Azure OpenAI.
OPENAI_API_TYPE=azure
# REQUIRED: Azure OpenAI API key.
OPENAI_API_KEY=$($script:OPENAI_API_KEY)
# REQUIRED: Azure OpenAI endpoint URL.
AZURE_OPENAI_ENDPOINT=$($script:AZURE_OPENAI_ENDPOINT)
# REQUIRED: Azure OpenAI API version.
OPENAI_API_VERSION=$($script:OPENAI_API_VERSION)
# REQUIRED: Primary model/deployment name used as fallback.
MODEL_NAME=$($script:PRIMARY_MODEL)
$($script:GPT5_FLAG_BLOCK)
$($script:CATEGORY_BLOCK)
"@
            $script:MODEL_BLOCK_DL = @"
# REQUIRED: Data Loader model plugin for Azure OpenAI.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.az_openai:AzOpenAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.az_openai:AzOpenAIPlugin
# REQUIRED: OpenAI API type for Azure OpenAI.
OPENAI_API_TYPE=azure
# REQUIRED: Azure OpenAI API key.
OPENAI_API_KEY=$($script:OPENAI_API_KEY)
# REQUIRED: Azure OpenAI endpoint URL.
AZURE_OPENAI_ENDPOINT=$($script:AZURE_OPENAI_ENDPOINT)
# REQUIRED: Azure OpenAI API version.
OPENAI_API_VERSION=$($script:OPENAI_API_VERSION)
# REQUIRED: Data Loader model/deployment name.
MODEL_NAME=$($script:PRIMARY_MODEL)
"@
        }
        'openai' {
            $script:OPENAI_API_KEY = Read-Prompt 'OpenAI API key' (Get-ExistingOr 'OPENAI_API_KEY' '') -Secret
            $script:OPENAI_API_BASE = Read-Prompt 'OPENAI_API_BASE (optional; leave blank for default OpenAI)' (Get-ExistingOr 'OPENAI_API_BASE' '')
            $script:PRIMARY_MODEL = Read-Prompt 'Primary OpenAI model name' (Get-ExistingOr 'MODEL_NAME' 'gpt-4o')
            $script:GPT5_FLAG_BLOCK = ''
            Set-AdvancedCategories 'OPENAI' $script:PRIMARY_MODEL
            $openaiBaseLine = ''
            if (-not [string]::IsNullOrEmpty($script:OPENAI_API_BASE)) {
                $openaiBaseLine = "# OPTIONAL: Custom OpenAI-compatible base URL.`nOPENAI_API_BASE=$($script:OPENAI_API_BASE)"
            }
            $script:MODEL_BLOCK_ORCH = @"
# REQUIRED: Orchestrator model plugin for OpenAI.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai_enhanced:OpenAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai_enhanced:OpenAIPlugin
# REQUIRED: OpenAI API type.
OPENAI_API_TYPE=openai
# REQUIRED: OpenAI API key.
OPENAI_API_KEY=$($script:OPENAI_API_KEY)
$openaiBaseLine
# REQUIRED: Primary model name used as fallback.
MODEL_NAME=$($script:PRIMARY_MODEL)
$($script:GPT5_FLAG_BLOCK)
$($script:CATEGORY_BLOCK)
"@
            $script:MODEL_BLOCK_DL = @"
# REQUIRED: Data Loader model plugin for OpenAI.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai:OpenAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.openai:OpenAIPlugin
# REQUIRED: OpenAI API type.
OPENAI_API_TYPE=openai
# REQUIRED: OpenAI API key.
OPENAI_API_KEY=$($script:OPENAI_API_KEY)
$openaiBaseLine
# REQUIRED: Data Loader model name.
MODEL_NAME=$($script:PRIMARY_MODEL)
"@
        }
        'aws_bedrock' {
            $script:AWS_REGION = Read-Prompt 'AWS_REGION' (Get-ExistingOr 'AWS_REGION' 'us-east-1')
            $useKeys = Read-YesNo 'Use explicit AWS keys in env? Choose No for IAM role/task role.' 'no'
            $awsKeysBlock = '# OPTIONAL: Using IAM role/task role; AWS keys are not set.'
            if ($useKeys -eq 'yes') {
                $script:AWS_ACCESS_KEY_ID = Read-Prompt 'AWS_ACCESS_KEY_ID' (Get-ExistingOr 'AWS_ACCESS_KEY_ID' '') -Secret
                $script:AWS_SECRET_ACCESS_KEY = Read-Prompt 'AWS_SECRET_ACCESS_KEY' (Get-ExistingOr 'AWS_SECRET_ACCESS_KEY' '') -Secret
                $script:AWS_SESSION_TOKEN = Read-Prompt 'AWS_SESSION_TOKEN optional' (Get-ExistingOr 'AWS_SESSION_TOKEN' '') -Secret
                $awsKeysBlock = @"
# OPTIONAL: AWS access key ID. Prefer IAM role in production.
AWS_ACCESS_KEY_ID=$($script:AWS_ACCESS_KEY_ID)
# OPTIONAL: AWS secret access key. Prefer IAM role in production.
AWS_SECRET_ACCESS_KEY=$($script:AWS_SECRET_ACCESS_KEY)
# OPTIONAL: AWS session token, if temporary credentials are used.
AWS_SESSION_TOKEN=$($script:AWS_SESSION_TOKEN)
"@
            }
            $script:PRIMARY_MODEL = Read-Prompt 'Primary Bedrock model ID' (Get-ExistingOr 'MODEL_NAME' 'anthropic.claude-3-5-sonnet-20241022-v2:0')
            Set-AdvancedCategories 'BEDROCK' $script:PRIMARY_MODEL
            $script:MODEL_BLOCK_ORCH = @"
# REQUIRED: Orchestrator model plugin for AWS Bedrock.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock_enhanced:BedrockPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock_enhanced:BedrockPlugin
# REQUIRED: AWS region for Bedrock.
AWS_REGION=$($script:AWS_REGION)
$awsKeysBlock
# REQUIRED: Primary Bedrock model ID.
MODEL_NAME=$($script:PRIMARY_MODEL)
$($script:CATEGORY_BLOCK)
"@
            $script:MODEL_BLOCK_DL = @"
# REQUIRED: Data Loader model plugin for AWS Bedrock.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock:BedrockPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.bedrock:BedrockPlugin
# REQUIRED: AWS region for Bedrock.
AWS_REGION=$($script:AWS_REGION)
$awsKeysBlock
# REQUIRED: Data Loader Bedrock model ID.
MODEL_NAME=$($script:PRIMARY_MODEL)
"@
        }
        'vertex_ai' {
            $script:PROJECT_ID = Read-Prompt 'GCP PROJECT_ID' (Get-ExistingOr 'PROJECT_ID' 'your-gcp-project-id')
            $script:LOCATION_ID = Read-Prompt 'GCP LOCATION_ID' (Get-ExistingOr 'LOCATION_ID' 'us-central1')
            $script:GOOGLE_APPLICATION_CREDENTIALS = Read-Prompt 'GOOGLE_APPLICATION_CREDENTIALS path inside container' (Get-ExistingOr 'GOOGLE_APPLICATION_CREDENTIALS' '/app/credentials/service-account-key.json')
            $script:PRIMARY_MODEL = Read-Prompt 'Primary Vertex AI model' (Get-ExistingOr 'MODEL_NAME' 'gemini-2.0-flash')
            Set-AdvancedCategories 'VERTEXAI' $script:PRIMARY_MODEL
            $script:MODEL_BLOCK_ORCH = @"
# REQUIRED: Orchestrator model plugin for Vertex AI.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai_enhanced:VertexAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai_enhanced:VertexAIPlugin
# REQUIRED: GCP project ID.
PROJECT_ID=$($script:PROJECT_ID)
# REQUIRED: GCP location.
LOCATION_ID=$($script:LOCATION_ID)
# REQUIRED: Service account path inside container.
GOOGLE_APPLICATION_CREDENTIALS=$($script:GOOGLE_APPLICATION_CREDENTIALS)
# REQUIRED: Primary Vertex AI model.
MODEL_NAME=$($script:PRIMARY_MODEL)
$($script:CATEGORY_BLOCK)
"@
            $script:MODEL_BLOCK_DL = @"
# REQUIRED: Data Loader model plugin for Vertex AI.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai:VertexAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai:VertexAIPlugin
# REQUIRED: GCP project ID.
PROJECT_ID=$($script:PROJECT_ID)
# REQUIRED: GCP location.
LOCATION_ID=$($script:LOCATION_ID)
# REQUIRED: Service account path inside container.
GOOGLE_APPLICATION_CREDENTIALS=$($script:GOOGLE_APPLICATION_CREDENTIALS)
# REQUIRED: Data Loader Vertex AI model.
MODEL_NAME=$($script:PRIMARY_MODEL)
"@
        }
        'gemini' {
            $script:GOOGLE_API_KEY = Read-Prompt 'Google Gemini API key' (Get-ExistingOr 'GOOGLE_API_KEY' '') -Secret
            $script:PRIMARY_MODEL = Read-Prompt 'Primary Gemini model' (Get-ExistingOr 'MODEL_NAME' 'gemini-2.0-flash')
            Set-AdvancedCategories 'GEMINI' $script:PRIMARY_MODEL
            $script:MODEL_BLOCK_ORCH = @"
# REQUIRED: Orchestrator model plugin for Google Gemini API.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.gemini_enhanced:GeminiPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.gemini_enhanced:GeminiPlugin
# REQUIRED: Gemini API key.
GOOGLE_API_KEY=$($script:GOOGLE_API_KEY)
# REQUIRED: Primary Gemini model.
MODEL_NAME=$($script:PRIMARY_MODEL)
$($script:CATEGORY_BLOCK)
"@
            $script:MODEL_BLOCK_DL = @"
# REQUIRED: Data Loader model plugin for Vertex AI/Gemini-compatible setup.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai:VertexAIPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.vertexai:VertexAIPlugin
# REQUIRED: Data Loader model name.
MODEL_NAME=$($script:PRIMARY_MODEL)
"@
        }
        'nvidia_nim' {
            $script:NVIDIA_API_KEY = Read-Prompt 'NVIDIA_API_KEY' (Get-ExistingOr 'NVIDIA_API_KEY' '') -Secret
            $script:NVIDIA_BASE_URL = Read-Prompt 'NVIDIA_BASE_URL' (Get-ExistingOr 'NVIDIA_BASE_URL' 'https://integrate.api.nvidia.com/v1')
            $script:PRIMARY_MODEL = Read-Prompt 'Primary NVIDIA NIM model' (Get-ExistingOr 'MODEL_NAME' 'meta/llama-3.1-70b-instruct')
            Set-AdvancedCategories 'NVIDIA' $script:PRIMARY_MODEL
            $script:MODEL_BLOCK_ORCH = @"
# REQUIRED: Orchestrator model plugin for NVIDIA NIM.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin
# REQUIRED: NVIDIA API key.
NVIDIA_API_KEY=$($script:NVIDIA_API_KEY)
# REQUIRED: NVIDIA base URL.
NVIDIA_BASE_URL=$($script:NVIDIA_BASE_URL)
# REQUIRED: Primary NVIDIA model.
MODEL_NAME=$($script:PRIMARY_MODEL)
$($script:CATEGORY_BLOCK)
"@
            $script:MODEL_BLOCK_DL = @"
# REQUIRED: Data Loader model plugin for NVIDIA NIM.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim:NvidiaNimPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.nvidia_nim:NvidiaNimPlugin
# REQUIRED: NVIDIA API key.
NVIDIA_API_KEY=$($script:NVIDIA_API_KEY)
# REQUIRED: NVIDIA base URL.
NVIDIA_BASE_URL=$($script:NVIDIA_BASE_URL)
# REQUIRED: Data Loader NVIDIA model.
MODEL_NAME=$($script:PRIMARY_MODEL)
"@
        }
        'ollama' {
            $script:OLLAMA_BASE_URL = Read-Prompt 'OLLAMA_BASE_URL' (Get-ExistingOr 'OLLAMA_BASE_URL' 'http://host.docker.internal:11434')
            $script:PRIMARY_MODEL = Read-Prompt 'Primary Ollama model' (Get-ExistingOr 'MODEL_NAME' 'llama3.1:8b')
            Set-AdvancedCategories 'OLLAMA' $script:PRIMARY_MODEL
            $script:MODEL_BLOCK_ORCH = @"
# REQUIRED: Orchestrator model plugin for Ollama.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama_enhanced:OllamaPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama_enhanced:OllamaPlugin
# REQUIRED: Ollama base URL reachable from the container.
OLLAMA_BASE_URL=$($script:OLLAMA_BASE_URL)
# REQUIRED: Primary Ollama model.
MODEL_NAME=$($script:PRIMARY_MODEL)
$($script:CATEGORY_BLOCK)
"@
            $script:MODEL_BLOCK_DL = @"
# REQUIRED: Data Loader model plugin for Ollama.
MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama:OllamaPlugin
# REQUIRED: Secondary model plugin; set same as MODEL_PLUGIN_ENTRY_POINT.
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama:OllamaPlugin
# REQUIRED: Ollama base URL reachable from the container.
OLLAMA_BASE_URL=$($script:OLLAMA_BASE_URL)
# REQUIRED: Data Loader Ollama model.
MODEL_NAME=$($script:PRIMARY_MODEL)
"@
        }
    }
}

function Configure-Embeddings {
    $defaultChoice = 1
    switch ($script:LLM_PROVIDER) {
        'azure_openai' { $defaultChoice = 1 }
        'openai'       { $defaultChoice = 2 }
        'aws_bedrock'  { $defaultChoice = 3 }
        'vertex_ai'    { $defaultChoice = 4 }
        'nvidia_nim'   { $defaultChoice = 5 }
        'ollama'       { $defaultChoice = 6 }
        'gemini'       { $defaultChoice = 4 }
    }
    $script:EMBEDDING_PROVIDER = Read-ChooseNum 'Select embedding provider for RAG. Data Loader and Orchestrator must use the same embedding model for the same index.' $defaultChoice @(
        'azure_openai|Azure OpenAI embeddings',
        'openai|OpenAI embeddings',
        'aws_bedrock|AWS Bedrock embeddings',
        'vertex_ai|Vertex AI embeddings',
        'nvidia_nim|NVIDIA NIM embeddings',
        'ollama|Ollama embeddings'
    )

    switch ($script:EMBEDDING_PROVIDER) {
        'azure_openai' {
            if ([string]::IsNullOrEmpty($script:OPENAI_API_KEY)) { $script:OPENAI_API_KEY = Read-Prompt 'Azure/OpenAI API key for embeddings' (Get-ExistingOr 'OPENAI_API_KEY' '') -Secret }
            if ([string]::IsNullOrEmpty($script:AZURE_OPENAI_ENDPOINT)) { $script:AZURE_OPENAI_ENDPOINT = Read-Prompt 'Azure OpenAI endpoint for embeddings' (Get-ExistingOr 'AZURE_OPENAI_ENDPOINT' 'https://your-resource.openai.azure.com/') }
            if ([string]::IsNullOrEmpty($script:OPENAI_API_VERSION)) { $script:OPENAI_API_VERSION = Read-Prompt 'Azure OpenAI API version for embeddings' (Get-ExistingOr 'OPENAI_API_VERSION' '2024-02-15-preview') }
            $script:EMBEDDING_MODEL_NAME = Read-Prompt 'Azure embedding deployment name' (Get-ExistingOr 'EMBEDDING_MODEL_NAME' 'text-embedding-ada-002')
            $script:EMBED_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Embedding plugin for Azure OpenAI.
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.az_openai:AzOpenAIEmbeddingsPlugin
# REQUIRED FOR RAG: OpenAI API type for Azure OpenAI embeddings.
OPENAI_API_TYPE=azure
# REQUIRED FOR RAG: Azure OpenAI API key for embeddings.
OPENAI_API_KEY=$($script:OPENAI_API_KEY)
# REQUIRED FOR RAG: Azure OpenAI endpoint for embeddings.
AZURE_OPENAI_ENDPOINT=$($script:AZURE_OPENAI_ENDPOINT)
# REQUIRED FOR RAG: Azure OpenAI API version for embeddings.
OPENAI_API_VERSION=$($script:OPENAI_API_VERSION)
# REQUIRED FOR RAG: Embedding deployment name.
EMBEDDING_MODEL_NAME=$($script:EMBEDDING_MODEL_NAME)
"@
            $script:EMBED_BLOCK_DL = $script:EMBED_BLOCK_ORCH
        }
        'openai' {
            if ([string]::IsNullOrEmpty($script:OPENAI_API_KEY)) { $script:OPENAI_API_KEY = Read-Prompt 'OpenAI API key for embeddings' (Get-ExistingOr 'OPENAI_API_KEY' '') -Secret }
            $script:EMBEDDING_MODEL_NAME = Read-Prompt 'OpenAI embedding model' (Get-ExistingOr 'EMBEDDING_MODEL_NAME' 'text-embedding-ada-002')
            $script:EMBED_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Embedding plugin for OpenAI.
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.openai:OpenAIEmbeddingsPlugin
# REQUIRED FOR RAG: OpenAI API type.
OPENAI_API_TYPE=openai
# REQUIRED FOR RAG: OpenAI API key for embeddings.
OPENAI_API_KEY=$($script:OPENAI_API_KEY)
# REQUIRED FOR RAG: Embedding model name.
EMBEDDING_MODEL_NAME=$($script:EMBEDDING_MODEL_NAME)
"@
            $script:EMBED_BLOCK_DL = $script:EMBED_BLOCK_ORCH
        }
        'aws_bedrock' {
            if ([string]::IsNullOrEmpty($script:AWS_REGION)) { $script:AWS_REGION = Read-Prompt 'AWS_REGION for embeddings' (Get-ExistingOr 'AWS_REGION' 'us-east-1') }
            $script:EMBEDDING_MODEL_NAME = Read-Prompt 'Bedrock embedding model ID' (Get-ExistingOr 'EMBEDDING_MODEL_NAME' 'amazon.titan-embed-text-v2:0')
            $script:EMBED_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Embedding plugin for AWS Bedrock.
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.bedrock:BedrockEmbeddingsPlugin
# REQUIRED FOR RAG: AWS region for Bedrock embeddings.
AWS_REGION=$($script:AWS_REGION)
# REQUIRED FOR RAG: Bedrock embedding model ID.
EMBEDDING_MODEL_NAME=$($script:EMBEDDING_MODEL_NAME)
"@
            $script:EMBED_BLOCK_DL = $script:EMBED_BLOCK_ORCH
        }
        'vertex_ai' {
            if ([string]::IsNullOrEmpty($script:PROJECT_ID)) { $script:PROJECT_ID = Read-Prompt 'GCP PROJECT_ID for embeddings' (Get-ExistingOr 'PROJECT_ID' 'your-gcp-project-id') }
            if ([string]::IsNullOrEmpty($script:LOCATION_ID)) { $script:LOCATION_ID = Read-Prompt 'GCP LOCATION_ID for embeddings' (Get-ExistingOr 'LOCATION_ID' 'us-central1') }
            if ([string]::IsNullOrEmpty($script:GOOGLE_APPLICATION_CREDENTIALS)) { $script:GOOGLE_APPLICATION_CREDENTIALS = Read-Prompt 'GOOGLE_APPLICATION_CREDENTIALS path inside container' (Get-ExistingOr 'GOOGLE_APPLICATION_CREDENTIALS' '/app/credentials/service-account-key.json') }
            $script:EMBEDDING_MODEL_NAME = Read-Prompt 'Vertex AI embedding model' (Get-ExistingOr 'EMBEDDING_MODEL_NAME' 'text-embedding-004')
            $script:EMBED_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Embedding plugin for Vertex AI.
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.vertexai:VertexAIEmbeddingsPlugin
# REQUIRED FOR RAG: GCP project ID for embeddings.
PROJECT_ID=$($script:PROJECT_ID)
# REQUIRED FOR RAG: GCP location for embeddings.
LOCATION_ID=$($script:LOCATION_ID)
# REQUIRED FOR RAG: Service account path inside container for embeddings.
GOOGLE_APPLICATION_CREDENTIALS=$($script:GOOGLE_APPLICATION_CREDENTIALS)
# REQUIRED FOR RAG: Vertex AI embedding model.
EMBEDDING_MODEL_NAME=$($script:EMBEDDING_MODEL_NAME)

"@
            $script:EMBED_BLOCK_DL = $script:EMBED_BLOCK_ORCH
        }
        'nvidia_nim' {
            if ([string]::IsNullOrEmpty($script:NVIDIA_API_KEY)) { $script:NVIDIA_API_KEY = Read-Prompt 'NVIDIA_API_KEY for embeddings' (Get-ExistingOr 'NVIDIA_API_KEY' '') -Secret }
            if ([string]::IsNullOrEmpty($script:NVIDIA_BASE_URL)) { $script:NVIDIA_BASE_URL = Read-Prompt 'NVIDIA_BASE_URL for embeddings' (Get-ExistingOr 'NVIDIA_BASE_URL' 'https://integrate.api.nvidia.com/v1') }
            $script:EMBEDDING_MODEL_NAME = Read-Prompt 'NVIDIA NIM embedding model' (Get-ExistingOr 'EMBEDDING_MODEL_NAME' 'nvidia/nv-embedqa-e5-v5')
            $script:EMBED_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Embedding plugin for NVIDIA NIM.
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.nvidia_nim:NvidiaNimEmbeddingsPlugin
# REQUIRED FOR RAG: NVIDIA API key for embeddings.
NVIDIA_API_KEY=$($script:NVIDIA_API_KEY)
# REQUIRED FOR RAG: NVIDIA base URL for embeddings.
NVIDIA_BASE_URL=$($script:NVIDIA_BASE_URL)
# REQUIRED FOR RAG: NVIDIA embedding model.
EMBEDDING_MODEL_NAME=$($script:EMBEDDING_MODEL_NAME)
"@
            $script:EMBED_BLOCK_DL = $script:EMBED_BLOCK_ORCH
        }
        'ollama' {
            if ([string]::IsNullOrEmpty($script:OLLAMA_BASE_URL)) { $script:OLLAMA_BASE_URL = Read-Prompt 'OLLAMA_BASE_URL for embeddings' (Get-ExistingOr 'OLLAMA_BASE_URL' 'http://host.docker.internal:11434') }
            $script:EMBEDDING_MODEL_NAME = Read-Prompt 'Ollama embedding model' (Get-ExistingOr 'EMBEDDING_MODEL_NAME' 'nomic-embed-text')
            $script:EMBED_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Embedding plugin for Ollama.
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.ollama:OllamaEmbeddingsPlugin
# REQUIRED FOR RAG: Ollama base URL for embeddings.
OLLAMA_BASE_URL=$($script:OLLAMA_BASE_URL)
# REQUIRED FOR RAG: Ollama embedding model.
EMBEDDING_MODEL_NAME=$($script:EMBEDDING_MODEL_NAME)
"@
            $script:EMBED_BLOCK_DL = $script:EMBED_BLOCK_ORCH
        }
    }
}

function Configure-VectorDb {
    $script:VECTOR_DB_PROVIDER = Read-ChooseNum 'Select Vector DB / Knowledge Base provider. This is independent from your LLM provider.' 1 @(
        'azure_ai_search|Azure AI Search / Azure Cognitive Search',
        'milvus|Milvus self-hosted',
        'zilliz|Zilliz Cloud',
        'redis|Redis (self-hosted)',
        'vertex_vector_search|Vertex AI Vector Search',
        'aws_bedrock_kb|AWS Bedrock Knowledge Bases',
        'custom|Custom / advanced plugin entrypoints'
    )
    $script:VECTOR_WRITABLE = 'yes'
    switch ($script:VECTOR_DB_PROVIDER) {
        'azure_ai_search' {
            $script:AZURE_COGNITIVE_SEARCH_SERVICE_NAME = Read-Prompt 'Azure AI Search service name' (Get-ExistingOr 'AZURE_COGNITIVE_SEARCH_SERVICE_NAME' 'your-search-service-name')
            $script:AZURE_COGNITIVE_SEARCH_API_KEY = Read-Prompt 'Azure AI Search API key' (Get-ExistingOr 'AZURE_COGNITIVE_SEARCH_API_KEY' '') -Secret
            $script:AZSEARCH_EP = Read-Prompt 'Azure AI Search endpoint' (Get-ExistingOr 'AZSEARCH_EP' 'https://your-search-service-name.search.windows.net/')
            $script:AZSEARCH_KEY = $script:AZURE_COGNITIVE_SEARCH_API_KEY
            $script:VECTOR_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Retriever plugin used by Orchestrator for Azure AI Search.
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.az_cog_search:AzCognitiveSearchRetrieverPlugin
# REQUIRED FOR RAG: Azure AI Search service name.
AZURE_COGNITIVE_SEARCH_SERVICE_NAME=$($script:AZURE_COGNITIVE_SEARCH_SERVICE_NAME)
# REQUIRED FOR RAG: Azure AI Search API key.
AZURE_COGNITIVE_SEARCH_API_KEY=$($script:AZURE_COGNITIVE_SEARCH_API_KEY)
# REQUIRED FOR RAG: Azure AI Search endpoint.
AZSEARCH_EP=$($script:AZSEARCH_EP)
# REQUIRED FOR RAG: Azure AI Search key alias.
AZSEARCH_KEY=$($script:AZSEARCH_KEY)
"@
            $script:VECTOR_BLOCK_DL = @"
# REQUIRED: Vector DB writer plugin used by Data Loader for Azure AI Search.
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.az_cog_search:ACognitiveSearchRetrieverPlugin
# REQUIRED: Azure AI Search service name.
AZURE_COGNITIVE_SEARCH_SERVICE_NAME=$($script:AZURE_COGNITIVE_SEARCH_SERVICE_NAME)
# REQUIRED: Azure AI Search API key.
AZURE_COGNITIVE_SEARCH_API_KEY=$($script:AZURE_COGNITIVE_SEARCH_API_KEY)
# REQUIRED: Azure AI Search endpoint.
AZSEARCH_EP=$($script:AZSEARCH_EP)
# REQUIRED: Azure AI Search key alias.
AZSEARCH_KEY=$($script:AZSEARCH_KEY)
"@
        }
        'milvus' {
            $script:VECTORDB_URI = Read-Prompt 'Milvus VECTORDB_URI' (Get-ExistingOr 'VECTORDB_URI' 'http://your-milvus-host:19530')
            $script:VECTORDB_TOKEN = Read-Prompt 'Milvus VECTORDB_TOKEN' (Get-ExistingOr 'VECTORDB_TOKEN' 'root:Milvus') -Secret
            $script:VECTOR_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Retriever plugin used by Orchestrator for Milvus.
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.milvus:MilvusRetrieverPlugin
# REQUIRED FOR RAG: Milvus endpoint URI.
VECTORDB_URI=$($script:VECTORDB_URI)
# REQUIRED FOR RAG: Milvus token or user:password.
VECTORDB_TOKEN=$($script:VECTORDB_TOKEN)
"@
            $script:VECTOR_BLOCK_DL = @"
# REQUIRED: Vector DB writer plugin used by Data Loader for Milvus.
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.milvus:MilvusRetrieverPlugin
# REQUIRED: Milvus endpoint URI.
VECTORDB_URI=$($script:VECTORDB_URI)
# REQUIRED: Milvus token or user:password.
VECTORDB_TOKEN=$($script:VECTORDB_TOKEN)
"@
        }
        'zilliz' {
            $script:ZILLIZ_CLOUD_URI = Read-Prompt 'Zilliz Cloud URI' (Get-ExistingOr 'ZILLIZ_CLOUD_URI' 'https://your-instance.zillizcloud.com')
            $script:ZILLIZ_CLOUD_API_KEY = Read-Prompt 'Zilliz Cloud API key' (Get-ExistingOr 'ZILLIZ_CLOUD_API_KEY' '') -Secret
            $script:VECTOR_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Retriever plugin used by Orchestrator for Zilliz Cloud.
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.zilliz:ZillizRetrieverPlugin
# REQUIRED FOR RAG: Zilliz Cloud URI.
ZILLIZ_CLOUD_URI=$($script:ZILLIZ_CLOUD_URI)
# REQUIRED FOR RAG: Zilliz Cloud API key.
ZILLIZ_CLOUD_API_KEY=$($script:ZILLIZ_CLOUD_API_KEY)
"@
            $script:VECTOR_BLOCK_DL = @"
# REQUIRED: Vector DB writer plugin used by Data Loader for Zilliz Cloud.
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.zilliz:ZillizRetrieverPlugin
# REQUIRED: Zilliz Cloud URI.
ZILLIZ_CLOUD_URI=$($script:ZILLIZ_CLOUD_URI)
# REQUIRED: Zilliz Cloud API key.
ZILLIZ_CLOUD_API_KEY=$($script:ZILLIZ_CLOUD_API_KEY)
"@
        }
        'redis' {
            $script:REDIS_URL = Read-Prompt 'REDIS_URL (may embed credentials, e.g. redis://user:pass@host:6379)' (Get-ExistingOr 'REDIS_URL' 'redis://your-redis-host:6379') -Secret
            $script:VECTOR_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Retriever plugin used by Orchestrator for Redis.
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.redis:RedisRetrieverPlugin
# REQUIRED FOR RAG: Redis connection URL.
REDIS_URL=$($script:REDIS_URL)
"@
            $script:VECTOR_BLOCK_DL = @"
# REQUIRED: Vector DB writer plugin used by Data Loader for Redis.
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.redis:RedisRetrieverPlugin
# REQUIRED: Redis connection URL.
REDIS_URL=$($script:REDIS_URL)
"@
        }
        'vertex_vector_search' {
            if ([string]::IsNullOrEmpty($script:PROJECT_ID)) { $script:PROJECT_ID = Read-Prompt 'GCP PROJECT_ID' (Get-ExistingOr 'PROJECT_ID' 'your-gcp-project-id') }
            if ([string]::IsNullOrEmpty($script:LOCATION_ID)) { $script:LOCATION_ID = Read-Prompt 'GCP LOCATION_ID' (Get-ExistingOr 'LOCATION_ID' 'us-central1') }
            $script:GCS_BUCKET_NAME = Read-Prompt 'GCS bucket for Vertex AI Vector Search' (Get-ExistingOr 'GCS_BUCKET_NAME' 'your-gcs-bucket-name')
            $script:PRIVATE_SC_IP = Read-Prompt 'PRIVATE_SC_IP (optional; leave blank if not using Private Service Connect)' (Get-ExistingOr 'PRIVATE_SC_IP' '')
            $script:VECTOR_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Retriever plugin used by Orchestrator for Vertex AI Vector Search.
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin
# REQUIRED FOR RAG: GCP project for Vertex AI Vector Search.
PROJECT_ID=$($script:PROJECT_ID)
# REQUIRED FOR RAG: GCP location for Vertex AI Vector Search.
LOCATION_ID=$($script:LOCATION_ID)
# REQUIRED FOR RAG: GCS bucket used by Vertex AI Vector Search.
GCS_BUCKET_NAME=$($script:GCS_BUCKET_NAME)
# OPTIONAL: Private Service Connect IP, if used.
PRIVATE_SC_IP=$($script:PRIVATE_SC_IP)
"@
            $script:VECTOR_BLOCK_DL = @"
# REQUIRED: Vector DB writer plugin used by Data Loader for Vertex AI Vector Search.
VECTORDB_PLUGIN_ENTRY_POINT=plugins.vectordbs.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin
# REQUIRED: GCP project for Vertex AI Vector Search.
PROJECT_ID=$($script:PROJECT_ID)
# REQUIRED: GCP location for Vertex AI Vector Search.
LOCATION_ID=$($script:LOCATION_ID)
# REQUIRED: GCS bucket used by Vertex AI Vector Search.
GCS_BUCKET_NAME=$($script:GCS_BUCKET_NAME)
# OPTIONAL: Private Service Connect IP, if used.
PRIVATE_SC_IP=$($script:PRIVATE_SC_IP)
"@
        }
        'aws_bedrock_kb' {
            if ([string]::IsNullOrEmpty($script:AWS_REGION)) { $script:AWS_REGION = Read-Prompt 'AWS_REGION for Bedrock KB' (Get-ExistingOr 'AWS_REGION' 'us-east-1') }
            $script:VECTOR_WRITABLE = 'no'
            $script:VECTOR_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Retriever plugin used by Orchestrator for AWS Bedrock Knowledge Bases.
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.amazon_kbs:AmazonKBsRetrieverPlugin
# REQUIRED FOR RAG: AWS region for Bedrock Knowledge Bases.
AWS_REGION=$($script:AWS_REGION)
# Runtime IAM role/user should allow: bedrock:Retrieve, bedrock:ListKnowledgeBases,
# bedrock:GetKnowledgeBase, and optionally bedrock:ListDataSources.
"@
            $script:VECTOR_BLOCK_DL = @"
# Data Loader omitted because Bedrock Knowledge Bases use AWS-native ingestion from S3.
"@
            $script:DATA_LOADER_NOTICE = 'AWS Bedrock Knowledge Bases should be populated through AWS-native ingestion, not Spotfire Data Loader.'
        }
        'custom' {
            Write-Warn 'Custom mode writes plugin entrypoints only. Add provider-specific variables manually after generation.'
            $script:CUSTOM_RETRIEVER_PLUGIN = Read-Prompt 'RETRIEVER_PLUGIN_ENTRY_POINT' (Get-ExistingOr 'RETRIEVER_PLUGIN_ENTRY_POINT' 'plugins.retrievers.example:ExampleRetrieverPlugin')
            $hasLoader = Read-YesNo 'Does this vector DB have a Data Loader writer plugin you want to configure now?' 'no'
            $script:VECTOR_WRITABLE = 'no'
            if ($hasLoader -eq 'yes') {
                $script:VECTOR_WRITABLE = 'yes'
                $script:CUSTOM_VECTORDB_PLUGIN = Read-Prompt 'VECTORDB_PLUGIN_ENTRY_POINT' (Get-ExistingOr 'VECTORDB_PLUGIN_ENTRY_POINT' 'plugins.vectordbs.example:ExampleVectorDbPlugin')
            } else {
                $script:CUSTOM_VECTORDB_PLUGIN = ''
            }
            $script:VECTOR_BLOCK_ORCH = @"
# REQUIRED FOR RAG: Custom retriever plugin used by Orchestrator.
RETRIEVER_PLUGIN_ENTRY_POINT=$($script:CUSTOM_RETRIEVER_PLUGIN)
# TODO: Add required custom vector DB credentials below.
"@
            if ($script:VECTOR_WRITABLE -eq 'yes') {
                $script:VECTOR_BLOCK_DL = @"
# REQUIRED: Custom vector DB writer plugin used by Data Loader.
VECTORDB_PLUGIN_ENTRY_POINT=$($script:CUSTOM_VECTORDB_PLUGIN)
# TODO: Add required custom vector DB credentials below.
"@
            } else {
                $script:VECTOR_BLOCK_DL = '# OPTIONAL: Data Loader disabled or native ingestion required for custom vector DB.'
            }
        }
    }
}

# ----------------------------------------------------------------------------
# cloud template env shortlist mode
# ----------------------------------------------------------------------------
function Get-CloudTargetLabel { param([string]$T)
    switch ($T) {
        'azure_container_apps' { 'Azure Container Apps' }
        'aws_ecs_fargate'      { 'AWS ECS / Fargate' }
        'gcp_cloud_run'        { 'GCP Cloud Run' }
        'kubernetes'           { 'Kubernetes (AKS / EKS / GKE)' }
        'other_cloud'          { 'Other cloud / customer-managed container platform' }
        default                { 'Cloud provider' }
    }
}
function Get-CloudSecretStoreLabel { param([string]$T)
    switch ($T) {
        'azure_container_apps' { 'Azure Key Vault / Azure Container App secrets' }
        'aws_ecs_fargate'      { 'AWS Secrets Manager or SSM Parameter Store' }
        'gcp_cloud_run'        { 'GCP Secret Manager' }
        'kubernetes'           { 'Kubernetes Secret, or external secret manager via CSI/external-secrets' }
        'other_cloud'          { 'Platform secret manager' }
        default                { 'Platform secret manager' }
    }
}
function Get-CloudSecretReferenceHint { param([string]$T)
    switch ($T) {
        'azure_container_apps' { 'For Azure Container Apps, create app secrets/Key Vault references and map env vars with secretref:<secret-name>.' }
        'aws_ecs_fargate'      { 'For AWS ECS/Fargate, store secrets in Secrets Manager/SSM and map env vars with valueFrom in the task definition.' }
        'gcp_cloud_run'        { 'For GCP Cloud Run, store values in Secret Manager and map them as secret-backed environment variables.' }
        'kubernetes'           { 'For Kubernetes, put SECRET variables in a Secret and CONFIG variables in a ConfigMap.' }
        'other_cloud'          { "Use your platform's secret manager for SECRET variables and normal environment variables for CONFIG variables." }
        default                { "Use your platform's secret manager for SECRET variables and normal environment variables for CONFIG variables." }
    }
}

function Get-CloudLlmBlock { param([string]$P)
    switch ($P) {
        'azure_openai' { @'
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
'@ }
        'openai' { @'
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
'@ }
        'aws_bedrock' { @'
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
'@ }
        'vertex_ai' { @'
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
'@ }
        'gemini' { @'
# ============================================================
# 05_LLM_PROVIDER_GOOGLE_GEMINI_API
# Include these in the Orchestrator container.
# ============================================================

# CONFIG
MODEL_PLUGIN_ENTRY_POINT=plugins.models.gemini_enhanced:GeminiPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.gemini_enhanced:GeminiPlugin

# SECRET
GOOGLE_API_KEY=
'@ }
        'nvidia_nim' { @'
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
'@ }
        'ollama' { @'
# ============================================================
# 05_LLM_PROVIDER_OLLAMA_SELF_HOSTED
# Include these in the Orchestrator container.
# ============================================================

# CONFIG
MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama_enhanced:OllamaPlugin
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=plugins.models.ollama_enhanced:OllamaPlugin
OLLAMA_BASE_URL=
'@ }
        default { @'
# ============================================================
# 05_LLM_PROVIDER_CUSTOM
# ============================================================

MODEL_PLUGIN_ENTRY_POINT=
SECONDARY_MODEL_PLUGIN_ENTRY_POINT=
# PROVIDER_API_KEY=
# PROVIDER_ENDPOINT=
'@ }
 }
}

function Get-CloudEmbeddingsBlock { param([string]$P)
    switch ($P) {
        'azure_openai' { @'
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
'@ }
        'openai' { @'
# ============================================================
# 06_EMBEDDINGS_OPENAI
# ============================================================

# CONFIG
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.openai:OpenAIEmbeddingsPlugin
OPENAI_API_TYPE=openai
# OPENAI_API_BASE=

# SECRET
OPENAI_API_KEY=
'@ }
        'aws_bedrock' { @'
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
'@ }
        'vertex_ai' { @'
# ============================================================
# 06_EMBEDDINGS_VERTEX_AI
# ============================================================

# CONFIG
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.vertexai:VertexAIEmbeddingsPlugin
PROJECT_ID=
LOCATION_ID=
EMBEDDING_MODEL_NAME=
GOOGLE_APPLICATION_CREDENTIALS=
'@ }
        'nvidia_nim' { @'
# ============================================================
# 06_EMBEDDINGS_NVIDIA_NIM
# ============================================================

# CONFIG
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.nvidia_nim:NvidiaNimEmbeddingsPlugin
NVIDIA_BASE_URL=

# SECRET
NVIDIA_API_KEY=
'@ }
        'ollama' { @'
# ============================================================
# 06_EMBEDDINGS_OLLAMA
# ============================================================

# CONFIG
EMBEDDINGS_PLUGIN_ENTRY_POINT=plugins.embeddings.ollama:OllamaEmbeddingsPlugin
OLLAMA_BASE_URL=
EMBEDDING_MODEL_NAME=
'@ }
        default { @'
# ============================================================
# 06_EMBEDDINGS_CUSTOM_OR_NOT_LISTED
# The selected embedding provider is not listed as a first-party embeddings block
# in the backend guide. Enter only variables required by your custom plugin.
# ============================================================

EMBEDDINGS_PLUGIN_ENTRY_POINT=
EMBEDDING_MODEL_NAME=
'@ }
 }
}

function Get-CloudVectorBlock { param([string]$P)
    switch ($P) {
        'azure_ai_search' { @'
# ============================================================
# 07_KNOWLEDGE_BASE_AZURE_COGNITIVE_SEARCH
# ============================================================

# CONFIG
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.az_cog_search:AzCognitiveSearchRetrieverPlugin
AZURE_COGNITIVE_SEARCH_SERVICE_NAME=

# SECRET
AZURE_COGNITIVE_SEARCH_API_KEY=
'@ }
        'milvus' { @'
# ============================================================
# 07_KNOWLEDGE_BASE_MILVUS
# ============================================================

# CONFIG
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.milvus:MilvusRetrieverPlugin
VECTORDB_URI=

# SECRET
VECTORDB_TOKEN=
'@ }
        'zilliz' { @'
# ============================================================
# 07_KNOWLEDGE_BASE_ZILLIZ_CLOUD
# ============================================================

# CONFIG
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.zilliz:ZillizRetrieverPlugin
ZILLIZ_CLOUD_URI=

# SECRET
ZILLIZ_CLOUD_API_KEY=
'@ }
        'qdrant' { @'
# ============================================================
# 07_KNOWLEDGE_BASE_QDRANT
# ============================================================

# CONFIG
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.qdrant:QdrantRetrieverPlugin
QDRANT_URL=

# SECRET - leave empty for local/no-auth Qdrant
QDRANT_API_KEY=
'@ }
        'mongodb_atlas' { @'
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
'@ }
        'redis' { @'
# ============================================================
# 07_KNOWLEDGE_BASE_REDIS
# ============================================================

# CONFIG or SECRET depending on whether credentials are embedded in the URL
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.redis:RedisRetrieverPlugin
REDIS_URL=
'@ }
        'vertex_vector_search' { @'
# ============================================================
# 07_KNOWLEDGE_BASE_VERTEX_AI_VECTOR_SEARCH
# ============================================================

# CONFIG
RETRIEVER_PLUGIN_ENTRY_POINT=plugins.retrievers.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin
PROJECT_ID=
LOCATION_ID=
GCS_BUCKET_NAME=
# PRIVATE_SC_IP=
'@ }
        'aws_bedrock_kb' { @'
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
'@ }
        'databricks' { @'
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
'@ }
        'pgvector' { @'
# ============================================================
# 07_KNOWLEDGE_BASE_POSTGRESQL_PGVECTOR
# Documented retriever variables only.
# ============================================================

# SECRET
PGVECTOR_CONNECTION_STRING=
'@ }
        default { @'
# ============================================================
# 07_KNOWLEDGE_BASE_CUSTOM_OR_OTHER
# Enter only variables documented by your custom retriever plugin.
# ============================================================

RETRIEVER_PLUGIN_ENTRY_POINT=
'@ }
 }
}

function Invoke-CloudMasterEnvMode {
    Write-Section 'Cloud  env shortlist mode'
    Write-Info 'This mode shortlists the env variables the customer must configure in the cloud platform.'

    # ----- optional: generate the four core credentials and inline them -----
    # By default the checklist is name-only. On request we run the official
    # generate_credentials.py and fill SECRET_KEY, HASHED_ADMIN_PASSWORD,
    # OAUTH2_CLIENT_SECRET_HASH and OAUTH2_CLIENT_ID directly into the template so the
    # customer can copy-paste them into their cloud secret manager. Customers who use
    # their own approved tool can decline, and the fields stay blank as before.
    $script:CLOUD_GEN_CREDS = 'no'
    $cSecretKey = ''; $cHashedAdmin = ''; $cOauthId = ''; $cOauthHash = ''
    Write-Info 'The four core credentials (SECRET_KEY, HASHED_ADMIN_PASSWORD, OAUTH2_CLIENT_ID, OAUTH2_CLIENT_SECRET_HASH) can be generated now and written straight into the checklist for copy-paste.'
    Write-Info 'Choose No if you prefer to produce them with your own approved tool - the fields will be left blank for you to fill in.'
    $genCloudCreds = Read-YesNo 'Generate these credentials now and fill them into the template?' 'no'
    if ($genCloudCreds -eq 'yes') {
        Write-Section 'Credentials'
        Ensure-Prereqs
        New-CredentialsFile (Join-Path $script:OUT_DIR 'copilot-generated-values.txt')
        $cSecretKey   = Get-FromCredentialsFile 'SECRET_KEY' $script:CREDENTIALS_FILE
        $cHashedAdmin = Get-FromCredentialsFile 'HASHED_ADMIN_PASSWORD' $script:CREDENTIALS_FILE
        $cOauthId     = Get-FromCredentialsFile 'OAUTH2_CLIENT_ID' $script:CREDENTIALS_FILE
        $cOauthHash   = Get-FromCredentialsFile 'OAUTH2_CLIENT_SECRET_HASH' $script:CREDENTIALS_FILE
        $script:CLOUD_GEN_CREDS = 'yes'
    }

    $script:IMAGE_TAG = Read-ImageTag 'Copilot backend/data-loader image tag to show in the checklist' $script:DEFAULT_IMAGE_TAG ''
    $script:FASTAPI_APP_VERSION = $script:IMAGE_TAG

    $script:ENABLE_ADMIN_CONSOLE = Read-YesNo 'Include Admin Console variables?' 'yes'
    $script:ENABLE_RAG = Read-YesNo 'Include RAG / Knowledge Base variables?' 'yes'

    $script:LLM_PROVIDER = Read-ChooseNum 'Which LLM provider should the checklist include?' 1 @(
        'azure_openai|Azure OpenAI',
        'openai|OpenAI',
        'aws_bedrock|AWS Bedrock',
        'vertex_ai|Google Vertex AI',
        'gemini|Google Gemini API',
        'nvidia_nim|NVIDIA NIM',
        'ollama|Ollama / self-hosted',
        'custom|Custom / other'
 )

    if ($script:ENABLE_RAG -eq 'yes') {
        $script:EMBEDDING_PROVIDER = Read-ChooseNum 'Which embeddings provider should the checklist include?' 1 @(
            'same_as_llm|Same family as selected LLM if documented',
            'azure_openai|Azure OpenAI embeddings',
            'openai|OpenAI embeddings',
            'aws_bedrock|AWS Bedrock embeddings',
            'vertex_ai|Google Vertex AI embeddings',
            'nvidia_nim|NVIDIA NIM embeddings',
            'ollama|Ollama embeddings',
            'custom|Custom / other embeddings'
 )
        if ($script:EMBEDDING_PROVIDER -eq 'same_as_llm') {
            switch ($script:LLM_PROVIDER) {
 { $_ -in @('azure_openai','openai','aws_bedrock','vertex_ai','nvidia_nim','ollama') } { $script:EMBEDDING_PROVIDER = $script:LLM_PROVIDER }
                default { $script:EMBEDDING_PROVIDER = 'custom'; Write-Warn "The backend guide does not list a first-party embeddings block for $($script:LLM_PROVIDER); using custom embeddings placeholders." }
 }
 }
        $script:VECTOR_DB_PROVIDER = Read-ChooseNum 'Which Vector DB / Knowledge Base should the checklist include?' 1 @(
            'azure_ai_search|Azure AI Search / Azure Cognitive Search',
            'milvus|Milvus self-hosted',
            'zilliz|Zilliz Cloud',
            'qdrant|Qdrant',
            'mongodb_atlas|MongoDB Atlas',
            'redis|Redis',
            'vertex_vector_search|Vertex AI Vector Search',
            'aws_bedrock_kb|AWS Bedrock Knowledge Bases',
            'databricks|Databricks',
            'pgvector|PostgreSQL pgvector',
            'custom|Custom / other'
 )
        if ($script:VECTOR_DB_PROVIDER -eq 'aws_bedrock_kb') {
            $script:ENABLE_DATA_LOADER = 'no'
            Write-Warn 'Bedrock Knowledge Bases usually use AWS-native ingestion. Data Loader variables will be omitted.'
 } else {
            $script:ENABLE_DATA_LOADER = Read-YesNo 'Include Data Loader variables?' 'yes'
 }
 } else {
        $script:EMBEDDING_PROVIDER = 'none'
        $script:VECTOR_DB_PROVIDER = 'none'
        $script:ENABLE_DATA_LOADER = 'no'
 }

    $script:ENABLE_AGENT_REGISTRY = Read-YesNo 'Include Agent Registry variables?' 'no'

    $cloudFile = Join-Path $script:OUT_DIR 'cloud-env-template.env'
    $targetLabel = Get-CloudTargetLabel $script:DEPLOYMENT_TARGET
    $secretStore = Get-CloudSecretStoreLabel $script:DEPLOYMENT_TARGET
    $secretHint  = Get-CloudSecretReferenceHint $script:DEPLOYMENT_TARGET

    if ($script:ENABLE_ADMIN_CONSOLE -eq 'yes') {
        $adminSection = @"
# ############################################################
# CONTAINER: ADMIN CONSOLE
# Copy every variable in this block into the Admin Console container.
# The SECRET values below MUST be identical to the same variables in
# the Orchestrator container - copy the exact same values into both.
# ############################################################

# CONFIG
ORCHESTRATOR_INTERNAL_URL=

# SECRET - must match the Orchestrator container exactly
SECRET_KEY=$($cSecretKey)
DATABASE_URL=
SYNC_DATABASE_URL=
HASHED_ADMIN_PASSWORD=$($cHashedAdmin)
"@
 } else {
        $adminSection = '# CONTAINER: ADMIN CONSOLE omitted because Admin Console was not selected.'
 }

    if ($script:ENABLE_RAG -eq 'yes') {
        $ragDefaultsSection = @'
# ============================================================
# 08_RAG_OPTIONAL_TUNING
# Optional documented RAG tuning values. Dont use them unless needed
# ============================================================

# CONFIG
# RAG_COLLECTIONS_METADATA=[]
# DEFAULT_RAG_TOPK=10
# DEFAULT_RAG_SCORE_THRESHOLD=0.5
# DEFAULT_RAG_RETRIEVER_TYPE=vector-store
'@
 } else {
        $ragDefaultsSection = '# 08_RAG_OPTIONAL_TUNING omitted because RAG was not selected.'
 }

    if ($script:ENABLE_DATA_LOADER -eq 'yes') {
        $dataLoaderSection = @'
# ############################################################
# CONTAINER: DATA LOADER
# Copy the documented Data Loader variables for the specific loader
# image you deploy (see the Data Loader guide) into this container.
# It reuses the SAME embeddings and vector-DB SECRET values as the
# Orchestrator container - copy those identical values here too.
# ############################################################
'@
 } else {
        $dataLoaderSection = '# CONTAINER: DATA LOADER omitted because Data Loader was not selected.'
 }

    if ($script:ENABLE_AGENT_REGISTRY -eq 'yes') {
        $agentSection = @'
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
'@
 } else {
        $agentSection = '# CONTAINER: AGENT REGISTRY omitted because Agent Registry was not selected.'
 }

    if ($script:ENABLE_RAG -eq 'yes') {
        $embeddingsBlock = Get-CloudEmbeddingsBlock $script:EMBEDDING_PROVIDER
        $vectorBlock = Get-CloudVectorBlock $script:VECTOR_DB_PROVIDER
 } else {
        $embeddingsBlock = '# 06_EMBEDDINGS omitted because RAG was not selected.'
        $vectorBlock = '# 07_VECTOR_DB omitted because RAG was not selected.'
 }
    $llmBlock = Get-CloudLlmBlock $script:LLM_PROVIDER

    if ($script:CLOUD_GEN_CREDS -eq 'yes') {
        $secretsPresentNote = @'
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
'@
    } else {
        $secretsPresentNote = '#'
    }

    $content = @"
# ============================================================
# Spotfire Copilot Cloud Template ENV Checklist
# Target deployment: $targetLabel
# Secret store: $secretStore
$secretsPresentNote
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
# 2. Put SECRET variables into $secretStore.
# 3. Put CONFIG variables into normal environment-variable configuration.
# 4. Keep STORE ONLY values in a password vault; do not inject them into containers.
# 5. Where a value is duplicated across blocks (e.g. SECRET_KEY, DATABASE_URL,
#    HASHED_ADMIN_PASSWORD in Orchestrator and Admin Console) use the IDENTICAL
#    value in every block - they must match.
# 6. Deploy the selected containers using the cloud provider UI, CLI, or IaC tool.
#
# CLOUD SECRET MAPPING
# $secretHint
#
# VARIABLE CLASSIFICATION
# SECRET     = store in cloud secret manager and reference from env var.
# CONFIG     = normal environment variable.
# STORE ONLY = keep in password vault; do not inject into containers.
#
# GENERATED SELECTIONS OVERVIEW
#
# Deployment target: $targetLabel
# LLM provider: $($script:LLM_PROVIDER)
# RAG enabled: $($script:ENABLE_RAG)
# Embeddings provider: $($script:EMBEDDING_PROVIDER)
# Vector DB provider: $($script:VECTOR_DB_PROVIDER)
# Data Loader: $($script:ENABLE_DATA_LOADER)
# Agent Registry: $($script:ENABLE_AGENT_REGISTRY)
# ============================================================

# ============================================================
# 00_DEPLOYMENT_AND_IMAGE_NOTES
# These are notes only, not container environment variables.
# Target deployment: $targetLabel
# Selected image tag: $($script:IMAGE_TAG)
# Orchestrator image: copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:$($script:IMAGE_TAG)
# Admin Console image: copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:$($script:IMAGE_TAG)
# Data Loader image family: copilotoci.azurecr.io/spotfirecopilot/data-loader-<type>:$($script:IMAGE_TAG)
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
SECRET_KEY=$($cSecretKey)
HASHED_ADMIN_PASSWORD=$($cHashedAdmin)
OAUTH2_CLIENT_SECRET_HASH=$($cOauthHash)

# GENERATED + CONFIG
OAUTH2_CLIENT_ID=$($cOauthId)

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

$llmBlock

$embeddingsBlock

$vectorBlock

$ragDefaultsSection

$adminSection

$dataLoaderSection

$agentSection

"@

    Write-EnvFile $cloudFile $content

    if ($script:CLOUD_GEN_CREDS -eq 'yes') {
        Protect-File $cloudFile
        Write-Warn 'This template now contains REAL generated secrets (SECRET_KEY, HASHED_ADMIN_PASSWORD, OAUTH2_CLIENT_SECRET_HASH). Please keep this template file safe: copy the values into your cloud secret manager, then delete the file or move it into a secure vault. Do not commit it to version control.'
    }

    Write-Ok 'Cloud template env checklist generated.'
    Write-Host "cloud-env-template.env: $cloudFile"
    Write-Host ''
    Write-Info 'No Docker Compose files were generated in cloud mode.'
    Write-Info 'Use the generated checklist to configure cloud secrets/env vars in the selected platform.'
}

# ----------------------------------------------------------------------------
# kubernetes (Helm) mode
# ----------------------------------------------------------------------------

# Map an LLM provider key to the orchestrator chart's model plugin entry point.
function Get-K8sModelPlugin { param([string]$Key)
    switch ($Key) {
        'azure_openai' { 'plugins.models.azure_openai_enhanced:AzureOpenAIPlugin' }
        'openai'       { 'plugins.models.openai_enhanced:OpenAIPlugin' }
        'aws_bedrock'  { 'plugins.models.bedrock_enhanced:BedrockPlugin' }
        'vertex_ai'    { 'plugins.models.vertexai_enhanced:VertexAIPlugin' }
        'gemini'       { 'plugins.models.gemini_enhanced:GeminiPlugin' }
        'nvidia_nim'   { 'plugins.models.nvidia_nim_enhanced:NvidiaNimPlugin' }
        'ollama'       { 'plugins.models.ollama_enhanced:OllamaPlugin' }
        default        { '' }
    }
}

# Map an embeddings provider key to the orchestrator chart's embeddings plugin entry point.
function Get-K8sEmbeddingsPlugin { param([string]$Key)
    switch ($Key) {
        'azure_openai' { 'plugins.embeddings.az_openai:AzOpenAIEmbeddingsPlugin' }
        'openai'       { 'plugins.embeddings.openai:OpenAIEmbeddingsPlugin' }
        'aws_bedrock'  { 'plugins.embeddings.bedrock:BedrockEmbeddingsPlugin' }
        'vertex_ai'    { 'plugins.embeddings.vertexai:VertexAIEmbeddingsPlugin' }
        'nvidia_nim'   { 'plugins.embeddings.nvidia_nim:NvidiaNimEmbeddingsPlugin' }
        'ollama'       { 'plugins.embeddings.ollama:OllamaEmbeddingsPlugin' }
        default        { '' }
    }
}

# Map a vector DB / retriever key to the orchestrator chart's retriever plugin entry point.
function Get-K8sRetrieverPlugin { param([string]$Key)
    switch ($Key) {
        'azure_ai_search'      { 'plugins.retrievers.az_cog_search:AzCognitiveSearchRetrieverPlugin' }
        'milvus'               { 'plugins.retrievers.milvus:MilvusRetrieverPlugin' }
        'zilliz'               { 'plugins.retrievers.zilliz:ZillizRetrieverPlugin' }
        'vertex_vector_search' { 'plugins.retrievers.vertexai_vector_search:VertexAIVectorSearchRetrieverPlugin' }
        'aws_bedrock_kb'       { 'plugins.retrievers.amazon_kbs:AmazonKBsRetrieverPlugin' }
        default                { '' }
    }
}

# Generate a Helm values bundle (values.yaml + secrets.values.yaml + helm-install.sh)
# for the official orchestrator-stack OCI chart. No cluster access is needed to
# generate the files; the operator runs helm-install.sh from a machine with helm
# and kubectl configured against the target cluster.
function Invoke-KubernetesMode {
    $chartVersion = '0.3.1'
    $k8sDir = Join-Path $script:OUT_DIR 'k8s'

    Write-Section 'Kubernetes (Helm) mode'
    Write-Info "This mode generates a Helm values bundle for the official Spotfire Copilot 'orchestrator-stack' chart."
    Write-Info "It writes values.yaml, secrets.values.yaml, helm-install.sh, and copilot-generated-values.txt under: $k8sDir"
    Write-Info 'The generated helm-install.sh deploys the orchestrator, optional Admin Console, and optional in-cluster PostgreSQL.'

    # Credentials first: run the official generate_credentials.py (mandated next to this
    # installer, exactly like the Linux VM flow) and capture its output so real values are
    # written into secrets.values.yaml instead of leaving blanks for manual pasting.
    Write-Section 'Credentials'
    Write-Info 'This mode runs the official generate_credentials.py and writes SECRET_KEY, HASHED_ADMIN_PASSWORD, OAUTH2_CLIENT_ID, and OAUTH2_CLIENT_SECRET_HASH into secrets.values.yaml.'
    Ensure-Prereqs
    if (-not (Test-Path $k8sDir)) { New-Item -ItemType Directory -Path $k8sDir -Force | Out-Null }
    New-CredentialsFile (Join-Path $k8sDir 'copilot-generated-values.txt')
    $k8sSecretKey     = Get-FromCredentialsFile 'SECRET_KEY' $script:CREDENTIALS_FILE
    $k8sHashedAdminPw = Get-FromCredentialsFile 'HASHED_ADMIN_PASSWORD' $script:CREDENTIALS_FILE
    $k8sOauthId       = Get-FromCredentialsFile 'OAUTH2_CLIENT_ID' $script:CREDENTIALS_FILE
    $k8sOauthHash     = Get-FromCredentialsFile 'OAUTH2_CLIENT_SECRET_HASH' $script:CREDENTIALS_FILE

    $k8sNamespace = Read-Prompt 'Kubernetes namespace to deploy into' 'copilot'
    $imageTag = Read-ImageTag 'Copilot orchestrator image tag' $script:DEFAULT_IMAGE_TAG 'copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator'
    if ([string]::IsNullOrEmpty($imageTag)) { $imageTag = $script:DEFAULT_IMAGE_TAG }
    $pullSecret = Read-Prompt 'Name of the Kubernetes image pull Secret for the ACR registry' 'orchestrator-acr-pull'

    $bundledDb = Read-YesNo 'Deploy a PostgreSQL container inside the cluster (bundled)? Choose No to use an external/managed PostgreSQL.' 'no'
    $pgPassword = ''; $dbUrl = ''; $syncDbUrl = ''; $pgStorageClass = ''; $pgSize = '100Gi'
    if ($bundledDb -eq 'yes') {
        $pgPassword = Get-RandomHex32
        $dbUrl = "postgresql+asyncpg://orchestrator:$pgPassword@orchestrator-postgresql:5432/orchestrator"
        $syncDbUrl = "postgresql://orchestrator:$pgPassword@orchestrator-postgresql:5432/orchestrator"
        $pgStorageClass = Read-Prompt 'StorageClass for the bundled PostgreSQL volume (leave blank for the cluster default)' ''
        $pgSize = Read-Prompt 'Persistent volume size for the bundled PostgreSQL' '100Gi'
        Write-Info 'A random PostgreSQL password was generated and written into secrets.values.yaml and the database URLs.'
    } else {
        Write-Info 'You chose external PostgreSQL. databaseUrl and syncDatabaseUrl will be left blank in secrets.values.yaml for you to fill in.'
    }

    $enableAdminConsole = Read-YesNo 'Deploy the Admin Console alongside the orchestrator?' 'yes'

    $llmProvider = Read-ChooseNum 'Which LLM provider will the orchestrator use?' 1 @(
        'azure_openai|Azure OpenAI',
        'openai|OpenAI',
        'aws_bedrock|AWS Bedrock',
        'vertex_ai|Google Vertex AI',
        'gemini|Google Gemini API',
        'nvidia_nim|NVIDIA NIM',
        'ollama|Ollama / self-hosted'
    )
    $modelPlugin = Get-K8sModelPlugin $llmProvider

    $enableRag = Read-YesNo 'Enable RAG / vector-store retrieval?' 'no'
    $embeddingsPlugin = ''; $retrieverPlugin = ''; $vectorDbProvider = 'none'; $embeddingProvider = 'none'
    if ($enableRag -eq 'yes') {
        $embeddingProvider = Read-ChooseNum 'Which embeddings provider?' 1 @(
            'azure_openai|Azure OpenAI embeddings',
            'openai|OpenAI embeddings',
            'aws_bedrock|AWS Bedrock embeddings',
            'vertex_ai|Google Vertex AI embeddings',
            'nvidia_nim|NVIDIA NIM embeddings',
            'ollama|Ollama embeddings'
        )
        $embeddingsPlugin = Get-K8sEmbeddingsPlugin $embeddingProvider
        $vectorDbProvider = Read-ChooseNum 'Which retriever / vector store?' 1 @(
            'azure_ai_search|Azure AI Search / Azure Cognitive Search',
            'milvus|Milvus',
            'zilliz|Zilliz Cloud',
            'vertex_vector_search|Vertex AI Vector Search',
            'aws_bedrock_kb|AWS Bedrock Knowledge Bases'
        )
        $retrieverPlugin = Get-K8sRetrieverPlugin $vectorDbProvider
    }

    $ingressClass = Read-ChooseNum 'Which ingress controller class should the Ingress resources use?' 1 @(
        'nginx|NGINX Ingress Controller',
        'alb|AWS ALB (aws-load-balancer-controller)',
        'none|No Ingress (use port-forward or your own routing)'
    )
    $orchHost = ''; $consoleHost = ''; $tls = 'no'; $orchTlsSecret = ''; $consoleTlsSecret = ''
    if ($ingressClass -ne 'none') {
        $orchHost = Read-Prompt 'Hostname for the orchestrator Ingress' 'orchestrator.example.com'
        if ($enableAdminConsole -eq 'yes') {
            $consoleHost = Read-Prompt 'Hostname for the Admin Console Ingress' 'orchestrator-console.example.com'
        }
        $tls = Read-YesNo "Enable TLS on the Ingress host(s)? Requires TLS Secret(s) to already exist in namespace $k8sNamespace." 'no'
        if ($tls -eq 'yes') {
            $orchTlsSecret = Read-Prompt 'TLS Secret name for the orchestrator host' 'orchestrator-tls'
            if ($enableAdminConsole -eq 'yes') {
                $consoleTlsSecret = Read-Prompt 'TLS Secret name for the Admin Console host' 'orchestrator-console-tls'
            }
        }
    }

    do { $replicas = (Read-Prompt 'Orchestrator replica count' '2').Trim() } until ($replicas -match '^[1-9][0-9]*$')
    $hpa = Read-YesNo 'Enable Horizontal Pod Autoscaling (HPA) for the orchestrator?' 'no'
    $hpaMax = '10'
    if ($hpa -eq 'yes') {
        do { $hpaMax = (Read-Prompt 'Maximum orchestrator replicas for HPA' '10').Trim() } until ($hpaMax -match '^[1-9][0-9]*$')
    }

    $resourcePreset = Read-ChooseNum 'Resource requests/limits preset for the orchestrator and console pods?' 2 @(
        'small|Small  - requests 250m CPU / 512Mi, limits 1 CPU / 1Gi',
        'medium|Medium - requests 500m CPU / 512Mi, limits 2 CPU / 2Gi (chart default)',
        'large|Large  - requests 1 CPU / 1Gi, limits 4 CPU / 4Gi'
    )
    switch ($resourcePreset) {
        'small' { $resCpuReq = '250m';  $resMemReq = '512Mi'; $resCpuLim = '1000m'; $resMemLim = '1Gi' }
        'large' { $resCpuReq = '1000m'; $resMemReq = '1Gi';   $resCpuLim = '4000m'; $resMemLim = '4Gi' }
        default { $resCpuReq = '500m';  $resMemReq = '512Mi'; $resCpuLim = '2000m'; $resMemLim = '2Gi' }
    }
    $resourcesBlock = @"
  resources:
    requests:
      cpu: "$resCpuReq"
      memory: "$resMemReq"
    limits:
      cpu: "$resCpuLim"
      memory: "$resMemLim"
"@

    # ----- assemble values.yaml blocks -----
    $orchConfig = @"
  config:
    logLevel: "INFO"
    storageType: "postgres"
    modelPluginEntryPoint: "$modelPlugin"
    secondaryModelPluginEntryPoint: "$modelPlugin"
"@
    if ($enableRag -eq 'yes') {
        $orchConfig = $orchConfig + @"

    embeddingsPluginEntryPoint: "$embeddingsPlugin"
    retrieverPluginEntryPoint: "$retrieverPlugin"
"@
    }

    if ($hpa -eq 'yes') {
        $autoscalingBlock = @"
  autoscaling:
    enabled: true
    minReplicas: $replicas
    maxReplicas: $hpaMax
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 75
"@
    } else {
        $autoscalingBlock = @"
  autoscaling:
    enabled: false
"@
    }

    $orchTlsYaml = "    tls: []"
    $consoleTlsYaml = "    tls: []"
    if ($tls -eq 'yes') {
        $orchTlsYaml = @"
    tls:
      - hosts:
          - "$orchHost"
        secretName: "$orchTlsSecret"
"@
        $consoleTlsYaml = @"
    tls:
      - hosts:
          - "$consoleHost"
        secretName: "$consoleTlsSecret"
"@
    }

    if ($ingressClass -eq 'none') {
        $orchIngressBlock = @"
  ingress:
    enabled: false
"@
    } else {
        $orchIngressBlock = @"
  ingress:
    enabled: true
    className: "$ingressClass"
    annotations: {}
    hosts:
      - host: "$orchHost"
        paths:
          - path: /
            pathType: Prefix
$orchTlsYaml
"@
    }

    if ($enableAdminConsole -eq 'yes') {
        if ($ingressClass -eq 'none') {
            $consoleIngress = @"
  ingress:
    enabled: false
"@
        } else {
            $consoleIngress = @"
  ingress:
    enabled: true
    className: "$ingressClass"
    annotations: {}
    hosts:
      - host: "$consoleHost"
        paths:
          - path: /
            pathType: Prefix
$consoleTlsYaml
"@
        }
        $consoleBlock = @"
orchestratorConsole:
  enabled: true
  replicaCount: 2
  imagePullSecrets:
    - name: "$pullSecret"
$resourcesBlock
  config:
    logLevel: "INFO"
    orchestratorInternalUrl: "http://orchestrator:80"
  secret:
    create: false
    existingSecretName: "orchestrator"
$consoleIngress
"@
    } else {
        $consoleBlock = @"
orchestratorConsole:
  enabled: false
"@
    }

    if ($bundledDb -eq 'yes') {
        $scLine = 'storageClass: ""'
        if (-not [string]::IsNullOrEmpty($pgStorageClass)) { $scLine = "storageClass: `"$pgStorageClass`"" }
        $pgBlock = @"
postgresql:
  enabled: true
  postgres:
    database: orchestrator
    username: orchestrator
  persistence:
    enabled: true
    size: $pgSize
    $scLine
"@
    } else {
        $pgBlock = @"
postgresql:
  enabled: false
"@
    }

    $valuesContent = @"
# ============================================================
# Spotfire Copilot - Kubernetes (Helm) values
# Chart: orchestrator-stack $chartVersion
# Release name: orchestrator   Namespace: $k8sNamespace
# Generated by spotfire-copilot-deploy.ps1
#
# Non-secret configuration only. Secrets live in secrets.values.yaml, which
# helm-install.sh passes AFTER this file so it overrides secret fields.
# ============================================================

# Single source of truth for the orchestrator + console image (both share it).
global:
  orchestratorImage:
    repository: "copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator"
    tag: "$imageTag"

orchestrator:
  replicaCount: $replicas
  imagePullSecrets:
    - name: "$pullSecret"
$resourcesBlock
$orchConfig
$autoscalingBlock
$orchIngressBlock

$consoleBlock

$pgBlock
"@

    # ----- assemble secrets.values.yaml blocks -----
    if ($bundledDb -eq 'yes') {
        $secretDbLines = @"
    # Bundled in-cluster PostgreSQL (postgresql.enabled=true). Password auto-generated.
    databaseUrl: "$dbUrl"
    syncDatabaseUrl: "$syncDbUrl"
"@
    } else {
        $secretDbLines = @"
    # External / managed PostgreSQL - FILL THESE IN before installing.
    # Async (asyncpg):  postgresql+asyncpg://USER:PASSWORD@HOST:5432/DBNAME
    # Sync  (psycopg2): postgresql://USER:PASSWORD@HOST:5432/DBNAME
    databaseUrl: ""
    syncDatabaseUrl: ""
"@
    }

    switch ($llmProvider) {
        'openai' { $providerSecretLines = '    openaiApiKey: ""' }
        'azure_openai' {
            $providerSecretLines = @"
    azureOpenaiApiKey: ""
    azureApiBase: ""
    azureApiVersion: ""
"@
        }
        'gemini' { $providerSecretLines = '    googleApiKey: ""' }
        'aws_bedrock' {
            $providerSecretLines = @"
    # Omit these if the pods use IRSA / instance roles instead of static keys.
    awsAccessKeyId: ""
    awsSecretAccessKey: ""
    awsRegionName: ""
"@
        }
        'vertex_ai' { $providerSecretLines = '    # Vertex AI uses a GCP service-account JSON via the chart gcpCredentials.* block, not an API key.' }
        'nvidia_nim' { $providerSecretLines = '    # No first-party API key required by default; use extraSecretEnv for custom endpoints/keys.' }
        'ollama' { $providerSecretLines = '    # No first-party API key required by default; use extraSecretEnv for custom endpoints/keys.' }
        default { $providerSecretLines = '    # Add provider credentials here or via extraSecretEnv.' }
    }

    $ragSecretLines = ''
    if ($enableRag -eq 'yes' -and $vectorDbProvider -eq 'azure_ai_search') {
        $ragSecretLines = '    azureCognitiveSearchApiKey: ""'
    }

    $pgSecretBlock = ''
    if ($bundledDb -eq 'yes') {
        $pgSecretBlock = @"

postgresql:
  postgres:
    password: "$pgPassword"
"@
    }

    $secretsContent = @"
# ============================================================
# Spotfire Copilot - Kubernetes (Helm) SECRET values
# Chart: orchestrator-stack $chartVersion
#
# SENSITIVE - do NOT commit to version control.
# helm-install.sh passes this file with -f AFTER values.yaml.
# The Admin Console reuses this Secret via existingSecretName: orchestrator.
# ============================================================

orchestrator:
  secret:
    create: true
    # Auto-filled by generate_credentials.py (also saved to copilot-generated-values.txt).
    secretKey: '$k8sSecretKey'
    hashedAdminPassword: '$k8sHashedAdminPw'
    oauth2ClientId: '$k8sOauthId'
    oauth2ClientSecretHash: '$k8sOauthHash'
$secretDbLines
    # Provider credentials ($llmProvider):
$providerSecretLines
$ragSecretLines
$pgSecretBlock
"@

    # ----- helm-install.sh wrapper -----
    $installScript = @"
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Spotfire Copilot - orchestrator-stack Helm installer
# Generated by spotfire-copilot-deploy.ps1
# ============================================================

NAMESPACE="$k8sNamespace"
RELEASE="orchestrator"
CHART="oci://copilotoci.azurecr.io/spotfirecopilot/orchestrator-stack"
CHART_VERSION="$chartVersion"
REGISTRY="copilotoci.azurecr.io"
PULL_SECRET="$pullSecret"

SCRIPT_DIR="`$(cd "`$(dirname "`${BASH_SOURCE[0]}")" && pwd)"
VALUES="`$SCRIPT_DIR/values.yaml"
SECRETS="`$SCRIPT_DIR/secrets.values.yaml"

command -v helm >/dev/null 2>&1 || { echo "ERROR: helm not found on PATH."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found on PATH."; exit 1; }

echo "==> Logging in to `$REGISTRY (Helm OCI registry)"
if command -v az >/dev/null 2>&1; then
  az acr login --name "`${REGISTRY%%.*}" || {
    echo "az acr login failed; falling back to 'helm registry login'."
    helm registry login "`$REGISTRY"
  }
else
  echo "Azure CLI not found; using 'helm registry login' (you will be prompted for registry credentials)."
  helm registry login "`$REGISTRY"
fi

echo "==> Ensuring namespace `$NAMESPACE exists"
kubectl create namespace "`$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

if ! kubectl -n "`$NAMESPACE" get secret "`$PULL_SECRET" >/dev/null 2>&1; then
  echo "NOTE: image pull secret '`$PULL_SECRET' not found in namespace `$NAMESPACE."
  echo "The pods reference it to pull from `$REGISTRY. Create it with your registry credentials, e.g.:"
  echo "  kubectl -n `$NAMESPACE create secret docker-registry `$PULL_SECRET --docker-server=`$REGISTRY --docker-username=<user> --docker-password=<password>"
fi

echo "==> helm upgrade --install `$RELEASE (chart `$CHART_VERSION) into namespace `$NAMESPACE"
helm upgrade --install "`$RELEASE" "`$CHART" --version "`$CHART_VERSION" --namespace "`$NAMESPACE" --create-namespace -f "`$VALUES" -f "`$SECRETS"

echo "==> Done. Check the rollout with:"
echo "   kubectl -n `$NAMESPACE get pods"
"@

    if (-not (Test-Path $k8sDir)) { New-Item -ItemType Directory -Path $k8sDir -Force | Out-Null }
    Write-TextFileLF -Path (Join-Path $k8sDir 'values.yaml') -Content $valuesContent
    Write-TextFileLF -Path (Join-Path $k8sDir 'secrets.values.yaml') -Content $secretsContent
    Write-TextFileLF -Path (Join-Path $k8sDir 'helm-install.sh') -Content $installScript
    Protect-File (Join-Path $k8sDir 'secrets.values.yaml')

    Write-Ok "Kubernetes Helm bundle generated under: $k8sDir"
    Write-Host '  values.yaml                    - non-secret Helm values'
    Write-Host '  secrets.values.yaml            - SECRET values, credentials pre-filled (do not commit)'
    Write-Host '  copilot-generated-values.txt   - raw generate_credentials.py output (do not commit)'
    Write-Host "  helm-install.sh                - installs orchestrator-stack $chartVersion into namespace $k8sNamespace"
    Write-Host ''
    Write-Info 'Next steps:'
    Write-Info "1. Credentials were generated and written into secrets.values.yaml (also saved to $(Join-Path $k8sDir 'copilot-generated-values.txt')). Store the plaintext admin password / OAuth client secret shown above in a secure vault."
    if ($bundledDb -ne 'yes') {
        Write-Info '2. Fill in databaseUrl and syncDatabaseUrl (external PostgreSQL) in secrets.values.yaml.'
    }
    Write-Info "3. Ensure the '$pullSecret' image pull secret exists in namespace $k8sNamespace (helm-install.sh prints the command if it is missing)."
    Write-Info "4. From a machine with helm + kubectl access to the cluster, run: $(Join-Path $k8sDir 'helm-install.sh')"
    Write-Warn 'secrets.values.yaml contains sensitive data. Keep it out of version control.'
}

# ============================================================================
# main
# ============================================================================

# ---- parse command-line arguments (accepts BOTH PowerShell -Style and GNU --style) ----
# Arguments arrive verbatim in $CliArgs (see the param block note). Each flag is
# normalized by stripping leading dashes and internal dashes and lower-casing, so
# "-ImageTag", "--image-tag" and "--image-tag=X" all resolve to the same option.
$script:__cli = @($CliArgs)
$script:__cliIdx = 0
function Get-CliArgValue {
    param([string]$Flag, [AllowNull()][string]$Inline)
    if (-not [string]::IsNullOrEmpty($Inline)) { return $Inline }
    $script:__cliIdx++
    if ($script:__cliIdx -ge $script:__cli.Count) { Invoke-Die "Option '$Flag' requires a value." }
    return $script:__cli[$script:__cliIdx]
}
while ($script:__cliIdx -lt $script:__cli.Count) {
    $__tok = $script:__cli[$script:__cliIdx]
    if ([string]::IsNullOrEmpty($__tok)) { $script:__cliIdx++; continue }
    # Split "--flag=value" (GNU) into flag + inline value. A leading "-" is required;
    # the "[^=]" guard avoids splitting Windows drive paths passed as a value token.
    $__inline = $null
    if ($__tok -match '^(--?[A-Za-z0-9][A-Za-z0-9-]*)=(.*)$') { $__flagRaw = $matches[1]; $__inline = $matches[2] } else { $__flagRaw = $__tok }
    if ($__flagRaw -notmatch '^-') { Invoke-Die "Unexpected argument: '$__tok'. See -Help for usage." }
    $__norm = (($__flagRaw -replace '^-+', '') -replace '-', '').ToLower()
    switch ($__norm) {
        'help'                 { $script:MODE = 'help' }
        'h'                    { $script:MODE = 'help' }
        '?'                    { $script:MODE = 'help' }
        'info'                 { $script:MODE = 'info' }
        'upgrade'              { $script:MODE = 'upgrade' }
        'imagetag'             { $script:UPGRADE_IMAGE_TAG = (Get-CliArgValue $__flagRaw $__inline) }
        'agenttag'             { $script:UPGRADE_AGENT_TAG = (Get-CliArgValue $__flagRaw $__inline) }
        'dir'                  { $script:OUT_DIR = (Get-CliArgValue $__flagRaw $__inline); $script:OUT_DIR_EXPLICIT = 'yes' }
        'fromdir'              { $script:FROM_DIR = (Get-CliArgValue $__flagRaw $__inline) }
        'yes'                  { $script:ASSUME_YES = 'yes' }
        'y'                    { $script:ASSUME_YES = 'yes' }
        'installprereqs'       { $script:INSTALL_PREREQS = 'yes' }
        'noinstallprereqs'     { $script:INSTALL_PREREQS = 'no' }
        'installdeepagents'    { $script:WITH_DEEPAGENTS = 'yes' }
        'withdeepagents'       { $script:WITH_DEEPAGENTS = 'yes' }
        'deepagentsscript'     { $script:DEEPAGENTS_SCRIPT = (Get-CliArgValue $__flagRaw $__inline) }
        'credentialsscript'    { $script:CREDENTIALS_SCRIPT = (Get-CliArgValue $__flagRaw $__inline) }
        'installagentregistry' { $script:MODE = 'agent_registry_only'; $script:INSTALL_AGENT_REGISTRY_ONLY = 'yes' }
        'installagentresgirty' { $script:MODE = 'agent_registry_only'; $script:INSTALL_AGENT_REGISTRY_ONLY = 'yes' }
        'nocolor'              { $script:UseColor = $false }
        default                { Invoke-Die "Unknown option: '$__flagRaw'. See -Help for usage." }
    }
    $script:__cliIdx++
}

if ($script:MODE -eq 'help') { Show-Help; exit 0 }

if ($script:MODE -eq 'info') { Set-DefaultDirForInfo }
if ($script:MODE -eq 'upgrade') { Invoke-Upgrade; exit 0 }
if ($script:MODE -eq 'agent_registry_only') { Invoke-AgentRegistryOnly; exit 0 }

# With an explicit -Dir/OUT_DIR the target is known now. For interactive generation the
# backend directory is finalized later from the image tag (Set-FinalOutDirForTag), so
# it is not created here.
if ($script:OUT_DIR_EXPLICIT -eq 'yes' -or $script:MODE -eq 'info') {
    if (-not (Test-Path $script:OUT_DIR)) { New-Item -ItemType Directory -Path $script:OUT_DIR -Force | Out-Null }
    Push-Location $script:OUT_DIR
    $script:OUT_DIR = (Get-Location).Path
    Pop-Location
}
$script:DEFAULT_CREDENTIALS_FILE = Get-DefaultCredentialsFile
$script:EXISTING_FILES = @(
 (Join-Path $script:OUT_DIR '.env'),
 (Join-Path $script:OUT_DIR '.env.orchestrator'),
 (Join-Path $script:OUT_DIR '.env.dataloader'),
 (Join-Path $script:OUT_DIR '.env.agent-registry')
)
if ($script:MODE -eq 'info') { Show-CurrentInfo; exit 0 }

if ($script:UseColor) {
    Write-Host '================================================================' -ForegroundColor Magenta
    Write-Host 'Spotfire Copilot 2.3.x Environment File Generator - ' -ForegroundColor Magenta
    if ($script:OUT_DIR_EXPLICIT -eq 'yes') {
        Write-Host "Output directory: $($script:OUT_DIR)" -ForegroundColor Magenta
    } else {
        Write-Host 'Output directory: set from the image tag you enter below' -ForegroundColor Magenta
    }
    Write-Host '================================================================' -ForegroundColor Magenta
} else {
    Write-Host '================================================================'
    Write-Host 'Spotfire Copilot 2.3.x Environment File Generator - '
    if ($script:OUT_DIR_EXPLICIT -eq 'yes') {
        Write-Host "Output directory: $($script:OUT_DIR)"
    } else {
        Write-Host 'Output directory: set from the image tag you enter below'
    }
    Write-Host '================================================================'
}

Write-Section 'Deployment target'
$script:DEPLOYMENT_TARGET = Read-ChooseNum 'Where are you deploying Spotfire Copilot?' 1 @(
    'linux_vm|Linux VM / Docker Compose',
    'azure_container_apps|Azure Container Apps',
    'aws_ecs_fargate|AWS ECS / Fargate',
    'gcp_cloud_run|GCP Cloud Run',
    'kubernetes|Kubernetes (AKS / EKS / GKE)',
    'other_cloud|Other cloud / customer-managed container platform'
)

if ($script:DEPLOYMENT_TARGET -ne 'linux_vm') {
    if ($script:OUT_DIR_EXPLICIT -eq 'no') {
        if (-not (Test-Path $script:OUT_DIR)) { New-Item -ItemType Directory -Path $script:OUT_DIR -Force | Out-Null }
        Push-Location $script:OUT_DIR
        $script:OUT_DIR = (Get-Location).Path
        Pop-Location
    }
    if ($script:DEPLOYMENT_TARGET -eq 'kubernetes') {
        Invoke-KubernetesMode
    } else {
        Invoke-CloudMasterEnvMode
    }
    Save-LastOutDir
    exit 0
}

Write-Section 'Required core setup'
Write-Info 'Core setup creates the Orchestrator configuration needed for authentication, PostgreSQL persistence, and LLM calls.'

$imageTagDefault = Get-ExistingOr 'IMAGE_TAG' $script:DEFAULT_IMAGE_TAG
$script:IMAGE_TAG = Read-ImageTag 'Copilot backend/data-loader image tag' $imageTagDefault 'copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator'
$script:FASTAPI_APP_VERSION = $script:IMAGE_TAG
Write-Info "FASTAPI_APP_VERSION will be set automatically to $($script:FASTAPI_APP_VERSION)."
Set-FinalOutDirForTag $script:IMAGE_TAG
$composeProjectDefault = Get-ExistingOr 'COMPOSE_PROJECT_NAME' 'spotfire-copilot'
$logLevelDefault = Get-ExistingOr 'LOG_LEVEL' 'INFO'
$accessDaysDefault = Get-ExistingOr 'ACCESS_TOKEN_EXPIRE_DAYS' '30'
$script:COMPOSE_PROJECT_NAME = Read-Prompt 'Docker Compose project name' $composeProjectDefault
$script:LOG_LEVEL = Read-Prompt 'LOG_LEVEL' $logLevelDefault
$script:ACCESS_TOKEN_EXPIRE_DAYS = Read-Prompt 'ACCESS_TOKEN_EXPIRE_DAYS' $accessDaysDefault

Write-Section 'Credentials'
Write-Info 'Credentials are required, but generating them is optional if you already have valid values.'
Write-Info 'Credential search order: current working directory, script directory, then selected backend folder.'
Write-Info 'Expected keys: SECRET_KEY, HASHED_ADMIN_PASSWORD, OAUTH2_CLIENT_ID, OAUTH2_CLIENT_SECRET_HASH.'
$haveCreds = Read-YesNo 'Have you already generated Spotfire Copilot credentials?' 'yes'
if ($haveCreds -eq 'yes') {
    $script:CREDENTIALS_FILE = Read-Prompt 'Please provide path to existing copilot-generated-values.txt. If missing, I can pick up from existing env values or you could enter them manually' $script:DEFAULT_CREDENTIALS_FILE
    $script:CREDENTIALS_FILE = Resolve-CredentialsPath $script:CREDENTIALS_FILE
    if (Test-Path $script:CREDENTIALS_FILE) {
        Write-Info "Using credential file: $($script:CREDENTIALS_FILE)"
 } else {
        Write-Warn "Credential file not found at $($script:CREDENTIALS_FILE). The script will try existing .env files first, then prompt for missing values."
 }
} else {
    $script:CREDENTIALS_FILE = Join-Path $script:OUT_DIR 'copilot-generated-values.txt'
    Write-Info "No existing credentials selected. Credentials will be generated automatically at: $($script:CREDENTIALS_FILE)"
 Warn-AdminPasswordRegenExistingState
    if (Test-Path $script:CREDENTIALS_FILE) {
        $regen = Read-YesNo 'Credential file already exists in the backend folder. Regenerate and overwrite it?' 'no'
        if ($regen -eq 'yes') {
            Backup-File $script:CREDENTIALS_FILE
 Ensure-Prereqs
            New-CredentialsFile $script:CREDENTIALS_FILE
 } else {
            Write-Info "Using existing credential file: $($script:CREDENTIALS_FILE)"
 }
 } else {
 Ensure-Prereqs
        New-CredentialsFile $script:CREDENTIALS_FILE
 }
}

if (Test-Path $script:CREDENTIALS_FILE) {
    Write-Info "Credential file selected: $($script:CREDENTIALS_FILE)"
    Copy-CredentialsToOutDir $script:CREDENTIALS_FILE
} else {
    Write-Warn 'No credential file selected; falling back to existing env files or manual prompts.'
}

$secretKeyFile = Get-FromCredentialsFile 'SECRET_KEY' $script:CREDENTIALS_FILE
$hashedAdminFile = Get-FromCredentialsFile 'HASHED_ADMIN_PASSWORD' $script:CREDENTIALS_FILE
$oauthClientIdFile = Get-FromCredentialsFile 'OAUTH2_CLIENT_ID' $script:CREDENTIALS_FILE
$oauthClientSecretHashFile = Get-FromCredentialsFile 'OAUTH2_CLIENT_SECRET_HASH' $script:CREDENTIALS_FILE
$loadedCount = 0
if (-not [string]::IsNullOrEmpty($secretKeyFile)) { $loadedCount++ }
if (-not [string]::IsNullOrEmpty($hashedAdminFile)) { $loadedCount++ }
if (-not [string]::IsNullOrEmpty($oauthClientIdFile)) { $loadedCount++ }
if (-not [string]::IsNullOrEmpty($oauthClientSecretHashFile)) { $loadedCount++ }
$useLoadedCreds = 'no'
if ($loadedCount -eq 4) {
    Write-Ok 'Loaded SECRET_KEY from credential file.'
    Write-Ok 'Loaded HASHED_ADMIN_PASSWORD from credential file.'
    Write-Ok "Loaded OAUTH2_CLIENT_ID from credential file: $(Get-Mask $oauthClientIdFile)"
    Write-Ok 'Loaded OAUTH2_CLIENT_SECRET_HASH from credential file.'
    $useLoadedCreds = Read-YesNo 'Use credentials loaded from copilot-generated-values.txt without re-prompting?' 'yes'
} else {
    Write-Warn "Loaded $loadedCount/4 credential values from the credential file. Missing values will be requested."
}
if ($useLoadedCreds -eq 'yes') {
    $script:SECRET_KEY = $secretKeyFile
    $script:HASHED_ADMIN_PASSWORD = $hashedAdminFile
    $script:OAUTH2_CLIENT_ID = $oauthClientIdFile
    $script:OAUTH2_CLIENT_SECRET_HASH = $oauthClientSecretHashFile
} else {
    $secretKeyDefault = if (-not [string]::IsNullOrEmpty($secretKeyFile)) { $secretKeyFile } else { Get-ExistingOr 'SECRET_KEY' '' }
    if ([string]::IsNullOrEmpty($secretKeyDefault)) { $secretKeyDefault = Get-RandomHex32 }
    $hashedAdminDefault = if (-not [string]::IsNullOrEmpty($hashedAdminFile)) { $hashedAdminFile } else { Get-ExistingOr 'HASHED_ADMIN_PASSWORD' '' }
    $oauthClientIdDefault = if (-not [string]::IsNullOrEmpty($oauthClientIdFile)) { $oauthClientIdFile } else { Get-ExistingOr 'OAUTH2_CLIENT_ID' '' }
    $oauthClientSecretHashDefault = if (-not [string]::IsNullOrEmpty($oauthClientSecretHashFile)) { $oauthClientSecretHashFile } else { Get-ExistingOr 'OAUTH2_CLIENT_SECRET_HASH' '' }
    Write-Info 'Review/edit each credential value. Press Enter to keep the loaded/default value.'
    $script:SECRET_KEY = Read-Prompt 'SECRET_KEY' $secretKeyDefault -Secret
    $script:HASHED_ADMIN_PASSWORD = Read-Prompt 'HASHED_ADMIN_PASSWORD bcrypt hash' $hashedAdminDefault -Secret
    $script:OAUTH2_CLIENT_ID = Read-Prompt 'OAUTH2_CLIENT_ID' $oauthClientIdDefault
    $script:OAUTH2_CLIENT_SECRET_HASH = Read-Prompt 'OAUTH2_CLIENT_SECRET_HASH bcrypt hash' $oauthClientSecretHashDefault -Secret
}
# No placeholder fallback: credentials must be real. If any value is still missing at
# this point, stop rather than writing an .env that cannot work.
$credMissing = @()
if ([string]::IsNullOrEmpty($script:SECRET_KEY)) { $credMissing += 'SECRET_KEY' }
if ([string]::IsNullOrEmpty($script:HASHED_ADMIN_PASSWORD)) { $credMissing += 'HASHED_ADMIN_PASSWORD' }
if ([string]::IsNullOrEmpty($script:OAUTH2_CLIENT_ID)) { $credMissing += 'OAUTH2_CLIENT_ID' }
if ([string]::IsNullOrEmpty($script:OAUTH2_CLIENT_SECRET_HASH)) { $credMissing += 'OAUTH2_CLIENT_SECRET_HASH' }
if ($credMissing.Count -gt 0) {
    Invoke-Die "Missing required credential values: $($credMissing -join ', '). Run generate_credentials.py (place it next to this installer and choose 'No' at the credentials question), or provide a copilot-generated-values.txt that contains all four values."
}

Write-Section 'Required backend database for Orchestrator'
Write-Info 'PostgreSQL is required because Orchestrator stores backend state such as users, OAuth clients, conversations, threads, agents, and token-related data.'
$script:POSTGRES_MODE = Read-ChooseNum 'Where should Orchestrator store its PostgreSQL data?' 1 @(
    'existing|Use existing PostgreSQL / managed PostgreSQL',
    'compose|Create PostgreSQL using this Docker Compose deployment'
)
if ($script:POSTGRES_MODE -eq 'existing') {
    $script:POSTGRES_HOST = Read-Prompt 'PostgreSQL host' (Get-ExistingOr 'POSTGRES_HOST' 'postgres.example.com')
    $script:POSTGRES_PORT = Read-Prompt 'PostgreSQL port' (Get-ExistingOr 'POSTGRES_PORT' '5432')
    $script:POSTGRES_DB   = Read-PgIdentifier 'PostgreSQL database name' (Get-Existing 'POSTGRES_DB' $script:EXISTING_FILES) 'orchestrator'
    $script:POSTGRES_USER = Read-PgIdentifier 'PostgreSQL username' (Get-Existing 'POSTGRES_USER' $script:EXISTING_FILES) 'orchestrator'
    $script:POSTGRES_PASSWORD = Read-Prompt 'PostgreSQL password' '' -Secret
    $sslDefault = Get-ExistingOr 'DB_SSLMODE' 'require'
    switch (("$sslDefault").Trim().ToLower()) {
 { $_ -in @('disable','disabled','false','off','none','no') } { $sslDefNum = 1 }
        'allow' { $sslDefNum = 2 }
        'prefer' { $sslDefNum = 3 }
        'verify-ca' { $sslDefNum = 5 }
        'verify-full' { $sslDefNum = 6 }
        default { $sslDefNum = 4 }
 }
    Write-Info "If your PostgreSQL server does NOT have SSL/TLS enabled (no certificate), choose 'disable'. Managed/cloud PostgreSQL usually needs 'require' or stricter."
    $script:DB_SSLMODE = Read-ChooseNum 'PostgreSQL SSL mode (DB_SSLMODE)' $sslDefNum @(
        'disable|disable - no SSL (use this if the server has no SSL certificate)',
        'allow|allow - try non-SSL first, then SSL',
        'prefer|prefer - try SSL first, fall back to non-SSL',
        'require|require - SSL required, without certificate verification',
        'verify-ca|verify-ca - SSL required, verify the server certificate CA',
        'verify-full|verify-full - SSL required, verify CA and hostname'
 )
    if ([string]::IsNullOrEmpty($script:POSTGRES_PASSWORD)) {
        $existingDbUrl = Get-ExistingOr 'DATABASE_URL' ''
        $existingSyncDbUrl = Get-ExistingOr 'SYNC_DATABASE_URL' ''
        if (-not [string]::IsNullOrEmpty($existingDbUrl) -and -not [string]::IsNullOrEmpty($existingSyncDbUrl)) {
            $script:DATABASE_URL = $existingDbUrl
            $script:SYNC_DATABASE_URL = $existingSyncDbUrl
            Write-Warn 'PostgreSQL password blank. Reusing existing DATABASE_URL and SYNC_DATABASE_URL.'
 } else {
            $script:POSTGRES_PASSWORD = 'REPLACE_WITH_POSTGRES_PASSWORD'
            Build-DatabaseUrls
 }
 } else {
        Build-DatabaseUrls
 }
} else {
    $script:POSTGRES_HOST = 'orchestrator-postgres'
    $script:POSTGRES_PORT = '5432'
    $script:DB_SSLMODE = 'disable'
    $script:POSTGRES_HOST_PORT = Read-Prompt 'Bundled PostgreSQL host port (published on 127.0.0.1; container port stays 5432)' '5432'
    $script:POSTGRES_DB   = Read-PgIdentifier 'Compose PostgreSQL database name' (Get-Existing 'POSTGRES_DB' $script:EXISTING_FILES) 'orchestrator'
    $script:POSTGRES_USER = Read-PgIdentifier 'Compose PostgreSQL username' (Get-Existing 'POSTGRES_USER' $script:EXISTING_FILES) 'orchestrator'
    $defaultComposePgPass = Get-ExistingOr 'POSTGRES_PASSWORD' ''

    if (Test-ExistingComposePostgresVolume) {
        Write-Warn 'Existing Docker Compose PostgreSQL volume detected. POSTGRES_PASSWORD initializes the database only when the data directory is empty; changing the env file later does not change the password stored inside the existing database volume.'
        $action = Read-ChooseNum 'How should the installer handle the existing local PostgreSQL volume?' 1 @(
            'reuse|Reuse existing local PostgreSQL data; I will enter/reuse the ORIGINAL database password',
            'reset|Fresh lab/test install; generate env with a new password and create a reset helper to delete the local PostgreSQL volume'
 )
        if ($action -eq 'reuse') {
            $script:POSTGRES_PASSWORD = Read-Prompt 'Existing Compose PostgreSQL password used when the volume was first initialized' $defaultComposePgPass -Secret
            if ([string]::IsNullOrEmpty($script:POSTGRES_PASSWORD)) {
                Invoke-Die 'Existing local PostgreSQL volume selected, but no password was provided. Enter the original database password or choose the reset option for a disposable lab install.'
 }
 } else {
            $script:POSTGRES_RESET_LOCAL_VOLUME_SELECTED = 'yes'
            $defaultComposePgPass = "Copilot_Postgres_$(-join ((Get-RandomHex32)[0..15]))"
            Write-Info 'A strong PostgreSQL password was auto-generated for the reinitialized volume.'
            $script:POSTGRES_PASSWORD = Read-Prompt 'New Compose PostgreSQL password for reinitialized local volume' $defaultComposePgPass -Secret -DefaultHint 'press Enter to accept the generated password'
            Write-ResetComposePostgresHelper
            Write-Warn "You selected a fresh lab/test reset. The installer will offer to run the targeted reset ($($script:OUT_DIR)\reset-local-postgres-volume.ps1) after the files are generated. If you skip it, run that helper before starting/restarting the stack."
 }
 } else {
        if (-not [string]::IsNullOrEmpty($defaultComposePgPass)) {
            # A saved POSTGRES_PASSWORD was found in an existing env file (re-run without a volume).
            $script:POSTGRES_PASSWORD = Read-Prompt 'Compose PostgreSQL password' $defaultComposePgPass -Secret
 } else {
            # Fresh install: nothing was saved, so generate a strong password as the default.
            $defaultComposePgPass = "Copilot_Postgres_$(-join ((Get-RandomHex32)[0..15]))"
            Write-Info 'A strong PostgreSQL password was auto-generated for this fresh install.'
            $script:POSTGRES_PASSWORD = Read-Prompt 'Compose PostgreSQL password' $defaultComposePgPass -Secret -DefaultHint 'press Enter to accept the generated password'
 }
 }
    Build-DatabaseUrls
}

Configure-LlmProvider

Write-Section 'Orchestrator host port'
Write-Info 'The Orchestrator API is published on this host port. The container port stays 8080; change the host port only if 8080 is already in use on this host.'
$script:ORCH_HOST_PORT = Read-Prompt 'Orchestrator host port' '8080'

Write-Section 'Optional Admin Console'
Write-Info 'Admin Console is optional and uses the same PostgreSQL database already configured for Orchestrator.'
$script:ENABLE_ADMIN_CONSOLE = Read-YesNo 'Deploy Admin Console?' 'yes'
if ($script:ENABLE_ADMIN_CONSOLE -eq 'no') {
    Write-Warn 'Skipping Admin Console: manage OAuth clients, users, diagnostics, conversations, RAG indexes, and agents through REST API instead of the web UI.'
} else {
    $script:ADMIN_HOST_PORT = Read-Prompt 'Admin Console host port (container port stays 8081)' '8081'
}

Write-Section 'Optional RAG / Knowledge Base'
Write-Info 'RAG is required for Help, HowTo, Spotfire documentation answers, and custom document Q&A.'
$script:ENABLE_RAG = Read-YesNo 'Enable RAG / Knowledge Base?' 'no'
$script:ENABLE_DATA_LOADER = 'no'
if ($script:ENABLE_RAG -eq 'no') {
    Write-Warn 'Skipping RAG: Orchestrator and LLM smoke tests can work, but Help, HowTo, docs answers, and custom document Q&A will not work.'
    $script:EMBED_BLOCK_ORCH = '# OPTIONAL: RAG disabled by installer choice; configure an embeddings plugin when enabling RAG.'
    $script:EMBED_BLOCK_DL = '# OPTIONAL: Data Loader disabled because RAG was not enabled.'
    $script:VECTOR_BLOCK_ORCH = '# OPTIONAL: RAG disabled by installer choice; configure a retriever plugin/vector DB for Help, HowTo, and document Q&A.'
    $script:VECTOR_BLOCK_DL = '# OPTIONAL: Data Loader disabled because RAG was not enabled.'
    $script:DEFAULT_HOWTO_INDEX = 'spotfiredocs'; $script:DEFAULT_RAG_TOPK = '10'; $script:DEFAULT_RAG_SCORE_THRESHOLD = '0.5'
    $script:RAG_DEFAULTS_BLOCK = ''
} else {
 Configure-Embeddings
 Configure-VectorDb
    $script:DEFAULT_HOWTO_INDEX = Get-ExistingOr 'DEFAULT_HOWTO_INDEX' 'spotfiredocs'
    $script:DEFAULT_RAG_TOPK = Get-ExistingOr 'DEFAULT_RAG_TOPK' '10'
    $script:DEFAULT_RAG_SCORE_THRESHOLD = Get-ExistingOr 'DEFAULT_RAG_SCORE_THRESHOLD' '0.5'
    $script:DEFAULT_HOWTO_INDEX = Read-Prompt 'Default Spotfire docs / HowTo index name' $script:DEFAULT_HOWTO_INDEX
    $script:DEFAULT_RAG_TOPK = Read-Prompt 'DEFAULT_RAG_TOPK' $script:DEFAULT_RAG_TOPK
    $script:DEFAULT_RAG_SCORE_THRESHOLD = Read-Prompt 'DEFAULT_RAG_SCORE_THRESHOLD' $script:DEFAULT_RAG_SCORE_THRESHOLD
    $script:RAG_DEFAULTS_BLOCK = @"
# RECOMMENDED: Default Spotfire docs / HowTo index name.
DEFAULT_HOWTO_INDEX=$($script:DEFAULT_HOWTO_INDEX)
# OPTIONAL: Number of RAG chunks to retrieve.
DEFAULT_RAG_TOPK=$($script:DEFAULT_RAG_TOPK)
# OPTIONAL: Minimum RAG relevance score threshold.
DEFAULT_RAG_SCORE_THRESHOLD=$($script:DEFAULT_RAG_SCORE_THRESHOLD)
# RECOMMENDED: Default RAG retriever type.
DEFAULT_RAG_RETRIEVER_TYPE=vector-store
"@
    Write-Section 'Optional Data Loader'
    if ($script:VECTOR_WRITABLE -eq 'yes') {
        Write-Info 'Data Loader ingests Spotfire docs and custom PDFs into a writable vector database.'
        $script:ENABLE_DATA_LOADER = Read-YesNo 'Deploy Data Loader?' 'yes'
        if ($script:ENABLE_DATA_LOADER -eq 'no') {
            Write-Warn 'Skipping Data Loader: populate the knowledge base through native tools or an existing ingestion process.'
        } else {
            $script:LOADER_HOST_PORT = Read-Prompt 'Data Loader host port (container port stays 8080)' '8090'
        }
 } else {
        $script:ENABLE_DATA_LOADER = 'no'
        $notice = if ([string]::IsNullOrEmpty($script:DATA_LOADER_NOTICE)) { 'selected vector DB uses native/manual ingestion or no writer plugin was configured.' } else { $script:DATA_LOADER_NOTICE }
        Write-Warn "Skipping Data Loader: $notice"
 }
}

Write-Section 'Optional Agent Registry'
Write-Info 'Agent Registry is only needed when Copilot should call custom or bundled A2A agents.'
$script:ENABLE_AGENT_REGISTRY = Read-YesNo 'Enable Agent Registry?' 'no'
$script:AGENT_CONTAINER_TAG = Get-ExistingOr 'AGENT_CONTAINER_TAG' ''
$script:AGENT_ENV_CONTENT = ''
if ($script:ENABLE_AGENT_REGISTRY -eq 'yes') {
    # ------------------------------------------------------------------
    # Agent Registry needs an Orchestrator OAuth client with the
    # agent_developer scope profile (ORCHESTRATOR_CLIENT_ID + SECRET).
    # That client can only be created against a RUNNING Orchestrator, which
    # does not exist yet during this initial generation. So the main flow
    # only ACCEPTS already-created credentials. Creating them live via the
    # Orchestrator REST API is handled by the dedicated flow:
    #   .\spotfire-copilot-deploy.ps1 -InstallAgentRegistry -Dir <backend>
    # If the credentials are not available, we defer and configure nothing
    # for Agent Registry in this run (no .env.agent-registry, no compose service).
    # ------------------------------------------------------------------
    $agentEnvFile = Join-Path $script:OUT_DIR '.env.agent-registry'
    $orchCredsReady = $false
    $script:ORCHESTRATOR_CLIENT_ID = ''
    $script:ORCHESTRATOR_CLIENT_SECRET = ''

    $exId = Get-Existing 'ORCHESTRATOR_CLIENT_ID' @($agentEnvFile)
    $exSecret = Get-Existing 'ORCHESTRATOR_CLIENT_SECRET' @($agentEnvFile)
    if (-not [string]::IsNullOrEmpty($exId) -and -not [string]::IsNullOrEmpty($exSecret) `
            -and $exId -notlike 'REPLACE_WITH_*' -and $exSecret -notlike 'REPLACE_WITH_*') {
        $useExisting = Read-YesNo 'Existing Agent Registry Orchestrator OAuth client found in .env.agent-registry. Reuse it?' 'yes'
        if ($useExisting -eq 'yes') {
            $script:ORCHESTRATOR_CLIENT_ID = $exId
            $script:ORCHESTRATOR_CLIENT_SECRET = $exSecret
            $orchCredsReady = $true
 }
 }

    if (-not $orchCredsReady) {
        Write-Warn 'Agent Registry needs its own orchestrator OAuth client with the agent_developer scope profile. Do not reuse the frontend/client OAuth credentials unless that client was explicitly created with agent_developer scopes.'
        $haveClient = Read-YesNo 'Have you already created the Orchestrator OAuth client for Agent Registry with Scope Profile agent_developer (you have its client ID and secret)?' 'no'
        if ($haveClient -eq 'yes') {
            while ($true) {
                $script:ORCHESTRATOR_CLIENT_ID = Get-StripOuterQuotes (Read-Prompt 'ORCHESTRATOR_CLIENT_ID from that agent_developer OAuth client' '')
                if (-not [string]::IsNullOrEmpty($script:ORCHESTRATOR_CLIENT_ID)) { break }
                Write-Warn 'ORCHESTRATOR_CLIENT_ID cannot be blank when you choose Yes.'
 }
            while ($true) {
                $script:ORCHESTRATOR_CLIENT_SECRET = Get-StripOuterQuotes (Read-Prompt 'ORCHESTRATOR_CLIENT_SECRET plaintext from that agent_developer OAuth client' '' -Secret)
                if (-not [string]::IsNullOrEmpty($script:ORCHESTRATOR_CLIENT_SECRET)) { break }
                Write-Warn 'ORCHESTRATOR_CLIENT_SECRET cannot be blank when you choose Yes.'
 }
            $orchCredsReady = $true
 }
 }

    if (-not $orchCredsReady) {
        # Defer: the agent_developer client cannot be minted until the Orchestrator is up.
        $script:ENABLE_AGENT_REGISTRY = 'no'
        Write-Warn 'Agent Registry was NOT configured in this run: it requires an Orchestrator agent_developer OAuth client, and the Orchestrator is not running yet during initial setup.'
        Write-Info 'Add Agent Registry after the core stack is deployed and the Orchestrator is up:'
        Write-Info "  1) cd `"$($script:OUT_DIR)`""
        Write-Info '  2) docker compose up -d          # start the Orchestrator and core services'
        Write-Info '  3) create the agent_developer OAuth client (Admin Console, or let the installer create it in the next step)'
        Write-Info "  4) re-run: .\spotfire-copilot-deploy.ps1 -InstallAgentRegistry -Dir `"$($script:OUT_DIR)`""
        Write-Info 'Nothing for Agent Registry was written to the .env files or docker-compose.yml in this run.'
 } else {
        Write-Warn 'Agent Registry image tags can vary by entitlement/release. The installer will not default to 1.1.0; enter the exact agent-container tag provided/tested for your environment.'
        $agentTagDefault = Get-ExistingOr 'AGENT_CONTAINER_TAG' ''
        while ($true) {
            $script:AGENT_CONTAINER_TAG = Read-ImageTag 'Agent container image tag (required; example: 1.1.0 or the tag confirmed by Spotfire Support)' $agentTagDefault 'copilotoci.azurecr.io/spotfirecopilot/agent-container'
            if (-not [string]::IsNullOrEmpty($script:AGENT_CONTAINER_TAG)) { break }
            Write-Warn 'Agent container image tag is required when Agent Registry is enabled. Do not leave this blank.'
 }
        $d = Get-Existing 'PORT' @($agentEnvFile); if ([string]::IsNullOrEmpty($d)) { $d = '8050' }
        $script:AGENT_PORT = Read-Prompt 'Agent Registry PORT' $d
        $d = Get-Existing 'BASE_URL' @($agentEnvFile); if ([string]::IsNullOrEmpty($d)) { $d = 'http://agent-registry:8050' }
        $script:AGENT_BASE_URL = Read-Prompt 'Agent Registry BASE_URL' $d
        $d = Get-Existing 'AUTH_CLIENT_ID' @($agentEnvFile); if ([string]::IsNullOrEmpty($d)) { $d = 'agent-registry-client' }
        $script:AUTH_CLIENT_ID = Read-Prompt 'Agent Registry AUTH_CLIENT_ID' $d

        $existingSecret = Get-Existing 'AUTH_CLIENT_SECRET' @($agentEnvFile)
        if (-not [string]::IsNullOrEmpty($existingSecret)) {
            $script:AUTH_CLIENT_SECRET = Read-Prompt 'Agent Registry AUTH_CLIENT_SECRET' $existingSecret -Secret
 } else {
            $script:AUTH_CLIENT_SECRET = Get-RandomUrlSafeToken
            Write-Ok 'Generated Agent Registry AUTH_CLIENT_SECRET. Save .env.agent-registry securely.'
 }
        $existingSign = Get-Existing 'AUTH_SIGNING_KEY' @($agentEnvFile)
        if (-not [string]::IsNullOrEmpty($existingSign)) {
            $script:AUTH_SIGNING_KEY = Read-Prompt 'Agent Registry AUTH_SIGNING_KEY' $existingSign -Secret
 } else {
            $script:AUTH_SIGNING_KEY = Get-RandomUrlSafeToken
            Write-Ok 'Generated Agent Registry AUTH_SIGNING_KEY. Save .env.agent-registry securely.'
 }

        $d = Get-Existing 'ORCHESTRATOR_URL' @($agentEnvFile); if ([string]::IsNullOrEmpty($d)) { $d = 'http://orchestrator:8080' }
        $script:ORCHESTRATOR_URL = Read-Prompt 'ORCHESTRATOR_URL for Agent Registry' $d

        $d = Get-Existing 'CUSTOM_WORKFLOWS_DIR' @($agentEnvFile); if ([string]::IsNullOrEmpty($d)) { $d = '/custom-workflows' }
        $script:CUSTOM_WORKFLOWS_DIR = Read-Prompt 'CUSTOM_WORKFLOWS_DIR inside container' $d
        $script:CONVERSATION_LOGS_DIR = '/conversation-logs'
        $script:AGENT_ENV_CONTENT = Build-AgentEnvContent
 }
} else {
    Write-Warn 'Skipping Agent Registry: Copilot will not call A2A agents, but core Orchestrator/RAG features can still work.'
}

Write-Section 'Output generation'
$script:GENERATE_COMPOSE = Read-YesNo 'Generate a docker-compose.yml file?' 'yes'

if ($script:POSTGRES_MODE -eq 'compose' -and $script:GENERATE_COMPOSE -ne 'yes') {
    $composePath = Join-Path $script:OUT_DIR 'docker-compose.yml'
    $hasPg = $false
    if (Test-Path $composePath) {
        foreach ($l in (Get-Content -LiteralPath $composePath)) { if ($l -match '^\s+orchestrator-postgres:') { $hasPg = $true; break } }
 }
    if ($hasPg) {
        Write-Warn 'POSTGRES_MODE=compose selected and existing docker-compose.yml already contains orchestrator-postgres; not regenerating compose.'
 } else {
        Write-Warn 'POSTGRES_MODE=compose requires docker-compose.yml to include the orchestrator-postgres service.'
        $script:GENERATE_COMPOSE = Read-YesNo 'Generate docker-compose.yml now to include orchestrator-postgres?' 'yes'
        if ($script:GENERATE_COMPOSE -ne 'yes') { Invoke-Die 'Cannot continue with POSTGRES_MODE=compose unless docker-compose.yml contains orchestrator-postgres.' }
 }
}

# ---- assemble env file contents ----
$embProviderOut = if ([string]::IsNullOrEmpty($script:EMBEDDING_PROVIDER)) { 'none' } else { $script:EMBEDDING_PROVIDER }
$vecProviderOut = if ([string]::IsNullOrEmpty($script:VECTOR_DB_PROVIDER)) { 'none' } else { $script:VECTOR_DB_PROVIDER }
$corsAdminPort = if (-not [string]::IsNullOrEmpty($script:ADMIN_HOST_PORT)) { $script:ADMIN_HOST_PORT } else { '8081' }

$BASE_ENV_CONTENT = @"
# ------------------------------
# Spotfire Copilot image versions
# ------------------------------
IMAGE_TAG=$($script:IMAGE_TAG)
FASTAPI_APP_VERSION=$($script:FASTAPI_APP_VERSION)
AGENT_CONTAINER_TAG=$($script:AGENT_CONTAINER_TAG)

# ------------------------------
# Docker Compose runtime
# ------------------------------
COMPOSE_PROJECT_NAME=$($script:COMPOSE_PROJECT_NAME)
LOG_LEVEL=$($script:LOG_LEVEL)
ACCESS_TOKEN_EXPIRE_DAYS=$($script:ACCESS_TOKEN_EXPIRE_DAYS)

# ------------------------------
# Installer selections
# These are informational and help with later review/upgrade
# ------------------------------
LLM_PROVIDER=$($script:LLM_PROVIDER)
POSTGRES_MODE=$($script:POSTGRES_MODE)
ENABLE_ADMIN_CONSOLE=$($script:ENABLE_ADMIN_CONSOLE)
ENABLE_RAG=$($script:ENABLE_RAG)
EMBEDDING_PROVIDER=$embProviderOut
VECTOR_DB_PROVIDER=$vecProviderOut
ENABLE_DATA_LOADER=$($script:ENABLE_DATA_LOADER)
ENABLE_AGENT_REGISTRY=$($script:ENABLE_AGENT_REGISTRY)
"@

$hashedAdminQuoted = ConvertTo-SingleQuotedEnvValue $script:HASHED_ADMIN_PASSWORD
$oauthSecretHashQuoted = ConvertTo-SingleQuotedEnvValue $script:OAUTH2_CLIENT_SECRET_HASH

$ORCH_ENV_CONTENT = @"
# ------------------------------
# Core authentication
# Generated values must come from generate_credentials.py
# ------------------------------
SECRET_KEY=$($script:SECRET_KEY)
HASHED_ADMIN_PASSWORD=$hashedAdminQuoted

# ------------------------------
# OAuth2 client credentials for Spotfire Copilot
# Spotfire Administration Manager uses the plaintext client secret
# ------------------------------
OAUTH2_CLIENT_ID=$($script:OAUTH2_CLIENT_ID)
OAUTH2_CLIENT_SECRET_HASH=$oauthSecretHashQuoted

# ------------------------------
# PostgreSQL
# Orchestrator and optional Admin Console use this database
# ------------------------------
POSTGRES_MODE=$($script:POSTGRES_MODE)
POSTGRES_HOST=$($script:POSTGRES_HOST)
POSTGRES_PORT=$($script:POSTGRES_PORT)
POSTGRES_DB=$($script:POSTGRES_DB)
POSTGRES_USER=$($script:POSTGRES_USER)
POSTGRES_PASSWORD=$($script:POSTGRES_PASSWORD)
DATABASE_URL=$($script:DATABASE_URL)
SYNC_DATABASE_URL=$($script:SYNC_DATABASE_URL)
DB_SSLMODE=$($script:DB_SSLMODE)

# ------------------------------
# Application URLs
# ------------------------------
ORCHESTRATOR_INTERNAL_URL=http://orchestrator:8080
CORS_ALLOWED_ORIGINS=http://localhost:$($corsAdminPort),http://localhost:3000

# ------------------------------
# LLM provider
# ------------------------------
$($script:MODEL_BLOCK_ORCH)

# ------------------------------
# Embeddings
# Used for RAG document/query vectorization
# ------------------------------
$($script:EMBED_BLOCK_ORCH)

# ------------------------------
# Vector DB / Knowledge Base
# Orchestrator uses RETRIEVER_PLUGIN_ENTRY_POINT
# ------------------------------
$($script:VECTOR_BLOCK_ORCH)

# ------------------------------
# RAG defaults
# ------------------------------
$($script:RAG_DEFAULTS_BLOCK)

# ------------------------------
# Optional LangSmith tracing - uncomment only when LangSmith tracing is required
# ------------------------------
# LANGCHAIN_TRACING_V2=true
# LANGCHAIN_ENDPOINT=https://api.smith.langchain.com
# LANGCHAIN_API_KEY=<langsmith-api-key>
# LANGCHAIN_PROJECT=orchestrator-$($script:IMAGE_TAG)
"@

$DL_ENV_CONTENT = @"
# ------------------------------
# Data Loader authentication
# Must match Orchestrator SECRET_KEY and admin hash
# ------------------------------
SECRET_KEY=$($script:SECRET_KEY)
HASHED_ADMIN_PASSWORD=$hashedAdminQuoted

# ------------------------------
# Core
# ------------------------------
LOG_LEVEL=$($script:LOG_LEVEL)
ACCESS_TOKEN_EXPIRE_DAYS=$($script:ACCESS_TOKEN_EXPIRE_DAYS)

# ------------------------------
# LLM provider
# ------------------------------
$($script:MODEL_BLOCK_DL)

# ------------------------------
# Embeddings
# Data Loader uses this to create vectors
# ------------------------------
$($script:EMBED_BLOCK_DL)

# ------------------------------
# Vector DB / Knowledge Base
# Data Loader uses VECTORDB_PLUGIN_ENTRY_POINT
# ------------------------------
$($script:VECTOR_BLOCK_DL)

# ------------------------------
# Local PDF document folder
# Host folder mounted to /docs inside the container
# ------------------------------
DOCS_DIR=/root/spotfire-copilot/pdf_docs_folder
"@

$BASE_ENV_CONTENT = Compress-EnvContent $BASE_ENV_CONTENT
$ORCH_ENV_CONTENT = Compress-EnvContent $ORCH_ENV_CONTENT
$DL_ENV_CONTENT = Compress-EnvContent $DL_ENV_CONTENT
if (-not [string]::IsNullOrEmpty($script:AGENT_ENV_CONTENT)) {
    $script:AGENT_ENV_CONTENT = Compress-EnvContent $script:AGENT_ENV_CONTENT
}

Write-EnvFile (Join-Path $script:OUT_DIR '.env') $BASE_ENV_CONTENT
Write-EnvFile (Join-Path $script:OUT_DIR '.env.orchestrator') $ORCH_ENV_CONTENT
if ($script:ENABLE_DATA_LOADER -eq 'yes') {
    Write-EnvFile (Join-Path $script:OUT_DIR '.env.dataloader') $DL_ENV_CONTENT
} else {
    Write-Info 'Data Loader disabled; .env.dataloader was not written.'
}
if ($script:ENABLE_AGENT_REGISTRY -eq 'yes') {
    Write-EnvFile (Join-Path $script:OUT_DIR '.env.agent-registry') $script:AGENT_ENV_CONTENT
}

# ---- docker-compose.yml generation ----
if ($script:GENERATE_COMPOSE -eq 'yes') {

    # Build docker-compose.yml as an array of single-quoted lines whose indentation
    # lives INSIDE the quotes. PowerShell ignores source indentation and interior
    # string spaces survive whitespace-collapse, so this stays valid YAML even if this
    # script file's leading indentation is mangled in transit.
    # ${IMAGE_TAG} / ${AGENT_CONTAINER_TAG} / $${POSTGRES_*} are kept LITERAL (single
    # quotes) so Docker Compose resolves them at runtime.
    $composeLines = New-Object System.Collections.Generic.List[string]
    $composeLines.Add('services:')

    if ($script:POSTGRES_MODE -eq 'compose') {
        @(
            '  orchestrator-postgres:'
            '    image: public.ecr.aws/docker/library/postgres:15-alpine'
            '    container_name: orchestrator-postgres-${IMAGE_TAG}'
            '    restart: unless-stopped'
            '    ports:'
            ('      - "127.0.0.1:{0}:5432"' -f $script:POSTGRES_HOST_PORT)
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
 ) | ForEach-Object { $composeLines.Add($_) }
 }

    @(
        '  orchestrator:'
        '    image: copilotoci.azurecr.io/spotfirecopilot/llm-orchestrator:${IMAGE_TAG}'
        '    container_name: orchestrator-${IMAGE_TAG}'
        '    restart: unless-stopped'
 ) | ForEach-Object { $composeLines.Add($_) }
    if ($script:POSTGRES_MODE -eq 'compose') {
        @(
            '    depends_on:'
            '      orchestrator-postgres:'
            '        condition: service_healthy'
 ) | ForEach-Object { $composeLines.Add($_) }
 }
    @(
        '    ports:'
        ('      - "{0}:8080"' -f $script:ORCH_HOST_PORT)
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
 ) | ForEach-Object { $composeLines.Add($_) }

    if ($script:ENABLE_ADMIN_CONSOLE -eq 'yes') {
        @(
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
            ('      - "{0}:8081"' -f $script:ADMIN_HOST_PORT)
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
 ) | ForEach-Object { $composeLines.Add($_) }
 }

    if ($script:ENABLE_DATA_LOADER -eq 'yes') {
        @(
            ''
            '  data-loader:'
            '    image: copilotoci.azurecr.io/spotfirecopilot/data-loader-pdf-pypdf:${IMAGE_TAG}'
            '    container_name: data-loader-${IMAGE_TAG}'
            '    restart: unless-stopped'
            '    ports:'
            ('      - "{0}:8080"' -f $script:LOADER_HOST_PORT)
            '    env_file:'
            '      - .env'
            '      - .env.dataloader'
            '    extra_hosts:'
            '      - "host.docker.internal:host-gateway"'
            '    volumes:'
            '      - /root/spotfire-copilot/pdf_docs_folder:/docs'
 ) | ForEach-Object { $composeLines.Add($_) }
 }

    if ($script:ENABLE_AGENT_REGISTRY -eq 'yes') {
        $composeLines.Add('')
 (Get-AgentRegistryServiceLines) | ForEach-Object { $composeLines.Add($_) }
 }

    @(
        ''
        'volumes:'
        '  postgres_data:'
        '    driver: local'
        '    name: ${COMPOSE_PROJECT_NAME:-spotfire-copilot}_postgres_data'
 ) | ForEach-Object { $composeLines.Add($_) }

    $composeContent = ($composeLines -join "`n") + "`n"
    Write-EnvFile (Join-Path $script:OUT_DIR 'docker-compose.yml') $composeContent

    if ($script:POSTGRES_MODE -eq 'compose') {
        $composePath = Join-Path $script:OUT_DIR 'docker-compose.yml'
        $found = $false
        foreach ($l in (Get-Content -LiteralPath $composePath)) { if ($l -match '^\s+orchestrator-postgres:') { $found = $true; break } }
        if (-not $found) { Invoke-Die 'Generated docker-compose.yml is missing orchestrator-postgres even though POSTGRES_MODE=compose.' }
        Write-Ok 'Verified docker-compose.yml contains orchestrator-postgres service.'
 }
}

# ---- optional local PostgreSQL reset ----
if ($script:POSTGRES_RESET_LOCAL_VOLUME_SELECTED -eq 'yes') {
    Write-Section 'Local PostgreSQL reset'
    Write-Warn 'You selected a fresh lab/test reset. This stops the Docker Compose stack and deletes ONLY the local PostgreSQL volume. Do this only when Copilot backend data can be discarded.'
    $runReset = Read-YesNo 'Run the targeted local PostgreSQL volume reset now?' 'yes'
    if ($runReset -eq 'yes') {
        $deleteConfirm = Read-Prompt 'Type DELETE to remove the local PostgreSQL volume now' ''
        if ($deleteConfirm -eq 'DELETE') {
            & (Join-Path $script:OUT_DIR 'reset-local-postgres-volume.ps1')
            Write-Ok 'Local Docker Compose PostgreSQL volume reset completed. Next docker compose up will initialize PostgreSQL with the password now in .env.orchestrator.'
 } else {
            Write-Warn "Reset skipped. You must run $($script:OUT_DIR)\reset-local-postgres-volume.ps1 before starting/restarting, otherwise the stale database password will remain."
 }
 } else {
        Write-Warn "Reset skipped. You must run $($script:OUT_DIR)\reset-local-postgres-volume.ps1 before starting/restarting, otherwise the stale database password will remain."
 }
}

Invoke-DeepAgentsIfRequested

Test-ComposeIfPossible
Save-LastOutDir

Write-Section 'Generated files'
foreach ($f in @((Join-Path $script:OUT_DIR '.env'), (Join-Path $script:OUT_DIR '.env.orchestrator'))) {
    if (Test-Path $f) { Get-Item $f | ForEach-Object { Write-Host ("  {0,10}  {1}" -f $_.Length, $_.FullName) } }
}
if ($script:ENABLE_DATA_LOADER -eq 'yes') { $f = Join-Path $script:OUT_DIR '.env.dataloader'; if (Test-Path $f) { Get-Item $f | ForEach-Object { Write-Host ("  {0,10}  {1}" -f $_.Length, $_.FullName) } } }
if ($script:ENABLE_AGENT_REGISTRY -eq 'yes') { $f = Join-Path $script:OUT_DIR '.env.agent-registry'; if (Test-Path $f) { Get-Item $f | ForEach-Object { Write-Host ("  {0,10}  {1}" -f $_.Length, $_.FullName) } } }
if ($script:GENERATE_COMPOSE -eq 'yes') { $f = Join-Path $script:OUT_DIR 'docker-compose.yml'; if (Test-Path $f) { Get-Item $f | ForEach-Object { Write-Host ("  {0,10}  {1}" -f $_.Length, $_.FullName) } } }

Write-Host ''
Write-Ok 'Generation complete.'
Write-Host "LLM provider: $($script:LLM_PROVIDER)"
Write-Host "PostgreSQL mode: $($script:POSTGRES_MODE)"
Write-Host "Admin Console: $($script:ENABLE_ADMIN_CONSOLE)"
Write-Host "RAG: $($script:ENABLE_RAG)"
Write-Host "Vector DB: $vecProviderOut"
Write-Host "Embedding provider: $embProviderOut"
Write-Host "Data Loader: $($script:ENABLE_DATA_LOADER)"
Write-Host "Agent Registry: $($script:ENABLE_AGENT_REGISTRY)"
Write-Host ''
Write-Info 'Next checks:'
Write-Host '  Change to your working directory'
Write-Host '  docker compose config > rendered-compose.yml'
Write-Host '  docker compose up -d --no-build'