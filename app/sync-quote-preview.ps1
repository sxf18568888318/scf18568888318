$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskJsPath = Join-Path $PSScriptRoot 'framework-preview.js'
$taskCssPath = Join-Path $PSScriptRoot 'framework-preview.css'
$taskJs = Get-Content -LiteralPath $taskJsPath -Raw -Encoding UTF8
$taskStart = $taskJs.IndexOf('  // Included inside the preview')
$taskEnd = $taskJs.IndexOf('  // Give owners explicit split views', $taskStart)
if ($taskStart -lt 0 -or $taskEnd -lt $taskStart) { throw 'Quotation source markers missing' }
$taskInclude = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cloud-draft.logic.js') -Raw -Encoding UTF8
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'quote-workshop.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom-quote-workshop.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'factory-operations.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'factory-refinements.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'factory-efficiency.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'factory-document-versions.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'requested-refinements.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'screenshot-navigation.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'practical-usability.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bill-workbench.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'renovation-workflow.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom-quote-refinements.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'reno-cloud-owner.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'reno-cloud-staff.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom-catalog-bom.logic.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom-catalog-bom.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom-procurement.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'role-gates.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'workflow-restoration.logic.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'factory-cloud.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom-cloud-drafts.inc.js') -Raw -Encoding UTF8)
$taskInclude += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'business-accounts.inc.js') -Raw -Encoding UTF8)
$taskJs = $taskJs.Substring(0, $taskStart) + $taskInclude + "`r`n" + $taskJs.Substring($taskEnd)
[IO.File]::WriteAllText($taskJsPath, $taskJs, [Text.UTF8Encoding]::new($false))
$taskNode = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
& $taskNode --check $taskJsPath
if ($LASTEXITCODE -ne 0) { throw 'JavaScript syntax check failed' }
$taskCss = Get-Content -LiteralPath $taskCssPath -Raw -Encoding UTF8
$taskCssStart = $taskCss.IndexOf('/* Room-based quotation workspace. */')
if ($taskCssStart -lt 0) { throw 'Quotation stylesheet marker missing' }
$taskCss = $taskCss.Substring(0, $taskCssStart) + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'quote-workshop.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom-quote-workshop.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom-quote-refinements.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'factory-operations.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'factory-efficiency.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'requested-refinements.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'practical-usability.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'renovation-workflow.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'reno-cloud-owner.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'reno-cloud-staff.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom-catalog-bom.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom-procurement.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'auth-gate.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'factory-cloud.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mobile-experience.css') -Raw -Encoding UTF8)
$taskCss += "`r`n" + (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'acceptance-repair.css') -Raw -Encoding UTF8)
[IO.File]::WriteAllText($taskCssPath, $taskCss, [Text.UTF8Encoding]::new($false))
$taskDist = Join-Path $taskRoot 'share-preview-site\dist'
Copy-Item -LiteralPath $taskJsPath -Destination (Join-Path $taskDist 'framework-preview.js')
Copy-Item -LiteralPath $taskCssPath -Destination (Join-Path $taskDist 'framework-preview.css')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'auth-gate.js') -Destination (Join-Path $taskDist 'auth-gate.js')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'vendor') -Destination $taskDist -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\supabase\seed\custom-catalog-demo.json') -Destination (Join-Path $taskDist 'custom-catalog-demo.json')
$taskBrandDist = Join-Path $taskDist 'assets\brand'
New-Item -ItemType Directory -Path $taskBrandDist -Force | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'assets\brand\*') -Destination $taskBrandDist -Recurse -Force
$taskHtmlPath = Join-Path $taskDist 'index.html'
$taskHtmlSource = Join-Path $PSScriptRoot 'framework-preview.html'
Copy-Item -LiteralPath $taskHtmlSource -Destination $taskHtmlPath -Force
$taskHtml = Get-Content -LiteralPath $taskHtmlPath -Raw -Encoding UTF8
$taskRevision = Get-Date -Format 'yyyyMMddHHmmss'
$taskHtml = $taskHtml.Replace('__ASSET_VERSION__', $taskRevision)
[IO.File]::WriteAllText($taskHtmlPath, $taskHtml, [Text.UTF8Encoding]::new($false))
$taskAuthJsPath = Join-Path $taskDist 'auth-gate.js'
$taskAuthJs = (Get-Content -LiteralPath $taskAuthJsPath -Raw -Encoding UTF8).Replace('__ASSET_VERSION__', $taskRevision)
[IO.File]::WriteAllText($taskAuthJsPath, $taskAuthJs, [Text.UTF8Encoding]::new($false))
$taskDistJsPath = Join-Path $taskDist 'framework-preview.js'
$taskDistJs = (Get-Content -LiteralPath $taskDistJsPath -Raw -Encoding UTF8).Replace('__ASSET_VERSION__', $taskRevision)
[IO.File]::WriteAllText($taskDistJsPath, $taskDistJs, [Text.UTF8Encoding]::new($false))
Write-Output 'Local quotation preview synchronized. Refresh localhost to see edits.'


