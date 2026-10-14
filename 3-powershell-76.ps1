# 3-powershell-76.ps1 — atualiza o PowerShell 7.4 (suporte acaba em 10/11/2026) para o 7.6 LTS.
# Precisa de admin (auto-eleva, pede UAC). Roda no Windows PowerShell 5.1 de propósito: o pwsh 7
# não pode estar aberto enquanto o instalador troca os arquivos dele.
#
# ANTES: feche o VS Code e todas as janelas/abas do PowerShell 7 (pwsh). Pare containers do Docker
# se estiver usando. O script confere e avisa.
# Rodar: clique direito > Executar com PowerShell, ou (do Prompt/Windows PowerShell):
#     powershell -ExecutionPolicy Bypass -File .\3-powershell-76.ps1
# Duração: 2 a 5 minutos.
#
# Por que MSI ("wix") e não o pacote padrão do winget (MSIX): o 7.4 desta máquina foi instalado por
# MSI em C:\Program Files\PowerShell\7. O MSI do 7.6 atualiza no mesmo lugar (mesmo caminho do
# pwsh.exe, que o VS Code, as tarefas agendadas e os scripts usam). O MSIX instalaria ao lado e
# deixaria o 7.4 velho no PATH. O winget não reconhece o 7.4 instalado (winget list não acha),
# por isso o `upgrade` pode responder "nenhum pacote instalado" e o script cai no `install`.

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}
$ErrorActionPreference = 'Continue'
$log = "$PSScriptRoot\log-ps76-$(Get-Date -Format 'yyyy-MM-dd-HHmm').txt"
Start-Transcript -Path $log | Out-Null
function Passo($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
$pwshExe = "$env:ProgramFiles\PowerShell\7\pwsh.exe"

function Versao-Pwsh {
    if (-not (Test-Path $pwshExe)) { return $null }
    return (& $pwshExe -NoProfile -NoLogo -Command '$PSVersionTable.PSVersion.ToString()') 2>$null
}

Passo "0) Conferindo o que está aberto"
$abertos = Get-Process -Name pwsh, Code -ErrorAction SilentlyContinue
if ($abertos) {
    $abertos | Group-Object Name | ForEach-Object { Write-Host "   aberto: $($_.Name) x$($_.Count)" -ForegroundColor Yellow }
    Write-Host "   Feche o VS Code e as janelas do PowerShell 7 (o Claude Code roda dentro deles) e tecle Enter." -ForegroundColor Yellow
    Read-Host "   Enter para conferir de novo (ou feche esta janela para desistir)" | Out-Null
    $abertos = Get-Process -Name pwsh, Code -ErrorAction SilentlyContinue
    if ($abertos) {
        $r = Read-Host "   Ainda há pwsh/VS Code aberto. O instalador pode pedir reinício. Continuar mesmo assim? [s/N]"
        if ($r -notmatch '^[sS]') { Stop-Transcript | Out-Null; exit 1 }
    }
}

$antes = Versao-Pwsh
Write-Host "   versão atual: $antes ($pwshExe)"
if ($antes -and ([version]$antes -ge [version]'7.6.0')) {
    Write-Host "   Já está no 7.6 ou mais novo. Nada a fazer." -ForegroundColor Green
    Stop-Transcript | Out-Null; Read-Host "Enter para fechar" | Out-Null; exit 0
}

Passo "1) winget upgrade --id Microsoft.PowerShell (MSI, máquina inteira)"
winget upgrade --id Microsoft.PowerShell --exact --installer-type wix --scope machine `
    --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
$depois = Versao-Pwsh
if (-not $depois -or ([version]$depois -lt [version]'7.6.0')) {
    Write-Host "   upgrade não trocou a versão (o winget não reconhece o 7.4 instalado por MSI). Tentando install por cima:" -ForegroundColor Yellow
    winget install --id Microsoft.PowerShell --exact --installer-type wix --scope machine `
        --accept-source-agreements --accept-package-agreements --silent --disable-interactivity --force
}

Passo "2) Conferência pós-instalação"
$depois = Versao-Pwsh
$ok = $depois -and ([version]$depois -ge [version]'7.6.0')
Write-Host "   pwsh.exe: $pwshExe"
Write-Host "   versão: $antes -> $depois" -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
$msi = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object DisplayName -match '^PowerShell 7' | Select-Object DisplayName, DisplayVersion
$msi | ForEach-Object { Write-Host "   instalado: $($_.DisplayName) $($_.DisplayVersion)" }
if (@($msi).Count -gt 1) { Write-Host "   ATENÇÃO: mais de um PowerShell 7 instalado; desinstale o 7.4 em Configurações > Aplicativos." -ForegroundColor Yellow }
$teste = & $pwshExe -NoProfile -NoLogo -Command '1 + 1' 2>&1
Write-Host "   teste (1 + 1): $teste" -ForegroundColor $(if ("$teste" -eq '2') { 'Green' } else { 'Red' })
$noPath = (& where.exe pwsh 2>$null) | Select-Object -First 1
Write-Host "   primeiro pwsh no PATH: $noPath"
$psrl = & $pwshExe -NoProfile -NoLogo -Command '(Get-Module PSReadLine -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()' 2>$null
Write-Host "   PSReadLine: $psrl"

if ($ok) {
    Write-Host ""
    Write-Host "Pronto. Abra o VS Code de novo; o terminal integrado já usa o 7.6 (mesmo caminho)." -ForegroundColor Green
    Write-Host "Confira no terminal novo:  `$PSVersionTable.PSVersion" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Não ficou no 7.6. Veja o log: $log" -ForegroundColor Red
    Write-Host "Alternativa manual: baixe o MSI x64 em github.com/PowerShell/PowerShell/releases (v7.6.x) e instale." -ForegroundColor Red
}
Stop-Transcript | Out-Null
Read-Host "Enter para fechar" | Out-Null
