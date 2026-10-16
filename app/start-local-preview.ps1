$ErrorActionPreference = 'Stop'
$previewRoot = Split-Path -Parent $PSScriptRoot
$previewPort = 8765
$previewUrl = "http://127.0.0.1:$previewPort/index.html?preview=factory"
$previewPython = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
if (-not (Test-Path -LiteralPath $previewPython)) { throw 'Bundled Python runtime not found.' }
$previewListening = Get-NetTCPConnection -LocalPort $previewPort -State Listen -ErrorAction SilentlyContinue
if (-not $previewListening) {
  $previewDist = Join-Path $previewRoot 'share-preview-site\dist'
  $previewLogs = Join-Path $previewRoot 'outputs\local-preview'
  New-Item -ItemType Directory -Path $previewLogs -Force | Out-Null
  $previewArguments = @('-m', 'http.server', "$previewPort", '--bind', '127.0.0.1', '--directory', ('"' + $previewDist + '"'))
  Start-Process -FilePath $previewPython -ArgumentList $previewArguments -WindowStyle Hidden -RedirectStandardOutput (Join-Path $previewLogs 'server.log') -RedirectStandardError (Join-Path $previewLogs 'server-error.log')
}
if (-not (Get-NetTCPConnection -LocalPort 8766 -State Listen -ErrorAction SilentlyContinue)) {
  $previewImportScript = Join-Path $PSScriptRoot 'document-import-server.py'
  Start-Process -FilePath $previewPython -ArgumentList ('"' + $previewImportScript + '"') -WindowStyle Hidden
}
Start-Process $previewUrl
Write-Output $previewUrl
