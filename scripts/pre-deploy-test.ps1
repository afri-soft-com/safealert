# SafeAlert — suite de tests pré-déploiement (local, sans deploy)
# Usage : .\scripts\pre-deploy-test.ps1
# Option : -SkipApiSmoke pour ignorer le test API contre Neon

param(
    [switch]$SkipApiSmoke,
    [int]$ApiPort = 3099
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Failed = $false

function Step($Name, [scriptblock]$Action) {
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    try {
        & $Action
        Write-Host "OK: $Name" -ForegroundColor Green
    } catch {
        Write-Host "FAIL: $Name — $($_.Exception.Message)" -ForegroundColor Red
        $script:Failed = $true
    }
}

Step "Backend unit tests" {
    Push-Location (Join-Path $Root "backend")
    npm test | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "npm test exited $LASTEXITCODE" }
    Pop-Location
}

Step "Frontend unit tests" {
    Push-Location (Join-Path $Root "frontend")
    flutter test | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "flutter test exited $LASTEXITCODE" }
    Pop-Location
}

Step "Flutter analyze" {
    Push-Location (Join-Path $Root "frontend")
    flutter analyze | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "flutter analyze exited $LASTEXITCODE" }
    Pop-Location
}

Step "npm audit (report only)" {
    Push-Location (Join-Path $Root "backend")
    npm audit 2>&1 | Out-Host
    Pop-Location
}

Step "Docker Compose validate (neon)" {
    Push-Location $Root
    docker compose -f docker-compose.neon.yml config 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "docker compose config exited $LASTEXITCODE" }
    Pop-Location
}

Step "Docker build smoke test" {
    Push-Location (Join-Path $Root "backend")
    docker build -t safealert-api:local-test . 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "docker build exited $LASTEXITCODE" }
    Pop-Location
}

if (-not $SkipApiSmoke) {
    Step "API smoke test (Neon)" {
        $envFile = Join-Path $Root "backend\.env"
        if (-not (Test-Path $envFile)) {
            throw "backend\.env manquant — définir DATABASE_URL (URL poolée Neon) avant le smoke test"
        }
        $dbUrl = (Get-Content $envFile | Where-Object { $_ -match '^\s*DATABASE_URL=' } | Select-Object -First 1)
        if (-not $dbUrl -or $dbUrl -match 'localhost|user:password') {
            throw "DATABASE_URL dans backend\.env doit pointer vers Neon (pas localhost)"
        }

        $env:PORT = "$ApiPort"
        if (-not $env:JWT_SECRET -or $env:JWT_SECRET.Length -lt 32) {
            $env:JWT_SECRET = "dev-predeploy-smoke-test-secret-32chars"
        }
        $env:NODE_ENV = "development"

        $server = Start-Process -FilePath "node" -ArgumentList "src/server.js" `
            -WorkingDirectory (Join-Path $Root "backend") -PassThru -WindowStyle Hidden

        try {
            Start-Sleep -Seconds 4
            $health = Invoke-RestMethod -Uri "http://localhost:$ApiPort/health" -TimeoutSec 10
            if ($health.status -ne "ok") { throw "/health status inattendu" }

            $ready = Invoke-RestMethod -Uri "http://localhost:$ApiPort/health/ready" -TimeoutSec 15
            if ($ready.status -ne "ready" -or $ready.db -ne "ok") { throw "/health/ready DB non prête" }

            $incidents = Invoke-RestMethod -Uri "http://localhost:$ApiPort/api/map/incidents" -TimeoutSec 15
            Write-Host "GET /api/map/incidents : $($incidents.Count) incident(s) (auth non requis pour GET)"
        } finally {
            Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
            Get-NetTCPConnection -LocalPort $ApiPort -ErrorAction SilentlyContinue |
                ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
        }
    }
}

Write-Host ""
if ($Failed) {
    Write-Host "Résultat : ÉCHEC — corriger les étapes en rouge avant déploiement." -ForegroundColor Red
    exit 1
}
Write-Host "Résultat : SUCCÈS — prêt pour revue de déploiement." -ForegroundColor Green
exit 0
