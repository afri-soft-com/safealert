# SafeAlert — premier déploiement VPS (PowerShell)
# Usage: .\deploy\deploy.ps1

$ErrorActionPreference = "Stop"
$DeployPath = if ($env:DEPLOY_PATH) { $env:DEPLOY_PATH } else { "/opt/safealert" }

Write-Host "=== SafeAlert — déploiement VPS ===" -ForegroundColor Cyan

if (-not (Test-Path ".env.production")) {
    Copy-Item ".env.production.example" ".env.production"
    Write-Host "Copiez .env.production.example vers .env.production et éditez les secrets, puis relancez." -ForegroundColor Yellow
    exit 1
}

Write-Host "→ Build et démarrage Docker Compose..."
docker compose --env-file .env.production up -d db api

Write-Host "→ Attente readiness API..."
$port = if ($env:PORT) { $env:PORT } else { "3000" }
$ready = $false
for ($i = 1; $i -le 30; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port/health/ready" -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
    Start-Sleep -Seconds 2
}
if (-not $ready) {
    Write-Host "Timeout — vérifiez : docker compose logs api" -ForegroundColor Red
    exit 1
}

Write-Host "→ Seed initial..."
docker compose --env-file .env.production --profile init run --rm seed

$domain = (Get-Content .env.production | Where-Object { $_ -match "^DOMAIN=" }) -replace "DOMAIN=", ""
if ($domain -and $domain -ne "localhost") {
    Write-Host "→ Proxy Caddy..."
    docker compose --env-file .env.production --profile proxy up -d
}

Write-Host "`n✅ Déploiement terminé." -ForegroundColor Green
Write-Host "Health : http://127.0.0.1:$port/health"
