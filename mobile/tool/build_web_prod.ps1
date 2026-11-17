<#
.SYNOPSIS
  Release build of the Zelora web app, ready to upload to Vercel.

.DESCRIPTION
  Runs `flutter build web --release` with the API address baked in, then copies vercel.json (SPA rewrite and cache
  headers) next to index.html in build\web. Release mode already minifies the code and tree-shakes unused icons.
  With -Deploy it also uploads build\web to Vercel (needs `npm i -g vercel` and `vercel login`, plus the project ids
  in $env:VERCEL_ORG_ID and $env:VERCEL_PROJECT_ID, see docs/DEPLOYMENT.md step D).

.PARAMETER ApiBaseUrl
  Public address of the backend, for example https://zelora-api.example.com  (no /api/v1 at the end).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\tool\build_web_prod.ps1 -ApiBaseUrl https://zelora-api.example.com

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\tool\build_web_prod.ps1 -ApiBaseUrl https://zelora-api.example.com -Deploy
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
  [switch]$Deploy
)

$ErrorActionPreference = 'Stop'
$mobile = Split-Path -Parent $PSScriptRoot
Set-Location $mobile

# the app trims these too, but a clean value keeps the build log readable
$api = $ApiBaseUrl.Trim().TrimEnd('/')
if ($api -match '/api/v1$') { $api = $api.Substring(0, $api.Length - '/api/v1'.Length) }
if ($api -notmatch '^https?://[^/\s]+$') {
  throw "ApiBaseUrl must look like https://your-backend.example.com (got '$ApiBaseUrl')."
}
if ($api -match '^http://' -and $api -notmatch '^http://(localhost|127\.0\.0\.1)(:\d+)?$') {
  Write-Warning 'The API address is plain http: browsers block it from an https page (mixed content). Use an https address.'
}

Write-Host "Building Zelora web (release) for API $api ..." -ForegroundColor Cyan
flutter build web --release "--dart-define=API_BASE_URL=$api"
if ($LASTEXITCODE -ne 0) { throw "flutter build web failed (exit code $LASTEXITCODE)." }

$out = Join-Path $mobile 'build\web'
Copy-Item -Path (Join-Path $mobile 'vercel.json') -Destination (Join-Path $out 'vercel.json') -Force
$sizeMb = [math]::Round(((Get-ChildItem $out -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB, 1)
Write-Host "Done: $out ($sizeMb MB, vercel.json copied)." -ForegroundColor Green

if (-not $Deploy) {
  Write-Host 'Next: upload build\web to Vercel, see docs/DEPLOYMENT.md step D (or run this script again with -Deploy).'
  return
}

# -Deploy: the Vercel project is identified by two ids, taken from the environment or from a .vercel\project.json
if (-not ($env:VERCEL_ORG_ID -and $env:VERCEL_PROJECT_ID)) {
  $link = Join-Path $mobile '.vercel\project.json'
  if (-not (Test-Path $link)) {
    throw 'Set $env:VERCEL_ORG_ID and $env:VERCEL_PROJECT_ID first (docs/DEPLOYMENT.md, step D), then run this script again.'
  }
  $project = Get-Content $link -Raw | ConvertFrom-Json
  $env:VERCEL_ORG_ID = $project.orgId
  $env:VERCEL_PROJECT_ID = $project.projectId
}
$vercel = if ($env:OS -eq 'Windows_NT') { 'vercel.cmd' } else { 'vercel' }
Write-Host 'Uploading build\web to Vercel (production)...' -ForegroundColor Cyan
& $vercel deploy $out --prod --yes
if ($LASTEXITCODE -ne 0) { throw "vercel deploy failed (exit code $LASTEXITCODE)." }
