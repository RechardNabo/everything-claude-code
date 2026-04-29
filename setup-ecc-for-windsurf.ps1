#Requires -Version 5.1
param(
    [string]$EccRepoPath = "",
    [string]$UserHome = $env:USERPROFILE,
    [switch]$SkipMcp,
    [switch]$SkipRules
)
$ErrorActionPreference = "Stop"

function Find-EccRepo {
    param([string]$ExplicitPath)
    if ($ExplicitPath -and (Test-Path "$ExplicitPath\.windsurfrules")) {
        return (Resolve-Path $ExplicitPath).Path
    }
    $candidates = @(
        "$env:USERPROFILE\Desktop\everything-claude-code"
        "$env:USERPROFILE\Desktop\ESP32\everything-claude-code"
        "$env:USERPROFILE\Downloads\everything-claude-code"
        "$env:USERPROFILE\source\repos\everything-claude-code"
        "$env:USERPROFILE\everything-claude-code"
        "$PSScriptRoot"
    )
    foreach ($c in $candidates) {
        if (Test-Path "$c\.windsurfrules") { return (Resolve-Path $c).Path }
    }
    return $null
}

$Repo = Find-EccRepo -ExplicitPath $EccRepoPath
if (-not $Repo) {
    Write-Host "ECC repo not found. Cloning from GitHub..." -ForegroundColor Yellow
    $cloneTarget = "$env:USERPROFILE\everything-claude-code"
    if (Test-Path $cloneTarget) { Remove-Item -Recurse -Force $cloneTarget }
    git clone https://github.com/lec-ai/everything-claude-code.git $cloneTarget 2>$null
    if ($LASTEXITCODE -ne 0) {
        git clone https://github.com/docuvera/everything-claude-code.git $cloneTarget 2>$null
    }
    $Repo = Find-EccRepo -ExplicitPath $cloneTarget
    if (-not $Repo) {
        Write-Error "Could not locate or clone ECC repo."
        exit 1
    }
}
Write-Host "Using ECC repo: $Repo" -ForegroundColor Cyan

$windHome       = "$UserHome\.codeium\windsurf"
$windsurfDir    = "$windHome\windsurf"
$workflowsDir   = "$windsurfDir\workflows"
$hooksRefDir    = "$windsurfDir\hooks-reference"
$globalRules    = "$UserHome\.windsurfrules"
$toggleRulesDir = "$UserHome\.windsurf\rules"
$mcpConfig      = "$windHome\mcp_config.json"

@($windsurfDir, $workflowsDir, $hooksRefDir, $toggleRulesDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

# --- Global rules ---
$srcGlobal = "$Repo\.windsurfrules"
if (Test-Path $srcGlobal) {
    Copy-Item -Path $srcGlobal -Destination $globalRules -Force
    Write-Host "Copied global rules -> $globalRules" -ForegroundColor Green
}

# --- Workflows ---
$wfMap = @{
    "code-review.md"      = "$Repo\agents\code-reviewer.md"
    "security-review.md"  = "$Repo\agents\security-reviewer.md"
    "tdd-guide.md"       = "$Repo\agents\tdd-guide.md"
    "planner.md"          = "$Repo\agents\planner.md"
    "build-fix.md"        = "$Repo\agents\build-error-resolver.md"
    "performance.md"      = "$Repo\agents\performance-optimizer.md"
    "silent-failures.md"  = "$Repo\agents\silent-failure-hunter.md"
    "refactor.md"         = "$Repo\agents\refactor-cleaner.md"
    "docs.md"             = "$Repo\agents\doc-updater.md"
    "test-coverage.md"    = "$Repo\commands\test-coverage.md"
    "feature-dev.md"      = "$Repo\commands\feature-dev.md"
    "quality-gate.md"     = "$Repo\commands\quality-gate.md"
}

function ConvertToWf {
    param([string]$SourcePath, [string]$TargetPath)
    if (-not (Test-Path $SourcePath)) { return $false }
    $content = Get-Content -Raw $SourcePath
    $desc = "ECC workflow"
    if ($content -match 'description:\s*(.+)') { $desc = $matches[1].Trim() }
    elseif ($content -match '^#\s+(.+)$') { $desc = $matches[1].Trim() }
    $yaml = "---`nauto_execution_mode: 0`ndescription: $desc`n---`n`n"
    $cleaned = $content -replace '^---\s*\r?\n[\s\S]*?\r?\n---\s*\r?\n', ''
    $cleaned = $cleaned -replace '^tools:\s*\[.*?\]\r?\n?', ''
    $cleaned = $cleaned -replace '^model:\s*.+\r?\n?', ''
    $cleaned = $cleaned -replace '^name:\s*.+\r?\n?', ''
    Set-Content -Path $TargetPath -Value ($yaml + $cleaned.Trim()) -Encoding UTF8 -NoNewline
    return $true
}

foreach ($kv in $wfMap.GetEnumerator()) {
    $target = Join-Path $workflowsDir $kv.Key
    if (ConvertToWf -SourcePath $kv.Value -TargetPath $target) {
        Write-Host "Created workflow: $($kv.Key)" -ForegroundColor Green
    } else {
        Write-Warning "Missing source for $($kv.Key)"
    }
}

# --- Toggleable Rules ---
if (-not $SkipRules) {
    $srcRulesDir = "$Repo\rules\common"
    if (Test-Path $srcRulesDir) {
        Get-ChildItem "$srcRulesDir\*.md" | ForEach-Object {
            $destName = "ecc_$($_.Name)"
            Copy-Item $_.FullName "$toggleRulesDir\$destName" -Force
            Write-Host "Copied rule -> $destName" -ForegroundColor Green
        }
    }
    $repoWfRules = "$Repo\.windsurf\rules\common"
    if (Test-Path $repoWfRules) {
        Get-ChildItem "$repoWfRules\*.md" | ForEach-Object {
            $destName = "ecc_$($_.Name)"
            Copy-Item $_.FullName "$toggleRulesDir\$destName" -Force
            Write-Host "Copied .windsurf rule -> $destName" -ForegroundColor Green
        }
    }
}

# --- MCP Config ---
if (-not $SkipMcp) {
    $mcpJson = @'
{
  "mcpServers": {
    "jira": {
      "command": "uvx",
      "args": ["mcp-atlassian==0.21.0"],
      "env": {
        "JIRA_URL": "YOUR_JIRA_URL_HERE",
        "JIRA_EMAIL": "YOUR_JIRA_EMAIL_HERE",
        "JIRA_API_TOKEN": "YOUR_JIRA_API_TOKEN_HERE"
      }
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "YOUR_GITHUB_PAT_HERE"
      }
    },
    "firecrawl": {
      "command": "npx",
      "args": ["-y", "firecrawl-mcp"],
      "env": {
        "FIRECRAWL_API_KEY": "YOUR_FIRECRAWL_KEY_HERE"
      }
    },
    "supabase": {
      "command": "npx",
      "args": ["-y", "@supabase/mcp-server-supabase@latest", "--project-ref=YOUR_PROJECT_REF"]
    },
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"]
    },
    "omega-memory": {
      "command": "uvx",
      "args": ["omega-memory", "serve"]
    },
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "railway": {
      "command": "npx",
      "args": ["-y", "@railway/mcp-server"]
    },
    "exa-web-search": {
      "command": "npx",
      "args": ["-y", "exa-mcp-server"],
      "env": {
        "EXA_API_KEY": "YOUR_EXA_API_KEY_HERE"
      }
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    },
    "magic": {
      "command": "npx",
      "args": ["-y", "@magicuidesign/mcp@latest"]
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "C:/Users/$env:USERNAME"]
    },
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp", "--browser", "chrome"]
    },
    "fal-ai": {
      "command": "npx",
      "args": ["-y", "fal-ai-mcp-server"],
      "env": {
        "FAL_KEY": "YOUR_FAL_KEY_HERE"
      }
    },
    "browserbase": {
      "command": "npx",
      "args": ["-y", "@browserbasehq/mcp-server-browserbase"],
      "env": {
        "BROWSERBASE_API_KEY": "YOUR_BROWSERBASE_KEY_HERE"
      }
    },
    "token-optimizer": {
      "command": "npx",
      "args": ["-y", "token-optimizer-mcp"]
    },
    "confluence": {
      "command": "npx",
      "args": ["-y", "confluence-mcp-server"],
      "env": {
        "CONFLUENCE_BASE_URL": "YOUR_CONFLUENCE_URL_HERE",
        "CONFLUENCE_EMAIL": "YOUR_EMAIL_HERE",
        "CONFLUENCE_API_TOKEN": "YOUR_CONFLUENCE_TOKEN_HERE"
      }
    },
    "evalview": {
      "command": "python3",
      "args": ["-m", "evalview", "mcp", "serve"],
      "env": {
        "OPENAI_API_KEY": "YOUR_OPENAI_API_KEY_HERE"
      }
    }
  }
}
'@
    Set-Content -Path $mcpConfig -Value $mcpJson -Encoding UTF8
    Write-Host "Wrote MCP config -> $mcpConfig" -ForegroundColor Green
}

Write-Host "`n=== Setup Complete ===" -ForegroundColor Cyan
Write-Host "Global rules: $globalRules"
Write-Host "Workflows: $workflowsDir ($((Get-ChildItem $workflowsDir).Count) files)"
if (-not $SkipRules) { Write-Host "Toggleable rules: $toggleRulesDir" }
if (-not $SkipMcp) { Write-Host "MCP config: $mcpConfig" }
Write-Host "`nReplace YOUR_*_HERE placeholders in $mcpConfig with your actual credentials." -ForegroundColor Yellow
