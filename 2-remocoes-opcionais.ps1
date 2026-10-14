# 2-remocoes-opcionais.ps1 — remoções que são DECISÃO SUA. Pergunta item a item (S/N), nada roda sem resposta.
# Rodar: clique direito > Executar com PowerShell, ou:  pwsh -File .\2-remocoes-opcionais.ps1
# Auto-eleva (pede UAC) porque a maioria dos desinstaladores exige admin.

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}
$ErrorActionPreference = 'Continue'
$log = "$PSScriptRoot\log-remocoes-$(Get-Date -Format 'yyyy-MM-dd-HHmm').txt"
Start-Transcript -Path $log | Out-Null

function Pergunta($titulo, $detalhe) {
    Write-Host ""
    Write-Host "== $titulo" -ForegroundColor Cyan
    Write-Host "   $detalhe" -ForegroundColor DarkGray
    $r = Read-Host "   Remover? (s/N)"
    return ($r -match '^[sSyY]')
}
function Tam($p) { if (Test-Path -LiteralPath $p) { [math]::Round(((Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1GB, 2) } else { 0 } }
function Appx($nome) { Get-AppxPackage -Name $nome -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue; Write-Host "   removido app $nome" }
function WingetUninstall($id) { winget uninstall --id $id --silent --accept-source-agreements 2>&1 | Select-Object -Last 2 }

$free0 = (Get-PSDrive C).Free
Write-Host "C: livre agora: $([math]::Round($free0/1GB,1)) GB" -ForegroundColor Green

# ─────────────────────────── DELL (bloatware de fábrica) ───────────────────────────
if (Pergunta "Dell SupportAssist (3.10.2, de 2021) + Remediation + OS Recovery plugin" "O serviço 'Dell Hardware Support' FALHA em todo boot (23 erros em 14 dias). Driver continua pelo Dell Command Update, que fica.") {
    Appx 'DellInc.DellSupportAssistforPCs'
    Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
        Where-Object { $_.DisplayName -match '^Dell SupportAssist( Remediation| OS Recovery Plugin.*)?$' } |
        ForEach-Object {
            Write-Host "   desinstalando $($_.DisplayName)..."
            if ($_.UninstallString -match 'msiexec') { $code = [regex]::Match($_.UninstallString, '\{[0-9A-F-]+\}').Value; Start-Process msiexec -ArgumentList "/x $code /qn /norestart" -Wait }
            else { $exe = ($_.UninstallString -replace '"', '') -replace '\s+/.*$', ''; $args = if ($_.UninstallString -match '\s(/.*)$') { $Matches[1] } else { '' }; Start-Process $exe -ArgumentList "$args /S /quiet /silent" -Wait -ErrorAction SilentlyContinue }
        }
}
if (Pergunta "Dell Digital Delivery Services (serviço Win32)" "Só serve para entregar software pré-instalado de fábrica. O app de loja já foi removido; este é o serviço que roda em Automático.") {
    WingetUninstall 'Dell.DigitalDelivery'
    Get-ItemProperty 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' |
        Where-Object DisplayName -eq 'Dell Digital Delivery Services' | ForEach-Object { $c = [regex]::Match($_.UninstallString, '\{[0-9A-F-]+\}').Value; if ($c) { Start-Process msiexec -ArgumentList "/x $c /qn /norestart" -Wait } }
}
if (Pergunta "Dell Mobile Connect Driver (Screenovate)" "Serviço descontinuado pela Dell. O app de loja já foi removido; sobrou o driver.") {
    Get-ItemProperty 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' |
        Where-Object DisplayName -eq 'Dell Mobile Connect Driver' | ForEach-Object { $c = [regex]::Match($_.UninstallString, '\{[0-9A-F-]+\}').Value; if ($c) { Start-Process msiexec -ArgumentList "/x $c /qn /norestart" -Wait } }
}
if (Pergunta "MyDell (app de loja)" "Hub da Dell. Se você usa o Dell Power Manager pelo app dele (modo térmico Cool/Quiet), NÃO precisa do MyDell.") { Appx 'DellInc.MyDell' }

# ─────────────────────────── REDE / ÁUDIO ───────────────────────────
if (Pergunta "Killer Control Center (app de loja)" "Só o painel de 'priorização de rede' (processo Killer ~170 MB em RAM). O DRIVER Wi-Fi fica intacto.") { Appx 'RivetNetworks.KillerControlCenter' }
if (Pergunta "Dolby Access + Dolby Vision Access" "Apps de configuração Dolby Atmos para fones; o áudio do XPS é Waves MaxxAudio. Remova só se nunca abriu.") { Appx 'DolbyLaboratories.DolbyAccess'; Appx 'DolbyLaboratories.DolbyVisionAccess' }

# ─────────────────────────── MICROSOFT (apps de loja) ───────────────────────────
$msApps = [ordered]@{
    'Microsoft.Copilot'              = 'Copilot (app). O botão/atalho some; o Copilot do Edge continua.'
    'MSTeams'                        = 'Microsoft Teams (novo). Você trabalha por ClickUp/WhatsApp; remova se não usa Teams.'
    'Microsoft.YourPhone'            = 'Phone Link (celular). Está RODANDO em segundo plano (~156 MB). Só remova se não conecta o celular.'
    'Clipchamp.Clipchamp'            = 'Clipchamp (editor de vídeo).'
    'Microsoft.Todos'                = 'Microsoft To Do.'
    'Microsoft.WindowsMaps'          = 'Mapas.'
    'Microsoft.ZuneVideo'            = 'Filmes e TV (Media Player de vídeo).'
    'Microsoft.GetHelp'              = 'Obter Ajuda (suporte Microsoft).'
    'Microsoft.MicrosoftOfficeHub'   = 'Microsoft 365 (app-launcher). Você tem o Office instalado; o hub é redundante.'
    'Microsoft.WindowsFeedbackHub'   = 'Hub de Comentários.'
    'MicrosoftCorporationII.QuickAssist' = 'Assistência Rápida (suporte remoto).'
}
foreach ($k in $msApps.Keys) { if (Pergunta $k $msApps[$k]) { Appx $k } }

# ─────────────────────────── DOWNLOADS / JOGOS ───────────────────────────
$rdr = "$env:USERPROFILE\Downloads\jogos\Red Dead Redemption 2 [DODI Repack]"
if (Test-Path $rdr) { if (Pergunta "Instalador do RDR2 em Downloads\jogos ($(Tam $rdr) GB)" "O jogo JÁ está instalado em C:\Program Files (x86)\DODI-Repacks (119 GB). O instalador é redundante. MAIOR GANHO DA MÁQUINA.") { Remove-Item -LiteralPath $rdr -Recurse -Force } }
$sts = "$env:USERPROFILE\Downloads\jogos\Slay.the.Spire.2.v0.109.0"
if (Test-Path $sts) { if (Pergunta "Slay the Spire 2 em Downloads\jogos ($(Tam $sts) GB)" "Jogo portátil rodando de dentro de Downloads. Se ainda joga, responda N.") { Remove-Item -LiteralPath $sts -Recurse -Force } }
Write-Host ""
Write-Host "== Jogos instalados (desinstale pelo próprio launcher, não por script):" -ForegroundColor Cyan
Write-Host "   Steam:     Arena Breakout Infinite 84,6 GB · Guildrun Demo 10,6 GB (é DEMO) · Project Zomboid 9,6 GB"
Write-Host "   Battle.net: Overwatch 71,6 GB · Hearthstone 12 GB (travou 2x em 14 dias)"
Write-Host "   Riot:      LoL 36,4 GB · VALORANT 32 GB · TFT 5 GB"
Write-Host "   Epic:      8,9 GB (Fortnite instalado hoje)"

# ─────────────────────────── OUTROS PROGRAMAS ───────────────────────────
if (Pergunta "uTorrent Web (654 MB em AppData)" "Cliente de torrent com WebView2. Remova se não usa.") { WingetUninstall 'BitTorrent.uTorrent.Web'; Remove-Item "$env:APPDATA\uTorrent Web" -Recurse -Force -ErrorAction SilentlyContinue }
if (Pergunta "Cache de shaders NVIDIA (DXCache 2,7 GB + GLCache 0,15 GB)" "Regenera sozinho, mas o 1º carregamento de cada jogo fica mais lento (stutter) até recompilar.") { Remove-Item "$env:LOCALAPPDATA\NVIDIA\DXCache\*", "$env:LOCALAPPDATA\NVIDIA\GLCache\*" -Recurse -Force -ErrorAction SilentlyContinue }
if (Pergunta "Cache do Opera GX (~1,2 GB: Cache 466 MB + Code Cache 719 MB)" "FECHE o Opera antes de responder S. Não apaga senhas, abas, histórico nem dados de sites (IndexedDB fica).") {
    if (Get-Process opera -ErrorAction SilentlyContinue) { Write-Host "   Opera ainda aberto — pulei." -ForegroundColor Yellow }
    else { Remove-Item "$env:LOCALAPPDATA\Opera Software\Opera GX Stable\Default\Cache", "$env:APPDATA\Opera Software\Opera GX Stable\Default\Code Cache", "$env:APPDATA\Opera Software\Opera GX Stable\Default\GPUCache" -Recurse -Force -ErrorAction SilentlyContinue; Write-Host "   feito" }
}
if (Pergunta "VS Code: WebStorage (615 MB) + agent-host\sdk-cache (279 MB)" "FECHE o VS Code antes. Armazenamento de webviews/extensões antigas (jul-ago); regenera. Não apaga settings, extensões nem histórico do Claude Code (~/.claude).") {
    if (Get-Process Code -ErrorAction SilentlyContinue) { Write-Host "   VS Code ainda aberto — pulei." -ForegroundColor Yellow }
    else { Remove-Item "$env:APPDATA\Code\WebStorage", "$env:APPDATA\Code\agent-host\sdk-cache" -Recurse -Force -ErrorAction SilentlyContinue; Write-Host "   feito" }
}
if (Pergunta "Docker: compactar docker_data.vhdx (5,8 GB no disco)" "Docker precisa estar PARADO. Só devolve espaço livre interno do disco virtual; se as imagens ocupam tudo, o ganho é zero. Antes, com o Docker aberto, rode: docker system prune -a") {
    if (Get-Process 'Docker Desktop', 'com.docker.backend' -ErrorAction SilentlyContinue) { Write-Host "   Docker aberto — pulei." -ForegroundColor Yellow }
    else {
        wsl --shutdown
        $vhd = "$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx"
        $dp = "$env:TEMP\compact-docker.txt"
        "select vdisk file=`"$vhd`"`nattach vdisk readonly`ncompact vdisk`ndetach vdisk`nexit" | Set-Content $dp -Encoding ASCII
        diskpart /s $dp
        Write-Host "   docker_data.vhdx agora: $([math]::Round((Get-Item $vhd).Length/1GB,2)) GB"
    }
}

$free1 = (Get-PSDrive C).Free
Write-Host ""
Write-Host "C: livre: $([math]::Round($free0/1GB,1)) GB -> $([math]::Round($free1/1GB,1)) GB (liberado $([math]::Round(($free1-$free0)/1GB,1)) GB)" -ForegroundColor Green
Write-Host "Log em: $log"
Stop-Transcript | Out-Null
Read-Host "Enter para fechar"
