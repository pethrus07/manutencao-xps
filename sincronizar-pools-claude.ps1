# Sincronizar pools de historico do Claude Code
# -----------------------------------------------------------------------------
# Problema que resolve: o Claude Code guarda o historico de sessoes e a memory/
# em um diretorio por WORKSPACE, dentro de %USERPROFILE%\.claude\projects\.
# Abrir outra pasta no VS Code = outro pool = lista de chats vazia e memory/
# desatualizada. Ja aconteceu 4 vezes (ultima: 18/09/2026).
#
# Solucao adotada em 18/09/2026: existe UM pool fisico (o canonico) e todos os
# outros nomes de pool sao junctions NTFS apontando para ele. Assim, qualquer
# pasta aberta no VS Code enxerga o mesmo historico e a mesma memory/.
#
# Este script:
#   1. converte em junction qualquer pool REAL que tenha aparecido depois
#      (consolidando antes o conteudo dele no canonico, sem sobrescrever o que
#      for mais novo);
#   2. pre-cria a junction das pastas de ~\Projetos que ainda nao tem uma.
#
# Uso:   pwsh -File sincronizar-pools-claude.ps1  [-WhatIf]
# Nao precisa de administrador (junction != symlink).

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$PoolRoot = "$env:USERPROFILE\.claude\projects",
    [string]$Canonico = "$env:USERPROFILE\.claude\projects\C--Users-olive",
    [string]$RaizProjetos = "$env:USERPROFILE\Projetos"
)

$ErrorActionPreference = 'Stop'

function Get-SlugDePool {
    param([string]$Caminho)
    # O Claude Code troca todo caractere nao alfanumerico por hifen:
    # C:\Users\olive\Projetos\atas  ->  C--Users-olive-Projetos-atas
    return ($Caminho -replace '[^a-zA-Z0-9]', '-')
}

if (-not (Test-Path $Canonico)) { throw "Pool canonico nao encontrado: $Canonico" }
$nomeCanonico = Split-Path $Canonico -Leaf

Write-Host "Pool canonico: $Canonico"
Write-Host ""

# --- 1. pools reais que apareceram depois -----------------------------------
$backup = Join-Path (Split-Path $PoolRoot -Parent) ("_pool-backup-" + (Get-Date -Format 'yyyyMMdd'))
$convertidos = 0

foreach ($dir in (Get-ChildItem $PoolRoot -Directory -Force)) {
    if ($dir.Name -eq $nomeCanonico) { continue }
    if ($dir.LinkType) { continue }   # ja e junction

    Write-Host "Pool real encontrado: $($dir.Name)"
    if ($PSCmdlet.ShouldProcess($dir.FullName, "consolidar no canonico e virar junction")) {
        # /XO = nao sobrescreve arquivo mais novo no destino (merge seguro)
        robocopy $dir.FullName $Canonico /E /XO /NFL /NDL /NP /NJH /NJS | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy falhou em $($dir.Name): $LASTEXITCODE" }

        New-Item -ItemType Directory -Force -Path $backup | Out-Null
        Move-Item -Path $dir.FullName -Destination (Join-Path $backup $dir.Name)
        New-Item -ItemType Junction -Path $dir.FullName -Target $Canonico | Out-Null
        Write-Host "  consolidado, arquivado em $backup e substituido por junction"
        $convertidos++
    }
}

# --- 2. pastas de projeto ainda sem junction --------------------------------
$alvos = @($RaizProjetos, "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Documents")
$alvos += (Get-ChildItem $RaizProjetos -Directory -ErrorAction SilentlyContinue).FullName
# guarda-chuvas: as subpastas tambem sao abertas como workspace, mas so as que
# sao projeto de verdade (repo git, ou disciplina da faculdade). Sem esse filtro
# entram pastas de build e de assets (out, lib, __pycache__, img...) que ninguem
# abre como workspace.
foreach ($u in @('faculdade', 'fabrica-de-conteudo', 'pdq-cheesebites', 'seguranca-frota-wp')) {
    $p = Join-Path $RaizProjetos $u
    if (-not (Test-Path $p)) { continue }
    foreach ($sub in (Get-ChildItem $p -Directory -ErrorAction SilentlyContinue)) {
        if ($sub.Name -like '_*' -or $sub.Name -like '.*') { continue }
        if ($u -eq 'faculdade' -or (Test-Path (Join-Path $sub.FullName '.git'))) { $alvos += $sub.FullName }
    }
}

$criadas = 0
foreach ($a in ($alvos | Sort-Object -Unique)) {
    $dest = Join-Path $PoolRoot (Get-SlugDePool $a)
    if (Test-Path $dest) { continue }
    if ($PSCmdlet.ShouldProcess($dest, "criar junction para $a")) {
        New-Item -ItemType Junction -Path $dest -Target $Canonico | Out-Null
        Write-Host "junction criada: $(Split-Path $dest -Leaf)"
        $criadas++
    }
}

$total = Get-ChildItem $PoolRoot -Force
Write-Host ""
Write-Host "pools reais convertidos: $convertidos | junctions novas: $criadas"
Write-Host ("total: {0} entradas, {1} junctions, {2} pasta(s) real(is)" -f $total.Count,
    ($total | Where-Object LinkType).Count, ($total | Where-Object { -not $_.LinkType }).Count)
