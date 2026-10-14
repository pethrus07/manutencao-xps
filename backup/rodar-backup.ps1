# rodar-backup.ps1 — um backup restic para o Cloudflare R2. NÃO precisa de admin.
# A tarefa agendada "Backup XPS (restic)" chama este arquivo todo dia. À mão:
#     pwsh -File .\rodar-backup.ps1            # backup agora
#     pwsh -File .\rodar-backup.ps1 -Status    # últimos snapshots e quando foi o último backup OK
#
# Rotina:
#   - todo dia: restic backup das ORIGENS (_comum.ps1) com excluir.txt e sem arquivo > 200 MB;
#   - domingo:  forget + prune (guarda 7 diários, 4 semanais, 12 mensais);
#   - dia 1:    check lendo 5% dos dados (confere que o que subiu ainda abre).
# Log: %LOCALAPPDATA%\backup-xps\logs\ (fica fora do backup; guarda os últimos 60).
#
# Limite conhecido: sem VSS (exigiria admin), arquivo aberto e travado na hora (ex.: sessão do
# Claude sendo escrita, banco SQLite em uso) pode sair "ilegível" — o restic avisa (rc=3) e o
# resto do backup vale. Vai no backup seguinte.

[CmdletBinding()]
param([switch]$Status)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_comum.ps1"

$pastaLog = Join-Path $env:LOCALAPPDATA 'backup-xps\logs'
New-Item -ItemType Directory -Force -Path $pastaLog | Out-Null
$marcaOk  = Join-Path $env:LOCALAPPDATA 'backup-xps\ultimo-ok.txt'
$restic   = Get-Restic

if ($Status) {
    Set-AmbienteRestic
    try {
        & $restic snapshots --latest 5
        if (Test-Path $marcaOk) { Write-Host "Último backup OK: $(Get-Content $marcaOk)" -ForegroundColor Green }
        else { Write-Host "Nenhum backup OK registrado nesta máquina." -ForegroundColor Yellow }
    } finally { Clear-AmbienteRestic }
    return
}

$log = Join-Path $pastaLog "backup-$(Get-Date -Format 'yyyy-MM-dd-HHmm').txt"
Start-Transcript -Path $log | Out-Null
$falhou = $false
try {
    Set-AmbienteRestic
    $origens = $ORIGENS | Where-Object { Test-Path $_ }
    Write-Host "Origens: $($origens -join ' | ')"

    # trava velha de execução interrompida (só remove trava sem processo vivo)
    & $restic unlock 2>&1 | Out-Host

    & $restic backup @origens `
        --exclude-file "$PSScriptRoot\excluir.txt" `
        --exclude-larger-than 200M `
        --exclude-caches `
        --tag diario
    $rc = $LASTEXITCODE
    switch ($rc) {
        0 { Write-Host "backup OK." -ForegroundColor Green }
        3 { Write-Host "backup OK com avisos: alguns arquivos não puderam ser lidos (abertos/travados). Ver acima." -ForegroundColor Yellow }
        default { $falhou = $true; Write-Host "backup FALHOU (rc=$rc)." -ForegroundColor Red }
    }

    if (-not $falhou) {
        Set-Content -Path $marcaOk -Value (Get-Date -Format 'yyyy-MM-dd HH:mm') -Encoding utf8

        if ((Get-Date).DayOfWeek -eq 'Sunday') {
            Write-Host "Domingo: forget + prune"
            & $restic forget --tag diario --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
            if ($LASTEXITCODE -ne 0) { $falhou = $true; Write-Host "forget/prune FALHOU (rc=$LASTEXITCODE)." -ForegroundColor Red }
        }
        if ((Get-Date).Day -eq 1) {
            Write-Host "Dia 1: check lendo 5% dos dados"
            & $restic check --read-data-subset=5%
            if ($LASTEXITCODE -ne 0) { $falhou = $true; Write-Host "check FALHOU (rc=$LASTEXITCODE)." -ForegroundColor Red }
        }
    }
} catch {
    $falhou = $true
    Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Clear-AmbienteRestic
    Stop-Transcript | Out-Null
    Get-ChildItem $pastaLog -Filter 'backup-*.txt' | Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 60 | Remove-Item -ErrorAction SilentlyContinue
}

if ($falhou) { exit 1 }
exit 0
