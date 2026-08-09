# SafeAlert — premier déploiement VPS (PowerShell)
# Usage: .\deploy\deploy.ps1
# Aligné sur deploy.sh : Neon par défaut (COMPOSE_FILE=docker-compose.neon.yml)

$ErrorActionPreference = "Stop"

$ComposeFile = if ($env:COMPOSE_FILE) { $env:COMPOSE_FILE } else { "docker-compose.neon.yml" }
if (Test-Path ".env.production") {
    $composeFromEnv = (Get-Content .env.production | Where-Object { $_ -match "^COMPOSE_FILE=" }) -replace "^COMPOSE_FILE=", ""
    if ($composeFromEnv -and -not $env:COMPOSE_FILE) { $ComposeFile = $composeFromEnv.Trim() }
}

Write-Host "=== SafeAlert — déploiement VPS ===" -ForegroundColor Cyan
Write-Host "    Compose : $ComposeFile"

if (-not (Test-Path ".env.production")) {
    Copy-Item ".env.production.example" ".env.production"
    Write-Host "Copiez .env.production.example vers .env.production et éditez les secrets, puis relancez." -ForegroundColor Yellow
    exit 1
}

# Charger variables utiles depuis .env.production
Get-Content .env.production | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    $parts = $_ -split '=', 2
    if ($parts.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($parts[0])) {
        $name = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if (-not (Test-Path "Env:$name")) {
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

$ComposeArgs = @("compose", "-f", $ComposeFile, "--env-file", ".env.production")

if ($ComposeFile -eq "docker-compose.neon.yml") {
    if (-not $env:DATABASE_URL) {
        Write-Host "DATABASE_URL requis pour docker-compose.neon.yml (Neon)." -ForegroundColor Red
        exit 1
    }
    Write-Host "→ Mode Neon : PostgreSQL externe, Redis + API sur ce VPS"
    Write-Host "→ Pull image GHCR..."
    docker @ComposeArgs pull api 2>$null
    Write-Host "→ Démarrage Redis + API..."
    docker @ComposeArgs up -d redis api
} else {
    Write-Host "→ Build / démarrage PostgreSQL + API..."
    docker @ComposeArgs pull api 2>$null
    docker @ComposeArgs build api
    docker @ComposeArgs up -d db api
}

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
    Write-Host "Timeout — vérifiez : docker compose -f $ComposeFile logs api" -ForegroundColor Red
    exit 1
}

Write-Host "→ Seed initial..."
docker @ComposeArgs --profile init run --rm seed
if ($LASTEXITCODE -ne 0) {
    Write-Host "Seed ignoré ou déjà appliqué." -ForegroundColor Yellow
}

$domain = $env:DOMAIN
if ($domain -and $domain -ne "localhost") {
    Write-Host "→ Proxy Caddy..."
    docker @ComposeArgs --profile proxy up -d
}

Write-Host "`n✅ Déploiement terminé." -ForegroundColor Green
Write-Host "Health : http://127.0.0.1:$port/health"
if ($domain -and $domain -ne "localhost") {
    Write-Host "Public : https://$domain/health"
}
Write-Host "`nProchaines étapes :"
Write-Host "  1. Configurer SMS (Twilio / Africa's Talking) et FCM"
Write-Host "  2. flutter build apk --release --dart-define=API_BASE_URL=https://$($domain)/api"
