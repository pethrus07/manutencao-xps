# 1-limpeza-admin.ps1 — correção da hibernação + limpeza de SISTEMA pelas ferramentas do próprio Windows.
# Precisa de admin (auto-eleva, pede UAC). Não apaga nenhum arquivo seu: usa a Limpeza de Disco (cleanmgr),
# o DISM e o powercfg, que só tocam em caches e componentes substituídos do Windows.
# Rodar: clique direito > Executar com PowerShell, ou:  pwsh -File .\1-limpeza-admin.ps1
# Duração: 10 a 25 minutos (o DISM e o cleanmgr são lentos). Pode continuar usando o PC.

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}
$ErrorActionPreference = 'Continue'
$log = "$PSScriptRoot\log-admin-$(Get-Date -Format 'yyyy-MM-dd-HHmm').txt"
Start-Transcript -Path $log | Out-Null
function Passo($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function GB($b) { [math]::Round($b / 1GB, 2) }
$free0 = (Get-PSDrive C).Free
Write-Host "C: livre no início: $(GB $free0) GB" -ForegroundColor Green

# ───────────── A) HIBERNAÇÃO QUEBRADA (34 'desligamentos inesperados' em 30 dias em 07/09; 37 em 14/10) ─────────────
# Evidência: todo evento Kernel-Power 41 tem SleepInProgress=6, Bugcheck=0, botão=0 e BootAppStatus=0xC00000D4
# (winresume não consegue retomar do hiberfil.sys). Recriar o hiberfil resolve quando ele está corrompido;
# se continuar falhando, a causa é o Intel VMD/RST (disco aparece como RAID) → atualizar BIOS + driver Intel RST,
# ou desligar a hibernação de vez (powercfg /h off) — ganha 12,7 GB e o notebook fica só com o Modern Standby.
Passo "A) Recriando hiberfil.sys e desligando o Fast Startup (usa o mesmo mecanismo e também falha)"
powercfg /h off
powercfg /h on
powercfg /h /type full
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -Type DWord
Write-Host "   hiberfil recriado. TESTE DEPOIS: Iniciar > Desligar > Hibernar (ou 'shutdown /h'); ao ligar, tem que voltar com as janelas abertas."
Write-Host "   Se voltar como boot frio de novo, rode:  powercfg /h off   (e atualize BIOS + Intel RST no site da Dell)." -ForegroundColor Yellow

# ───────────── A2) RELÓGIO (44,9 s atrasado em 14/10; w32time estava DESABILITADO) ─────────────
# Já gerou falso achado de QA ("servidor adiantado"). Liga o serviço, aponta para o NTP.br e ressincroniza.
Passo "A2) Relógio: ligando o serviço de hora e sincronizando com o NTP.br"
Set-Service w32time -StartupType Automatic
Start-Service w32time -ErrorAction SilentlyContinue
w32tm /config /manualpeerlist:"a.ntp.br,0x8 b.ntp.br,0x8 time.windows.com,0x8" /syncfromflags:manual /reliable:no /update
Restart-Service w32time
w32tm /resync /force
w32tm /stripchart /computer:a.ntp.br /samples:2 /dataonly

# ───────────── A3) Serviço "Dell Hardware Support" falha em TODO boot (16 erros em 14 dias) ─────────────
# Vai para Manual (não remove nada; o SupportAssist abre ele se precisar). Remover o SupportAssist é decisão do 2-remocoes-opcionais.ps1.
Passo "A3) Dell Hardware Support: Automático -> Manual"
Set-Service 'Dell Hardware Support' -StartupType Manual -ErrorAction SilentlyContinue

# ───────────── B) Delivery Optimization ─────────────
Passo "B) Cache do Delivery Optimization"
Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue

# ───────────── C) Limpeza de Disco (cleanmgr) nas categorias seguras ─────────────
# Cobre: logs de upgrade (C:\Windows\Panther, 1,4 GB), relatórios de erro, temporários do sistema, cache do Windows Update,
# pacotes de driver antigos, miniaturas. Fica de FORA de propósito: Lixeira, Downloads, arquivos ESD de reset, cache de shaders DirectX.
Passo "C) Limpeza de Disco do Windows"
$cats = 'Active Setup Temp Folders', 'BranchCache', 'Delivery Optimization Files', 'Device Driver Packages', 'Diagnostic Data Viewer database files',
        'Downloaded Program Files', 'Internet Cache Files', 'Old ChkDsk Files', 'Previous Installations', 'RetailDemo Offline Content', 'Setup Log Files',
        'System error memory dump files', 'System error minidump files', 'Temporary Files', 'Temporary Setup Files', 'Thumbnail Cache', 'Update Cleanup',
        'Upgrade Discarded Files', 'User file versions', 'Windows Defender', 'Windows Error Reporting Files', 'Windows Upgrade Log Files'
$vc = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
Get-ChildItem $vc | ForEach-Object { Set-ItemProperty $_.PSPath -Name StateFlags0099 -Value 0 -Type DWord }
foreach ($c in $cats) { if (Test-Path "$vc\$c") { Set-ItemProperty "$vc\$c" -Name StateFlags0099 -Value 2 -Type DWord } }
Start-Process cleanmgr.exe -ArgumentList '/sagerun:99' -Wait

# ───────────── D) WinSxS: componentes substituídos (16 GB hoje) ─────────────
Passo "D) DISM StartComponentCleanup (demora; mantém a possibilidade de desinstalar a última atualização)"
Dism.exe /Online /Cleanup-Image /StartComponentCleanup

# ───────────── E) TRIM do SSD ─────────────
Passo "E) TRIM (Optimize-Volume -ReTrim)"
Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue

# ───────────── F) Atualizações seguras via winget ─────────────
# Lista revista em 14/10/2026. Ficam de fora de propósito: PowerShell 7.6 (troca de linha; fazer à parte, com o VS Code fechado —
# a 7.4 sai de suporte em nov/2026), Claude Desktop, Outlook e MongoDB (candidatos a remoção, decisão pendente).
# Docker entra agora: o Docker Desktop não está rodando (não sobe no boot).
Passo "F) winget: atualizações de apps em uso"
$ids = 'AgileBits.1Password', 'AgileBits.1Password.CLI', 'GitHub.cli', 'Git.Git', '7zip.7zip', 'Microsoft.PowerToys',
       'OpenJS.NodeJS.LTS', 'Python.Python.3.14', 'Python.Launcher', 'Docker.DockerDesktop', 'REALiX.HWiNFO',
       'Microsoft.VCRedist.2013.x64', 'Microsoft.VCRedist.2013.x86', 'Microsoft.VCRedist.2015+.x64', 'Microsoft.VCRedist.2015+.x86',
       'Nvidia.PhysX', 'errata-ai.Vale', 'ClassicDIY.ModbusTool', 'EpicGames.EpicGamesLauncher', 'Blizzard.BattleNet'
foreach ($i in $ids) { Write-Host "   -> $i"; winget upgrade --id $i --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Select-Object -Last 1 }

# ───────────── G) Drivers Dell (Intel RST/VMD de 2022 — suspeito da hibernação —, Intel DTT de 2021, Thunderbolt de 2022) ─────────────
# Só DRIVERS: o BIOS 1.48 já está na fila do Windows Update e entra no próximo reinício. Sem reiniciar aqui.
Passo "G) Dell Command Update: drivers"
$dcu = 'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe'
if (Test-Path $dcu) {
    & $dcu /applyUpdates -updateType=driver -reboot=disable -silent "-outputLog=$PSScriptRoot\log-dcu-$(Get-Date -Format 'yyyy-MM-dd-HHmm').log"
    Write-Host "   dcu-cli saiu com código $LASTEXITCODE (0 = aplicou; 1 = precisa reiniciar; 500 = nada a atualizar; outro = ver log-dcu)"
} else { Write-Host "   dcu-cli não encontrado" -ForegroundColor Yellow }

# ───────────── Resumo ─────────────
$free1 = (Get-PSDrive C).Free
Passo "RESUMO"
Write-Host "C: livre: $(GB $free0) GB -> $(GB $free1) GB  (liberado $(GB ($free1 - $free0)) GB)" -ForegroundColor Green
Write-Host "hiberfil.sys agora: $(GB (Get-Item C:\hiberfil.sys -Force -ErrorAction SilentlyContinue).Length) GB | Fast Startup: desligado"
Write-Host "Hora: $(w32tm /query /status | Select-String 'Source|Fonte')"
Write-Host "Falta manual (Explorer): apagar a pasta C:\Drivers (1,2 GB de pacotes de driver de fábrica, 2021)."
Write-Host "AGORA REINICIE o notebook: há atualizações do Windows + BIOS 1.48 + drivers esperando o reinício." -ForegroundColor Yellow
Write-Host "Log em: $log"
Stop-Transcript | Out-Null
Read-Host "Enter para fechar"
