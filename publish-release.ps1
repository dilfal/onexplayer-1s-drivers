<#
.SYNOPSIS
    Crea il repository GitHub e pubblica la Release v1.0.0 con i 12 archivi driver .zip.
.DESCRIPTION
    Usa GitHub CLI (gh). Il repository deve essere pubblico affinche `irm ... | iex`
    possa scaricare lo script e gli asset senza token.
#>

[CmdletBinding()]
param(
    [string]$RepoName = "dilfal/onexplayer-1s-drivers",
    [string]$ReleaseTag = "v1.0.0",
    [string]$DriversSourceDir = "C:\Users\df\Dev\Scripts\bazzite-handheld-setup\OneDrive_2026-11-13\Drivers (1S)"
)

$ErrorActionPreference = 'Stop'

$RequiredZips = @(
    "chipset-10.1.18460.8229-public-mup.zip",
    "serialio_30.100.2013.5_pv_tgl-lp_20h1.zip",
    "intel_(r)_csme_15.0.1.1345v4.2_b0_consumer.zip",
    "intel(r)gna_pvcandidate_02.00.00.1010.zip",
    "intel(r)_dtt_8.7.10400.15556.zip",
    "igfx_win10_100.9616.zip",
    "Audio_2015.6.18_6.0.1.7541.zip",
    "wifi-phwfw01690_21.110.1.1_g.zip",
    "bt-phbtw12144_21.110.0.3g.zip",
    "tbt_dch_sw_rev75.zip",
    "9.Cardreader.zip",
    "boschaccelerometer.zip"
)

Set-Location $PSScriptRoot

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) non trovato nel PATH."
}

Write-Host "Verifica autenticazione GitHub CLI..." -ForegroundColor Cyan
gh auth status

foreach ($z in $RequiredZips) {
    $full = Join-Path $DriversSourceDir $z
    if (-not (Test-Path -LiteralPath $full)) {
        throw "Archivio driver mancante: $full"
    }
}

if (-not (Test-Path (Join-Path $PSScriptRoot ".git"))) {
    Write-Host "Inizializzazione repository Git..." -ForegroundColor Cyan
    git init -b main
    git add .gitignore Avvia.cmd oxp1s.ps1 publish-release.ps1 README.md
    git commit -m "Initial commit: OneXPlayer 1S Driver Utility (Win11 Pro)"
}

$repoExists = $false
try {
    gh repo view $RepoName | Out-Null
    $repoExists = $true
} catch {
    $repoExists = $false
}

if (-not $repoExists) {
    Write-Host "Creazione repository pubblico $RepoName su GitHub..." -ForegroundColor Cyan
    gh repo create $RepoName --public --source . --remote origin --push
} else {
    Write-Host "Repository $RepoName gia esistente. Push su origin/main..." -ForegroundColor Cyan
    git push -u origin main
}

$zipPaths = $RequiredZips | ForEach-Object { Join-Path $DriversSourceDir $_ }

$releaseExists = $false
try {
    gh release view $ReleaseTag --repo $RepoName | Out-Null
    $releaseExists = $true
} catch {
    $releaseExists = $false
}

if (-not $releaseExists) {
    Write-Host "Creazione Release $ReleaseTag e upload dei 12 pacchetti driver (~1,34 GB)..." -ForegroundColor Green
    gh release create $ReleaseTag @zipPaths `
        --repo $RepoName `
        --title "OneXPlayer 1S Drivers ($ReleaseTag)" `
        --notes "Pacchetti driver ufficiali per OneXPlayer 1S (Windows 11 Pro) usati da oxp1s.ps1."
} else {
    Write-Host "Release $ReleaseTag gia presente. Upload/aggiornamento asset..." -ForegroundColor Green
    gh release upload $ReleaseTag @zipPaths --repo $RepoName --clobber
}

Write-Host ""
Write-Host "Pubblicazione completata!" -ForegroundColor Green
Write-Host "Comando di avvio su Windows 11:" -ForegroundColor Yellow
Write-Host "  irm https://raw.githubusercontent.com/$RepoName/main/oxp1s.ps1 | iex"
