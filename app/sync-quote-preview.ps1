#Requires -Version 5.1
<#
.SYNOPSIS
  Yijiang Business Suite - Local build script.
.DESCRIPTION
  Concatenates the scattered source files under app/ into framework-preview.js
  and framework-preview.css, then syncs them to share-preview-site/dist for
  local preview or Netlify deployment.

  IMPORTANT:
  - framework-preview.js / framework-preview.css are GENERATED files. Do NOT
    edit them by hand.
  - To change functionality, edit the .inc.js / .logic.js / .css source files
    listed at the top of this script, then re-run it.
  - Make sure the marker comments inside app/framework-preview.js remain intact.
.NOTES
  Run: powershell -NoProfile -ExecutionPolicy Bypass -File .\sync-quote-preview.ps1
  Or:  npm run build
#>
$ErrorActionPreference = 'Stop'

# Project paths
$appRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $appRoot
$distDir = Join-Path $projectRoot 'share-preview-site\dist'

$frameworkJsPath = Join-Path $appRoot 'framework-preview.js'
$frameworkCssPath = Join-Path $appRoot 'framework-preview.css'
$frameworkHtmlPath = Join-Path $appRoot 'framework-preview.html'

# ============================================================
# Source file lists (grouped by domain)
# ============================================================

# JS sources concatenated into framework-preview.js in this order
$jsSources = @(
    # Shared logic
    'cloud-draft.logic.js'
    # Renovation / whole-house business
    'quote-workshop.inc.js'
    'custom-quote-workshop.inc.js'
    'renovation-workflow.inc.js'
    'reno-cloud-owner.inc.js'
    'reno-cloud-staff.inc.js'
    # Factory business
    'factory-operations.inc.js'
    'factory-refinements.inc.js'
    'factory-efficiency.inc.js'
    'factory-document-versions.inc.js'
    'factory-cloud.inc.js'
    # Custom cabinetry business
    'custom-quote-refinements.inc.js'
    'custom-catalog-bom.logic.js'
    'custom-catalog-bom.inc.js'
    'custom-procurement.inc.js'
    'custom-cloud-drafts.inc.js'
    # Shared UX / utilities
    'requested-refinements.inc.js'
    'screenshot-navigation.inc.js'
    'practical-usability.inc.js'
    'bill-workbench.inc.js'
    'role-gates.inc.js'
    'workflow-restoration.logic.js'
    'business-accounts.inc.js'
)

# CSS sources concatenated into framework-preview.css in this order
$cssSources = @(
    'quote-workshop.css'
    'custom-quote-workshop.css'
    'custom-quote-refinements.css'
    'factory-operations.css'
    'factory-efficiency.css'
    'requested-refinements.css'
    'practical-usability.css'
    'renovation-workflow.css'
    'reno-cloud-owner.css'
    'reno-cloud-staff.css'
    'custom-catalog-bom.css'
    'custom-procurement.css'
    'auth-gate.css'
    'factory-cloud.css'
    'mobile-experience.css'
    'acceptance-repair.css'
    'account-admin.css'
)

# ============================================================
# Helper functions
# ============================================================

function Get-NodePath {
    $node = Get-Command 'node' -ErrorAction SilentlyContinue
    if ($node) { return $node.Source }

    $candidates = @(
        (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe')
        (Join-Path $env:USERPROFILE '.workbuddy\binaries\node\versions\22.22.2-6\node.exe')
        'C:\Program Files\nodejs\node.exe'
        'C:\ProgramData\chocolatey\bin\node.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'node.exe not found. Install Node.js (>=18) or ensure node is in PATH.'
}

function Read-SourceFile ($relativePath) {
    $fullPath = Join-Path $appRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Source file missing: $relativePath"
    }
    return Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
}

function Write-TextFile ($path, $content) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))
}

function Copy-StaticAsset ($sourceRelative, $destName) {
    $source = Join-Path $appRoot $sourceRelative
    $dest = Join-Path $distDir $destName
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $dest -Recurse -Force
        Write-Host "  [OK] $sourceRelative -> $destName"
    } else {
        Write-Warning "  [MISS] $sourceRelative not found, skipped"
    }
}

# ============================================================
# 1. Concatenate framework-preview.js
# ============================================================
Write-Host "`n[1/5] Concatenating framework-preview.js ..."

$frameworkJs = Read-SourceFile 'framework-preview.js'
$markerStart = '  // Included inside the preview'
$markerEnd = '  // Give owners explicit split views'
$startIndex = $frameworkJs.IndexOf($markerStart)
$endIndex = $frameworkJs.IndexOf($markerEnd, $startIndex)

if ($startIndex -lt 0 -or $endIndex -lt $startIndex) {
    throw "Concatenation markers missing in framework-preview.js.`nExpected: $markerStart and $markerEnd.`nDo not edit framework-preview.js by hand; restore it from Git."
}

$includedJs = ($jsSources | ForEach-Object {
    Write-Host "  [INC] $_"
    Read-SourceFile $_
}) -join "`r`n"

$mergedJs = $frameworkJs.Substring(0, $startIndex) + $includedJs + "`r`n" + $frameworkJs.Substring($endIndex)
Write-TextFile $frameworkJsPath $mergedJs
Write-Host "  [OK] Written framework-preview.js ($([math]::Round((Get-Item $frameworkJsPath).Length / 1KB, 1)) KB)"

# ============================================================
# 2. JS syntax check
# ============================================================
Write-Host "`n[2/5] JavaScript syntax check ..."
$nodePath = Get-NodePath
Write-Host "  [NODE] $nodePath"
& $nodePath --check $frameworkJsPath
if ($LASTEXITCODE -ne 0) {
    throw 'JavaScript syntax check failed. Check recently modified .inc.js / .logic.js source files.'
}
Write-Host "  [OK] Syntax check passed"

# ============================================================
# 3. Concatenate framework-preview.css
# ============================================================
Write-Host "`n[3/5] Concatenating framework-preview.css ..."

$frameworkCss = Read-SourceFile 'framework-preview.css'
$cssMarker = '/* Room-based quotation workspace. */'
$cssStartIndex = $frameworkCss.IndexOf($cssMarker)
if ($cssStartIndex -lt 0) {
    throw "Concatenation marker missing in framework-preview.css: $cssMarker"
}

$includedCss = ($cssSources | ForEach-Object {
    Write-Host "  [INC] $_"
    Read-SourceFile $_
}) -join "`r`n"

$mergedCss = $frameworkCss.Substring(0, $cssStartIndex) + $includedCss
Write-TextFile $frameworkCssPath $mergedCss
Write-Host "  [OK] Written framework-preview.css ($([math]::Round((Get-Item $frameworkCssPath).Length / 1KB, 1)) KB)"

# ============================================================
# 4. Sync static assets to publish directory
# ============================================================
Write-Host "`n[4/5] Syncing static assets to $distDir ..."

New-Item -ItemType Directory -Path $distDir -Force | Out-Null

Copy-Item -LiteralPath $frameworkJsPath -Destination (Join-Path $distDir 'framework-preview.js') -Force
Copy-Item -LiteralPath $frameworkCssPath -Destination (Join-Path $distDir 'framework-preview.css') -Force
Copy-StaticAsset 'auth-gate.js' 'auth-gate.js'
Copy-StaticAsset 'account-admin.js' 'account-admin.js'
Copy-StaticAsset 'vendor' 'vendor'
Copy-StaticAsset 'assets\brand' 'assets\brand'

$catalogSource = Join-Path $projectRoot 'supabase\seed\custom-catalog-demo.json'
$catalogDest = Join-Path $distDir 'custom-catalog-demo.json'
if (Test-Path -LiteralPath $catalogSource) {
    Copy-Item -LiteralPath $catalogSource -Destination $catalogDest -Force
    Write-Host "  [OK] supabase\seed\custom-catalog-demo.json -> custom-catalog-demo.json"
} elseif (-not (Test-Path -LiteralPath $catalogDest)) {
    throw 'Custom catalog asset missing from both source and publish directories.'
} else {
    Write-Host "  [OK] Kept existing custom-catalog-demo.json in publish directory"
}

Copy-Item -LiteralPath $frameworkHtmlPath -Destination (Join-Path $distDir 'index.html') -Force
$revision = Get-Date -Format 'yyyyMMddHHmmss'
$distHtmlPath = Join-Path $distDir 'index.html'
$distHtml = (Get-Content -LiteralPath $distHtmlPath -Raw -Encoding UTF8).Replace('__ASSET_VERSION__', $revision)
Write-TextFile $distHtmlPath $distHtml

foreach ($file in @('auth-gate.js', 'account-admin.js', 'framework-preview.js')) {
    $filePath = Join-Path $distDir $file
    if (Test-Path -LiteralPath $filePath) {
        $content = (Get-Content -LiteralPath $filePath -Raw -Encoding UTF8).Replace('__ASSET_VERSION__', $revision)
        Write-TextFile $filePath $content
    }
}
Write-Host "  [OK] Asset revision: $revision"

# ============================================================
# 5. Done
# ============================================================
Write-Host "`n[5/5] Build complete.`n"
Write-Host "  Local preview: .\start-local-preview.ps1  or  npm run preview"
Write-Host "  Publish dir:   $distDir"
Write-Host "  Reminder: re-run this script after editing source files.`n"
